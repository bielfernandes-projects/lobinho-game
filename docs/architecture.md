# Lobinho Game — Architecture & Documentation

## Overview
A real-time multiplayer Werewolf (Lobisomem) party game built with Next.js 16, Supabase (PostgreSQL + Realtime), and Tailwind CSS. Host creates a room, players join, host configures the role scenario, and the classic night/day cycle plays out with a Tribunal day-phase system.

### `<current>` — Wolf consensus inline votes + witch exhausted state + diseased/frenzy DB fix

- **Wolf panel: inline votes on target buttons** — Replaced separate "🗳️ Votos" panel with voter names shown inline on each target button (e.g. `(Você)`, `(Lobo1)`). Removed ~140 lines of old vote panel code. Uses `votesByTarget` Map to group consensus votes by target.
- **Witch panel: "Poções esgotadas" persistent state** — When both potions are used, witch panel now shows "Poções esgotadas — Aguarde a noite passar..." instead of auto-calling `onDone()`. Added `'exhausted'` step type. Witch sees this until host advances nightStep.
- **DB fix: `wolves_frenzy` leak on diseased skip** — `resolve_night` PASSO 0 did early RETURN when `diseased_skip_wolves=true` but did NOT clear `rooms.wolves_frenzy`. If Wolf Cub died before Diseased, frenzy persisted to next night, forcing wolves to pick 2 targets incorrectly. Added `UPDATE rooms SET wolves_frenzy = false WHERE id = p_room_id AND wolves_frenzy = true;` in diseased_skip block.
- **Migration** (`20260720111422_fix_diseased_skip_frenzy_leak.sql`): Recreated `resolve_night` with the one-line fix. Verified deployed function contains the fix.
- **Files**: `src/components/werewolf-panel.tsx`, `src/components/witch-panel.tsx`, `supabase/migrations/20260720111422_fix_diseased_skip_frenzy_leak.sql`, `docs/architecture.md`.

### `<current>` — Wolf consensus voting fix: dead wolves excluded from count
- **Fix: dead wolves counted in consensus UI** — `wolves.length` included dead wolves (from `get_werewolf_teammates`), so the consensus panel was shown even when only 1 wolf remained alive (because dead wolves inflated the count). Changed all UI conditions from `wolves.length` to `aliveWolves.length` (alive wolves only). This ensures:
  - When only 1 wolf is alive, the direct confirm button appears (no consensus needed).
  - When 2+ wolves are alive, the consensus panel shows with vote tracking.
  - Dead wolves no longer appear in the "Seus aliados" list (label updated to "Seus aliados (vivos)").
  - The frenzy section also uses `aliveWolves` for allies display.
- **Cleanup: dead code removed** — Removed ~100 lines of commented-out frenzy consensus analysis in `computeConsensus()` that never returned `hasConsensus: true` (frenzy uses its own UI path with `handleFrenzyConfirm`).
- **All wolf variants included** — `get_werewolf_teammates` returns `werewolf`, `wolf_cub`, `alpha_wolf`, `lone_wolf`. All participate in consensus voting per game rules 4.6 and 7.4. `sorceress` correctly excluded (does not wake with wolves).
- **Files**: `src/components/werewolf-panel.tsx`, `docs/architecture.md`.

### `<current>` — "Ajude o Dev" support footer (commit `10794b5`)
- **Support footer on home page** — New `SupportFooter` component added below the install button on the entry screen:
  - Dark theme card (`bg-neutral-900/60`, border `neutral-800`) consistent with app design.
  - 💛 **Pix link** — opens Nubank cobrar URL (`nubank.com.br/cobrar/33flp/...`) in new tab.
  - 📧 **Email link** — `mailto:` with subject "Sugestão Lobinho" to `gabriel.fernandeshw@gmail.com`.
  - Heart emoji header, "Ajude o Dev" label, short description text.
- **Files**: `src/components/support-footer.tsx` (new), `src/app/page.tsx`, `docs/architecture.md`.

### `<current>` — 5 Playtest Improvements (commit `9b94f56`)
- **Witch doesn't play on Night 1** — Added `turnIndex === 1` guards in 3 places in `page.tsx`:
  - `renderNightPanel()` witch block returns `sleepScreen()` on first night.
  - Both `nextRoleToWake` IIFEs skip witch when `turnIndex === 1`.
  - Host button filter hides witch button on first night.
  - Matches official Werewolf rules: Witch only acts from Night 2 onward.
- **Dead role buttons visible for host** — Removed `.eq('is_alive', true)` from `availableNightRoles` query. Host can now wake dead roles (for confusion/TPA). Dead players still see `sleepScreen()` via the `isAlive` check in `renderNightPanel()`.
- **Binary reveal mode "Apenas Time Vila"** — `getRevealedRoleText` in `reveal.ts` now returns `'Era da Vila'` / `'Não era da Vila'` instead of team-specific labels. `ScenarioBuilder` label updated to "👥 Apenas Time Vila". Removed unused `getRevealedRoleText` import from `scenario-explanation.tsx`.
- **Witch UX when potions already used** — `witch-panel.tsx` rewritten:
  - Both potions used → shows "Poções esgotadas" persistent message (does NOT auto-call `onDone()`; waits for host to advance nightStep).
  - Life potion used → skips save step, goes directly to poison.
  - Death potion used → shows save step, then auto-skips poison.
  - Neither used → normal flow.
  - Added `loaded` state to prevent premature rendering.
- **Wolf consensus voting** — New DB table + RPCs + complete `werewolf-panel.tsx` rewrite:
  - New table `consensus_votes` (PK: room_id + turn_index + voter_id) with RLS.
  - New RPC `upsert_consensus_vote(room_id, target_id)` — SECURITY DEFINER.
  - New RPC `get_wolf_consensus(room_id)` — SECURITY DEFINER, returns voter/target names.
  - Realtime subscription on `consensus_votes` for live vote updates.
  - Confirm button only enables when ALL alive wolves voted for the same target.
  - Frenzy mode unchanged (direct target selection, no consensus — per-wolf).
  - Single wolf mode: direct confirm after voting.
- **Database** (migration `20260719220000_consensus_votes.sql`, applied via CLI, file deleted):
  - `consensus_votes` table with RLS policy `players_can_read_consensus_votes`.
  - New RPCs: `upsert_consensus_vote`, `get_wolf_consensus`.
- **Files**: `src/app/game/[id]/page.tsx`, `src/lib/reveal.ts`, `src/components/scenario-builder.tsx`, `src/components/scenario-explanation.tsx`, `src/components/witch-panel.tsx`, `src/components/werewolf-panel.tsx`, `docs/architecture.md`.

### `<current>` — Night button pulse animation (commit `386b45b`)
- **Pulse animation on night controls** — Host's night buttons now pulse with `animate-pulse` to guide the sequence:
  - When `nightStep === 'sleeping'` and there's a `nextRoleToWake`, the button for that role pulses (e.g., "🐺 Acordar Lobos").
  - When `nightStep !== 'sleeping'` (a role is active), the "😴 Todos Dormindo" button pulses, prompting the host to return to sleeping state.
  - `nextRoleToWake` computation extracted from IIFE into accessible scope for both text display and button styling.
- **Scenario explanation count display** — Role count now always appears next to the name as `Name (N)` (e.g., "Lobisomem (2)", "Seer (1)") instead of the conditional `×N` badge.
- **Files**: `src/app/game/[id]/page.tsx`, `src/components/scenario-explanation.tsx`, `docs/architecture.md`.

### `<current>` — Crash prevention + scenario explanation RLS fix (commit `97d79fd`)
- **Fix: Scenario Explanation vazia para jogadores** — RLS impedia jogadores não-host de lerem a coluna `role` na tabela `players`. Query direta `from('players').select('id, role, is_host')` retornava `role = null` para não-hosts, causando "Nenhum papel encontrado". Solução: nova RPC `get_scenario_composition(p_room_id)` (`SECURITY DEFINER`) retorna `{role_id, player_count}` agregado (sem expor quem tem qual papel). `ScenarioExplanation` agora usa a RPC em vez de query direta.
- **Fix: Vercel crash "This page couldn't load"** — Múltiplas causas de unhandled promise rejection:
  - `error.tsx` + `global-error.tsx` criados (error boundaries) — erros agora são contidos e mostram fallback "Algo deu errado".
  - 4 polling useEffects no `page.tsx` (night roles, winner players, vote count, night actions) envoltos em try/catch.
  - 15+ componentes (seer-panel, witch-panel, bodyguard-panel, aura-seer-panel, priest-panel, doppelganger-panel, hunter-retaliate-panel, marksman-panel, sorceress-panel, tribunal-panel, tribunal-reveal, tribunal-voting, cupid-panel, cult-leader-panel, mason-panel) convertidos de `.then()` sem tratamento para async IIFE com try/catch.
  - `setResolvedActions`/`setActedRoles` movidos do corpo do render para `useEffect` (causavam setState durante render).
  - `sorceress-panel`: `supabase` removido das deps do useEffect (causava re-renders infinitos).
  - `useCurrentPlayer`: `.catch()` adicionado no `.then()` do `load()`.
- **Database** (migration via CLI, arquivo deletado):
  - Nova RPC `get_scenario_composition(p_room_id UUID)` — `SECURITY DEFINER`, retorna composição do cenário (roles + contagem) sem expor atribuições individuais.
- **Files**: `src/app/error.tsx`, `src/app/global-error.tsx`, `src/app/game/[id]/page.tsx`, `src/components/scenario-explanation.tsx`, `src/components/seer-panel.tsx`, `src/components/witch-panel.tsx`, `src/components/bodyguard-panel.tsx`, `src/components/aura-seer-panel.tsx`, `src/components/priest-panel.tsx`, `src/components/doppelganger-panel.tsx`, `src/components/hunter-retaliate-panel.tsx`, `src/components/marksman-panel.tsx`, `src/components/sorceress-panel.tsx`, `src/components/tribunal-panel.tsx`, `src/components/tribunal-reveal.tsx`, `src/components/tribunal-voting.tsx`, `src/components/cupid-panel.tsx`, `src/components/cult-leader-panel.tsx`, `src/components/mason-panel.tsx`, `src/hooks/use-player.ts`, `docs/architecture.md`.

### `<current>` — Critical audit fixes: host visibility, rule corrections, constraint fix, collapsible strikes
- **Fix: host aparecia na lista de jogadores** — `start_game` agora seta `role = 'moderator'` no host. `HostRolePanel` filtra por `is_host` em vez de `role !== 'moderator'`. `fetch_roles_for_host` agora retorna `is_host` no JSON.
- **Fix: constraint `game_state_current_phase_check`** — Adicionado `'scenario_reveal'` à constraint CHECK (antes era `card_reveal, night, day, vote, ended`). Sem isso, `start_game` falhava com erro de constraint.
- **Fix: botão avançar para host na scenario_reveal** — Dashboard do host agora renderiza `ScenarioExplanation` com botões "Iniciar Jogo" e "Voltar ao Lobby" quando `phase = 'scenario_reveal'`. Antes, o host ficava sem ações nessa fase.
- **Fix: strikes expansível** — `StrikePanel` agora tem toggle ▼/▲ (colapsa por padrão), consistente com o "Painel do Mestre".
- **Fix: Cursed sobrevive ao linchamento** — `host_execute_accused` e `resolve_day_vote` agora convertem Cursed → werewolf **sem matar**. Avança direto para noite. Regra 5.6/7.3: "When LYNCHED: does NOT die, role changes to werewolf."
- **Fix: Prince imunidade one-shot** — Nova coluna `game_state.prince_revealed BOOLEAN DEFAULT false`. Na 1ª vez que Príncipe é linchado, revela identidade e sobrevive. Nas vezes seguintes, morre normalmente. Regra 5.4/7.3.
- **Fix: Squire só é promovido quando Prince MORRE** — Removida promoção do bloco de Prince (que sobrevive). Squire agora só é promovido quando Prince morre via soulmate. Regra 7.7.
- **Fix: Mayor voto x2 no backend** — `resolve_day_vote` agora faz `SUM(CASE WHEN role='mayor' THEN 2 ELSE 1)` em vez de `COUNT(*)`. Regra 5.3.
- **Fix: `availableNightRoles` filtra mortos** — Adicionado `.eq('is_alive', true)` na query. Botões de acordar papéis mortos não aparecem mais.
- **Fix: `resolvedActions` reset no turno** — Agora é resetado quando `turnIndex` muda, evitando botões desabilitados indevidamente.
- **Fix: Cursed banner usa `player.id`** — Evita falsos positivos com nomes duplicados.
- **Fix: Pacifist points** — Corrigido de `-1` para `+2` em `cards.ts` (conf. regra 7.3).
- **Fix: Sorceress cor** — Corrigido de roxo para vermelho em `ROLE_STYLE` (time wolf).
- **Fix: código duplicado removido** — Bloco morto de `scenario_reveal` para jogadores removido de `page.tsx`.
- **Database** (migrations via CLI, arquivos deletados):
  - `game_state_current_phase_check` inclui `scenario_reveal`.
  - `start_game` seta `role = 'moderator'` no host.
  - `fetch_roles_for_host` retorna `is_host`.
  - `game_state.prince_revealed BOOLEAN DEFAULT false`.
  - `host_execute_accused` e `resolve_day_vote` reescritos com Cursed survival, Prince one-shot, Squire-only-on-death, Mayor x2.
- **Files**: `src/app/game/[id]/page.tsx`, `src/components/host-role-panel.tsx`, `src/components/strike-panel.tsx`, `src/lib/cards.ts`, `docs/architecture.md`.

### `<current-1>` — QoL based on real testing: stale screens fix, custom timer, strikes, scenario explanation, PWA
- **Stale screens fix** — Supabase Realtime agora com `heartbeatIntervalMs: 10000` (padrão era 30s) e `re-subscribe` automático em `useGameState`/`useCurrentPlayer`/`useRoomPlayers`. `useRoomPlayers` agora tem Realtime no `players` (mortes/role changes em tempo real). Polling do `useGameState` reduzido de 5s→2s. `useCurrentPlayer` 10s→5s. Reconnect silencioso após 3s em caso de `CHANNEL_ERROR`/`TIMED_OUT`/`CLOSED`.
- **Free-form debate time** — `HostTimerControls` agora tem `<input type="number">` (0.5–30 min, decimais) substituindo os 5 botões de preset. `VoteTimerPanel` também aceita input (0.5–10 min).
- **Day timer persistente** — Timer do dia agora aparece em TODAS as sub-fases do dia (discussion, trial, voting, reveal) tanto para host quanto para jogadores. O host pode pausar/retomar manualmente — a transição entre fases não pausa o cronômetro.
- **Strike system (x/3 + insta-kill)** — Nova coluna `strikes INT` em `players` (CHECK 0..3). RPCs `add_strike`, `remove_strike`, `insta_kill` (host only). Componente `StrikePanel` no dashboard do host lista jogadores vivos com contador 0/3 → 3/3. Em 3/3, modal de confirmação ☠️ aparece. Após confirmação, `insta_kill` mata o jogador e dispara `check_game_over`. Strikes resetam em `back_to_lobby` via `trg_reset_game`.
- **Scenario explanation screen** — Nova fase `scenario_reveal` entre lobby e `card_reveal`. Componente `ScenarioExplanation` lista todos os papéis do cenário com nome (EN + PT), descrição, time, contagem ×N. Host vê botões "▶ Iniciar Jogo" (→ `card_reveal` via `advance_to_card_reveal`) e "↩ Voltar ao Lobby" (via `back_to_lobby_from_scenario`). Jogadores veem lista (read-only) e aguardam. `start_game` agora inicia em `scenario_reveal` em vez de `card_reveal`.
- **PWA icons melhorados** — Manifest agora referencia PNGs (192px/512px) além de SVGs, e versões maskable. `layout.tsx` agora inclui `appleWebApp.capable: true` e `apple-touch-icon` link via metadata `icons.apple`. `InstallButton` agora detecta iOS (Safari não dispara `beforeinstallprompt`) e mostra modal com instruções "Compartilhar → Adicionar à Tela de Início". Em modo standalone (já instalado), botão não aparece.
- **Database** (`20260719180639_strikes.sql`, `20260719190000_scenario_explanation.sql`, `20260719191000_start_game_scenario_reveal.sql`):
  - `players.strikes INT NOT NULL DEFAULT 0 CHECK (strikes BETWEEN 0 AND 3)`
  - New RPCs: `add_strike`, `remove_strike`, `insta_kill`, `advance_to_card_reveal`, `back_to_lobby_from_scenario`
  - Updated RPC: `start_game` agora cria `game_state` com `current_phase = 'scenario_reveal'`
  - Updated constraint: `night_actions_action_type_check` agora inclui `'insta_kill'`
  - `trg_reset_game` resetada para limpar `strikes` ao voltar para `waiting`
- **Files**: `src/lib/supabase/client.ts`, `src/hooks/use-room.ts`, `src/hooks/use-player.ts`, `src/components/host-timer-controls.tsx`, `src/components/vote-timer-panel.tsx`, `src/components/strike-panel.tsx`, `src/components/scenario-explanation.tsx`, `src/components/install-button.tsx`, `src/app/game/[id]/page.tsx`, `src/app/layout.tsx`, `public/manifest.json`, `public/icon-192x192.png`, `public/icon-512x512.png`, `public/icon-maskable-192x192.png`, `public/icon-maskable-512x512.png`, `supabase/migrations/20260719180639_strikes.sql`, `supabase/migrations/20260719190000_scenario_explanation.sql`, `supabase/migrations/20260719191000_start_game_scenario_reveal.sql`, `docs/architecture.md`.

### `<current>` — Diseased, Cursed, Doppelgänger: 3 new roles (official rulebook)
- **3 new roles** (verified against official PDFs in `game_archives/`):
  - **Diseased (Doente)** `diseased` (+3 pts, village): When wolves kill the Diseased, wolves' next night kill is skipped (`game_state.diseased_skip_wolves = true`). Triggered in `resolve_night` when victim has `role = 'diseased'`. Flag is consumed next night (same function checks and clears it before wolves resolve).
  - **Cursed (Amaldiçoado)** `cursed` (-3 pts, village→wolf): When attacked by wolves, the Cursed is NOT killed — instead their role is updated to `werewolf` and they join the wolf team. When LYNCHED, same conversion but Cursed SURVIVES (does not die). Banner shown to player via `cursed_converted` event data. Seer sees as Villager until conversion. Logic in `resolve_night`, `host_execute_accused`, `resolve_day_vote`.
  - **Doppelgänger (Doppelgänger)** `doppelganger` (-2 pts, village→target's team): Night 1 only — picks a target via `doppelganger_select` RPC. When target dies (any cause), Doppelgänger secretly becomes target's role. Until then, they're on Village team and Seer sees as Villager. Logic in `resolve_night` (copies role on target death) and `host_execute_accused` / `resolve_day_vote` (same copy on lynch). `players.doppelganger_target_id` column tracks the bond.
- **Database** (`20260719200000_diseased_cursed_doppelganger.sql`):
  - `game_state` gained `diseased_skip_wolves BOOLEAN DEFAULT FALSE`.
  - `players` gained `doppelganger_target_id UUID REFERENCES players(id)`.
  - `players_role_check` updated with `diseased`, `cursed`, `doppelganger`.
  - `night_actions_action_type_check` updated with `doppelganger_select`.
  - New RPC: `doppelganger_select(p_room_id, p_target_id)`.
  - Updated RPCs: `resolve_night` (diseased skip, cursed conversion, doppelgänger copy), `host_execute_accused` (cursed on lynch, doppelgänger copy), `resolve_day_vote` (cursed on lynch, doppelgänger copy).
- **Frontend**:
  - `src/lib/cards.ts`: entries for `diseased`, `cursed`, `doppelganger` in `CARD_CATALOG`, `ROLE_STYLE`, `ROLE_LABEL`, `ROLE_TRANSLATION`.
  - `src/components/doppelganger-panel.tsx`: Night 1 target selection panel (like cupid — only appears night 1).
  - `src/app/game/[id]/page.tsx`: `WAKE_ORDER` + `doppelganger`; `STEP_TO_ACTION_TYPES` + `doppelganger: ['doppelganger_select']`; `NIGHT_ROLE_LABELS` + `doppelganger`; `availableNightRoles` query includes `doppelganger`; host button for doppelganger (night 1 only); `renderNightPanel()` block for doppelganger; `showCursedBanner` state + banner JSX.
  - `src/components/host-action-log.tsx`: `doppelganger_select: '🎭 selecionou'` label.
- **Files**: `supabase/migrations/20260719200000_diseased_cursed_doppelganger.sql`, `src/lib/cards.ts`, `src/components/doppelganger-panel.tsx`, `src/app/game/[id]/page.tsx`, `src/components/host-action-log.tsx`, `docs/architecture.md`.

### `<current>` — Hunter, Squire, Marksman: 3 new village roles
- **3 new VILLAGE roles** (no new win conditions):
  - **Hunter (Caçador)** `hunter` (+2 pts): When killed (lynch or night), enters `hunter_pending` state. Dead Hunter chooses a revenge target or skips. Retaliation kills the target instantly. Triggered via new `day_step = 'hunter_reveal'` (lynch path) or during `announcement` (night death path).
  - **Squire (Escudeiro)** `squire` (+2 pts): Passive role. When the Prince dies by any cause, the alive Squire's role is updated to `prince` (inheriting the protection). Logic lives in the same death-resolution RPCs (`resolve_night`, `host_execute_accused`, `resolve_day_vote`).
  - **Marksman (Atirador)** `marksman` (+2 pts): Unique DAY action. During `day_step = 'discussion'`, the Marksman can shoot one player via `marksman_shoot` RPC. One-use (`has_used_power`).
- **Database** (`20260719120000_hunter_squire_marksman.sql`):
  - `game_state` gained `hunter_pending BOOLEAN DEFAULT FALSE` and `hunter_id UUID DEFAULT NULL`.
  - `players_role_check` updated with `hunter`, `squire`, `marksman`.
  - `night_actions_action_type_check` updated with `hunter_shot`.
  - New RPCs: `hunter_retaliate`, `advance_after_hunter`, `marksman_shoot`.
  - Updated RPCs: `resolve_night` (Squire promotion on wolf kill), `host_execute_accused` (Squire promotion on lynch), `resolve_day_vote` (Squire promotion on lynch), `check_game_over` + `trg_check_game_over` (Hunter pending gate: game doesn't end while Hunter is pending).
  - New `day_step`: `hunter_reveal` — sits between `lynch` and `lynch_reveal`; host waits for Hunter to act, then advances.
- **Frontend**:
  - `src/lib/cards.ts`: 3 new entries in `CARD_CATALOG`, `ROLE_STYLE`, `ROLE_LABEL`, `ROLE_TRANSLATION`.
  - `src/hooks/use-room.ts`: `GameStateRow` includes `hunter_pending` and `hunter_id`; `useGameState` selects both columns.
  - `src/components/hunter-retaliate-panel.tsx`: dead Hunter picks revenge target or skips.
  - `src/components/marksman-panel.tsx`: day-action button + modal for target selection.
  - `src/app/game/[id]/page.tsx`: dead-player bypass for pending Hunter; `HunterRetaliatePanel` rendered during `announcement` (night death) and `hunter_reveal` (lynch death); `MarksmanPanel` rendered during `discussion` for alive Marksman with unused power; host phase display includes `hunter_reveal`; host controls include advance button for `hunter_reveal`.
  - `src/components/host-action-log.tsx`: `hunter_shot: '🔫 atirou em'` label added.
- **Files**: `supabase/migrations/20260719120000_hunter_squire_marksman.sql`, `src/lib/cards.ts`, `src/hooks/use-room.ts`, `src/components/hunter-retaliate-panel.tsx`, `src/components/marksman-panel.tsx`, `src/app/game/[id]/page.tsx`, `src/components/host-action-log.tsx`, `docs/architecture.md`.

### `<current>` — Bugfix: Hunter/Squire/Marksman critical fixes (migration `20260719171231`)
- **Critical**: `page.tsx` called `advance_after_host` instead of `advance_after_hunter` — host advance button was broken. Fixed.
- **Critical**: `marksman_shoot` RPC lacked self-target check. Added `IF p_target_id = v_marksman_id THEN RAISE EXCEPTION`.
- **Critical**: Hunter skip button called `advance_after_hunter` (host-only RPC). Created new `hunter_skip` RPC (non-host) that clears `hunter_pending` without changing `day_step`. Updated `hunter-retaliate-panel.tsx` to call it.
- **High**: `resolve_night` never called `check_game_over()` — could leave `winner` unset. Added call.
- **High**: Dead code removed from `host_execute_accused` and `resolve_day_vote` (Squire promotion after Prince early-return was unreachable).
- **High**: Dead player bypass race condition fixed — `isHunterPending` computed before `DeadPlayerScreen` check to prevent brief flash.
- **Medium**: `marksman_panel.tsx` modal stays open on error; fixed to close on error. Typo "usedo" → "usado".
- **Medium**: Squire promotion deferred until after all deaths processed in `resolve_night`, `host_execute_accused`, `resolve_day_vote` — fixes simultaneous Prince+Squire death (frenzy).
- **Medium**: `resolve_day_vote` return JSON now includes `hunter_pending` (consistency with `host_execute_accused`).
- **Files**: `supabase/migrations/20260719171231_bugfix_hunter_squire_marksman.sql`, `src/app/game/[id]/page.tsx`, `src/components/hunter-retaliate-panel.tsx`, `src/components/marksman-panel.tsx`, `docs/architecture.md`.

### `<current>` — Player limits 6-78, nomes em inglês, player list /78
- **Mínimo de jogadores 6**: `scenario-builder.tsx` validação e mensagem de erro alteradas de 4 para 6.
- **Máximo de jogadores 78** (77 jogadores + 1 mestre): `max_players: 78` na criação da sala (`page.tsx`); `player-list.tsx` mostra `{total}/78`; ScenarioBuilder valida `playerCount <= 77` (exclui host).
- **Nomes dos personagens em inglês**: `CARD_CATALOG[*].name` traduzido para inglês (ex: "Werewolf", "Seer", "Witch"). Novo mapa `ROLE_TRANSLATION` mantém traduções em português para tooltip. `ROLE_LABEL` e `NIGHT_ROLE_LABELS` continuam em português.
- **RoleInfoModal bilíngue**: Título mostra nome em inglês, abaixo entre parênteses a tradução em português (ex: "Werewolf (Lobisomem)").
- **Files**: `src/app/page.tsx`, `src/components/player-list.tsx`, `src/components/scenario-builder.tsx`, `src/lib/cards.ts`, `src/components/role-info-modal.tsx`, `docs/architecture.md`.

### `<current>` — 3 ScenarioBuilder QoL: tooltip sem pontos, revealMode padrão, reset
- **RoleInfoModal sem pontos**: Removida linha "Pontos: +X" do modal de informações de papel (`src/components/role-info-modal.tsx`). Pontos continuam visíveis apenas ao lado do nome no ScenarioBuilder.
- **RevealMode padrão `'team'`**: `useState<RevealMode>('total')` → `useState<RevealMode>('team')` em `src/components/scenario-builder.tsx`. Novas partidas começam com "Apenas o Time" selecionado.
- **Botão Resetar Cenário**: Novo botão full-width abaixo do termômetro no ScenarioBuilder — zera todos os `counts` de volta a 0 e limpa o localStorage.
- **Files**: `src/components/role-info-modal.tsx`, `src/components/scenario-builder.tsx`, `docs/architecture.md`.

### `<current>` — 4 Fixes Críticos: lone_wolf_win, HostRolePanel polling, redução de polling, erro 406
- **Fix 1 — `host_end_game` não reconhecia `lone_wolf_win`**: A função caía no `ELSE` e levantava `Nenhum vencedor definido`. Adicionado `ELSIF v_winner = 'lone_wolf_win' THEN UPDATE rooms SET status = 'finished_lone_wolf_win'`.
- **Fix 2 — `HostRolePanel` sem polling fallback**: O painel do mestre dependia só de Realtime para atualizar `has_viewed_card`. Adicionado `setInterval(fetchPlayers, 4000)` como fallback em `src/components/host-role-panel.tsx`.
- **Fix 3 — Redução do excesso de polling**:
  - `useGameState`: 3s → 5s (`src/hooks/use-room.ts`).
  - `useCurrentPlayer`: 5s → 10s (`src/hooks/use-player.ts`).
  - `useRoomPlayers`: 2s → 4s (`src/hooks/use-room.ts`).
  - `resolvedActions`/`voteCount` polling em `src/app/game/[id]/page.tsx`: 2s → 4s.
  - `PollVoteCount` em `src/components/tribunal-panel.tsx`: 2s → 4s.
  - `host-controls.tsx` (resolve night wolves / resolve vote): 2s → 4s.
- **Fix 4 — Erro 406 ao voltar pro lobby**: Quando o host volta pro lobby, `trg_reset_game` deleta `game_state`. O polling continuava e recebia `PGRST116`. `useGameState` agora trata `error.code === 'PGRST116'` silenciosamente e não loga como erro.
- **Files**: `src/hooks/use-room.ts`, `src/hooks/use-player.ts`, `src/components/host-role-panel.tsx`, `src/app/game/[id]/page.tsx`, `src/components/tribunal-panel.tsx`, `src/components/host-controls.tsx`, `docs/architecture.md`.

### `<current-1>` — Fix Realtime instável: polling fallback + player_profiles sem SECURITY DEFINER
- **Root cause**: O WebSocket do Supabase estava sendo interrompido pelo Cloudflare (`__cf_bm` rejeitado). Como `useGameState` e `useCurrentPlayer` dependiam 100% de Realtime, o estado congelava e o jogo parava de responder.
- **Fix frontend**:
  - `src/hooks/use-room.ts` → `useGameState`: adicionado `setInterval(load, 3000)` como fallback de polling. Se Realtime funcionar, o polling é redundante; se cair, o estado continua atualizando.
  - `src/hooks/use-player.ts` → `useCurrentPlayer`: adicionado `setInterval(load, 5000)` como fallback. Garante que morte, infecção Alfa e outros status próprios cheguem mesmo com WebSocket off.
- **Fix banco**:
  - `player_profiles` estava como `SECURITY DEFINER` (alerta crítico do Advisor). Recriada via CLI como view padrão (`SECURITY INVOKER`) com RLS desabilitado: `relrowsecurity = false`.
  - Comando: `DROP VIEW IF EXISTS public.player_profiles; CREATE VIEW public.player_profiles AS SELECT id, room_id, name, is_alive, is_host, has_viewed_card, user_id, created_at FROM public.players; ALTER VIEW public.player_profiles SET (security_barrier = false);`
- **Vercel**: Redeploy manual necessário (CLI sem credenciais). Use o dashboard com "Use existing Build Cache" DESATIVADO.
- **Variáveis de ambiente a conferir no dashboard da Vercel**:
  - `NEXT_PUBLIC_SUPABASE_URL=https://bamygdefokpdrzdofccu.supabase.co`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbG...ktHA`
  - `SUPABASE_SERVICE_ROLE_KEY=eyJhbG...Eqo`
- **Files**: `src/hooks/use-room.ts`, `src/hooks/use-player.ts`, `docs/architecture.md`.

### `<current-1>` — Fix jogo quebrado: drop start_game duplicada, limpeza RPC órfã, verificação de funções/constraints
- **Causa raiz do jogo quebrado**: A função `start_game(p_room_id UUID)` (versão antiga sem `p_roles`) coexistia com `start_game(p_room_id UUID, p_roles JSONB)`. A API REST do Supabase falhava ao resolver qual chamar, então `Iniciar Jogo` não funcionava.
  - Ação: `DROP FUNCTION IF EXISTS public.start_game(UUID);`
  - Verificação: só restou `start_game | p_room_id uuid, p_roles jsonb`.
- **Limpeza RPC órfã**: `DROP FUNCTION IF EXISTS public.get_room_profiles(UUID);` — criada no rollback do RLS fix e nunca chamada pelo frontend.
- **Verificações de integridade** (todas passaram):
  - `night_actions_action_type_check`: contém `witch_skip` e `sorceress_search`.
  - `check_game_over` e `trg_check_game_over`: contêm `v_alive_count <= 2` (paridade do Lobo Solitário).
  - `execute_night_action`: Seer detecta `('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'lycan')`; Padre valida `v_used_power` e seta `has_used_power = true WHERE id = v_player_id`.
  - `resolve_night`: deduplica vítimas com `IS DISTINCT FROM`; NÃO atualiza `wolves_frenzy` em `game_state` (apenas em `rooms`).
  - `get_werewolf_teammates`: usa `p.name::text` para evitar mismatch de tipo.
- **Build local**: `npm run build` passou.
- **Vercel**: Redeploy manual necessário (CLI sem credenciais). Use o dashboard com "Use existing Build Cache" DESATIVADO.
- **Files**: `docs/architecture.md`.

### `<current-1>` — Hotfixes: Lobo Solitário paridade + constraint witch_skip (commit `fe84b05`)
- **Bug 1 — Lobo Solitário paridade**: `check_game_over` e `trg_check_game_over` impediam `villagers_win` quando Solitário vivo, mas não declaravam `lone_wolf_win` na paridade (Solitário + 1 outro = 2 vivos, sem lobos de time). Adicionado `IF v_alive_count <= 2 THEN ... lone_wolf_win` no bloco `v_wolves = 0` de ambas as funções. Agora: `v_wolves = 0` + Solitário vivo + `<= 2` vivos → `lone_wolf_win`; `> 2` vivos → jogo continua.
- **Bug 2 — Constraint `night_actions_action_type_check` sem `witch_skip`**: A RPC `execute_night_action` já tinha o branch `witch_skip` mas a constraint CHECK da tabela `night_actions` não incluía o valor. Resultado: "deixar morrer" na bruxa causava erro `violates check constraint`. Corrigido via SQL Editor.
- **Bug 3 — Feiticeira sem resultado**: Removida guarda `actedRoles.has('sorceress')` do `renderNightPanel`. Painel agora fica visível com o resultado até o host avançar o `nightStep`.
- **Bug 4 — Maçons na ordem de acordar**: `nextRoleToWake` usava `availableNightRoles.has('masons')` (plural) em vez de `'mason'` (singular). Criado bloco especial com mapeamento correto.
- **Files**: SQL Editor (`check_game_over`, `trg_check_game_over`, constraint `night_actions`), `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current-1>` — Lote 5A: Maçom, Pacifista, Idiota, Feiticeira
- **Novas cartas** (`src/lib/cards.ts`): `mason` (🧱 Maçom, +2 pts, vila), `pacifist` (🕊️ Pacifista, -1 pt, vila), `idiot` (🤪 Idiota, +2 pts, vila), `sorceress` (🔮 Feiticeira, -3 pts, lobo/time lobo).
- **Banco** (aplicado via SQL Editor):
  - `players_role_check` e `night_actions_action_type_check` atualizados para aceitar `mason`, `pacifist`, `idiot`, `sorceress`, `sorceress_search`, `mason_recognition`.
  - Nova RPC `get_masons(p_room_id UUID)` retorna todos os jogadores vivos com role `mason`.
  - `execute_night_action`: novo branch `sorceress_search` retorna `{is_seer: BOOLEAN}` quando o alvo é `seer`; `check_game_over` e `trg_check_game_over` contam `sorceress` como lobo no time dos lobos.
- **Ordem noturna**: `masons` (apenas 1ª noite) → `cupid` → `priest` → `bodyguard` → `wolves` → `witch` → `seer` → `aura_seer` → `sorceress` → `cult_leader`.
- **Frontend**:
  - `src/components/mason-panel.tsx`: mostra os outros Maçons vivos na 1ª noite.
  - `src/components/sorceress-panel.tsx`: permite à Feiticeira procurar pela Vidente a cada noite.
  - `src/app/game/[id]/page.tsx`: `WAKE_ORDER`, `STEP_TO_ACTION_TYPES`, `NIGHT_ROLE_LABELS`, botões do host e `renderNightPanel` atualizados para `masons` e `sorceress`.
  - `src/components/tribunal-voting.tsx`: `pacifist` vota automaticamente `no` (absolvição); `idiot` vota automaticamente `yes` (linchamento).
  - `src/components/host-action-log.tsx`: novos labels `sorceress_search` e `mason_recognition`.
- **Files**: `src/lib/cards.ts`, `src/components/mason-panel.tsx`, `src/components/sorceress-panel.tsx`, `src/app/game/[id]/page.tsx`, `src/components/tribunal-voting.tsx`, `src/components/host-action-log.tsx`, `docs/architecture.md`.

### `<current-1>` — 3 Correções Finais: Witch Dimming/Skip, Vítimas Duplicadas, Lone Wolf
- **Bruxa pular e aparecer no histórico**: nova ação `witch_skip` inserida em `night_actions` quando a bruxa pula save ou poison. `execute_night_action` ganhou branch `witch_skip`, a constraint `night_actions_action_type_check` foi atualizada, e `HostActionLog` exibe "🧪 pulou".
- **Bruxa pular e botão apagar**: `src/app/game/[id]/page.tsx` agora marca o `prevStep` em `resolvedActions` sempre que o host avança o `nightStep`. `STEP_TO_ACTION_TYPES` inclui `witch_skip` para o polling detectar o skip. Resolve o dimming para bruxa e qualquer outro papel que pule.
- **Vítimas duplicadas (lobo + veneno no mesmo alvo)**: `resolve_night` agora verifica `v_poison_target_id IS DISTINCT FROM v_wolf_target_id` e `v_wolf_target2_id` antes de adicionar a segunda entrada no array `victims`.
- **Lobo Solitário não encerra jogo prematuramente**: `check_game_over` e `trg_check_game_over` verificam se um `lone_wolf` vivo ainda existe antes de declarar `villagers_win`. O Solitário só vence na Priority 0 (último vivo).
- **Botão "Todos Dormindo" visível**: borda `border-white/30` no controle noturno do host.
- **Files**: `src/app/game/[id]/page.tsx`, `src/components/witch-panel.tsx`, `src/components/host-action-log.tsx`, `docs/architecture.md`.

### `<current-1>` — Correções Finais: RPC type mismatch, Aura Seer, UI Noturna
- **`get_werewolf_teammates` type mismatch**: `execute_night_action` causava erro "Returned type character varying(30) does not match expected type text in column 2" porque `players.name` é `character varying(30)` mas a função declarava `RETURNS TABLE(id UUID, name TEXT)`. Corrigido com cast explícito `p.name::text` no `SELECT`.
- **Aura Seer não marca lobos como "papel especial"**: `execute_night_action` no branch `aura_investigate` agora exclui `wolf_cub`, `alpha_wolf` e `lone_wolf` do conjunto de papéis "comuns", além de `werewolf`.
- **Seer detecta todas as variantes**: `execute_night_action` no branch `seer_investigate` usa `role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'lycan')`.
- **Botão "Todos Dormindo" visível**: borda alterada para `border-white/30` em `src/app/game/[id]/page.tsx` para destacar o botão no controle noturno do host.
- **Dimming fallback da Bruxa**: quando o host avança o `nightStep` de `'witch'` para outro valor, `src/app/game/[id]/page.tsx` agora marca `'witch'` em `resolvedActions`, garantindo que o botão "Acordar Bruxa" escureça mesmo que o polling não capture as ações.
- **Files**: `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current-1>` — 7 Correções: Seer, Padre, WerewolfPanel, Witch Log, Game Over, Dead Code, Migrations
- **Seer detecta todas as variantes de lobo**: `execute_night_action` no banco agora usa `role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'lycan')` na investigação da vidente.
- **Padre 1 uso por jogo**: `execute_night_action` valida `v_used_power` para `priest_bless` e marca `has_used_power = true` no jogador padre.
- **`WerewolfPanel` robusto**: `useEffect` de carregamento de alvos em `src/components/werewolf-panel.tsx` agora captura erros de `player_profiles` e `get_werewolf_teammates`, usa flag `cancelled` para evitar setState em componente desmontado, garante `wolfIds` mesmo com `wolvesData` nulo, e recarrega quando `wolvesFrenzy` muda.
- **`HostActionLog` try/catch**: busca de nomes em `player_profiles` agora está envolvida em `try/catch`, evitando que erro silencioso esconda ações da bruxa no histórico.
- **Game Over `renderEnded()`**: fallback de `winnerType` cobre todos os status `finished_*`; filtros de `wolves_win` e `villagers_win` usam `CARD_CATALOG.team`, excluindo moderador automaticamente.
- **`PollVoteCount` reescrito**: `src/components/tribunal-panel.tsx` usa `useEffect` para polling de 2s em vez de inicializador assíncrono do `useState`.
- **Código morto removido**: deletado `src/lib/types.ts` (tipos desatualizados, nenhum uso real) e removida variável `wolfVictimName2` de `src/app/game/[id]/page.tsx`.
- **Limpeza de migrations**: deletados todos os arquivos `.sql` defasados de `src/lib/sql/` e `supabase/migrations/`. Diretórios preservados com `.gitkeep`. O banco real continua sendo mantido via Supabase SQL Editor.
- **Files**: `src/components/werewolf-panel.tsx`, `src/components/host-action-log.tsx`, `src/app/game/[id]/page.tsx`, `src/components/tribunal-panel.tsx`, `src/hooks/use-player.ts`, `src/lib/types.ts` (deletado), `src/lib/sql/`, `supabase/migrations/`, `docs/architecture.md`.

### `<current-1>` — Fixes do Lote 4 (wolf_cub, alpha_wolf, lone_wolf)
- **Problema**: Fim de jogo prematuro quando `wolf_cub` morria e sobrava `alpha_wolf`; `resolve_night` quebrava ao tentar setar `wolves_frenzy` em `game_state` (coluna existe apenas em `rooms`); tela de game over não filtrava corretamente vencedores.
- **Fix SQL** (migration `supabase/migrations/20260707130000_fix_lote4_wolf_variations.sql`, aplicada via `supabase db push`):
  - `check_game_over` e `trg_check_game_over`: contagem de lobos agora usa `role IN ('werewolf', 'wolf_cub', 'alpha_wolf')`; não-lobos excluem essas 3 roles + `moderator`. `lone_wolf` continua como facção independente (non_wolf).
  - `resolve_night`: removido `wolves_frenzy = false` dos `UPDATE game_state`; limpeza do frenesi mantida apenas em `UPDATE rooms SET wolves_frenzy = false`.
- **Frontend**:
  - `src/app/game/[id]/page.tsx`: fallback de `winnerType` cobre todos os status `finished_*`; filtros de `wolves_win` e `villagers_win` usam `CARD_CATALOG.team` (`wolf` / `village`), excluindo moderador automaticamente.
  - `src/components/werewolf-panel.tsx`: `useEffect` de carregamento de alvos agora depende de `wolvesFrenzy`; `handleFrenzyConfirm` mantém estado em caso de erro para permitir retry.
- **Files**: `supabase/migrations/20260707130000_fix_lote4_wolf_variations.sql`, `src/lib/sql/migration-026-wolf-variations.sql`, `src/app/game/[id]/page.tsx`, `src/components/werewolf-panel.tsx`, `docs/architecture.md`.

### `<current-1>` — Rollback: RLS fix abortado (commit `d18bcd1`)
- **Contexto**: Tentamos corrigir o RLS da view `player_profiles` que impedia jogadores não-host de verem a lista de jogadores nos painéis noturnos.
- **O que foi feito**:
  1. Criada RPC `get_room_profiles` (SECURITY DEFINER) no banco remoto via `supabase db push` (migration `20260703_fix_rls_player_profiles.sql` — deletada do git no rollback mas permanece no banco).
  2. Substituídas todas as chamadas `from('player_profiles')` por `rpc('get_room_profiles')` em 13 arquivos (todos os painéis noturnos + hooks).
- **O que quebrou**: A RPC tinha `WHERE user_id = auth.uid()` ambíguo — a função declara `RETURNS TABLE(..., user_id UUID)`, e o PostgreSQL não conseguia distinguir se `user_id` era a coluna da tabela `players` ou a coluna de output. Resultado: `column reference "user_id" is ambiguous`, exception para TODOS os usuários, player list vazia no lobby.
- **Correção tentada**: `players.user_id = auth.uid()` — aplicada ao banco mas o frontend já estava quebrado.
- **Rollback**: Reset forçado para `d18bcd1` (feat: implementa variacoes de lobo Lote 4). GitHub force-push removeu commits `40348e3`, `a4cfe0b`, `811da79`, `6ada794`, `441b368`.
- **Estado atual do banco** (contém objetos órfãos, inofensivos):
  - `get_room_profiles(p_room_id UUID)` — SECURITY DEFINER RPC, criada pela migration. Não é mais chamada pelo frontend.
  - A migration `20260703_fix_rls_player_profiles.sql` foi aplicada via `supabase db push` mas o arquivo não existe mais no git.
  - A migration anterior `20260702224500_fix_4_issues.sql` permanece no banco por ter sido aplicada via SQL Editor.
- **Aprendizado**: Nunca declarar coluna em `RETURNS TABLE` com mesmo nome de coluna usada no `WHERE` sem qualificar com alias da tabela. Testar RPC com `curl` ANTES de trocar o frontend.
- **Commits perdidos no rollback**:
  - `40348e3` — fix: resolve_night_wolves quebrava na 1ª noite (COUNT DISTINCT target_id retorna 0 para NULL)
  - `a4cfe0b` — fix: resolve_night referenciava game_state.wolves_frenzy (coluna em rooms, nao game_state)
  - `811da79` — fix: 3 bugs do Lote 4 (check_game_over, game over screen, frenesi sem botao)
  - `6ada794` — fix: substitui player_profiles por get_room_profiles RPC em todos os paineis
  - `441b368` — fix: qualifica user_id no RPC (correcao do bug, aplicada ao banco mas perdida no git)

### `<current-1>` — Variações de Lobo (Lote 4)
- **Migration `migration-026-wolf-variations.sql`** (aplicada via `supabase db query --linked`):
  - `rooms.wolves_frenzy BOOLEAN DEFAULT FALSE` — ativado via trigger quando o Filhote de Lobo morre
  - `trigger trg_wolf_cub_death`: AFTER UPDATE OF is_alive, se OLD.role = 'wolf_cub' → `UPDATE rooms SET wolves_frenzy = true`
  - `players_role_check` atualizado: inclui `wolf_cub, lone_wolf, alpha_wolf`
  - `night_actions_action_type_check` atualizado: inclui `alpha_infect`
  - `rooms_status_check` atualizado: inclui `'finished_lone_wolf_win'`
- **Cartas novas** (`src/lib/cards.ts`):
  - `wolf_cub` (🐺 Filhote de Lobo, -8 pts, wolf): morre → lobos em frenesi (2 vítimas na próxima noite)
  - `lone_wolf` (🐺 Lobo Solitário, -5 pts, independent): acorda com lobos, vence só se for o último vivo
  - `alpha_wolf` (🐺 Lobo Alfa, -9 pts, wolf): 1x/jogo pode infectar a vítima (role → 'werewolf') em vez de matar
- **`get_werewolf_teammates`**: agora retorna todos com role IN ('werewolf','wolf_cub','alpha_wolf','lone_wolf')
- **`execute_night_action`**: aceita `alpha_infect` (só alpha_wolf com poder), `werewolf_kill` agora aceita wolf_cub/alpha_wolf/lone_wolf
- **`resolve_night_wolves`**: lê `wolves_frenzy` de rooms; se true, exige EXATAMENTE 2 alvos distintos; se false, mantém 1 (comportamento anterior)
- **`resolve_night`**: 
  - Se `wolves_frenzy = true`: processa ambos os alvos (com saves/proteções), seta `wolves_frenzy = false` ao final
  - Se existir `alpha_infect` para o alvo: não mata, altera role para 'werewolf', marca `has_used_power = true` do Alfa
  - Registra `infected_id` e `infected_name` em `last_event`
- **`check_game_over` + trigger**: Prioridade 0 — se `alive_count = 1` e role = 'lone_wolf', `winner = 'lone_wolf_win'`
- **Frontend** (`WerewolfPanel`): em frenesi, permite selecionar 2 alvos com confirmação; alpha vê checkbox de infecção; todas as variantes de lobo acordam via step 'wolves'
- **Infection Banner**: se `lastEvent.infected_id === player.id`, mostra 🐺 "Você foi mordido pelo Lobo Alfa e agora pertence à Alcatéia!" no canto inferior esquerdo
- **HostRolePanel**: sem mudanças — lê o role do DB, então um infectado automaticamente aparece como 🐺 Lobisomem
- **Game Over**: `winner === 'lone_wolf_win'` exibe "O LOBO SOLITÁRIO VENCEU!" com nome do vencedor
- **Files**: `src/lib/cards.ts`, `src/lib/sql/migration-026-wolf-variations.sql`, `src/components/werewolf-panel.tsx`, `src/components/host-action-log.tsx`, `src/app/game/[id]/page.tsx`, `src/hooks/use-player.ts`, `src/lib/types.ts`, `docs/architecture.md`.

### `<current-1>` — Modos de Revelação (reveal_mode)
- **Migration `20260703175534_reveal_mode.sql`**: `rooms.reveal_mode TEXT` (check: `'total'`, `'team'`, `'hidden'`). Default `'total'`.
- **`src/lib/reveal.ts`**: `getRevealedRoleText(roleId, revealMode)` — utility que mascara papel segundo o modo:
  - `'total'` → nome da carta (ex: "Vidente")
  - `'team'` → time da carta (ex: "Time da Vila")
  - `'hidden'` → "Identidade Oculta"
- **ScenarioBuilder**: Nova seção "Configurações da Partida" com 3 radio buttons. Host escolhe o modo antes de iniciar (`UPDATE rooms.reveal_mode` antes de `start_game`).
- **RPCs alteradas** (via SQL Editor): `resolve_night`, `resolve_day_vote`, `host_execute_accused` — cada objeto em `last_event.victims` (e `last_vote_result` para linchamento) agora inclui `'role'` do jogador morto.
- **`get_graveyard_info(p_room_id)`**: Nova RPC SECURITY DEFINER que retorna `[{id, name, role}]` de todos os jogadores mortos (não-moderador). Usada pelo cemitério.
- **DayAnnouncement**: Recebe `revealMode` prop. Abaixo do nome da vítima exibe o papel mascarado (host vê sempre o original via `'total'`).
- **Banners de linchamento** (host + player view em `game/[id]/page.tsx`): Agora mostram o papel da vítima (original para host, mascarado para jogadores).
- **GraveyardList**: Novo componente colapsável listando mortos com papel mascarado, visível para todos os jogadores não-host durante o jogo. Polling a cada 5s via RPC `get_graveyard_info`.
- **Regra de visibilidade**: O host (`isHost === true`) SEMPRE enxerga o papel original, ignorando o `reveal_mode`. A máscara só se aplica aos jogadores comuns.
- **Bugfix `execute_night_action`**: A UNIQUE constraint de `night_actions` foi alterada de `(room_id, turn_index, actor_id)` para `(room_id, turn_index, actor_id, action_type, target_id)` pela migration do Cupido. A função `execute_night_action` ainda referenciava a constraint antiga no `ON CONFLICT`, causando erro "there is no unique or exclusion constraint matching the ON CONFLICT specification" em ações noturnas (lobos 1ª noite, bruxa veneno, etc). Corrigido: todos os `ON CONFLICT` agora usam as 5 colunas corretas.
- **Bugfix `last_vote_result` persistente**: `last_vote_result` nunca era limpo nas transições de fase. Um linchamento no Dia 2 fazia o modal "O acusado foi linchado pela vila!" reaparecer no `reveal` do Dia 3. Corrigido:
  - Frontend: removido o bloco `lastVoteResult?.type === 'lynch'` do step `reveal` (host + players) — o anúncio já é exibido corretamente no step `lynch_reveal`.
  - SQL: `resolve_night`, `advance_to_night`, `host_day_to_night`, `host_absolve_accused` agora setam `last_vote_result = NULL` ao transicionar.
- **Files**: `supabase/migrations/20260703175534_reveal_mode.sql`, `src/lib/reveal.ts`, `src/components/scenario-builder.tsx`, `src/components/day-announcement.tsx`, `src/components/graveyard-list.tsx`, `src/app/game/[id]/page.tsx`, `src/lib/sql/migration-024-reveal-mode.sql`, `src/lib/sql/migration-025-clear-last-vote-result.sql`, `docs/architecture.md`.

### `<current-1>` — 4 fixes: Cupido log dupla, História persistente, Alma gêmea no anúncio, Modal de linchamento
- **Cupido log dupla**: `submit_cupid_match` insere 2 linhas em `night_actions` (uma por alvo). `UNIQUE constraint` alterada para `(room_id, turn_index, actor_id, action_type, target_id)`. `HostActionLog` agrupa por `actor_id` e exibe "X uniu A e B".
- **História persistente**: `HostActionLog` agora busca TODAS as ações da sala (sem filtro `turnIndex`), agrupa por `turn_index`, exibe "Noite 1", "Noite 2", etc em jogos com múltiplos turnos.
- **Alma gêmea no anúncio diurno**: `resolve_night` checa soulmate de vítima lobisomem e veneno PÓS trigger, inclui no array `victims` (causa `soulmate`). `resolve_day_vote` e `host_execute_accused` registram `soulmate_name` em `last_event`/`last_vote_result`. `DayAnnouncement` mostra "coração partido por amor" (host only, causa `soulmate`).
- **Modal de linchamento**: `resolve_day_vote` e `host_execute_accused` setam `current_phase = 'day', day_step = 'lynch_reveal'` em vez de ir direto para `'night'`. Novo RPC `advance_to_night` (substitui `advance_after_prince`). Host vê banner + "Avançar para Noite"; jogadores veem banner + "A noite está chegando...".
- **Migration**: `20260702224500_fix_4_issues.sql` (aplicar no SQL Editor).
- **Files**: `supabase/migrations/20260702224500_fix_4_issues.sql`, `src/hooks/use-room.ts`, `src/components/host-action-log.tsx`, `src/components/day-announcement.tsx`, `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current-1>` — Lote 3.5: Cupido log, Culto Panel ícones, Príncipe UI, Soulmate trigger fix

### `<current-1>` — 3 bugfixes: Cupido/Culto/Príncipe
- **Cupido**: Corrigido off-by-one no `page.tsx` linha 782. Painel não renderizava na primeira noite.
- **Líder de Culto**: Criada RPC `get_cult_targets`. `CultLeaderPanel` agora chama a RPC.
- **Príncipe**: `resolve_day_vote` + `host_execute_accused` verificam `role = 'prince'`. RPC `advance_after_prince`. Frontend banner.
- **Migrations**: `20260702213720_cult_targets.sql`, `20260702213742_prince_mechanic.sql`, `20260702214222_prince_host_execute.sql`.
- **Files**: `supabase/migrations/20260702213720..42..22`, `src/components/cult-leader-panel.tsx`, `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current-2>` — Bugfix: Botão cupido turnIndex off-by-one
- **Problema**: `advance_phase` incrementa `turn_index` ao sair de `card_reveal` → `night`. Na primeira noite `turnIndex === 1`, não `0`. O filtro `turnIndex > 0` escondia o botão do cupido.
- **Fix**: Filtro do botão mudou de `turnIndex > 0` para `turnIndex !== 1`. Texto preditivo ganhou `if (s === 'cupid' && turnIndex !== 1) return false`. `isFirstNight` do WerewolfPanel corrigido de `turnIndex === 0` para `turnIndex === 1`.
- **Commit**: `76efc12`
- **Files**: `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current-2>` — ScenarioBuilder: Catálogo agrupado por time + pontos coloridos
- **`CARD_CATALOG`** (`src/lib/cards.ts`): `CardDefinition` ganhou `team: 'village' | 'wolf' | 'independent'`. Cada carta categorizada: Village (aldeões, vidente, bruxa, etc), Wolf (lobisomem), Independent (curtidor, cupido, líder de culto).
- **ScenarioBuilder agrupado**: A lista de cartas agora renderiza 3 seções com cabeçalhos coloridos: 🌿 Time da Vila (verde), 🐺 Time dos Lobos (vermelho), ⚖️ Independentes (roxo). Cartas aparecem dentro de sua seção.
- **Pontos visíveis**: Ao lado do nome de cada carta, badge `[+7]` (verde se >0), `[-6]` (vermelho se <0), `[0]` (amarelo se 0) com formatação de sinal explícito.
- **Files**: `src/lib/cards.ts`, `src/components/scenario-builder.tsx`, `docs/architecture.md`.

### `<current-3>` — Lote 3: Cupido + Líder de Culto + 1ª Noite Lobos
- **Migrations (4 via CLI)**: `lot3_columns`, `lot3_cupid_rpc`, `lot3_soulmate_trigger`, `lot3_game_over`.
- **Cupido**: RPC dedicada `submit_cupid_match` — cross-update de soulmate_id entre 2 alvos. Só age na 1ª noite. -3 pontos.
- **Líder de Culto**: `execute_night_action('cult_convert')` → `UPDATE in_cult = true`. Toda noite. 1 ponto.
- **Soulmate trigger**: `trg_soulmate_death` — morte em cadeia com guarda anti-loop.
- **check_game_over**: PRIORIDADE 1: `soulmates_win`. PRIORIDADE 2: `cult_win`.
- **1ª Noite Lobos**: `isFirstNight === (turnIndex === 1)` — reconhecimento sem morte.
- **Files**: `supabase/migrations/20260702203438..54`, `src/lib/cards.ts`, `src/components/werewolf-panel.tsx`, `src/components/cupid-panel.tsx`, `src/components/cult-leader-panel.tsx`, `src/app/game/[id]/page.tsx`, `src/lib/sql/migration-023-lot3.sql`.

### `<current-4>` — 5 UX fixes + resolve_night bugfix (players.last_event)
- **Bugfix**: migration `20260702194405_fix_players_last_event.sql` — remove `last_event = 'lobisomem'/'veneno'` dos `UPDATE players` no `resolve_night` (coluna não existe em players, causa erro). A causa da morte já vai no `game_state.last_event` (JSONB victims).
- **Bodyguard self-block**: `BodyguardPanel` filtra `r.id !== playerId` — guarda-costas não pode se proteger.
- **RoleInfoModal**: Novo componente `src/components/role-info-modal.tsx` — modal centralizado (`z-[100]`, `bg-black/50`) com nome, pontos, descrição. Substitui tooltips inline em `ScenarioBuilder`, `HostRolePanel`, `TribunalPanel`.
- **Night buttons dim**: Polling de `night_actions` a cada 2s (apenas durante `phase === 'night'`). Botões de papéis já resolvidos na rodada atual ficam `opacity-50 cursor-not-allowed`. "😴 Todos Dormindo" permanece 100% visível.
- **Action log labels**: `host-action-log.tsx` agora tem labels para `priest_bless → 🙏 abençoou`, `bodyguard_protect → 🛡️ protegeu`, `aura_investigate → 👁️ investigou aura de`.
- **Game Over**: Títulos mudaram para `VITÓRIA DO TIME DA VILA` / `VITÓRIA DO TIME DOS LOBOS` / `O CURTIDOR VENCEU`. Lista de vencedores exibe apenas nomes (sem role entre parênteses).
- **Files**: `src/components/bodyguard-panel.tsx`, `src/components/role-info-modal.tsx`, `src/components/scenario-builder.tsx`, `src/components/host-role-panel.tsx`, `src/components/tribunal-panel.tsx`, `src/components/host-action-log.tsx`, `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current+1>` — PWA, Home refactor, resolve_night sequential fix
- **PWA infra**: `@serwist/next` configurado em `next.config.ts`; `sw.ts` service worker com precache + runtime caching; `manifest.json` com ícones SVG 192/512; `metadata.manifest` no layout.
- **Install button**: `use-install-prompt.ts` hook escuta `beforeinstallprompt`; `InstallButton` renderiza "📲 Instalar App" na Home apenas quando instalável.
- **Home simplificada**: Input "Nome do Jogador" + "Código da Sala" sempre visíveis; dois botões lado a lado (`flex flex-row gap-4`): **Criar Sala** (gera PIN novo automaticamente) e **Entrar** (usa PIN digitado). Remove alternador de modo.
- **resolve_night 3-passos**: Nova migration `20260702182612_fix_priest_poison_order.sql`. Ordem sequencial dentro da RPC:
  1. **Padre**: lê `priest_bless` da night_actions → `UPDATE is_blessed = TRUE`
  2. **Lobisomens**: lê alvo → verifica `is_blessed` (pós-Passo1) + bodyguard → consome bênção se salvar
  3. **Bruxa (veneno)**: lê alvo → **re-lê** `is_blessed` (pós-Passo1 e Passo2) + bodyguard → consome bênção se salvar
  - `last_event` setado diretamente nos UPDATEs de morte para `lobisomem`/`veneno`.
- **Files**: `next.config.ts`, `src/app/sw.ts`, `public/manifest.json`, `public/icon-*.svg`, `src/hooks/use-install-prompt.ts`, `src/components/install-button.tsx`, `src/app/page.tsx`, `src/app/layout.tsx`, `supabase/migrations/20260702182612_fix_priest_poison_order.sql`, `src/lib/sql/migration-022-fix-priest-poison-order.sql`, `docs/architecture.md`.

## Game Flow (State Machine)

```
lobby → card_reveal → night → day (announcement → discussion → trial → voting → reveal)
                                    ↓ (se príncipe)          ↓ (se maioria SIM)
                                prince_reveal → night →   lynch_reveal → night → ...
```

| Phase | Description |
|-------|-------------|
| `waiting` / lobby | Players join; host configures scenario (role distribution). |
| `card_reveal` | Each player sees their role card; host advances when all viewed. |
| `night` | Host wakes roles sequentially (cupid → priest → bodyguard → wolves → witch → seer → aura_seer → cult_leader); each performs action. Cupido only on night 1 (turnIndex === 1). Wolves don't kill on night 1 (just recognize each other). |
| `day` | Announcement (victims) → discussion → tribunal phase (trial → voting → reveal). Se o alvo do linchamento for o Príncipe, entra em `prince_reveal` e avança direto para night. |
| `finished_villagers_win` | Game over — villagers win. |
| `finished_wolves_win` | Game over — wolves win. |
| `finished_tanner_win` | Game over — tanner wins. |
| `finished_soulmates_win` | Game over — soulmates win (love conquers all). |
| `finished_cult_win` | Game over — cult dominates the village. |

**`current_phase`** values: `waiting`, `card_reveal`, `night`, `day`, `ended`.

**`day_step`** (when `current_phase = 'day'`): `announcement`, `discussion`, `trial`, `voting`, `reveal`, `prince_reveal`, `lynch_reveal`.

**`night_step`** (when `current_phase = 'night'`): `sleeping`, `cupid`, `priest`, `bodyguard`, `wolves`, `witch`, `seer`, `aura_seer`, `cult_leader`.

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

### `<current+1>` — 4 usability tweaks (beta)
- **Night guide preditivo**: `nextRoleToWake` calcula o primeiro papel em `WAKE_ORDER` disponível e não resolvido; exibe `📍 Vez de acordar: ...` antes do host clicar.
- **Discussion copywriting**: Não-host vê "Hora da Discussão" com subtítulo explicativo (`Comunique-se com a vila...`).
- **Vote counter X/Y**: `voteCount` e `eligibleVoters` (vivos - moderador - acusado) exibidos via polling a cada 2s durante `dayStep = 'voting'`, apenas no painel do host.
- **Game over público**: `winnerPlayers` inclui `role` agora; nomes e papéis (ex: "João (Lobisomem)") renderizados para TODOS os jogadores, sem restrição de `isHost`.

### `<current+2>` — Bugfixes dos 4 usability tweaks
- **Night guide**: `nightRolesActedRef` (useRef<Set>) acumula papéis que já foram acordados (detecta transição `nightStep` de um papel para outro); resetado a cada novo `turnIndex`. `nextRoleToWake` pula papéis no ref (além de `wolvesResolved` para lobos).
- **DayAnnouncement**: Um único `☠️` no topo, nomes listados abaixo (sem caveira por nome); causa da morte (host only) em cada linha. Layout não empurra outros elementos.
- **DayAnnouncement escondido**: No player view, só renderiza durante `dayStep === 'announcement' || 'discussion'`; durante `trial`/`voting`/`reveal` some e deixa o conteúdo da fase atual visível.
- **Vote counter host-only**: Removido do player view (`TribunalVoting` não exibe mais X/Y).
- **Game over**: Subtítulo redundante (`🐺 Lobisomens` / `👔 Curtidor`) removido; `winnerPlayers` agora com polling a cada 2s (fallback Realtime) para garantir que todos os jogadores recebam os dados.

### `<current>` — 5 UX/QoL improvements
- **Day Announcement (Task 1)**: `day_step = 'announcement'` added to `resolve_night` RPC (applied via `supabase db push`, migration `20260701130300_day_step_announcement`); host sees "Iniciar Debate" button; players see victims without sub-phase content until host starts discussion.
- **Winner names (Task 2)**: `renderEnded` queries `players` table for `role = 'werewolf'` (wolves win) or `role = 'tanner'` (tanner win) and displays the names below the victory banner.
- **Night guide (Task 3)**: `WAKE_ORDER` constant used to show NEXT turn indicator preditivo (`📍 Vez de acordar: 🐺 Lobisomens`) during sleeping, or `📍 Vez:` when a role is active.
- **Scenario localStorage (Task 4)**: `counts` persisted to/restored from `localStorage` key `lobinho_last_scenario` — host's role distribution survives page refresh.
- **Player limit 25 (Task 5)**: `player-list.tsx` shows `/25` instead of `/8`; `scenario-builder.tsx` validates `playerCount <= 25`.

### `6940c6c+1` — Fix players_role_check constraint
- Added missing `mayor`, `prince`, `tanner`, `lycan` to `players_role_check` constraint.
- `migration-021-fix-role-constraint.sql`: single ALTER TABLE to drop and recreate constraint.
- Start game was failing with "violates check constraint players_role_check" for any scenario using new roles.

### `<current+1>` — 4 UI/UX fixes (beta testing)
- **AuraSeerPanel result**: Added `showResult` state; result stays visible until player clicks "Fechar Olhos" button (calls `onDone`). Fixes panel closing before showing aura result.
- **Role color standardisation**: `ROLE_STYLE` (`src/lib/cards.ts`) — unified Tailwind classes for all 11 roles (werewolf, wolf_cub, seer, aura_seer, witch, villager, lycan, mayor, prince, tanner, priest, bodyguard). Used identically in `HostRolePanel` badges and night wake-up buttons. `ROLE_LABEL` expanded for all roles, replacing per-role inline classes.
- **Tooltips for Host**: `HostRolePanel` and `TribunalPanel` accuse modal now show ⓘ icon next to each player role; clicking toggles a tooltip with `card.description` from `CARD_CATALOG`. Moderator still excluded from both panels.
- **Lynch banner → floating overlay**: Removed the persistent top red bar (`w-full bg-red-950/40`) showing lynch deaths. Replaced with a centered floating overlay (`⚖️ O acusado foi linchado pela vila!`) during `dayStep === 'reveal'` only. Disappears automatically when host advances past reveal.
- **Files touched**: `src/components/aura-seer-panel.tsx`, `src/lib/cards.ts`, `src/components/host-role-panel.tsx`, `src/components/tribunal-panel.tsx`, `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `<current>` — Lote 2: Padre, Guarda-costas, Vidente de Aura
- **Migration `20260701130400_lot2_priest_bodyguard_aura.sql`**: `players.is_blessed BOOLEAN DEFAULT FALSE`; `night_actions_action_type_check` atualizado com `priest_bless`, `bodyguard_protect`, `aura_investigate`.
- **`execute_night_action`**: 3 novos branches — `priest_bless` (seta `is_blessed = true`), `bodyguard_protect` (registra em `night_actions`), `aura_investigate` (retorna `has_special_role` se role ∉ {'villager', 'werewolf'}).
- **`resolve_night`**: Morte dos lobos anulada se o alvo tiver `bodyguard_protect` DAQUELA noite OU `is_blessed = true`. Bênção é consumida (`is_blessed = false`) ao salvar.
- **`CARD_CATALOG`**: 3 novas cartas — `priest` (3 pts), `bodyguard` (3 pts), `aura_seer` (3 pts).
- **`WAKE_ORDER`**: `['priest', 'bodyguard', 'wolves', 'seer', 'witch', 'aura_seer']` — guia preditivo funciona automaticamente.
- **Painéis noturnos**: `PriestPanel` (1 uso por jogo via state), `BodyguardPanel` (lastTargetId no localStorage, bloqueia alvo repetido), `AuraSeerPanel` (resultado "Papel Especial" / "Cidadão Comum").
- **Host controls**: Botões dinâmicos para acordar Padre, Guarda-costas, Vidente de Aura — filtrados por `availableNightRoles`.
- **Arquivos tocados**: `supabase/migrations/20260701130400_lot2_priest_bodyguard_aura.sql`, `src/lib/cards.ts`, `src/app/game/[id]/page.tsx`, `src/components/priest-panel.tsx`, `src/components/bodyguard-panel.tsx`, `src/components/aura-seer-panel.tsx`, `docs/architecture.md`.

### `<current+1>` — Wolf consensus retry, AuraSeer matches Seer behavior
- **Wolf consensus retry**: `resolve_night_wolves` now checks `COUNT(DISTINCT target_id)` BEFORE setting `wolves_resolved`. If >1 distinct target: deletes all wolf `night_actions` + raises exception. Host sees error message; wolves retry until they agree. Applied via migration `20260702043153_fix_wolf_consensus_retry.sql`.
- **AuraSeerPanel**: Removed "Fechar Olhos" button. `onDone` called immediately after result (like common Seer). Removed `actedRoles.has('aura_seer')` guard in page.tsx — panel stays visible until host advances `nightStep`.

### `76b7a07` — Wolf consensus: return `{consensus: false}` instead of `RAISE EXCEPTION`
- `resolve_night_wolves` RPC: `RAISE EXCEPTION` caused PostgreSQL to rollback the entire transaction, including the `DELETE` that clears wolf votes. Changed to return `{consensus: false, message: '…'}` instead, so the `DELETE` persists and wolves can retry.
- `HostControls` updated to read `data.consensus === false` and display the error to the host.
- **Files**: `supabase/migrations/20260702044318_fix_wolf_consensus_no_exception.sql`, `src/components/host-controls.tsx`.

### `76b7a07` — Game Over reveals roles to ALL players via RPC
- `player_profiles` view (auto-generated by Supabase) exposes only public columns; `role` is sensitive and invisible to non-host players via normal queries.
- Created `get_revealed_players(p_room_id)` — SECURITY DEFINER RPC that bypasses RLS and returns `{id, name, role}` for all players in a room.
- Game Over polling effect now calls `supabase.rpc('get_revealed_players', { p_room_id })` instead of querying `players` + `player_profiles` separately — works identically for hosts and regular players.
- For `villagers_win`, the RPC returns all players (since no `roleFilter` is applied), showing the full player list.
- **Files**: `supabase/migrations/20260702050008_reveal_players_rpc.sql`, `src/app/game/[id]/page.tsx`, `docs/architecture.md`.

### `fc79acc` — DayAnnouncement spacing, discussion banner, Game Over names fix
- **DayAnnouncement `mb-8`**: container ganha `mb-8` pra evitar colisão do botão "Iniciar Debate" com `HostRolePanel` quando não há vítimas.
- **Discussion banner**: DayAnnouncement removido do player view durante `discussion`. Substituído por banner `📣 Hora da Discussão` no centro-superior (mesma posição do DayAnnouncement) com timer abaixo.
- **Game Over via `player_profiles`**: `winnerPlayers` agora busca `name` de `player_profiles` (não `players.name`, coluna vazia) e `role` de `players`, merge por `id` — mesmo padrão de `tribunal-reveal.tsx`.

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
| PriestPanel | `src/components/priest-panel.tsx` | Priest night action: bless a player (1 use per game) |
| BodyguardPanel | `src/components/bodyguard-panel.tsx` | Bodyguard night action: protect a player (no repeat last target) |
| AuraSeerPanel | `src/components/aura-seer-panel.tsx` | Aura Seer night action: detect if target has special role |
| InstallButton | `src/components/install-button.tsx` | PWA install button (visible only when `beforeinstallprompt` captured) |
| RoleInfoModal | `src/components/role-info-modal.tsx` | Centralized modal with role name, points, description (z-[100], bg-black/50). Replaces tooltips in ScenarioBuilder, HostRolePanel, TribunalPanel. |
| SeerPanel | `src/components/seer-panel.tsx` | Seer night action: investigate player, see is_werewolf |
| CupidPanel | `src/components/cupid-panel.tsx` | Cupid night action (night 1 only): pick two soulmates |
| CultLeaderPanel | `src/components/cult-leader-panel.tsx` | Cult Leader night action: convert a player to the cult |
| WerewolfPanel | `src/components/werewolf-panel.tsx` | Werewolf night action: see teammates, choose victim (night 1: recognition only) |
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
| `use-install-prompt` | `src/hooks/use-install-prompt.ts` | Listens to `beforeinstallprompt` event; returns `{ isInstallable, promptInstall }` |

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
| `20260701130400_lot2_priest_bodyguard_aura.sql` | Lote 2: `is_blessed`, `priest_bless`/`bodyguard_protect`/`aura_investigate`, bodyguard+blessing resolve_night | Applied via CLI (db push) |
| `20260702044318_fix_wolf_consensus_no_exception.sql` | `resolve_night_wolves` returns `{consensus: false}` instead of `RAISE EXCEPTION` to avoid DELETE rollback | Applied via CLI (db push) |
| `20260702050008_reveal_players_rpc.sql` | `get_revealed_players(p_room_id)` — SECURITY DEFINER RPC to bypass RLS and return `{id, name, role}` for all players in a room. Used by Game Over to show winner roles to all clients. | Applied via CLI (db push) |
| `20260702182612_fix_priest_poison_order.sql` | **Fix resolve_night**: ordem sequencial Padre → Lobos → Bruxa. Passo 1 seta `is_blessed`, Passo 2 lobos checam blessing+bodyguard, Passo 3 veneno re-lê `is_blessed` pós-passos 1-2. **Bug**: adicionou `last_event` em UPDATEs de players (coluna inexistente). | Applied via CLI (db push) |
| `20260702194405_fix_players_last_event.sql` | **Correção**: Remove `last_event` dos UPDATEs em `players` no `resolve_night`. `last_event` só existe em `game_state`. | Applied via CLI (db push) |
| `20260702203438_lot3_columns.sql` | Lote 3: `soulmate_id`, `in_cult`, constraints (roles, night_actions, rooms status) | Apply via CLI (db push) |
| `20260702203452_lot3_cupid_rpc.sql` | `submit_cupid_match(p_room_id, p_target_a, p_target_b)` — dedicated RPC | Apply via CLI (db push) |
| `20260702203453_lot3_soulmate_trigger.sql` | `trg_soulmate_death` — death chain for soulmates | Apply via CLI (db push) |
| `20260702203454_lot3_game_over.sql` | `check_game_over` (+soulmates/+cult), `host_end_game`, `execute_night_action` (+cult_convert), `get_revealed_players` (+in_cult/+soulmate_id) | Apply via CLI (db push) |

**Important**: All migrations have `CREATE OR REPLACE FUNCTION` blocks removed (neutered). The actual DB schema is maintained through Supabase SQL Editor. These files are reference copies only.

---

## Business Rules

### Win Condition
- Checked by `check_game_over()` trigger after each death.
- **Priority 1 (Soulmates)**: If exactly 2 non-moderator players are alive AND they are each other's soulmates → `soulmates_win`.
- **Priority 2 (Cult)**: If cult_leader is alive AND no non-moderator, non-leader player has `in_cult = false` → `cult_win`.
- **Priority 3 (Tanner)**: Dead tanner with `last_event.event_type = 'lynch'` → `tanner_win`.
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
- Stored in `last_event.victims` array on `game_state`.
- Visible only to host via `DayAnnouncement isHost` prop.
- Possible values: `lobisomem` (wolf kill), `veneno` (witch poison), `linchamento` (tribunal execution), `soulmate` (heartbreak).

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

12. **Game Over role revelation via RPC** — `player_profiles` view (auto-generated by Supabase) exposes only public columns; `role` is sensitive. Regular players cannot see other players' roles even after game ends. Solution: `get_revealed_players()` SECURITY DEFINER RPC in `20260702050008_reveal_players_rpc.sql` bypasses RLS and returns `{id, name, role}` for all room players. Game Over component calls this RPC instead of direct table queries, ensuring all clients see the full winner list.

13. **Cupid dedicated RPC** — `submit_cupid_match` created instead of adding `cupid_match` to `execute_night_action`. Cupid needs 2 targets (cross-update soulmate_id), which doesn't fit the single-target pattern of `execute_night_action`.

14. **Soulmate death chain via trigger** — `trg_soulmate_death` fires `AFTER UPDATE OF is_alive` (same timing as `trg_check_game_over`). Guard `IF partner is alive` prevents infinite loop. Alphabetically `s` < `t`, so soulmate trigger fires before game over trigger on the same row.

15. **Cult win excludes leader from `in_cult` count** — `check_game_over` checks `role NOT IN ('moderator', 'cult_leader') AND in_cult = false`. The leader is inherently part of the cult and doesn't need `in_cult = true` flag.

16. **Winner players via `get_revealed_players`** — instead of a new RPC, `get_revealed_players` was updated to return `in_cult` and `soulmate_id`. Frontend filters locally for `soulmates_win` (soulmate_id != null) and `cult_win` (in_cult || role === 'cult_leader'). All identities are revealed post-game anyway.

17. **Werewolf first night** — uses `turnIndex === 0` (no `night_number` column). WerewolfPanel receives `isFirstNight` prop. Registers `execute_night_action('werewolf_kill', null)` to advance the action queue without killing anyone.
