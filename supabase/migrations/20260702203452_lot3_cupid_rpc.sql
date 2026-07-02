-- Lot 3: Cupid dedicated RPC
-- submit_cupid_match — cross-updates soulmate_id for two targets

CREATE OR REPLACE FUNCTION public.submit_cupid_match(p_room_id UUID, p_target_a UUID, p_target_b UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_role TEXT;
BEGIN
  SELECT id, role INTO v_player_id, v_role
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF v_role != 'cupid' THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  UPDATE players SET soulmate_id = p_target_b WHERE id = p_target_a;
  UPDATE players SET soulmate_id = p_target_a WHERE id = p_target_b;

  RETURN jsonb_build_object('success', true);
END;
$$;
