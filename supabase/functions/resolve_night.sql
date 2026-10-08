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
    AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'lone_wolf');

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
       OR v_role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'lone_wolf') THEN
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
$function$
