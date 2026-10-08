CREATE OR REPLACE FUNCTION public.get_wolves_for_sorceress(p_room_id uuid)
 RETURNS TABLE(id uuid, name text, is_alive boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM players p
        WHERE p.room_id = p_room_id AND p.user_id = auth.uid() AND p.role IN ('sorceress', 'minion')
    ) THEN
        RAISE EXCEPTION 'Apenas a Feiticeira pode ver os lobos';
    END IF;

    RETURN QUERY
    SELECT p.id, p.name, p.is_alive
    FROM players p
    WHERE p.room_id = p_room_id
      AND p.role = ANY(pack_roles());
END;
$function$
