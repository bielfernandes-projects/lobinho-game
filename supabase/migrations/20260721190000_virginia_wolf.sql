-- Virginia Wolf: wolf-team; night 1 picks a partner (night_actions 'virginia_partner');
--   if she dies the partner dies too (trigger) and is announced in the morning like any death.

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT, expected INT DEFAULT 1)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> expected THEN
    RAISE EXCEPTION 'patch anchor count <> %: %', expected, anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

-- constraints
DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''dire_wolf''::character varying', '''dire_wolf''::character varying, ''virginia_wolf''::character varying');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'night_actions_action_type_check';
  ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  EXECUTE 'ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check ' ||
    public.__patch(d, '''dire_wolf_companion''::text', '''dire_wolf_companion''::text, ''virginia_partner''::text');
END
$do$;

-- Virginia Wolf joins every wolf-team list
DO $do$
DECLARE r RECORD; d TEXT;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('check_game_over', 'trg_check_game_over', 'execute_night_action',
                        'get_werewolf_teammates', 'get_wolf_consensus', 'get_wolves_for_sorceress',
                        'resolve_night', 'upsert_consensus_vote')
  LOOP
    d := pg_get_functiondef(r.oid);
    IF position('''dire_wolf'', ''virginia_wolf''' IN d) = 0 THEN
      EXECUTE replace(d, '''alpha_wolf'', ''dire_wolf''', '''alpha_wolf'', ''dire_wolf'', ''virginia_wolf''');
    END IF;
  END LOOP;
END
$do$;

-- virginia_partner action (night 1 only, not self)
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'ELSIF p_action_type = ''dire_wolf_companion'' THEN', $r$ELSIF p_action_type = 'virginia_partner' THEN
    IF v_role <> 'virginia_wolf' OR v_turn <> 1 OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'dire_wolf_companion' THEN$r$);
  EXECUTE d;
END
$do$;

-- resolve_night: announce a Virginia-linked death in the morning
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, '-- B21 FIX: Agora sim', $r$-- Partner of a dead Virginia Wolf: announce like any other death
  DECLARE
    v_vw RECORD;
  BEGIN
    FOR v_vw IN
      SELECT pt.name AS name, pt.role AS role
      FROM players vw
      JOIN night_actions na ON na.actor_id = vw.id AND na.action_type = 'virginia_partner'
      JOIN players pt ON pt.id = na.target_id
      WHERE vw.room_id = p_room_id AND vw.role = 'virginia_wolf' AND vw.is_alive = false
        AND pt.is_alive = false
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_victims) v WHERE v->>'name' = vw.name)
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_victims) v WHERE v->>'name' = pt.name)
    LOOP
      v_victims := v_victims || jsonb_build_object('name', v_vw.name, 'cause', 'companheiro', 'role', v_vw.role);
    END LOOP;
  END;

  -- B21 FIX: Agora sim$r$);
  EXECUTE d;
END
$do$;

-- Virginia Wolf death takes the partner with her
CREATE OR REPLACE FUNCTION public.trg_virginia_wolf_partner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE players SET is_alive = false
  WHERE is_alive = true
    AND id IN (
      SELECT target_id FROM night_actions
      WHERE room_id = NEW.room_id AND action_type = 'virginia_partner' AND actor_id = NEW.id
    );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_virginia_wolf_partner ON players;
CREATE TRIGGER trg_virginia_wolf_partner
AFTER UPDATE OF is_alive ON players
FOR EACH ROW
WHEN (OLD.is_alive = true AND NEW.is_alive = false AND NEW.role = 'virginia_wolf')
EXECUTE FUNCTION public.trg_virginia_wolf_partner();

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
