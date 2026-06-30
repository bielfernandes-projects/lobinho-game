-- ============================================================
-- FIX: role column type — TEXT[] → TEXT
-- ============================================================
-- Se a coluna role foi criada acidentalmente como TEXT[] (array),
-- esta migration converte para TEXT mantendo dados existentes.
-- ============================================================

-- 1) Descobrir o tipo atual
DO $$
DECLARE
  v_typ TEXT;
BEGIN
  SELECT data_type INTO v_typ
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'players'
    AND column_name = 'role';

  IF v_typ IS NULL THEN
    RAISE NOTICE 'Coluna role nao existe — nada a fazer';
    RETURN;
  END IF;

  IF v_typ <> 'ARRAY' THEN
    RAISE NOTICE 'Coluna role ja e TEXT (type=%), nada a fazer', v_typ;
    RETURN;
  END IF;

  -- Se for array, converter para TEXT
  -- Primeiro converte arrays existentes para o primeiro elemento (se houver)
  ALTER TABLE players
    ALTER COLUMN role TYPE TEXT
    USING (
      CASE
        WHEN role IS NULL THEN NULL
        WHEN array_length(role, 1) IS NULL THEN NULL
        ELSE role[1]
      END
    );

  RAISE NOTICE 'Coluna role convertida de TEXT[] para TEXT com sucesso';
END $$;
