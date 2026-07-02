-- Lot 3: Soulmate death chain trigger
-- When a player dies, their soulmate dies too (heartbreak)

CREATE OR REPLACE FUNCTION public.after_player_death_soulmate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_alive = false AND NEW.soulmate_id IS NOT NULL THEN
    IF (SELECT is_alive FROM players WHERE id = NEW.soulmate_id) = true THEN
      UPDATE players SET is_alive = false, last_event = 'coracao_partido'
      WHERE id = NEW.soulmate_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_soulmate_death ON players;
CREATE OR REPLACE TRIGGER trg_soulmate_death
AFTER UPDATE OF is_alive ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.after_player_death_soulmate();
