-- ============================================================
-- MIGRATION 014: Correção get_player_roles + resolve_night NULL
--
-- 1. get_player_roles: SELECT interno agora retorna as 5
--    colunas exigidas pelo RETURNS TABLE (id, name, role,
--    is_alive, has_viewed_card). A versão atual em
--    migration-complete-safe.sql só retorna 2 colunas,
--    causando erro de mismatch no HostRolePanel.
--
-- 2. resolve_night: Usa IS DISTINCT FROM em vez de != para
--    comparar poison target com wolf target. Quando
--    v_wolf_target_id é NULL (ex: nenhum lobo agiu), a
--    expressão != NULL retorna NULL (falso), impedindo o
--    veneno da bruxa de funcionar.
-- ============================================================

-- ============================================================
-- FIX 1: [REMOVED] get_player_roles — use fetch_roles_for_host
-- (criada manualmente no Supabase para evitar overwrite no deploy)
-- ============================================================
-- A definicao abaixo foi removida propositalmente.

-- ============================================================
-- FIX 2: resolve_night — IS DISTINCT FROM em vez de !=
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_wolf_target_id UUID;
  v_wolf_target_name TEXT;
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_victims JSONB;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Alvo dos lobos (mais votado)
  SELECT target_id INTO v_wolf_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  GROUP BY target_id
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Bruxa salvou?
  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  -- Alvo do veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  -- Matar alvo dos lobos (se bruxa nao salvou)
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  -- Matar alvo do veneno (se diferente do alvo dos lobos)
  -- USAMOS IS DISTINCT FROM para tratar NULL corretamente
  IF v_poison_target_id IS NOT NULL AND v_poison_target_id IS DISTINCT FROM v_wolf_target_id THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
  END IF;

  -- Construir array de vitimas
  v_victims := '[]'::JSONB;
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno');
  END IF;

  -- Avancar para day
  UPDATE game_state
  SET current_phase = 'day',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  -- Verificar fim de jogo apos mortes noturnas
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object('success', true, 'victims', v_victims, 'game_over', v_game_over);
END;
$$;
