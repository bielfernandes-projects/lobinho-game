-- Fix Lote 4 (wolf_cub, alpha_wolf, lone_wolf)
-- 1) check_game_over/trg_check_game_over now count wolf_cub and alpha_wolf as wolves.
-- 2) resolve_night no longer tries to set wolves_frenzy on game_state (it lives on rooms).

-- ═══ FIX 1: check_game_over — include wolf_cub and alpha_wolf in wolf count ═══

CREATE OR REPLACE FUNCTION public.check_game_over(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_alive_count INT;
  v_winner TEXT;
  v_winner_display TEXT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN jsonb_build_object('game_over', false, 'skipped', true);
  END IF;

  SELECT COUNT(*) FILTER (WHERE is_alive = true AND role != 'moderator')
  INTO v_alive_count
  FROM players WHERE room_id = p_room_id;

  -- PRIORITY 0: Lone Wolf win
  IF v_alive_count = 1 THEN
    IF EXISTS (
      SELECT 1 FROM players
      WHERE room_id = p_room_id AND is_alive = true AND role = 'lone_wolf'
    ) THEN
      UPDATE game_state SET winner = 'lone_wolf_win' WHERE room_id = p_room_id;
      RETURN jsonb_build_object('game_over', true, 'winner', 'lone_wolf_win', 'display', 'Lobo Solitario Venceu');
    END IF;
  END IF;

  -- PRIORITY 1: Soulmates win
  IF v_alive_count = 2 THEN
    IF EXISTS (
      SELECT 1 FROM players a
      JOIN players b ON b.id = a.soulmate_id
      WHERE a.room_id = p_room_id
        AND a.is_alive = true AND b.is_alive = true
        AND a.role != 'moderator' AND b.role != 'moderator'
        AND b.soulmate_id = a.id
    ) THEN
      UPDATE game_state SET winner = 'soulmates_win' WHERE room_id = p_room_id;
      RETURN jsonb_build_object('game_over', true, 'winner', 'soulmates_win');
    END IF;
  END IF;

  -- PRIORITY 2: Cult win
  IF EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND is_alive = true AND role = 'cult_leader'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM players
      WHERE room_id = p_room_id AND is_alive = true
        AND role NOT IN ('moderator', 'cult_leader')
        AND in_cult = false
    ) THEN
      UPDATE game_state SET winner = 'cult_win' WHERE room_id = p_room_id;
      RETURN jsonb_build_object('game_over', true, 'winner', 'cult_win');
    END IF;
  END IF;

  -- PRIORITY 3: tanner win
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = p_room_id;
  IF v_last_event->>'event_type' = 'lynch' AND EXISTS (
    SELECT 1 FROM players
    WHERE id = (v_last_event->>'victim_id')::UUID
      AND role = 'tanner' AND is_alive = false
  ) THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = p_room_id;
    RETURN jsonb_build_object('game_over', true, 'winner', 'tanner_win', 'display', 'Curtidor Venceu');
  END IF;

  -- Standard wolf/village check — includes wolf_cub and alpha_wolf as wolves
  -- lone_wolf counts as non_wolf (independent faction)
  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf')),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = p_room_id;

  IF v_wolves = 0 THEN
    v_winner := 'villagers_win';
    v_winner_display := 'Aldeoes Venceram';
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = p_room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    v_winner := 'wolves_win';
    v_winner_display := 'Lobisomens Venceram';
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = p_room_id;
  END IF;

  IF v_winner IS NULL THEN
    RETURN jsonb_build_object('game_over', false);
  END IF;

  RETURN jsonb_build_object('game_over', true, 'winner', v_winner, 'display', v_winner_display);
END;
$$;


-- ═══ FIX 2: trg_check_game_over — same correction in trigger ═══

CREATE OR REPLACE FUNCTION public.trg_check_game_over()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn_index INT;
  v_phase TEXT;
  v_last_event JSONB;
  v_wolves INT;
  v_non_wolves INT;
  v_alive_count INT;
BEGIN
  SELECT turn_index, current_phase INTO v_turn_index, v_phase
  FROM game_state WHERE room_id = NEW.room_id;

  IF v_turn_index IS NULL OR v_turn_index = 0 OR v_phase = 'card_reveal' THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) FILTER (WHERE is_alive = true AND role != 'moderator')
  INTO v_alive_count
  FROM players WHERE room_id = NEW.room_id;

  -- PRIORITY 0: Lone Wolf win
  IF v_alive_count = 1 THEN
    IF EXISTS (
      SELECT 1 FROM players
      WHERE room_id = NEW.room_id AND is_alive = true AND role = 'lone_wolf'
    ) THEN
      UPDATE game_state SET winner = 'lone_wolf_win' WHERE room_id = NEW.room_id;
      RETURN NEW;
    END IF;
  END IF;

  -- PRIORITY 1: Soulmates win
  IF v_alive_count = 2 THEN
    IF EXISTS (
      SELECT 1 FROM players a
      JOIN players b ON b.id = a.soulmate_id
      WHERE a.room_id = NEW.room_id AND a.is_alive = true AND b.is_alive = true
        AND a.role != 'moderator' AND b.role != 'moderator' AND b.soulmate_id = a.id
    ) THEN
      UPDATE game_state SET winner = 'soulmates_win' WHERE room_id = NEW.room_id;
      RETURN NEW;
    END IF;
  END IF;

  -- PRIORITY 2: Cult win
  IF EXISTS (
    SELECT 1 FROM players
    WHERE room_id = NEW.room_id AND is_alive = true AND role = 'cult_leader'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM players
      WHERE room_id = NEW.room_id AND is_alive = true
        AND role NOT IN ('moderator', 'cult_leader') AND in_cult = false
    ) THEN
      UPDATE game_state SET winner = 'cult_win' WHERE room_id = NEW.room_id;
      RETURN NEW;
    END IF;
  END IF;

  -- PRIORITY 3: tanner win
  SELECT last_event INTO v_last_event FROM game_state WHERE room_id = NEW.room_id;
  IF NEW.role = 'tanner' AND NEW.is_alive = false
     AND v_last_event->>'event_type' = 'lynch' AND v_last_event->>'victim_id' = NEW.id::TEXT
  THEN
    UPDATE game_state SET winner = 'tanner_win' WHERE room_id = NEW.room_id;
    RETURN NEW;
  END IF;

  -- Standard wolf/village check — includes wolf_cub and alpha_wolf as wolves
  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role IN ('werewolf', 'wolf_cub', 'alpha_wolf')),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'moderator'))
  INTO v_wolves, v_non_wolves
  FROM players WHERE room_id = NEW.room_id;

  IF v_wolves = 0 THEN
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = NEW.room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = NEW.room_id;
  END IF;

  RETURN NEW;
END;
$$;


-- ═══ FIX 3: resolve_night — remove wolves_frenzy from UPDATE game_state ═══
-- wolves_frenzy is a column on rooms, not game_state.
-- Cleanup is already done by: UPDATE rooms SET wolves_frenzy = false

CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_priest_target_id UUID;
  v_frenzy BOOLEAN;
  v_wolf_target_ids UUID[];
  v_wolf_target_id UUID;
  v_wolf_target2_id UUID;
  v_wolf_target_name TEXT;
  v_wolf_target_role TEXT;
  v_wolf_target2_name TEXT;
  v_wolf_target2_role TEXT;
  v_witch_save_exists BOOLEAN;
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  v_poison_target_role TEXT;
  v_bodyguard_target_id UUID;
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_killed_by_poison BOOLEAN;
  v_victims JSONB;
  v_soulmate_of_wolf UUID;
  v_soulmate_of_poison UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_alpha_infected_id UUID;
  v_alpha_infected_name TEXT;
  v_is_infected BOOLEAN;
  v_infected_player_role TEXT;
  v_target_has_alpha_infect BOOLEAN;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT COALESCE(wolves_frenzy, false) INTO v_frenzy
  FROM rooms WHERE id = p_room_id;

  -- PASSO 1: Padre
  SELECT target_id INTO v_priest_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless'
  LIMIT 1;

  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- Collect distinct wolf targets
  SELECT ARRAY_AGG(DISTINCT target_id) INTO v_wolf_target_ids
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  v_wolf_target_id := v_wolf_target_ids[1];
  IF v_frenzy AND array_length(v_wolf_target_ids, 1) >= 2 THEN
    v_wolf_target2_id := v_wolf_target_ids[2];
  END IF;

  -- PASSO 2: Lobisomens (target 1)
  IF v_wolf_target_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn
        AND action_type = 'alpha_infect' AND target_id = v_wolf_target_id
    ) INTO v_target_has_alpha_infect;

    IF v_target_has_alpha_infect THEN
      SELECT role INTO v_infected_player_role
      FROM players WHERE id = v_wolf_target_id;

      UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
      SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target_id;
      v_alpha_infected_id := v_wolf_target_id;

      UPDATE players SET has_used_power = true
      WHERE room_id = p_room_id AND role = 'alpha_wolf';
    ELSE
      SELECT EXISTS (
        SELECT 1 FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
      ) INTO v_witch_save_exists;

      SELECT target_id INTO v_bodyguard_target_id
      FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

      v_is_blessed := false;
      SELECT COALESCE(is_blessed, false) INTO v_is_blessed
      FROM players WHERE id = v_wolf_target_id;

      v_killed_by_wolves := NOT v_witch_save_exists
        AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
        AND NOT v_is_blessed;

      IF v_is_blessed THEN
        UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
      END IF;

      IF v_killed_by_wolves THEN
        UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
        SELECT name, role INTO v_wolf_target_name, v_wolf_target_role FROM players WHERE id = v_wolf_target_id;
      END IF;
    END IF;
  END IF;

  -- PASSO 2b: Lobisomens (target 2 — frenzy)
  IF v_frenzy AND v_wolf_target2_id IS NOT NULL THEN
    v_killed_by_wolves := false;

    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn
        AND action_type = 'alpha_infect' AND target_id = v_wolf_target2_id
    ) INTO v_target_has_alpha_infect;

    IF v_target_has_alpha_infect AND v_alpha_infected_id IS NULL THEN
      SELECT role INTO v_infected_player_role
      FROM players WHERE id = v_wolf_target2_id;
      UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target2_id;
      SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target2_id;
      v_alpha_infected_id := v_wolf_target2_id;

      UPDATE players SET has_used_power = true
      WHERE room_id = p_room_id AND role = 'alpha_wolf';
    ELSE
      SELECT target_id INTO v_bodyguard_target_id
      FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

      v_is_blessed := false;
      SELECT COALESCE(is_blessed, false) INTO v_is_blessed
      FROM players WHERE id = v_wolf_target2_id;

      v_killed_by_wolves := (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target2_id)
        AND NOT v_is_blessed;

      IF v_is_blessed THEN
        UPDATE players SET is_blessed = false WHERE id = v_wolf_target2_id;
      END IF;

      IF v_killed_by_wolves THEN
        UPDATE players SET is_alive = false WHERE id = v_wolf_target2_id;
        SELECT name, role INTO v_wolf_target2_name, v_wolf_target2_role FROM players WHERE id = v_wolf_target2_id;
      END IF;
    END IF;
  END IF;

  -- PASSO 3: Bruxa — veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  v_killed_by_poison := false;
  IF v_poison_target_id IS NOT NULL THEN
    v_is_blessed := false;
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_poison_target_id;

    SELECT target_id INTO v_bodyguard_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

    v_killed_by_poison := (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_poison_target_id)
      AND NOT v_is_blessed;

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    END IF;

    IF v_killed_by_poison THEN
      UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
      SELECT name, role INTO v_poison_target_name, v_poison_target_role FROM players WHERE id = v_poison_target_id;
    END IF;
  END IF;

  -- PASSO 4: Soulmate deaths
  v_victims := '[]'::JSONB;

  IF v_wolf_target_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn
      AND action_type = 'alpha_infect' AND target_id = v_wolf_target_id
  ) THEN
    SELECT soulmate_id INTO v_soulmate_of_wolf FROM players WHERE id = v_wolf_target_id;
    IF v_soulmate_of_wolf IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_wolf) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_wolf;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
      v_soulmate_name := NULL;
    END IF;
  END IF;

  IF v_frenzy AND v_wolf_target2_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn
      AND action_type = 'alpha_infect' AND target_id = v_wolf_target2_id
  ) THEN
    SELECT soulmate_id INTO v_soulmate_of_wolf FROM players WHERE id = v_wolf_target2_id;
    IF v_soulmate_of_wolf IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_wolf) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_wolf;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
      v_soulmate_name := NULL;
    END IF;
  END IF;

  IF v_killed_by_poison AND v_poison_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_poison FROM players WHERE id = v_poison_target_id;
    IF v_soulmate_of_poison IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_poison) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_poison;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
    END IF;
  END IF;

  IF v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem', 'role', v_wolf_target_role);
  END IF;

  IF v_frenzy AND v_wolf_target2_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target2_name, 'cause', 'lobisomem', 'role', v_wolf_target2_role);
  END IF;

  IF v_killed_by_poison AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno', 'role', v_poison_target_role);
  END IF;

  -- Build last_event — do NOT touch wolves_frenzy on game_state (column does not exist)
  IF v_alpha_infected_id IS NOT NULL THEN
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'announcement',
        turn_index = v_turn,
        phase_started_at = now(),
        wolves_resolved = false,
        last_event = jsonb_build_object(
          'type', 'night_result',
          'victims', v_victims,
          'infected_id', v_alpha_infected_id,
          'infected_name', v_alpha_infected_name
        ),
        last_vote_result = NULL
    WHERE room_id = p_room_id;
  ELSE
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'announcement',
        turn_index = v_turn,
        phase_started_at = now(),
        wolves_resolved = false,
        last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims),
        last_vote_result = NULL
    WHERE room_id = p_room_id;
  END IF;

  -- Clear frenzy on rooms (not on game_state)
  UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;
