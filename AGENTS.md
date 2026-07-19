<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

## Pre-flight check
**No início de cada sessão ou tarefa, verifique se a Supabase CLI está instalada e atualizada. Se não estiver, instale/atualize antes de rodar qualquer migração ou código.**

## Documentation imperative
**Before any change**: read `docs/architecture.md` to understand the full context, business rules, and existing patterns.
**Before every commit**: update `docs/architecture.md` with what changed (new feature, bugfix, refactor — include commit hash, rationale, files touched).

## Deployment rules (SEMPRE SEGUIR)
1. **Mudanças no banco**: criar migration SQL em `supabase/migrations/` com timestamp e rodar `supabase db push --linked`.
2. **Antes de commitar**: atualizar `docs/architecture.md` com o que mudou.
3. **Commit + push**: commitar tudo e dar push pro GitHub.
4. **Deploy na Vercel é automático** — não precisa fazer nada após o push (não fazer redeploy manual).

## Goal
Ship a complete, production-ready Werewolf game with QoL improvements, Scenario Builder, and Tribunal day-phase system.

## Key Decisions (condensed)
- **`actedRoles.has('seer')` removed** instead of `setTimeout` — nightStep already dismisses panel.
- **Timer uses `clientStartRef`** instead of modifying RPC — avoids SQL changes.
- **Moderator filtered frontend-only** (`filter(r.role !== 'moderator')`) — simplest approach.
- **DB trigger `trg_reset_game`** auto-resets on `rooms.status → 'waiting'` — no frontend logic needed.
- **Scenario Builder** replaces hardcoded role distribution — host chooses exact composition.
- **Game over via `game_state.winner`** — death events render before host ends match.
- **Cause of death hidden from non-host** — `DayAnnouncement isHost` prop.
- **Single reusable tribunal timer** instead of 3 fixed timers.

## Critical Context
- **`rooms.status` is `TEXT`** (was `VARCHAR(20)` — broke `finished_villagers_win`).
- **`game_state.winner`** is set by trigger at death; game only visually ends when host calls `host_end_game`.
- **Moderator excluded** from `v_non_wolves` count, accusation list, HostRolePanel, and night-role counts.
- **Night buttons dynamically filtered** — only roles present in scenario appear.
- **Always update `docs/architecture.md`** before committing.

## Relevant Files
- `src/lib/cards.ts` – card catalog with id, name, points, description, team.
- `src/components/scenario-builder.tsx` – host UI in lobby for building game scenario.
- `src/components/flip-card.tsx` – shows description on card back (points hidden).
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
- `src/app/game/[id]/page.tsx` – renders all game phases; game over by `game_state.winner`; Finalizar button for host; dynamic night buttons.
- `src/app/lobby/[id]/page.tsx` – ScenarioBuilder, kick, beforeunload, leavingRef for expulsion guard.
- `src/hooks/use-room.ts` – `GameStateRow` includes `winner`, `day_step`, `current_accused_id`.
- `src/hooks/use-player.ts` – player state polling with Realtime fallback.
