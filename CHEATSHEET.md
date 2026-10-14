# Database Fundamentals Cheatsheet

### Session 1.1: Schema Modeling & The 8KB Page
1. **The 8KB Page:** PostgreSQL reads and writes data in 8KB disk blocks; rows are unsorted heap tuples referenced by `ctid = (page, line_pointer)`.
2. **Column Alignment:** Order columns widest-to-narrowest (`BIGINT`/`TIMESTAMPTZ` → `INT` → `SMALLINT` → `BOOLEAN` → `VARCHAR`) to eliminate CPU padding waste.
3. **Data Types:** Use `BIGINT` (cents) over `FLOAT` for money, always default to `TIMESTAMPTZ`, and avoid 32-bit `INT` IDs to prevent the 2.14B wraparound cliff.
4. **Foreign Key Indexes:** PostgreSQL never auto-indexes foreign keys; always index FK columns to prevent full table scans and lock contention on parent deletes.

### Session 1.2: Indexing Mechanics & The B-Tree
1. **B-Tree Shape:** An index is its own array of 8KB pages: metapage (`bt_metap`) → root → interior → leaf. Non-leaf `ctid` = child *index* page; leaf `ctid` = *heap* `(page, row)`. Fan-out is ~150-200 per page, so 100k rows = 3 levels and a lookup reads ~3 index pages + 1 table page.
2. **Heap vs Index:** The table is unordered (an UPDATE writes a new row copy elsewhere); the index is the sorted copy of `(key → ctid)`. The PK is just a unique index. `ORDER BY` sorts the result, or walks a sorted index to skip the sort. (ClickHouse sorts the table itself and keeps a sparse index; Postgres does not.)
3. **Leftmost Prefix:** `(a, b)` serves `a` and `a, b`, never `b` alone. Put the always-filtered `=` column first, then range/sort columns (`(status, created_at)` covers `status` and `status + created_at > ?`). Don't keep a redundant single-column index that a composite already covers.
4. **Selectivity Cliff:** An index saves *page reads*, not rows examined. `status='pending'` (~14%) touches all 1,177 table pages anyway, so Seq Scan (4.6 ms) beat the bitmap index (8.5 ms). Index wins at ~0.01% (one order: 1,177 pages → ~4, ~100x faster).
5. **ORDER BY + LIMIT:** A sorted index plus `LIMIT n` reads ~n entries (`Index Scan Backward` for `DESC`) instead of sorting everything. A partial index (`WHERE status='pending'`) means every entry walked is a valid result.
6. **Reading EXPLAIN:** Read innermost line first. Check `Buffers` (pages touched), `rows` estimate vs actual (big gap = stale stats), `Rows Removed by Filter`. Cost numbers are only for comparing plans.
