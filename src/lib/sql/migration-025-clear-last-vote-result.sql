-- ═══════════════════════════════════════════════════════════════
-- clear_last_vote_result.sql
-- APLICAR VIA SUPABASE SQL EDITOR OU `supabase db query --linked`
--
-- last_vote_result nunca era limpo ao trocar de fase, fazendo
-- com que o modal de linchamento aparecesse em votações seguintes.
-- 
-- Corrige 4 funções:
--   1. resolve_night — ao sair da noite para o dia
--   2. advance_to_night — ao sair do lynch_reveal para a noite
--   3. host_day_to_night — atalho direto para a noite
--   4. host_absolve_accused — ao inocentar o acusado
-- ═══════════════════════════════════════════════════════════════

-- ===== 1. resolve_night =====
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
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect'
  LIMIT 1;

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

  -- PASSO 3: Bruxa (veneno)
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison'
  LIMIT 1;

  IF v_poison_target_id IS NOT NULL THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name, role INTO v_poison_target_name, v_poison_target_role FROM players WHERE id = v_poison_target_id;
    v_killed_by_poison := true;
  ELSE
    v_killed_by_poison := false;
  END IF;

  -- Soulmates
  v_victims := '[]'::JSONB;

  IF v_killed_by_wolves AND v_wolf_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_wolf FROM players WHERE id = v_wolf_target_id;
    IF v_soulmate_of_wolf IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_wolf) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_wolf;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
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
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims),
      last_vote_result = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;

-- ===== 2. advance_to_night =====
DROP FUNCTION IF EXISTS public.advance_to_night(UUID) CASCADE;

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
      night_step = 'sleeping',
      last_vote_result = NULL
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ===== 3. host_day_to_night =====
DROP FUNCTION IF EXISTS public.host_day_to_night(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.host_day_to_night(p_room_id UUID)
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
    RAISE EXCEPTION 'Somente o host pode avancar para a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  UPDATE game_state
  SET current_phase = 'night',
      turn_index = v_turn + 1,
      phase_started_at = now(),
      night_step = 'sleeping',
      day_step = 'discussion',
      current_accused_id = NULL,
      last_vote_result = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ===== 4. host_absolve_accused =====
DROP FUNCTION IF EXISTS public.host_absolve_accused(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.host_absolve_accused(p_room_id UUID)
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
    RAISE EXCEPTION 'Somente o host pode absolver o acusado';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  DELETE FROM votes WHERE room_id = p_room_id AND turn_index = v_turn;

  UPDATE game_state
  SET day_step = 'discussion',
      current_accused_id = NULL,
      last_vote_result = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
