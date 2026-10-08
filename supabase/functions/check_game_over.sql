CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id uuid)
 RETURNS jsonb
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
v_winner TEXT;
v_winner_display TEXT;
BEGIN
SELECT turn_index, current_phase INTO v_turn_index, v_phase
FROM game_state WHERE room_id = p_room_id;
IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
RETURN jsonb_build_object('game_over', false, 'skipped', true);
END IF;
SELECT COUNT(*) FILTER (WHERE is_alive = true AND role != 'moderator')
INTO v_alive_count
FROM players WHERE room_id = p_room_id;
-- PRIORITY 0: Lone Wolf win
IF v_alive_count = 1 THEN
IF EXISTS (
SELECT 1 FROM players
WHERE room_id = p_room_id AND is_alive = true AND role = 'lone_wolf'
) THEN
UPDATE game_state SET winner = 'lone_wolf_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'lone_wolf_win', 'display', 'Lobo Solitario Venceu');
END IF;
END IF;
-- PRIORITY 0b: Chupacabra last alive
IF v_alive_count = 1 AND EXISTS (
SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'chupacabra'
) THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'chupacabra_win', 'display', 'Chupacu Venceu');
END IF;
-- PRIORITY 1: Soulmates win
IF v_alive_count = 2 THEN
IF EXISTS (
SELECT 1 FROM players a
JOIN players b ON b.id = a.soulmate_id
WHERE a.room_id = p_room_id
AND a.is_alive = true AND b.is_alive = true
AND a.role != 'moderator' AND b.role != 'moderator'
AND b.soulmate_id = a.id
) THEN
UPDATE game_state SET winner = 'soulmates_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'soulmates_win');
END IF;
END IF;
-- PRIORITY 2: Cult win
IF EXISTS (
SELECT 1 FROM players
WHERE room_id = p_room_id AND is_alive = true AND role = 'cult_leader'
) THEN
IF NOT EXISTS (
SELECT 1 FROM players
WHERE room_id = p_room_id AND is_alive = true
AND role NOT IN ('moderator', 'cult_leader')
AND in_cult = false
) THEN
UPDATE game_state SET winner = 'cult_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'cult_win');
END IF;
END IF;
-- PRIORITY 3: tanner win
SELECT last_event INTO v_last_event FROM game_state WHERE room_id = p_room_id;
IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
SELECT 1 FROM players
WHERE id = (v_last_event->>'victim_id')::UUID
AND role = 'tanner' AND is_alive = false
) THEN
UPDATE game_state SET winner = 'tanner_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'tanner_win', 'display', 'Curtidor Venceu');
END IF;
-- Standard wolf/village check
SELECT
COUNT(*) FILTER (WHERE is_alive = true AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'sorceress', 'minion')),
COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'sorceress', 'minion', 'moderator'))
INTO v_wolves, v_non_wolves
FROM players WHERE room_id = p_room_id;
IF v_wolves = 0 THEN
IF EXISTS (
SELECT 1 FROM players
WHERE room_id = p_room_id AND is_alive = true AND role = 'lone_wolf'
) THEN
IF v_alive_count <= 2 THEN
UPDATE game_state SET winner = 'lone_wolf_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'lone_wolf_win', 'display', 'Lobo Solitario Venceu');
END IF;
RETURN jsonb_build_object('game_over', false);
END IF;
IF EXISTS (
SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'chupacabra'
) THEN
IF v_alive_count <= 2 THEN
UPDATE game_state SET winner = 'chupacabra_win' WHERE room_id = p_room_id;
RETURN jsonb_build_object('game_over', true, 'winner', 'chupacabra_win', 'display', 'Chupacu Venceu');
END IF;
RETURN jsonb_build_object('game_over', false);
END IF;
v_winner := 'villagers_win';
v_winner_display := 'Aldeoes Venceram';
UPDATE game_state SET winner = 'villagers_win' WHERE room_id = p_room_id;
ELSIF v_wolves >= v_non_wolves THEN
v_winner := 'wolves_win';
v_winner_display := 'Lobisomens Venceram';
UPDATE game_state SET winner = 'wolves_win' WHERE room_id = p_room_id;
END IF;
IF v_winner IS NULL THEN
RETURN jsonb_build_object('game_over', false);
END IF;
RETURN jsonb_build_object('game_over', true, 'winner', v_winner, 'display', v_winner_display);
END;
$function$
