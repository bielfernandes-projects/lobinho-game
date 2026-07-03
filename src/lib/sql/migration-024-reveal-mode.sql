-- ═══════════════════════════════════════════════════════════════
-- migration-024-reveal-mode.sql
-- APLICAR VIA SUPABASE SQL EDITOR (manual)
--
-- 1. Altera resolve_night para incluir role nos victims
-- 2. Altera resolve_day_vote para incluir role nas victims
-- 3. Altera host_execute_accused para incluir role nas victims
-- 4. Cria RPC get_graveyard_info
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- 1. resolve_night — incluir role em cada victim do JSON
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.resolve_night(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_priest_target_id UUID;
  v_distinct_wolf_targets INT;
  v_wolf_target_id UUID;
  v_wolf_target_name TEXT;
  v_wolf_target_role TEXT;
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_poison_target_role TEXT;
  v_bodyguard_target_id UUID;
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_killed_by_poison BOOLEAN;
  v_victims JSONB;
  v_soulmate_of_wolf UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_soulmate_of_poison UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- PASSO 1: Padre
  SELECT target_id INTO v_priest_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless'
  LIMIT 1;

  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- PASSO 2: Lobisomens
  SELECT COUNT(DISTINCT target_id)
  INTO v_distinct_wolf_targets
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  IF v_distinct_wolf_targets = 1 THEN
    SELECT target_id INTO v_wolf_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
    LIMIT 1;
  ELSE
    v_wolf_target_id := NULL;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  SELECT target_id INTO v_bodyguard_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

  v_is_blessed := false;
  IF v_wolf_target_id IS NOT NULL THEN
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_wolf_target_id;
  END IF;

  v_killed_by_wolves := v_wolf_target_id IS NOT NULL
    AND NOT v_witch_save_exists
    AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
    AND NOT v_is_blessed;

  IF v_wolf_target_id IS NOT NULL AND v_is_blessed THEN
    UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
  END IF;

  IF v_killed_by_wolves THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name, role INTO v_wolf_target_name, v_wolf_target_role FROM players WHERE id = v_wolf_target_id;
  END IF;

  -- PASSO 3: Bruxa — veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  v_killed_by_poison := false;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_poison_target_id;

    v_killed_by_poison := (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_poison_target_id)
      AND NOT v_is_blessed;

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    END IF;

    IF v_killed_by_poison THEN
      UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
      SELECT name, role INTO v_poison_target_name, v_poison_target_role FROM players WHERE id = v_poison_target_id;
    END IF;
  END IF;

  -- PASSO 4: Soulmate deaths
  v_victims := '[]'::JSONB;
  IF v_killed_by_wolves AND v_wolf_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_wolf FROM players WHERE id = v_wolf_target_id;
    IF v_soulmate_of_wolf IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_wolf) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_wolf;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
      v_soulmate_name := NULL;
    END IF;
  END IF;

  IF v_killed_by_poison AND v_poison_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_poison FROM players WHERE id = v_poison_target_id;
    IF v_soulmate_of_poison IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_poison) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_poison;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
    END IF;
  END IF;

  IF v_killed_by_wolves AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem', 'role', v_wolf_target_role);
  END IF;
  IF v_killed_by_poison AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno', 'role', v_poison_target_role);
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'announcement',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 2. resolve_day_vote — incluir role
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.resolve_day_vote(UUID) CASCADE;

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
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a votacao';
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
          'message', 'A vila nao chegou a um consenso. Ninguem foi linchado.'
        )
    WHERE room_id = p_room_id;
  ELSE
    SELECT name, role INTO v_victim_name, v_target_role
    FROM players WHERE id = v_target_id;

    -- PRINCE CHECK
    IF v_target_role = 'prince' THEN
      UPDATE game_state
      SET current_phase = 'day',
          day_step = 'prince_reveal',
          turn_index = v_turn,
          phase_started_at = now(),
          last_event = jsonb_build_object(
            'type', 'prince_reveal',
            'victim_id', v_target_id,
            'victim_name', v_victim_name,
            'victim_role', v_target_role
          ),
          last_vote_result = jsonb_build_object(
            'type', 'prince_reveal',
            'victim_name', v_victim_name,
            'victim_role', v_target_role
          )
      WHERE room_id = p_room_id;

      RETURN jsonb_build_object(
        'success', true,
        'prince_reveal', true,
        'victim_name', v_victim_name
      );
    END IF;

    -- Normal lynching
    UPDATE players SET is_alive = false WHERE id = v_target_id;

    -- Check soulmate death
    SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_target_id;
    IF v_soulmate_id IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_id) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;
    END IF;

    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'lynch_reveal',
        turn_index = v_turn,
        phase_started_at = now(),
        last_event = jsonb_build_object(
          'type', 'vote_result',
          'event_type', 'lynch',
          'victim_id', v_target_id,
          'victim_name', v_victim_name,
          'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name,
          'soulmate_role', v_soulmate_role
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name,
          'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name,
          'soulmate_role', v_soulmate_role
        )
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 3. host_execute_accused — incluir role
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.host_execute_accused(UUID) CASCADE;

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
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode executar esta acao';
  END IF;

  SELECT current_accused_id, turn_index INTO v_accused_id, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_accused_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum acusado para executar';
  END IF;

  SELECT name, role INTO v_accused_name, v_accused_role
  FROM players WHERE id = v_accused_id;

  -- PRINCE CHECK
  IF v_accused_role = 'prince' THEN
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'prince_reveal',
        turn_index = v_turn,
        current_accused_id = NULL,
        last_event = jsonb_build_object(
          'type', 'prince_reveal',
          'victim_id', v_accused_id,
          'victim_name', v_accused_name,
          'victim_role', v_accused_role
        ),
        last_vote_result = jsonb_build_object(
          'type', 'prince_reveal',
          'victim_name', v_accused_name,
          'victim_role', v_accused_role
        )
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object(
      'success', true,
      'prince_reveal', true,
      'victim_name', v_accused_name
    );
  END IF;

  -- Normal execution
  UPDATE players SET is_alive = false WHERE id = v_accused_id;

  -- Check soulmate death
  SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_accused_id;
  IF v_soulmate_id IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_id) = false THEN
    SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'lynch_reveal',
      turn_index = v_turn,
      phase_started_at = now(),
      current_accused_id = NULL,
      last_event = jsonb_build_object(
        'type', 'vote_result',
        'event_type', 'lynch',
        'victim_id', v_accused_id,
        'victim_name', v_accused_name,
        'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name,
        'soulmate_role', v_soulmate_role
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name,
        'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name,
        'soulmate_role', v_soulmate_role
      )
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 4. get_graveyard_info — retorna mortos com role
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_graveyard_info(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object('id', p.id, 'name', p.name, 'role', p.role)
  ) INTO v_result
  FROM players p
  WHERE p.room_id = p_room_id
    AND p.is_alive = false
    AND p.role != 'moderator';

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 5. execute_night_action — fix ON CONFLICT columns
--    A UNIQUE constraint foi alterada de (room_id, turn_index, actor_id)
--    para (room_id, turn_index, actor_id, action_type, target_id)
--    pela migration do Cupido. O ON CONFLICT precisa corresponder.
-- ═══════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.execute_night_action(UUID, TEXT, UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.execute_night_action(p_room_id uuid, p_action_type text, p_target_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_player_id UUID;
  v_role TEXT;
  v_alive BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
  v_result BOOLEAN;
  v_wolves_resolved BOOLEAN;
  v_target_role TEXT;
BEGIN
  SELECT id, role, is_alive,
         COALESCE(has_used_life_potion, false),
         COALESCE(has_used_death_potion, false)
    INTO v_player_id, v_role, v_alive, v_used_life, v_used_death
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos nao podem agir';
  END IF;

  IF (p_action_type = 'werewolf_kill' AND v_role != 'werewolf') OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') OR
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch') OR
     (p_action_type = 'priest_bless' AND v_role != 'priest') OR
     (p_action_type = 'bodyguard_protect' AND v_role != 'bodyguard') OR
     (p_action_type = 'aura_investigate' AND v_role != 'aura_seer') OR
     (p_action_type = 'cult_convert' AND v_role != 'cult_leader')
  THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  SELECT turn_index INTO v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF p_action_type IN ('witch_save', 'witch_poison') THEN
    SELECT COALESCE(wolves_resolved, false) INTO v_wolves_resolved
    FROM game_state WHERE room_id = p_room_id;
    IF NOT v_wolves_resolved THEN
      RAISE EXCEPTION 'Aguarde os lobos decidirem primeiro';
    END IF;
  END IF;

  IF p_action_type = 'witch_save' AND v_used_life THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da vida';
  END IF;

  IF p_action_type = 'witch_poison' AND v_used_death THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da morte';
  END IF;

  IF p_action_type = 'witch_save' THEN
    UPDATE players SET has_used_life_potion = true WHERE id = v_player_id;
  ELSIF p_action_type = 'witch_poison' THEN
    UPDATE players SET has_used_death_potion = true WHERE id = v_player_id;
  ELSIF p_action_type = 'priest_bless' THEN
    UPDATE players SET is_blessed = true WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'bodyguard_protect' THEN
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'aura_investigate' THEN
    SELECT role INTO v_target_role
    FROM players WHERE id = p_target_id;

    v_result := (v_target_role NOT IN ('villager', 'werewolf'));

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

    RETURN jsonb_build_object('has_special_role', v_result);
  ELSIF p_action_type = 'cult_convert' THEN
    UPDATE players SET in_cult = true WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role IN ('werewolf', 'lycan') INTO v_result
    FROM players WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

    RETURN jsonb_build_object('is_werewolf', v_result);
  END IF;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$$;
