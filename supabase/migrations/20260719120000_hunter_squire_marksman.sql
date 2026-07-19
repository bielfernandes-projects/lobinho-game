-- ============================================================
-- Lote 6: Hunter (Caçador), Squire (Escudeiro), Marksman (Atirador)
-- ============================================================

-- 1. Adicionar colunas de Hunter no game_state
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS hunter_pending BOOLEAN DEFAULT FALSE;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS hunter_id UUID DEFAULT NULL;

-- 2. Atualizar constraints de roles
DO $$
BEGIN
  -- players_role_check: adicionar hunter, squire, marksman
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'players_role_check') THEN
    ALTER TABLE players DROP CONSTRAINT players_role_check;
  END IF;
  ALTER TABLE players ADD CONSTRAINT players_role_check CHECK (
    role IN (
      'werewolf', 'seer', 'witch', 'villager', 'mayor', 'prince', 'tanner',
      'lycan', 'priest', 'bodyguard', 'aura_seer', 'wolf_cub', 'lone_wolf',
      'alpha_wolf', 'cupid', 'cult_leader', 'mason', 'pacifist', 'idiot',
      'sorceress', 'moderator', 'hunter', 'squire', 'marksman'
    )
  );

  -- night_actions_action_type_check: adicionar hunter_shot
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'night_actions_action_type_check') THEN
    ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  END IF;
  ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check CHECK (
    action_type IN (
      'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
      'witch_skip', 'priest_bless', 'bodyguard_protect', 'aura_investigate',
      'cult_convert', 'alpha_infect', 'cupid_match', 'sorceress_search',
      'mason_recognition', 'hunter_shot'
    )
  );
END $$;

-- 3. RPC: hunter_retaliate — Hunter dá o tiro de vingança
CREATE OR REPLACE FUNCTION public.hunter_retaliate(
  p_room_id UUID,
  p_target_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hunter_id UUID;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
BEGIN
  -- Verificar que existe hunter_pending
  SELECT hunter_id INTO v_hunter_id
  FROM game_state WHERE room_id = p_room_id;

  IF v_hunter_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum Caçador pendente de retaliação';
  END IF;

  -- Verificar que o alvo está vivo
  SELECT name INTO v_target_name FROM players WHERE id = p_target_id AND is_alive = true;
  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou já está morto';
  END IF;

  -- Verificar que o alvo não é o próprio Hunter
  IF p_target_id = v_hunter_id THEN
    RAISE EXCEPTION 'Você não pode atirar em si mesmo';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Matar o alvo
  UPDATE players SET is_alive = false WHERE id = p_target_id;

  -- Registrar a ação no log noturno
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_hunter_id, 'hunter_shot', p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Limpar estado do Hunter
  UPDATE game_state
  SET hunter_pending = false, hunter_id = NULL
  WHERE room_id = p_room_id;

  -- Verificar game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'game_over', v_game_over
  );
END;
$$;

-- 4. RPC: marksman_shoot — Atirador atira durante o dia
CREATE OR REPLACE FUNCTION public.marksman_shoot(
  p_room_id UUID,
  p_target_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_marksman_id UUID;
  v_alive BOOLEAN;
  v_used_power BOOLEAN;
  v_current_phase TEXT;
  v_day_step TEXT;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
BEGIN
  -- Verificar que o jogador é o Marksman e está vivo
  SELECT id, is_alive, COALESCE(has_used_power, false)
  INTO v_marksman_id, v_alive, v_used_power
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_marksman_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos não podem agir';
  END IF;

  IF (SELECT role FROM players WHERE id = v_marksman_id) != 'marksman' THEN
    RAISE EXCEPTION 'Ação inválida para o seu papel';
  END IF;

  IF v_used_power THEN
    RAISE EXCEPTION 'Você já usou seu tiro';
  END IF;

  -- Verificar que estamos no dia e em discussion
  SELECT current_phase, day_step, turn_index
  INTO v_current_phase, v_day_step, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'day' THEN
    RAISE EXCEPTION 'Só pode atirar durante o dia';
  END IF;

  IF v_day_step != 'discussion' THEN
    RAISE EXCEPTION 'Só pode atirar durante a discussão';
  END IF;

  -- Verificar que o alvo está vivo e não é host
  SELECT name INTO v_target_name
  FROM players
  WHERE id = p_target_id AND is_alive = true AND is_host = false;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou não é válido';
  END IF;

  -- Marcar poder como usado
  UPDATE players SET has_used_power = true WHERE id = v_marksman_id;

  -- Matar o alvo
  UPDATE players SET is_alive = false WHERE id = p_target_id;

  -- Verificar game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'game_over', v_game_over
  );
END;
$$;

-- 5. Atualizar resolve_night — Hunter pending + Squire promotion
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_priest_target_id UUID;
  v_frenzy BOOLEAN;
  v_wolf_target_ids UUID[];
  v_wolf_target_id UUID;
  v_wolf_target2_id UUID;
  v_wolf_target_name TEXT;
  v_wolf_target_role TEXT;
  v_wolf_target2_name TEXT;
  v_wolf_target2_role TEXT;
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_poison_target_role TEXT;
  v_bodyguard_target_id UUID;
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_killed_by_poison BOOLEAN;
  v_victims JSONB := '[]'::JSONB;
  v_soulmate_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_alpha_infected_id UUID;
  v_alpha_infected_name TEXT;
  v_target_has_alpha_infect BOOLEAN;
  v_hunter_killed BOOLEAN := false;
  v_hunter_id UUID;
  v_squire_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;
  SELECT COALESCE(wolves_frenzy, false) INTO v_frenzy FROM rooms WHERE id = p_room_id;

  -- PASSO 1: Padre
  SELECT target_id INTO v_priest_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless'
  LIMIT 1;
  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- Collect distinct wolf targets
  SELECT ARRAY_AGG(DISTINCT target_id) INTO v_wolf_target_ids
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';
  v_wolf_target_id := v_wolf_target_ids[1];
  IF v_frenzy AND array_length(v_wolf_target_ids, 1) >= 2 THEN
    v_wolf_target2_id := v_wolf_target_ids[2];
  END IF;

  -- PASSO 2: Lobisomens (target 1)
  IF v_wolf_target_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn
        AND action_type = 'alpha_infect' AND target_id = v_wolf_target_id
    ) INTO v_target_has_alpha_infect;

    IF v_target_has_alpha_infect THEN
      UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
      SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target_id;
      v_alpha_infected_id := v_wolf_target_id;
      UPDATE players SET has_used_power = true
      WHERE room_id = p_room_id AND role = 'alpha_wolf' AND has_used_power = false;
    ELSE
      SELECT EXISTS (
        SELECT 1 FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
      ) INTO v_witch_save_exists;

      SELECT target_id INTO v_bodyguard_target_id
      FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

      v_is_blessed := false;
      SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_wolf_target_id;

      v_killed_by_wolves := NOT v_witch_save_exists
        AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
        AND NOT v_is_blessed;

      IF v_is_blessed THEN
        UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
      END IF;

      IF v_killed_by_wolves THEN
        UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
        SELECT name, role INTO v_wolf_target_name, v_wolf_target_role FROM players WHERE id = v_wolf_target_id;

        -- Verificar se é Hunter
        IF v_wolf_target_role = 'hunter' THEN
          v_hunter_killed := true;
          v_hunter_id := v_wolf_target_id;
        END IF;

        -- Verificar se é Prince → Squire promotion
        IF v_wolf_target_role = 'prince' THEN
          SELECT id INTO v_squire_id FROM players
          WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
          IF v_squire_id IS NOT NULL THEN
            UPDATE players SET role = 'prince' WHERE id = v_squire_id;
          END IF;
        END IF;

        v_victims := v_victims || jsonb_build_object(
          'name', v_wolf_target_name,
          'cause', 'lobisomem',
          'role', v_wolf_target_role
        );
      END IF;
    END IF;
  END IF;

  -- PASSO 2b: Lobisomens (target 2 — frenzy)
  IF v_wolf_target2_id IS NOT NULL AND v_frenzy THEN
    v_is_blessed := false;
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_wolf_target2_id;

    SELECT target_id INTO v_bodyguard_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
    ) INTO v_witch_save_exists;

    v_killed_by_wolves := NOT v_witch_save_exists
      AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target2_id)
      AND NOT v_is_blessed;

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_wolf_target2_id;
    END IF;

    IF v_killed_by_wolves THEN
      UPDATE players SET is_alive = false WHERE id = v_wolf_target2_id;
      SELECT name, role INTO v_wolf_target2_name, v_wolf_target2_role FROM players WHERE id = v_wolf_target2_id;

      IF v_wolf_target2_role = 'hunter' THEN
        v_hunter_killed := true;
        v_hunter_id := v_wolf_target2_id;
      END IF;

      IF v_wolf_target2_role = 'prince' THEN
        SELECT id INTO v_squire_id FROM players
        WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
        IF v_squire_id IS NOT NULL THEN
          UPDATE players SET role = 'prince' WHERE id = v_squire_id;
        END IF;
      END IF;

      v_victims := v_victims || jsonb_build_object(
        'name', v_wolf_target2_name,
        'cause', 'lobisomem',
        'role', v_wolf_target2_role
      );
    END IF;
  END IF;

  -- PASSO 3: Bruxa — veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison'
  LIMIT 1;

  IF v_poison_target_id IS NOT NULL THEN
    v_is_blessed := false;
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_poison_target_id;

    SELECT target_id INTO v_bodyguard_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

    v_killed_by_poison := NOT v_is_blessed
      AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_poison_target_id);

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    END IF;

    IF v_killed_by_poison THEN
      UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
      SELECT name, role INTO v_poison_target_name, v_poison_target_role FROM players WHERE id = v_poison_target_id;

      IF v_poison_target_role = 'hunter' THEN
        v_hunter_killed := true;
        v_hunter_id := v_poison_target_id;
      END IF;

      IF v_poison_target_role = 'prince' THEN
        SELECT id INTO v_squire_id FROM players
        WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
        IF v_squire_id IS NOT NULL THEN
          UPDATE players SET role = 'prince' WHERE id = v_squire_id;
        END IF;
      END IF;

      v_victims := v_victims || jsonb_build_object(
        'name', v_poison_target_name,
        'cause', 'veneno',
        'role', v_poison_target_role
      );
    END IF;
  END IF;

  -- PASSO 4: Soulmate deaths
  FOR i IN 0..jsonb_array_length(v_victims) - 1 LOOP
    DECLARE
      v_victim_id UUID;
      v_victim_name TEXT;
      v_victim_role TEXT;
    BEGIN
      SELECT id INTO v_victim_id
      FROM players WHERE room_id = p_room_id AND name = (v_victims->i->>'name');
      IF v_victim_id IS NOT NULL THEN
        SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_victim_id;
        IF v_soulmate_id IS NOT NULL THEN
          IF (SELECT is_alive FROM players WHERE id = v_soulmate_id) THEN
            UPDATE players SET is_alive = false WHERE id = v_soulmate_id;
            SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;

            IF v_soulmate_role = 'hunter' THEN
              v_hunter_killed := true;
              v_hunter_id := v_soulmate_id;
            END IF;

            IF v_soulmate_role = 'prince' THEN
              SELECT id INTO v_squire_id FROM players
              WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
              IF v_squire_id IS NOT NULL THEN
                UPDATE players SET role = 'prince' WHERE id = v_squire_id;
              END IF;
            END IF;

            v_victims := v_victims || jsonb_build_object(
              'name', v_soulmate_name,
              'cause', 'soulmate',
              'role', v_soulmate_role
            );
          END IF;
        END IF;
      END IF;
    END;
  END LOOP;

  -- Atualizar game_state
  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'announcement',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object(
        'type', 'night_result',
        'victims', v_victims,
        'wolf_votes', (
          SELECT COUNT(*) FROM night_actions
          WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
        )
      ),
      last_vote_result = NULL,
      -- Hunter pending
      hunter_pending = CASE WHEN v_hunter_killed THEN true ELSE false END,
      hunter_id = CASE WHEN v_hunter_killed THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  -- Limpar frenesi
  UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;

  RETURN jsonb_build_object(
    'success', true,
    'victims', v_victims,
    'hunter_pending', v_hunter_killed
  );
END;
$$;

-- 6. Atualizar host_execute_accused — Hunter pending + Squire promotion
CREATE OR REPLACE FUNCTION public.host_execute_accused(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_accused_id UUID;
  v_accused_name TEXT;
  v_accused_role TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_soulmate_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_squire_id UUID;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode executar esta ação';
  END IF;

  SELECT current_accused_id, turn_index INTO v_accused_id, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_accused_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum acusado para executar';
  END IF;

  SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;

  -- PRINCE CHECK
  IF v_accused_role = 'prince' THEN
    UPDATE game_state
    SET current_phase = 'day', day_step = 'prince_reveal',
        turn_index = v_turn, current_accused_id = NULL,
        last_event = jsonb_build_object('type', 'prince_reveal', 'victim_id', v_accused_id, 'victim_name', v_accused_name, 'victim_role', v_accused_role),
        last_vote_result = jsonb_build_object('type', 'prince_reveal', 'victim_name', v_accused_name, 'victim_role', v_accused_role)
    WHERE room_id = p_room_id;
    RETURN jsonb_build_object('success', true, 'prince_reveal', true, 'victim_name', v_accused_name);
  END IF;

  UPDATE players SET is_alive = false WHERE id = v_accused_id;

  -- Squire promotion
  IF v_accused_role = 'prince' THEN
    SELECT id INTO v_squire_id FROM players
    WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
    IF v_squire_id IS NOT NULL THEN
      UPDATE players SET role = 'prince' WHERE id = v_squire_id;
    END IF;
  END IF;

  -- Hunter check
  IF v_accused_role = 'hunter' THEN
    v_hunter_pending := true;
    v_hunter_id := v_accused_id;
  END IF;

  -- Check soulmate
  SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_accused_id;
  IF v_soulmate_id IS NOT NULL THEN
    IF (SELECT is_alive FROM players WHERE id = v_soulmate_id) THEN
      UPDATE players SET is_alive = false WHERE id = v_soulmate_id;
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;

      -- Hunter check on soulmate
      IF v_soulmate_role = 'hunter' THEN
        v_hunter_pending := true;
        v_hunter_id := v_soulmate_id;
      END IF;

      -- Squire check on soulmate
      IF v_soulmate_role = 'prince' THEN
        SELECT id INTO v_squire_id FROM players
        WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
        IF v_squire_id IS NOT NULL THEN
          UPDATE players SET role = 'prince' WHERE id = v_squire_id;
        END IF;
      END IF;
    END IF;
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = CASE WHEN v_hunter_pending THEN 'hunter_reveal' ELSE 'lynch_reveal' END,
      turn_index = v_turn, phase_started_at = now(), current_accused_id = NULL,
      last_event = jsonb_build_object(
        'type', 'vote_result', 'event_type', 'lynch',
        'victim_id', v_accused_id, 'victim_name', v_accused_name,
        'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name, 'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role
      ),
      hunter_pending = v_hunter_pending,
      hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over, 'hunter_pending', v_hunter_pending);
END;
$$;

-- 7. Atualizar resolve_day_vote — Hunter pending + Squire promotion
CREATE OR REPLACE FUNCTION public.resolve_day_vote(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_target_id UUID;
  v_vote_count INT;
  v_tie_count INT;
  v_threshold INT;
  v_alive INT;
  v_victim_name TEXT;
  v_target_role TEXT;
  v_game_over JSONB;
  v_soulmate_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_squire_id UUID;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a votação';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT COUNT(*) INTO v_alive
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role != 'moderator';

  v_threshold := floor(v_alive / 2) + 1;

  SELECT target_id, COUNT(*) AS cnt INTO v_target_id, v_vote_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  ORDER BY cnt DESC
  LIMIT 1;

  SELECT COUNT(*) INTO v_tie_count FROM (
    SELECT target_id FROM votes
    WHERE room_id = p_room_id AND turn_index = v_turn
    GROUP BY target_id
    HAVING COUNT(*) = v_vote_count
  ) AS ties;

  IF v_vote_count < v_threshold OR v_tie_count > 1 THEN
    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        last_event = jsonb_build_object('type', 'vote_result', 'event_type', 'vote_tie'),
        last_vote_result = jsonb_build_object(
          'type', 'vote_tie',
          'message', 'A vila não chegou a um consenso. Ninguém foi linchado.'
        )
    WHERE room_id = p_room_id;
  ELSE
    SELECT name, role INTO v_victim_name, v_target_role FROM players WHERE id = v_target_id;

    -- PRINCE CHECK
    IF v_target_role = 'prince' THEN
      -- Squire promotion
      SELECT id INTO v_squire_id FROM players
      WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
      IF v_squire_id IS NOT NULL THEN
        UPDATE players SET role = 'prince' WHERE id = v_squire_id;
      END IF;

      UPDATE game_state
      SET current_phase = 'day',
          day_step = 'prince_reveal',
          turn_index = v_turn,
          phase_started_at = now(),
          last_event = jsonb_build_object(
            'type', 'prince_reveal', 'victim_id', v_target_id,
            'victim_name', v_victim_name, 'victim_role', v_target_role
          ),
          last_vote_result = jsonb_build_object(
            'type', 'prince_reveal', 'victim_name', v_victim_name, 'victim_role', v_target_role
          )
      WHERE room_id = p_room_id;
      RETURN jsonb_build_object('success', true, 'prince_reveal', true, 'victim_name', v_victim_name);
    END IF;

    UPDATE players SET is_alive = false WHERE id = v_target_id;

    -- Hunter check
    IF v_target_role = 'hunter' THEN
      v_hunter_pending := true;
      v_hunter_id := v_target_id;
    END IF;

    -- Squire promotion (for completeness)
    IF v_target_role = 'prince' THEN
      SELECT id INTO v_squire_id FROM players
      WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
      IF v_squire_id IS NOT NULL THEN
        UPDATE players SET role = 'prince' WHERE id = v_squire_id;
      END IF;
    END IF;

    -- Check soulmate
    SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_target_id;
    IF v_soulmate_id IS NOT NULL THEN
      IF (SELECT is_alive FROM players WHERE id = v_soulmate_id) THEN
        UPDATE players SET is_alive = false WHERE id = v_soulmate_id;
        SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;

        -- Hunter check on soulmate
        IF v_soulmate_role = 'hunter' THEN
          v_hunter_pending := true;
          v_hunter_id := v_soulmate_id;
        END IF;

        -- Squire check on soulmate
        IF v_soulmate_role = 'prince' THEN
          SELECT id INTO v_squire_id FROM players
          WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
          IF v_squire_id IS NOT NULL THEN
            UPDATE players SET role = 'prince' WHERE id = v_squire_id;
          END IF;
        END IF;
      END IF;
    END IF;

    UPDATE game_state
    SET current_phase = 'day',
        day_step = CASE WHEN v_hunter_pending THEN 'hunter_reveal' ELSE 'lynch_reveal' END,
        turn_index = v_turn,
        phase_started_at = now(),
        last_event = jsonb_build_object(
          'type', 'vote_result', 'event_type', 'lynch',
          'victim_id', v_target_id, 'victim_name', v_victim_name,
          'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name, 'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role
        ),
        hunter_pending = v_hunter_pending,
        hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- 8. RPC: advance_after_hunter — avança de hunter_reveal para lynch_reveal
CREATE OR REPLACE FUNCTION public.advance_after_hunter(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode avançar';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  UPDATE game_state
  SET day_step = 'lynch_reveal',
      hunter_pending = false,
      hunter_id = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
