-- Fixes:
-- 1. Cupid log: show both names (insert 2 rows + UNIQUE change)
-- 2. Soulmate death: include soulmate in last_event.victims
-- 3. Lynching modal: add lynch_reveal step instead of jumping to night
-- 4. advance_to_night RPC (reusable after prince_reveal or lynch_reveal)

-- ===== 1. Cupid: insert both targets =====
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_room_id_turn_index_actor_id_key;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_room_turn_actor_type_target_key
  UNIQUE (room_id, turn_index, actor_id, action_type, target_id);

CREATE OR REPLACE FUNCTION public.submit_cupid_match(p_room_id UUID, p_target_a UUID, p_target_b UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_role TEXT;
  v_turn INT;
BEGIN
  SELECT id, role INTO v_player_id, v_role
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF v_role != 'cupid' THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  UPDATE players SET soulmate_id = p_target_b WHERE id = p_target_a;
  UPDATE players SET soulmate_id = p_target_a WHERE id = p_target_b;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, 'cupid_match', p_target_a);

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, 'cupid_match', p_target_b);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ===== 2. resolve_night: include soulmate in victims =====
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
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_bodyguard_target_id UUID;
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_killed_by_poison BOOLEAN;
  v_victims JSONB;
  v_soulmate_of_wolf UUID;
  v_soulmate_name TEXT;
  v_soulmate_of_poison UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 1: Padre — abençoa o alvo (is_blessed = TRUE)
  -- ════════════════════════════════════════════════════════════════
  SELECT target_id INTO v_priest_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless'
  LIMIT 1;

  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 2: Lobisomens — ataque dos lobos
  -- ════════════════════════════════════════════════════════════════
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
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 3: Bruxa — veneno (checa is_blessed do estado PÓS passos 1 e 2)
  -- ════════════════════════════════════════════════════════════════
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
      SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
    END IF;
  END IF;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 4: Check soulmate deaths (trigger already killed soulmates)
  -- ════════════════════════════════════════════════════════════════
  v_victims := '[]'::JSONB;
  IF v_killed_by_wolves AND v_wolf_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_wolf FROM players WHERE id = v_wolf_target_id;
    IF v_soulmate_of_wolf IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_wolf) = false THEN
      SELECT name INTO v_soulmate_name FROM players WHERE id = v_soulmate_of_wolf;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate');
      v_soulmate_name := NULL;
    END IF;
  END IF;

  IF v_killed_by_poison AND v_poison_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_poison FROM players WHERE id = v_poison_target_id;
    IF v_soulmate_of_poison IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_poison) = false THEN
      SELECT name INTO v_soulmate_name FROM players WHERE id = v_soulmate_of_poison;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate');
    END IF;
  END IF;

  IF v_killed_by_wolves AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_killed_by_poison AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno');
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

-- ===== 3. resolve_day_vote: lynch_reveal step instead of night =====
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

    -- PRINCE CHECK: if victim is prince, reveal identity and survive
    IF v_target_role = 'prince' THEN
      UPDATE game_state
      SET current_phase = 'day',
          day_step = 'prince_reveal',
          turn_index = v_turn,
          phase_started_at = now(),
          last_event = jsonb_build_object(
            'type', 'prince_reveal',
            'victim_id', v_target_id,
            'victim_name', v_victim_name
          ),
          last_vote_result = jsonb_build_object(
            'type', 'prince_reveal',
            'victim_name', v_victim_name
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

    -- Check soulmate death (trigger already killed soulmate)
    SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_target_id;
    IF v_soulmate_id IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_id) = false THEN
      SELECT name INTO v_soulmate_name FROM players WHERE id = v_soulmate_id;
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
          'soulmate_name', v_soulmate_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name,
          'soulmate_name', v_soulmate_name
        )
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ===== 4. host_execute_accused: lynch_reveal step instead of night =====
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

  -- PRINCE CHECK: reveal identity and survive
  IF v_accused_role = 'prince' THEN
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'prince_reveal',
        turn_index = v_turn,
        current_accused_id = NULL,
        last_event = jsonb_build_object(
          'type', 'prince_reveal',
          'victim_id', v_accused_id,
          'victim_name', v_accused_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'prince_reveal',
          'victim_name', v_accused_name
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

  -- Check soulmate death (trigger already killed soulmate)
  SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_accused_id;
  IF v_soulmate_id IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_id) = false THEN
    SELECT name INTO v_soulmate_name FROM players WHERE id = v_soulmate_id;
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
        'soulmate_name', v_soulmate_name
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name,
        'soulmate_name', v_soulmate_name
      )
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ===== 5. advance_to_night RPC (replaces advance_after_prince + supports lynch_reveal) =====
DROP FUNCTION IF EXISTS public.advance_after_prince(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.advance_to_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode avancar a fase';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  UPDATE game_state
  SET current_phase = 'night',
      day_step = 'discussion',
      turn_index = v_turn + 1,
      phase_started_at = now(),
      night_step = 'sleeping'
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;
