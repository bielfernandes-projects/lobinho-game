CREATE OR REPLACE FUNCTION public.trg_reset_game()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'waiting' AND OLD.status != 'waiting' THEN
    -- Limpar game_state
    DELETE FROM game_state WHERE room_id = NEW.id;
    -- Resetar strikes de todos os jogadores
    UPDATE players SET strikes = 0 WHERE room_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$
