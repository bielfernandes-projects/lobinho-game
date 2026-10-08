CREATE OR REPLACE FUNCTION public.advance_after_hunter(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
