CREATE OR REPLACE FUNCTION public.hunter_retaliate(p_room_id uuid, p_target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hunter_id UUID;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;
  -- Verificar que existe hunter_pending
  SELECT hunter_id INTO v_hunter_id
  FROM game_state WHERE room_id = p_room_id;

  IF v_hunter_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum Caçador pendente de retaliação';
  END IF;

  -- Verificar que o alvo está vivo
  SELECT name INTO v_target_name FROM players WHERE id = p_target_id AND is_alive = true;
  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou já está morto';
  END IF;

  -- Verificar que o alvo não é o próprio Hunter
  IF p_target_id = v_hunter_id THEN
    RAISE EXCEPTION 'Você não pode atirar em si mesmo';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Matar o alvo
  v_kill := kill_players(p_room_id, ARRAY[p_target_id], ARRAY['cacador']);

  -- Registrar a ação no log noturno
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_hunter_id, 'hunter_shot', p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Limpar estado do Hunter
  UPDATE game_state
  SET hunter_pending = false, hunter_id = NULL
  WHERE room_id = p_room_id;

  -- Verificar game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$
