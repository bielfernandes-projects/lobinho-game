-- Lot 3 fix: RPC get_cult_targets for CultLeaderPanel
-- Returns alive, non-converted, non-moderator, non-cult_leader players

CREATE OR REPLACE FUNCTION public.get_cult_targets(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'name', p.name
    )
    ORDER BY p.name ASC
  ) INTO v_result
  FROM players p
  WHERE p.room_id = p_room_id
    AND p.is_alive = true
    AND p.role NOT IN ('moderator', 'cult_leader')
    AND (p.in_cult = false OR p.in_cult IS NULL);

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
