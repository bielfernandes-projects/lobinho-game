-- Ghost, two ways:
--  1) Card `ghost` (village, +2): the holder is programmed to die on night 1 (resolve_night, turn 1),
--     then sees every player's role and writes one letter per day.
--  2) Variant (rooms.ghost_enabled, used only when no ghost card is in the room): the FIRST player to die
--     becomes the Ghost, keeps their team and writes one letter per day (no role vision).
-- game_state.ghost_id marks who the Ghost is for the current game.

CREATE OR REPLACE FUNCTION public.__patch(def TEXT, anchor TEXT, repl TEXT, expected INT DEFAULT 1)
RETURNS TEXT LANGUAGE plpgsql AS $f$
BEGIN
  IF array_length(string_to_array(def, anchor), 1) - 1 <> expected THEN
    RAISE EXCEPTION 'patch anchor count <> %: %', expected, anchor;
  END IF;
  RETURN replace(def, anchor, repl);
END;
$f$;

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS ghost_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS ghost_id UUID;

CREATE TABLE IF NOT EXISTS ghost_letters (
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  turn_index INT NOT NULL,
  letter TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, turn_index)
);
ALTER TABLE ghost_letters ENABLE ROW LEVEL SECURITY;

DO $do$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'players_role_check';
  ALTER TABLE players DROP CONSTRAINT players_role_check;
  EXECUTE 'ALTER TABLE players ADD CONSTRAINT players_role_check ' ||
    public.__patch(d, '''virginia_wolf''::character varying', '''virginia_wolf''::character varying, ''ghost''::character varying');
END
$do$;

-- Programmed death of the Ghost card on night 1
DO $do$
DECLARE d TEXT;
BEGIN
  d := pg_get_functiondef('public.resolve_night(uuid)'::regprocedure);
  d := public.__patch(d, '-- PASSO 4: Soulmate deaths', $r$-- Ghost card: programmed to die on the first night
  IF v_turn = 1 THEN
    DECLARE
      v_gh_id UUID;
      v_gh_name TEXT;
    BEGIN
      FOR v_gh_id IN
        SELECT id FROM players WHERE room_id = p_room_id AND role = 'ghost' AND is_alive = true
      LOOP
        UPDATE players SET is_alive = false WHERE id = v_gh_id;
        SELECT name INTO v_gh_name FROM players WHERE id = v_gh_id;
        v_victims := v_victims || jsonb_build_object('name', v_gh_name, 'cause', 'fantasma', 'role', 'ghost');
      END LOOP;
    END;
  END IF;

  -- PASSO 4: Soulmate deaths$r$);
  EXECUTE d;
END
$do$;

-- Who becomes the Ghost
CREATE OR REPLACE FUNCTION public.trg_ghost_assign()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_assign BOOLEAN := false;
BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = NEW.room_id AND ghost_id IS NULL) THEN
    IF EXISTS (SELECT 1 FROM players WHERE room_id = NEW.room_id AND role = 'ghost') THEN
      v_assign := (NEW.role = 'ghost');
    ELSE
      v_assign := COALESCE((SELECT ghost_enabled FROM rooms WHERE id = NEW.room_id), false);
    END IF;
  END IF;

  IF v_assign THEN
    UPDATE game_state SET ghost_id = NEW.id WHERE room_id = NEW.room_id;
    DELETE FROM ghost_letters WHERE room_id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ghost_assign ON players;
CREATE TRIGGER trg_ghost_assign
AFTER UPDATE OF is_alive ON players
FOR EACH ROW
WHEN (OLD.is_alive = true AND NEW.is_alive = false AND NEW.role <> 'moderator')
EXECUTE FUNCTION public.trg_ghost_assign();

CREATE OR REPLACE FUNCTION public.get_ghost_state(p_room_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_ghost UUID;
  v_phase TEXT;
  v_turn INT;
  v_me UUID;
  v_am_ghost BOOLEAN;
  v_card BOOLEAN;
BEGIN
  SELECT id INTO v_me FROM players WHERE room_id = p_room_id AND user_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  SELECT ghost_id, current_phase, turn_index INTO v_ghost, v_phase, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_ghost IS NULL THEN
    RETURN jsonb_build_object('active', false);
  END IF;

  v_am_ghost := (v_ghost = v_me);
  SELECT (role = 'ghost') INTO v_card FROM players WHERE id = v_ghost;

  RETURN jsonb_build_object(
    'active', true,
    'am_ghost', v_am_ghost,
    'can_write', v_am_ghost AND v_phase = 'day'
      AND NOT EXISTS (SELECT 1 FROM ghost_letters WHERE room_id = p_room_id AND turn_index = v_turn),
    'letters', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('turn', turn_index, 'letter', letter) ORDER BY turn_index)
      FROM ghost_letters WHERE room_id = p_room_id
    ), '[]'::jsonb),
    'view', CASE WHEN v_am_ghost THEN (
      SELECT jsonb_agg(jsonb_build_object('name', name, 'role', role, 'is_alive', is_alive) ORDER BY name)
      FROM players WHERE room_id = p_room_id AND is_host = false AND role <> 'moderator'
    ) ELSE NULL END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.ghost_write_letter(p_room_id UUID, p_letter TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_turn INT;
  v_phase TEXT;
  v_ghost UUID;
BEGIN
  SELECT turn_index, current_phase, ghost_id INTO v_turn, v_phase, v_ghost
  FROM game_state WHERE room_id = p_room_id;

  IF v_ghost IS NULL OR NOT EXISTS (
    SELECT 1 FROM players WHERE id = v_ghost AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Apenas o Fantasma pode escrever';
  END IF;
  IF v_phase <> 'day' THEN
    RAISE EXCEPTION 'O Fantasma so escreve durante o dia';
  END IF;
  IF p_letter !~ '^[A-Za-z]$' THEN
    RAISE EXCEPTION 'Escreva apenas uma letra';
  END IF;

  INSERT INTO ghost_letters (room_id, turn_index, letter)
  VALUES (p_room_id, v_turn, upper(p_letter));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_ghost_state(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ghost_write_letter(UUID, TEXT) TO authenticated;

DROP FUNCTION public.__patch(TEXT, TEXT, TEXT, INT);
