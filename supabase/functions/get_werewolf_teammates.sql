CREATE OR REPLACE FUNCTION public.get_werewolf_teammates(p_room_id uuid)
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT role FROM players WHERE user_id = auth.uid() AND room_id = p_room_id)
     <> ALL(pack_roles()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT p.id, p.name::text
  FROM players p
  WHERE p.room_id = p_room_id
    AND p.role = ANY(pack_roles())
    AND p.user_id != auth.uid();
END;
$function$
