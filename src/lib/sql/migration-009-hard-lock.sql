-- ============================================================
-- MIGRATION 009: HARD LOCK — Race Condition no Fim de Jogo
--
-- Adiciona trava de seguranca em check_game_over() e
-- trg_check_game_over() para impedir avaliacao de vitoria
-- durante turn_index = 0 ou current_phase = 'card_reveal'.
-- ============================================================

-- ============================================================
-- RPC: check_game_over — com Hard Lock
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
  v_wolves INT;
  v_non_wolves INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  -- Hard Lock: abortar se turn_index = 0 ou current_phase = 'card_reveal'
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
-- TRIGGER: trg_check_game_over — com Hard Lock
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
  v_wolves INT;
  v_non_wolves INT;
BEGIN
  -- Hard Lock: abortar se turn_index = 0 ou current_phase = 'card_reveal'
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
