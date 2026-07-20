-- Fix: stale consensus_votes leaking between nights
--
-- Root cause: resolve_night does NOT increment turn_index (it preserves the
-- current value). The advance_to_night / advance_phase functions should
-- increment it, but even if they do, there is NO cleanup of consensus_votes
-- between turns. If turn_index doesn't change (or has a race condition),
-- old votes with target_index=1 from a previous night appear in
-- get_wolf_consensus and make computeConsensus(1) return immediate consensus
-- in frenzy mode.
--
-- Fix: trigger on game_state that deletes ALL consensus_votes for a room
-- when current_phase transitions to 'night'. This ensures a clean slate
-- every night regardless of turn_index behavior.

-- ── Function: cleanup consensus_votes on night start ────────────────
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

-- ── Trigger: fire after game_state.current_phase changes to 'night' ─
DROP TRIGGER IF EXISTS trg_cleanup_consensus_on_night ON game_state;
CREATE TRIGGER trg_cleanup_consensus_on_night
  AFTER UPDATE OF current_phase ON game_state
  FOR EACH ROW
  WHEN (NEW.current_phase = 'night')
  EXECUTE FUNCTION public.cleanup_consensus_on_night_start();
