-- Lot 3: Game over conditions for soulmates_win and cult_win
-- 1. check_game_over — add soulmates (P1) and cult (P2) before existing logic
-- 2. trg_check_game_over — same addition
-- 3. host_end_game — handle new winner types
-- 4. execute_night_action — add cult_convert branch
-- 5. get_revealed_players — include in_cult and soulmate_id columns

-- ============================================================
-- 1. Updated check_game_over
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- PRIORITY 1: Soulmates win (exactly 2 alive non-moderator players AND they are soulmates)
  SELECT COUNT(*) FILTER (WHERE is_alive = true AND role != 'moderator')
  INTO v_alive_count
  FROM players WHERE room_id = p_room_id;

  IF v_alive_count = 2 THEN
    IF EXISTS (
      SELECT 1 FROM players a
      JOIN players b ON b.id = a.soulmate_id
      WHERE a.room_id = p_room_id
        AND a.is_alive = true
        AND b.is_alive = true
        AND a.role != 'moderator'
        AND b.role != 'moderator'
        AND b.soulmate_id = a.id
    ) THEN
      UPDATE game_state SET winner = 'soulmates_win' WHERE room_id = p_room_id;
      RETURN jsonb_build_object('game_over', true, 'winner', 'soulmates_win');
    END IF;
  END IF;

  -- PRIORITY 2: Cult win (leader alive, no alive non-leader non-moderator has in_cult = false)
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

  -- PRIORITY 3: tanner win check (lynch victim must be the tanner)
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = p_room_id;
  IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
    SELECT 1 FROM players
    WHERE id = (v_last_event->>'victim_id')::UUID
      AND role = 'tanner'
      AND is_alive = false
  ) THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = p_room_id;
    RETURN jsonb_build_object('game_over', true, 'winner', 'tanner_win', 'display', 'Curtidor Venceu');
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = p_room_id;

  IF v_wolves = 0 THEN
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
$$;

-- ============================================================
-- 2. Updated trg_check_game_over
-- ============================================================
DROP TRIGGER IF EXISTS trg_check_game_over ON players;
CREATE OR REPLACE FUNCTION public.trg_check_game_over()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_alive_count INT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = NEW.room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NEW;
  END IF;

  -- PRIORITY 1: Soulmates win
  SELECT COUNT(*) FILTER (WHERE is_alive = true AND role != 'moderator')
  INTO v_alive_count
  FROM players WHERE room_id = NEW.room_id;

  IF v_alive_count = 2 THEN
    IF EXISTS (
      SELECT 1 FROM players a
      JOIN players b ON b.id = a.soulmate_id
      WHERE a.room_id = NEW.room_id
        AND a.is_alive = true
        AND b.is_alive = true
        AND a.role != 'moderator'
        AND b.role != 'moderator'
        AND b.soulmate_id = a.id
    ) THEN
      UPDATE game_state SET winner = 'soulmates_win' WHERE room_id = NEW.room_id;
      RETURN NEW;
    END IF;
  END IF;

  -- PRIORITY 2: Cult win
  IF EXISTS (
    SELECT 1 FROM players
    WHERE room_id = NEW.room_id AND is_alive = true AND role = 'cult_leader'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM players
      WHERE room_id = NEW.room_id AND is_alive = true
        AND role NOT IN ('moderator', 'cult_leader')
        AND in_cult = false
    ) THEN
      UPDATE game_state SET winner = 'cult_win' WHERE room_id = NEW.room_id;
      RETURN NEW;
    END IF;
  END IF;

  -- PRIORITY 3: tanner win
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = NEW.room_id;
  IF NEW.role = 'tanner'
     AND NEW.is_alive = false
     AND v_last_event->>'event_type' = 'lynch'
     AND v_last_event->>'victim_id' = NEW.id::TEXT
  THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = NEW.room_id;
    RETURN NEW;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = NEW.room_id;

  IF v_wolves = 0 THEN
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = NEW.room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = NEW.room_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_check_game_over
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_game_over();

-- ============================================================
-- 3. Updated host_end_game — support soulmates_win and cult_win
-- ============================================================
CREATE OR REPLACE FUNCTION public.host_end_game(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode encerrar o jogo';
  END IF;

  SELECT winner INTO v_winner FROM game_state WHERE room_id = p_room_id;

  IF v_winner = 'villagers_win' THEN
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
  ELSIF v_winner = 'wolves_win' THEN
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
  ELSIF v_winner = 'tanner_win' THEN
    UPDATE rooms SET status = 'finished_tanner_win' WHERE id = p_room_id;
  ELSIF v_winner = 'soulmates_win' THEN
    UPDATE rooms SET status = 'finished_soulmates_win' WHERE id = p_room_id;
  ELSIF v_winner = 'cult_win' THEN
    UPDATE rooms SET status = 'finished_cult_win' WHERE id = p_room_id;
  ELSE
    RAISE EXCEPTION 'Nenhum vencedor definido';
  END IF;

  UPDATE game_state SET current_phase = 'ended' WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'winner', v_winner);
END;
$$;

-- ============================================================
-- 4. Updated execute_night_action — add cult_convert branch
-- ============================================================
CREATE OR REPLACE FUNCTION public.execute_night_action(p_room_id uuid, p_action_type text, p_target_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn INT;
  v_player_id UUID;
  v_role TEXT;
  v_alive BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
  v_result BOOLEAN;
  v_wolves_resolved BOOLEAN;
  v_target_role TEXT;
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
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch') OR
     (p_action_type = 'priest_bless' AND v_role != 'priest') OR
     (p_action_type = 'bodyguard_protect' AND v_role != 'bodyguard') OR
     (p_action_type = 'aura_investigate' AND v_role != 'aura_seer') OR
     (p_action_type = 'cult_convert' AND v_role != 'cult_leader')
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
  ELSIF p_action_type = 'priest_bless' THEN
    UPDATE players SET is_blessed = true WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'bodyguard_protect' THEN
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'aura_investigate' THEN
    SELECT role INTO v_target_role
    FROM players WHERE id = p_target_id;

    v_result := (v_target_role NOT IN ('villager', 'werewolf'));

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('has_special_role', v_result);
  ELSIF p_action_type = 'cult_convert' THEN
    UPDATE players SET in_cult = true WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role IN ('werewolf', 'lycan') INTO v_result
    FROM players WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('is_werewolf', v_result);
  END IF;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ============================================================
-- 5. Updated get_revealed_players — include in_cult and soulmate_id
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_revealed_players(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'role', p.role,
      'in_cult', p.in_cult,
      'soulmate_id', p.soulmate_id
    )
    ORDER BY p.name ASC
  ) INTO v_result
  FROM players p
  WHERE p.room_id = p_room_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
