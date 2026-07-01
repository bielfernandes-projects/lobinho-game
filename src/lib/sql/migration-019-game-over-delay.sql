-- ============================================================
-- MIGRATION 019: Game Over Delay — mestre decide quando encerrar
-- ============================================================

-- 1. Coluna winner na game_state (NULL enquanto jogo ativo)
ALTER TABLE public.game_state ADD COLUMN IF NOT EXISTS winner TEXT DEFAULT NULL;

-- 2. check_game_over: só define winner, NÃO mexe em rooms.status nem current_phase
CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_wolves INT;
  v_non_wolves INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN jsonb_build_object('game_over', false, 'skipped', true);
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role != 'werewolf')
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

-- 3. Trigger: só define winner, não rooms.status
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
  v_wolves INT;
  v_non_wolves INT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = NEW.room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NEW;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role != 'werewolf')
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

-- 4. RPC: host_end_game — mestre finaliza a partida manualmente
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
  ELSE
    RAISE EXCEPTION 'Nenhum vencedor definido';
  END IF;

  UPDATE game_state SET current_phase = 'ended' WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'winner', v_winner);
END;
$$;
