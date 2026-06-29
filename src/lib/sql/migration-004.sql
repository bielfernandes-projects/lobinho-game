-- ============================================================
-- MIGRATION 004: bruxa + endgame + correção votação (empate)
-- ============================================================

-- ============================================================
-- 1. FLAGS DA BRUXA na tabela players
-- ============================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_used_life_potion BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_used_death_potion BOOLEAN NOT NULL DEFAULT false;

-- ============================================================
-- 2. wolves_resolved + last_vote_result no game_state
-- ============================================================
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS wolves_resolved BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS last_vote_result JSONB;

-- ============================================================
-- 3. ATUALIZAR CONSTRAINT da night_actions (witch_save, witch_poison)
-- ============================================================
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN ('werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison'));

-- ============================================================
-- 4. ATUALIZAR CONSTRAINT do rooms.status (finished_*_win)
-- ============================================================
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_status_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_status_check
  CHECK (status IN ('waiting', 'playing', 'finished', 'finished_villagers_win', 'finished_wolves_win'));

-- ============================================================
-- 5. RPC: submit_night_action (agora suporta bruxa)
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_night_action(
  p_room_id UUID,
  p_action_type TEXT,
  p_target_id UUID
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
  v_result BOOLEAN;
  v_current_phase TEXT;
  v_wolves_resolved BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
BEGIN
  SELECT id, role, is_alive, has_used_life_potion, has_used_death_potion
    INTO v_player_id, v_role, v_alive, v_used_life, v_used_death
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogador morto nao pode agir';
  END IF;

  -- Validar role x action_type
  IF (p_action_type = 'werewolf_kill' AND v_role != 'werewolf') OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') OR
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch')
  THEN
    RAISE EXCEPTION 'Acao nao permitida para seu papel';
  END IF;

  -- Validar fase
  SELECT current_phase, turn_index, wolves_resolved
    INTO v_current_phase, v_turn, v_wolves_resolved
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'night' THEN
    RAISE EXCEPTION 'Nao e hora de agir';
  END IF;

  -- Bruxa precisa esperar lobos resolverem
  IF p_action_type IN ('witch_save', 'witch_poison') AND NOT v_wolves_resolved THEN
    RAISE EXCEPTION 'Aguarde o ataque dos lobos';
  END IF;

  -- Validar pocoes
  IF p_action_type = 'witch_save' AND v_used_life THEN
    RAISE EXCEPTION 'Pocao da vida ja foi usada';
  END IF;

  IF p_action_type = 'witch_poison' AND v_used_death THEN
    RAISE EXCEPTION 'Pocao da morte ja foi usada';
  END IF;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id);

  -- Atualizar flag da bruxa
  IF p_action_type = 'witch_save' THEN
    UPDATE players SET has_used_life_potion = true WHERE id = v_player_id;
  ELSIF p_action_type = 'witch_poison' THEN
    UPDATE players SET has_used_death_potion = true WHERE id = v_player_id;
  END IF;

  -- Seer: resultado imediato
  IF p_action_type = 'seer_investigate' THEN
    SELECT role = 'werewolf' INTO v_result
    FROM players WHERE id = p_target_id AND room_id = p_room_id;

    UPDATE night_actions SET result = v_result
    WHERE actor_id = v_player_id AND turn_index = v_turn;

    RETURN jsonb_build_object('result', v_result);
  END IF;

  RETURN jsonb_build_object('result', null);
END;
$$;

-- ============================================================
-- 6. RPC: resolve_night_wolves
--    Conta votos dos lobos, armazena alvo no last_event
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_night_wolves(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_victim_id UUID;
  v_victim_name TEXT;
  v_max_votes INT := 0;
  v_tie_count INT := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver o ataque';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Apurar votos dos lobos em unico SELECT
  WITH vote_counts AS (
    SELECT target_id, COUNT(*)::INT as cnt
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
    GROUP BY target_id
  ),
  max_votes AS (
    SELECT COALESCE(MAX(cnt), 0) as max_cnt,
           COUNT(*)::INT as tied_targets
    FROM vote_counts
  ),
  top_target AS (
    SELECT v.target_id
    FROM vote_counts v, max_votes m
    WHERE v.cnt = m.max_cnt
    ORDER BY v.target_id
    LIMIT 1
  )
  SELECT m.max_cnt, m.tied_targets, t.target_id
  INTO v_max_votes, v_tie_count, v_victim_id
  FROM max_votes m LEFT JOIN top_target t ON true;

  IF v_victim_id IS NOT NULL AND v_max_votes > 0 AND v_tie_count = 1 THEN
    SELECT name INTO v_victim_name FROM players WHERE id = v_victim_id;
  END IF;

    -- Armazenar alvo dos lobos no last_event (nao mexe em last_vote_result)
  UPDATE game_state
  SET wolves_resolved = true,
      last_event = jsonb_build_object(
        'type', 'wolf_target',
        'victim_id', v_victim_id,
        'victim_name', v_victim_name,
        'wolf_votes', v_max_votes
      )
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'victim_id', v_victim_id,
    'victim_name', v_victim_name,
    'wolf_votes', v_max_votes,
    'tie', v_tie_count > 1
  );
END;
$$;

-- ============================================================
-- 7. RPC: resolve_night (agora com bruxa + endgame)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_victim_name TEXT;
  v_victim_id UUID;
  v_saved BOOLEAN := false;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_winner TEXT;
  v_victims JSONB := '[]'::JSONB;
  v_alive_count INT;
  v_wolf_count INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  -- Safety: lobos precisam ter sido resolvidos primeiro
  IF NOT EXISTS (
    SELECT 1 FROM game_state WHERE room_id = p_room_id AND wolves_resolved = true
  ) THEN
    RAISE EXCEPTION 'Ataque dos lobos ainda nao foi resolvido';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Ler alvo dos lobos do last_event (definido por resolve_night_wolves)
  SELECT (last_event->>'victim_id')::UUID, (last_event->>'victim_name')
  INTO v_victim_id, v_victim_name
  FROM game_state WHERE room_id = p_room_id;

  -- Bruxa salvou?
  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_saved;

  -- Se nao salvou e tem vitima, mata
  IF v_victim_id IS NOT NULL AND NOT v_saved THEN
    UPDATE players SET is_alive = false WHERE id = v_victim_id;
    v_victims := v_victims || jsonb_build_object('name', v_victim_name, 'cause', 'wolf');
  END IF;

  -- Bruxa envenenou?
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison'
  LIMIT 1;

  IF v_poison_target_id IS NOT NULL THEN
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'poison');
  END IF;

  -- Verificar fim de jogo
  SELECT COUNT(*) INTO v_alive_count
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  SELECT COUNT(*) INTO v_wolf_count
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'werewolf';

  IF v_wolf_count = 0 THEN
    v_winner := 'villagers_win';
    UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
  ELSIF v_wolf_count * 2 >= v_alive_count THEN
    v_winner := 'wolves_win';
    UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
  END IF;

  IF v_winner IS NOT NULL THEN
    UPDATE game_state
    SET current_phase = 'ended', phase_started_at = now(),
        wolves_resolved = false,
        last_event = jsonb_build_object(
          'type', 'night_result',
          'victims', v_victims,
          'winner', v_winner
        )
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object(
      'victims', v_victims,
      'game_over', true,
      'winner', v_winner
    );
  END IF;

  -- Resetar para o dia
  UPDATE game_state
  SET current_phase = 'day', phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'victims', v_victims,
    'game_over', false,
    'winner', null
  );
END;
$$;

-- ============================================================
-- 8. ATUALIZAR resolve_day_vote (empate + endgame + rooms.status)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_day_vote(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_alive_count INT;
  v_threshold INT;
  v_top_target UUID;
  v_top_votes INT := 0;
  v_tie_count INT := 0;
  v_lynched_name TEXT;
  v_winner TEXT;
  v_event_type TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a votacao';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT COUNT(*) INTO v_alive_count
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  v_threshold := floor(v_alive_count / 2.0)::INT + 1;

  -- Apurar votos com deteccao de empate em unico SELECT
  WITH vote_counts AS (
    SELECT target_id, COUNT(*)::INT as cnt
    FROM votes
    WHERE room_id = p_room_id AND turn_index = v_turn
    GROUP BY target_id
  ),
  max_votes AS (
    SELECT COALESCE(MAX(cnt), 0) as max_cnt,
           COUNT(*)::INT as tied_targets
    FROM vote_counts
  ),
  top_target AS (
    SELECT v.target_id
    FROM vote_counts v, max_votes m
    WHERE v.cnt = m.max_cnt
    ORDER BY v.target_id
    LIMIT 1
  )
  SELECT m.max_cnt, m.tied_targets, t.target_id
  INTO v_top_votes, v_tie_count, v_top_target
  FROM max_votes m LEFT JOIN top_target t ON true;

  -- Linchamento: precisa de maioria absoluta E sem empate
  IF v_top_target IS NOT NULL AND v_top_votes >= v_threshold AND v_tie_count = 1 THEN
    SELECT name INTO v_lynched_name FROM players WHERE id = v_top_target;
    UPDATE players SET is_alive = false WHERE id = v_top_target;
    v_event_type := 'lynch';
  ELSE
    v_top_target := NULL;
    v_lynched_name := NULL;
    v_event_type := 'vote_tie';
  END IF;

  -- Verificar game over (trigger tambem fara, mas fazemos aqui para retorno correto)
  WITH counts AS (
    SELECT
      COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf') AS wolves,
      COUNT(*) FILTER (WHERE is_alive = true AND role != 'werewolf') AS non_wolves
    FROM players WHERE room_id = p_room_id
  )
  SELECT
    CASE
      WHEN wolves = 0 THEN 'villagers_win'
      WHEN wolves >= non_wolves THEN 'wolves_win'
    END
  INTO v_winner
  FROM counts;

  IF v_winner IS NOT NULL THEN
    IF v_winner = 'villagers_win' THEN
      UPDATE rooms SET status = 'finished_villagers_win' WHERE id = p_room_id;
    ELSE
      UPDATE rooms SET status = 'finished_wolves_win' WHERE id = p_room_id;
    END IF;

    UPDATE game_state
    SET current_phase = 'ended', phase_started_at = now(),
        wolves_resolved = false,
        last_vote_result = jsonb_build_object(
          'type', v_event_type,
          'victim_name', v_lynched_name
        ),
        last_event = jsonb_build_object(
          'type', v_event_type,
          'victim_name', v_lynched_name,
          'winner', v_winner
        )
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object(
      'lynched_id', v_top_target,
      'lynched_name', v_lynched_name,
      'event', v_event_type,
      'game_over', true,
      'winner', v_winner
    );
  END IF;

  UPDATE game_state
  SET current_phase = 'night', turn_index = turn_index + 1, phase_started_at = now(),
      wolves_resolved = false,
      last_vote_result = jsonb_build_object(
        'type', v_event_type,
        'victim_name', v_lynched_name
      ),
      last_event = jsonb_build_object(
        'type', v_event_type,
        'victim_name', v_lynched_name
      )
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'lynched_id', v_top_target,
    'lynched_name', v_lynched_name,
    'event', v_event_type,
    'game_over', false,
    'winner', null
  );
END;
$$;

-- ============================================================
-- 9. TRIGGER: checar game over ao alterar is_alive
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wolves INT;
  v_non_wolves INT;
  v_status TEXT;
BEGIN
  IF NEW.room_id IS NULL THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO v_wolves
  FROM players WHERE room_id = NEW.room_id AND is_alive = true AND role = 'werewolf';

  SELECT COUNT(*) INTO v_non_wolves
  FROM players WHERE room_id = NEW.room_id AND is_alive = true AND role != 'werewolf';

  -- Nao agir se jogo ja acabou
  SELECT status INTO v_status FROM rooms WHERE id = NEW.room_id;
  IF v_status LIKE 'finished_%' THEN RETURN NEW; END IF;

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

DROP TRIGGER IF EXISTS trg_check_game_over ON players;
CREATE TRIGGER trg_check_game_over
  AFTER UPDATE OF is_alive ON players
  FOR EACH ROW
  WHEN (OLD.is_alive IS DISTINCT FROM NEW.is_alive AND NEW.room_id IS NOT NULL)
  EXECUTE FUNCTION check_game_over_trigger();

-- ============================================================
-- 10. ATUALIZAR advance_phase (card_reveal→night, day→vote)
-- ============================================================
CREATE OR REPLACE FUNCTION public.advance_phase(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current VARCHAR;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode avancar a fase';
  END IF;

  SELECT current_phase INTO v_current FROM game_state WHERE room_id = p_room_id;

  IF v_current = 'card_reveal' THEN
    UPDATE game_state SET current_phase = 'night', phase_started_at = now()
    WHERE room_id = p_room_id;
  ELSIF v_current = 'day' THEN
    UPDATE game_state SET current_phase = 'vote', phase_started_at = now()
    WHERE room_id = p_room_id;
  ELSE
    RAISE EXCEPTION 'Nao e possivel avancar da fase %', v_current;
  END IF;
END;
$$;

-- ============================================================
-- 11. REALTIME: novas colunas
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE votes;
