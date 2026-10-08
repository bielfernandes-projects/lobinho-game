-- Sorceress sees who the wolves are (wolves still do NOT see her:
-- get_werewolf_teammates is unchanged and never returns 'sorceress').
CREATE OR REPLACE FUNCTION public.get_wolves_for_sorceress(p_room_id UUID)
RETURNS TABLE (id UUID, name TEXT, is_alive BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM players p
        WHERE p.room_id = p_room_id AND p.user_id = auth.uid() AND p.role = 'sorceress'
    ) THEN
        RAISE EXCEPTION 'Apenas a Feiticeira pode ver os lobos';
    END IF;

    RETURN QUERY
    SELECT p.id, p.name, p.is_alive
    FROM players p
    WHERE p.room_id = p_room_id
      AND p.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_wolves_for_sorceress(UUID) TO authenticated;
