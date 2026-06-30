-- ============================================================
-- MIGRATION 011: Excluir Mestre da contagem e ações de jogo
--
-- 1. resolve_day_vote: v_alive exclui role = 'moderator'
-- 2. Nova RPC submit_vote: insere voto com SECURITY DEFINER
--    (evita RLS blocker que impedia consenso)
-- ============================================================

-- ============================================================
-- RPC: resolve_day_vote -- moderator exclusion
-- ============================================================
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
  v_game_over JSONB;
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

  SELECT COUNT(*) INTO v_tie_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  HAVING COUNT(*) = v_vote_count;

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
    SELECT name INTO v_victim_name FROM players WHERE id = v_target_id;
    UPDATE players SET is_alive = false WHERE id = v_target_id;

    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        last_event = jsonb_build_object(
          'type', 'vote_result',
          'event_type', 'lynch',
          'victim_id', v_target_id,
          'victim_name', v_victim_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name
        )
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ============================================================
-- RPC: submit_vote -- insere voto com SECURITY DEFINER
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_vote(
  p_room_id UUID,
  p_turn_index INT,
  p_target_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_alive BOOLEAN;
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

  INSERT INTO votes (room_id, turn_index, voter_id, target_id)
  VALUES (p_room_id, p_turn_index, v_player_id, p_target_id)
  ON CONFLICT (room_id, turn_index, voter_id)
  DO UPDATE SET target_id = EXCLUDED.target_id, created_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;
