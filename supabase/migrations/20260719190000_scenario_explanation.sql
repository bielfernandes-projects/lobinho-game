-- 20260719190000_scenario_explanation.sql
-- Adiciona fase 'scenario_reveal' entre o lobby e o card_reveal.
-- Nesta fase, todos os jogadores veem a composição do cenário
-- (lista de papéis) e o mestre explica as regras antes de iniciar.
--
-- Cria RPC `advance_to_card_reveal` que transiciona da fase
-- 'scenario_reveal' para 'card_reveal'.

-- 1. Atualizar a constraint de current_phase na tabela game_state
-- (a coluna é TEXT, sem CHECK — atualizar lógica nos comentários)
-- Esta fase é usada no frontend; nenhuma constraint precisa mudar.

-- 2. RPC: advance_to_card_reveal — host avança da explicação do cenário
-- para a fase de revelação das cartas.
CREATE OR REPLACE FUNCTION public.advance_to_card_reveal(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_current_phase TEXT;
BEGIN
  -- Verificar que o caller é o host
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode iniciar o jogo';
  END IF;

  -- Verificar fase atual
  SELECT current_phase INTO v_current_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase IS NULL THEN
    RAISE EXCEPTION 'game_state não inicializado';
  END IF;

  IF v_current_phase != 'scenario_reveal' THEN
    RAISE EXCEPTION 'Não é possível iniciar a revelação a partir da fase %', v_current_phase;
  END IF;

  -- Transicionar para card_reveal
  UPDATE game_state
  SET current_phase = 'card_reveal',
      day_step = 'discussion'
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 3. RPC: back_to_lobby_from_scenario — host volta ao lobby durante a
-- fase scenario_reveal (reseta o jogo)
CREATE OR REPLACE FUNCTION public.back_to_lobby_from_scenario(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_is_host BOOLEAN;
  v_current_phase TEXT;
BEGIN
  -- Verificar que o caller é o host
  SELECT id, is_host INTO v_caller_id, v_caller_is_host
  FROM players WHERE user_id = auth.uid() AND room_id = p_room_id;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Jogador não encontrado na sala';
  END IF;

  IF NOT v_caller_is_host THEN
    RAISE EXCEPTION 'Apenas o mestre pode voltar ao lobby';
  END IF;

  -- Verificar fase atual
  SELECT current_phase INTO v_current_phase
  FROM game_state WHERE room_id = p_room_id;

  IF v_current_phase IS NULL THEN
    RAISE EXCEPTION 'game_state não inicializado';
  END IF;

  IF v_current_phase != 'scenario_reveal' THEN
    RAISE EXCEPTION 'Não é possível voltar ao lobby a partir da fase %', v_current_phase;
  END IF;

  -- Voltar ao lobby: muda status da sala para 'waiting'
  UPDATE rooms
  SET status = 'waiting'
  WHERE id = p_room_id;

  -- O trigger trg_reset_game cuida de limpar game_state e strikes

  RETURN jsonb_build_object('success', true);
END;
$$;
