-- ============================================================
-- MIGRATION 002: has_viewed_card + RPCs + Realtime
-- ============================================================

-- COLUNA: has_viewed_card
ALTER TABLE players ADD COLUMN IF NOT EXISTS has_viewed_card BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE players ADD COLUMN IF NOT EXISTS viewed_card_at TIMESTAMPTZ;

-- REALTIME: habilitar tabelas na publicacao
ALTER PUBLICATION supabase_realtime ADD TABLE players;
ALTER PUBLICATION supabase_realtime ADD TABLE game_state;

-- ============================================================
-- RPC: start_game
-- Distribui papeis (Aldeao, Lobisomem, Vidente, Bruxa)
-- e avanca para fase 'night'
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

  -- Distribuicao: 1 seer, 1 witch, floor(N/3) wolves, resto villagers
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

  -- Embaralhar
  SELECT ARRAY_AGG(id ORDER BY random()) INTO v_shuffled
  FROM unnest(v_player_ids) AS id;

  -- Atribuir papeis
  FOR v_i IN 1..v_num LOOP
    UPDATE players SET role = v_roles[v_i] WHERE id = v_shuffled[v_i];
  END LOOP;

  -- Marcar sala como em jogo
  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  -- Inserir / resetar estado do jogo
  INSERT INTO game_state (room_id, current_phase, turn_index)
  VALUES (p_room_id, 'night', 0)
  ON CONFLICT (room_id) DO UPDATE
    SET current_phase = 'night', turn_index = 0, phase_started_at = now();
END;
$$;

-- ============================================================
-- RPC: advance_phase
-- Avanca da fase atual para a proxima (night→day→vote→night→...)
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
-- A definicao abaixo foi removida propositalmente.
-- O deploy re-executa este arquivo e recriaria a funcao antiga,
-- sobrescrevendo a versao corrigida (fetch_roles_for_host).
-- ============================================================
