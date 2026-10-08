CREATE OR REPLACE FUNCTION public.upsert_consensus_vote(p_room_id uuid, p_target_id uuid, p_target_index smallint DEFAULT 1)
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

    -- Alive guard: dead wolves cannot vote
    IF NOT EXISTS (
        SELECT 1 FROM players
        WHERE id = v_player_id
          AND is_alive = true
    ) THEN
        RAISE EXCEPTION 'Jogadores mortos não podem votar';
    END IF;

    -- Role guard: only wolf variants can vote
    IF NOT EXISTS (
        SELECT 1 FROM players
        WHERE id = v_player_id
          AND role = ANY(pack_roles())
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
$function$
