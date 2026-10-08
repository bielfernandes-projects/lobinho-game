CREATE OR REPLACE FUNCTION public.hunter_skip(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hunter_id UUID;
BEGIN
  -- Verificar que existe hunter_pending
  SELECT hunter_id INTO v_hunter_id
  FROM game_state WHERE room_id = p_room_id;

  IF v_hunter_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum Caçador pendente de retaliação';
  END IF;

  -- Verificar que quem chamou é o próprio Hunter
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE id = v_hunter_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Somente o Caçador pode decidir pular';
  END IF;

  -- Limpar estado do Hunter (sem mudar day_step — o host avança)
  UPDATE game_state
  SET hunter_pending = false, hunter_id = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'skipped', true);
END;
$function$
