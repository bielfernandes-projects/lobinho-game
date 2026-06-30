-- ============================================================
-- MIGRATION 015: Reconstrução Forçada de RPCs + TEXT columns
--
-- 1. DROP das funções conflitantes para limpar assinaturas
-- 2. ALTER TABLE de VARCHAR para TEXT (limite de caracteres)
-- 3. Recriação de get_player_roles com 5 colunas tipadas
-- 4. Recriação de submit_night_action com TEXT (sem ambiguidade)
-- ============================================================

-- ============================================================
-- 1. DROP de funções conflitantes
-- ============================================================
DROP FUNCTION IF EXISTS public.get_player_roles(UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.submit_night_action(UUID, VARCHAR, UUID);

-- ============================================================
-- 2. ALTER COLUMNS para TEXT (evita erro 'value too long')
-- ============================================================
ALTER TABLE night_actions ALTER COLUMN action_type TYPE TEXT;
ALTER TABLE game_state ALTER COLUMN night_step TYPE TEXT;

-- ============================================================
-- 3. [REMOVED] get_player_roles — use fetch_roles_for_host
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================

-- ============================================================
-- 4. [REMOVED] submit_night_action — use execute_night_action
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================
