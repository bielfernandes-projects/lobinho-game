-- ============================================================
-- MIGRATION 013: Correções de ambiguidade de RPC e falso empate
--
-- 1. submit_night_action: DROP de todas as assinaturas conflitantes
--    (VARCHAR vs TEXT) e recria com TEXT
-- 2. resolve_day_vote: subquery correta para contagem de empates
--    (evita falso positivo quando COUNT(*) retorna v_vote_count
--     em vez do número de alvos empatados)
-- ============================================================

-- ============================================================
-- FIX 1: [REMOVED] submit_night_action — use execute_night_action
-- (criada manualmente no Supabase para evitar overwrite no deploy)
--
-- Os DROPs abaixo limpam assinaturas antigas (mantidos).
-- A recriacao abaixo foi removida propositalmente.
-- ============================================================
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, VARCHAR, UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, VARCHAR);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, TEXT);

-- ============================================================
-- FIX 2: resolve_day_vote — subquery correta para contagem de
--         empates (evita falso positivo)
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
