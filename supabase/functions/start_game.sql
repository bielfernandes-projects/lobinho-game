CREATE OR REPLACE FUNCTION public.start_game(p_room_id uuid, p_roles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_status TEXT;
  v_player_count INT;
  v_alive_count INT;
  v_roles JSONB;
  v_player RECORD;
  v_idx INT := 0;
  v_role TEXT;
  v_existing_game_state BOOLEAN;
BEGIN
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode iniciar o jogo';
  END IF;

  SELECT status INTO v_status FROM rooms WHERE id = p_room_id;
  IF v_status != 'waiting' THEN
    RAISE EXCEPTION 'Sala não está em estado de espera (status: %)', v_status;
  END IF;

  SELECT COUNT(*) INTO v_alive_count
  FROM players WHERE room_id = p_room_id AND is_host = false;

  v_roles := p_roles;
  IF jsonb_array_length(v_roles) != v_alive_count THEN
    RAISE EXCEPTION 'Número de cartas (%) não corresponde ao número de jogadores (%)', jsonb_array_length(v_roles), v_alive_count;
  END IF;

  -- Distribuir papéis aleatoriamente para jogadores (NÃO host)
  FOR v_player IN
    SELECT id FROM players WHERE room_id = p_room_id AND is_host = false
    ORDER BY random()
  LOOP
    v_role := v_roles ->> v_idx;
    UPDATE players SET role = v_role WHERE id = v_player.id;
    v_idx := v_idx + 1;
  END LOOP;

  -- Setar host como moderator
  UPDATE players SET role = 'moderator' WHERE room_id = p_room_id AND is_host = true;

  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  SELECT EXISTS(SELECT 1 FROM game_state WHERE room_id = p_room_id) INTO v_existing_game_state;

  IF v_existing_game_state THEN
    UPDATE game_state
    SET current_phase = 'scenario_reveal',
        day_step = 'discussion',
        night_step = 'sleeping',
        turn_index = 0
    WHERE room_id = p_room_id;
  ELSE
    INSERT INTO game_state (
      room_id, current_phase, day_step, night_step, turn_index,
      wolves_resolved, voting_open, hunter_pending,
      timer_duration, timer_remaining, is_timer_running
    )
    VALUES (
      p_room_id, 'scenario_reveal', 'discussion', 'sleeping', 0,
      false, false, false,
      NULL, NULL, false
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'phase', 'scenario_reveal'
  );
END;
$function$
