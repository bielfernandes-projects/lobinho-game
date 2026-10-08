-- Apprentice Seer: trigger promotes him to seer when the Seer dies (any cause).
-- Dire Wolf: wolf-team; picks a companion on night 1 (night_actions 'dire_wolf_companion');
--            dies when the companion dies (trigger).
-- Old Witch: each night "poxes" a player (night_actions 'old_witch_pox' -> game_state.poxed_id,
--            set in resolve_night); the poxed player sits out the next day.
-- Drunk: host reveals the real role on night 3 via host_reveal_drunk.
-- Patches existing functions in place (anchor replace on pg_get_functiondef).

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT, expected INT DEFAULT 1)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> expected THEN
    RAISE EXCEPTION 'patch anchor count <> %: %', expected, anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

ALTER TABLE game_state ADD COLUMN IF NOT EXISTS poxed_id UUID;

DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''martyr''::character varying', '''martyr''::character varying, ''apprentice_seer''::character varying, ''old_witch''::character varying, ''drunk''::character varying, ''dire_wolf''::character varying');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'night_actions_action_type_check';
  ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  EXECUTE 'ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check ' ||
    public.__patch(d, '''tough_guy_doomed''::text', '''tough_guy_doomed''::text, ''old_witch_pox''::text, ''dire_wolf_companion''::text');
END
$do$;

-- Dire Wolf joins every wolf-team list
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
    IF position('''alpha_wolf'', ''dire_wolf''' IN d) = 0 THEN
      EXECUTE replace(d, '''wolf_cub'', ''alpha_wolf''', '''wolf_cub'', ''alpha_wolf'', ''dire_wolf''');
    END IF;
  END LOOP;
END
$do$;

-- new night actions
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'ELSIF p_action_type = ''huntress_kill'' THEN', $r$ELSIF p_action_type = 'old_witch_pox' THEN
    IF v_role <> 'old_witch' OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'dire_wolf_companion' THEN
    IF v_role <> 'dire_wolf' OR v_turn <> 1 OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'huntress_kill' THEN$r$);
  EXECUTE d;
END
$do$;

-- resolve_night: publish tonight's pox target
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, 'SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;', $r$SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;
  UPDATE game_state SET poxed_id = (
    SELECT target_id FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'old_witch_pox' LIMIT 1
  ) WHERE room_id = p_room_id;$r$);
  EXECUTE d;
END
$do$;

-- Apprentice Seer promotion
CREATE OR REPLACE FUNCTION public.trg_apprentice_seer()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE players SET role = 'seer'
  WHERE id = (
    SELECT id FROM players
    WHERE room_id = NEW.room_id AND role = 'apprentice_seer' AND is_alive = true
    LIMIT 1
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_apprentice_seer ON players;
CREATE TRIGGER trg_apprentice_seer
AFTER UPDATE OF is_alive ON players
FOR EACH ROW
WHEN (OLD.is_alive = true AND NEW.is_alive = false AND NEW.role = 'seer')
EXECUTE FUNCTION public.trg_apprentice_seer();

-- Dire Wolf dies with its companion
CREATE OR REPLACE FUNCTION public.trg_dire_wolf_companion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE players SET is_alive = false
  WHERE is_alive = true AND role = 'dire_wolf'
    AND id IN (
      SELECT actor_id FROM night_actions
      WHERE room_id = NEW.room_id AND action_type = 'dire_wolf_companion' AND target_id = NEW.id
    );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dire_wolf_companion ON players;
CREATE TRIGGER trg_dire_wolf_companion
AFTER UPDATE OF is_alive ON players
FOR EACH ROW
WHEN (OLD.is_alive = true AND NEW.is_alive = false)
EXECUTE FUNCTION public.trg_dire_wolf_companion();

-- Drunk: host reveals the real role
CREATE OR REPLACE FUNCTION public.host_reveal_drunk(p_room_id UUID, p_player_id UUID, p_role TEXT)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode revelar o Bebado';
  END IF;
  IF p_role IN ('moderator', 'drunk') THEN
    RAISE EXCEPTION 'Papel invalido';
  END IF;
  UPDATE players SET role = p_role
  WHERE id = p_player_id AND room_id = p_room_id AND role = 'drunk' AND is_alive = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bebado nao encontrado';
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.host_reveal_drunk(UUID, UUID, TEXT) TO authenticated;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
