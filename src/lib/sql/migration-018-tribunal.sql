-- ============================================================
-- MIGRATION 018: Sistema de Tribunal (Acusação, Defesa, Plebiscito)
-- ============================================================

-- 1. Novas colunas na game_state
ALTER TABLE public.game_state ADD COLUMN IF NOT EXISTS day_step TEXT DEFAULT 'discussion';
ALTER TABLE public.game_state ADD COLUMN IF NOT EXISTS current_accused_id UUID DEFAULT NULL;

-- 2. Coluna vote_value na tabela votes
ALTER TABLE public.votes ADD COLUMN IF NOT EXISTS vote_value TEXT;

-- 3. Atualiza advance_phase: day -> night (voto agora é sub-fase do dia)
CREATE OR REPLACE FUNCTION public.advance_phase(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current VARCHAR;
  v_next VARCHAR;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode avancar a fase';
  END IF;

  SELECT current_phase INTO v_current FROM game_state WHERE room_id = p_room_id;

  v_next := CASE v_current
    WHEN 'card_reveal' THEN 'night'
    WHEN 'night' THEN 'day'
    WHEN 'day' THEN 'night'
    WHEN 'vote' THEN 'night'
    ELSE 'ended'
  END;

  UPDATE game_state
  SET current_phase = v_next,
      turn_index = turn_index + 1,
      phase_started_at = now(),
      night_step = CASE WHEN v_next = 'night' THEN 'sleeping' ELSE night_step END,
      day_step = 'discussion',
      current_accused_id = NULL
  WHERE room_id = p_room_id;
END;
$$;

-- 4. RPC: submit_tribunal_vote
CREATE OR REPLACE FUNCTION public.submit_tribunal_vote(p_room_id UUID, p_vote_value TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_alive BOOLEAN;
  v_current_phase TEXT;
  v_day_step TEXT;
  v_accused_id UUID;
  v_turn INT;
BEGIN
  SELECT id, is_alive INTO v_player_id, v_alive
  FROM players
  WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos nao podem votar';
  END IF;

  SELECT current_phase, day_step, current_accused_id, turn_index
  INTO v_current_phase, v_day_step, v_accused_id, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'day' OR v_day_step != 'voting' THEN
    RAISE EXCEPTION 'Votacao nao esta aberta';
  END IF;

  IF v_player_id = v_accused_id THEN
    RAISE EXCEPTION 'O acusado nao pode votar';
  END IF;

  IF p_vote_value NOT IN ('yes', 'no') THEN
    RAISE EXCEPTION 'Voto deve ser yes ou no';
  END IF;

  INSERT INTO votes (room_id, turn_index, voter_id, target_id, vote_value)
  VALUES (p_room_id, v_turn, v_player_id, v_accused_id, p_vote_value)
  ON CONFLICT (room_id, turn_index, voter_id)
  DO UPDATE SET vote_value = EXCLUDED.vote_value, target_id = EXCLUDED.target_id, created_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 5. RPC: host_execute_accused
CREATE OR REPLACE FUNCTION public.host_execute_accused(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_accused_id UUID;
  v_accused_name TEXT;
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

  SELECT name INTO v_accused_name FROM players WHERE id = v_accused_id;

  UPDATE players SET is_alive = false WHERE id = v_accused_id;

  UPDATE game_state
  SET current_phase = 'night',
      turn_index = v_turn + 1,
      phase_started_at = now(),
      night_step = 'sleeping',
      day_step = 'discussion',
      current_accused_id = NULL,
      last_event = jsonb_build_object(
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

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- 6. RPC: host_absolve_accused
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
      current_accused_id = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 7. RPC: host_day_to_night (avanca direto para noite sem acusacao)
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
      current_accused_id = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
