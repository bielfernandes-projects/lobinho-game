-- ============================================================
-- MIGRATION 006: start_game rewrite (no arrays)
-- ============================================================
-- Substitui start_game por uma versao que nao usa
-- manipulacao explicita de arrays (ARRAY[], ||, unnest).
-- Usa ROW_NUMBER() + CASE no lugar.
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

  -- Atribuir papeis: N lobos, 1 seer, 1 bruxa, resto aldeoes
  -- Embaralhado via random() no ORDER BY
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

  -- Marcar sala como em jogo
  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  -- Inserir / resetar estado do jogo
  INSERT INTO game_state (room_id, current_phase, turn_index)
  VALUES (p_room_id, 'card_reveal', 0)
  ON CONFLICT (room_id) DO UPDATE
    SET current_phase = 'card_reveal', turn_index = 0, phase_started_at = now();
END;
$$;
