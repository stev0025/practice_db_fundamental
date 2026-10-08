-- seed_data.sql: Realistic E-Commerce / SaaS Dataset for DB 101 Lab
-- Generates:
--   20,000 Users
--    2,000 Products
--  100,000 Orders
--  250,000 Order Items
--   50,000 Audit Logs

\echo '==> Dropping existing tables if any...'
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS users CASCADE;

\echo '==> Creating schema...'

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID DEFAULT gen_random_uuid() NOT NULL,
    email VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'seller', 'admin')),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'pending')),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price_cents INT NOT NULL CHECK (price_cents >= 0),
    inventory_count INT NOT NULL DEFAULT 0 CHECK (inventory_count >= 0),
    tags TEXT[] DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    order_number VARCHAR(64) NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'cancelled', 'refunded')),
    total_amount_cents INT NOT NULL CHECK (total_amount_cents >= 0),
    created_at TIMESTAMPTZ NOT NULL,
    shipped_at TIMESTAMPTZ
);

CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price_cents INT NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id BIGINT NOT NULL,
    action VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

\echo '==> Generating 20,000 users...'
INSERT INTO users (email, full_name, role, status, metadata, created_at, updated_at)
SELECT 
    'user_' || i || '@example' || (CASE WHEN i % 5 = 0 THEN '.org' WHEN i % 3 = 0 THEN '.net' ELSE '.com' END),
    'User ' || i || ' ' || (ARRAY['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis'])[1 + (i % 8)],
    (ARRAY['customer', 'customer', 'customer', 'customer', 'seller', 'admin'])[1 + (i % 6)],
    (ARRAY['active', 'active', 'active', 'active', 'active', 'suspended', 'pending'])[1 + (i % 7)],
    jsonb_build_object(
        'plan', (ARRAY['free', 'starter', 'pro', 'enterprise'])[1 + (i % 4)],
        'login_count', (i * 7) % 500,
        'country', (ARRAY['US', 'DE', 'JP', 'GB', 'CA', 'FR', 'SG', 'AU'])[1 + (i % 8)],
        'preferences', jsonb_build_object('newsletter', (i % 2 = 0), 'dark_mode', (i % 3 = 0))
    ),
    NOW() - (interval '1 day' * (i % 730)),
    NOW() - (interval '1 hour' * (i % 100))
FROM generate_series(1, 20000) AS i;

\echo '==> Generating 2,000 products...'
INSERT INTO products (sku, title, category, price_cents, inventory_count, tags, is_active, created_at)
SELECT
    'SKU-' || LPAD(i::text, 6, '0'),
    'Product ' || i || ' ' || (ARRAY['Pro', 'Ultra', 'Mini', 'Max', 'Standard', 'Lite', 'Plus'])[1 + (i % 7)],
    (ARRAY['Electronics', 'Books', 'Home & Kitchen', 'Apparel', 'Sports', 'Toys', 'Automotive'])[1 + (i % 7)],
    (100 + ((i * 37) % 50000)), -- 1.00 to 500.00 USD
    ((i * 13) % 1000),
    ARRAY[(ARRAY['sale', 'clearance', 'bestseller', 'new-arrival', 'refurbished'])[1 + (i % 5)]],
    (i % 15 != 0),
    NOW() - (interval '1 day' * (i % 365))
FROM generate_series(1, 2000) AS i;

\echo '==> Generating 100,000 orders...'
INSERT INTO orders (order_number, user_id, status, total_amount_cents, created_at, shipped_at)
SELECT
    'ORD-' || TO_CHAR(NOW() - (interval '1 minute' * (i * 5)), 'YYYYMMDD') || '-' || LPAD(i::text, 7, '0'),
    1 + ((i * 17) % 20000), -- foreign key to users
    (ARRAY['pending', 'processing', 'completed', 'completed', 'completed', 'cancelled', 'refunded'])[1 + (i % 7)],
    500 + ((i * 73) % 95000),
    NOW() - (interval '1 minute' * (i * 5)),
    CASE WHEN (i % 7) IN (2, 3, 4) THEN NOW() - (interval '1 minute' * (i * 5)) + interval '2 days' ELSE NULL END
FROM generate_series(1, 100000) AS i;

\echo '==> Generating 250,000 order items...'
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
SELECT
    1 + (i % 100000), -- foreign key to orders
    1 + ((i * 31) % 2000), -- foreign key to products
    1 + (i % 5),
    200 + ((i * 19) % 20000)
FROM generate_series(1, 250000) AS i;

\echo '==> Generating 50,000 audit logs...'
INSERT INTO audit_logs (entity_type, entity_id, action, payload, created_at)
SELECT
    (ARRAY['order', 'user', 'product', 'auth'])[1 + (i % 4)],
    1 + ((i * 13) % 20000),
    (ARRAY['create', 'update', 'delete', 'login', 'status_change', 'password_reset'])[1 + (i % 6)],
    jsonb_build_object(
        'ip', '192.168.1.' || (i % 254),
        'client', (ARRAY['ios-app', 'android-app', 'web-chrome', 'web-firefox', 'internal-api'])[1 + (i % 5)],
        'latency_ms', (i * 3) % 350
    ),
    NOW() - (interval '2 minute' * i)
FROM generate_series(1, 50000) AS i;

\echo '==> Analyzing tables to update query planner statistics...'
VACUUM ANALYZE users;
VACUUM ANALYZE products;
VACUUM ANALYZE orders;
VACUUM ANALYZE order_items;
VACUUM ANALYZE audit_logs;

\echo '==> Seed complete! Table summary:'
SELECT 
    relname AS table_name,
    n_live_tup AS estimated_rows,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
