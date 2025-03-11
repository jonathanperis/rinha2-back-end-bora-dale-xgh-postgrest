DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
        CREATE ROLE web_anon NOLOGIN;
    END IF;
END
$$;

-- Grant basic privileges to the web_anon role so it can access the schema and tables.
GRANT CONNECT ON DATABASE rinha TO web_anon;

-- Grant privileges on the public schema
GRANT USAGE ON SCHEMA public TO web_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO web_anon;

-- If you're also exposing functions or tables in the api schema, grant privileges there as well:
GRANT USAGE ON SCHEMA api TO web_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA api GRANT SELECT ON TABLES TO web_anon;

-- Grant privileges on the Clientes table
GRANT SELECT, UPDATE ON public."Clientes" TO web_anon;

-- Grant privileges on the Transacoes table (required for inserting transactions)
GRANT INSERT, SELECT ON public."Transacoes" TO web_anon;

-- Grant usage on sequences (required for auto-incrementing IDs)
GRANT USAGE, SELECT ON SEQUENCE public."Clientes_Id_seq" TO web_anon;
GRANT USAGE, SELECT ON SEQUENCE public."Transacoes_Id_seq" TO web_anon;

-- Grant execute permission on the RPC function to web_anon
GRANT EXECUTE ON FUNCTION api.insert_transacao(integer, text, text, integer) TO web_anon;