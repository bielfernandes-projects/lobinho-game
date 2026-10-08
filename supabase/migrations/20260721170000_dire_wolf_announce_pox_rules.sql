-- 1) Dire Wolf dying with its companion during the night shows up in the morning announcement.
-- 2) Old Witch: poxed player is immune (cannot be lynched / shot by Marksman or Hunter);
--    Old Witch cannot pox the same player two nights in a row.

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT, expected INT DEFAULT 1)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> expected THEN
    RAISE EXCEPTION 'patch anchor count <> %: %', expected, anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

-- resolve_night: append companion-linked Dire Wolf deaths to the victims list
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, '-- B21 FIX: Agora sim', $r$-- Dire Wolf dead because its companion died tonight: announce like any other death
  DECLARE
    v_dw RECORD;
  BEGIN
    FOR v_dw IN
      SELECT dw.name AS name
      FROM players dw
      JOIN night_actions na ON na.actor_id = dw.id AND na.action_type = 'dire_wolf_companion'
      JOIN players c ON c.id = na.target_id
      WHERE dw.room_id = p_room_id AND dw.role = 'dire_wolf' AND dw.is_alive = false
        AND c.is_alive = false
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_victims) v WHERE v->>'name' = c.name)
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_victims) v WHERE v->>'name' = dw.name)
    LOOP
      v_victims := v_victims || jsonb_build_object('name', v_dw.name, 'cause', 'companheiro', 'role', 'dire_wolf');
    END LOOP;
  END;

  -- B21 FIX: Agora sim$r$);
  EXECUTE d;
END
$do$;

-- Old Witch: no repeat target on consecutive nights
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'IF v_role <> ''old_witch'' OR p_target_id IS NULL OR p_target_id = v_player_id THEN', $r$IF v_role = 'old_witch' AND EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn - 1
        AND action_type = 'old_witch_pox' AND target_id = p_target_id
    ) THEN
      RAISE EXCEPTION 'Nao pode escolher o mesmo jogador duas noites seguidas';
    END IF;
    IF v_role <> 'old_witch' OR p_target_id IS NULL OR p_target_id = v_player_id THEN$r$);
  EXECUTE d;
END
$do$;

-- Poxed player is out of the village today: cannot be lynched, nor shot by Marksman/Hunter
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.host_execute_accused(uuid)'::regprocedure);
  d := public.__patch(d, 'SELECT martyr_id INTO v_martyr FROM game_state WHERE room_id = p_room_id;', $r$IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = v_accused_id) THEN
      RAISE EXCEPTION 'Acusado esta fora da vila hoje';
    END IF;
    SELECT martyr_id INTO v_martyr FROM game_state WHERE room_id = p_room_id;$r$);
  EXECUTE d;

  d := pg_get_functiondef('public.marksman_shoot(uuid,uuid)'::regprocedure);
  d := regexp_replace(d, '\mBEGIN\M', $r$BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;$r$);
  EXECUTE d;

  d := pg_get_functiondef('public.hunter_retaliate(uuid,uuid)'::regprocedure);
  d := regexp_replace(d, '\mBEGIN\M', $r$BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;$r$);
  EXECUTE d;
END
$do$;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
