-- Role groups, defined ONCE for the database. Keep in sync with src/lib/night-steps.ts (WOLF_ROLES).
--   pack_roles()      roles that wake with the wolves, vote on the victim and are seen as wolves
--   wolf_team_roles() roles that count as the wolf team for win conditions
CREATE OR REPLACE FUNCTION public.pack_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY['werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'lone_wolf']::text[]
$function$;

CREATE OR REPLACE FUNCTION public.wolf_team_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY['werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'sorceress', 'minion']::text[]
$function$
