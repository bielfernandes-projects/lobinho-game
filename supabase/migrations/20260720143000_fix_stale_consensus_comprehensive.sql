-- Fix: comprehensive stale consensus_votes defense
--
-- ROOT CAUSE: trg_reset_game (triggered when rooms.status → 'waiting')
-- did NOT delete consensus_votes or reset wolves_frenzy. Old votes from
-- a previous game with matching turn_index leaked into the next game,
-- making computeConsensus() return true instantly.
--
-- FIXES:
-- 1. One-time cleanup of ALL stale consensus_votes
-- 2. Improved trigger: fires on INSERT OR UPDATE of game_state
-- 3. get_wolf_consensus: add is_alive = true filter
-- 4. Reset trigger: now cleans consensus_votes + wolves_frenzy

-- ── 0. One-time cleanup ────────────────────────────────────────────
DELETE FROM consensus_votes;

-- ── 1. Improved trigger: fire on INSERT OR UPDATE ──────────────────
DROP TRIGGER IF EXISTS trg_cleanup_consensus_on_night ON game_state;

CREATE OR REPLACE FUNCTION public.cleanup_consensus_on_night_start()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.current_phase = 'night' THEN
    DELETE FROM consensus_votes WHERE room_id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_cleanup_consensus_on_night
  AFTER INSERT OR UPDATE ON game_state
  FOR EACH ROW
  WHEN (NEW.current_phase = 'night')
  EXECUTE FUNCTION public.cleanup_consensus_on_night_start();

-- ── 2. get_wolf_consensus: filter alive wolves only ────────────────
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

-- ── 3. Reset trigger: clean consensus_votes + wolves_frenzy ─────────
DROP TRIGGER IF EXISTS trg_reset_game ON rooms;

CREATE OR REPLACE FUNCTION public.handle_room_reset()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'waiting' AND OLD.status IS DISTINCT FROM 'waiting' THEN
    UPDATE players SET
      is_alive = true,
      has_viewed_card = false,
      role = NULL,
      strikes = 0,
      doppelganger_target_id = NULL
    WHERE room_id = NEW.id;

    DELETE FROM night_actions WHERE room_id = NEW.id;
    DELETE FROM votes WHERE room_id = NEW.id;
    DELETE FROM consensus_votes WHERE room_id = NEW.id;
    DELETE FROM game_state WHERE room_id = NEW.id;

    UPDATE rooms SET wolves_frenzy = false WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_reset_game
  AFTER UPDATE OF status ON rooms
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_room_reset();
