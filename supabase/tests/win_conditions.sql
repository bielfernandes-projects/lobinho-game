-- Win-condition tests for compute_winner. Rollback-only (always ends with an exception).
--   Expected final message:  TODOS OS TESTES PASSARAM (rollback intencional)
CREATE OR REPLACE FUNCTION pg_temp.mkuser() RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE u uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id) VALUES (u);
  RETURN u;
END;
$f$;

CREATE OR REPLACE FUNCTION pg_temp.mkroom() RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE r uuid := gen_random_uuid(); h uuid := pg_temp.mkuser(); pin text;
BEGIN
  LOOP
    pin := floor(random()*9000+1000)::int::text;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM rooms WHERE pin_code = pin);
  END LOOP;
  INSERT INTO rooms (id, pin_code, host_id) VALUES (r, pin, h);
  INSERT INTO players (room_id, name, user_id, role, is_host) VALUES (r, 'Host', h, 'moderator', true);
  INSERT INTO game_state (room_id, current_phase, turn_index) VALUES (r, 'night', 2);
  RETURN r;
END;
$f$;

CREATE OR REPLACE FUNCTION pg_temp.mkp(r uuid, n text, rl text, alive boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE pid uuid;
BEGIN
  INSERT INTO players (room_id, name, user_id, role, is_alive) VALUES (r, n, pg_temp.mkuser(), rl, alive) RETURNING id INTO pid;
  RETURN pid;
END;
$f$;

DO $test$
DECLARE
  r UUID; a UUID; b UUID;
BEGIN
  -- villagers win: no wolf-team alive
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'seer'); PERFORM pg_temp.mkp(r, 'W', 'werewolf', false);
  IF compute_winner(r) IS DISTINCT FROM 'villagers_win' THEN RAISE EXCEPTION 'FALHOU 1: villagers_win, veio %', compute_winner(r); END IF;

  -- wolves win on parity
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  IF compute_winner(r) IS DISTINCT FROM 'wolves_win' THEN RAISE EXCEPTION 'FALHOU 2: wolves_win, veio %', compute_winner(r); END IF;

  -- game goes on: 2 villagers vs 1 wolf
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  IF compute_winner(r) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 3: jogo deveria continuar, veio %', compute_winner(r); END IF;

  -- lone wolf: last alive, 1v1, 3 alive continues
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'L', 'lone_wolf'); PERFORM pg_temp.mkp(r, 'V1', 'villager', false);
  IF compute_winner(r) IS DISTINCT FROM 'lone_wolf_win' THEN RAISE EXCEPTION 'FALHOU 4a: lone_wolf ultimo, veio %', compute_winner(r); END IF;
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'L', 'lone_wolf'); PERFORM pg_temp.mkp(r, 'V1', 'villager');
  IF compute_winner(r) IS DISTINCT FROM 'lone_wolf_win' THEN RAISE EXCEPTION 'FALHOU 4b: lone_wolf 1v1, veio %', compute_winner(r); END IF;
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'L', 'lone_wolf'); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager');
  IF compute_winner(r) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 4c: lone_wolf com 3 vivos continua, veio %', compute_winner(r); END IF;

  -- chupacabra: last alive; 3 alive and no wolves does not end as villagers_win
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'C', 'chupacabra'); PERFORM pg_temp.mkp(r, 'V1', 'villager', false);
  IF compute_winner(r) IS DISTINCT FROM 'chupacabra_win' THEN RAISE EXCEPTION 'FALHOU 5a: chupacu ultimo, veio %', compute_winner(r); END IF;
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'C', 'chupacabra'); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager');
  IF compute_winner(r) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 5b: chupacu vivo com 3 vivos nao encerra, veio %', compute_winner(r); END IF;

  -- minion counts as wolf team (keeps the game from ending as villagers_win)
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'M', 'minion'); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager');
  IF compute_winner(r) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 6: lacaio vivo mantem o jogo, veio %', compute_winner(r); END IF;

  -- soulmates: exactly two alive and linked
  r := pg_temp.mkroom(); a := pg_temp.mkp(r, 'A', 'villager'); b := pg_temp.mkp(r, 'B', 'werewolf');
  UPDATE players SET soulmate_id = b WHERE id = a; UPDATE players SET soulmate_id = a WHERE id = b;
  IF compute_winner(r) IS DISTINCT FROM 'soulmates_win' THEN RAISE EXCEPTION 'FALHOU 7: soulmates_win, veio %', compute_winner(r); END IF;

  -- cult: leader + everyone else converted
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'CL', 'cult_leader'); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  UPDATE players SET in_cult = true WHERE room_id = r AND name IN ('V1', 'V2', 'W');
  IF compute_winner(r) IS DISTINCT FROM 'cult_win' THEN RAISE EXCEPTION 'FALHOU 8: cult_win, veio %', compute_winner(r); END IF;

  -- tanner lynched
  r := pg_temp.mkroom(); a := pg_temp.mkp(r, 'T', 'tanner', false); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  UPDATE game_state SET last_event = jsonb_build_object('event_type', 'lynch', 'victim_id', a) WHERE room_id = r;
  IF compute_winner(r) IS DISTINCT FROM 'tanner_win' THEN RAISE EXCEPTION 'FALHOU 9: tanner_win, veio %', compute_winner(r); END IF;

  -- not started yet
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  UPDATE game_state SET current_phase = 'card_reveal' WHERE room_id = r;
  IF compute_winner(r) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 10: card_reveal nao encerra jogo'; END IF;

  -- the trigger path writes the same answer into game_state.winner
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'V2', 'villager'); b := pg_temp.mkp(r, 'W', 'werewolf');
  UPDATE players SET is_alive = false WHERE id = b;
  IF (SELECT winner FROM game_state WHERE room_id = r) IS DISTINCT FROM 'villagers_win' THEN
    RAISE EXCEPTION 'FALHOU 11: trigger deveria gravar villagers_win, veio %', (SELECT winner FROM game_state WHERE room_id = r); END IF;

  -- check_game_over RPC result
  r := pg_temp.mkroom(); PERFORM pg_temp.mkp(r, 'V1', 'villager'); PERFORM pg_temp.mkp(r, 'W', 'werewolf');
  IF (check_game_over(r)->>'winner') IS DISTINCT FROM 'wolves_win' THEN RAISE EXCEPTION 'FALHOU 12: check_game_over deveria devolver wolves_win'; END IF;

  RAISE EXCEPTION 'TODOS OS TESTES PASSARAM (rollback intencional)';
END
$test$;
