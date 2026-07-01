<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

## Goal
- Ship a complete, production-ready Werewolf game with QoL improvements, dynamic Scenario Builder, and Tribunal day-phase system.

## Constraints & Preferences
- Manually fix DB via Supabase SQL Editor (migration files are reference copies, not auto-applied).
- `CREATE OR REPLACE FUNCTION` blocks in `src/lib/sql/` are neutered so deploy pipeline doesn't overwrite manual DB changes.
- Vercel stale cache: manual Redeploy required after push unless cache build is disabled in dashboard settings.

## Progress
### Done
- **SQL migrations neutralised** (commit `84fe80c`): All `.sql` files had `get_player_roles` and `submit_night_action` `CREATE OR REPLACE FUNCTION` blocks removed.
- **console.error label fix**: `host-role-panel.tsx` `'get_player_roles error:'` → `'fetch_roles_for_host error:'`.
- **RPC rename in React**: All components call `fetch_roles_for_host` / `execute_night_action`.
- **Production DB fixes** (run manually in SQL Editor): column type bumps (`action_type`, `night_step`, `status` → `TEXT`), `name::TEXT` casts in RPCs, `execute_night_action` rebuilt with role validation + witch‑flag tracking + `ON CONFLICT DO NOTHING`.
- **Seer result fix**: Removed `actedRoles.has('seer')` guard from `renderNightPanel()` in `page.tsx`.
- **Timer clock-skew fix**: `timer-display.tsx` uses `clientStartRef.current = Date.now()` when timer starts/resumes, computes elapsed client-side instead of from server `timer_started_at`.
- **5 QoL improvements** (commit `7098c78`):
  - Voting lock (`voting_open` column + host "Liberar Urnas" button + player buttons disabled while locked).
  - Endgame buttons: "Voltar para o Lobby" (host only, sets `rooms.status = 'waiting'`) and "Sair da Sala" (all, deletes player + redirect).
  - Lobby management: `beforeunload` listener deletes player via `fetch` with `keepalive: true`; host "Expulsar" button; "Sair da Sala" deletes from DB.
  - Host kill button: `☠️` in `HostRolePanel` calls `host_kill_player` RPC with confirmation modal.
  - Hide moderator from `HostRolePanel` via `filter(r.role !== 'moderator')`.
- **Fix: reset game on lobby return, dead player ignored in allViewed, kick notification** (commit `5ee8b36`):
  - `reset_game` trigger: when `rooms.status` changes to `'waiting'`, automatically resets `players` (`is_alive`, `has_viewed_card`, `role`), deletes `votes`, `night_actions`, `game_state`.
  - `allViewed` now ignores dead players (`!p.isAlive`).
  - Kicked player sees "🚫 Você foi expulso da sala pelo Host" modal via Realtime `DELETE` listener on `players`.
- **Scenario Builder** (commit `aa4b88d`):
  - `src/lib/cards.ts` — catalog of 4 cards (`werewolf`, `seer`, `witch`, `villager`) with `id`, `name`, `points`, `description`.
  - `src/components/scenario-builder.tsx` — host UI in lobby with +/- counters per card, thermometer (`< -3` red, `> 3` green, else yellow), tooltip with description/points, validation (total cards = non-host player count).
  - `src/lib/sql/migration-017-scenario-builder.sql` — new `start_game(p_room_id, p_roles JSONB)` replacing hardcoded distribution.
  - `src/components/flip-card.tsx` — shows card `description` and `points` on back face (points visible only in Scenario Builder tooltip since commit `3f3fea3`).
  - Lobby page: replaced `HostControls mode="start"` with `<ScenarioBuilder>`.
  - Game page: card_reveal resolves `CARD_CATALOG` and passes `name`, `description`, `points` to `FlipCard`.
- **Tribunal System** (commit `5cb3beb`):
  - `migration-018-tribunal.sql`: day_step/current_accused_id columns, submit_tribunal_vote, host_execute_accused, host_absolve_accused, host_day_to_night RPCs, updated advance_phase (day → night).
  - `tribunal-panel.tsx`: host panel for accusation, trial, voting, reveal.
  - `tribunal-voting.tsx`: player yes/no voting UI.
  - `tribunal-reveal.tsx`: vote tally display for all players.
  - `vote-timer-panel.tsx`: single reusable timer (was 3 timers).
  - page.tsx: separate day/vote phases replaced with unified tribunal day.
- **Tribunal fixes** (commit `3f3fea3`):
  - Card points removed from FlipCard (only visible in Scenario Builder tooltip).
  - Moderator excluded from accusation list (`players` table with `.neq('role', 'moderator')`).
  - Accused name fetched via useEffect on accusedId change (not reliant on modal state).
  - Timer moved to trial step (before voting opens).
  - SQL bug fix: `v_pvote_value` → `p_vote_value` in `submit_tribunal_vote`.
- **Game Over Delay + Host Action Log + Expulsion fix** (commit `pending`):
  - `migration-019-game-over-delay.sql`: `game_state.winner` column; `check_game_over()` and `trg_check_game_over()` only set `winner`, not rooms.status; new `host_end_game` RPC.
  - `host-action-log.tsx`: real-time night action log for host (wolves kill, seer investigate, witch save/poison).
  - `day-announcement.tsx`: `isHost` prop — cause of death hidden from non-host players.
  - page.tsx: game ended by `game_state.winner` (host sees Finalizar button), wolves_win in blood red, villager_win in yellow.
  - lobby page.tsx: `leavingRef` prevents false expulsion modal when leaving voluntarily.

### In Progress
- (none)

### Blocked
- Vercel stale build cache: pushes require manual Redeploy unless "Enable Build Cache" is turned off in Vercel dashboard.

## Key Decisions
- **Remove `actedRoles.has('seer')` guard** rather than adding `setTimeout` — simpler, and `nightStep !== 'seer'` already dismisses panel on host advance.
- **Use `clientStartRef` in timer** instead of modifying `start_timer` RPC — avoids touching SQL.
- **Use `filter(r.role !== 'moderator')`** in `HostRolePanel` to hide host — simplest frontend-only approach.
- **Use DB trigger `trg_reset_game`** for clean resets — fires automatically on any `rooms.status → 'waiting'` change, no frontend changes needed.
- **Scenario Builder** replaces hardcoded role distribution — host chooses exact card composition for each match.
- **Game over via `game_state.winner`** instead of immediate `rooms.status` change — lets death events render before host ends match.
- **Cause of death hidden from players** — only host sees via `DayAnnouncement isHost` prop.
- **Single reusable tribunal timer** instead of 3 fixed timers — host resets and reuses as needed.

## Next Steps
1. Run `migration-016-qol.sql` through `migration-019-game-over-delay.sql` in Supabase SQL Editor (if not already applied to production DB).
2. Disable Vercel build cache or do manual Redeploy.
3. Test all features in production.

## Critical Context
- **SQL migration files are reference copies** — the actual DB is maintained via SQL Editor. Migration files in `src/lib/sql/` have `CREATE OR REPLACE FUNCTION` blocks neutered to prevent deploy-time overwrite.
- **Vercel redeploy required** after any push due to stale build cache (`X-Vercel-Cache: HIT`). Disable "Enable Build Cache" in Vercel dashboard → Settings → Git to fix permanently.
- **`rooms.status` column was `VARCHAR(20)`** — caused `finished_villagers_win` (21 chars) to silently break game over. Now `TEXT`.
- **`execute_night_action` rebuilt** with full role validation, witch‑flag tracking, `ON CONFLICT DO NOTHING` — survived RPC neutering.
- **`reset_game` trigger** on `rooms` table: on status change to `'waiting'`, resets all players and clears votes/night_actions/game_state.
- **`host_kill_player` RPC** sets `is_alive = false`, records `last_event`, calls `check_game_over`.
- **Scenario Builder** sends flattened roles array (e.g. `['werewolf', 'werewolf', 'seer', 'villager']`) to `start_game(p_room_id, p_roles)`.
- **`game_state.winner`** replaces `rooms.status = 'finished_*'` for game-over detection — winner is stored at moment of death, but game only ends when host calls `host_end_game`.
- **`host_end_game` RPC** sets `rooms.status = 'finished_*'` and `current_phase = 'ended'` — called by host clicking Finalizar button.
- **Cause of death** (`lobisomem` / `veneno`) only visible to host — `DayAnnouncement isHost` prop.
- **Night actions logged** in real-time for host via `HostActionLog` component subscribed to `night_actions` INSERT.
- **Expulsion modal** guarded by `leavingRef` to prevent false trigger on voluntary leave.

## Relevant Files
- `src/lib/cards.ts` – card catalog with id, name, points, description.
- `src/components/scenario-builder.tsx` – host UI in lobby for building game scenario.
- `src/components/flip-card.tsx` – shows description on card back (points hidden since `3f3fea3`).
- `src/components/host-role-panel.tsx` – ☠️ kill button, filters moderator from list.
- `src/components/tribunal-panel.tsx` – host panel for accusation, trial, voting, reveal.
- `src/components/tribunal-voting.tsx` – player yes/no voting in tribunal.
- `src/components/tribunal-reveal.tsx` – vote tally display.
- `src/components/vote-timer-panel.tsx` – single reusable timer.
- `src/components/day-announcement.tsx` – day start with victims (cause hidden from non-host).
- `src/components/host-action-log.tsx` – real-time night action log for host.
- `src/components/voting-panel.tsx` – player voting (deprecated by tribunal system).
- `src/components/player-list.tsx` – lobby player list with kick button.
- `src/components/timer-display.tsx` – uses `clientStartRef` to avoid clock skew.
- `src/components/seer-panel.tsx` – calls `execute_night_action`, reads `res.data.is_werewolf`.
- `src/components/werewolf-panel.tsx` – calls `get_werewolf_teammates` then `execute_night_action`.
- `src/components/witch-panel.tsx` – calls `execute_night_action` twice (save + poison).
- `src/app/game/[id]/page.tsx` – renders all game phases; game over by `game_state.winner`; Finalizar button for host.
- `src/app/lobby/[id]/page.tsx` – ScenarioBuilder, kick, beforeunload, leavingRef for expulsion.
- `src/hooks/use-room.ts` – `GameStateRow` includes `winner`, `day_step`, `current_accused_id`.
- `src/lib/sql/migration-019-game-over-delay.sql` – winner column, neutered check_game_over, host_end_game RPC.
- `src/lib/sql/migration-018-tribunal.sql` – tribunal system (day steps, RPCs).
- `src/lib/sql/migration-017-scenario-builder.sql` – new `start_game(p_room_id, p_roles JSONB)`.
- `src/lib/sql/migration-016-qol.sql` – voting_open, host_kill_player, reset_game trigger.
- `src/lib/sql/` – 19 migration files, all with `get_player_roles`/`submit_night_action` `CREATE` blocks removed.
- `src/lib/sql/migration-complete-safe.sql` – runs DDL (tables, constraints) but no longer recreates old RPCs.
