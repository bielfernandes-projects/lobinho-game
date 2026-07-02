-- Fix: resolve_night_wolves — return {consensus: false} instead of RAISE EXCEPTION
-- RAISE EXCEPTION rolls back the DELETE, so votes are never cleared.
-- Instead, DELETE + return a signal; frontend shows the error message.
DROP FUNCTION IF EXISTS public.resolve_night_wolves(UUID) CASCADE;
CREATE OR REPLACE FUNCTION public.resolve_night_wolves(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_distinct_targets INT;
  v_victim_id UUID;
  v_victim_name TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver o ataque';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Enforce consensus: count distinct targets chosen by wolves
  SELECT COUNT(DISTINCT target_id) INTO v_distinct_targets
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  IF v_distinct_targets > 1 THEN
    -- No consensus: delete all wolf votes so they can retry
    -- DELETE must happen BEFORE returning (no RAISE to avoid rollback)
    DELETE FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

    RETURN jsonb_build_object(
      'consensus', false,
      'message', 'Os lobos precisam chegar em um consenso — votos limpos, escolham novamente.'
    );
  END IF;

  -- Consensus reached: get the single target
  SELECT target_id INTO v_victim_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  LIMIT 1;

  IF v_victim_id IS NOT NULL THEN
    SELECT name INTO v_victim_name FROM players WHERE id = v_victim_id;
  END IF;

  UPDATE game_state
  SET wolves_resolved = true,
      last_event = jsonb_build_object(
        'type', 'wolf_target',
        'victim_id', v_victim_id,
        'victim_name', v_victim_name
      )
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'consensus', true,
    'victim_id', v_victim_id,
    'victim_name', v_victim_name
  );
END;
$$;
