-- ============================================================
-- MIGRATION 020: Expansion Lot 1 — Passives (Mayor, Prince, Tanner, Lycan)
-- ============================================================
-- Apply this entire file via Supabase SQL Editor.
-- Also apply the one-line change to execute_night_action separately (see end of file).

-- ============================================================
-- 1. Add 'finished_tanner_win' to rooms.status constraint
-- ============================================================
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_status_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_status_check
  CHECK (status IN ('waiting', 'playing', 'finished', 'finished_villagers_win', 'finished_wolves_win', 'finished_tanner_win'));

-- ============================================================
-- 2. Update check_game_over — add tanner win priority rule
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN jsonb_build_object('game_over', false, 'skipped', true);
  END IF;

  -- PRIORITY: tanner win check (victim of the lynch must be the tanner)
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = p_room_id;
  IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
    SELECT 1 FROM players
    WHERE id = (v_last_event->>'victim_id')::UUID
      AND role = 'tanner'
      AND is_alive = false
  ) THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = p_room_id;
    RETURN jsonb_build_object('game_over', true, 'winner', 'tanner_win', 'display', 'Curtidor Venceu');
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = p_room_id;

  IF v_wolves = 0 THEN
    v_winner := 'villagers_win';
    v_winner_display := 'Aldeoes Venceram';
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = p_room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    v_winner := 'wolves_win';
    v_winner_display := 'Lobisomens Venceram';
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = p_room_id;
  END IF;

  IF v_winner IS NULL THEN
    RETURN jsonb_build_object('game_over', false);
  END IF;

  RETURN jsonb_build_object('game_over', true, 'winner', v_winner, 'display', v_winner_display);
END;
$$;

-- ============================================================
-- 3. Update trg_check_game_over — add tanner win priority rule
-- ============================================================
DROP TRIGGER IF EXISTS trg_check_game_over ON players;
CREATE OR REPLACE FUNCTION public.trg_check_game_over()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = NEW.room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NEW;
  END IF;

  -- PRIORITY: tanner win check (the player being killed must be the tanner AND the cause must be lynch)
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = NEW.room_id;
  IF NEW.role = 'tanner'
     AND NEW.is_alive = false
     AND v_last_event->>'event_type' = 'lynch'
     AND v_last_event->>'victim_id' = NEW.id::TEXT
  THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = NEW.room_id;
    RETURN NEW;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = NEW.room_id;

  IF v_wolves = 0 THEN
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = NEW.room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = NEW.room_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_check_game_over
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_game_over();

-- ============================================================
-- 4. Update host_execute_accused — prince check + reorder for tanner
-- ============================================================
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

  SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;

  -- PRINCE CHECK: if prince is accused, reveal identity and absolve instead of killing
  IF v_accused_role = 'prince' THEN
    UPDATE game_state
    SET last_event = jsonb_build_object(
          'type', 'prince_revealed',
          'player_name', v_accused_name,
          'message', format('%s revelou ser o Principe e sobreviveu ao linchamento', v_accused_name)
        ),
        day_step = 'discussion',
        current_accused_id = NULL
    WHERE room_id = p_room_id;

    DELETE FROM votes WHERE room_id = p_room_id AND turn_index = v_turn;

    RETURN jsonb_build_object('success', true, 'prince_revealed', true);
  END IF;

  -- Record lynch in game_state FIRST (so trigger trg_check_game_over sees last_event)
  UPDATE game_state
  SET last_event = jsonb_build_object(
        'type', 'vote_result',
        'event_type', 'lynch',
        'victim_id', v_accused_id,
        'victim_name', v_accused_name
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name
      )
  WHERE room_id = p_room_id;

  -- Kill the accused player (trigger fires here, can see 'lynch' in last_event)
  UPDATE players SET is_alive = false WHERE id = v_accused_id;

  -- Advance to night
  UPDATE game_state
  SET current_phase = 'night',
      turn_index = v_turn + 1,
      phase_started_at = now(),
      night_step = 'sleeping',
      day_step = 'discussion',
      current_accused_id = NULL
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ============================================================
-- 5. Update host_end_game — support tanner_win
-- ============================================================
CREATE OR REPLACE FUNCTION public.host_end_game(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode encerrar o jogo';
  END IF;

  SELECT winner INTO v_winner FROM game_state WHERE room_id = p_room_id;

  IF v_winner = 'villagers_win' THEN
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
  ELSIF v_winner = 'wolves_win' THEN
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
  ELSIF v_winner = 'tanner_win' THEN
    UPDATE rooms SET status = 'finished_tanner_win' WHERE id = p_room_id;
  ELSE
    RAISE EXCEPTION 'Nenhum vencedor definido';
  END IF;

  UPDATE game_state SET current_phase = 'ended' WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'winner', v_winner);
END;
$$;

-- ============================================================
-- 6. Lycan — execute_night_action seer check
-- ============================================================
-- INSTRUCAO: Na RPC execute_night_action (ja existente no banco),
-- altere APENAS a linha:
--
--   SELECT (role = 'werewolf') INTO v_result
--
-- para:
--
--   SELECT (role IN ('werewolf', 'lycan')) INTO v_result
--
-- Esta RPC foi removida dos arquivos de migracao (neutered) e
-- deve ser editada manualmente no Supabase SQL Editor.
-- ============================================================
