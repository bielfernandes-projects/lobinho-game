CREATE OR REPLACE FUNCTION public.get_wolf_consensus(p_room_id uuid)
 RETURNS TABLE(voter_id uuid, voter_name text, target_id uuid, target_name text, target_index smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_turn_index INT;
BEGIN
    SELECT turn_index INTO v_turn_index
    FROM game_state
    WHERE room_id = p_room_id;

    IF v_turn_index IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        cv.voter_id,
        vp.name::TEXT AS voter_name,
        cv.target_id,
        tp.name::TEXT AS target_name,
        cv.target_index
    FROM consensus_votes cv
    JOIN players vp ON vp.id = cv.voter_id
    LEFT JOIN players tp ON tp.id = cv.target_id
    WHERE cv.room_id = p_room_id
      AND cv.turn_index = v_turn_index
      AND vp.role = ANY(pack_roles())
      AND vp.is_alive = true;
END;
$function$
