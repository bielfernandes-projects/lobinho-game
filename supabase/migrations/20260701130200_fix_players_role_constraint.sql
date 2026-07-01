-- ============================================================
-- Fix players_role_check constraint to include new Lot 1 roles
-- ============================================================
ALTER TABLE public.players DROP CONSTRAINT IF EXISTS players_role_check;
ALTER TABLE public.players ADD CONSTRAINT players_role_check
  CHECK (role = ANY (ARRAY[
    'unassigned', 'villager', 'werewolf', 'seer', 'witch',
    'moderator', 'mayor', 'prince', 'tanner', 'lycan'
  ]));
