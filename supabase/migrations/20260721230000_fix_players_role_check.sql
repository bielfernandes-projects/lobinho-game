-- Repairs players_role_check. The earlier anchor-patching wrapped every role added after
-- 'doppelganger' into one ROW(...) element, so the database rejected all of them.
-- Explicit list = source of truth (keep in sync with src/lib/cards.ts).
ALTER TABLE players DROP CONSTRAINT IF EXISTS players_role_check;
ALTER TABLE players ADD CONSTRAINT players_role_check CHECK (role::text IN (
  'werewolf', 'seer', 'witch', 'villager', 'mayor', 'prince', 'tanner', 'lycan', 'priest',
  'bodyguard', 'aura_seer', 'wolf_cub', 'lone_wolf', 'alpha_wolf', 'cupid', 'cult_leader',
  'mason', 'pacifist', 'idiot', 'sorceress', 'moderator', 'hunter', 'squire', 'marksman',
  'diseased', 'cursed', 'doppelganger',
  'chupacabra', 'minion', 'huntress', 'tough_guy', 'martyr', 'apprentice_seer', 'old_witch',
  'drunk', 'dire_wolf', 'virginia_wolf', 'ghost'
));
