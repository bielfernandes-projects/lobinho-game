-- ============================================================
-- MIGRATION 013: Correções de ambiguidade de RPC e falso empate
--
-- 1. submit_night_action: DROP de todas as assinaturas conflitantes
--    (VARCHAR vs TEXT) e recria com TEXT
-- 2. resolve_day_vote: subquery correta para contagem de empates
--    (evita falso positivo quando COUNT(*) retorna v_vote_count
--     em vez do número de alvos empatados)
-- ============================================================

-- ============================================================
-- FIX 1: submit_night_action — ambiguidade VARCHAR vs TEXT
-- ============================================================
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, VARCHAR, UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, VARCHAR);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.submit_night_action(
  p_room_id UUID,
  p_action_type TEXT,
  p_target_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_player_id UUID;
  v_role TEXT;
  v_alive BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
  v_result BOOLEAN;
  v_wolves_resolved BOOLEAN;
BEGIN
  SELECT id, role, is_alive,
         COALESCE(has_used_life_potion, false),
         COALESCE(has_used_death_potion, false)
    INTO v_player_id, v_role, v_alive, v_used_life, v_used_death
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos nao podem agir';
  END IF;

  IF (p_action_type = 'werewolf_kill' AND v_role != 'werewolf') OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') OR
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch')
  THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  SELECT turn_index INTO v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF p_action_type IN ('witch_save', 'witch_poison') THEN
    SELECT COALESCE(wolves_resolved, false) INTO v_wolves_resolved
    FROM game_state WHERE room_id = p_room_id;
    IF NOT v_wolves_resolved THEN
      RAISE EXCEPTION 'Aguarde os lobos decidirem primeiro';
    END IF;
  END IF;

  IF p_action_type = 'witch_save' AND v_used_life THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da vida';
  END IF;

  IF p_action_type = 'witch_poison' AND v_used_death THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da morte';
  END IF;

  IF p_action_type = 'witch_save' THEN
    UPDATE players SET has_used_life_potion = true WHERE id = v_player_id;
  ELSIF p_action_type = 'witch_poison' THEN
    UPDATE players SET has_used_death_potion = true WHERE id = v_player_id;
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role = 'werewolf' INTO v_result
    FROM players WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result);
  ELSE
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id);
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    RETURN jsonb_build_object('is_werewolf', v_result);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- FIX 2: resolve_day_vote — subquery correta para contagem de
--         empates (evita falso positivo)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_day_vote(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_target_id UUID;
  v_vote_count INT;
  v_tie_count INT;
  v_threshold INT;
  v_alive INT;
  v_victim_name TEXT;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a votacao';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT COUNT(*) INTO v_alive
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role != 'moderator';

  v_threshold := floor(v_alive / 2) + 1;

  SELECT target_id, COUNT(*) AS cnt INTO v_target_id, v_vote_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  ORDER BY cnt DESC
  LIMIT 1;

  SELECT COUNT(*) INTO v_tie_count FROM (
    SELECT target_id FROM votes
    WHERE room_id = p_room_id AND turn_index = v_turn
    GROUP BY target_id
    HAVING COUNT(*) = v_vote_count
  ) AS ties;

  IF v_vote_count < v_threshold OR v_tie_count > 1 THEN
    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        last_event = jsonb_build_object('type', 'vote_result', 'event_type', 'vote_tie'),
        last_vote_result = jsonb_build_object(
          'type', 'vote_tie',
          'message', 'A vila nao chegou a um consenso. Ninguem foi linchado.'
        )
    WHERE room_id = p_room_id;
  ELSE
    SELECT name INTO v_victim_name FROM players WHERE id = v_target_id;
    UPDATE players SET is_alive = false WHERE id = v_target_id;

    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        last_event = jsonb_build_object(
          'type', 'vote_result',
          'event_type', 'lynch',
          'victim_id', v_target_id,
          'victim_name', v_victim_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name
        )
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;
