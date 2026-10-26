# Database Fundamentals Cheatsheet

### Session 1.1: Schema Modeling & The 8KB Page
1. **The 8KB Page:** PostgreSQL reads and writes data in 8KB disk blocks; rows are unsorted heap tuples referenced by `ctid = (page, line_pointer)`.
2. **Column Alignment:** Order columns widest-to-narrowest (`BIGINT`/`TIMESTAMPTZ` → `INT` → `SMALLINT` → `BOOLEAN` → `VARCHAR`) to eliminate CPU padding waste.
3. **Data Types:** Use `BIGINT` (cents) over `FLOAT` for money, always default to `TIMESTAMPTZ`, and avoid 32-bit `INT` IDs to prevent the 2.14B wraparound cliff.
4. **Foreign Key Indexes:** PostgreSQL never auto-indexes foreign keys; always index FK columns to prevent full table scans and lock contention on parent deletes.

### Session 1.2: Indexing Mechanics & The B-Tree
1. **B-Tree:** A sorted copy of `(key → ctid)` in its own pages (root → interior → leaf), so a lookup reads ~3 index pages plus 1 table page.
2. **Leftmost Prefix:** `(a, b)` serves `a` and `a, b`, never `b` alone; put the always-filtered `=` column first.
3. **Selectivity Cliff:** Indexes save page reads, so at ~14% of rows (every page touched) a Seq Scan beats them.
4. **ORDER BY + LIMIT:** A sorted index with `LIMIT n` reads ~n entries and skips the sort.

### Session 1.3: EXPLAIN (ANALYZE, BUFFERS) & Cost Model
1. **Read Plans:** Start at the innermost line; compare `rows=` (estimate) to `actual rows=`, and wrap DML in `BEGIN; ... ROLLBACK;` since `ANALYZE` really runs it.
2. **Cost Formula:** Seq Scan = `relpages*1.0 + reltuples*0.01 + reltuples*0.0025`; index plans add `random_page_cost` (4.0) per table page, so they lose as matches grow.
3. **Covering Index:** `INCLUDE` the selected columns for an Index Only Scan with `Heap Fetches: 0` and fewer buffers.
4. **Diagnose Slow Queries:** Bad estimates → `ANALYZE`; high `read` → disk-bound; all `hit` but slow → CPU-bound (too many rows).
