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
-- 3. get_player_roles — 5 colunas estritamente tipadas
-- ============================================================
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

-- ============================================================
-- 4. submit_night_action — TEXT (sem ambiguidade VARCHAR vs TEXT)
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_night_action(
  p_room_id UUID,
  p_action_type TEXT,
  p_target_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_player_id UUID;
  v_role TEXT;
  v_alive BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
  v_result BOOLEAN;
  v_wolves_resolved BOOLEAN;
BEGIN
  SELECT id, role, is_alive,
         COALESCE(has_used_life_potion, false),
         COALESCE(has_used_death_potion, false)
    INTO v_player_id, v_role, v_alive, v_used_life, v_used_death
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Jogador nao encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos nao podem agir';
  END IF;

  IF (p_action_type = 'werewolf_kill' AND v_role != 'werewolf') OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') OR
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch')
  THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  SELECT turn_index INTO v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF p_action_type IN ('witch_save', 'witch_poison') THEN
    SELECT COALESCE(wolves_resolved, false) INTO v_wolves_resolved
    FROM game_state WHERE room_id = p_room_id;
    IF NOT v_wolves_resolved THEN
      RAISE EXCEPTION 'Aguarde os lobos decidirem primeiro';
    END IF;
  END IF;

  IF p_action_type = 'witch_save' AND v_used_life THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da vida';
  END IF;

  IF p_action_type = 'witch_poison' AND v_used_death THEN
    RAISE EXCEPTION 'Voce ja usou a pocao da morte';
  END IF;

  IF p_action_type = 'witch_save' THEN
    UPDATE players SET has_used_life_potion = true WHERE id = v_player_id;
  ELSIF p_action_type = 'witch_poison' THEN
    UPDATE players SET has_used_death_potion = true WHERE id = v_player_id;
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role = 'werewolf' INTO v_result
    FROM players WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result);
  ELSE
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id);
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    RETURN jsonb_build_object('is_werewolf', v_result);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
