-- Create a dedicated API schema for PostgREST endpoints
CREATE SCHEMA IF NOT EXISTS api;

CREATE OR REPLACE FUNCTION api.get_extrato(cliente_id integer)
RETURNS jsonb AS $$
DECLARE 
  result jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public."Clientes" WHERE "Id" = cliente_id) THEN
    result := jsonb_build_object(
      'saldo', jsonb_build_object(
                  'total', (SELECT "SaldoInicial" FROM public."Clientes" WHERE "Id" = cliente_id),
                  'limite', (SELECT "Limite" FROM public."Clientes" WHERE "Id" = cliente_id),
                  'data_extrato', NOW()
                ),
      'ultimas_transacoes', COALESCE((
         SELECT jsonb_agg(t)
         FROM (
             SELECT "Valor", "Tipo", "Descricao", "RealizadoEm"
             FROM public."Transacoes"
             WHERE "ClienteId" = cliente_id
             ORDER BY "Id" DESC
             LIMIT 10
         ) t
      ), '[]'::jsonb)
    );
  ELSE
    result := jsonb_build_object(
      'saldo', jsonb_build_object(
                  'total', 0,
                  'limite', 0,
                  'data_extrato', NOW()
                ),
      'ultimas_transacoes', '[]'::jsonb
    );
  END IF;
  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION api.insert_transacao(
    cliente_id integer,
    valor integer,
    tipo text,
    descricao text
)
RETURNS jsonb AS $$
DECLARE
  updated_saldo integer;
  limite integer;
BEGIN
  -- Validate transaction type (must be either 'c' or 'd')
  IF tipo NOT IN ('c', 'd') THEN
    RAISE EXCEPTION 'Invalid transaction type. Allowed values are "c" or "d".';
  END IF;
  -- Validate description: non-null, non-empty and maximum 10 characters
  IF descricao IS NULL OR length(descricao) = 0 OR length(descricao) > 10 THEN
    RAISE EXCEPTION 'Invalid description. It must be non-empty and at most 10 characters long.';
  END IF;
  -- Validate transaction value must be greater than 0
  IF valor <= 0 THEN
    RAISE EXCEPTION 'Invalid valor. Must be greater than 0.';
  END IF;
  
  -- Execute the original transaction logic.
  updated_saldo := public.InsertTransacao(cliente_id, valor, tipo, descricao);
  
  -- If the returned saldo is null, the client was not found or the update failed.
  IF updated_saldo IS NULL THEN
    RAISE EXCEPTION 'Client not found or transaction failed.';
  END IF;
  
  -- Retrieve the client's limit.
  SELECT "Limite" INTO limite FROM public."Clientes" WHERE "Id" = cliente_id;
  
  -- Return a JSON object with lowercase keys that match your load test expectation.
  RETURN jsonb_build_object(
    'id', cliente_id,
    'limite', limite,
    'saldo', updated_saldo
  );
END;
$$ LANGUAGE plpgsql VOLATILE;