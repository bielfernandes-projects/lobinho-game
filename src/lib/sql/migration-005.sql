-- ============================================================
-- MIGRATION 005: timer dinamico da Fase do Dia
-- ============================================================

-- ============================================================
-- 1. COLUNAS DE TIMER no game_state
-- ============================================================
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_duration INT;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_remaining INT;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS is_timer_running BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE game_state ADD COLUMN IF NOT EXISTS timer_started_at TIMESTAMPTZ;

-- ============================================================
-- 2. RPC: start_timer
--    Inicia o cronometro com duracao definida pelo host
-- ============================================================
CREATE OR REPLACE FUNCTION public.start_timer(p_room_id UUID, p_duration INT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode iniciar o cronometro';
  END IF;

  IF p_duration < 60 OR p_duration > 600 THEN
    RAISE EXCEPTION 'Duracao deve ser entre 60 e 600 segundos';
  END IF;

  UPDATE game_state
  SET timer_duration = p_duration,
      timer_remaining = p_duration,
      is_timer_running = true,
      timer_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;

-- ============================================================
-- 3. RPC: pause_timer
--    Congela o tempo restante atual
-- ============================================================
CREATE OR REPLACE FUNCTION public.pause_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_started TIMESTAMPTZ;
  v_remaining INT;
  v_running BOOLEAN;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode pausar o cronometro';
  END IF;

  SELECT is_timer_running, timer_remaining, timer_started_at
    INTO v_running, v_remaining, v_started
  FROM game_state WHERE room_id = p_room_id;

  IF NOT v_running THEN
    RAISE EXCEPTION 'Cronometro ja esta pausado';
  END IF;

  v_remaining := GREATEST(0, v_remaining - EXTRACT(EPOCH FROM (now() - v_started))::INT);

  UPDATE game_state
  SET is_timer_running = false,
      timer_remaining = v_remaining,
      timer_started_at = null
  WHERE room_id = p_room_id;
END;
$$;

-- ============================================================
-- 4. RPC: resume_timer
--    Retoma a contagem de onde parou
-- ============================================================
CREATE OR REPLACE FUNCTION public.resume_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode retomar o cronometro';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM game_state WHERE room_id = p_room_id AND is_timer_running = false AND timer_remaining > 0
  ) THEN
    RAISE EXCEPTION 'Cronometro nao pode ser retomado';
  END IF;

  UPDATE game_state
  SET is_timer_running = true,
      timer_started_at = now()
  WHERE room_id = p_room_id;
END;
$$;

-- ============================================================
-- 5. RPC: reset_timer
--    Zera o cronometro
-- ============================================================
CREATE OR REPLACE FUNCTION public.reset_timer(p_room_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE room_id = p_room_id AND user_id = auth.uid() AND is_host = true
  ) THEN
    RAISE EXCEPTION 'Somente o host pode resetar o cronometro';
  END IF;

  UPDATE game_state
  SET timer_duration = null,
      timer_remaining = null,
      is_timer_running = false,
      timer_started_at = null
  WHERE room_id = p_room_id;
END;
$$;
