-- Fix: wolves_frenzy flag leaks when diseased_skip takes precedence
--
-- Bug: resolve_night PASSO 0 does early RETURN when diseased_skip_wolves=true,
-- but does NOT clear rooms.wolves_frenzy. If Wolf Cub died before Diseased,
-- frenzy persists to the next night, forcing wolves to pick 2 targets incorrectly.
--
-- Fix: clear wolves_frenzy inside the diseased_skip block, before RETURN.
-- Only change vs DB version: added 1 line in PASSO 0 after diseased_skip_wolves = false.

CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_victims JSONB := '[]'::JSONB;
  v_soulmate_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_alpha_infected_id UUID;
  v_alpha_infected_name TEXT;
  v_target_has_alpha_infect BOOLEAN;
  v_hunter_killed BOOLEAN := false;
  v_hunter_id UUID;
  v_squire_id UUID;
  v_prince_died BOOLEAN := false;
  v_game_over JSONB;
  v_diseased_skip BOOLEAN := false;
  v_cursed_converted BOOLEAN := false;
  v_cursed_converted_name TEXT;
  v_doppelganger_id UUID;
  v_doppelganger_new_role TEXT;
  v_doppelganger_new_role_name TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;
  SELECT COALESCE(wolves_frenzy, false) INTO v_frenzy FROM rooms WHERE id = p_room_id;

  -- PASSO 0: Checar se lobos devem pular esta noite (Diseased)
  SELECT diseased_skip_wolves INTO v_diseased_skip FROM game_state WHERE room_id = p_room_id;
  IF v_diseased_skip THEN
    UPDATE game_state SET diseased_skip_wolves = false WHERE room_id = p_room_id;

    -- FIX: clear wolves_frenzy when diseased skip takes precedence
    UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;

    -- Lobos pulam: sem vítimas, avança para dia
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'announcement',
        turn_index = v_turn,
        phase_started_at = now(),
        wolves_resolved = false,
        last_event = jsonb_build_object('type', 'night_result', 'victims', '[]'::JSONB, 'diseased_skip', true),
        last_vote_result = NULL,
        hunter_pending = false,
        hunter_id = NULL
    WHERE room_id = p_room_id;

    v_game_over := check_game_over(p_room_id);
    RETURN jsonb_build_object('success', true, 'victims', '[]'::JSONB, 'diseased_skip', true, 'game_over', v_game_over);
  END IF;

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
      UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
      SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target_id;
      v_alpha_infected_id := v_wolf_target_id;
      UPDATE players SET has_used_power = true
      WHERE room_id = p_room_id AND role = 'alpha_wolf' AND has_used_power = false;
    ELSE
      -- CHECAR CURSED ANTES de processar proteções
      SELECT role INTO v_wolf_target_role FROM players WHERE id = v_wolf_target_id;
      IF v_wolf_target_role = 'cursed' THEN
        -- Cursed não morre: vira lobisomem na noite seguinte
        UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
        SELECT name INTO v_cursed_converted_name FROM players WHERE id = v_wolf_target_id;
        v_cursed_converted := true;
      ELSE
        SELECT EXISTS (
          SELECT 1 FROM night_actions
          WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
        ) INTO v_witch_save_exists;

        SELECT target_id INTO v_bodyguard_target_id
        FROM night_actions
        WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

        v_is_blessed := false;
        SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_wolf_target_id;

        v_killed_by_wolves := NOT v_witch_save_exists
          AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
          AND NOT v_is_blessed;

        IF v_is_blessed THEN
          UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
        END IF;

        IF v_killed_by_wolves THEN
          UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
          SELECT name, role INTO v_wolf_target_name, v_wolf_target_role FROM players WHERE id = v_wolf_target_id;

          IF v_wolf_target_role = 'hunter' THEN
            v_hunter_killed := true;
            v_hunter_id := v_wolf_target_id;
          END IF;

          IF v_wolf_target_role = 'prince' THEN
            v_prince_died := true;
          END IF;

          -- DISEASED: setar skip se for Doente
          IF v_wolf_target_role = 'diseased' THEN
            UPDATE game_state SET diseased_skip_wolves = true WHERE room_id = p_room_id;
          END IF;

          v_victims := v_victims || jsonb_build_object(
            'name', v_wolf_target_name,
            'cause', 'lobisomem',
            'role', v_wolf_target_role
          );
        END IF;
      END IF;
    END IF;
  END IF;

  -- PASSO 2b: Lobisomens (target 2 — frenzy)
  IF v_wolf_target2_id IS NOT NULL AND v_frenzy THEN
    v_is_blessed := false;
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_wolf_target2_id;

    SELECT target_id INTO v_bodyguard_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
    ) INTO v_witch_save_exists;

    v_killed_by_wolves := NOT v_witch_save_exists
      AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target2_id)
      AND NOT v_is_blessed;

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_wolf_target2_id;
    END IF;

    IF v_killed_by_wolves THEN
      UPDATE players SET is_alive = false WHERE id = v_wolf_target2_id;
      SELECT name, role INTO v_wolf_target2_name, v_wolf_target2_role FROM players WHERE id = v_wolf_target2_id;

      IF v_wolf_target2_role = 'hunter' THEN
        v_hunter_killed := true;
        v_hunter_id := v_wolf_target2_id;
      END IF;

      IF v_wolf_target2_role = 'prince' THEN
        v_prince_died := true;
      END IF;

      IF v_wolf_target2_role = 'diseased' THEN
        UPDATE game_state SET diseased_skip_wolves = true WHERE room_id = p_room_id;
      END IF;

      v_victims := v_victims || jsonb_build_object(
        'name', v_wolf_target2_name,
        'cause', 'lobisomem',
        'role', v_wolf_target2_role
      );
    END IF;
  END IF;

  -- PASSO 3: Bruxa — veneno
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison'
  LIMIT 1;

  IF v_poison_target_id IS NOT NULL THEN
    v_is_blessed := false;
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed FROM players WHERE id = v_poison_target_id;

    SELECT target_id INTO v_bodyguard_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

    v_killed_by_poison := NOT v_is_blessed
      AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_poison_target_id);

    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    END IF;

    IF v_killed_by_poison THEN
      UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
      SELECT name, role INTO v_poison_target_name, v_poison_target_role FROM players WHERE id = v_poison_target_id;

      IF v_poison_target_role = 'hunter' THEN
        v_hunter_killed := true;
        v_hunter_id := v_poison_target_id;
      END IF;

      IF v_poison_target_role = 'prince' THEN
        v_prince_died := true;
      END IF;

      -- CURSED por veneno: NÃO converte (só lobos convertem)
      v_victims := v_victims || jsonb_build_object(
        'name', v_poison_target_name,
        'cause', 'veneno',
        'role', v_poison_target_role
      );
    END IF;
  END IF;

  -- PASSO 4: Soulmate deaths
  FOR i IN 0..jsonb_array_length(v_victims) - 1 LOOP
    DECLARE
      v_victim_id UUID;
      v_victim_name TEXT;
      v_victim_role TEXT;
    BEGIN
      SELECT id INTO v_victim_id
      FROM players WHERE room_id = p_room_id AND name = (v_victims->i->>'name');
      IF v_victim_id IS NOT NULL THEN
        SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_victim_id;
        IF v_soulmate_id IS NOT NULL THEN
          IF (SELECT is_alive FROM players WHERE id = v_soulmate_id) THEN
            UPDATE players SET is_alive = false WHERE id = v_soulmate_id;
            SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;

            IF v_soulmate_role = 'hunter' THEN
              v_hunter_killed := true;
              v_hunter_id := v_soulmate_id;
            END IF;

            IF v_soulmate_role = 'prince' THEN
              v_prince_died := true;
            END IF;

            v_victims := v_victims || jsonb_build_object(
              'name', v_soulmate_name,
              'cause', 'soulmate',
              'role', v_soulmate_role
            );
          END IF;
        END IF;
      END IF;
    END;
  END LOOP;

  -- B21 FIX: Agora sim — após todas as mortes, promover Squire se Prince morreu
  IF v_prince_died THEN
    SELECT id INTO v_squire_id FROM players
    WHERE room_id = p_room_id AND is_alive = true AND role = 'squire' LIMIT 1;
    IF v_squire_id IS NOT NULL THEN
      UPDATE players SET role = 'prince' WHERE id = v_squire_id;
    END IF;
  END IF;

  -- DOPPELGÄNGER: quando alvo morre, copia o papel
  FOR v_doppelganger_id IN
    SELECT p.id FROM players p
    WHERE p.room_id = p_room_id AND p.is_alive = true AND p.role = 'doppelganger'
      AND p.doppelganger_target_id IS NOT NULL
  LOOP
    DECLARE
      v_dg_target_id UUID;
      v_dg_target_alive BOOLEAN;
    BEGIN
      SELECT doppelganger_target_id INTO v_dg_target_id FROM players WHERE id = v_doppelganger_id;
      IF v_dg_target_id IS NOT NULL THEN
        SELECT is_alive INTO v_dg_target_alive FROM players WHERE id = v_dg_target_id;
        IF v_dg_target_alive = false THEN
          -- Alvo morreu: copiar papel
          SELECT role INTO v_doppelganger_new_role FROM players WHERE id = v_dg_target_id;
          UPDATE players SET role = v_doppelganger_new_role WHERE id = v_doppelganger_id;
          SELECT name INTO v_doppelganger_new_role_name FROM players WHERE id = v_dg_target_id;
        END IF;
      END IF;
    END;
  END LOOP;

  -- Atualizar game_state
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
        'cursed_converted', v_cursed_converted,
        'cursed_converted_name', v_cursed_converted_name
      ),
      last_vote_result = NULL,
      hunter_pending = CASE WHEN v_hunter_killed THEN true ELSE false END,
      hunter_id = CASE WHEN v_hunter_killed THEN v_hunter_id ELSE NULL END
  WHERE room_id = p_room_id;

  -- Limpar frenesi
  UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;

  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'victims', v_victims,
    'hunter_pending', v_hunter_killed,
    'cursed_converted', v_cursed_converted,
    'game_over', v_game_over
  );
END;
$function$;
