-- ============================================================
-- MIGRACAO COMPLETA E SEGURA (pode rodar varias vezes)
-- Combina 002 + 003 + 004 + 005 + 006 sem erros de repeticao
-- ============================================================

-- ============================================================
-- 002: has_viewed_card + start_game + advance_phase
-- ============================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_viewed_card BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE players ADD COLUMN IF NOT EXISTS viewed_card_at TIMESTAMPTZ;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'players')
  THEN ALTER PUBLICATION supabase_realtime ADD TABLE players; END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'game_state')
  THEN ALTER PUBLICATION supabase_realtime ADD TABLE game_state; END IF;
END $$;

-- ============================================================
-- 003: night_actions + votes + core RPCs
-- ============================================================
ALTER TABLE game_state DROP CONSTRAINT IF EXISTS game_state_current_phase_check;
ALTER TABLE game_state ADD CONSTRAINT game_state_current_phase_check
  CHECK (current_phase IN ('card_reveal', 'night', 'day', 'vote', 'ended'));

CREATE TABLE IF NOT EXISTS night_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  turn_index INT NOT NULL,
  actor_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  action_type VARCHAR(20) NOT NULL
    CHECK (action_type IN ('werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison')),
  target_id UUID REFERENCES players(id) ON DELETE CASCADE,
  result BOOLEAN,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, turn_index, actor_id)
);

CREATE INDEX IF NOT EXISTS idx_night_actions_room_turn ON night_actions(room_id, turn_index);

CREATE TABLE IF NOT EXISTS votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  turn_index INT NOT NULL,
  voter_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, turn_index, voter_id)
);

CREATE INDEX IF NOT EXISTS idx_votes_room_turn ON votes(room_id, turn_index);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'night_actions')
  THEN ALTER PUBLICATION supabase_realtime ADD TABLE night_actions; END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'votes')
  THEN ALTER PUBLICATION supabase_realtime ADD TABLE votes; END IF;
END $$;

-- ============================================================
-- 004: witch + endgame + tie + wolves_resolved
-- ============================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_used_life_potion BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_used_death_potion BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE game_state ADD COLUMN IF NOT EXISTS wolves_resolved BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS last_vote_result JSONB;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS last_event JSONB;

-- Atualizar constraint da rooms para incluir finished_*
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_status_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_status_check
  CHECK (status IN ('waiting', 'playing', 'finished', 'finished_villagers_win', 'finished_wolves_win'));

-- ============================================================
-- 005: timer columns
-- ============================================================
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_duration INT;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_remaining INT;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS is_timer_running BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_started_at TIMESTAMPTZ;

-- ============================================================
-- RLS nas novas tabelas
-- ============================================================
ALTER TABLE night_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS night_actions_insert_alive ON night_actions;
CREATE POLICY night_actions_insert_alive ON night_actions
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM players
      WHERE id = actor_id AND is_alive = true AND room_id = room_id
    )
  );

DROP POLICY IF EXISTS night_actions_select_own ON night_actions;
CREATE POLICY night_actions_select_own ON night_actions
  FOR SELECT TO authenticated
  USING (actor_id IN (SELECT id FROM players WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS votes_insert_alive ON votes;
CREATE POLICY votes_insert_alive ON votes
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM players
      WHERE id = voter_id AND is_alive = true AND room_id = room_id
    )
  );

DROP POLICY IF EXISTS votes_select_all ON votes;
CREATE POLICY votes_select_all ON votes
  FOR SELECT TO authenticated
  USING (true);

-- ============================================================
-- RPC: start_game (sem arrays)
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

  SELECT COUNT(*) INTO v_num
  FROM players WHERE room_id = p_room_id;

  IF v_num < 4 THEN
    RAISE EXCEPTION 'Minimo de 4 jogadores para iniciar';
  END IF;

  v_n_wolves := GREATEST(1, floor(v_num / 3.0)::INT);

  WITH shuffled AS (
    SELECT id, row_number() OVER (ORDER BY random()) - 1 AS rn
    FROM players
    WHERE room_id = p_room_id
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
-- RPC: advance_phase
-- ============================================================
CREATE OR REPLACE FUNCTION public.advance_phase(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current VARCHAR;
  v_next VARCHAR;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode avancar a fase';
  END IF;

  SELECT current_phase INTO v_current FROM game_state WHERE room_id = p_room_id;

  v_next := CASE v_current
    WHEN 'night' THEN 'day'
    WHEN 'day' THEN 'vote'
    WHEN 'vote' THEN 'night'
    ELSE 'ended'
  END;

  UPDATE game_state
  SET current_phase = v_next,
      turn_index = turn_index + 1,
      phase_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;

-- ============================================================
-- [REMOVED] get_player_roles — use fetch_roles_for_host
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================

-- ============================================================
-- [REMOVED] submit_night_action — use execute_night_action
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================

-- ============================================================
-- RPC: resolve_night_wolves
-- ============================================================
DROP FUNCTION IF EXISTS public.resolve_night_wolves(UUID) CASCADE;
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
    'votes', v_max_votes,
    'tie', CASE WHEN v_tie_count > 1 THEN true ELSE false END
  );
END;
$$;

-- ============================================================
-- RPC: resolve_night
-- ============================================================
DROP FUNCTION IF EXISTS public.resolve_night(UUID) CASCADE;
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
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Alvo dos lobos
  SELECT target_id INTO v_wolf_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  GROUP BY target_id
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Bruxa salvou?
  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  -- Alvo do veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  -- Matar alvo dos lobos (se bruxa nao salvou)
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  -- Matar alvo do veneno (se diferente do alvo dos lobos)
  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
  END IF;

  -- Construir victims array
  v_victims := '[]'::JSONB;
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno');
  END IF;

  -- Avancar para day (começa com announcement)
  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'announcement',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;

-- ============================================================
-- RPC: resolve_day_vote
-- ============================================================
DROP FUNCTION IF EXISTS public.resolve_day_vote(UUID) CASCADE;
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
  v_winner TEXT;
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

  -- Contar votos
  SELECT target_id, COUNT(*) AS cnt INTO v_target_id, v_vote_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  ORDER BY cnt DESC
  LIMIT 1;

  -- Verificar empate
  SELECT COUNT(*) INTO v_tie_count
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  HAVING COUNT(*) = v_vote_count;

  IF v_vote_count < v_threshold OR v_tie_count > 1 THEN
    -- Empate ou votos insuficientes - ninguem morre
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
    -- Alguem morre
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

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- RPC: check_game_over
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wolves INT;
  v_non_wolves INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role != 'werewolf')
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
-- RPC: get_werewolf_teammates
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_werewolf_teammates(p_room_id UUID)
RETURNS TABLE(id UUID, name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT role FROM players WHERE user_id = auth.uid() AND room_id = p_room_id) != 'werewolf' THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT p.id, p.name
  FROM players p
  WHERE p.room_id = p_room_id AND p.role = 'werewolf' AND p.user_id != auth.uid();
END;
$$;

-- ============================================================
-- TRIGGER: check_game_over on is_alive change
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
  v_wolves INT;
  v_non_wolves INT;
BEGIN
  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role != 'werewolf')
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

DROP TRIGGER IF EXISTS trg_check_game_over ON players;
CREATE OR REPLACE TRIGGER trg_check_game_over
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_game_over();

-- ============================================================
-- RPCs: timer
-- ============================================================
CREATE OR REPLACE FUNCTION public.start_timer(p_room_id UUID, p_duration INT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode controlar o timer';
  END IF;

  IF p_duration < 60 OR p_duration > 600 THEN
    RAISE EXCEPTION 'Duracao deve estar entre 60 e 600 segundos';
  END IF;

  UPDATE game_state
  SET timer_duration = p_duration,
      timer_remaining = p_duration,
      is_timer_running = true,
      timer_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_remaining INT;
  v_started TIMESTAMPTZ;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode controlar o timer';
  END IF;

  SELECT timer_remaining, timer_started_at INTO v_remaining, v_started
  FROM game_state WHERE room_id = p_room_id;

  IF v_started IS NOT NULL THEN
    v_remaining := GREATEST(0, v_remaining - EXTRACT(EPOCH FROM (now() - v_started))::INT);
  END IF;

  UPDATE game_state
  SET is_timer_running = false,
      timer_remaining = v_remaining,
      timer_started_at = null
  WHERE room_id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode controlar o timer';
  END IF;

  UPDATE game_state
  SET is_timer_running = true,
      timer_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode controlar o timer';
  END IF;

  UPDATE game_state
  SET timer_duration = null,
      timer_remaining = null,
      is_timer_running = false,
      timer_started_at = null
  WHERE room_id = p_room_id;
END;
$$;
