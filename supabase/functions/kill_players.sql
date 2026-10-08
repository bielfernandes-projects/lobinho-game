-- Death module. One interface for "these players die": every death path calls this.
--   kill_players(room, ids, causes) -> {deaths: [{id,name,role,cause}], hunter_pending, hunter_id}
-- Chain deaths (soulmate, Dire Wolf companion, Virginia Wolf partner) are produced by the
-- AFTER UPDATE OF is_alive triggers; this module reports them by diffing who was alive before/after.
-- Post-effects live here once: Hunter pending, Prince -> Squire promotion, Doppelganger role copy.
CREATE OR REPLACE FUNCTION public.kill_players(p_room_id uuid, p_ids uuid[], p_causes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_before UUID[];
  v_deaths JSONB := '[]'::JSONB;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_prince_died BOOLEAN := false;
  v_squire_id UUID;
  r RECORD;
  v_cause TEXT;
  v_idx INT;
BEGIN
  SELECT COALESCE(array_agg(id), ARRAY[]::UUID[]) INTO v_before
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  -- one statement: simultaneous deaths (Prince + Squire together, etc.)
  UPDATE players SET is_alive = false
  WHERE room_id = p_room_id AND is_alive = true AND id = ANY(p_ids);

  FOR r IN
    SELECT p.id, p.name, p.role, p.soulmate_id
    FROM players p
    WHERE p.room_id = p_room_id AND p.is_alive = false AND p.id = ANY(v_before)
    ORDER BY array_position(p_ids, p.id) NULLS LAST, p.name
  LOOP
    v_idx := array_position(p_ids, r.id);
    IF v_idx IS NOT NULL THEN
      v_cause := COALESCE(p_causes[v_idx], 'morte');
    ELSIF r.soulmate_id IS NOT NULL AND r.soulmate_id = ANY(p_ids) THEN
      v_cause := 'soulmate';
    ELSE
      v_cause := 'cadeia';
    END IF;

    v_deaths := v_deaths || jsonb_build_object('id', r.id, 'name', r.name, 'role', r.role, 'cause', v_cause);

    IF r.role = 'hunter' THEN
      v_hunter_pending := true;
      v_hunter_id := r.id;
    END IF;
    IF r.role = 'prince' THEN
      v_prince_died := true;
    END IF;
  END LOOP;

  -- Squire inherits the Prince only after ALL simultaneous deaths are settled
  IF v_prince_died THEN
    SELECT id INTO v_squire_id FROM players
    WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
    IF v_squire_id IS NOT NULL THEN
      UPDATE players SET role = 'prince' WHERE id = v_squire_id;
    END IF;
  END IF;

  -- Doppelganger copies the role of a dead target
  UPDATE players d SET role = t.role
  FROM players t
  WHERE d.room_id = p_room_id AND d.is_alive = true AND d.role = 'doppelganger'
    AND d.doppelganger_target_id = t.id AND t.is_alive = false;

  RETURN jsonb_build_object(
    'deaths', v_deaths,
    'hunter_pending', v_hunter_pending,
    'hunter_id', v_hunter_id
  );
END;
$function$
