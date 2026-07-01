-- ============================================================
-- MIGRATION 017: Scenario Builder — start_game com p_roles JSONB
-- ============================================================

CREATE OR REPLACE FUNCTION public.start_game(p_room_id UUID, p_roles JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_num INT;
  v_role TEXT;
  v_idx INT := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode iniciar a partida';
  END IF;

  -- Forca host como moderador
  UPDATE players SET role = 'moderator'
  WHERE room_id = p_room_id AND is_host = true;

  -- Conta jogadores nao-host
  SELECT COUNT(*) INTO v_num
  FROM players WHERE room_id = p_room_id AND is_host = false;

  IF v_num < 4 THEN
    RAISE EXCEPTION 'Minimo de 4 jogadores (excluindo o mestre) para iniciar';
  END IF;

  IF jsonb_array_length(p_roles) != v_num THEN
    RAISE EXCEPTION 'Numero de cartas (%) nao corresponde ao numero de jogadores (%)',
      jsonb_array_length(p_roles), v_num;
  END IF;

  -- Zera roles de jogadores nao-host (para caso de reset)
  UPDATE players SET role = NULL
  WHERE room_id = p_room_id AND is_host = false;

  -- Distribui as roles embaralhando aleatoriamente
  FOR v_role IN SELECT jsonb_array_elements_text(p_roles) LOOP
    UPDATE players SET role = v_role
    WHERE id = (
      SELECT id FROM players
      WHERE room_id = p_room_id AND is_host = false AND role IS NULL
      ORDER BY random()
      LIMIT 1
    );
  END LOOP;

  UPDATE rooms SET status = 'playing' WHERE id = p_room_id;

  INSERT INTO game_state (room_id, current_phase, turn_index)
  VALUES (p_room_id, 'card_reveal', 0)
  ON CONFLICT (room_id) DO UPDATE
    SET current_phase = 'card_reveal', turn_index = 0, phase_started_at = now();
END;
$$;
