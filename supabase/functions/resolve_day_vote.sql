CREATE OR REPLACE FUNCTION public.resolve_day_vote(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_turn INT;
  v_target_id UUID;
  v_vote_count NUMERIC;
  v_tie_count INT;
  v_threshold NUMERIC;
  v_alive INT;
  v_victim_name TEXT;
  v_target_role TEXT;
  v_game_over JSONB;
  v_soulmate_id UUID;
  v_soulmate_name TEXT;
  v_soulmate_role TEXT;
  v_squire_id UUID;
  v_hunter_pending BOOLEAN := false;
  v_hunter_id UUID;
  v_prince_died BOOLEAN := false;
  v_cursed_converted BOOLEAN := false;
  v_cursed_converted_name TEXT;
  v_doppelganger_id UUID;
  v_doppelganger_new_role TEXT;
  v_doppelganger_new_role_name TEXT;
  v_prince_revealed BOOLEAN := false;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resolver a votação';
  END IF;

  SELECT turn_index INTO v_turn FROM game_state WHERE room_id = p_room_id;

  -- Contar votos PONDERADOS: Mayor conta x2
  SELECT target_id, SUM(CASE WHEN p2.role = 'mayor' THEN 2 ELSE 1 END) INTO v_target_id, v_vote_count
  FROM votes v
  JOIN players p2 ON p2.id = v.voter_id
  WHERE v.room_id = p_room_id AND v.turn_index = v_turn
  GROUP BY target_id
  ORDER BY SUM(CASE WHEN p2.role = 'mayor' THEN 2 ELSE 1 END) DESC
  LIMIT 1;

  -- Threshold: vivos (excluindo moderador) - acusado
  SELECT COUNT(*) INTO v_alive
  FROM players WHERE room_id = p_room_id AND is_alive = true AND role != 'moderator';

  v_threshold := floor(v_alive / 2) + 1;

  -- Verificar empate (contar quantos targets têm o mesmo score)
  SELECT COUNT(*) INTO v_tie_count FROM (
    SELECT target_id, SUM(CASE WHEN p2.role = 'mayor' THEN 2 ELSE 1 END) AS cnt
    FROM votes v
    JOIN players p2 ON p2.id = v.voter_id
    WHERE v.room_id = p_room_id AND v.turn_index = v_turn
    GROUP BY target_id
    HAVING SUM(CASE WHEN p2.role = 'mayor' THEN 2 ELSE 1 END) = v_vote_count
  ) AS ties;

  IF v_vote_count < v_threshold OR v_tie_count > 1 THEN
    UPDATE game_state
    SET current_phase = 'night',
        turn_index = v_turn + 1,
        phase_started_at = now(),
        last_event = jsonb_build_object('type', 'vote_result', 'event_type', 'vote_tie'),
        last_vote_result = jsonb_build_object(
          'type', 'vote_tie',
          'message', 'A vila não chegou a um consenso. Ninguém foi linchado.'
        )
    WHERE room_id = p_room_id;
  ELSE
    SELECT name, role INTO v_victim_name, v_target_role FROM players WHERE id = v_target_id;

    -- PRINCE CHECK — one-shot
    SELECT prince_revealed INTO v_prince_revealed FROM game_state WHERE room_id = p_room_id;

    IF v_target_role = 'prince' AND NOT v_prince_revealed THEN
      UPDATE game_state
      SET current_phase = 'day',
          day_step = 'prince_reveal',
          turn_index = v_turn,
          phase_started_at = now(),
          prince_revealed = true,
          last_event = jsonb_build_object(
            'type', 'prince_reveal', 'victim_id', v_target_id,
            'victim_name', v_victim_name, 'victim_role', v_target_role
          ),
          last_vote_result = jsonb_build_object(
            'type', 'prince_reveal', 'victim_name', v_victim_name, 'victim_role', v_target_role
          )
      WHERE room_id = p_room_id;
      RETURN jsonb_build_object('success', true, 'prince_reveal', true, 'victim_name', v_victim_name);
    END IF;

    -- CURSED: linchamento converte mas NÃO morre
    IF v_target_role = 'cursed' THEN
      UPDATE players SET role = 'werewolf' WHERE id = v_target_id;
      v_target_role := 'werewolf';
      v_cursed_converted := true;
      v_cursed_converted_name := v_victim_name;
      -- Cursed SOBREVIVE — avançar para noite sem vítima
      UPDATE game_state
      SET current_phase = 'night',
          turn_index = v_turn + 1,
          phase_started_at = now(),
          current_accused_id = NULL,
          last_event = jsonb_build_object(
            'type', 'vote_result', 'event_type', 'lynch',
            'victim_id', v_target_id, 'victim_name', v_victim_name,
            'victim_role', v_target_role,
            'cursed_converted', v_cursed_converted,
            'cursed_converted_name', v_cursed_converted_name
          ),
          last_vote_result = jsonb_build_object(
            'type', 'lynch', 'victim_name', v_victim_name, 'victim_role', v_target_role,
            'cursed_converted', v_cursed_converted,
            'cursed_converted_name', v_cursed_converted_name
          )
      WHERE room_id = p_room_id;
      v_game_over := check_game_over(p_room_id);
      RETURN jsonb_build_object('success', true, 'cursed_converted', true, 'game_over', v_game_over);
    END IF;

    -- Matar o acusado
    UPDATE players SET is_alive = false WHERE id = v_target_id;

    -- Hunter check
    IF v_target_role = 'hunter' THEN
      v_hunter_pending := true;
      v_hunter_id := v_target_id;
    END IF;

    -- Check soulmate
    SELECT soulmate_id INTO v_soulmate_id FROM players WHERE id = v_target_id;
    IF v_soulmate_id IS NOT NULL THEN
      IF (SELECT is_alive FROM players WHERE id = v_soulmate_id) THEN
        UPDATE players SET is_alive = false WHERE id = v_soulmate_id;
        SELECT name, role INTO v_soulmate_name, v_soulmate_role FROM players WHERE id = v_soulmate_id;

        IF v_soulmate_role = 'hunter' THEN
          v_hunter_pending := true;
          v_hunter_id := v_soulmate_id;
        END IF;

        IF v_soulmate_role = 'prince' THEN
          v_prince_died := true;
        END IF;
      END IF;
    END IF;

    -- Squire promotion — SOMENTE quando Prince MORRE
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
            SELECT role INTO v_doppelganger_new_role FROM players WHERE id = v_dg_target_id;
            UPDATE players SET role = v_doppelganger_new_role WHERE id = v_doppelganger_id;
            SELECT name INTO v_doppelganger_new_role_name FROM players WHERE id = v_dg_target_id;
          END IF;
        END IF;
      END;
    END LOOP;

    UPDATE game_state
    SET current_phase = 'day',
        day_step = CASE WHEN v_hunter_pending THEN 'hunter_reveal' ELSE 'lynch_reveal' END,
        turn_index = v_turn,
        phase_started_at = now(),
        current_accused_id = NULL,
        last_event = jsonb_build_object(
          'type', 'vote_result', 'event_type', 'lynch',
          'victim_id', v_target_id, 'victim_name', v_victim_name,
          'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
          'cursed_converted', v_cursed_converted,
          'cursed_converted_name', v_cursed_converted_name
        ),
        last_vote_result = jsonb_build_object(
          'type', 'lynch',
          'victim_name', v_victim_name, 'victim_role', v_target_role,
          'soulmate_name', v_soulmate_name, 'soulmate_role', v_soulmate_role,
          'cursed_converted', v_cursed_converted,
          'cursed_converted_name', v_cursed_converted_name
        ),
        hunter_pending = v_hunter_pending,
        hunter_id = CASE WHEN v_hunter_pending THEN v_hunter_id ELSE NULL END
    WHERE room_id = p_room_id;
  END IF;

  v_game_over := check_game_over(p_room_id);
  RETURN jsonb_build_object('success', true, 'game_over', v_game_over, 'hunter_pending', v_hunter_pending);
END;
$function$
