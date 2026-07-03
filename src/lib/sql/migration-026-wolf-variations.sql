-- ═══════════════════════════════════════════════════════════════════════
-- migration-026-wolf-variations.sql
-- APLICAR VIA SUPABASE SQL EDITOR OU `supabase db query --linked`
--
-- 1. wolves_frenzy BOOLEAN em rooms  +  trigger trg_wolf_cub_death
-- 2. CHECK constraints atualizadas (wolf_cub, lone_wolf, alpha_wolf, alpha_infect)
-- 3. get_werewolf_teammates  — incluir wolf_cub, alpha_wolf, lone_wolf
-- 4. execute_night_action    — aceitar novas roles + alpha_infect
-- 5. resolve_night_wolves    — frenesi (2 alvos) ou normal (1 alvo)
-- 6. resolve_night           — frenesi + infeccao alfa
-- 7. check_game_over         — lone_wolf_win prioridade 0
-- 8. trg_check_game_over     — mesmo
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 1. wolves_frenzy column + trigger
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS wolves_frenzy BOOLEAN NOT NULL DEFAULT false;

DROP TRIGGER IF EXISTS trg_wolf_cub_death ON players;
DROP FUNCTION IF EXISTS public.trg_wolf_cub_death() CASCADE;

CREATE OR REPLACE FUNCTION public.trg_wolf_cub_death()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_alive = false AND OLD.role = 'wolf_cub' THEN
    UPDATE rooms SET wolves_frenzy = true WHERE id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_wolf_cub_death
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
WHEN (NEW.is_alive = false AND OLD.role = 'wolf_cub')
EXECUTE FUNCTION public.trg_wolf_cub_death();


-- ═══════════════════════════════════════════════════════════════════════
-- 2. CHECK constraints
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE players DROP CONSTRAINT IF EXISTS players_role_check;
ALTER TABLE players ADD CONSTRAINT players_role_check
  CHECK (role = ANY (ARRAY[
    'unassigned', 'villager', 'werewolf', 'seer', 'witch',
    'moderator', 'mayor', 'prince', 'tanner', 'lycan',
    'priest', 'bodyguard', 'aura_seer', 'cupid', 'cult_leader',
    'wolf_cub', 'lone_wolf', 'alpha_wolf'
  ]));

ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN (
    'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
    'priest_bless', 'bodyguard_protect', 'aura_investigate',
    'cult_convert', 'cupid_match', 'alpha_infect'
  ));

ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_status_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_status_check
  CHECK (status IN ('waiting', 'playing', 'finished',
    'finished_villagers_win', 'finished_wolves_win', 'finished_tanner_win',
    'finished_soulmates_win', 'finished_cult_win', 'finished_lone_wolf_win'));


-- ═══════════════════════════════════════════════════════════════════════
-- 3. get_werewolf_teammates — incluir wolf_cub, alpha_wolf, lone_wolf
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_werewolf_teammates(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.get_werewolf_teammates(p_room_id UUID)
RETURNS TABLE(id UUID, name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT role FROM players WHERE user_id = auth.uid() AND room_id = p_room_id)
     NOT IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf') THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT p.id, p.name
  FROM players p
  WHERE p.room_id = p_room_id
    AND p.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')
    AND p.user_id != auth.uid();
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- 4. execute_night_action — aceitar novas roles + alpha_infect
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.execute_night_action(UUID, TEXT, UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.execute_night_action(
  p_room_id uuid,
  p_action_type text,
  p_target_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
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

  IF (p_action_type = 'werewolf_kill' AND v_role NOT IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')) OR
     (p_action_type = 'seer_investigate' AND v_role != 'seer') OR
     (p_action_type IN ('witch_save', 'witch_poison') AND v_role != 'witch') OR
     (p_action_type = 'priest_bless' AND v_role != 'priest') OR
     (p_action_type = 'bodyguard_protect' AND v_role != 'bodyguard') OR
     (p_action_type = 'aura_investigate' AND v_role != 'aura_seer') OR
     (p_action_type = 'cult_convert' AND v_role != 'cult_leader') OR
     (p_action_type = 'alpha_infect' AND v_role != 'alpha_wolf')
  THEN
    RAISE EXCEPTION 'Acao invalida para o seu papel';
  END IF;

  IF p_action_type = 'alpha_infect' AND v_used_power THEN
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
  ELSIF p_action_type = 'priest_bless' THEN
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
    SELECT role INTO v_target_role FROM players WHERE id = p_target_id;
    v_result := (v_target_role NOT IN ('villager', 'werewolf'));
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
  END IF;

  IF p_action_type = 'seer_investigate' THEN
    SELECT role IN ('werewolf', 'lycan') INTO v_result
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
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- 5. resolve_night_wolves — frenesi (2 alvos) ou normal (1 alvo)
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.resolve_night_wolves(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.resolve_night_wolves(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  v_distinct_targets INT;
  v_victim_id UUID;
  v_victim_name TEXT;
  v_victim2_id UUID;
  v_victim2_name TEXT;
  v_frenzy BOOLEAN;
  v_expected_targets INT;
  v_targets UUID[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver o ataque';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  SELECT COALESCE(wolves_frenzy, false) INTO v_frenzy
  FROM rooms WHERE id = p_room_id;

  v_expected_targets := CASE WHEN v_frenzy THEN 2 ELSE 1 END;

  SELECT COUNT(DISTINCT target_id) INTO v_distinct_targets
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  IF v_distinct_targets != v_expected_targets THEN
    DELETE FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

    RETURN jsonb_build_object(
      'consensus', false,
      'message', CASE WHEN v_frenzy
        THEN 'Os lobos em frenesi precisam escolher EXATAMENTE 2 vitimas — votos limpos, escolham novamente.'
        ELSE 'Os lobos precisam chegar em um consenso — votos limpos, escolham novamente.'
      END
    );
  END IF;

  -- Collect distinct targets
  SELECT ARRAY_AGG(DISTINCT target_id) INTO v_targets
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  v_victim_id := v_targets[1];
  SELECT name INTO v_victim_name FROM players WHERE id = v_victim_id;

  IF v_frenzy AND array_length(v_targets, 1) >= 2 THEN
    v_victim2_id := v_targets[2];
    SELECT name INTO v_victim2_name FROM players WHERE id = v_victim2_id;
  END IF;

  UPDATE game_state
  SET wolves_resolved = true,
      last_event = CASE WHEN v_frenzy THEN
        jsonb_build_object(
          'type', 'wolf_target',
          'frenzy', true,
          'victim_id', v_victim_id,
          'victim_name', v_victim_name,
          'victims', jsonb_build_array(
            jsonb_build_object('victim_id', v_victim_id, 'victim_name', v_victim_name),
            jsonb_build_object('victim_id', v_victim2_id, 'victim_name', v_victim2_name)
          )
        )
      ELSE
        jsonb_build_object(
          'type', 'wolf_target',
          'victim_id', v_victim_id,
          'victim_name', v_victim_name
        )
      END
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'consensus', true,
    'victim_id', v_victim_id,
    'victim_name', v_victim_name,
    'victim2_id', v_victim2_id,
    'victim2_name', v_victim2_name
  );
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- 6. resolve_night — frenesi + infeccao alfa
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.resolve_night(UUID) CASCADE;

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
    -- Check alpha infection for this target
    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn
        AND action_type = 'alpha_infect' AND target_id = v_wolf_target_id
    ) INTO v_target_has_alpha_infect;

    IF v_target_has_alpha_infect THEN
      SELECT role INTO v_infected_player_role
      FROM players WHERE id = v_wolf_target_id;

      -- Infection bypasses all shields — change role, don't kill
      UPDATE players SET role = 'werewolf' WHERE id = v_wolf_target_id;
      SELECT name INTO v_alpha_infected_name FROM players WHERE id = v_wolf_target_id;
      v_alpha_infected_id := v_wolf_target_id;

      -- Mark alpha's power as used
      UPDATE players SET has_used_power = true
      WHERE room_id = p_room_id AND role = 'alpha_wolf';
    ELSE
      -- Normal wolf kill resolution
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
    -- Reset variables for second target
    v_killed_by_wolves := false;

    -- Check alpha infection for this target
    SELECT EXISTS (
      SELECT 1 FROM night_actions
      WHERE room_id = p_room_id AND turn_index = v_turn
        AND action_type = 'alpha_infect' AND target_id = v_wolf_target2_id
    ) INTO v_target_has_alpha_infect;

    IF v_target_has_alpha_infect AND v_alpha_infected_id IS NULL THEN
      -- Infect second target
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

  -- Soulmate of wolf target 1
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

  -- Soulmate of wolf target 2
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

  -- Soulmate of poison target
  IF v_killed_by_poison AND v_poison_target_id IS NOT NULL THEN
    SELECT soulmate_id INTO v_soulmate_of_poison FROM players WHERE id = v_poison_target_id;
    IF v_soulmate_of_poison IS NOT NULL AND (SELECT is_alive FROM players WHERE id = v_soulmate_of_poison) = false THEN
      SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_of_poison;
      v_victims := v_victims || jsonb_build_object('name', v_soulmate_name, 'cause', 'soulmate', 'role', v_soulmate_role);
    END IF;
  END IF;

  -- Wolf target 1 killed
  IF v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem', 'role', v_wolf_target_role);
  END IF;

  -- Wolf target 2 killed (frenzy)
  IF v_frenzy AND v_wolf_target2_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target2_name, 'cause', 'lobisomem', 'role', v_wolf_target2_role);
  END IF;

  IF v_killed_by_poison AND v_poison_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_poison_target_name, 'cause', 'veneno', 'role', v_poison_target_role);
  END IF;

  -- Build last_event with infection info if applicable
  IF v_alpha_infected_id IS NOT NULL THEN
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'announcement',
        turn_index = v_turn,
        phase_started_at = now(),
        wolves_resolved = false,
        wolves_frenzy = false,
        last_event = jsonb_build_object(
          'type', 'night_result',
          'victims', v_victims,
          'infected_id', v_alpha_infected_id,
          'infected_name', v_alpha_infected_name
        ),
        last_vote_result = NULL
    WHERE room_id = p_room_id;
  ELSE
    -- Clear frenzy at end of night (if it was active)
    UPDATE game_state
    SET current_phase = 'day',
        day_step = 'announcement',
        turn_index = v_turn,
        phase_started_at = now(),
        wolves_resolved = false,
        wolves_frenzy = false,
        last_event = jsonb_build_object('type', 'night_result', 'victims', v_victims),
        last_vote_result = NULL
    WHERE room_id = p_room_id;

    UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;
  END IF;

  RETURN jsonb_build_object('success', true, 'victims', v_victims);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- 7. check_game_over — lone_wolf_win prioridade 0
-- ═══════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.check_game_over(UUID) CASCADE;

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

  -- Standard wolf/village check (lone_wolf counted as non_wolf)
  SELECT
    COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
    COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
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


-- ═══════════════════════════════════════════════════════════════════════
-- 8. trg_check_game_over — mesmo com lone_wolf_win
-- ═══════════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_check_game_over ON players;

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

  -- Standard wolf/village check
  SELECT COUNT(*) FILTER (WHERE is_alive = true AND role = 'werewolf'),
         COUNT(*) FILTER (WHERE is_alive = true AND role NOT IN ('werewolf', 'moderator'))
  INTO v_wolves, v_non_wolves FROM players WHERE room_id = NEW.room_id;

  IF v_wolves = 0 THEN
    UPDATE game_state SET winner = 'villagers_win' WHERE room_id = NEW.room_id;
  ELSIF v_wolves >= v_non_wolves THEN
    UPDATE game_state SET winner = 'wolves_win' WHERE room_id = NEW.room_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_check_game_over
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_game_over();
