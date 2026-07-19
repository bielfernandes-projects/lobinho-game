# Werewolf (Lobisomem) — Game Rules Reference

> **THE SINGLE SOURCE OF TRUTH FOR GAME RULES.**
>
> **⚠️ MANDATORY READING FOR AI AGENTS ⚠️**
>
> Before making ANY code change related to:
> - Roles (adding, removing, or modifying)
> - Game mechanics (night/day cycle, death resolution, win conditions)
> - The scenario builder (role distribution, balance)
> - Any feature that touches player state, night actions, or day actions
>
> You **MUST** read this entire file first and explicitly base your plan on it.
> The rules in this file are authoritative. If you discover a discrepancy between this file and the code, the **rules win** — fix the code, not the rules.

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Players and Roles (Core Concepts)](#2-players-and-roles-core-concepts)
3. [Phase Machine](#3-phase-machine)
4. [The Night Phase — Complete Spec](#4-the-night-phase--complete-spec)
5. [The Day Phase — Tribunal System](#5-the-day-phase--tribunal-system)
6. [Win Conditions (Priority Order)](#6-win-conditions-priority-order)
7. [Complete Role Catalog](#7-complete-role-catalog)
8. [Seer & Aura Seer Vision Reference](#8-seer--aura-seer-vision-reference)
9. [Death Causes and How They Are Revealed](#9-death-causes-and-how-they-are-revealed)
10. [Official vs Fan-Made Classification](#10-official-vs-fan-made-classification)
11. [Variant Rules (Optional)](#11-variant-rules-optional)
12. [Points & Scenario Balance](#12-points--scenario-balance)
13. [Implementation Notes for AI Agents](#13-implementation-notes-for-ai-agents)
14. [Quick-Reference: What to Read Before What](#14-quick-reference-what-to-read-before-what)

---

## 1. Game Overview

### 1.1 High-level

Werewolf is a hidden-identity social deduction game. Players are secretly assigned **roles** at the start of the game. Some roles belong to the **Village** (good), some to the **Werewolves** (bad), and some are **Independent** (their own win condition).

The game alternates between:
- **NIGHT** — certain roles "wake up" and take a secret action
- **DAY** — the Village discusses and votes to lynch (execute) a player

The first team to achieve their win condition wins. The game ends when one team's win condition is satisfied.

### 1.2 Player count

| Version | Min players | Max players |
|---------|-------------|-------------|
| Basic (Seer + Werewolves + Villagers) | 5 | 68 |
| Recommended for our app | **6** | **78 (77 players + 1 moderator)** |

A **Moderator** is always present. The moderator is not a real player — they cannot be targeted, vote, die, or be assigned a role from the catalog. They run the game and may have UI affordances (the "host" in our app).

### 1.3 Teams

| Team | Goal | Color in our app |
|------|------|-------------------|
| **Village** (Aldeia) | Eliminate all Werewolves | Blue |
| **Werewolf** (Lobisomem) | Achieve parity with non-werewolf players (or eliminate them) | Red |
| **Independent** | Fulfill a role-specific personal win condition | Purple |
| **Special third teams** (Vampires, etc.) | Wipe out all other teams | (n/a — not yet implemented) |

A player's team is **not necessarily fixed** — some roles switch teams during the game (Cursed, Doppelgänger, Drunk).

---

## 2. Players and Roles (Core Concepts)

### 2.1 Role definition

Each player has exactly one **role** at any time. The role determines:
- What team they are on
- What night actions (if any) they can take
- What special day actions (if any) they can take
- How the Seer / Aura Seer sees them
- Their personal win condition (if Independent)
- Their point value (for scenario balance)

### 2.2 Role states

Every player has these boolean state flags (in our database, on the `players` table):

| State | Meaning |
|-------|---------|
| `is_alive` | Can take actions, can be targeted, can vote |
| `is_host` | Is the moderator. Excluded from game logic. |
| `is_blessed` | Has a permanent protection shield (Priest's blessing, one-shot) |
| `has_used_power` | Has already used their one-shot ability (Priest, Marksman, Alpha Wolf) |
| `in_cult` | Has been converted by the Cult Leader |
| `has_viewed_card` | Has already seen their own role card (for card_reveal phase) |
| `doppelganger_target_id` | (Doppelgänger only) the player whose death will trigger role-copy |
| `soulmate_id` | (Soulmate only) the other half of a Cupid-bonded pair |

### 2.3 When a player dies

When a player's `is_alive` becomes `false`:
- They can no longer take actions (night or day)
- They cannot vote
- They cannot be targeted
- They may trigger role-specific death effects (Hunter, Prince→Squire promotion, Soulmate chain, Wolf Cub→Frenzy, Diseased→Skip, Alpha→Infection)

### 2.4 Team-switching

Three roles can switch teams during a game:
- **Cursed** — village → werewolf (when attacked by wolves or lynched)
- **Doppelgänger** — village → target's team (when target dies)
- **Drunk** — village → hidden role (revealed night 3)

The Seer's vision updates immediately when a player switches teams.

---

## 3. Phase Machine

The game has a state machine with these phases. Each has well-defined sub-states.

### 3.1 Top-level phases (`current_phase`)

| Phase | Description |
|-------|-------------|
| `waiting` | Lobby. Players join. Host configures the scenario. |
| `card_reveal` | Each player privately views their own role card. |
| `night` | Roles wake up sequentially per WAKE_ORDER. |
| `day` | Day phase (announcement → discussion → tribunal). |
| `ended` | Game over. Show results. |

### 3.2 Day sub-states (`day_step`, when `current_phase = 'day'`)

| Sub-state | What happens |
|-----------|--------------|
| `announcement` | Show who died during the night (cause hidden from non-host) |
| `hunter_reveal` | Only if a Hunter died at night. Dead Hunter picks revenge target. |
| `discussion` | Players discuss. Marksman can shoot. |
| `trial` | Host selects a player to accuse. |
| `voting` | Players vote YES (lynch) or NO (absolve). |
| `reveal` | Votes tallied. Host executes or absolves. |
| `prince_reveal` | Only if accused was the Prince. Identity revealed, Prince survives. |
| `lynch_reveal` | Lynch completed. Show results. |

### 3.3 Night sub-states (`night_step`, when `current_phase = 'night'`)

| Sub-state | Who wakes |
|-----------|-----------|
| `sleeping` | (transition state, no panel shown) |
| `masons` | Masons (night 1 only) |
| `cupid` | Cupid (night 1 only) |
| `doppelganger` | Doppelgänger (night 1 only) |
| `priest` | Priest (if not used) |
| `bodyguard` | Bodyguard |
| `wolves` | All wolf-team roles that wake with wolves |
| `witch` | Witch (only after wolves are resolved) |
| `seer` | Seer |
| `aura_seer` | Aura Seer |
| `sorceress` | Sorceress |
| `cult_leader` | Cult Leader |

### 3.4 Phase transitions

```
waiting → card_reveal → night → day → night → day → ... → ended
                          ↑                    ↓
                          └────────────────────┘
```

When day ends (no lynch, or lynch executed, or Prince-survived):
- If no win condition is met → advance to night
- If a win condition is met → advance to ended (host must confirm via `host_end_game`)

---

## 4. The Night Phase — Complete Spec

The host calls each role in **WAKE_ORDER**. Each role takes its action, then "sleeps" (closes eyes).

### 4.1 Night 1 special rules

On night 1, the following roles take actions:
- **Masons** — wake to recognize each other
- **Cupid** — picks 2 soulmates
- **Doppelgänger** — picks 1 target
- **Priest** — can bless
- **Bodyguard** — can protect
- **Wolves** — recognize each other (NO kill on night 1)
- **Witch** — wakes but cannot act (no wolf kill yet)
- **Seer / Aura Seer / Sorceress / Cult Leader** — take their action

### 4.2 Night 2+ rules

All roles that wake each night may take their action. Wolves now perform their kill.

### 4.3 Night Resolution Order (`resolve_night` SQL function)

When the host resolves the night, deaths are processed in this **strict 3-pass order**:

| Pass | Step | What happens |
|------|------|--------------|
| Pre | 0 | Check `diseased_skip_wolves` flag — if true, wolves skip their kill entirely (consume flag) |
| Pre | 1 | Apply **Priest blessing** first (if any) — sets `is_blessed = true` on target |
| 1 | 2a | Wolves kill target #1: check Alpha infect → Cursed conversion → Witch save → Bodyguard → Blessing |
| 1 | 2b | (If frenzy) Wolves kill target #2: same checks, no Alpha infect |
| 2 | 3 | Witch poison: re-read `is_blessed` → check Bodyguard → kill if not protected |
| 3 | 4 | **Soulmate death chain** — every victim's soulmate dies (if alive) |
| Post | 5 | **Squire promotion** — if Prince died, alive Squire → role = 'prince' |
| Post | 6 | **Doppelgänger role-copy** — if Doppelgänger's target died, copy target's role |
| Post | 7 | **Death-event effects** — Hunter sets `hunter_pending`; Wolf Cub sets `wolves_frenzy`; Diseased sets `diseased_skip_wolves` |
| Post | 8 | Update `game_state` to `current_phase = 'day'`, `day_step = 'announcement'` |
| Post | 9 | Call `check_game_over()` — sets `winner` if condition met, but does NOT change `rooms.status` |

### 4.4 Wolf consensus rule

Wolves must all agree on the same target. If they disagree (multiple distinct `werewolf_kill` actions for different targets), the system:
1. Deletes all wolf kill actions
2. Host must re-prompt wolves to agree
3. Wolves are NOT punished by a wasted night (they can re-vote)

This is enforced by `resolve_night_wolves(p_room_id)` which checks `COUNT(DISTINCT target_id)`.

### 4.5 Frenzy (Wolf Cub death)

When a Wolf Cub dies (any cause), `trg_wolf_cub_death` sets `rooms.wolves_frenzy = true`. Next night:
- Wolves must select **EXACTLY 2 DISTINCT targets**
- The frenzy flag is cleared after the wolves resolve

### 4.6 What wakes with the wolves

The following roles wake during the `wolves` step and see each other:
- `werewolf`
- `wolf_cub` (if not dead)
- `alpha_wolf` (if not dead)
- `lone_wolf` (wakes but is NOT on wolf team — see Win Conditions)

`Sorceress` is on the wolf team but does **not** wake with the wolves.

### 4.7 Wolf kill constraints

- Wolves cannot target another wolf at night (engine-enforced)
- Wolves cannot target the moderator
- Wolves cannot target a dead player
- A wolf may target themselves only in custom variants (NOT in our app)

---

## 5. The Day Phase — Tribunal System

### 5.1 Day sub-step flow

```
announcement → (hunter_reveal?) → discussion → trial → voting → reveal → (prince_reveal?) → lynch_reveal
```

### 5.2 Voting rules

- Each alive non-moderator player gets exactly one vote: `yes` (lynch) or `no` (absolve)
- A vote for the accused is `yes`; a vote for anyone else (or abstention) is `no`
- The **threshold** for a successful lynch is `floor(alive_players / 2) + 1` (simple majority of alive, non-moderator voters)
- If no candidate reaches threshold → vote fails → advance to night
- Ties → vote fails → advance to night

### 5.3 Forced votes

| Role | Forced vote | Display |
|------|-------------|---------|
| **Pacifist** | Always `no` (absolve) | "Você é Pacifista — voto automático: NÃO" |
| **Idiot** | Always `yes` (lynch) | "Você é Idiota — voto automático: SIM" |
| **Mayor** | Counts as 2 votes (x2) | Shows `x2` badge |

### 5.4 Prince exception

If the accused is the **Prince**:
- Day sub-step becomes `prince_reveal`
- Prince's identity is revealed
- Prince **survives** (does not die)
- Day is canceled, advance to night
- (If the Prince is the only one accused, it's a wasted day for wolves)

### 5.5 Hunter exception

If the lynched (or night-killed) player is a **Hunter**:
- `game_state.hunter_pending = true`
- `game_state.hunter_id` set
- Day sub-step becomes `hunter_reveal`
- Dead Hunter picks revenge target (or skips)
- Hunter's revenge kill is instant
- Game does NOT end while Hunter is pending

### 5.6 Cursed on lynch

If a **Cursed** is lynched:
- They do NOT die
- Their role changes to `werewolf`
- They become part of the wolf team
- Cursed banner shown to the player

### 5.7 Day actions (non-tribunal)

| Action | Who | When | Effect |
|--------|-----|------|--------|
| Marksman shoot | Marksman | During `discussion` | Kill a player (one-shot) |
| Hunter retaliation | Hunter (dead) | During `hunter_reveal` | Kill a player (one-shot) |

---

## 6. Win Conditions (Priority Order)

The `check_game_over()` trigger fires AFTER every death. It sets `game_state.winner` but does NOT change `rooms.status` — the host must confirm by calling `host_end_game()`.

### 6.1 Priority table

| Priority | Condition | `winner` value |
|----------|-----------|----------------|
| 1 | Dead Tanner (lynched, not night-killed or poisoned) | `tanner_win` |
| 2 | Exactly 2 alive non-moderator players, AND they are each other's soulmates | `soulmates_win` |
| 3 | Cult Leader alive AND all other non-moderator, non-leader players have `in_cult = true` | `cult_win` |
| 4 | Lone Wolf alive AND no team-wolves alive AND (alive_count = 1 OR alive_count ≤ 2) | `lone_wolf_win` |
| 5 | `v_wolves >= v_non_wolves` (wolves achieve parity) | `wolves_win` |
| 6 | No alive werewolves (and no other win condition triggered) | `villagers_win` |

### 6.2 Wolf count logic

`v_wolves` includes: `werewolf`, `wolf_cub`, `alpha_wolf`, `sorceress` (wolf-team but doesn't wake with them).

`v_non_wolves` includes: all alive non-moderator players EXCEPT `werewolf`, `wolf_cub`, `alpha_wolf`, `lone_wolf`. (Moderator is always excluded.)

### 6.3 Lone Wolf logic

The Lone Wolf:
- Wakes with the wolves (sees them, they see Lone Wolf)
- Is **NOT** on the wolf team
- Wins only if they are the last player standing OR have parity (1 other alive non-werewolf + Lone Wolf)
- If Lone Wolf is still alive and there are no team-wolves, `villagers_win` is **suppressed** — Lone Wolf gets the win

### 6.4 Soulmate win logic

- If both soulmates are alive AND exactly 2 non-moderator players alive → soulmates win (their own team)
- If soulmates are on different teams and become the last 2 alive → they form their own team and win
- If both soulmates die, no soulmate win

### 6.5 Cult win logic

- Cult Leader is always "in the cult" implicitly
- Cult Leader wins if they are alive AND every other alive non-moderator player has `in_cult = true`
- If Cult Leader dies, the first cult member they picked becomes the new Cult Leader

---

## 7. Complete Role Catalog

### 7.1 How to read this catalog

For each role:
- **ID** — the role identifier used in code
- **Name (EN / PT)** — display names
- **Team** — which team
- **Pts** — point value for scenario balance
- **Type** — Official / Expansion / Fan-Made
- **When wakes** — which night steps
- **Description** — the card text shown to players
- **Mechanics** — how it works mechanically
- **Seer sees** — what Seer sees when investigating this role
- **Aura Seer sees** — what Aura Seer sees

### 7.2 Catalog index

| ID | Name (EN) | Name (PT) | Team | Pts | Type |
|----|-----------|-----------|------|-----|------|
| `villager` | Villager | Aldeão | Village | +1 | Official |
| `seer` | Seer | Vidente | Village | +7 | Official |
| `apprentice_seer` | Apprentice Seer | Vidente Aprendiz | Village | +4 | Official |
| `witch` | Witch | Bruxa | Village | +4 | Official |
| `aura_seer` | Aura Seer | Vidente de Aura | Village | +3 | Official |
| `bodyguard` | Bodyguard | Guarda-costas | Village | +3 | Official |
| `priest` | Priest | Padre / Sacerdote | Village | +3 | Official |
| `hunter` | Hunter | Caçador | Village | +3 | Official |
| `huntress` | Huntress | Caçadora | Village | +3 | Official |
| `prince` | Prince | Príncipe | Village | +3 | Official |
| `martyr` | Martyr | Mártir | Village | +3 | Official |
| `tough_guy` | Tough Guy | Cara Durão | Village | +3 | Official |
| `mayor` | Mayor | Prefeito | Village | +2 | Official |
| `ghost` | Ghost | Fantasma | Village | +2 | Official |
| `mason` | Mason | Maçom | Village | +2 | Official |
| `old_witch` | Old Witch | Bruxa Velha | Village | +3 | Official |
| `drunk` | Drunk | Bêbado | Village → other | +4 | Official |
| `diseased` | Diseased | Doente | Village | +3 | Official Expansion |
| `cursed` | Cursed | Amaldiçoado | Village → Wolf | -3 | Official Expansion |
| `doppelganger` | Doppelgänger | Doppelgänger | Village → Target's | -2 | Official Expansion |
| `lycan` | Lycan | Licano | Village | -1 | Official |
| `pacifist` | Pacifist | Pacifista | Village | +2 | Official |
| `idiot` | Idiot | Idiota | Village | +2 | Official |
| `werewolf` | Werewolf | Lobisomem | Wolf | -6 | Official |
| `wolf_cub` | Wolf Cub | Filhote de Lobo | Wolf | -8 | Official |
| `alpha_wolf` | Alpha Wolf | Lobo Alfa | Wolf | -9 | Official |
| `lone_wolf` | Lone Wolf | Lobo Solitário | Independent | -5 | Official |
| `sorceress` | Sorceress | Feiticeira | Wolf | -3 | Official |
| `minion` | Minion | Servo | Wolf | -6 | Official |
| `bad_wolf` | Bad Wolf | Lobo Mau | Wolf | -9 | Official |
| `dire_wolf` | Dire Wolf | Lobo Aproveitador | Wolf | -4 | Official |
| `fruit_brute` | Fruit Brute | Lobo Vegetariano | Wolf | -3 | Official |
| `wolverine` | Wolverine | Wolverine | Wolf | -4 | Official |
| `virginia_wolf` | Virginia Wolf | Quem Tem Medo do Lobo Mau? | Wolf | -2 | Official |
| `cupid` | Cupid | Cupido | Independent | -3 | Official |
| `cult_leader` | Cult Leader | Líder de Culto | Independent | +1 | Official |
| `tanner` | Tanner | Curtidor | Independent | -2 | Official |
| `hoodlum` | Hoodlum | Bandido | Independent | 0 | Official |
| `vampire` | Vampire | Vampiro | Vampires | -7 | Official |
| `soulmate` | (Soulmate — not a separate role) | — | (conditional) | — | (condition) |
| `marksman` | Marksman | Atirador | Village | +2 | Fan-Made |
| `squire` | Squire | Escudeiro | Village | +1 | Fan-Made |
| `moderator` | Moderator | Mestre | (host) | — | (host only) |

> **Status note (as of the most recent code state):**
> **Implemented** (26 player roles + moderator): `villager`, `seer`, `witch`, `aura_seer`, `bodyguard`, `priest`, `hunter`, `prince`, `mayor`, `mason`, `lycan`, `pacifist`, `idiot`, `werewolf`, `wolf_cub`, `alpha_wolf`, `lone_wolf`, `sorceress`, `cupid`, `cult_leader`, `tanner`, `diseased`, `cursed`, `doppelganger`, `marksman`, `squire`.
> **NOT yet implemented** (to be added in future iterations): `apprentice_seer`, `huntress`, `martyr`, `tough_guy`, `ghost`, `old_witch`, `drunk`, `minion`, `bad_wolf`, `dire_wolf`, `fruit_brute`, `wolverine`, `virginia_wolf`, `hoodlum`, `vampire`.

### 7.3 Village Roles (Aldeia)

#### `villager` — Villager / Aldeão
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +1 |
| Type | Official |
| Wake | Never |
| Seer sees | Not werewolf |
| Aura Seer sees | Not special (returns `false`) |
| **Description (EN)** | Find the werewolves and lynch them. |
| **Description (PT)** | Encontre os lobisomens e elimine-os. |
| **Mechanics** | No special ability. Pure voting power. |

#### `seer` — Seer / Vidente
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +7 |
| Type | Official |
| Wake | Every night, after wolves |
| **Description (EN)** | Each night, choose a player to learn if they are Village or Werewolf. |
| **Description (PT)** | Toda noite, escolha alguém para saber se é vila ou lobo. |
| **Mechanics** | Each night, points at a player. Moderator shows thumbs-up (Village) or thumbs-down (Werewolf). Seer sees as Werewolf: `werewolf`, `wolf_cub`, `alpha_wolf`, `lone_wolf`, `lycan`. |
| **Seer sees** | Not werewolf (thumbs-up) |
| **Aura Seer sees** | Returns `false` (Seer is a "special" role) |

#### `apprentice_seer` — Apprentice Seer / Vidente Aprendiz
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +4 |
| Type | Official |
| Wake | Each night AFTER Seer dies; otherwise not |
| **Description (EN)** | If the Seer dies, you become the new Seer. |
| **Description (PT)** | Se a Vidente morrer, você vira a nova Vidente. |
| **Mechanics** | Stays on the bench until Seer dies. The Moderator (or our app) taps the Apprentice Seer on the shoulder the next time the Seer is called — they now act as Seer. The Apprentice Seer does not know who the Seer is. |

#### `witch` — Witch / Bruxa
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +4 |
| Type | Official |
| Wake | After wolves are resolved |
| **Description (EN)** | Once per game, during the night, you can use a healing potion or a death potion. |
| **Description (PT)** | Uma vez por jogo, durante a noite, você pode usar poção da vida ou da morte. |
| **Mechanics** | Healing potion: saves the wolf's victim (one-shot). Death potion: kills any player (one-shot). Both potions may be used in the same night. Witch can also skip (no action). The Moderator calls the Witch every night, even if both potions are used. |

#### `aura_seer` — Aura Seer / Vidente de Aura
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Each night |
| **Description (EN)** | Each night, learn if a player has a special role (not a plain Villager or Werewolf). |
| **Description (PT)** | Toda noite, descubra se um jogador tem um papel especial (não é Aldeão nem Lobisomem). |
| **Mechanics** | Each night, points at a player. Moderator tells them if the target is a "special" role (not `villager`, not `werewolf`, not `wolf_cub`, not `alpha_wolf`, not `lone_wolf`). Lycan, Cursed, and Doppelgänger are seen as "current team" — so a non-converted Cursed appears as Village, and a non-targeted Doppelgänger appears as Village. |

#### `bodyguard` — Bodyguard / Guarda-costas
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Each night |
| **Description (EN)** | Each night, protect a different player. The shield lasts only that night and blocks wolves and poisons. |
| **Description (PT)** | Toda noite, proteja um jogador. O escudo dura SÓ AQUELA NOITE e bloqueia lobos e poções. |
| **Mechanics** | Protects a different player each night (cannot protect the same player two nights in a row, cannot protect self). The protected player cannot be killed by wolves OR witch poison that night. |
| **Alternate rules** | Some variants: cannot protect the same player twice in the same game. Or: protected player also can't be killed the next day. |

#### `priest` — Priest / Padre / Sacerdote
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Once (one-shot) |
| **Description (EN)** | Once per game, choose a player to receive a permanent shield. The next attempt to kill that player fails. |
| **Description (PT)** | Uma vez por jogo, escolha alguém para receber um escudo permanente. A próxima tentativa de matar essa pessoa falha. |
| **Mechanics** | One-shot. Blesses one player with `is_blessed = true`. The next attempt to kill that player (by wolves, witch poison, or even Marksman shot) is blocked, and the blessing is consumed (`is_blessed = false`). Priest cannot bless themselves. If the Priest dies after blessing, the blessing persists. |

#### `hunter` — Hunter / Caçador
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | (only when dead, to retaliate) |
| **Description (EN)** | When you die, you may shoot another player. Your victim dies immediately. |
| **Description (PT)** | Quando você morrer, pode atirar em um jogador. Sua vítima morre imediatamente. |
| **Mechanics** | When killed (lynch or night), the Hunter gets one revenge shot. Calls `hunter_retaliate(p_room_id, p_target_id)` to kill a target, or `hunter_skip(p_room_id)` to skip. The revenge kill is instant. `game_state.hunter_pending = true` blocks `check_game_over()` until the Hunter acts. |

#### `huntress` — Huntress / Caçadora
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Once (one-shot, night) |
| **Description (EN)** | Once per game, during the night, you can eliminate a player. |
| **Description (PT)** | Uma vez por jogo, durante a noite, você pode eliminar um jogador. |
| **Mechanics** | One-shot night kill. Like the Hunter, but the kill happens during the night phase (not on death). Distinct from Hunter — Hunter acts on death, Huntress acts while alive. |

#### `prince` — Prince / Príncipe
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | If the village decides to lynch you, you reveal your identity and survive. |
| **Description (PT)** | Se a vila decidir te linchar, você revela sua identidade e sobrevive. |
| **Mechanics** | First time voted to lynch: identity revealed, Prince survives, day is canceled, advance to night. Subsequent lynches (if any) are NOT immune (one-shot protection). Can still die from wolf kill, witch poison, or other causes. When Prince dies, an alive Squire is promoted to Prince. |

#### `martyr` — Martyr / Mártir
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | (only on lynch — optional) |
| **Description (EN)** | You may take the place of anyone who is lynched, dying in their stead. |
| **Description (PT)** | O Mártir pode morrer no lugar do linchado. |
| **Mechanics** | After a successful lynch vote but before the role reveal, the Martyr can volunteer to die instead. The original target survives. |
| **Alternate rule** | Martyr wakes each night after wolves target someone and may take their place — the original target survives and Martyr dies. |

#### `tough_guy` — Tough Guy / Cara Durão
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | If targeted by wolves, you die the following night instead of the same night. |
| **Description (PT)** | Se os lobos tentarem te eliminar, você só será eliminado na noite seguinte. |
| **Mechanics** | When wolves target the Tough Guy, the kill is deferred to the next night. Players are told "no one died" the previous morning. The next night, the Tough Guy dies (and any other deaths happen that night). |

#### `mayor` — Mayor / Prefeito
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +2 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | Your vote in the tribunal counts double. |
| **Description (PT)** | Seu voto no tribunal conta dobrado. |
| **Mechanics** | Vote is weighted x2. |

#### `ghost` — Ghost / Fantasma
| Field | Value |
|-------|-------|
| Team | Village (retains original team) |
| Pts | +2 |
| Type | Official |
| Wake | (only as a dead player) |
| **Description (EN)** | The first player to die becomes the Ghost. Each night, they write one letter of a clue for the village. |
| **Description (PT)** | O primeiro jogador a morrer vira fantasma. Toda noite o fantasma se comunica escrevendo uma letra. |
| **Mechanics** | Dies on night 1 (or the first death). Each night, writes one letter on a piece of paper as a clue from beyond. May not identify any player by name or initials. May not speak, make eye contact, or otherwise communicate with the village. |
| **Alternate rule** | The first player to die becomes the Ghost but keeps their original team. |

#### `mason` — Mason / Maçom
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +2 (each) |
| Type | Official |
| Wake | Night 1 only |
| **Description (EN)** | On the 1st night, wake with the other Masons to recognize each other. You are secret allies. |
| **Description (PT)** | Na 1ª noite, acorde com os outros Maçons para se reconhecerem. Vocês são aliados secretos. |
| **Mechanics** | Night 1 only. Masons recognize each other. If any player directly or indirectly mentions the Masons (or the "secret society"), they are killed by the Masons that night — and the Masons themselves lose automatically, even if on a winning team. |

#### `old_witch` — Old Witch / Bruxa Velha
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official |
| Wake | Each night |
| **Description (EN)** | Each night, place a "pox" on a player. That player must leave the game area for one day. |
| **Description (PT)** | Cada noite, coloca "varíola" em alguém — esse jogador sai por 1 dia. |
| **Mechanics** | Targets a player each night. The target must leave the game area for the next day (no discussion, no vote, no participation). The target is also safe from the Hunter's shot and any other player attacks. The Old Witch cannot target themselves. |

#### `drunk` — Drunk / Bêbado
| Field | Value |
|-------|-------|
| Team | Village (then becomes whatever their real role is) |
| Pts | +4 |
| Type | Official |
| Wake | Night 3 (and beyond) |
| **Description (EN)** | You are a Villager until the third night, when the Moderator reveals your real role. |
| **Description (PT)** | Você é Aldeia até a 3ª noite, quando o narrador revela sua real função. |
| **Mechanics** | For the first 2 days, the Drunk thinks they are a regular Villager. On the third night, the Moderator wakes them and reveals their real role (which can be any role in the deck). Until then, they cannot use any special ability. |
| **Setup** | During deck preparation, the Moderator picks a random role for the Drunk and secretly keeps it. |

#### `diseased` — Diseased / Doente
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +3 |
| Type | Official Expansion |
| Wake | Never |
| **Description (EN)** | If you are killed by wolves, they skip their next night's kill. |
| **Description (PT)** | Se você for morto por lobos, eles não matam ninguém na noite seguinte. |
| **Mechanics** | When wolves kill the Diseased, `game_state.diseased_skip_wolves = true`. Next night, the wolves' kill is skipped entirely (or the target is chosen but doesn't die, depending on reveal mode). Flag is consumed. Triggers ONLY on wolf kill, not on poison or lynch. |

#### `cursed` — Cursed / Amaldiçoado
| Field | Value |
|-------|-------|
| Team | Village (then Werewolf after conversion) |
| Pts | -3 |
| Type | Official Expansion |
| Wake | (always wakes, even after conversion, for Moderator to signal team) |
| **Description (EN)** | You are on the Village team until you are attacked by wolves — then you become a Werewolf. |
| **Description (PT)** | É do time vila até ser alvo dos lobos e ir pro time deles. |
| **Mechanics** | When attacked by wolves (and would die): does NOT die. Instead, role changes to `werewolf`, becomes a wolf team member, joins the wolf pack. When LYNCHED: same — does NOT die, role changes to `werewolf`. Witch POISON kills normally (no conversion). Seer sees Cursed as Village until conversion. Moderator wakes the Cursed every night, even after conversion, to show them the V/W signal. |

#### `doppelganger` — Doppelgänger / Doppelgänger
| Field | Value |
|-------|-------|
| Team | Village initially, then becomes target's team |
| Pts | -2 |
| Type | Official Expansion |
| Wake | Night 1 only (to pick target) |
| **Description (EN)** | On the 1st night, pick a player. When they die, you secretly take over their role. |
| **Description (PT)** | Na 1ª noite escolha um jogador. Quando ele for eliminado, você se torna aquele papel. |
| **Mechanics** | Night 1: picks one target. `players.doppelganger_target_id` is set. While target is alive, Doppelgänger is on the Village team. When target dies (any cause — night kill, poison, lynch, soulmate chain), Doppelgänger's role is silently updated to the target's role, and they join the target's team. Seer sees Doppelgänger as Village until target dies. |
| **Alternate rule** | Doppelgänger instantly becomes the target's role on night 1. The original holder keeps their role. (Tilt mechanic — can be very unbalanced.) |

#### `lycan` — Lycan / Licano
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | -1 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | You are on the Village team, but you have wolf blood. The Seer sees you as a Werewolf. |
| **Description (PT)** | Você é da vila, mas tem sangue de lobo. A Vidente te enxerga como Lobisomem. |
| **Mechanics** | Appears as Werewolf to the Seer. Otherwise a normal Villager. |
| **Alternate rule** | In role-reveal games, the Lycan is shown to the players as a Werewolf when killed. |

#### `pacifist` — Pacifist / Pacifista
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +2 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | You always vote to keep players alive (NO). |
| **Description (PT)** | Você odeia violência. Seu voto no tribunal é SEMPRE pela absolvição (NÃO). |
| **Mechanics** | Forced `no` vote in every tribunal. Cannot choose otherwise. |
| **Alternate rule** | Pacifist may not nominate or second a nomination. |

#### `idiot` — Idiot / Idiota (da Vila)
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +2 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | You always vote to lynch players (YES). |
| **Description (PT)** | Seu voto no tribunal é SEMPRE pelo linchamento (SIM). |
| **Mechanics** | Forced `yes` vote in every tribunal. Cannot choose otherwise. |
| **Alternate rule** | The Idiot is randomly determined after the game starts — they don't know they're the Idiot. |

### 7.4 Werewolf Roles

#### `werewolf` — Werewolf / Lobisomem
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -6 |
| Type | Official |
| Wake | Every night, with other wolves |
| **Description (EN)** | Each night, wake with the other wolves and choose a victim together. |
| **Description (PT)** | Toda noite, acorde com os lobos e escolham em conjunto alguém para eliminar. |
| **Mechanics** | Wolves must all agree on the same target. Cannot target another wolf. Night 1: recognition only, no kill. |

#### `wolf_cub` — Wolf Cub / Filhote de Lobo
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -8 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | If you die, the wolves enter frenzy and kill TWO victims the next night. |
| **Description (PT)** | Se você morrer, os lobos entram em frenesi e escolhem DUAS vítimas na noite seguinte. |
| **Mechanics** | When the Wolf Cub dies (any cause), `trg_wolf_cub_death` sets `rooms.wolves_frenzy = true`. Next night, wolves must select EXACTLY 2 distinct victims. Frenzy flag is cleared after resolution. |

#### `alpha_wolf` — Alpha Wolf / Lobo Alfa
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -9 |
| Type | Official |
| Wake | Every night, with wolves (plus one-shot infect action) |
| **Description (EN)** | Once per game, you can transform the wolves' victim into a Werewolf instead of killing them. |
| **Description (PT)** | Uma vez por jogo, você pode transformar a vítima dos lobos em um Lobisomem em vez de matá-la. |
| **Mechanics** | One-shot. Action type `alpha_infect`. If the wolves' target is the Alpha infect target, the target's role is updated to `werewolf` (NOT killed). Infected player sees the alpha infection banner. After use, `has_used_power = true` for the Alpha Wolf. |

#### `lone_wolf` — Lone Wolf / Lobo Solitário
| Field | Value |
|-------|-------|
| Team | **Independent** (NOT wolf team) |
| Pts | -5 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | You wake with the wolves, but you only win if you are the LAST player standing. |
| **Description (PT)** | Toda noite, acorde com os lobos. Você só ganha se for o último jogador. |
| **Mechanics** | Wakes with wolves (sees them, they see Lone Wolf). Wins only if alive_count = 1 (and that's Lone Wolf) OR alive_count ≤ 2 with no team-wolves alive. NOT counted in `v_wolves` for wolf win parity. Suppresses `villagers_win` until Lone Wolf is dead. |

#### `sorceress` — Sorceress / Feiticeira
| Field | Value |
|-------|-------|
| Team | Wolf (counted in `v_wolves` for win condition) |
| Pts | -3 |
| Type | Official |
| Wake | Each night, separately (does NOT wake with wolves) |
| **Description (EN)** | Each night, search for the Seer. The wolves don't know who you are, and the Seer sees you as a Villager. |
| **Description (PT)** | Toda noite, procure pela Vidente. Os lobos não sabem quem você é, e a Vidente te enxerga como Aldeão. |
| **Mechanics** | Points at a player each night. Moderator tells them if the target is the Seer. Does NOT wake with the wolves — wolves don't know who the Sorceress is. The Seer sees the Sorceress as Village. |
| **Alternate rule** | The Sorcerer is shown who the wolves are on the first night. |

#### `minion` — Minion / Servo
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -6 |
| Type | Official |
| Wake | (only on night 1 to be informed) |
| **Description (EN)** | On the first night, the wolves choose a player to be the Minion. You know who the wolves are but you do not wake with them. |
| **Description (PT)** | Na primeira noite os lobisomens escolhem alguém para ser o servo. Você sabe quem são os lobisomens mas você não acorda com eles. |
| **Mechanics** | On night 1, the wolves point at one player to be the Minion. The Minion joins the wolf team, sees the wolves, but does NOT wake with them. The Seer sees the Minion as a Villager. If the Minion has another special role, that role remains intact. |
| **Alternate rule** | The Minion card is dealt as a regular role and shown to the Minion AND to the wolves. The card prevents the Minion from having a dual role. |

#### `bad_wolf` — Bad Wolf / Lobo Mau
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -9 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | If you are in the game, the wolves may kill 2 adjacent players. |
| **Description (PT)** | Se você estiver no jogo, os lobisomens podem eliminar dois jogadores adjacentes. |
| **Mechanics** | Wolves may choose 2 ADJACENT players (seated next to each other) as their kill. This is a permanent boost to the wolf team while the Bad Wolf is alive. |

#### `dire_wolf` — Dire Wolf / Lobo Aproveitador
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -4 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | On the first night, choose a "companion" player. If that player is eliminated, you are eliminated. |
| **Description (PT)** | A cada noite acorde com os outros lobisomens. Na primeira noite escolha o jogador para ser seu companheiro. Você é eliminado se esse jogador for eliminado. |
| **Mechanics** | Night 1: chooses a companion. The Dire Wolf dies if its companion dies. This creates a hidden bond within the wolf pack. |

#### `fruit_brute` — Fruit Brute / Lobo Vegetariano
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -3 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | On the first night, wake with the other wolves. While there are other wolves in the game, do not wake on subsequent nights. |
| **Description (PT)** | Na primeira noite acorde com os outros lobisomens. Enquanto houver outros lobisomens no jogo. Não acorde nas noites subsequentes. |
| **Mechanics** | Wakes night 1 to see other wolves, but on subsequent nights, the Fruit Brute does NOT wake. This is a "liability" wolf — they know who the wolves are but are isolated from night coordination. |

#### `wolverine` — Wolverine
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -4 |
| Type | Official |
| Wake | Every night, with wolves |
| **Description (EN)** | Each night, wake with the other wolves. If you are the last wolf, you cannot kill at night. |
| **Description (PT)** | A cada noite, acorde com os outros Lobisomens. Se você for o último Lobisomem no jogo, não conseguirá eliminar um jogador a noite. |
| **Mechanics** | Standard wolf, but with a critical weakness: if the Wolverine is the last wolf alive, it cannot perform the night kill. |

#### `virginia_wolf` — Virginia Wolf / "Quem Tem Medo do Lobo Mau?"
| Field | Value |
|-------|-------|
| Team | Wolf |
| Pts | -2 |
| Type | Official |
| Wake | Night 1 only (to pick partner) |
| **Description (EN)** | On the first night, pick a player. If you die, that player also dies. |
| **Description (PT)** | Na primeira noite, escolha um jogador. Se você for eliminada, essa pessoa morre junto. |
| **Mechanics** | Night 1: picks a partner. The partner does NOT know they were chosen. If Virginia Wolf dies (any cause), the partner dies too (of a broken heart, like a soulmate). |

### 7.5 Independent Roles

#### `cupid` — Cupid / Cupido
| Field | Value |
|-------|-------|
| Team | Independent |
| Pts | -3 |
| Type | Official |
| Wake | Night 1 only |
| **Description (EN)** | On the 1st night, pick two players. If one dies, the other dies of heartbreak. |
| **Description (PT)** | Na 1ª noite, escolha dois jogadores. Se um for eliminado, o outro também será eliminado. |
| **Mechanics** | Night 1: picks 2 players, who become soulmates. Both `soulmate_id` fields are set. From then on, if one dies, the other dies (death chain handled by `trg_soulmate_death` trigger). |
| **Alternate rules** | Cupid is dealt as an extra card. After picking, Cupid receives the leftover card and BECOMES that role. OR: Moderator randomly picks the soulmates, so no one knows who they are except themselves. |

#### `cult_leader` — Cult Leader / Líder de Culto
| Field | Value |
|-------|-------|
| Team | Independent (own win: cult domination) |
| Pts | +1 |
| Type | Official |
| Wake | Each night |
| **Description (EN)** | Each night, convert one player to the cult. If all living players are in the cult, you win! |
| **Description (PT)** | Toda noite, escolhe alguém para entrar no culto. Se todos os jogadores fizerem parte do culto, você ganha. |
| **Mechanics** | Each night, converts one alive player to the cult (`in_cult = true`). Wins if all alive non-moderator, non-cult-leader players have `in_cult = true`. The Cult Leader is implicitly "in the cult." |
| **Alternate rule** | If the Cult Leader dies, the first cult member they picked becomes the new Cult Leader. |

#### `tanner` — Tanner / Curtidor
| Field | Value |
|-------|-------|
| Team | Independent |
| Pts | -2 |
| Type | Official |
| Wake | Never |
| **Description (EN)** | You hate your life. You win if the village lynchs you. |
| **Description (PT)** | Você ganha o jogo se conseguir ser linchado pela vila. |
| **Mechanics** | Wins only if LYNCHED (killed by tribunal vote, NOT by night kill, poison, or other means). Death event must be `event_type = 'lynch'`. The Tanner win has the HIGHEST priority — checked first, before any other win condition. |

#### `hoodlum` — Hoodlum / Bandido
| Field | Value |
|-------|-------|
| Team | Independent |
| Pts | 0 |
| Type | Official |
| Wake | Night 1 only |
| **Description (EN)** | On the 1st night, pick two players. You win if both are dead at the end of the game and you are still alive. |
| **Description (PT)** | Na primeira noite, escolha dois jogadores. Se eles forem eliminados e você continuar vivo, ao final do jogo, você ganha. |
| **Mechanics** | Night 1: picks 2 players. Wins if at game end, both picked players are dead AND the Hoodlum is still alive. Normal win conditions for other teams still apply, so the Hoodlum needs the Village to win (otherwise the game may end before both targets die). |
| **Alternate rule** | Picks 4 players, and if Hoodlum is still alive when all 4 are dead, Hoodlum wins instantly and all other teams (except possibly Cult Leader) lose. |

#### `vampire` — Vampire / Vampiro
| Field | Value |
|-------|-------|
| Team | **Vampires** (third major team) |
| Pts | -7 |
| Type | Official |
| Wake | Each night |
| **Description (EN)** | Each night, choose a victim. If that victim is nominated during the day, they die instantly in the middle of the day. |
| **Description (PT)** | Toda noite escolhem um alvo. Se, durante o dia, ele for para votação, ele morre instantaneamente. |
| **Mechanics** | Each night, vampires pick a victim. The victim is NOT revealed until a nomination occurs. If the victim is ever nominated, they die instantly mid-day. Vampires cannot be killed by werewolves (they're a separate team). With 3 major teams, vampires or werewolves must wipe out both other teams to win. |
| **Special role** | In a vampire game, the Hunter becomes a "Vampire Hunter" — when killed by Vampires, automatically kills the Vampire closest to them. |

### 7.6 Conditional / Non-card Roles

#### Soulmates (Almas Gêmeas) — not a separate role
| Field | Value |
|-------|-------|
| Type | (Condition assigned by Cupid) |
| **Description (EN)** | There are no cards for Soulmates. They are chosen by Cupid on the first night. |
| **Description (PT)** | Não há cartas para Almas Gêmeas. São escolhidos pelo Cupido na 1ª noite. |
| **Mechanics** | The two players chosen by Cupid become soulmates. If one dies, the other dies of heartbreak. If both are on the Village team, they win with the Village. If both are on the Werewolf team, they win with the Werewolves. If on different teams, they form their own team and win only if they are the last two alive. The Soulmates may have any other role in addition to being a Soulmate. |

#### `moderator` — Moderator / Mestre
| Field | Value |
|-------|-------|
| Type | (host only, not a player) |
| **Description (EN)** | The Moderator runs the game. Not a player. |
| **Description (PT)** | O Mestre/Moderador conduz o jogo. Não é um jogador. |
| **Mechanics** | Cannot be targeted, cannot vote, cannot die. Excluded from all game logic. May have UI affordances (host controls, role peek, etc.). |

### 7.7 Fan-Made Roles (NOT in the official rulebook)

These roles were created by the community or the project. They are NOT part of the Ultimate Werewolf rulebook.

#### `marksman` — Marksman / Atirador
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +2 |
| Type | **Fan-Made** (this project) |
| Wake | (day action during `discussion` phase) |
| **Description (EN)** | Once per game, during the day, you can shoot a player before the tribunal. |
| **Description (PT)** | Uma vez por jogo, durante o dia, você pode atirar em um jogador antes do tribunal. |
| **Mechanics** | Day action during `day_step = 'discussion'`. Calls `marksman_shoot(p_room_id, p_target_id)`. One-shot (`has_used_power` flag). Cannot shoot self. Kill is instant. Triggers `check_game_over`. |

#### `squire` — Squire / Escudeiro
| Field | Value |
|-------|-------|
| Team | Village |
| Pts | +1 |
| Type | **Fan-Made** (this project) |
| Wake | Never |
| **Description (EN)** | If the Prince dies, you take his place and become the new Prince. |
| **Description (PT)** | Se o Príncipe morrer, você assume seu lugar e se torna o novo Príncipe. |
| **Mechanics** | Passive role. When the Prince dies (any cause — night kill, poison, lynch, soulmate chain), the alive Squire's role is updated to `prince`. Squire promotion is deferred until ALL deaths in the current resolution are processed (to handle simultaneous Prince+Squire death during frenzy). |

---

## 8. Seer & Aura Seer Vision Reference

### 8.1 Seer vision (`is_werewolf: true/false`)

| Role | Seer sees as Werewolf? | Reason |
|------|------------------------|--------|
| `villager` | ❌ No | Plain villager |
| `seer` | ❌ No | Village |
| `apprentice_seer` | ❌ No | Village |
| `witch` | ❌ No | Village |
| `aura_seer` | ❌ No | Village |
| `bodyguard` | ❌ No | Village |
| `priest` | ❌ No | Village |
| `hunter` | ❌ No | Village |
| `huntress` | ❌ No | Village |
| `prince` | ❌ No | Village |
| `martyr` | ❌ No | Village |
| `tough_guy` | ❌ No | Village |
| `mayor` | ❌ No | Village |
| `ghost` | ❌ No | Village |
| `mason` | ❌ No | Village |
| `old_witch` | ❌ No | Village |
| `drunk` (before reveal) | ❌ No | Drunk acts as Villager |
| `drunk` (after reveal, real role is X) | (depends on X) | Real role's vision |
| `diseased` | ❌ No | Village |
| `cursed` (not converted) | ❌ No | Cursed appears as Village until conversion |
| `cursed` (after conversion) | ✅ Yes | Now a Werewolf |
| `doppelganger` (target alive) | ❌ No | Doppelgänger appears as Village until target dies |
| `doppelganger` (target dead) | (depends on copied role) | Copied role's vision |
| `lycan` | ✅ Yes | Lycan appears as Werewolf to Seer (wolf blood) |
| `pacifist` | ❌ No | Village |
| `idiot` | ❌ No | Village |
| `werewolf` | ✅ Yes | Werewolf |
| `wolf_cub` | ✅ Yes | Werewolf |
| `alpha_wolf` | ✅ Yes | Werewolf |
| `lone_wolf` | ✅ Yes | Lone Wolf counts as Werewolf for Seer |
| `sorceress` | ❌ No | Seer sees Sorceress as Village (she's hidden) |
| `minion` | ❌ No | Seer sees Minion as Village |
| `bad_wolf` | ✅ Yes | Werewolf |
| `dire_wolf` | ✅ Yes | Werewolf |
| `fruit_brute` | ✅ Yes | Werewolf |
| `wolverine` | ✅ Yes | Werewolf |
| `virginia_wolf` | ✅ Yes | Werewolf |
| `cupid` | ❌ No | Independent, but not "werewolf" |
| `cult_leader` | ❌ No | Independent |
| `tanner` | ❌ No | Independent |
| `hoodlum` | ❌ No | Independent |
| `vampire` | ✅ Yes | (in our app, Vampire is treated as a "werewolf" for Seer vision — adjust if implementing actual Vampire team) |
| `marksman` | ❌ No | Village |
| `squire` | ❌ No | Village |
| `moderator` | n/a | Cannot be targeted |

**Seer vision implementation (current code):**
```sql
is_werewolf = target.role IN ('werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'lycan')
```

### 8.2 Aura Seer vision (`is_special: true/false`)

`is_special` is `true` when the target's role is NOT one of:
`('villager', 'werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf')`

So the Aura Seer considers `lycan`, `cursed` (until converted), `doppelganger` (until target dies), and all other "special" roles as special. Werewolves and their variants are considered "common."

| Role | Aura Seer sees as Special? |
|------|----------------------------|
| `villager` | ❌ No (common) |
| `werewolf` | ❌ No (common) |
| `wolf_cub` | ❌ No (common) |
| `alpha_wolf` | ❌ No (common) |
| `lone_wolf` | ❌ No (common) |
| `lycan` | ✅ Yes (special — though it's "wolf blood") |
| `cursed` (not converted) | ✅ Yes (special) |
| `cursed` (converted) | ❌ No (now a common werewolf) |
| `doppelganger` (target alive) | ✅ Yes (special) |
| `doppelganger` (target dead) | depends on copied role |
| All other roles | ✅ Yes (special) |

---

## 9. Death Causes and How They Are Revealed

### 9.1 `cause` values

When a player dies, the death is recorded in `last_event.victims[].cause`:

| Cause | Meaning | Triggers |
|-------|---------|----------|
| `lobisomem` | Killed by wolves | Wolf kill pass (after all wolf checks) |
| `veneno` | Killed by witch poison | Witch poison pass (after all wolf checks) |
| `linchamento` | Killed by tribunal vote | `host_execute_accused` or `resolve_day_vote` |
| `soulmate` | Died of heartbreak | Soulmate death chain trigger |

### 9.2 Visibility rules

- **Host (moderator)** sees the cause of every death.
- **Regular players** see WHO died, but NOT WHY (cause is hidden).
- The `DayAnnouncement` component receives an `isHost` prop to switch display mode.

### 9.3 Special death effects

| Role dying | Effect |
|------------|--------|
| `hunter` | `game_state.hunter_pending = true` — Hunter gets revenge shot |
| `prince` (lynched) | Prince survives (Prince exception, `prince_reveal` day_step) |
| `prince` (other cause) | Alive Squire promoted to Prince |
| `wolf_cub` | `rooms.wolves_frenzy = true` — next night, wolves kill 2 |
| `diseased` (wolf kill) | `game_state.diseased_skip_wolves = true` — next night, wolves skip |
| `cursed` (wolf attack or lynch) | Role changes to `werewolf`, not dead |
| `doppelganger` (any cause) | Doesn't die — but role-copy may apply (when TARGET dies) |
| `cupid` (any cause) | Cupid's soulmates remain bound (Cupid's death doesn't break the chain) |
| Any player with soulmate | Soulmate dies too (death chain) |
| Any player with blessing | Blessing consumed; if blessing was the only thing protecting, player survives |

---

## 10. Official vs Fan-Made Classification

### 10.1 Official Core Roles (from Ultimate Werewolf rulebook, Ted Alspach / Pegasus Spiele)

| Category | Roles |
|----------|-------|
| **Village Core** | `villager`, `seer`, `apprentice_seer`, `witch`, `aura_seer`, `bodyguard`, `priest`, `hunter`, `huntress`, `prince`, `martyr`, `tough_guy`, `mayor`, `ghost`, `mason`, `old_witch`, `drunk`, `lycan`, `pacifist`, `idiot` |
| **Wolf Team** | `werewolf`, `wolf_cub`, `alpha_wolf`, `lone_wolf`, `sorceress`, `minion`, `bad_wolf`, `dire_wolf`, `fruit_brute`, `wolverine`, `virginia_wolf` |
| **Independent** | `cupid`, `cult_leader`, `tanner`, `hoodlum` |
| **Vampires (third team)** | `vampire` |

### 10.2 Official Expansion Roles (from supplementary rules and expansions)

| Category | Roles |
|----------|-------|
| **Village Expansions** | `diseased` |
| **Switching Teams** | `cursed`, `doppelganger` |

### 10.3 Fan-Made Roles (NOT in any official rulebook — created for this project)

| Category | Roles |
|----------|-------|
| **Village Fan-Made** | `marksman`, `squire` |

### 10.4 Classification rationale

When adding a new role, you MUST decide:
1. Is this role from the Ultimate Werewolf rulebook? → Use the official mechanics verbatim.
2. Is this role from a known expansion? → Reference the expansion source.
3. Is this role created for this project? → Document it as Fan-Made and add original mechanics.

Fan-made roles must NOT break existing mechanics. They must integrate cleanly into the WAKE_ORDER, win conditions, and death resolution.

---

## 11. Variant Rules (Optional)

These are optional variants. The app supports some, but not all.

### 11.1 Reveal modes

| Mode | What is shown to players on death |
|------|------------------------------------|
| `total` | Full role name (e.g., "Werewolf") |
| `team` | Only the team ("Village", "Werewolves", "Independent") |
| `hidden` | Nothing — just that the player died |

Default for new games: `team`.

### 11.2 Role revealing

By default, the Moderator reveals the specific role of each player after they die. Variants:

| Variant | Rule |
|---------|------|
| **Reveal Werewolf/Villager Only** | Reveal only if the player was a Werewolf, not the specific role. |
| **Team Reveals** | Reveal only the team (Werewolf, Villager, Vampire, Cult, etc.). |
| **No Reveal** | Nothing is revealed except that the player is dead. |

### 11.3 Variable Roles/Werewolves

Some roles (Lone Wolf, Idiot) benefit if they "might" be in the game. In variable mode, certain roles are mixed with extra Villagers and randomly discarded, so the actual composition is unknown. Important: always include at least one Seer and at least one Werewolf.

### 11.4 Voting variants

| Variant | Rule |
|---------|------|
| **Two Player Nominations (Big Brother)** | First two nominated and seconded players are voted on. The most-voted is lynched. Ties → both lynched. |
| **The Process of Elimination** | Players declare each other "safe" in a chain. The last unsafe player is lynched. |
| **Secret Ballot (Survivor Style)** | Players write names; most votes = lynched. Ties → revote among tied. |
| **1, 2, 3, Point! (German Style)** | Moderator counts down and everyone points at once. Most fingers = lynched. |

### 11.5 Dice rolling for daily changes

A 2d6 roll determines a daily variant. Chart:

| Roll | Variant |
|------|---------|
| 2 | Wolf target becomes a new Werewolf next night |
| 3 | First nominated and seconded player is instantly lynched (no vote) |
| 4 | Two lynchings instead of one |
| 6-8 | No variant |
| 9 | Same as previous day |
| 10 | Process of Elimination |
| 11 | No discussion except for nominating and seconding |
| 12 | Wolf target loses special ability instead of dying |

### 11.6 The Amulet of Protection (NOT yet implemented in our app)

A special role that protects one player. The Amulet holder is called first at night, can pass it to another player. If the Amulet holder is killed, they survive. The Amulet is destroyed if the holder declines to pass or passes to themselves. (Complex — recommend against implementing without playtesting.)

### 11.7 Fun Moderator variants

- **No Werewolves or Seer** — The Moderator pretends to call them and fakes the game. (Surprise — but risks player anger.)
- **All Werewolves** — Every player is a Werewolf. Instant Werewolf win.

---

## 12. Points & Scenario Balance

### 12.1 Point system

Each role has a point value. The sum of all points in a scenario determines which team is favored.

- **Positive points** — favor the Village (e.g., Seer +7, Witch +4)
- **Negative points** — favor the Werewolves (e.g., Werewolf -6, Wolf Cub -8)
- **Zero** — neutral (e.g., Hoodlum 0)
- **Independent** — depends on the role

### 12.2 Balance rules

- A **balanced** scenario has a point sum close to 0 (range: -3 to +3).
- **Sum < -3** → "Vantagem dos Lobos" (Werewolf advantage) — red indicator.
- **Sum > +3** → "Vantagem da Aldeia" (Village advantage) — green indicator.
- Between -3 and +3 → "Equilibrado" (balanced) — yellow indicator.

### 12.3 Tilting rules

| Group experience | Adjustment |
|------------------|------------|
| Many players don't know each other | Add +5 points in special roles to favor Village |
| Mostly experienced players | Add +5 points to favor Werewolves |

### 12.4 Role ratio rules

- For games with <15 players, the ratio of special roles (including Werewolves) to Villagers should be close to 1:1.
- For larger games (20+), the ratio can go up to 3:1.

### 12.5 Always include vanilla Villagers

Plain Villagers with no powers are essential — they keep the game going and provide a baseline. With full role reveal, you need more plain Villagers; with no reveal, you can have fewer.

---

## 13. Implementation Notes for AI Agents

### 13.1 When you add or modify a role

You MUST:

1. **Read the role's spec in this file FIRST.**
2. **Add the role to `src/lib/cards.ts`**:
   - `CARD_CATALOG` entry (id, name, points, team, description)
   - `ROLE_STYLE` (Tailwind classes for color)
   - `ROLE_LABEL` (PT label with emoji)
   - `ROLE_TRANSLATION` (EN → PT)
3. **Add the role to the `players_role_check` constraint** via a new migration.
4. **Add the role to the `night_actions_action_type_check` constraint** if it has night actions.
5. **Add the role to `WAKE_ORDER` in `src/app/game/[id]/page.tsx`** if it has night actions.
6. **Add the role to `STEP_TO_ACTION_TYPES` and `NIGHT_ROLE_LABELS`** if applicable.
7. **Add the role to the `availableNightRoles` query** in `src/app/game/[id]/page.tsx`.
8. **Add a host action log label** in `src/components/host-action-log.tsx`.
9. **Create the role panel** in `src/components/<role>-panel.tsx` if it has a night action.
10. **Add the role to `resolve_night`, `host_execute_accused`, `resolve_day_vote`** if it has death effects.
11. **Add a banner** for any role-conversion effects.
12. **Update `docs/architecture.md`** with what you added.
13. **Update this file's "Status note"** in section 7.2.

### 13.2 When you modify a death-effect mechanic

You MUST:

1. Verify the effect in the official rulebook (or in this file for fan-made).
2. Check that the change does NOT break:
   - `resolve_night` (3-pass order)
   - `check_game_over` (win conditions)
   - `trg_soulmate_death` (soulmate chain)
   - `trg_wolf_cub_death` (frenzy trigger)
3. Test that death events still trigger correct effects.

### 13.3 When you change the WAKE_ORDER

You MUST:

1. Justify the order based on dependencies (e.g., Witch must be AFTER wolves).
2. Verify the order is consistent with the official rulebook page 22 (Roll Calling Order).
3. Update `STEP_TO_ACTION_TYPES` to match.

### 13.4 When you change win conditions

You MUST:

1. Maintain the priority order (Tanner > Soulmates > Cult > Lone Wolf > Wolves > Village).
2. Update `check_game_over` SQL function to reflect the new logic.
3. Update `host_end_game` to handle the new `winner` value.
4. Update the win-condition display in the UI.

### 13.5 Schema constraints (current state)

| Constraint | Current values |
|------------|----------------|
| `players_role_check` | `werewolf`, `seer`, `witch`, `villager`, `mayor`, `prince`, `tanner`, `lycan`, `priest`, `bodyguard`, `aura_seer`, `wolf_cub`, `lone_wolf`, `alpha_wolf`, `cupid`, `cult_leader`, `mason`, `pacifist`, `idiot`, `sorceress`, `moderator`, `hunter`, `squire`, `marksman`, `diseased`, `cursed`, `doppelganger` |
| `night_actions_action_type_check` | `werewolf_kill`, `seer_investigate`, `witch_save`, `witch_poison`, `witch_skip`, `priest_bless`, `bodyguard_protect`, `aura_investigate`, `cult_convert`, `alpha_infect`, `cupid_match`, `sorceress_search`, `mason_recognition`, `hunter_shot`, `doppelganger_select` |

When you add a role with a new action, you MUST add that action to `night_actions_action_type_check` via a migration.

### 13.6 Wake order (current code)

```ts
WAKE_ORDER = [
  'masons',         // night 1 only
  'cupid',          // night 1 only
  'doppelganger',   // night 1 only
  'priest',         // one-shot
  'bodyguard',      // each night
  'wolves',         // each night
  'witch',          // after wolves resolved
  'seer',           // each night
  'aura_seer',      // each night
  'sorceress',      // each night (separately from wolves)
  'cult_leader',    // each night
]
```

When adding new roles with night actions, decide their place in this order based on dependencies.

---

## 14. Quick-Reference: What to Read Before What

| Task | Required reading |
|------|------------------|
| Add a new Village role (no night action) | Section 7.3 (Village roles), 8 (Vision refs), 13.1 (Implementation) |
| Add a new Village role (with night action) | Section 7.3, 8, 4 (Night phase), 13.1, 13.3 (WAKE_ORDER) |
| Add a new Wolf role | Section 7.4 (Wolf roles), 6 (Win conditions), 8, 13.1 |
| Add a new Independent role | Section 7.5, 6, 13.1, 13.4 (Win conditions) |
| Modify a death effect | Section 4.3 (3-pass order), 9 (Death causes), 13.2 |
| Add a new win condition | Section 6, 13.4 |
| Change the Seer vision | Section 8.1, 13.1 (Vision update) |
| Add a new night action type | Section 13.5 (constraint), 4 (Night phase) |
| Add a new scenario role combination | Section 12 (Points & balance), 10 (Classification) |
| Add a new variant rule | Section 11 (Variants), 13.1 |

---

## Appendix A: Glossary of Terms

| Term | Meaning |
|------|---------|
| **Aldeia** | Village (Portuguese) |
| **Alcance do Lobo** | Wolf pack reach (how many wolves can wake) |
| **Consensus** | When all wolves agree on the same target |
| **Convert** | To change a player's team (Cursed, Alpha Wolf infect, Cult Leader) |
| **Frenzy** | When Wolf Cub dies — wolves kill 2 next night |
| **Lynch** | Day execution by tribunal vote |
| **Reveal** | What is shown to players about a dead player's role |
| **Soulmate** | Bonded pair chosen by Cupid — one dies, other dies of heartbreak |
| **Vidente** | Seer (Portuguese) |

---

## Appendix B: Document Maintenance

When you change this file:
1. **Update the "Status note"** in section 7.2 to reflect the current implementation state.
2. **Add an entry to the changelog at the bottom** of this file.
3. **Update `docs/architecture.md`** with cross-references to this file.

## Changelog

- **v1.0 (2026-07-19)** — Initial creation. Includes all 50+ roles from the official Ultimate Werewolf rulebook (English + Portuguese) plus the 2 fan-made roles (`marksman`, `squire`) and the 26 implemented roles. 11-point section, 14 sections, 7 appendices, 30+ tables.
