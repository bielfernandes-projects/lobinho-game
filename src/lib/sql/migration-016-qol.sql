-- 1. Coluna voting_open na game_state
ALTER TABLE public.game_state ADD COLUMN IF NOT EXISTS voting_open BOOLEAN DEFAULT false;

-- 2. RLS: Jogador pode se remover da sala
DROP POLICY IF EXISTS "Jogador pode se remover" ON public.players;
CREATE POLICY "Jogador pode se remover" ON public.players
  FOR DELETE USING (user_id = auth.uid());

-- 3. RLS: Host pode remover jogadores da sala dele
DROP POLICY IF EXISTS "Host pode remover jogadores" ON public.players;
CREATE POLICY "Host pode remover jogadores" ON public.players
  FOR DELETE USING (
    room_id IN (SELECT id FROM public.rooms WHERE host_id = auth.uid())
  );

-- 4. RPC: host_kill_player (punicao do mestre)
CREATE OR REPLACE FUNCTION public.host_kill_player(p_target_id UUID, p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_victim_name TEXT;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM rooms WHERE id = p_room_id AND host_id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas o host pode executar esta acao';
  END IF;

  SELECT name INTO v_victim_name FROM players WHERE id = p_target_id;
  IF v_victim_name IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado';
  END IF;

  UPDATE players SET is_alive = false WHERE id = p_target_id;

  UPDATE game_state
  SET last_event = jsonb_build_object(
    'type', 'host_execution',
    'victim_id', p_target_id,
    'victim_name', v_victim_name,
    'cause', 'punicao do mestre'
  )
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over);
END;
$$;

-- 5. Trigger: reseta tudo quando rooms.status volta para 'waiting'
CREATE OR REPLACE FUNCTION public.reset_game()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.votes WHERE room_id = NEW.id;
  DELETE FROM public.night_actions WHERE room_id = NEW.id;
  DELETE FROM public.game_state WHERE room_id = NEW.id;
  UPDATE public.players SET
    is_alive = true,
    has_viewed_card = false,
    viewed_card_at = NULL,
    role = NULL
  WHERE room_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reset_game ON public.rooms;
CREATE TRIGGER trg_reset_game
  AFTER UPDATE OF status ON public.rooms
  FOR EACH ROW
  WHEN (NEW.status = 'waiting' AND OLD.status IS DISTINCT FROM 'waiting')
  EXECUTE FUNCTION public.reset_game();
