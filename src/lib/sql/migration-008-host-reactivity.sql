-- ============================================================
-- MIGRATION 008: Reatividade do Host (Lobby + Painel)
-- ============================================================

-- ============================================================
-- 1. Adicionar rooms à publicação Realtime
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'rooms'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE rooms;
  END IF;
END $$;

-- ============================================================
-- 2. RPC: get_player_roles (retorna tabela completa)
-- ============================================================
DROP FUNCTION IF EXISTS public.get_player_roles(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.get_player_roles(p_room_id UUID)
RETURNS TABLE(id UUID, name TEXT, role TEXT, is_alive BOOLEAN, has_viewed_card BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode ver os papeis';
  END IF;

  RETURN QUERY
  SELECT p.id, p.name, p.role::TEXT, p.is_alive, p.has_viewed_card
  FROM players p
  WHERE p.room_id = p_room_id;
END;
$$;
