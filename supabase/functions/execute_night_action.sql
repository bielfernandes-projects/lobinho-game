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
v_used_power BOOLEAN;
v_result BOOLEAN;
v_wolves_resolved BOOLEAN;
v_target_role TEXT;
BEGIN
SELECT id, role, is_alive,
COALESCE(has_used_life_potion, false),
COALESCE(has_used_death_potion, false),
COALESCE(has_used_power, false)
INTO v_player_id, v_role, v_alive, v_used_life, v_used_death, v_used_power
FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;
IF v_player_id IS NULL THEN
RAISE EXCEPTION 'Jogador nao encontrado na sala';
END IF;
IF NOT v_alive THEN
RAISE EXCEPTION 'Jogadores mortos nao podem agir';
END IF;
IF (p_action_type = 'werewolf_kill' AND v_role <> ALL(pack_roles())) OR
(p_action_type = 'seer_investigate' AND v_role != 'seer') OR
(p_action_type IN ('witch_save', 'witch_poison', 'witch_skip') AND v_role != 'witch') OR
(p_action_type = 'priest_bless' AND v_role != 'priest') OR
(p_action_type = 'bodyguard_protect' AND v_role != 'bodyguard') OR
(p_action_type = 'aura_investigate' AND v_role != 'aura_seer') OR
(p_action_type = 'cult_convert' AND v_role != 'cult_leader') OR
(p_action_type = 'alpha_infect' AND v_role != 'alpha_wolf')
     OR
     (p_action_type = 'sorceress_search' AND v_role != 'sorceress')
THEN
RAISE EXCEPTION 'Acao invalida para o seu papel';
END IF;
IF p_action_type = 'alpha_infect' AND v_used_power THEN
RAISE EXCEPTION 'Voce ja usou seu poder especial';
END IF;
IF p_action_type = 'priest_bless' AND v_used_power THEN
RAISE EXCEPTION 'Voce ja usou seu poder especial';
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
ELSIF p_action_type = 'witch_skip' THEN
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, 'witch_skip', null)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
ELSIF p_action_type = 'old_witch_pox' THEN
    IF v_role = 'old_witch' AND EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn - 1
        AND action_type = 'old_witch_pox' AND target_id = p_target_id
    ) THEN
      RAISE EXCEPTION 'Nao pode escolher o mesmo jogador duas noites seguidas';
    END IF;
    IF v_role = 'old_witch' AND EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn - 1
        AND action_type = 'old_witch_pox' AND target_id = p_target_id
    ) THEN
      RAISE EXCEPTION 'Nao pode escolher o mesmo jogador duas noites seguidas';
    END IF;
    IF v_role <> 'old_witch' OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'virginia_partner' THEN
    IF v_role <> 'virginia_wolf' OR v_turn <> 1 OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'dire_wolf_companion' THEN
    IF v_role <> 'dire_wolf' OR v_turn <> 1 OR p_target_id IS NULL OR p_target_id = v_player_id THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'huntress_kill' THEN
    IF v_role <> 'huntress' THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    IF v_used_power THEN
      RAISE EXCEPTION 'Voce ja usou seu poder especial';
    END IF;
    UPDATE players SET has_used_power = true WHERE id = v_player_id;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'chupacabra_kill' THEN
    IF v_role <> 'chupacabra' THEN
      RAISE EXCEPTION 'Acao invalida para o seu papel';
    END IF;
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'priest_bless' THEN
UPDATE players SET has_used_power = true WHERE id = v_player_id;
UPDATE players SET is_blessed = true WHERE id = p_target_id;
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
ELSIF p_action_type = 'bodyguard_protect' THEN
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
ELSIF p_action_type = 'aura_investigate' THEN
SELECT (CASE WHEN role = 'drunk' THEN COALESCE((SELECT drunk_hidden_role FROM rooms WHERE id = p_room_id), role) ELSE role END) INTO v_target_role FROM players WHERE id = p_target_id;
v_result := (v_target_role <> 'villager' AND v_target_role <> ALL(pack_roles()));
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('has_special_role', v_result);
ELSIF p_action_type = 'cult_convert' THEN
UPDATE players SET in_cult = true WHERE id = p_target_id;
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
ELSIF p_action_type = 'alpha_infect' THEN
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
  ELSIF p_action_type = 'sorceress_search' THEN
    SELECT (CASE WHEN role = 'drunk' THEN COALESCE((SELECT drunk_hidden_role FROM rooms WHERE id = p_room_id), role) ELSE role END) INTO v_target_role FROM players WHERE id = p_target_id;
    v_result := (v_target_role = 'seer');
    INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
    VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
    ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
    RETURN jsonb_build_object('is_seer', v_result);
END IF;
IF p_action_type = 'seer_investigate' THEN
SELECT (CASE WHEN role = 'drunk' THEN COALESCE((SELECT drunk_hidden_role FROM rooms WHERE id = p_room_id), role) ELSE role END) = ANY(pack_roles() || 'lycan'::text) INTO v_result
FROM players WHERE id = p_target_id;
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id, result)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id, v_result)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('is_werewolf', v_result);
END IF;
INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
VALUES (p_room_id, v_turn, v_player_id, p_action_type, p_target_id)
ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;
RETURN jsonb_build_object('success', true);
END;
$function$
