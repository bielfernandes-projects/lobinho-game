-- Trigger on players.is_alive: records the winner computed by compute_winner.
CREATE OR REPLACE FUNCTION public.trg_check_game_over()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_winner TEXT;
BEGIN
  v_winner := compute_winner(NEW.room_id);
  IF v_winner IS NOT NULL THEN
    UPDATE game_state SET winner = v_winner WHERE room_id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$function$
