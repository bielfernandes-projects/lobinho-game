-- Role groups as database functions (pack_roles / wolf_team_roles) + every function that listed wolves now uses them.
-- Also: players can only update has_viewed_card / viewed_card_at from the client (players_update_own allowed ANY column,
-- e.g. changing their own role or resurrecting themselves). SECURITY DEFINER functions are unaffected.

-- Role groups, defined ONCE for the database. Keep in sync with src/lib/night-steps.ts (WOLF_ROLES).
--   pack_roles()      roles that wake with the wolves, vote on the victim and are seen as wolves
--   wolf_team_roles() roles that count as the wolf team for win conditions
CREATE OR REPLACE FUNCTION public.pack_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY['werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'lone_wolf']::text[]
$function$;

CREATE OR REPLACE FUNCTION public.wolf_team_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY['werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'sorceress', 'minion']::text[]
$function$;

-- Win conditions in ONE place. Pure: reads the room, writes nothing.
-- Returns the winner key or NULL when the game goes on. Priority order:
--   lone_wolf (last alive) > chupacabra (last alive) > soulmates > cult > tanner >
--   (no wolf-team alive: lone wolf 1v1 > chupacabra 1v1 > villagers) > wolves parity.
-- Callers: check_game_over (RPC use) and trg_check_game_over (trigger on players.is_alive).
CREATE OR REPLACE FUNCTION public.compute_winner(p_room_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_alive_count INT;
  v_lone_wolf BOOLEAN;
  v_chupacabra BOOLEAN;
BEGIN
  SELECT turn_index, current_phase, last_event INTO v_turn_index, v_phase, v_last_event
  FROM game_state WHERE room_id = p_room_id;
  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NULL;
  END IF;

  SELECT COUNT(*) FILTER (WHERE is_alive AND role <> 'moderator'),
         COUNT(*) FILTER (WHERE is_alive AND role = ANY(wolf_team_roles())),
         COUNT(*) FILTER (WHERE is_alive AND role <> ALL(wolf_team_roles()) AND role <> 'moderator'),
         COALESCE(BOOL_OR(is_alive AND role = 'lone_wolf'), false),
         COALESCE(BOOL_OR(is_alive AND role = 'chupacabra'), false)
  INTO v_alive_count, v_wolves, v_non_wolves, v_lone_wolf, v_chupacabra
  FROM players WHERE room_id = p_room_id;

  -- Last one standing
  IF v_alive_count = 1 AND v_lone_wolf THEN RETURN 'lone_wolf_win'; END IF;
  IF v_alive_count = 1 AND v_chupacabra THEN RETURN 'chupacabra_win'; END IF;

  -- Soulmates: exactly the two lovers left
  IF v_alive_count = 2 AND EXISTS (
    SELECT 1 FROM players a JOIN players b ON b.id = a.soulmate_id
    WHERE a.room_id = p_room_id AND a.is_alive AND b.is_alive
      AND a.role <> 'moderator' AND b.role <> 'moderator' AND b.soulmate_id = a.id
  ) THEN RETURN 'soulmates_win'; END IF;

  -- Cult: every other living player converted
  IF EXISTS (SELECT 1 FROM players WHERE room_id = p_room_id AND is_alive AND role = 'cult_leader')
     AND NOT EXISTS (
       SELECT 1 FROM players
       WHERE room_id = p_room_id AND is_alive
         AND role NOT IN ('moderator', 'cult_leader') AND in_cult = false
     ) THEN RETURN 'cult_win'; END IF;

  -- Tanner: lynched
  IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
    SELECT 1 FROM players
    WHERE id = (v_last_event->>'victim_id')::UUID AND role = 'tanner' AND is_alive = false
  ) THEN RETURN 'tanner_win'; END IF;

  -- Wolf team vs the rest
  IF v_wolves = 0 THEN
    IF v_lone_wolf THEN
      IF v_alive_count <= 2 THEN RETURN 'lone_wolf_win'; END IF;
      RETURN NULL;
    END IF;
    IF v_chupacabra THEN
      IF v_alive_count <= 2 THEN RETURN 'chupacabra_win'; END IF;
      RETURN NULL;
    END IF;
    RETURN 'villagers_win';
  ELSIF v_wolves >= v_non_wolves THEN
    RETURN 'wolves_win';
  END IF;

  RETURN NULL;
END;
$function$;

-- Resolves the night. Decides WHO dies (protections, conversions, deferrals) and hands the whole
-- list to the death module (kill_players) in one call, so chain deaths, Hunter, Prince/Squire and
-- Doppelganger are handled in one place.
CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn INT;
  v_frenzy BOOLEAN;
  v_diseased_skip BOOLEAN := false;
  v_wolves_alive_at_start INT;
  v_priest_target_id UUID;
  v_wolf_target_ids UUID[];
  v_wolf_target_id UUID;
  v_wolf_target2_id UUID;
  v_witch_save BOOLEAN;
  v_poison_target_id UUID;
  v_chupa_target_id UUID;
  v_huntress_target_id UUID;
  v_bodyguard_id UUID;
  v_role TEXT;
  v_kill_ids UUID[] := ARRAY[]::UUID[];
  v_kill_causes TEXT[] := ARRAY[]::TEXT[];
  v_kill JSONB;
  v_victims JSONB := '[]'::JSONB;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_diseased_died BOOLEAN := false;
  v_alpha_infected_id UUID;
  v_alpha_infected_name TEXT;
  v_cursed_converted BOOLEAN := false;
  v_cursed_converted_id UUID;
  v_cursed_converted_name TEXT;
  v_game_over JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;
  SELECT COALESCE(wolves_frenzy, false) INTO v_frenzy FROM rooms WHERE id = p_room_id;
  SELECT COALESCE(diseased_skip_wolves, false) INTO v_diseased_skip FROM game_state WHERE room_id = p_room_id;
  SELECT target_id INTO v_bodyguard_id FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect' LIMIT 1;
  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save;

  -- Old Witch: tonight's pox target sits out the next day
  UPDATE game_state SET poxed_id = (
    SELECT target_id FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'old_witch_pox' LIMIT 1
  ) WHERE room_id = p_room_id;

  SELECT COUNT(*) INTO v_wolves_alive_at_start FROM players
  WHERE room_id = p_room_id AND is_alive = true
    AND role = ANY(pack_roles());

  -- Priest: blessing (protects against wolves and poison only)
  SELECT target_id INTO v_priest_target_id FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless' LIMIT 1;
  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- Wolves. A Diseased killed last night makes the wolves skip THIS night only; every other
  -- night action still happens.
  IF v_diseased_skip THEN
    UPDATE game_state SET diseased_skip_wolves = false WHERE room_id = p_room_id;
    UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;
    v_frenzy := false;
  ELSE
    SELECT ARRAY_AGG(DISTINCT target_id) INTO v_wolf_target_ids FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';
    v_wolf_target_id := v_wolf_target_ids[1];
    IF v_frenzy AND array_length(v_wolf_target_ids, 1) >= 2 THEN
      v_wolf_target2_id := v_wolf_target_ids[2];
    END IF;

    -- Tough Guy: attack is deferred to a later night (unless protected)
    IF v_wolf_target_id IS NOT NULL
       AND (SELECT role FROM players WHERE id = v_wolf_target_id) = 'tough_guy' THEN
      IF COALESCE((SELECT is_blessed FROM players WHERE id = v_wolf_target_id), false) THEN
        UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
      ELSIF NOT v_witch_save AND (v_bodyguard_id IS NULL OR v_bodyguard_id <> v_wolf_target_id) THEN
        INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
        VALUES (p_room_id, v_turn, v_wolf_target_id, 'tough_guy_doomed', v_wolf_target_id)
        ON CONFLICT DO NOTHING;
      END IF;
      v_wolf_target_id := NULL;
    END IF;

    -- Target 1
    IF v_wolf_target_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn
          AND action_type = 'alpha_infect' AND target_id = v_wolf_target_id
      ) THEN
        UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
        SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target_id;
        v_alpha_infected_id := v_wolf_target_id;
        UPDATE players SET has_used_power = true
        WHERE room_id = p_room_id AND role = 'alpha_wolf' AND has_used_power = false;
      ELSE
        SELECT role INTO v_role FROM players WHERE id = v_wolf_target_id;
        IF v_role = 'cursed' THEN
          UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
          v_cursed_converted := true;
          v_cursed_converted_id := v_wolf_target_id;
          SELECT name INTO v_cursed_converted_name FROM players WHERE id = v_wolf_target_id;
        ELSIF COALESCE((SELECT is_blessed FROM players WHERE id = v_wolf_target_id), false) THEN
          UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
        ELSIF NOT v_witch_save AND (v_bodyguard_id IS NULL OR v_bodyguard_id <> v_wolf_target_id) THEN
          v_kill_ids := array_append(v_kill_ids, v_wolf_target_id);
          v_kill_causes := array_append(v_kill_causes, 'lobisomem');
          IF v_role = 'diseased' THEN v_diseased_died := true; END IF;
        END IF;
      END IF;
    END IF;

    -- Target 2 (frenzy)
    IF v_wolf_target2_id IS NOT NULL THEN
      IF COALESCE((SELECT is_blessed FROM players WHERE id = v_wolf_target2_id), false) THEN
        UPDATE players SET is_blessed = false WHERE id = v_wolf_target2_id;
      ELSIF NOT v_witch_save AND (v_bodyguard_id IS NULL OR v_bodyguard_id <> v_wolf_target2_id)
            AND NOT (v_wolf_target2_id = ANY(v_kill_ids)) THEN
        v_kill_ids := array_append(v_kill_ids, v_wolf_target2_id);
        v_kill_causes := array_append(v_kill_causes, 'lobisomem');
        IF (SELECT role FROM players WHERE id = v_wolf_target2_id) = 'diseased' THEN
          v_diseased_died := true;
        END IF;
      END IF;
    END IF;
  END IF;

  -- Witch: poison (Priest blessing and Bodyguard protect; the life potion does not)
  SELECT target_id INTO v_poison_target_id FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison' LIMIT 1;
  IF v_poison_target_id IS NOT NULL AND NOT (v_poison_target_id = ANY(v_kill_ids)) THEN
    IF COALESCE((SELECT is_blessed FROM players WHERE id = v_poison_target_id), false) THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    ELSIF v_bodyguard_id IS NULL OR v_bodyguard_id <> v_poison_target_id THEN
      v_kill_ids := array_append(v_kill_ids, v_poison_target_id);
      v_kill_causes := array_append(v_kill_causes, 'veneno');
    END IF;
  END IF;

  -- Chupacabra: kills wolves only (anyone once all wolves were dead). Bodyguard and the life
  -- potion protect; the Priest does not.
  SELECT target_id INTO v_chupa_target_id FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'chupacabra_kill' LIMIT 1;
  IF v_chupa_target_id IS NOT NULL
     AND (SELECT is_alive FROM players WHERE id = v_chupa_target_id)
     AND NOT (v_chupa_target_id = ANY(v_kill_ids))
     AND NOT v_witch_save
     AND (v_bodyguard_id IS NULL OR v_bodyguard_id <> v_chupa_target_id) THEN
    SELECT role INTO v_role FROM players WHERE id = v_chupa_target_id;
    IF v_wolves_alive_at_start = 0
       OR v_role = ANY(pack_roles()) THEN
      v_kill_ids := array_append(v_kill_ids, v_chupa_target_id);
      v_kill_causes := array_append(v_kill_causes, 'chupacabra');
    END IF;
  END IF;

  -- Huntress: one shot; Bodyguard protects, Priest does not
  SELECT target_id INTO v_huntress_target_id FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'huntress_kill' LIMIT 1;
  IF v_huntress_target_id IS NOT NULL
     AND (SELECT is_alive FROM players WHERE id = v_huntress_target_id)
     AND NOT (v_huntress_target_id = ANY(v_kill_ids))
     AND (v_bodyguard_id IS NULL OR v_bodyguard_id <> v_huntress_target_id) THEN
    v_kill_ids := array_append(v_kill_ids, v_huntress_target_id);
    v_kill_causes := array_append(v_kill_causes, 'cacadora');
  END IF;

  -- Tough Guy marked on a PREVIOUS night dies now
  SELECT v_kill_ids || COALESCE(array_agg(na.target_id), ARRAY[]::UUID[]),
         v_kill_causes || COALESCE(array_agg('lobisomem'::text), ARRAY[]::TEXT[])
  INTO v_kill_ids, v_kill_causes
  FROM night_actions na JOIN players p ON p.id = na.target_id
  WHERE na.room_id = p_room_id AND na.action_type = 'tough_guy_doomed'
    AND na.turn_index < v_turn AND p.is_alive = true AND p.role = 'tough_guy'
    AND NOT (na.target_id = ANY(v_kill_ids));

  -- Ghost card: programmed to die on the first night
  IF v_turn = 1 THEN
    SELECT v_kill_ids || COALESCE(array_agg(id), ARRAY[]::UUID[]),
           v_kill_causes || COALESCE(array_agg('fantasma'::text), ARRAY[]::TEXT[])
    INTO v_kill_ids, v_kill_causes
    FROM players
    WHERE room_id = p_room_id AND role = 'ghost' AND is_alive = true
      AND NOT (id = ANY(v_kill_ids));
  END IF;

  -- Frenzy is consumed tonight. Cleared BEFORE the deaths so that a Wolf Cub dying tonight
  -- (its trigger sets frenzy for the NEXT night) is not wiped.
  IF v_frenzy THEN
    UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id;
  END IF;

  -- Everyone dies through the death module, in one call
  IF array_length(v_kill_ids, 1) > 0 THEN
    v_kill := kill_players(p_room_id, v_kill_ids, v_kill_causes);
    v_victims := v_kill->'deaths';
    v_hunter_pending := COALESCE((v_kill->>'hunter_pending')::BOOLEAN, false);
    v_hunter_id := NULLIF(v_kill->>'hunter_id', '')::UUID;
  END IF;

  -- A Diseased killed by the wolves makes the wolves skip the NEXT night
  IF v_diseased_died THEN
    UPDATE game_state SET diseased_skip_wolves = true WHERE room_id = p_room_id;
  END IF;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = 'announcement',
      turn_index = v_turn,
      phase_started_at = now(),
      wolves_resolved = false,
      last_event = jsonb_build_object(
        'type', 'night_result',
        'victims', v_victims,
        'wolf_votes', (
          SELECT COUNT(*) FROM night_actions
          WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
        ),
        'diseased_skip', v_diseased_skip,
        'cursed_converted', v_cursed_converted,
        'cursed_converted_id', v_cursed_converted_id,
        'cursed_converted_name', v_cursed_converted_name,
        'infected_id', v_alpha_infected_id,
        'infected_name', v_alpha_infected_name
      ),
      last_vote_result = NULL,
      hunter_pending = v_hunter_pending,
      hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'victims', v_victims,
    'hunter_pending', v_hunter_pending,
    'cursed_converted', v_cursed_converted,
    'diseased_skip', v_diseased_skip,
    'game_over', v_game_over
  );
END;
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.get_werewolf_teammates(p_room_id uuid)
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT role FROM players WHERE user_id = auth.uid() AND room_id = p_room_id)
     <> ALL(pack_roles()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT p.id, p.name::text
  FROM players p
  WHERE p.room_id = p_room_id
    AND p.role = ANY(pack_roles())
    AND p.user_id != auth.uid();
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_wolf_consensus(p_room_id uuid)
 RETURNS TABLE(voter_id uuid, voter_name text, target_id uuid, target_name text, target_index smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_turn_index INT;
BEGIN
    SELECT turn_index INTO v_turn_index
    FROM game_state
    WHERE room_id = p_room_id;

    IF v_turn_index IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        cv.voter_id,
        vp.name::TEXT AS voter_name,
        cv.target_id,
        tp.name::TEXT AS target_name,
        cv.target_index
    FROM consensus_votes cv
    JOIN players vp ON vp.id = cv.voter_id
    LEFT JOIN players tp ON tp.id = cv.target_id
    WHERE cv.room_id = p_room_id
      AND cv.turn_index = v_turn_index
      AND vp.role = ANY(pack_roles())
      AND vp.is_alive = true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_wolves_for_sorceress(p_room_id uuid)
 RETURNS TABLE(id uuid, name text, is_alive boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM players p
        WHERE p.room_id = p_room_id AND p.user_id = auth.uid() AND p.role IN ('sorceress', 'minion')
    ) THEN
        RAISE EXCEPTION 'Apenas a Feiticeira pode ver os lobos';
    END IF;

    RETURN QUERY
    SELECT p.id, p.name, p.is_alive
    FROM players p
    WHERE p.room_id = p_room_id
      AND p.role = ANY(pack_roles());
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_consensus_vote(p_room_id uuid, p_target_id uuid, p_target_index smallint DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_player_id UUID;
    v_turn_index INT;
BEGIN
    -- Resolve player from auth
    SELECT id INTO v_player_id
    FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid()
    LIMIT 1;

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'Player not found in room';
    END IF;

    -- Alive guard: dead wolves cannot vote
    IF NOT EXISTS (
        SELECT 1 FROM players
        WHERE id = v_player_id
          AND is_alive = true
    ) THEN
        RAISE EXCEPTION 'Jogadores mortos não podem votar';
    END IF;

    -- Role guard: only wolf variants can vote
    IF NOT EXISTS (
        SELECT 1 FROM players
        WHERE id = v_player_id
          AND role = ANY(pack_roles())
    ) THEN
        RAISE EXCEPTION 'Apenas lobisomens podem votar';
    END IF;

    -- Get current turn index
    SELECT turn_index INTO v_turn_index
    FROM game_state
    WHERE room_id = p_room_id;

    IF v_turn_index IS NULL THEN
        RAISE EXCEPTION 'Game state not found';
    END IF;

    -- Upsert the vote
    INSERT INTO consensus_votes (room_id, turn_index, voter_id, target_id, target_index, updated_at)
    VALUES (p_room_id, v_turn_index, v_player_id, p_target_id, p_target_index, NOW())
    ON CONFLICT (room_id, turn_index, voter_id, target_index)
    DO UPDATE SET target_id = p_target_id, updated_at = NOW();
END;
$function$;

REVOKE UPDATE ON public.players FROM anon, authenticated;
GRANT UPDATE (has_viewed_card, viewed_card_at) ON public.players TO authenticated;
