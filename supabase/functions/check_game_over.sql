-- RPC-style game-over check: asks compute_winner and records the result.
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM game_state
    WHERE room_id = p_room_id AND COALESCE(turn_index, 0) <> 0 AND current_phase <> 'card_reveal'
  ) THEN
    RETURN jsonb_build_object('game_over', false, 'skipped', true);
  END IF;

  v_winner := compute_winner(p_room_id);
  IF v_winner IS NULL THEN
    RETURN jsonb_build_object('game_over', false);
  END IF;

  UPDATE game_state SET winner = v_winner WHERE room_id = p_room_id;
  RETURN jsonb_build_object(
    'game_over', true,
    'winner', v_winner,
    'display', CASE v_winner
      WHEN 'lone_wolf_win' THEN 'Lobo Solitario Venceu'
      WHEN 'chupacabra_win' THEN 'Chupacu Venceu'
      WHEN 'tanner_win' THEN 'Curtidor Venceu'
      WHEN 'villagers_win' THEN 'Aldeoes Venceram'
      WHEN 'wolves_win' THEN 'Lobisomens Venceram'
      ELSE NULL END
  );
END;
$function$
