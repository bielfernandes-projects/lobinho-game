-- The variant Ghost also sees every player's role (he stays awake all game anyway).
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.get_ghost_state(uuid)'::regprocedure);
  IF position('v_am_ghost AND v_card THEN' IN d) > 0 THEN
    EXECUTE replace(d, 'v_am_ghost AND v_card THEN', 'v_am_ghost THEN');
  END IF;
END
$do$;
