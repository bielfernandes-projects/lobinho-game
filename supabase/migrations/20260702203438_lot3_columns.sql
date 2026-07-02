-- Lot 3: Cupid + Cult Leader columns and constraints
-- 1. soulmate_id + in_cult on players
-- 2. Updated night_actions constraint
-- 3. Updated players_role_check
-- 4. Updated rooms status check

-- 1. Add soulmate_id and in_cult columns
ALTER TABLE players ADD COLUMN IF NOT EXISTS soulmate_id UUID REFERENCES players(id) ON DELETE SET NULL;
ALTER TABLE players ADD COLUMN IF NOT EXISTS in_cult BOOLEAN NOT NULL DEFAULT false;

-- 2. Update night_actions constraint to include cult_convert
ALTER TABLE night_actions DROP CONSTRAINT IF EXISTS night_actions_action_type_check;
ALTER TABLE night_actions ADD CONSTRAINT night_actions_action_type_check
  CHECK (action_type IN (
    'werewolf_kill', 'seer_investigate', 'witch_save', 'witch_poison',
    'priest_bless', 'bodyguard_protect', 'aura_investigate', 'cult_convert'
  ));

-- 3. Update players_role_check to include all lot2 + lot3 roles
ALTER TABLE players DROP CONSTRAINT IF EXISTS players_role_check;
ALTER TABLE players ADD CONSTRAINT players_role_check
  CHECK (role = ANY (ARRAY[
    'unassigned', 'villager', 'werewolf', 'seer', 'witch',
    'moderator', 'mayor', 'prince', 'tanner', 'lycan',
    'priest', 'bodyguard', 'aura_seer', 'cupid', 'cult_leader'
  ]));

-- 4. Update rooms status constraint to include new winner types
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_status_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_status_check
  CHECK (status IN ('waiting', 'playing', 'finished',
    'finished_villagers_win', 'finished_wolves_win', 'finished_tanner_win',
    'finished_soulmates_win', 'finished_cult_win'));
