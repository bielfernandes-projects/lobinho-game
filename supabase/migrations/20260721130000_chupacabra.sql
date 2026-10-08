-- Chupacabra (Chupacu): independent role. Each night picks a player: dies only if
-- werewolf/wolf_cub/alpha_wolf/lone_wolf (or ANY player once all wolves were dead at
-- night start). No feedback to the Chupacabra. Wins when last alive (or 1v1).
-- Patches existing functions in place (anchor replace) so unrelated logic is untouched.

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> 1 THEN
    RAISE EXCEPTION 'patch anchor not found exactly once: %', anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

-- ── constraints ─────────────────────────────────────────────────────
DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''doppelganger''::character varying', '''doppelganger''::character varying, ''chupacabra''::character varying');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'night_actions_action_type_check';
  ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  EXECUTE 'ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check ' ||
    public.__patch(d, '''doppelganger_select''::text', '''doppelganger_select''::text, ''chupacabra_kill''::text');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'rooms_status_check';
  ALTER TABLE rooms DROP CONSTRAINT rooms_status_check;
  EXECUTE 'ALTER TABLE rooms ADD CONSTRAINT rooms_status_check ' ||
    public.__patch(d, '''finished_lone_wolf_win''::text', '''finished_lone_wolf_win''::text, ''finished_chupacabra_win''::text');
END
$do$;

-- ── check_game_over ─────────────────────────────────────────────────
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.check_game_over(uuid)'::regprocedure);
  d := public.__patch(d, '-- PRIORITY 1: Soulmates win', $r$-- PRIORITY 0b: Chupacabra last alive
IF v_alive_count = 1 AND EXISTS (
SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'chupacabra'
) THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'chupacabra_win', 'display', 'Chupacu Venceu');
END IF;
-- PRIORITY 1: Soulmates win$r$);
  d := public.__patch(d, 'v_winner := ''villagers_win'';', $r$IF EXISTS (
SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'chupacabra'
) THEN
IF v_alive_count <= 2 THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'chupacabra_win', 'display', 'Chupacu Venceu');
END IF;
RETURN jsonb_build_object('game_over', false);
END IF;
v_winner := 'villagers_win';$r$);
  EXECUTE d;

  d := pg_get_functiondef('public.trg_check_game_over()'::regprocedure);
  d := public.__patch(d, '-- PRIORITY 1: Soulmates win', $r$-- PRIORITY 0b: Chupacabra last alive
IF v_alive_count = 1 AND EXISTS (
SELECT 1 FROM players WHERE room_id = NEW.room_id AND is_alive = true AND role = 'chupacabra'
) THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = NEW.room_id;
RETURN NEW;
END IF;
-- PRIORITY 1: Soulmates win$r$);
  d := public.__patch(d, 'UPDATE game_state SET winner = ''villagers_win'' WHERE room_id = NEW.room_id;', $r$IF EXISTS (
SELECT 1 FROM players WHERE room_id = NEW.room_id AND is_alive = true AND role = 'chupacabra'
) THEN
IF v_alive_count <= 2 THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = NEW.room_id;
END IF;
RETURN NEW;
END IF;
UPDATE game_state SET winner = 'villagers_win' WHERE room_id = NEW.room_id;$r$);
  EXECUTE d;
END
$do$;

-- ── host_end_game ───────────────────────────────────────────────────
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.host_end_game(uuid)'::regprocedure);
  d := public.__patch(d, 'ELSIF v_winner = ''cult_win'' THEN', $r$ELSIF v_winner = 'chupacabra_win' THEN
    UPDATE rooms SET status = 'finished_chupacabra_win' WHERE id = p_room_id;
  ELSIF v_winner = 'cult_win' THEN$r$);
  EXECUTE d;
END
$do$;

-- ── execute_night_action: chupacabra_kill (no feedback) ─────────────
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'ELSIF p_action_type = ''priest_bless'' THEN', $r$ELSIF p_action_type = 'chupacabra_kill' THEN
    IF v_role <> 'chupacabra' THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'priest_bless' THEN$r$);
  EXECUTE d;
END
$do$;

-- ── resolve_night: chupacabra kill step ─────────────────────────────
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, 'v_doppelganger_new_role_name TEXT;', $r$v_doppelganger_new_role_name TEXT;
  v_chupa_target_id UUID;
  v_chupa_target_name TEXT;
  v_chupa_target_role TEXT;
  v_wolves_alive_at_start INT;$r$);
  d := public.__patch(d, '-- PASSO 1: Padre', $r$-- Chupacabra: were any wolves alive when the night started?
  SELECT COUNT(*) INTO v_wolves_alive_at_start FROM players
  WHERE room_id = p_room_id AND is_alive = true
    AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf');

  -- PASSO 1: Padre$r$);
  d := public.__patch(d, '-- PASSO 4: Soulmate deaths', $r$-- PASSO 3b: Chupacabra (kills only wolves, or anyone once all wolves were dead)
  SELECT target_id INTO v_chupa_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'chupacabra_kill'
  LIMIT 1;

  IF v_chupa_target_id IS NOT NULL
     AND (SELECT is_alive FROM players WHERE id = v_chupa_target_id) THEN
    SELECT name, role INTO v_chupa_target_name, v_chupa_target_role FROM players WHERE id = v_chupa_target_id;
    IF v_wolves_alive_at_start = 0
       OR v_chupa_target_role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf') THEN
      UPDATE players SET is_alive = false WHERE id = v_chupa_target_id;
      IF v_chupa_target_role = 'hunter' THEN
        v_hunter_killed := true;
        v_hunter_id := v_chupa_target_id;
      END IF;
      IF v_chupa_target_role = 'prince' THEN
        v_prince_died := true;
      END IF;
      v_victims := v_victims || jsonb_build_object(
        'name', v_chupa_target_name,
        'cause', 'chupacabra',
        'role', v_chupa_target_role
      );
    END IF;
  END IF;

  -- PASSO 4: Soulmate deaths$r$);
  EXECUTE d;
END
$do$;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT);
