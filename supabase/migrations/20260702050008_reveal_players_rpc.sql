-- RPC: get_revealed_players — retorna id, name e role de todos os jogadores da sala
-- SECURITY DEFINER: executa com permissões do owner (bypass RLS)
-- Útil para o Game Over, onde todos precisam ver os papéis dos vencedores
CREATE OR REPLACE FUNCTION public.get_revealed_players(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'role', p.role
    )
    ORDER BY p.name ASC
  ) INTO v_result
  FROM players p
  WHERE p.room_id = p_room_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
