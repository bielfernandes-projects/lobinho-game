# Lobinho Game — Architecture & Documentation

## Overview
A real-time multiplayer Werewolf (Lobisomem) party game built with Next.js 16, Supabase (PostgreSQL + Realtime), and Tailwind CSS. Host creates a room, players join, host configures the role scenario, and the classic night/day cycle plays out with a Tribunal day-phase system.

## Game Flow (State Machine)

```
lobby → card_reveal → night → day → (tribunal or night) → game_over
```

| Phase | Description |
|-------|-------------|
| `waiting` / lobby | Players join; host configures scenario (role distribution). |
| `card_reveal` | Each player sees their role card; host advances when all viewed. |
| `night` | Host wakes roles sequentially (wolves → seer → witch); each performs action. |
| `day` | Announcement (victims) → discussion → tribunal phase (trial → voting → reveal). May loop back to night. |
| `finished_villagers_win` | Game over — villagers win. |
| `finished_wolves_win` | Game over — wolves win. |

**`current_phase`** values: `waiting`, `card_reveal`, `night`, `day`, `ended`.

**`day_step`** (when `current_phase = 'day'`): `announcement`, `discussion`, `trial`, `voting`, `reveal`.

**`night_step`** (when `current_phase = 'night'`): `sleeping`, `wolves`, `seer`, `witch`.

---

## Commit History

### `84fe80c` — SQL migrations neutralised
- Removed all `CREATE OR REPLACE FUNCTION` blocks from `.sql` files (get_player_roles, submit_night_action).
- Deploy pipeline no longer overwrites manual DB changes.

### `7098c78` — 5 QoL improvements
- **Voting lock**: `voting_open` column; host "Liberar Urnas" button; player buttons disabled while locked.
- **Endgame buttons**: "Voltar para o Lobby" (host only, `rooms.status = 'waiting'`); "Sair da Sala" (all, delete player + redirect).
- **Lobby management**: `beforeunload` listener deletes player via `fetch` + `keepalive: true`; host "Expulsar" button; "Sair da Sala" deletes from DB.
- **Host kill button**: ☠️ in `HostRolePanel` calls `host_kill_player` RPC with confirmation modal.
- **Hide moderator** from `HostRolePanel` via `filter(r.role !== 'moderator')`.

### `5ee8b36` — Reset game on lobby return, dead player ignored, kick notification
- `trg_reset_game` trigger: on `rooms.status → 'waiting'`, resets `players` (`is_alive`, `has_viewed_card`, `role`), deletes `votes`, `night_actions`, `game_state`.
- `allViewed` ignores dead players (`!p.isAlive`).
- Kicked player sees "🚫 Você foi expulso" modal via Realtime `DELETE` listener.

### `aa4b88d` — Scenario Builder
- `src/lib/cards.ts`: catalog of 4 cards (`werewolf`, `seer`, `witch`, `villager`), later expanded to 8 cards in Lot 1.
- `src/components/scenario-builder.tsx`: host UI with +/- counters, thermometer, tooltip, validation.
- `src/lib/sql/migration-017-scenario-builder.sql`: new `start_game(p_room_id, p_roles JSONB)`.
- Game page: card_reveal resolves `CARD_CATALOG` and passes name/description/points to `FlipCard`.

### `5cb3beb` — Tribunal System
- `migration-018-tribunal.sql`: `day_step`/`current_accused_id` columns; `submit_tribunal_vote`, `host_execute_accused`, `host_absolve_accused`, `host_day_to_night` RPCs.
- `tribunal-panel.tsx`: host panel for accusation, trial, voting, reveal.
- `tribunal-voting.tsx`: player yes/no voting UI.
- `tribunal-reveal.tsx`: vote tally display.
- `vote-timer-panel.tsx`: single reusable timer (replaced 3).
- `page.tsx`: separate day/vote phases replaced with unified tribunal day.

### `3f3fea3` — Tribunal fixes
- Card points removed from FlipCard (only in Scenario Builder tooltip).
- Moderator excluded from accusation list.
- Accused name fetched via `useEffect` on `accusedId`.
- Timer moved to trial step (before voting opens).
- SQL bug fix: `v_pvote_value` → `p_vote_value`.

### `9e25b27` — Game Over Delay + Host Action Log
- `migration-019-game-over-delay.sql`: `game_state.winner` column; `check_game_over()` and `trg_check_game_over()` only set `winner` (not `rooms.status`); new `host_end_game` RPC.
- `host-action-log.tsx`: real-time night action log via Realtime `night_actions` subscription.
- `day-announcement.tsx`: `isHost` prop hides cause of death from non-host.
- `page.tsx`: game ended by `game_state.winner`; host sees "Finalizar Partida"; `wolves_win` in blood red (`text-red-700`), `villagers_win` in yellow (`text-yellow-500`).
- `lobby/[id]/page.tsx`: `leavingRef` prevents false expulsion on voluntary leave.

### `1e690f7` — Moderator excluded from `v_non_wolves`
- `check_game_over` trigger's `v_non_wolves` count uses `role NOT IN ('werewolf', 'moderator')`.
- Moderator is neutral; their presence shouldn't count toward villager team for win condition.

### `fa028ae` — Dynamic Night Controls
- Night role buttons (wolves/seer/witch) only appear if those roles exist in `players` for the current game.
- `availableNightRoles` state (Set<string>) populated via `useEffect` querying `players` table.
- Buttons rendered via `.filter((b) => availableNightRoles.has(b.role))`.

### `6940c6c` — Expansion Lot 1 (Mayor, Prince, Tanner, Lycan)
- **CARD_CATALOG** (`src/lib/cards.ts`): 4 new cards added (mayor, prince, tanner, lycan).
- **Mayor vote** (`tribunal-reveal.tsx`): weighted vote counting (mayor = 2), `x2` badge displayed.
- **Prince immunity** (`host_execute_accused` RPC): if accused role is `prince`, identity revealed and absolved instead of killed.
- **Tanner win** (`check_game_over` / `trg_check_game_over`): dead tanner with `last_event.event_type = 'lynch'` → `winner = 'tanner_win'` (highest priority).
- **Lycan seer check** (`execute_night_action` RPC): seer sees lycan as werewolf (`role IN ('werewolf', 'lycan')`).
- **`host_execute_accused` reordered**: `game_state.last_event` set BEFORE `players.is_alive` UPDATE so trigger sees lynch context.
- **`host_end_game` updated**: handles `tanner_win` → `rooms.status = 'finished_tanner_win'`.
- **Rooms constraint**: added `'finished_tanner_win'` to status check.
- **Game screen** (`page.tsx`): `gameEnded` includes `'finished_tanner_win'`; `renderEnded` shows gray/brown tanner victory screen.

### `<current>` — 5 UX/QoL improvements
- **Day Announcement (Task 1)**: `day_step = 'announcement'` added to `resolve_night` RPC (applied via `supabase db push`, migration `20260701130300_day_step_announcement`); host sees "Iniciar Debate" button; players see victims without sub-phase content until host starts discussion.
- **Winner names (Task 2)**: `renderEnded` queries `players` table for `role = 'werewolf'` (wolves win) or `role = 'tanner'` (tanner win) and displays the names below the victory banner.
- **Night guide (Task 3)**: `WAKE_ORDER` constant used to show current turn indicator (`📍 Vez: 🐺 Lobisomens`) in host night panel; "✅ Todas as ações concluídas" when wolves resolved and step is sleeping.
- **Scenario localStorage (Task 4)**: `counts` persisted to/restored from `localStorage` key `lobinho_last_scenario` — host's role distribution survives page refresh.
- **Player limit 25 (Task 5)**: `player-list.tsx` shows `/25` instead of `/8`; `scenario-builder.tsx` validates `playerCount <= 25`.

### `6940c6c+1` — Fix players_role_check constraint
- Added missing `mayor`, `prince`, `tanner`, `lycan` to `players_role_check` constraint.
- `migration-021-fix-role-constraint.sql`: single ALTER TABLE to drop and recreate constraint.
- Start game was failing with "violates check constraint players_role_check" for any scenario using new roles.

---

## Component Catalog

| Component | File | Responsibility |
|-----------|------|----------------|
| ScenarioBuilder | `src/components/scenario-builder.tsx` | Host UI in lobby; +/- counters per card, validation, tooltip |
| FlipCard | `src/components/flip-card.tsx` | Role card display (description on back, points hidden) |
| HostRolePanel | `src/components/host-role-panel.tsx` | ☠️ kill button; filters moderator; role list |
| TribunalPanel | `src/components/tribunal-panel.tsx` | Host panel: accuse, trial, voting, reveal |
| TribunalVoting | `src/components/tribunal-voting.tsx` | Player yes/no voting (SIM = lynch, NÃO = absolve) |
| TribunalReveal | `src/components/tribunal-reveal.tsx` | Vote tally for all players |
| VoteTimerPanel | `src/components/vote-timer-panel.tsx` | Single reusable timer (start/stop/reset) |
| DayAnnouncement | `src/components/day-announcement.tsx` | Day start with victims; cause hidden from non-host; host "Iniciar Debate" button |
| HostActionLog | `src/components/host-action-log.tsx` | Real-time night action log via Realtime |
| VotingPanel | `src/components/voting-panel.tsx` | Legacy player voting (deprecated by tribunal) |
| PlayerList | `src/components/player-list.tsx` | Lobby player list with kick button |
| TimerDisplay | `src/components/timer-display.tsx` | Timer widget using `clientStartRef` to avoid clock skew |
| SeerPanel | `src/components/seer-panel.tsx` | Seer night action: investigate player, see is_werewolf |
| WerewolfPanel | `src/components/werewolf-panel.tsx` | Werewolf night action: see teammates, choose victim |
| WitchPanel | `src/components/witch-panel.tsx` | Witch night action: save (first kill) + poison (once each) |

### Pages

| Page | Route | File |
|------|-------|------|
| Home | `/` | (root, redirects to room creation) |
| Lobby | `/lobby/[id]` | `src/app/lobby/[id]/page.tsx` |
| Game | `/game/[id]` | `src/app/game/[id]/page.tsx` |

### Hooks

| Hook | File | Role |
|------|------|------|
| `use-room` | `src/hooks/use-room.ts` | Fetches room, player, game state; `GameStateRow` includes `winner`, `day_step`, `current_accused_id` |

---

## SQL Migrations Reference

| File | Purpose | Status |
|------|---------|--------|
| `migration-001-base.sql` | Core schema (rooms, players, votes, game_state) | Applied, neutered |
| `migration-002-night-actions.sql` | Night actions table + RPCs | Applied, neutered |
| `migration-003-to-015` | Iterative fixes (columns, triggers, views) | Applied, neutered |
| `migration-016-qol.sql` | `voting_open`, `host_kill_player`, `trg_reset_game` | Run in SQL Editor |
| `migration-017-scenario-builder.sql` | `start_game(p_room_id, p_roles JSONB)` | Run in SQL Editor |
| `migration-018-tribunal.sql` | `day_step`, `current_accused_id`, tribunal RPCs | Run in SQL Editor |
| `migration-019-game-over-delay.sql` | `game_state.winner`, `check_game_over`, `host_end_game` | Run in SQL Editor |
| `migration-020-expansion-lot1.sql` | Mayor/Prince/Tanner/Lycan cards, mechanics, tanner win | Apply via CLI (db push) |
| `migration-021-fix-role-constraint.sql` | Fix `players_role_check` constraint to include new roles | Apply via CLI (db push) |
| `20260701130300_day_step_announcement.sql` | `resolve_night` sets `day_step = 'announcement'` | Apply via CLI (db push) |

**Important**: All migrations have `CREATE OR REPLACE FUNCTION` blocks removed (neutered). The actual DB schema is maintained through Supabase SQL Editor. These files are reference copies only.

---

## Business Rules

### Win Condition
- Checked by `check_game_over()` trigger after each death.
- **Wolves win** when `v_wolves >= v_non_wolves` (where `v_non_wolves` excludes werewolves AND moderators).
- **Villagers win** when no werewolves remain alive.
- Winner is stored in `game_state.winner`; game only visually ends when host clicks "Finalizar Partida" (`host_end_game` RPC).

### Moderator (Master)
- Not a player — cannot be targeted, cannot vote, cannot die.
- Excluded from:
  - `v_non_wolves` count (win condition)
  - Accusation list in Tribunal
  - `HostRolePanel` role list
  - Night-role counts (`availableNightRoles`)
- Present only in player list for lobby management.

### Cause of Death
- Stored in `last_event` column on `players` table.
- Visible only to host via `DayAnnouncement isHost` prop.
- Possible values: `lobisomem` (wolf kill), `veneno` (witch poison), `linchamento` (tribunal execution).

### Timer
- Uses `clientStartRef` (not server `timer_started_at`) to avoid clock skew.
- Single reusable `VoteTimerPanel` component; host starts/stops/resets as needed.

### Night Actions
- Each night role can act once per night step.
- `execute_night_action` RPC validates role, tracks witch saves/poisons via flags, uses `ON CONFLICT DO NOTHING`.
- Witch: can save the first wolf kill (`save`) and/or poison a player (`poison`). Each usable only once per game.

### Tribunal Day Phase
1. **Accusation**: Host selects a player to accuse (from alive, non-moderator players).
2. **Trial**: Host starts timer; players discuss.
3. **Voting**: Timer stops; players vote SIM (lynch) or NÃO (absolve).
4. **Reveal**: Votes tallied; host executes or absolves the accused.
   - Majority SIM → accused dies (linchamento); `check_game_over` fires.
   - Majority NÃO or tie → accused absolved.
5. Host advances back to night (`host_day_to_night`).

### Reset
- When `rooms.status` changes to `'waiting'`, `trg_reset_game` trigger fires automatically.
- Resets: `players.is_alive`, `players.has_viewed_card`, `players.role`; deletes `votes`, `night_actions`, `game_state`.

---

## Key Decisions (Full)

1. **SQL migration files = reference copies** — `CREATE OR REPLACE FUNCTION` blocks removed to prevent deploy-time overwrite. All actual DB changes go through Supabase SQL Editor.

2. **`actedRoles.has('seer')` removed** instead of `setTimeout` — the `nightStep !== 'seer'` check already dismisses the seer panel when host advances. Simpler, no race condition.

3. **Timer uses `clientStartRef`** (`timer-display.tsx`) rather than modifying the `start_timer` RPC — avoids any SQL changes and eliminates clock skew from server-client time differences.

4. **Moderator filtered frontend-only** via `filter(r.role !== 'moderator')` — simplest approach; no backend changes needed to exclude the master from gameplay.

5. **DB trigger `trg_reset_game`** auto-resets on `rooms.status → 'waiting'` — fires automatically, no frontend logic needed for clean state after returning to lobby.

6. **Scenario Builder** replaces hardcoded role distribution — host chooses exact card composition per match using +/- UI with validation.

7. **Game over via `game_state.winner`** instead of immediate `rooms.status` change — lets death events and animations render before host ends the match manually.

8. **Cause of death hidden from non-host** — players see only who died; host sees the reason (`DayAnnouncement isHost` prop + `last_event`).

9. **Single reusable tribunal timer** (`VoteTimerPanel`) instead of 3 fixed timers — host starts/stops/resets as needed per trial.

10. **Night buttons dynamically filtered** — only roles present in the current game scenario appear as wake-up buttons, determined by querying `players` table at runtime.

11. **`rooms.status` is `TEXT`** (originally `VARCHAR(20)`) — fixed because `finished_villagers_win` (21 chars) silently broke game over logic.
