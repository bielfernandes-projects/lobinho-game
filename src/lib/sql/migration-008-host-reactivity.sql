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
-- 2. [REMOVED] get_player_roles — use fetch_roles_for_host
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================
-- A definicao abaixo foi removida propositalmente.
