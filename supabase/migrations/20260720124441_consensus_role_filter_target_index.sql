-- Consensus voting fixes:
-- 1. get_wolf_consensus: drop + recreate with role filtering + target_index
-- 2. upsert_consensus_vote: drop + recreate with role guard + target_index
-- 3. consensus_votes table: add target_index column, expand PK
-- 4. Clean up stale non-wolf votes

-- ── RPC: drop old functions first (need DROP to change return type) ──
DROP FUNCTION IF EXISTS public.get_wolf_consensus(UUID);
DROP FUNCTION IF EXISTS public.upsert_consensus_vote(UUID, UUID);

-- ── TABLE: add target_index column ──────────────────────────────────
ALTER TABLE consensus_votes ADD COLUMN target_index SMALLINT NOT NULL DEFAULT 1;

-- Expand PK to include target_index
ALTER TABLE consensus_votes DROP CONSTRAINT consensus_votes_pkey;
ALTER TABLE consensus_votes ADD PRIMARY KEY (room_id, turn_index, voter_id, target_index);

-- Remove stale non-wolf votes (cleanup)
DELETE FROM consensus_votes cv
WHERE NOT EXISTS (
    SELECT 1 FROM players p
    WHERE p.id = cv.voter_id
      AND p.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')
);

-- ── RPC: upsert_consensus_vote (with role guard + target_index) ─────
CREATE OR REPLACE FUNCTION public.upsert_consensus_vote(
    p_room_id UUID,
    p_target_id UUID,
    p_target_index SMALLINT DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_player_id UUID;
    v_turn_index INT;
BEGIN
    -- Resolve player from auth
    SELECT id INTO v_player_id
    FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid()
    LIMIT 1;

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'Player not found in room';
    END IF;

    -- Role guard: only wolf variants can vote
    IF NOT EXISTS (
        SELECT 1 FROM players
        WHERE id = v_player_id
          AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')
    ) THEN
        RAISE EXCEPTION 'Apenas lobisomens podem votar';
    END IF;

    -- Get current turn index
    SELECT turn_index INTO v_turn_index
    FROM game_state
    WHERE room_id = p_room_id;

    IF v_turn_index IS NULL THEN
        RAISE EXCEPTION 'Game state not found';
    END IF;

    -- Upsert the vote
    INSERT INTO consensus_votes (room_id, turn_index, voter_id, target_id, target_index, updated_at)
    VALUES (p_room_id, v_turn_index, v_player_id, p_target_id, p_target_index, NOW())
    ON CONFLICT (room_id, turn_index, voter_id, target_index)
    DO UPDATE SET target_id = p_target_id, updated_at = NOW();
END;
$function$;

-- ── RPC: get_wolf_consensus (filtered by role + returns target_index) ─
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
      AND vp.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf');
END;
$function$;
