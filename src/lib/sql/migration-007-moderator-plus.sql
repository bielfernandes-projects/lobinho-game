-- ============================================================
-- MIGRATION 007: Moderador + Correcoes + Transferencia Host
-- ============================================================

-- ============================================================
-- 1. RPC: start_game (moderador, exclui host do sorteio)
-- ============================================================
CREATE OR REPLACE FUNCTION public.start_game(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_num INT;
  v_n_wolves INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode iniciar a partida';
  END IF;

  -- Forcar host como moderador
  UPDATE players SET role = 'moderator'
  WHERE room_id = p_room_id AND is_host = true;

  -- Contar apenas jogadores NAO host para distribuicao
  SELECT COUNT(*) INTO v_num
  FROM players WHERE room_id = p_room_id AND is_host = false;

  IF v_num < 4 THEN
    RAISE EXCEPTION 'Minimo de 4 jogadores (excluindo o mestre) para iniciar';
  END IF;

  v_n_wolves := GREATEST(1, floor(v_num / 3.0)::INT);

  -- Distribuir papeis apenas entre nao-host
  WITH shuffled AS (
    SELECT id, row_number() OVER (ORDER BY random()) - 1 AS rn
    FROM players
    WHERE room_id = p_room_id AND is_host = false
  )
  UPDATE players p
  SET role = CASE
    WHEN s.rn < v_n_wolves THEN 'werewolf'
    WHEN s.rn = v_n_wolves THEN 'seer'
    WHEN s.rn = v_n_wolves + 1 THEN 'witch'
    ELSE 'villager'
  END
  FROM shuffled s
  WHERE p.id = s.id;

  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  INSERT INTO game_state (room_id, current_phase, turn_index)
  VALUES (p_room_id, 'card_reveal', 0)
  ON CONFLICT (room_id) DO UPDATE
    SET current_phase = 'card_reveal', turn_index = 0, phase_started_at = now();
END;
$$;

-- ============================================================
-- 2. RPC: check_game_over (corrige v_non_wolves + race cond.)
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phase TEXT;
  v_wolves INT;
  v_non_wolves INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  -- Prevencao de race condition: so avaliar durante jogo ativo
  SELECT current_phase INTO v_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_phase IS NULL OR v_phase IN ('waiting', 'card_reveal', 'ended') THEN
    RETURN jsonb_build_object('game_over', false, 'skipped', true);
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = p_room_id;

  IF v_wolves = 0 THEN
    v_winner := 'villagers_win';
    v_winner_display := 'Aldeoes Venceram';
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
    UPDATE game_state
    SET current_phase = 'ended',
        last_event = jsonb_build_object('winner', 'villagers_win')
    WHERE room_id = p_room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    v_winner := 'wolves_win';
    v_winner_display := 'Lobisomens Venceram';
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
    UPDATE game_state
    SET current_phase = 'ended',
        last_event = jsonb_build_object('winner', 'wolves_win')
    WHERE room_id = p_room_id;
  END IF;

  IF v_winner IS NULL THEN
    RETURN jsonb_build_object('game_over', false);
  END IF;

  RETURN jsonb_build_object('game_over', true, 'winner', v_winner, 'display', v_winner_display);
END;
$$;

-- ============================================================
-- 3. TRIGGER: trg_check_game_over (corrige + race cond.)
-- ============================================================
DROP TRIGGER IF EXISTS trg_check_game_over ON players;
DROP FUNCTION IF EXISTS public.trg_check_game_over() CASCADE;
DROP FUNCTION IF EXISTS public.check_game_over_trigger() CASCADE;

CREATE OR REPLACE FUNCTION public.trg_check_game_over()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phase TEXT;
  v_wolves INT;
  v_non_wolves INT;
BEGIN
  -- Prevencao de race condition
  SELECT current_phase INTO v_phase
  FROM game_state WHERE room_id = NEW.room_id;

  IF v_phase IS NULL OR v_phase IN ('waiting', 'card_reveal') THEN
    RETURN NEW;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = NEW.room_id;

  IF v_wolves = 0 THEN
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = NEW.room_id;
    UPDATE game_state SET current_phase = 'ended',
      last_event = jsonb_build_object('winner', 'villagers_win')
    WHERE room_id = NEW.room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = NEW.room_id;
    UPDATE game_state SET current_phase = 'ended',
      last_event = jsonb_build_object('winner', 'wolves_win')
    WHERE room_id = NEW.room_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_check_game_over
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_game_over();

-- ============================================================
-- 4. RPC: transfer_host (troca host entre jogadores)
-- ============================================================
CREATE OR REPLACE FUNCTION public.transfer_host(p_room_id UUID, p_new_host_player_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_host_id UUID;
  v_new_host_user_id UUID;
  v_room_status TEXT;
BEGIN
  -- Verificar se quem chamou e o host atual
  SELECT id INTO v_current_host_id
  FROM players
  WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true;

  IF v_current_host_id IS NULL THEN
    RAISE EXCEPTION 'Somente o host atual pode transferir o cargo';
  END IF;

  -- Verificar se o novo host existe na sala
  SELECT user_id INTO v_new_host_user_id
  FROM players
  WHERE id = p_new_host_player_id AND room_id = p_room_id;

  IF v_new_host_user_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  -- Nao permitir transferencia durante partida
  SELECT status INTO v_room_status FROM rooms WHERE id = p_room_id;
  IF v_room_status = 'playing' THEN
    RAISE EXCEPTION 'Nao e possivel transferir o cargo durante uma partida';
  END IF;

  -- Transferir
  UPDATE players SET is_host = false WHERE id = v_current_host_id;
  UPDATE players SET is_host = true WHERE id = p_new_host_player_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- 5. Atualizar RPC: resolve_day_vote (chama check_game_over)
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
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  v_threshold := floor(v_alive / 2) + 1;

  SELECT target_id, COUNT(*) AS cnt INTO v_target_id, v_vote_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  ORDER BY cnt DESC
  LIMIT 1;

  SELECT COUNT(*) INTO v_tie_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  HAVING COUNT(*) = v_vote_count;

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

  -- Verificar fim de jogo apos lynch
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- ============================================================
-- 6. Atualizar RPC: resolve_night (chama check_game_over)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_wolf_target_id UUID;
  v_wolf_target_name TEXT;
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_victims JSONB;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT target_id INTO v_wolf_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  GROUP BY target_id
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
  END IF;

  v_victims := '[]'::JSONB;
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno');
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  -- Verificar fim de jogo apos mortes noturnas
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'victims', v_victims, 'game_over', v_game_over);
END;
$$;
