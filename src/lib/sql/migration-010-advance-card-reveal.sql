-- ============================================================
-- MIGRATION 010: Fix advance_phase — card_reveal → night
--
-- Adiciona 'card_reveal' no CASE do advance_phase para
-- que o avancar da revelacao va para 'night' em vez de
-- cair no ELSE 'ended'.
-- ============================================================

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
    WHEN 'day' THEN 'vote'
    WHEN 'vote' THEN 'night'
    ELSE 'ended'
  END;

  UPDATE game_state
  SET current_phase = v_next,
      turn_index = turn_index + 1,
      phase_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;
