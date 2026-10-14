-- =====================================================================
-- Session 1.4: High-Performance Queries, Window Functions & CTE Traps
-- Database Fundamentals (DB 101)
-- =====================================================================
-- Run with: make psql   (paste each part)
-- Tip: \timing on   and   \pset pager off
-- Setup: make sure Session 1.3 indexes exist (safe to re-run)
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
ANALYZE orders; ANALYZE order_items; ANALYZE users;

-- ---------------------------------------------------------------------
-- PART 1: The Three Join Algorithms
-- ---------------------------------------------------------------------

-- Few rows on the outer side -> Nested Loop (for each outer row, look up inner via index)
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.full_name, o.order_number
FROM users u JOIN orders o ON o.user_id = u.id
WHERE u.id = 42;

-- Many rows on both sides -> Hash Join (build a hash table of one side, probe with the other)
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.full_name, o.order_number
FROM users u JOIN orders o ON o.user_id = u.id;
-- Look for: 'Hash' node with 'Buckets', 'Batches', 'Memory Usage'.

-- Both sides already sorted (or cheap to sort) -> Merge Join. Force it to see it:
SET enable_hashjoin = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.full_name, o.order_number
FROM users u JOIN orders o ON o.user_id = u.id;
RESET enable_hashjoin;

-- Rule of thumb:
--   Nested Loop : few outer rows + indexed inner lookup
--   Hash Join   : big unsorted inputs, equality join, needs memory (work_mem)
--   Merge Join  : both inputs sorted, handles huge inputs


-- ---------------------------------------------------------------------
-- PART 2: Memory & Temp Files (work_mem)
-- ---------------------------------------------------------------------
SHOW work_mem;   -- 4MB in this lab

-- Sort that fits in memory
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount_cents DESC;
-- Look for: 'Sort Method: quicksort  Memory: ...kB' or 'external merge  Disk: ...kB'

-- Starve it of memory and watch it spill to disk
SET work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount_cents DESC;
-- Look for: 'Sort Method: external merge  Disk: ...kB' and 'temp read/written' in Buffers.

-- Same for a hash join: Batches > 1 means the hash table did not fit
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM order_items oi JOIN orders o ON o.id = oi.order_id;
RESET work_mem;
-- Takeaway: work_mem is PER sort/hash node PER query, so 100 connections x several nodes
-- can exhaust RAM. (Session 3.2 covers sizing.)


-- ---------------------------------------------------------------------
-- PART 3: Top-N per Group ("latest 3 orders per user")
-- ---------------------------------------------------------------------

-- Approach A: correlated subquery (re-runs the inner query for EVERY outer row)
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.created_at
FROM orders o
WHERE o.user_id < 2000
  AND (SELECT count(*) FROM orders o2
       WHERE o2.user_id = o.user_id AND o2.created_at > o.created_at) < 3;

-- Approach B: window function (one pass, no self-join)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, created_at
FROM (
    SELECT id, user_id, created_at,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM orders
    WHERE user_id < 2000
) t
WHERE rn <= 3;
-- Compare Execution Time and Buffers between A and B.

-- Window function cousins: how ties are handled
SELECT user_id, status, total_amount_cents,
       ROW_NUMBER() OVER w AS row_num,   -- 1,2,3,4 (always unique)
       RANK()       OVER w AS rnk,       -- 1,1,3,4 (ties share, then gap)
       DENSE_RANK() OVER w AS dense_rnk  -- 1,1,2,3 (ties share, no gap)
FROM orders
WHERE user_id = 42
WINDOW w AS (PARTITION BY user_id ORDER BY status);

-- Running total with SUM() OVER
SELECT id, created_at, total_amount_cents,
       SUM(total_amount_cents) OVER (ORDER BY created_at) AS running_total
FROM orders
WHERE user_id = 42
ORDER BY created_at;


-- ---------------------------------------------------------------------
-- PART 4: CTEs — Inlined vs MATERIALIZED
-- ---------------------------------------------------------------------
-- Since PG 12, a CTE used ONCE is inlined (treated like a subquery) by default.

-- Inlined: the filter user_id = 42 is pushed INTO the CTE, so the index is used
EXPLAIN (ANALYZE, BUFFERS)
WITH recent AS (SELECT * FROM orders WHERE created_at > now() - interval '30 days')
SELECT * FROM recent WHERE user_id = 42;

-- Materialized: the CTE runs fully first and is stored; the outer filter cannot go inside
EXPLAIN (ANALYZE, BUFFERS)
WITH recent AS MATERIALIZED (SELECT * FROM orders WHERE created_at > now() - interval '30 days')
SELECT * FROM recent WHERE user_id = 42;
-- Look for: 'CTE Scan on recent' with 'Rows Removed by Filter'.

-- When MATERIALIZED helps: the CTE is expensive AND referenced several times
-- (or you want it to run once as an optimisation barrier). Otherwise leave the default.


-- ---------------------------------------------------------------------
-- PART 5: Join Traps (Cartesian & Fan-out)
-- ---------------------------------------------------------------------
SET statement_timeout = '5s';   -- safety net for this part

-- Trap 1: forgot the join condition. DO NOT RUN WITHOUT 'EXPLAIN' (no ANALYZE)!
-- Look at the estimated rows: 20,000 x 100,000 = 2,000,000,000
EXPLAIN SELECT count(*) FROM users u, orders o;

-- Small, safe version: 100 users x 1000 orders = 100,000 rows from an unintended product
SELECT count(*) FROM (SELECT * FROM users WHERE id <= 100) u,
                     (SELECT * FROM orders WHERE id <= 1000) o;

-- Trap 2: fan-out. Each order has ~2.5 items, so joining to order_items repeats the order row
-- and SUM() over-counts.
SELECT SUM(total_amount_cents) AS correct_total FROM orders;

SELECT SUM(o.total_amount_cents) AS inflated_total
FROM orders o JOIN order_items oi ON oi.order_id = o.id;

-- Fix: aggregate the many-side first, or sum from the one-side only
SELECT SUM(o.total_amount_cents) AS correct_again
FROM orders o
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);

RESET statement_timeout;


-- ---------------------------------------------------------------------
-- CLEANUP (optional)
-- ---------------------------------------------------------------------
-- RESET ALL;
