-- Fix: resolve_night — ordem sequencial Padre → Lobos → Bruxa (veneno)
-- PASSO 1: Padre (is_blessed = TRUE)
-- PASSO 2: Lobisomens (verifica is_blessed + bodyguard)
-- PASSO 3: Bruxa veneno (verifica is_blessed do estado atual + bodyguard)

DROP FUNCTION IF EXISTS public.resolve_night(UUID) CASCADE;

CREATE OR REPLACE FUNCTION public.resolve_night(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_turn INT;
  -- Priest (Passo 1)
  v_priest_target_id UUID;
  -- Wolves (Passo 2)
  v_distinct_wolf_targets INT;
  v_wolf_target_id UUID;
  v_wolf_target_name TEXT;
  -- Witch (Passo 2)
  v_witch_save_exists BOOLEAN;
  -- Witch poison (Passo 3)
  v_poison_target_id UUID;
  v_poison_target_name TEXT;
  -- Bodyguard (aplicado a ambos passos 2 e 3)
  v_bodyguard_target_id UUID;
  -- Blessed state (lida em passos 2 e 3)
  v_is_blessed BOOLEAN;
  v_killed_by_wolves BOOLEAN;
  v_killed_by_poison BOOLEAN;
  v_victims JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a noite';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 1: Padre — abençoa o alvo (is_blessed = TRUE)
  -- ════════════════════════════════════════════════════════════════
  SELECT target_id INTO v_priest_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'priest_bless'
  LIMIT 1;

  IF v_priest_target_id IS NOT NULL THEN
    UPDATE players SET is_blessed = true WHERE id = v_priest_target_id;
  END IF;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 2: Lobisomens — ataque dos lobos
  -- ════════════════════════════════════════════════════════════════
  -- Consensus check: count distinct targets chosen by wolves
  SELECT COUNT(DISTINCT target_id)
  INTO v_distinct_wolf_targets
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill';

  -- Only apply wolf kill if ALL wolves agreed on the SAME target (consensus)
  IF v_distinct_wolf_targets = 1 THEN
    SELECT target_id INTO v_wolf_target_id
    FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'werewolf_kill'
    LIMIT 1;
  ELSE
    v_wolf_target_id := NULL;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM night_actions
    WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_save'
  ) INTO v_witch_save_exists;

  SELECT target_id INTO v_bodyguard_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'bodyguard_protect';

  -- Check blessing for wolf target
  v_is_blessed := false;
  IF v_wolf_target_id IS NOT NULL THEN
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_wolf_target_id;
  END IF;

  v_killed_by_wolves := v_wolf_target_id IS NOT NULL
    AND NOT v_witch_save_exists
    AND (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_wolf_target_id)
    AND NOT v_is_blessed;

  -- Consume blessing if it saved the wolf target
  IF v_wolf_target_id IS NOT NULL AND v_is_blessed THEN
    UPDATE players SET is_blessed = false WHERE id = v_wolf_target_id;
  END IF;

  IF v_killed_by_wolves THEN
    UPDATE players SET is_alive = false, last_event = 'lobisomem' WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  -- ════════════════════════════════════════════════════════════════
  -- PASSO 3: Bruxa — veneno (checa is_blessed do estado PÓS passos 1 e 2)
  -- ════════════════════════════════════════════════════════════════
  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  v_killed_by_poison := false;
  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    -- Re-read is_blessed (may have been set in passo 1 or consumed in passo 2)
    SELECT COALESCE(is_blessed, false) INTO v_is_blessed
    FROM players WHERE id = v_poison_target_id;

    v_killed_by_poison := (v_bodyguard_target_id IS NULL OR v_bodyguard_target_id != v_poison_target_id)
      AND NOT v_is_blessed;

    -- Consume blessing if it saved the poison target
    IF v_is_blessed THEN
      UPDATE players SET is_blessed = false WHERE id = v_poison_target_id;
    END IF;

    IF v_killed_by_poison THEN
      UPDATE players SET is_alive = false, last_event = 'veneno' WHERE id = v_poison_target_id;
      SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
    END IF;
  END IF;

  -- Build victims JSONB
  v_victims := '[]'::JSONB;
  IF v_killed_by_wolves AND v_wolf_target_name IS NOT NULL THEN
    v_victims := v_victims || jsonb_build_object('name', v_wolf_target_name, 'cause', 'lobisomem');
  END IF;
  IF v_killed_by_poison AND v_poison_target_name IS NOT NULL THEN
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
