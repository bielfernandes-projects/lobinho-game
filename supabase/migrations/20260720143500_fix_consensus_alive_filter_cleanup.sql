-- One-time cleanup + is_alive filter for get_wolf_consensus
-- Follow-up to 20260720143000 (already applied)

-- ── 0. One-time cleanup of ALL stale consensus_votes ───────────────
DELETE FROM consensus_votes;

-- ── 1. get_wolf_consensus: filter alive wolves only ────────────────
CREATE OR REPLACE FUNCTION public.get_wolf_consensus(p_room_id UUID)
RETURNS TABLE(
    voter_id UUID,
    voter_name TEXT,
    target_id UUID,
    target_name TEXT,
    target_index SMALLINT
)
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
      AND vp.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')
      AND vp.is_alive = true;
END;
$function$;
