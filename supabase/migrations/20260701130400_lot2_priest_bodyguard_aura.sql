-- Migration: Lote 2 - Padre, Guarda-costas, Vidente de Aura
-- 1. is_blessed column on players
-- 2. Updated night_actions constraint
-- 3. Updated execute_night_action with 3 new action types
-- 4. Updated resolve_night with bodyguard + blessing checks

-- 1. Add is_blessed column
ALTER TABLE players ADD COLUMN IF NOT EXISTS is_blessed BOOLEAN NOT NULL DEFAULT false;

-- 2. Update night_actions constraint to include new action types
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN (
    'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
    'priest_bless', 'bodyguard_protect', 'aura_investigate'
  ));

-- 3. Updated execute_night_action
CREATE OR REPLACE FUNCTION public.execute_night_action(p_room_id uuid, p_action_type text, p_target_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn INT;
  v_player_id UUID;
  v_role TEXT;
  v_alive BOOLEAN;
  v_used_life BOOLEAN;
  v_used_death BOOLEAN;
  v_result BOOLEAN;
  v_wolves_resolved BOOLEAN;
  v_target_role TEXT;
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
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch') OR
     (p_action_type = 'priest_bless' AND v_role != 'priest') OR
     (p_action_type = 'bodyguard_protect' AND v_role != 'bodyguard') OR
     (p_action_type = 'aura_investigate' AND v_role != 'aura_seer')
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
  ELSIF p_action_type = 'priest_bless' THEN
    UPDATE players SET is_blessed = true WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'bodyguard_protect' THEN
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'aura_investigate' THEN
    SELECT role INTO v_target_role
    FROM players WHERE id = p_target_id;

    v_result := (v_target_role NOT IN ('villager', 'werewolf'));

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('has_special_role', v_result);
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role IN ('werewolf', 'lycan') INTO v_result
    FROM players WHERE id = p_target_id;

    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

    RETURN jsonb_build_object('is_werewolf', v_result);
  END IF;

  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- 4. Updated resolve_night with bodyguard + blessing check
DROP FUNCTION IF EXISTS public.resolve_night(UUID) CASCADE;
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
  v_bodyguard_target_id UUID;
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_victims JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT target_id INTO v_wolf_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
  GROUP BY target_id
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  SELECT target_id INTO v_bodyguard_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

  v_is_blessed := false;
  IF v_wolf_target_id IS NOT NULL THEN
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_wolf_target_id;
  END IF;

  v_killed_by_wolves := v_wolf_target_id IS NOT NULL
    AND NOT v_witch_save_exists
    AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
    AND NOT v_is_blessed;

  IF v_wolf_target_id IS NOT NULL AND v_is_blessed THEN
    UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
  END IF;

  IF v_killed_by_wolves THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
  END IF;

  v_victims := '[]'::JSONB;
  IF v_killed_by_wolves AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno');
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'announcement',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims)
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;
