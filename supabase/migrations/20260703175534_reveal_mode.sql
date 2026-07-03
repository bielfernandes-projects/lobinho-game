-- Add reveal_mode column to rooms table for death info visibility
-- Values: 'total' (full disclosure), 'team' (team only), 'hidden' (nothing)

ALTER TABLE rooms ADD COLUMN reveal_mode TEXT NOT NULL DEFAULT 'total';
ALTER TABLE rooms ADD CONSTRAINT rooms_reveal_mode_check
  CHECK (reveal_mode IN ('total', 'team', 'hidden'));
