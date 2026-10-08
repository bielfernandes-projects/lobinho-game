CREATE OR REPLACE FUNCTION public.insta_kill(p_room_id uuid, p_player_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_target_alive BOOLEAN;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  -- Verificar que o caller é o host
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode matar jogadores';
  END IF;

  -- Verificar que o alvo está vivo
  SELECT is_alive, name INTO v_target_alive, v_target_name
  FROM players WHERE id = p_player_id AND room_id = p_room_id;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado na sala';
  END IF;

  IF NOT v_target_alive THEN
    RAISE EXCEPTION 'Jogador já está morto';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Matar
  UPDATE players SET strikes = 0 WHERE id = p_player_id;
  v_kill := kill_players(p_room_id, ARRAY[p_player_id], ARRAY['strike']);

  -- Log
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_caller_id, 'insta_kill', p_player_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$
