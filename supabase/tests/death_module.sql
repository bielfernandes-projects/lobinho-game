-- Death module tests. Safe to run in the SQL Editor: everything happens inside one DO block that
-- always ends with an exception, so NOTHING is persisted.
--   Expected final message:  TODOS OS TESTES PASSARAM (rollback intencional)
-- helper: a real auth user for the fixture (rooms.host_id / players.user_id have foreign keys)
CREATE OR REPLACE FUNCTION pg_temp.mkuser() RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE u uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id) VALUES (u);
  RETURN u;
END;
$f$;

DO $test$
DECLARE
  v_room UUID := gen_random_uuid();
  v_host_user UUID := pg_temp.mkuser();
  v_host UUID;
  a UUID; b UUID; h UUID; p UUID; s UUID; d UUID; c UUID; vw UUID; vp UUID; w UUID;
  dg UUID; dgt UUID; poisoned UUID; wolfvictim UUID; guard UUID; tg UUID; x UUID;
  r JSONB;

BEGIN
  INSERT INTO rooms (id, pin_code, host_id) VALUES (v_room, floor(random()*9000+1000)::int::text, v_host_user);
  INSERT INTO players (room_id, name, user_id, role, is_host) VALUES (v_room, 'Host', v_host_user, 'moderator', true) RETURNING id INTO v_host;
  INSERT INTO game_state (room_id, current_phase, turn_index) VALUES (v_room, 'night', 2);

  -- ───────── kill_players ─────────
  -- 1. soulmate chain
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'A', pg_temp.mkuser(), 'villager') RETURNING id INTO a;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'B', pg_temp.mkuser(), 'villager') RETURNING id INTO b;
  UPDATE players SET soulmate_id = b WHERE id = a;
  UPDATE players SET soulmate_id = a WHERE id = b;
  r := kill_players(v_room, ARRAY[a], ARRAY['teste']);
  IF jsonb_array_length(r->'deaths') <> 2 THEN RAISE EXCEPTION 'FALHOU 1a: soulmate deveria gerar 2 mortes, veio %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'deaths') e WHERE e->>'id' = b::text AND e->>'cause' = 'soulmate') THEN
    RAISE EXCEPTION 'FALHOU 1b: B deveria morrer por soulmate, veio %', r; END IF;

  -- 2. idempotent on dead players
  r := kill_players(v_room, ARRAY[a], ARRAY['teste']);
  IF jsonb_array_length(r->'deaths') <> 0 THEN RAISE EXCEPTION 'FALHOU 2: matar morto deveria dar 0 mortes, veio %', r; END IF;

  -- 3. Dire Wolf dies with companion
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'C', pg_temp.mkuser(), 'villager') RETURNING id INTO c;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'D', pg_temp.mkuser(), 'dire_wolf') RETURNING id INTO d;
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 1, d, 'dire_wolf_companion', c);
  r := kill_players(v_room, ARRAY[c], ARRAY['teste']);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'deaths') e WHERE e->>'id' = d::text) THEN
    RAISE EXCEPTION 'FALHOU 3: Dire Wolf deveria morrer com o companheiro, veio %', r; END IF;

  -- 4. Virginia Wolf takes partner
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'VW', pg_temp.mkuser(), 'virginia_wolf') RETURNING id INTO vw;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'VP', pg_temp.mkuser(), 'villager') RETURNING id INTO vp;
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 1, vw, 'virginia_partner', vp);
  r := kill_players(v_room, ARRAY[vw], ARRAY['teste']);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'deaths') e WHERE e->>'id' = vp::text) THEN
    RAISE EXCEPTION 'FALHOU 4: par da Virginia deveria morrer, veio %', r; END IF;

  -- 5. Hunter pending
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'H', pg_temp.mkuser(), 'hunter') RETURNING id INTO h;
  r := kill_players(v_room, ARRAY[h], ARRAY['teste']);
  IF NOT (r->>'hunter_pending')::boolean OR (r->>'hunter_id')::uuid <> h THEN RAISE EXCEPTION 'FALHOU 5: Cacador pendente, veio %', r; END IF;

  -- 6. Prince dies -> Squire promoted
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'P', pg_temp.mkuser(), 'prince') RETURNING id INTO p;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'S', pg_temp.mkuser(), 'squire') RETURNING id INTO s;
  r := kill_players(v_room, ARRAY[p], ARRAY['teste']);
  IF (SELECT role FROM players WHERE id = s) <> 'prince' THEN RAISE EXCEPTION 'FALHOU 6: Escudeiro deveria virar Principe'; END IF;

  -- 7. Prince + Squire die together -> no promotion of a dead squire
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'P2', pg_temp.mkuser(), 'prince') RETURNING id INTO p;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'S2', pg_temp.mkuser(), 'squire') RETURNING id INTO s;
  r := kill_players(v_room, ARRAY[p, s], ARRAY['teste', 'teste']);
  IF (SELECT role FROM players WHERE id = s) <> 'squire' THEN RAISE EXCEPTION 'FALHOU 7: Escudeiro morto nao deveria ser promovido'; END IF;

  -- 8. Doppelganger copies a dead target's role
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'DGT', pg_temp.mkuser(), 'seer') RETURNING id INTO dgt;
  INSERT INTO players (room_id, name, user_id, role, doppelganger_target_id) VALUES (v_room, 'DG', pg_temp.mkuser(), 'doppelganger', dgt) RETURNING id INTO dg;
  r := kill_players(v_room, ARRAY[dgt], ARRAY['teste']);
  IF (SELECT role FROM players WHERE id = dg) <> 'seer' THEN RAISE EXCEPTION 'FALHOU 8: Doppelganger deveria virar seer'; END IF;

  -- ───────── resolve_night ─────────
  PERFORM set_config('request.jwt.claim.sub', v_host_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host_user)::text, true);

  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'W', pg_temp.mkuser(), 'werewolf') RETURNING id INTO w;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'V1', pg_temp.mkuser(), 'villager') RETURNING id INTO wolfvictim;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'V2', pg_temp.mkuser(), 'villager') RETURNING id INTO poisoned;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'GD', pg_temp.mkuser(), 'bodyguard') RETURNING id INTO guard;

  -- 9. wolves kill V1
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 2, w, 'werewolf_kill', wolfvictim);
  r := resolve_night(v_room);
  IF (SELECT is_alive FROM players WHERE id = wolfvictim) THEN RAISE EXCEPTION 'FALHOU 9: V1 deveria morrer'; END IF;
  IF jsonb_array_length(r->'victims') <> 1 THEN RAISE EXCEPTION 'FALHOU 9b: 1 vitima esperada, veio %', r; END IF;

  -- 10. bodyguard protects the wolf target
  UPDATE game_state SET current_phase = 'night', turn_index = 3 WHERE room_id = v_room;
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'V3', pg_temp.mkuser(), 'villager') RETURNING id INTO x;
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 3, w, 'werewolf_kill', x);
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 3, guard, 'bodyguard_protect', x);
  r := resolve_night(v_room);
  IF NOT (SELECT is_alive FROM players WHERE id = x) THEN RAISE EXCEPTION 'FALHOU 10: Guarda-costas deveria proteger'; END IF;

  -- 11. DISEASED SKIP: wolves skip, but the witch poison still kills
  UPDATE game_state SET current_phase = 'night', turn_index = 4, diseased_skip_wolves = true WHERE room_id = v_room;
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 4, w, 'werewolf_kill', x);
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 4, w, 'witch_poison', poisoned);
  r := resolve_night(v_room);
  IF NOT (SELECT is_alive FROM players WHERE id = x) THEN RAISE EXCEPTION 'FALHOU 11a: lobos deveriam pular a noite'; END IF;
  IF (SELECT is_alive FROM players WHERE id = poisoned) THEN RAISE EXCEPTION 'FALHOU 11b: veneno deveria continuar valendo na noite do Doente'; END IF;
  IF (SELECT diseased_skip_wolves FROM game_state WHERE room_id = v_room) THEN RAISE EXCEPTION 'FALHOU 11c: flag do Doente deveria ser consumida'; END IF;

  -- 12. Tough Guy: marked on night N, dies on a later night
  INSERT INTO players (room_id, name, user_id, role) VALUES (v_room, 'TG', pg_temp.mkuser(), 'tough_guy') RETURNING id INTO tg;
  UPDATE game_state SET current_phase = 'night', turn_index = 5 WHERE room_id = v_room;
  INSERT INTO night_actions (room_id, turn_index, actor_id, action_type, target_id) VALUES (v_room, 5, w, 'werewolf_kill', tg);
  r := resolve_night(v_room);
  IF NOT (SELECT is_alive FROM players WHERE id = tg) THEN RAISE EXCEPTION 'FALHOU 12a: Tough Guy nao deveria morrer na mesma noite'; END IF;
  UPDATE game_state SET current_phase = 'night', turn_index = 6 WHERE room_id = v_room;
  r := resolve_night(v_room);
  IF (SELECT is_alive FROM players WHERE id = tg) THEN RAISE EXCEPTION 'FALHOU 12b: Tough Guy deveria morrer na noite seguinte'; END IF;

  RAISE EXCEPTION 'TODOS OS TESTES PASSARAM (rollback intencional)';
END
$test$;
