CREATE UNLOGGED TABLE public."Clientes" (
    "Id" integer NOT NULL,
    "Limite" integer NOT NULL,
    "SaldoInicial" integer NOT NULL
);

ALTER TABLE public."Clientes" OWNER TO postgres;

ALTER TABLE public."Clientes" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Clientes_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE UNLOGGED TABLE public."Transacoes" (
    "Id" integer NOT NULL,
    "Valor" integer NOT NULL,
    "ClienteId" integer NOT NULL,
    "Tipo" varchar(1) NOT NULL,
    "Descricao" text NOT NULL,
    "RealizadoEm" timestamp DEFAULT NOW()
) WITH (fillfactor = 90);

ALTER TABLE public."Transacoes" OWNER TO postgres;

ALTER TABLE public."Transacoes" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Transacoes_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

COPY public."Clientes" ("Id", "Limite", "SaldoInicial") FROM stdin;
1	100000	0
2	80000	0
3	1000000	0
4	10000000	0
5	500000	0
\.

COPY public."Transacoes" ("Id", "Valor", "ClienteId", "Tipo", "Descricao", "RealizadoEm") FROM stdin;
\.

-- Critical fix for sequences
SELECT pg_catalog.setval('public."Clientes_Id_seq"', (SELECT MAX("Id") FROM public."Clientes"), true);
SELECT pg_catalog.setval('public."Transacoes_Id_seq"', (SELECT MAX("Id") FROM public."Transacoes"), true);

ALTER TABLE ONLY public."Clientes"
    ADD CONSTRAINT "PK_Clientes" PRIMARY KEY ("Id");

ALTER TABLE ONLY public."Transacoes"
    ADD CONSTRAINT "PK_Transacoes" PRIMARY KEY ("Id");

-- Optimized composite index for transaction retrieval
CREATE INDEX "IX_Transacoes_ClienteId_Id_Desc" ON public."Transacoes" USING btree ("ClienteId", "Id" DESC);

-- -- Add BRIN index for time-based queries (if used)
-- CREATE INDEX "IX_Transacoes_RealizadoEm" ON public."Transacoes" USING brin ("RealizadoEm");

-- -- Cluster table by time if mostly time-ordered inserts
-- CLUSTER public."Transacoes" USING "IX_Transacoes_RealizadoEm";

-- Optimized function with proper transaction handling
CREATE OR REPLACE FUNCTION public.InsertTransacao(
    IN id INTEGER,
    IN valor INTEGER,
    IN tipo VARCHAR(1),
    IN descricao VARCHAR(10)
) RETURNS INTEGER AS $$
DECLARE
    novo_saldo INTEGER;
    cliente_exists BOOLEAN;
BEGIN
    -- Check if the client exists
    SELECT EXISTS (SELECT 1 FROM public."Clientes" WHERE "Id" = id) INTO cliente_exists;
    IF NOT cliente_exists THEN
        RETURN NULL;
    END IF;

    -- Update balance with the original's condition to allow credits unconditionally
    UPDATE public."Clientes"
    SET "SaldoInicial" = "SaldoInicial" + (valor * CASE tipo WHEN 'c' THEN 1 ELSE -1 END)
    WHERE "Id" = id
    AND (
        ("SaldoInicial" + (valor * CASE tipo WHEN 'c' THEN 1 ELSE -1 END) >= -"Limite")
        OR (valor * CASE tipo WHEN 'c' THEN 1 ELSE -1 END) > 0
    )
    RETURNING "SaldoInicial" INTO novo_saldo;

    -- Insert transaction only if the client exists (handled above) and balance was updated
    IF FOUND THEN
        INSERT INTO public."Transacoes" ("Valor", "Tipo", "Descricao", "ClienteId", "RealizadoEm")
        VALUES (valor, tipo, descricao, id, NOW());
    ELSE
        -- If update failed (debit exceeds limit), return current balance without updating
        SELECT "SaldoInicial" INTO novo_saldo FROM public."Clientes" WHERE "Id" = id;
    END IF;

    RETURN novo_saldo;
END;
$$ LANGUAGE plpgsql;

-- Optimized balance retrieval function using jsonb for efficiency
CREATE OR REPLACE FUNCTION public.GetSaldoClienteById(IN id INTEGER)
RETURNS TABLE (
    Total INTEGER,
    Limite INTEGER,
    data_extrato TIMESTAMP,
    transacoes jsonb
) AS $$
BEGIN
  RETURN QUERY 
  SELECT 
    c."SaldoInicial" AS Total,
    c."Limite" AS Limite,
    NOW()::timestamp AS data_extrato,
    COALESCE((
        SELECT jsonb_agg(t)
        FROM (
            SELECT "Valor", "Tipo", "Descricao", "RealizadoEm"
            FROM public."Transacoes"
            WHERE "ClienteId" = id
            ORDER BY "Id" DESC
            LIMIT 10
        ) t
    ), '[]'::jsonb) AS transacoes
  FROM public."Clientes" c
  WHERE c."Id" = id;
END;
$$ LANGUAGE plpgsql;