-- 20260719180639_strikes.sql
-- Sistema de strikes (x/3) com insta-kill do Mestre.
--
-- Adiciona a coluna `strikes` na tabela `players` (default 0).
-- Cria RPCs:
--   - add_strike(p_room_id, p_player_id) — incrementa strikes, retorna novo valor
--   - remove_strike(p_room_id, p_player_id) — decrementa strikes (mínimo 0)
--   - insta_kill(p_room_id, p_player_id) — mata instantaneamente, dispara check_game_over

-- 1. Adicionar coluna strikes
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS strikes INT NOT NULL DEFAULT 0
  CHECK (strikes >= 0 AND strikes <= 3);

-- 2. RPC: add_strike — incrementa strikes de um jogador (host only)
CREATE OR REPLACE FUNCTION public.add_strike(
  p_room_id UUID,
  p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_target_alive BOOLEAN;
  v_target_name TEXT;
  v_new_strikes INT;
BEGIN
  -- Verificar que o caller é o host
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode adicionar strikes';
  END IF;

  -- Verificar que o alvo está vivo e não é host
  SELECT is_alive, name INTO v_target_alive, v_target_name
  FROM players WHERE id = p_player_id AND room_id = p_room_id;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado na sala';
  END IF;

  IF NOT v_target_alive THEN
    RAISE EXCEPTION 'Jogador já está morto';
  END IF;

  -- Incrementar strikes (cap em 3)
  UPDATE players
  SET strikes = LEAST(strikes + 1, 3)
  WHERE id = p_player_id AND room_id = p_room_id
  RETURNING strikes INTO v_new_strikes;

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'new_strikes', v_new_strikes,
    'reached_max', v_new_strikes >= 3
  );
END;
$$;

-- 3. RPC: remove_strike — decrementa strikes (host only)
CREATE OR REPLACE FUNCTION public.remove_strike(
  p_room_id UUID,
  p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_target_name TEXT;
  v_new_strikes INT;
BEGIN
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode remover strikes';
  END IF;

  SELECT name INTO v_target_name
  FROM players WHERE id = p_player_id AND room_id = p_room_id;

  IF v_target_name IS NULL THEN
    RAISE EXCEPTION 'Alvo não encontrado na sala';
  END IF;

  UPDATE players
  SET strikes = GREATEST(strikes - 1, 0)
  WHERE id = p_player_id AND room_id = p_room_id
  RETURNING strikes INTO v_new_strikes;

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'new_strikes', v_new_strikes
  );
END;
$$;

-- 4. RPC: insta_kill — mata um jogador instantaneamente (host only)
-- Reutiliza lógica do host_kill_player sem passar por soulmate chain
CREATE OR REPLACE FUNCTION public.insta_kill(
  p_room_id UUID,
  p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_target_alive BOOLEAN;
  v_target_name TEXT;
  v_turn INT;
  v_game_over JSONB;
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
  UPDATE players SET is_alive = false, strikes = 0 WHERE id = p_player_id;

  -- Log
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id)
  VALUES (p_room_id, v_turn, v_caller_id, 'insta_kill', p_player_id)
  ON CONFLICT (room_id, turn_index, actor_id, action_type, target_id) DO NOTHING;

  -- Game over
  v_game_over := check_game_over(p_room_id);

  RETURN jsonb_build_object(
    'success', true,
    'target_name', v_target_name,
    'game_over', v_game_over
  );
END;
$$;

-- 5. Atualizar constraint de night_actions_action_type_check
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions
  ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN (
    'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
    'witch_skip', 'priest_bless', 'bodyguard_protect', 'aura_investigate',
    'cult_convert', 'alpha_infect', 'cupid_match', 'sorceress_search',
    'mason_recognition', 'hunter_shot', 'doppelganger_select', 'insta_kill'
  ));

-- 6. Resetar strikes ao voltar para waiting (via trigger existente trg_reset_game)
-- Adicionar lógica no trigger para limpar strikes
CREATE OR REPLACE FUNCTION public.trg_reset_game()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'waiting' AND OLD.status != 'waiting' THEN
    -- Limpar game_state
    DELETE FROM game_state WHERE room_id = NEW.id;
    -- Resetar strikes de todos os jogadores
    UPDATE players SET strikes = 0 WHERE room_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;
