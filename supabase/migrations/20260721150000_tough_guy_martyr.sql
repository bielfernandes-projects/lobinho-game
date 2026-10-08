-- Tough Guy: wolf attack does not kill him that night; he dies on the NEXT night's resolve
--            (marker row in night_actions: action_type 'tough_guy_doomed').
-- Martyr: after the lynch vote, may volunteer (game_state.martyr_id); host_execute_accused
--         then kills the Martyr instead of the accused.
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

ALTER TABLE game_state ADD COLUMN IF NOT EXISTS martyr_id UUID;

DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''huntress''::character varying', '''huntress''::character varying, ''tough_guy''::character varying, ''martyr''::character varying');

  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'night_actions_action_type_check';
  ALTER TABLE night_actions DROP CONSTRAINT night_actions_action_type_check;
  EXECUTE 'ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check ' ||
    public.__patch(d, '''huntress_kill''::text', '''huntress_kill''::text, ''tough_guy_doomed''::text');
END
$do$;

CREATE OR REPLACE FUNCTION public.martyr_volunteer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_player_id UUID;
  v_accused UUID;
  v_step TEXT;
BEGIN
  SELECT id INTO v_player_id FROM players
  WHERE room_id = p_room_id AND user_id = auth.uid() AND role = 'martyr' AND is_alive = true;
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Apenas o Martir vivo pode se oferecer';
  END IF;

  SELECT current_accused_id, day_step INTO v_accused, v_step FROM game_state WHERE room_id = p_room_id;
  IF v_step <> 'reveal' OR v_accused IS NULL OR v_accused = v_player_id THEN
    RAISE EXCEPTION 'Nao e possivel se oferecer agora';
  END IF;

  UPDATE game_state SET martyr_id = v_player_id WHERE room_id = p_room_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.martyr_volunteer(UUID) TO authenticated;

DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.host_execute_accused(uuid)'::regprocedure);
  d := public.__patch(d, 'SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;', $r$DECLARE
    v_martyr UUID;
  BEGIN
    SELECT martyr_id INTO v_martyr FROM game_state WHERE room_id = p_room_id;
    IF v_martyr IS NOT NULL AND EXISTS (
      SELECT 1 FROM players WHERE id = v_martyr AND is_alive = true AND role = 'martyr'
    ) THEN
      v_accused_id := v_martyr;
    END IF;
    UPDATE game_state SET martyr_id = NULL WHERE room_id = p_room_id;
  END;
  SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;$r$);
  EXECUTE d;
END
$do$;

DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, '-- PASSO 2: Lobisomens (target 1)', $r$-- Tough Guy: wolf attack is deferred to the next night (unless protected)
  IF v_wolf_target_id IS NOT NULL
     AND (SELECT role FROM players WHERE id = v_wolf_target_id) = 'tough_guy' THEN
    IF COALESCE((SELECT is_blessed FROM players WHERE id = v_wolf_target_id), false) THEN
      UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
    ELSIF NOT EXISTS (
        SELECT 1 FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save')
      AND NOT EXISTS (
        SELECT 1 FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn
          AND action_type = 'bodyguard_protect' AND target_id = v_wolf_target_id) THEN
      INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
      VALUES (p_room_id, v_turn, v_wolf_target_id, 'tough_guy_doomed', v_wolf_target_id)
      ON CONFLICT DO NOTHING;
    END IF;
    v_wolf_target_id := NULL;
  END IF;

  -- PASSO 2: Lobisomens (target 1)$r$);
  d := public.__patch(d, '-- PASSO 4: Soulmate deaths', $r$-- Tough Guy: doomed on a PREVIOUS night dies now
  DECLARE
    v_tg_id UUID;
    v_tg_name TEXT;
  BEGIN
    FOR v_tg_id IN
      SELECT na.target_id FROM night_actions na
      JOIN players p ON p.id = na.target_id
      WHERE na.room_id = p_room_id AND na.action_type = 'tough_guy_doomed'
        AND na.turn_index < v_turn AND p.is_alive = true AND p.role = 'tough_guy'
    LOOP
      UPDATE players SET is_alive = false WHERE id = v_tg_id;
      SELECT name INTO v_tg_name FROM players WHERE id = v_tg_id;
      v_victims := v_victims || jsonb_build_object('name', v_tg_name, 'cause', 'lobisomem', 'role', 'tough_guy');
    END LOOP;
  END;

  -- PASSO 4: Soulmate deaths$r$);
  EXECUTE d;
END
$do$;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
