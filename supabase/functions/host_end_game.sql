CREATE OR REPLACE FUNCTION public.host_end_game(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode encerrar o jogo';
  END IF;

  SELECT winner INTO v_winner FROM game_state WHERE room_id = p_room_id;

  IF v_winner = 'villagers_win' THEN
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
  ELSIF v_winner = 'wolves_win' THEN
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
  ELSIF v_winner = 'tanner_win' THEN
    UPDATE rooms SET status = 'finished_tanner_win' WHERE id = p_room_id;
  ELSIF v_winner = 'soulmates_win' THEN
    UPDATE rooms SET status = 'finished_soulmates_win' WHERE id = p_room_id;
  ELSIF v_winner = 'chupacabra_win' THEN
    UPDATE rooms SET status = 'finished_chupacabra_win' WHERE id = p_room_id;
  ELSIF v_winner = 'cult_win' THEN
    UPDATE rooms SET status = 'finished_cult_win' WHERE id = p_room_id;
  ELSIF v_winner = 'lone_wolf_win' THEN
    UPDATE rooms SET status = 'finished_lone_wolf_win' WHERE id = p_room_id;
  ELSE
    RAISE EXCEPTION 'Nenhum vencedor definido';
  END IF;

  UPDATE game_state SET current_phase = 'ended' WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'winner', v_winner);
END;
$function$
