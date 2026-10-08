-- Drunk: the host sets a hidden "reserve" role (rooms.drunk_hidden_role) at scenario time.
-- The Drunk wakes on night 3 and sobers up into it (drunk_sober_up); until then the Seer / Aura Seer
-- (and the Sorceress search) see the hidden role instead of "drunk".

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT, expected INT DEFAULT 1)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> expected THEN
    RAISE EXCEPTION 'patch anchor count <> %: %', expected, anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS drunk_hidden_role TEXT;

DROP FUNCTION IF EXISTS public.host_reveal_drunk(UUID, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.drunk_sober_up(p_room_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_player_id UUID;
  v_turn INT;
  v_hidden TEXT;
BEGIN
  SELECT id INTO v_player_id FROM players
  WHERE room_id = p_room_id AND user_id = auth.uid() AND role = 'drunk' AND is_alive = true;
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Apenas o Bebado vivo pode usar isto';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;
  IF v_turn < 3 THEN
    RAISE EXCEPTION 'A bebedeira ainda nao passou';
  END IF;

  SELECT COALESCE(drunk_hidden_role, 'villager') INTO v_hidden FROM rooms WHERE id = p_room_id;
  UPDATE players SET role = v_hidden WHERE id = v_player_id;
  RETURN jsonb_build_object('role', v_hidden);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.drunk_sober_up(UUID) TO authenticated;

DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.execute_night_action(uuid,text,uuid)'::regprocedure);
  d := public.__patch(d, 'SELECT role IN (''werewolf'', ''wolf_cub'', ''alpha_wolf'', ''dire_wolf'', ''lone_wolf'', ''lycan'') INTO v_result',
    'SELECT (CASE WHEN role = ''drunk'' THEN COALESCE((SELECT drunk_hidden_role FROM rooms WHERE id = p_room_id), role) ELSE role END) IN (''werewolf'', ''wolf_cub'', ''alpha_wolf'', ''dire_wolf'', ''lone_wolf'', ''lycan'') INTO v_result');
  d := public.__patch(d, 'SELECT role INTO v_target_role FROM players WHERE id = p_target_id;',
    'SELECT (CASE WHEN role = ''drunk'' THEN COALESCE((SELECT drunk_hidden_role FROM rooms WHERE id = p_room_id), role) ELSE role END) INTO v_target_role FROM players WHERE id = p_target_id;', 2);
  EXECUTE d;
END
$do$;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
