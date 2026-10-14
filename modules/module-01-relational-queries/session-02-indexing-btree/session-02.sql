-- =====================================================================
-- Session 1.2: Indexing Mechanics & The Anatomy of a B-Tree
-- Database Fundamentals (DB 101)
-- =====================================================================
-- Run with: make psql   (then \i or paste each part)
-- Tip: \timing on   and   \pset pager off

-- ---------------------------------------------------------------------
-- PART 1: Peeking Inside a B-Tree (pageinspect)
-- ---------------------------------------------------------------------

DROP INDEX IF EXISTS idx_orders_order_number;
CREATE INDEX idx_orders_order_number ON orders (order_number);

-- Metapage: where is the root, and how tall is the tree?
-- Notice: 'root' = block number of root page, 'level' = tree height (0 = root is a leaf)
SELECT * FROM bt_metap('idx_orders_order_number');

-- Index size vs heap size
SELECT
    pg_size_pretty(pg_relation_size('orders')) AS heap_size,
    pg_size_pretty(pg_relation_size('idx_orders_order_number')) AS index_size;

-- Root page stats (replace 3 with the 'root' value from bt_metap if different)
SELECT * FROM bt_page_stats('idx_orders_order_number', (SELECT root FROM bt_metap('idx_orders_order_number')));

-- Root / interior page items: ctid here points to a CHILD INDEX PAGE, not a heap row
SELECT itemoffset, ctid, itemlen, data
FROM bt_page_items('idx_orders_order_number', (SELECT root FROM bt_metap('idx_orders_order_number')))
LIMIT 10;

-- Leaf page items: ctid here is the HEAP (page, line pointer) of the row
-- Block 1 is normally the first leaf page.
SELECT itemoffset, ctid, itemlen, data
FROM bt_page_items('idx_orders_order_number', 1)
LIMIT 10;

-- Follow a leaf pointer into the heap: should return that exact order
-- SELECT * FROM orders WHERE ctid = '(0,1)';  -- substitute a ctid from the leaf query


-- ---------------------------------------------------------------------
-- PART 2: Composite Indexes & the Leftmost-Prefix Rule
-- ---------------------------------------------------------------------

DROP INDEX IF EXISTS idx_orders_user_status;
DROP INDEX IF EXISTS idx_orders_status_user;
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
CREATE INDEX idx_orders_status_user ON orders (status, user_id);
ANALYZE orders;

-- Q1: equality on both columns -> both indexes work
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42 AND status = 'completed';

-- Q2: filter on leading column of (user_id, status) only
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42;

-- Q3: filter on the SECOND column only. Which index can serve this, and how well?
-- Predict first: is (user_id, status) usable? Is (status, user_id) usable?
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';

-- Drop one index at a time and re-run Q2/Q3 to see the planner's fallback.
-- DROP INDEX idx_orders_user_status;
-- DROP INDEX idx_orders_status_user;


-- ---------------------------------------------------------------------
-- PART 3: Selectivity Cliff — Why Postgres Ignores Your Index
-- ---------------------------------------------------------------------

-- status = 'completed' matches ~43% of rows (3 of 7 buckets): index not worth it
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'completed';

-- user_id = 42 matches ~5 rows: index wins
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42;

-- Force the comparison: disable seq scan and see what the index scan would have cost
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'completed';
RESET enable_seqscan;
-- Compare 'Buffers: shared hit=' and execution time between the two plans.


-- ---------------------------------------------------------------------
-- PART 4: Partial Index (Index only what you query)
-- ---------------------------------------------------------------------

DROP INDEX IF EXISTS idx_orders_pending_partial;
CREATE INDEX idx_orders_pending_partial ON orders (created_at) WHERE status = 'pending';
DROP INDEX IF EXISTS idx_orders_created_full;
CREATE INDEX idx_orders_created_full ON orders (created_at);

SELECT
    indexrelid::regclass AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index
WHERE indexrelid IN ('idx_orders_pending_partial'::regclass, 'idx_orders_created_full'::regclass);

-- The predicate in the query must imply the index predicate to use it
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at DESC LIMIT 20;


-- ---------------------------------------------------------------------
-- PART 5: Expression Index (LOWER(email))
-- ---------------------------------------------------------------------

DROP INDEX IF EXISTS idx_users_email_lower;
DROP INDEX IF EXISTS idx_users_email;
CREATE INDEX idx_users_email ON users (email);   -- plain index, for contrast

-- Plain index cannot serve a function call on the column
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE LOWER(email) = 'user_1234@example.com';

CREATE INDEX idx_users_email_lower ON users (LOWER(email));
ANALYZE users;

-- Same query now: Seq Scan -> Index Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE LOWER(email) = 'user_1234@example.com';


-- ---------------------------------------------------------------------
-- BONUS: Close the loop from Session 1.1 (unindexed FK)
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM order_items WHERE order_id = 123;
-- CREATE INDEX idx_order_items_order_id ON order_items (order_id);
-- Re-run the EXPLAIN above and compare.

-- ---------------------------------------------------------------------
-- CLEANUP (optional)
-- ---------------------------------------------------------------------
-- DROP INDEX IF EXISTS idx_orders_order_number, idx_orders_user_status, idx_orders_status_user,
--     idx_orders_pending_partial, idx_orders_created_full, idx_users_email, idx_users_email_lower;
