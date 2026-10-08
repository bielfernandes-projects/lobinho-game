-- 1) Chupacabra is blockable by Bodyguard and Witch save (NOT by Priest).
-- 2) Minion (wolf team, sees wolves on night 1, hidden from them).
-- 3) Huntress (village, one-shot night kill; Bodyguard protects, Priest does not).
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

-- constraints
DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''chupacabra''::character varying', '''chupacabra''::character varying, ''minion''::character varying, ''huntress''::character varying');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'night_actions_action_type_check';
  ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  EXECUTE 'ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check ' ||
    public.__patch(d, '''chupacabra_kill''::text', '''chupacabra_kill''::text, ''huntress_kill''::text');
END
$do$;

-- win conditions: minion counts as wolf team (like sorceress)
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.check_game_over(uuid)'::regprocedure);
  d := public.__patch(d, '''alpha_wolf'', ''sorceress''', '''alpha_wolf'', ''sorceress'', ''minion''', 2);
  EXECUTE d;
  d := pg_get_functiondef('public.trg_check_game_over()'::regprocedure);
  d := public.__patch(d, '''alpha_wolf'', ''sorceress''', '''alpha_wolf'', ''sorceress'', ''minion''', 2);
  EXECUTE d;
END
$do$;

-- sorceress RPC also serves the minion
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.get_wolves_for_sorceress(uuid)'::regprocedure);
  d := public.__patch(d, 'AND p.role = ''sorceress''', 'AND p.role IN (''sorceress'', ''minion'')');
  EXECUTE d;
END
$do$;

-- huntress_kill action
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'ELSIF p_action_type = ''chupacabra_kill'' THEN', $r$ELSIF p_action_type = 'huntress_kill' THEN
    IF v_role <> 'huntress' THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    IF v_used_power THEN
      RAISE EXCEPTION 'Voce ja usou seu poder especial';
    END IF;
    UPDATE players SET has_used_power = true WHERE id = v_player_id;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'chupacabra_kill' THEN$r$);
  EXECUTE d;
END
$do$;

-- resolve_night: chupacabra protections + huntress kill
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, 'AND (SELECT is_alive FROM players WHERE id = v_chupa_target_id) THEN', $r$AND (SELECT is_alive FROM players WHERE id = v_chupa_target_id)
     AND NOT EXISTS (
       SELECT 1 FROM night_actions
       WHERE room_id = p_room_id AND turn_index = v_turn
         AND action_type = 'bodyguard_protect' AND target_id = v_chupa_target_id)
     AND NOT EXISTS (
       SELECT 1 FROM night_actions
       WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save') THEN$r$);
  d := public.__patch(d, 'v_wolves_alive_at_start INT;', $r$v_wolves_alive_at_start INT;
  v_huntress_target_id UUID;
  v_huntress_target_name TEXT;
  v_huntress_target_role TEXT;$r$);
  d := public.__patch(d, '-- PASSO 4: Soulmate deaths', $r$-- PASSO 3c: Huntress (one-shot night kill; Bodyguard protects, Priest does not)
  SELECT target_id INTO v_huntress_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'huntress_kill'
  LIMIT 1;

  IF v_huntress_target_id IS NOT NULL
     AND (SELECT is_alive FROM players WHERE id = v_huntress_target_id)
     AND NOT EXISTS (
       SELECT 1 FROM night_actions
       WHERE room_id = p_room_id AND turn_index = v_turn
         AND action_type = 'bodyguard_protect' AND target_id = v_huntress_target_id) THEN
    UPDATE players SET is_alive = false WHERE id = v_huntress_target_id;
    SELECT name, role INTO v_huntress_target_name, v_huntress_target_role FROM players WHERE id = v_huntress_target_id;
    IF v_huntress_target_role = 'hunter' THEN
      v_hunter_killed := true;
      v_hunter_id := v_huntress_target_id;
    END IF;
    IF v_huntress_target_role = 'prince' THEN
      v_prince_died := true;
    END IF;
    v_victims := v_victims || jsonb_build_object(
      'name', v_huntress_target_name,
      'cause', 'cacadora',
      'role', v_huntress_target_role
    );
  END IF;

  -- PASSO 4: Soulmate deaths$r$);
  EXECUTE d;
END
$do$;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
