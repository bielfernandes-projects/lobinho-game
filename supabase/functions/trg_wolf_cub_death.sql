CREATE OR REPLACE FUNCTION public.trg_wolf_cub_death()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.is_alive = false AND OLD.role = 'wolf_cub' THEN
    UPDATE rooms SET wolves_frenzy = true WHERE id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$function$
