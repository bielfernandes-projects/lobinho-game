-- Death module: kill_players + callers (resolve_night, host_execute_accused, marksman_shoot,
-- hunter_retaliate, insta_kill). Source of truth: supabase/functions/*.sql
-- Also fixes: Diseased skip dropping every night action, missing infected_id/cursed_converted_id.

-- Death module. One interface for "these players die": every death path calls this.
--   kill_players(room, ids, causes) -> {deaths: [{id,name,role,cause}], hunter_pending, hunter_id}
-- Chain deaths (soulmate, Dire Wolf companion, Virginia Wolf partner) are produced by the
-- AFTER UPDATE OF is_alive triggers; this module reports them by diffing who was alive before/after.
-- Post-effects live here once: Hunter pending, Prince -> Squire promotion, Doppelganger role copy.
CREATE OR REPLACE FUNCTION public.kill_players(p_room_id uuid, p_ids uuid[], p_causes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_before UUID[];
  v_deaths JSONB := '[]'::JSONB;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_prince_died BOOLEAN := false;
  v_squire_id UUID;
  r RECORD;
  v_cause TEXT;
  v_idx INT;
BEGIN
  SELECT COALESCE(array_agg(id), ARRAY[]::UUID[]) INTO v_before
  FROM players WHERE room_id = p_room_id AND is_alive = true;

  -- one statement: simultaneous deaths (Prince + Squire together, etc.)
  UPDATE players SET is_alive = false
  WHERE room_id = p_room_id AND is_alive = true AND id = ANY(p_ids);

  FOR r IN
    SELECT p.id, p.name, p.role, p.soulmate_id
    FROM players p
    WHERE p.room_id = p_room_id AND p.is_alive = false AND p.id = ANY(v_before)
    ORDER BY array_position(p_ids, p.id) NULLS LAST, p.name
  LOOP
    v_idx := array_position(p_ids, r.id);
    IF v_idx IS NOT NULL THEN
      v_cause := COALESCE(p_causes[v_idx], 'morte');
    ELSIF r.soulmate_id IS NOT NULL AND r.soulmate_id = ANY(p_ids) THEN
      v_cause := 'soulmate';
    ELSE
      v_cause := 'cadeia';
    END IF;

    v_deaths := v_deaths || jsonb_build_object('id', r.id, 'name', r.name, 'role', r.role, 'cause', v_cause);

    IF r.role = 'hunter' THEN
      v_hunter_pending := true;
      v_hunter_id := r.id;
    END IF;
    IF r.role = 'prince' THEN
      v_prince_died := true;
    END IF;
  END LOOP;

  -- Squire inherits the Prince only after ALL simultaneous deaths are settled
  IF v_prince_died THEN
    SELECT id INTO v_squire_id FROM players
    WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
    IF v_squire_id IS NOT NULL THEN
      UPDATE players SET role = 'prince' WHERE id = v_squire_id;
    END IF;
  END IF;

  -- Doppelganger copies the role of a dead target
  UPDATE players d SET role = t.role
  FROM players t
  WHERE d.room_id = p_room_id AND d.is_alive = true AND d.role = 'doppelganger'
    AND d.doppelganger_target_id = t.id AND t.is_alive = false;

  RETURN jsonb_build_object(
    'deaths', v_deaths,
    'hunter_pending', v_hunter_pending,
    'hunter_id', v_hunter_id
  );
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
$function$;

-- Lynch the accused. Decides who actually dies (Prince immunity, Cursed conversion, Martyr swap,
-- Old Witch immunity) and delegates the death itself, and everything that follows from it, to the
-- death module (kill_players).
CREATE OR REPLACE FUNCTION public.host_execute_accused(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_accused_id UUID;
  v_accused_name TEXT;
  v_accused_role TEXT;
  v_martyr UUID;
  v_turn INT;
  v_game_over JSONB;
  v_prince_revealed BOOLEAN := false;
  v_kill JSONB;
  v_deaths JSONB := '[]'::JSONB;
  v_extra JSONB := '[]'::JSONB;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode executar esta ação';
  END IF;

  SELECT current_accused_id, turn_index, martyr_id INTO v_accused_id, v_turn, v_martyr
  FROM game_state WHERE room_id = p_room_id;

  IF v_accused_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum acusado para executar';
  END IF;

  -- Old Witch: the poxed player is out of the village today
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = v_accused_id) THEN
    RAISE EXCEPTION 'Acusado esta fora da vila hoje';
  END IF;

  -- Martyr takes the accused's place
  IF v_martyr IS NOT NULL AND EXISTS (
    SELECT 1 FROM players WHERE id = v_martyr AND is_alive = true AND role = 'martyr'
  ) THEN
    v_accused_id := v_martyr;
  END IF;
  UPDATE game_state SET martyr_id = NULL WHERE room_id = p_room_id;

  SELECT name, role INTO v_accused_name, v_accused_role FROM players WHERE id = v_accused_id;

  -- Prince: first lynch only reveals him
  SELECT prince_revealed INTO v_prince_revealed FROM game_state WHERE room_id = p_room_id;
  IF v_accused_role = 'prince' AND NOT v_prince_revealed THEN
    UPDATE game_state
    SET current_phase = 'day', day_step = 'prince_reveal',
        turn_index = v_turn, current_accused_id = NULL,
        prince_revealed = true,
        last_event = jsonb_build_object('type', 'prince_reveal', 'victim_id', v_accused_id, 'victim_name', v_accused_name, 'victim_role', v_accused_role),
        last_vote_result = jsonb_build_object('type', 'prince_reveal', 'victim_name', v_accused_name, 'victim_role', v_accused_role)
    WHERE room_id = p_room_id;
    RETURN jsonb_build_object('success', true, 'prince_reveal', true, 'victim_name', v_accused_name);
  END IF;

  -- Cursed: lynching converts, does not kill
  IF v_accused_role = 'cursed' THEN
    UPDATE players SET role = 'werewolf' WHERE id = v_accused_id;
    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        current_accused_id = NULL,
        last_event = jsonb_build_object(
          'type', 'vote_result', 'event_type', 'lynch',
          'victim_id', v_accused_id, 'victim_name', v_accused_name,
          'victim_role', 'werewolf',
          'cursed_converted', true,
          'cursed_converted_id', v_accused_id,
          'cursed_converted_name', v_accused_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch', 'victim_name', v_accused_name, 'victim_role', 'werewolf',
          'cursed_converted', true,
          'cursed_converted_name', v_accused_name
        )
    WHERE room_id = p_room_id;
    v_game_over := check_game_over(p_room_id);
    RETURN jsonb_build_object('success', true, 'cursed_converted', true, 'game_over', v_game_over);
  END IF;

  -- Everything else dies through the death module
  v_kill := kill_players(p_room_id, ARRAY[v_accused_id], ARRAY['linchamento']);
  v_deaths := v_kill->'deaths';
  v_hunter_pending := COALESCE((v_kill->>'hunter_pending')::BOOLEAN, false);
  v_hunter_id := NULLIF(v_kill->>'hunter_id', '')::UUID;

  -- Chain deaths (soulmate, companion, partner) besides the accused, announced like the rest
  SELECT COALESCE(jsonb_agg(d), '[]'::JSONB) INTO v_extra
  FROM jsonb_array_elements(v_deaths) d WHERE d->>'id' <> v_accused_id::TEXT;

  SELECT d->>'name', d->>'role' INTO v_soulmate_name, v_soulmate_role
  FROM jsonb_array_elements(v_extra) d WHERE d->>'cause' = 'soulmate' LIMIT 1;

  UPDATE game_state
  SET current_phase = 'day',
      day_step = CASE WHEN v_hunter_pending THEN 'hunter_reveal' ELSE 'lynch_reveal' END,
      turn_index = v_turn, phase_started_at = now(), current_accused_id = NULL,
      last_event = jsonb_build_object(
        'type', 'vote_result', 'event_type', 'lynch',
        'victim_id', v_accused_id, 'victim_name', v_accused_name,
        'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
        'extra_deaths', v_extra
      ),
      last_vote_result = jsonb_build_object(
        'type', 'lynch',
        'victim_name', v_accused_name, 'victim_role', v_accused_role,
        'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
        'extra_deaths', v_extra
      ),
      hunter_pending = v_hunter_pending,
      hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over, 'hunter_pending', v_hunter_pending);
END;
$function$;

CREATE OR REPLACE FUNCTION public.marksman_shoot(p_room_id uuid, p_target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_marksman_id UUID;
  v_alive BOOLEAN;
  v_used_power BOOLEAN;
  v_current_phase TEXT;
  v_day_step TEXT;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;
  SELECT id, is_alive, COALESCE(has_used_power, false)
  INTO v_marksman_id, v_alive, v_used_power
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_marksman_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_alive THEN
    RAISE EXCEPTION 'Jogadores mortos não podem agir';
  END IF;

  IF (SELECT role FROM players WHERE id = v_marksman_id) != 'marksman' THEN
    RAISE EXCEPTION 'Ação inválida para o seu papel';
  END IF;

  IF v_used_power THEN
    RAISE EXCEPTION 'Você já usou seu tiro';
  END IF;

  -- B2 FIX: impedir auto-target
  IF p_target_id = v_marksman_id THEN
    RAISE EXCEPTION 'Você não pode atirar em si mesmo';
  END IF;

  SELECT current_phase, day_step, turn_index
  INTO v_current_phase, v_day_step, v_turn
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase != 'day' THEN
    RAISE EXCEPTION 'Só pode atirar durante o dia';
  END IF;

  IF v_day_step != 'discussion' THEN
    RAISE EXCEPTION 'Só pode atirar durante a discussão';
  END IF;

  SELECT name INTO v_target_name
  FROM players
  WHERE id = p_target_id AND is_alive = true AND is_host = false;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou não é válido';
  END IF;

  UPDATE players SET has_used_power = true WHERE id = v_marksman_id;
  -- death module: chain deaths, Prince -> Squire, Doppelganger (Hunter retaliation is not triggered by day shots)
  v_kill := kill_players(p_room_id, ARRAY[p_target_id], ARRAY['atirador']);

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.hunter_retaliate(p_room_id uuid, p_target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hunter_id UUID;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  IF EXISTS (SELECT 1 FROM game_state WHERE room_id = p_room_id AND poxed_id = p_target_id) THEN
    RAISE EXCEPTION 'Alvo esta fora da vila hoje';
  END IF;
  -- Verificar que existe hunter_pending
  SELECT hunter_id INTO v_hunter_id
  FROM game_state WHERE room_id = p_room_id;

  IF v_hunter_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum Caçador pendente de retaliação';
  END IF;

  -- Verificar que o alvo está vivo
  SELECT name INTO v_target_name FROM players WHERE id = p_target_id AND is_alive = true;
  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado ou já está morto';
  END IF;

  -- Verificar que o alvo não é o próprio Hunter
  IF p_target_id = v_hunter_id THEN
    RAISE EXCEPTION 'Você não pode atirar em si mesmo';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Matar o alvo
  v_kill := kill_players(p_room_id, ARRAY[p_target_id], ARRAY['cacador']);

  -- Registrar a ação no log noturno
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_hunter_id, 'hunter_shot', p_target_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Limpar estado do Hunter
  UPDATE game_state
  SET hunter_pending = false, hunter_id = NULL
  WHERE room_id = p_room_id;

  -- Verificar game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.insta_kill(p_room_id uuid, p_player_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_target_alive BOOLEAN;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
  v_kill JSONB;
BEGIN
  -- Verificar que o caller é o host
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode matar jogadores';
  END IF;

  -- Verificar que o alvo está vivo
  SELECT is_alive, name INTO v_target_alive, v_target_name
  FROM players WHERE id = p_player_id AND room_id = p_room_id;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado na sala';
  END IF;

  IF NOT v_target_alive THEN
    RAISE EXCEPTION 'Jogador já está morto';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Matar
  UPDATE players SET strikes = 0 WHERE id = p_player_id;
  v_kill := kill_players(p_room_id, ARRAY[p_player_id], ARRAY['strike']);

  -- Log
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_caller_id, 'insta_kill', p_player_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'deaths', v_kill->'deaths',
    'game_over', v_game_over
  );
END;
$function$;

