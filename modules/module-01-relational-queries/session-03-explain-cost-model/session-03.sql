-- =====================================================================
-- Session 1.3: Demystifying EXPLAIN (ANALYZE, BUFFERS) & Planner Cost Models
-- Database Fundamentals (DB 101)
-- =====================================================================
-- Run with: make psql   (paste each part)
-- Tip: \timing on   and   \pset pager off

-- ---------------------------------------------------------------------
-- PART 1: EXPLAIN vs EXPLAIN ANALYZE
-- ---------------------------------------------------------------------

-- EXPLAIN only shows the planner's GUESS. The query is NOT executed.
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- EXPLAIN ANALYZE actually RUNS the query and adds real numbers.
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 42;

-- Compare: 'rows=' (estimate) vs 'actual ... rows=' (reality).
-- Compare: 'cost=' (abstract units) vs 'actual time=' (real milliseconds).

-- WARNING: ANALYZE really executes. For INSERT/UPDATE/DELETE, wrap in a
-- transaction and roll back so you don't change data:
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) UPDATE orders SET total_amount_cents = total_amount_cents WHERE user_id = 42;
ROLLBACK;


-- ---------------------------------------------------------------------
-- PART 2: Where does "cost=" come from? (Do the maths yourself)
-- ---------------------------------------------------------------------

-- The planner's price list (defaults):
SELECT name, setting
FROM pg_settings
WHERE name IN ('seq_page_cost', 'random_page_cost', 'cpu_tuple_cost',
               'cpu_index_tuple_cost', 'cpu_operator_cost');

-- The planner's knowledge of the table (from the last ANALYZE):
SELECT relname, relpages, reltuples FROM pg_class WHERE relname = 'orders';

-- Seq Scan cost formula:
--   relpages * seq_page_cost            (read every page)
-- + reltuples * cpu_tuple_cost          (process every row)
-- + reltuples * cpu_operator_cost       (apply the WHERE filter to every row)
SELECT
    relpages * current_setting('seq_page_cost')::float
  + reltuples * current_setting('cpu_tuple_cost')::float
  + reltuples * current_setting('cpu_operator_cost')::float AS my_calculated_cost
FROM pg_class WHERE relname = 'orders';

-- Now compare with the planner's number (look at the first cost= value after '..'):
EXPLAIN SELECT * FROM orders WHERE status = 'pending';
-- They should match. The planner is just arithmetic over table statistics.


-- ---------------------------------------------------------------------
-- PART 3: The Scan-Type Ladder (selectivity changes the plan)
-- ---------------------------------------------------------------------
-- orders.user_id has 20,000 distinct values, ~5 orders each (uniform).

DROP INDEX IF EXISTS idx_orders_user_id;
CREATE INDEX idx_orders_user_id ON orders (user_id);
ANALYZE orders;

-- ~0.005% of rows -> expect Index Scan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 42;

-- ~1% of rows -> expect Bitmap Heap Scan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id < 200;

-- ~10% of rows -> Bitmap or Seq Scan (the crossover zone)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id < 2000;

-- ~50% of rows -> expect Seq Scan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id < 10000;

-- For each: note scan type, 'Heap Blocks', Buffers, and Execution Time.


-- ---------------------------------------------------------------------
-- PART 4: Index Only Scan (never touch the table)
-- ---------------------------------------------------------------------

-- Only user_id is in idx_orders_user_id, but we also ask for total_amount_cents,
-- so Postgres must visit the table for every match.
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, total_amount_cents FROM orders WHERE user_id < 200;

-- Put the extra column INSIDE the index (INCLUDE = stored in leaves, not sorted).
DROP INDEX IF EXISTS idx_orders_user_cover;
CREATE INDEX idx_orders_user_cover ON orders (user_id) INCLUDE (total_amount_cents);

-- Index Only Scan needs the visibility map to be up to date:
VACUUM orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, total_amount_cents FROM orders WHERE user_id < 200;
-- Look for: 'Index Only Scan' and 'Heap Fetches: 0'.
-- Compare 'Buffers' with the previous plan.


-- ---------------------------------------------------------------------
-- PART 5: Stale Statistics (the #1 cause of surprise bad plans)
-- ---------------------------------------------------------------------
-- Work on a COPY so the main tables stay untouched.

DROP TABLE IF EXISTS orders_stats_demo;
CREATE TABLE orders_stats_demo AS SELECT * FROM orders;
CREATE INDEX ON orders_stats_demo (status);
ALTER TABLE orders_stats_demo SET (autovacuum_enabled = false);  -- stop auto-ANALYZE
ANALYZE orders_stats_demo;

-- Baseline: planner knows 'refunded' is ~14%
EXPLAIN (ANALYZE) SELECT * FROM orders_stats_demo WHERE status = 'refunded';

-- Change the data distribution drastically, WITHOUT re-analyzing:
UPDATE orders_stats_demo SET status = 'refunded' WHERE status = 'completed';

-- Planner still believes 'refunded' is ~14%, but it is now ~57%.
-- Compare estimated 'rows=' with 'actual rows=':
EXPLAIN (ANALYZE) SELECT * FROM orders_stats_demo WHERE status = 'refunded';

-- Fix: refresh statistics
ANALYZE orders_stats_demo;
EXPLAIN (ANALYZE) SELECT * FROM orders_stats_demo WHERE status = 'refunded';
-- Estimate should now match reality (and the plan may switch to Seq Scan).

DROP TABLE orders_stats_demo;


-- ---------------------------------------------------------------------
-- PART 6: Reading I/O Timings (CPU-bound or disk-bound?)
-- ---------------------------------------------------------------------
-- track_io_timing = on in this lab, so BUFFERS output includes 'I/O Timings'.
--   shared hit  = page found in Postgres memory (shared_buffers)
--   shared read = page fetched from OS / disk
-- Run the same query twice and compare hit/read:
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM order_items WHERE product_id = 77;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM order_items WHERE product_id = 77;
-- Second run: reads become hits, time drops.

-- Diagnosis cheat table:
--   big gap estimate vs actual rows     -> stale stats (run ANALYZE)
--   high 'read', high I/O Timings       -> disk-bound (cold cache / too much data)
--   all 'hit', still slow               -> CPU-bound (too many rows processed)

-- ---------------------------------------------------------------------
-- CLEANUP (optional)
-- ---------------------------------------------------------------------
-- DROP INDEX IF EXISTS idx_orders_user_id, idx_orders_user_cover;
