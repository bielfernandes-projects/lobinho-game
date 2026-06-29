-- ============================================================
-- MIGRATION 003: core loop (night/day/vote)
-- ============================================================

-- ============================================================
-- 1. ALTERAR CHECK do game_state para incluir card_reveal
-- ============================================================
ALTER TABLE game_state DROP CONSTRAINT IF EXISTS game_state_current_phase_check;
ALTER TABLE game_state ADD CONSTRAINT game_state_current_phase_check
  CHECK (current_phase IN ('card_reveal', 'night', 'day', 'vote', 'ended'));

-- ============================================================
-- 2. NOVAS TABELAS
-- ============================================================
CREATE TABLE IF NOT EXISTS night_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  turn_index INT NOT NULL,
  actor_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  action_type VARCHAR(20) NOT NULL
    CHECK (action_type IN ('werewolf_kill', 'seer_investigate')),
  target_id UUID REFERENCES players(id) ON DELETE CASCADE,
  result BOOLEAN,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, turn_index, actor_id)
);

CREATE INDEX idx_night_actions_room_turn ON night_actions(room_id, turn_index);

CREATE TABLE IF NOT EXISTS votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  turn_index INT NOT NULL,
  voter_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, turn_index, voter_id)
);

CREATE INDEX idx_votes_room_turn ON votes(room_id, turn_index);

-- ============================================================
-- 3. REALTIME
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE night_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE votes;

-- ============================================================
-- 4. ATUALIZAR start_game (usa card_reveal em vez de night)
-- ============================================================
CREATE OR REPLACE FUNCTION public.start_game(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_ids UUID[];
  v_shuffled UUID[];
  v_roles TEXT[];
  v_num INT;
  v_n_wolves INT;
  v_i INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode iniciar a partida';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY created_at) INTO v_player_ids
  FROM players WHERE room_id = p_room_id;

  v_num := array_length(v_player_ids, 1);

  IF v_num < 4 THEN
    RAISE EXCEPTION 'Minimo de 4 jogadores para iniciar';
  END IF;

  v_n_wolves := GREATEST(1, floor(v_num / 3.0)::INT);
  v_roles := ARRAY[]::TEXT[];

  FOR v_i IN 1..v_n_wolves LOOP
    v_roles := v_roles || 'werewolf';
  END LOOP;
  v_roles := v_roles || 'seer';
  v_roles := v_roles || 'witch';
  WHILE array_length(v_roles, 1) < v_num LOOP
    v_roles := v_roles || 'villager';
  END LOOP;

  SELECT ARRAY_AGG(id ORDER BY random()) INTO v_shuffled
  FROM unnest(v_player_ids) AS id;

  FOR v_i IN 1..v_num LOOP
    UPDATE players SET role = v_roles[v_i] WHERE id = v_shuffled[v_i];
  END LOOP;

  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  INSERT INTO game_state (room_id, current_phase, turn_index)
  VALUES (p_room_id, 'card_reveal', 0)
  ON CONFLICT (room_id) DO UPDATE
    SET current_phase = 'card_reveal', turn_index = 0, phase_started_at = now();
END;
$$;

-- ============================================================
-- 5. ATUALIZAR advance_phase (card_reveal → night, day → vote)
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
-- 6. COLUNA last_event no game_state
-- ============================================================
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS last_event JSONB;

-- ============================================================
-- 7. RPC: submit_night_action
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
BEGIN
  SELECT id, role, is_alive INTO v_player_id, v_role, v_alive
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogador morto nao pode agir';
  END IF;

  IF (p_action_type = 'werewolf_kill' AND v_role != 'werewolf') OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') THEN
    RAISE EXCEPTION 'Acao nao permitida para seu papel';
  END IF;

  SELECT current_phase, turn_index INTO v_current_phase, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'night' THEN
    RAISE EXCEPTION 'Nao e hora de agir';
  END IF;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id);

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
-- 8. RPC: resolve_night (conta votos lobos, mata vitima)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_victim_id UUID;
  v_victim_name TEXT;
  v_top_target UUID;
  v_max_votes INT := 0;
  v_alive_count INT;
  v_wolf_count INT;
  v_game_over JSONB;
  v_winner TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT target_id, COUNT(*)::INT INTO v_top_target, v_max_votes
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  GROUP BY target_id
  ORDER BY COUNT(*) DESC, random()
  LIMIT 1;

  IF v_top_target IS NOT NULL AND v_max_votes > 0 THEN
    SELECT name INTO v_victim_name FROM players WHERE id = v_top_target;
    v_victim_id := v_top_target;
    UPDATE players SET is_alive = false WHERE id = v_victim_id;
  END IF;

  -- Verifica fim de jogo
  SELECT COUNT(*) INTO v_alive_count
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  SELECT COUNT(*) INTO v_wolf_count
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'werewolf';

  IF v_wolf_count = 0 THEN
    v_winner := 'villagers';
  ELSIF v_wolf_count * 2 >= v_alive_count THEN
    v_winner := 'werewolves';
  END IF;

  IF v_winner IS NOT NULL THEN
    UPDATE game_state
    SET current_phase = 'ended', phase_started_at = now(),
        last_event = jsonb_build_object('type', 'death', 'victim_name', v_victim_name, 'winner', v_winner)
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object(
      'victim_id', v_victim_id,
      'victim_name', v_victim_name,
      'game_over', true,
      'winner', v_winner
    );
  END IF;

  UPDATE game_state
  SET current_phase = 'day', phase_started_at = now(),
      last_event = jsonb_build_object('type', 'death', 'victim_name', v_victim_name)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'victim_id', v_victim_id,
    'victim_name', v_victim_name,
    'game_over', false,
    'winner', null
  );
END;
$$;

-- ============================================================
-- 9. RPC: get_werewolf_teammates (wolf ve outros lobos)
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

  RETURN QUERY SELECT p.id, p.name::TEXT
  FROM players p
  WHERE p.room_id = p_room_id AND p.role = 'werewolf';
END;
$$;

-- ============================================================
-- 10. RPC: check_game_over
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alive INT;
  v_wolves INT;
BEGIN
  SELECT COUNT(*) INTO v_alive
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  SELECT COUNT(*) INTO v_wolves
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role = 'werewolf';

  IF v_wolves = 0 THEN
    RETURN jsonb_build_object('game_over', true, 'winner', 'villagers');
  END IF;

  IF v_wolves * 2 >= v_alive THEN
    RETURN jsonb_build_object('game_over', true, 'winner', 'werewolves');
  END IF;

  RETURN jsonb_build_object('game_over', false, 'winner', null);
END;
$$;

-- ============================================================
-- 11. RPC: resolve_day_vote (maioria absoluta, linchamento)
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
  v_lynched_name TEXT;
  v_game_over JSONB;
  v_winner TEXT;
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

  SELECT target_id, COUNT(*)::INT INTO v_top_target, v_top_votes
  FROM votes
  WHERE room_id = p_room_id AND turn_index = v_turn
  GROUP BY target_id
  ORDER BY COUNT(*) DESC, random()
  LIMIT 1;

  IF v_top_target IS NOT NULL AND v_top_votes >= v_threshold THEN
    SELECT name INTO v_lynched_name FROM players WHERE id = v_top_target;
    UPDATE players SET is_alive = false WHERE id = v_top_target;
  END IF;

  v_game_over := check_game_over(p_room_id);

  IF (v_game_over->>'game_over')::boolean THEN
    v_winner := v_game_over->>'winner';
    UPDATE game_state
    SET current_phase = 'ended', phase_started_at = now(),
        last_event = jsonb_build_object('type', 'lynch', 'victim_name', v_lynched_name, 'winner', v_winner)
    WHERE room_id = p_room_id;

    RETURN jsonb_build_object(
      'lynched_id', v_top_target,
      'lynched_name', v_lynched_name,
      'game_over', true,
      'winner', v_winner
    );
  END IF;

  UPDATE game_state
  SET current_phase = 'night', turn_index = turn_index + 1, phase_started_at = now(),
      last_event = jsonb_build_object('type', 'lynch', 'victim_name', v_lynched_name)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'lynched_id', v_top_target,
    'lynched_name', v_lynched_name,
    'game_over', false,
    'winner', null
  );
END;
$$;

-- ============================================================
-- 12. RLS: night_actions
-- ============================================================
ALTER TABLE night_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY night_actions_select_own ON night_actions
  FOR SELECT USING (
    actor_id IN (SELECT id FROM players WHERE user_id = auth.uid() AND room_id = room_id)
  );

CREATE POLICY night_actions_select_host ON night_actions
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM rooms WHERE rooms.id = night_actions.room_id AND rooms.host_id = auth.uid())
  );

CREATE POLICY night_actions_insert_alive ON night_actions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players
      WHERE players.id = actor_id
        AND players.user_id = auth.uid()
        AND players.is_alive = true
    )
  );

-- ============================================================
-- 13. RLS: votes
-- ============================================================
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY votes_select_all ON votes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM players
      WHERE players.room_id = votes.room_id AND players.user_id = auth.uid()
    )
  );

CREATE POLICY votes_insert_alive ON votes
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players
      WHERE players.id = voter_id
        AND players.user_id = auth.uid()
        AND players.is_alive = true
    )
  );

CREATE POLICY votes_select_host ON votes
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM rooms WHERE rooms.id = votes.room_id AND rooms.host_id = auth.uid())
  );
