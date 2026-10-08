-- Win conditions in ONE place. Pure: reads the room, writes nothing.
-- Returns the winner key or NULL when the game goes on. Priority order:
--   lone_wolf (last alive) > chupacabra (last alive) > soulmates > cult > tanner >
--   (no wolf-team alive: lone wolf 1v1 > chupacabra 1v1 > villagers) > wolves parity.
-- Callers: check_game_over (RPC use) and trg_check_game_over (trigger on players.is_alive).
CREATE OR REPLACE FUNCTION public.compute_winner(p_room_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_alive_count INT;
  v_lone_wolf BOOLEAN;
  v_chupacabra BOOLEAN;
BEGIN
  SELECT turn_index, current_phase, last_event INTO v_turn_index, v_phase, v_last_event
  FROM game_state WHERE room_id = p_room_id;
  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NULL;
  END IF;

  SELECT COUNT(*) FILTER (WHERE is_alive AND role <> 'moderator'),
         COUNT(*) FILTER (WHERE is_alive AND role = ANY(wolf_team_roles())),
         COUNT(*) FILTER (WHERE is_alive AND role <> ALL(wolf_team_roles()) AND role <> 'moderator'),
         COALESCE(BOOL_OR(is_alive AND role = 'lone_wolf'), false),
         COALESCE(BOOL_OR(is_alive AND role = 'chupacabra'), false)
  INTO v_alive_count, v_wolves, v_non_wolves, v_lone_wolf, v_chupacabra
  FROM players WHERE room_id = p_room_id;

  -- Last one standing
  IF v_alive_count = 1 AND v_lone_wolf THEN RETURN 'lone_wolf_win'; END IF;
  IF v_alive_count = 1 AND v_chupacabra THEN RETURN 'chupacabra_win'; END IF;

  -- Soulmates: exactly the two lovers left
  IF v_alive_count = 2 AND EXISTS (
    SELECT 1 FROM players a JOIN players b ON b.id = a.soulmate_id
    WHERE a.room_id = p_room_id AND a.is_alive AND b.is_alive
      AND a.role <> 'moderator' AND b.role <> 'moderator' AND b.soulmate_id = a.id
  ) THEN RETURN 'soulmates_win'; END IF;

  -- Cult: every other living player converted
  IF EXISTS (SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive AND role = 'cult_leader')
     AND NOT EXISTS (
       SELECT 1 FROM players
       WHERE room_id = p_room_id AND is_alive
         AND role NOT IN ('moderator', 'cult_leader') AND in_cult = false
     ) THEN RETURN 'cult_win'; END IF;

  -- Tanner: lynched
  IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
    SELECT 1 FROM players
    WHERE id = (v_last_event->>'victim_id')::UUID AND role = 'tanner' AND is_alive = false
  ) THEN RETURN 'tanner_win'; END IF;

  -- Wolf team vs the rest
  IF v_wolves = 0 THEN
    IF v_lone_wolf THEN
      IF v_alive_count <= 2 THEN RETURN 'lone_wolf_win'; END IF;
      RETURN NULL;
    END IF;
    IF v_chupacabra THEN
      IF v_alive_count <= 2 THEN RETURN 'chupacabra_win'; END IF;
      RETURN NULL;
    END IF;
    RETURN 'villagers_win';
  ELSIF v_wolves >= v_non_wolves THEN
    RETURN 'wolves_win';
  END IF;

  RETURN NULL;
END;
$function$
