-- Migration: day_step = 'announcement' on night resolution
-- Sets day_step to 'announcement' so the DayAnnouncement component
-- shows before the host clicks "Iniciar Debate"

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

  SELECT target_id INTO v_poison_target_id
  FROM night_actions
  WHERE room_id = p_room_id AND turn_index = v_turn AND action_type = 'witch_poison';

  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists THEN
    UPDATE players SET is_alive = false WHERE id = v_wolf_target_id;
    SELECT name INTO v_wolf_target_name FROM players WHERE id = v_wolf_target_id;
  END IF;

  IF v_poison_target_id IS NOT NULL AND v_poison_target_id != v_wolf_target_id THEN
    UPDATE players SET is_alive = false WHERE id = v_poison_target_id;
    SELECT name INTO v_poison_target_name FROM players WHERE id = v_poison_target_id;
  END IF;

  v_victims := '[]'::JSONB;
  IF v_wolf_target_id IS NOT NULL AND NOT v_witch_save_exists AND v_wolf_target_name IS NOT NULL THEN
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
