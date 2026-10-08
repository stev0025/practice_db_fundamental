-- 01-init.sql: Lab Extensions & Initialization
-- Runs automatically on container first boot via /docker-entrypoint-initdb.d/

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_buffercache";
CREATE EXTENSION IF NOT EXISTS "pageinspect";

-- Verify extensions
SELECT extname, extversion FROM pg_extension;
