-- =====================================================================
-- Session 1.1: Schema Modeling, Constraints & The 8KB Page
-- Database Fundamentals (DB 101)
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1: The Invisible Made Visible — Peeking Inside the 8KB Page
-- ---------------------------------------------------------------------

-- Check how many 8KB pages make up the 'users' table
SELECT 
    relname,
    relpages,
    reltuples,
    pg_size_pretty(pg_relation_size(oid)) AS heap_size,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
WHERE relname = 'users';

-- Inspect the Page Header of Block 0 in the users table
-- Notice: lsn (Write-Ahead Log offset), checksum, lower, upper, special
SELECT * FROM page_header(get_raw_page('users', 0));

-- Look at the individual row pointers (ItemId) and tuple headers in Block 0
-- Notice: lp (Line Pointer), t_ctid (tuple identifier: block, offset), t_xmin, t_xmax
SELECT 
    lp,
    lp_off,
    lp_flags,
    lp_len,
    t_ctid,
    t_xmin,
    t_xmax
FROM heap_page_items(get_raw_page('users', 0))
LIMIT 10;


-- ---------------------------------------------------------------------
-- PART 2: Column Alignment & The "Hidden Padding" Experiment
-- ---------------------------------------------------------------------
-- PostgreSQL aligns columns on 1, 2, 4, or 8 byte boundaries.
-- Poor column ordering wastes disk space and shared_buffers memory!

DROP TABLE IF EXISTS bad_alignment;
DROP TABLE IF EXISTS good_alignment;

-- Bad order: smallint (2 bytes) + bigint (8 bytes) + smallint (2 bytes) + bigint (8 bytes)
-- Forces 6 bytes of padding after each smallint!
CREATE TABLE bad_alignment (
    id1 SMALLINT,
    val1 BIGINT,
    id2 SMALLINT,
    val2 BIGINT
);

-- Good order: bigint (8) + bigint (8) + smallint (2) + smallint (2)
-- Zero padding wasted!
CREATE TABLE good_alignment (
    val1 BIGINT,
    val2 BIGINT,
    id1 SMALLINT,
    id2 SMALLINT
);

-- Insert 100,000 rows into both tables
INSERT INTO bad_alignment
SELECT 1, 100, 2, 200 FROM generate_series(1, 100000);

INSERT INTO good_alignment
SELECT 100, 200, 1, 2 FROM generate_series(1, 100000);

-- Compare the physical table sizes!
SELECT 
    'bad_alignment' AS table_name,
    pg_size_pretty(pg_relation_size('bad_alignment')) AS table_size,
    pg_relation_size('bad_alignment') AS raw_bytes
UNION ALL
SELECT 
    'good_alignment' AS table_name,
    pg_size_pretty(pg_relation_size('good_alignment')) AS table_size,
    pg_relation_size('good_alignment') AS raw_bytes;


-- ---------------------------------------------------------------------
-- PART 3: Data Types — Trap vs Best Practice
-- ---------------------------------------------------------------------

-- Trap 1: FLOAT vs NUMERIC for currency
-- Notice: 0.1 + 0.2 in floating point
SELECT 
    (0.1::float + 0.2::float = 0.3::float) AS float_equality,
    (0.1::numeric + 0.2::numeric = 0.3::numeric) AS numeric_equality,
    (0.1::float + 0.2::float) AS float_exact_value;

-- Trap 2: TIMESTAMP vs TIMESTAMPTZ
-- Observe how TIMESTAMP ignores client timezones, while TIMESTAMPTZ normalizes to UTC internally
SHOW timezone;
SELECT 
    '2026-10-08 12:00:00'::timestamp AS bare_timestamp,
    '2026-10-08 12:00:00+00'::timestamptz AS utc_timestamptz;


-- ---------------------------------------------------------------------
-- PART 4: Constraints & Foreign Key Traps
-- ---------------------------------------------------------------------

-- 1. Test CHECK constraint violation
-- Should fail: price_cents must be >= 0
-- INSERT INTO products (sku, title, category, price_cents) VALUES ('FAIL-1', 'Invalid Product', 'Toys', -50);

-- 2. Foreign Key Cascade vs Restrict
-- In seed_data: orders -> users has ON DELETE RESTRICT
-- Attempting to delete a user with orders will fail immediately!
-- DELETE FROM users WHERE id = 1;

-- 3. The Unindexed Foreign Key Trap (Platform incident scenario)
-- Look at order_items: order_id references orders(id).
-- Is order_id indexed? Let's check!
SELECT 
    indexname, 
    indexdef 
FROM pg_indexes 
WHERE tablename = 'order_items';

-- Notice: Only order_items_pkey exists! 
-- order_id has NO INDEX. In Session 1.2 and Module 2, we will see why this triggers
-- full sequential scans and lock contention during deletions.
