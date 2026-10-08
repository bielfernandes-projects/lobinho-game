-- Lynch the accused. Decides who actually dies (Prince immunity, Cursed conversion, Martyr swap,
-- Old Witch immunity) and delegates the death itself, and everything that follows from it, to the
-- death module (kill_players).
CREATE OR REPLACE FUNCTION public.host_execute_accused(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_accused_id UUID;
  v_accused_name TEXT;
  v_accused_role TEXT;
  v_martyr UUID;
  v_turn INT;
  v_game_over JSONB;
  v_prince_revealed BOOLEAN := false;
  v_kill JSONB;
  v_deaths JSONB := '[]'::JSONB;
  v_extra JSONB := '[]'::JSONB;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode executar esta ação';
  END IF;

  SELECT current_accused_id, turn_index, martyr_id INTO v_accused_id, v_turn, v_martyr
  FROM game_state WHERE room_id = p_room_id;

  IF v_accused_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum acusado para executar';
  END IF;

  -- Old Witch: the poxed player is out of the village today
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = v_accused_id) THEN
    RAISE EXCEPTION 'Acusado esta fora da vila hoje';
  END IF;

  -- Martyr takes the accused's place
  IF v_martyr IS NOT NULL AND EXISTS (
    SELECT 1 FROM players WHERE id = v_martyr AND is_alive = true AND role = 'martyr'
  ) THEN
    v_accused_id := v_martyr;
  END IF;
  UPDATE game_state SET martyr_id = NULL WHERE room_id = p_room_id;

  SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;

  -- Prince: first lynch only reveals him
  SELECT prince_revealed INTO v_prince_revealed FROM game_state WHERE room_id = p_room_id;
  IF v_accused_role = 'prince' AND NOT v_prince_revealed THEN
    UPDATE game_state
    SET current_phase = 'day', day_step = 'prince_reveal',
        turn_index = v_turn, current_accused_id = NULL,
        prince_revealed = true,
        last_event = jsonb_build_object('type', 'prince_reveal', 'victim_id', v_accused_id, 'victim_name', v_accused_name, 'victim_role', v_accused_role),
        last_vote_result = jsonb_build_object('type', 'prince_reveal', 'victim_name', v_accused_name, 'victim_role', v_accused_role)
    WHERE room_id = p_room_id;
    RETURN jsonb_build_object('success', true, 'prince_reveal', true, 'victim_name', v_accused_name);
  END IF;

  -- Cursed: lynching converts, does not kill
  IF v_accused_role = 'cursed' THEN
    UPDATE players SET role = 'werewolf' WHERE id = v_accused_id;
    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        current_accused_id = NULL,
        last_event = jsonb_build_object(
          'type', 'vote_result', 'event_type', 'lynch',
          'victim_id', v_accused_id, 'victim_name', v_accused_name,
          'victim_role', 'werewolf',
          'cursed_converted', true,
          'cursed_converted_id', v_accused_id,
          'cursed_converted_name', v_accused_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch', 'victim_name', v_accused_name, 'victim_role', 'werewolf',
          'cursed_converted', true,
          'cursed_converted_name', v_accused_name
        )
    WHERE room_id = p_room_id;
    v_game_over := check_game_over(p_room_id);
    RETURN jsonb_build_object('success', true, 'cursed_converted', true, 'game_over', v_game_over);
  END IF;

  -- Everything else dies through the death module
  v_kill := kill_players(p_room_id, ARRAY[v_accused_id], ARRAY['linchamento']);
  v_deaths := v_kill->'deaths';
  v_hunter_pending := COALESCE((v_kill->>'hunter_pending')::BOOLEAN, false);
  v_hunter_id := NULLIF(v_kill->>'hunter_id', '')::UUID;

  -- Chain deaths (soulmate, companion, partner) besides the accused, announced like the rest
  SELECT COALESCE(jsonb_agg(d), '[]'::JSONB) INTO v_extra
  FROM jsonb_array_elements(v_deaths) d WHERE d->>'id' <> v_accused_id::TEXT;

  SELECT d->>'name', d->>'role' INTO v_soulmate_name, v_soulmate_role
  FROM jsonb_array_elements(v_extra) d WHERE d->>'cause' = 'soulmate' LIMIT 1;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = CASE WHEN v_hunter_pending THEN 'hunter_reveal' ELSE 'lynch_reveal' END,
      turn_index = v_turn, phase_started_at = now(), current_accused_id = NULL,
      last_event = jsonb_build_object(
        'type', 'vote_result', 'event_type', 'lynch',
        'victim_id', v_accused_id, 'victim_name', v_accused_name,
        'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
        'extra_deaths', v_extra
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name, 'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
        'extra_deaths', v_extra
      ),
      hunter_pending = v_hunter_pending,
      hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over, 'hunter_pending', v_hunter_pending);
END;
$function$
