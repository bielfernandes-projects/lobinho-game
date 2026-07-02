-- Fixes:
-- 1. Add 'cupid_match' to night_actions constraint
-- 2. Update submit_cupid_match to log in night_actions
-- 3. Fix soulmate trigger: remove last_event (column doesn't exist on players)

-- ===== 1. Update night_actions constraint =====
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN (
    'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
    'priest_bless', 'bodyguard_protect', 'aura_investigate', 'cult_convert',
    'cupid_match'
  ));

-- ===== 2. Update submit_cupid_match to log in night_actions =====
CREATE OR REPLACE FUNCTION public.submit_cupid_match(p_room_id UUID, p_target_a UUID, p_target_b UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_role TEXT;
  v_turn INT;
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

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, 'cupid_match', p_target_a)
  ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ===== 3. Update fetch_roles_for_host: add soulmate_id and in_cult =====
DROP FUNCTION IF EXISTS public.fetch_roles_for_host(UUID);
CREATE FUNCTION public.fetch_roles_for_host(p_room_id UUID)
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
      'role', p.role,
      'is_alive', p.is_alive,
      'has_viewed_card', p.has_viewed_card,
      'soulmate_id', p.soulmate_id,
      'in_cult', p.in_cult
    )
    ORDER BY p.name ASC
  ) INTO v_result
  FROM players p
  WHERE p.room_id = p_room_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- ===== 4. Fix soulmate trigger: remove last_event (column doesn't exist) =====
CREATE OR REPLACE FUNCTION public.after_player_death_soulmate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_alive = false AND NEW.soulmate_id IS NOT NULL THEN
    IF (SELECT is_alive FROM players WHERE id = NEW.soulmate_id) = true THEN
      UPDATE players SET is_alive = false
      WHERE id = NEW.soulmate_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
