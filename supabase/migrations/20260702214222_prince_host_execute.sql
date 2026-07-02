-- Prince check in host_execute_accused

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
