CREATE OR REPLACE FUNCTION public.marksman_shoot(p_room_id uuid, p_target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_marksman_id UUID;
  v_alive BOOLEAN;
  v_used_power BOOLEAN;
  v_current_phase TEXT;
  v_day_step TEXT;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;
  SELECT id, is_alive, COALESCE(has_used_power, false)
  INTO v_marksman_id, v_alive, v_used_power
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_marksman_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos não podem agir';
  END IF;

  IF (SELECT role FROM players WHERE id = v_marksman_id) != 'marksman' THEN
    RAISE EXCEPTION 'Ação inválida para o seu papel';
  END IF;

  IF v_used_power THEN
    RAISE EXCEPTION 'Você já usou seu tiro';
  END IF;

  -- B2 FIX: impedir auto-target
  IF p_target_id = v_marksman_id THEN
    RAISE EXCEPTION 'Você não pode atirar em si mesmo';
  END IF;

  SELECT current_phase, day_step, turn_index
  INTO v_current_phase, v_day_step, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'day' THEN
    RAISE EXCEPTION 'Só pode atirar durante o dia';
  END IF;

  IF v_day_step != 'discussion' THEN
    RAISE EXCEPTION 'Só pode atirar durante a discussão';
  END IF;

  SELECT name INTO v_target_name
  FROM players
  WHERE id = p_target_id AND is_alive = true AND is_host = false;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou não é válido';
  END IF;

  UPDATE players SET has_used_power = true WHERE id = v_marksman_id;
  -- death module: chain deaths, Prince -> Squire, Doppelganger (Hunter retaliation is not triggered by day shots)
  v_kill := kill_players(p_room_id, ARRAY[p_target_id], ARRAY['atirador']);

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$
