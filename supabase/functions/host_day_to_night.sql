CREATE OR REPLACE FUNCTION public.host_day_to_night(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
