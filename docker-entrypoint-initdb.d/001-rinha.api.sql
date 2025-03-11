-- Create a dedicated API schema for PostgREST endpoints
CREATE SCHEMA IF NOT EXISTS api;

-- Create a function to mimic GET /clientes/{id}/extrato.
-- This function wraps the existing GetSaldoClienteById function from the public schema.
CREATE OR REPLACE FUNCTION api.get_extrato(p_cliente_id integer)
RETURNS TABLE (
  total integer,
  limite integer,
  data_extrato timestamp,
  transacoes jsonb
) AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public."Clientes" WHERE "Id" = p_cliente_id) THEN
    RETURN QUERY
      SELECT 
        c."SaldoInicial" AS total,
        c."Limite" AS limite,
        NOW()::timestamp AS data_extrato,
        COALESCE((
            SELECT jsonb_agg(t)
            FROM (
                SELECT "Valor", "Tipo", "Descricao", "RealizadoEm"
                FROM public."Transacoes"
                WHERE "ClienteId" = p_cliente_id
                ORDER BY "Id" DESC
                LIMIT 10
            ) t
        ), '[]'::jsonb) AS transacoes
      FROM public."Clientes" c
      WHERE c."Id" = p_cliente_id;
  ELSE
    RETURN QUERY
      SELECT 
        0 AS total,
        0 AS limite,
        NOW()::timestamp AS data_extrato,
        '[]'::jsonb AS transacoes;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Create a function to mimic POST /clientes/{id}/transacoes.
-- This function validates the input and then calls the existing InsertTransacao function.
-- It returns a JSON object with the client id, limite, and updated saldo.
CREATE OR REPLACE FUNCTION api.insert_transacao(
    p_cliente_id integer,
    p_valor integer,
    p_tipo text,
    p_descricao text
)
RETURNS jsonb AS $$
DECLARE
  updated_saldo integer;
  limite integer;
BEGIN
  -- Validate transaction type (must be either 'c' (credit) or 'd' (debit))
  IF p_tipo NOT IN ('c', 'd') THEN
    RAISE EXCEPTION 'Invalid transaction type. Allowed values are "c" or "d".';
  END IF;
  -- Validate description: non-null, non-empty and maximum 10 characters
  IF p_descricao IS NULL OR length(p_descricao) = 0 OR length(p_descricao) > 10 THEN
    RAISE EXCEPTION 'Invalid description. It must be non-empty and at most 10 characters long.';
  END IF;
  -- Validate transaction value must be greater than 0
  IF p_valor <= 0 THEN
    RAISE EXCEPTION 'Invalid valor. Must be greater than 0.';
  END IF;
  
  -- Execute the original transaction logic.
  updated_saldo := public.InsertTransacao(p_cliente_id, p_valor, p_tipo, p_descricao);
  
  -- If the returned saldo is null, the client was not found or the update failed.
  IF updated_saldo IS NULL THEN
    RAISE EXCEPTION 'Client not found or transaction failed.';
  END IF;
  
  -- Retrieve the client's limit.
  SELECT "Limite" INTO limite FROM public."Clientes" WHERE "Id" = p_cliente_id;
  
  -- Return a JSON object with lowercase keys that match your load test expectation.
  RETURN jsonb_build_object(
    'id', p_cliente_id,
    'limite', limite,
    'saldo', updated_saldo
  );
END;
$$ LANGUAGE plpgsql VOLATILE;