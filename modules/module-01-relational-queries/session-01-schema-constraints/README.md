# Session 1.1: Schema Modeling, Constraints & The 8KB Page

> **Module 1:** Relational & Query Foundations (Layer A)  
> **Duration:** 30 minutes  
> **Target Audience:** Half-Backend, Half-Platform Engineer  
> **Lab Script:** [session-01.sql](file:///home/steven/projects/practice_db_fundamental/modules/module-01-relational-queries/session-01-schema-constraints/session-01.sql)

---

## 1. Mental Model: What is a Table, Really?

In application code, we think of a table as an abstract list of objects or rows.  
In the PostgreSQL engine, **a table is an array of 8 Kilobyte (8192 bytes) pages on disk**:

```text
+-------------------------------------------------------------------------+
|                              8KB Page Layout                            |
+-------------------------------------------------------------------------+
|  PageHeaderData (24 bytes): LSN, Checksum, lower offset, upper offset  |
+-------------------------------------------------------------------------+
|  ItemId Array (Line Pointers: 4 bytes each)                            |
|  [ lp 1 ] [ lp 2 ] [ lp 3 ] ... ------> (grows downward)               |
+-------------------------------------------------------------------------+
|                                                                         |
|                          FREE SPACE (Unallocated)                       |
|                                                                         |
+-------------------------------------------------------------------------+
|                              <------ (grows upward)                     |
|  Tuple 3 (HeapTupleHeader + Data)                                       |
+-------------------------------------------------------------------------+
|  Tuple 2 (HeapTupleHeader + Data)                                       |
+-------------------------------------------------------------------------+
|  Tuple 1 (HeapTupleHeader + Data)                                       |
+-------------------------------------------------------------------------+
|  Special Space (Index-specific metadata, unused in standard heap)       |
+-------------------------------------------------------------------------+
```

Every row in PostgreSQL has a physical coordinate called a **`ctid`** (tuple identifier):
- `(0, 1)` means **Page 0, Line Pointer 1**.
- When an index points to a row, it doesn't store a pointer to the raw byte offset; it stores `(page_number, item_number)`.

---

## 2. Hands-on Walkthrough (Run in `make psql`)

To start this session, open an interactive PostgreSQL shell:
```bash
make psql
```

### Part 1: Inspecting Page 0 with `pageinspect`

Run this query to check how many 8KB pages make up the `users` table:
```sql
SELECT 
    relname,
    relpages,
    reltuples,
    pg_size_pretty(pg_relation_size(oid)) AS heap_size
FROM pg_class
WHERE relname = 'users';
```
*(Notice: 20,000 users occupy roughly 700+ pages of 8KB each).*

Now, peek at the actual raw header of **Page 0**:
```sql
SELECT * FROM page_header(get_raw_page('users', 0));
```
**What you are seeing:**
- `lsn`: The Log Sequence Number of the last WAL record that modified this 8KB page.
- `lower`: Byte offset where the line pointer array ends.
- `upper`: Byte offset where the actual tuple data begins (growing backwards from the end of the page).

Now look at the first 5 line pointers and tuple headers in Page 0:
```sql
SELECT 
    lp,
    lp_off,
    lp_len,
    t_ctid,
    t_xmin,
    t_xmax
FROM heap_page_items(get_raw_page('users', 0))
LIMIT 5;
```
**Takeaway:** Every single row has an ItemId pointer (`lp`) that points to a byte offset (`lp_off`) and byte length (`lp_len`), plus an MVCC header (`t_xmin`, `t_xmax`).

---

### Part 2: The Hidden Padding Trap (Column Alignment)

PostgreSQL aligns types on CPU boundaries:
- `BIGINT` & `TIMESTAMPTZ`: 8-byte aligned.
- `INTEGER`: 4-byte aligned.
- `SMALLINT`: 2-byte aligned.
- `BOOLEAN` / `CHAR`: 1-byte aligned.

If you place a `SMALLINT` right before a `BIGINT`, PostgreSQL is forced to insert **6 padding bytes of wasted dead space** per row to maintain 8-byte alignment!

Let's test this directly:
```sql
DROP TABLE IF EXISTS bad_alignment;
DROP TABLE IF EXISTS good_alignment;

-- Bad order: smallint (2) + bigint (8) + smallint (2) + bigint (8) -> 6 bytes wasted twice per row
CREATE TABLE bad_alignment (
    id1 SMALLINT,
    val1 BIGINT,
    id2 SMALLINT,
    val2 BIGINT
);

-- Good order: bigint (8) + bigint (8) + smallint (2) + smallint (2) -> 0 bytes wasted
CREATE TABLE good_alignment (
    val1 BIGINT,
    val2 BIGINT,
    id1 SMALLINT,
    id2 SMALLINT
);

INSERT INTO bad_alignment SELECT 1, 100, 2, 200 FROM generate_series(1, 100000);
INSERT INTO good_alignment SELECT 100, 200, 1, 2 FROM generate_series(1, 100000);

-- Compare physical disk size:
SELECT 
    'bad_alignment' AS table_name,
    pg_size_pretty(pg_relation_size('bad_alignment')) AS size,
    pg_relation_size('bad_alignment') AS bytes
UNION ALL
SELECT 
    'good_alignment' AS table_name,
    pg_size_pretty(pg_relation_size('good_alignment')) AS size,
    pg_relation_size('good_alignment') AS bytes;
```
**Observation:**
- `bad_alignment`: **5.8 MB** (approx)
- `good_alignment`: **4.2 MB** (approx)
- *That is a ~25% memory and disk reduction simply by ordering columns from largest to smallest type!*

---

### Part 3: Data Types — Real World Production Traps

#### 1. Currency & Floats (The Rounding Nightmare)
Run:
```sql
SELECT 
    (0.1::float + 0.2::float = 0.3::float) AS float_equality,
    (0.1::numeric + 0.2::numeric = 0.3::numeric) AS numeric_equality,
    (0.1::float + 0.2::float) AS float_exact_value;
```
- Floating-point arithmetic (`FLOAT`, `DOUBLE PRECISION`) uses IEEE 754 approximations: `0.1 + 0.2` becomes `0.30000000000000004`!
- **Rule:** Never store financial amounts or currency in `FLOAT`. Use `BIGINT` (e.g. `price_cents`) or `NUMERIC(12, 2)`.

#### 2. `TIMESTAMP` vs `TIMESTAMPTZ`
Run:
```sql
SHOW timezone;
SELECT 
    '2026-10-08 12:00:00'::timestamp AS bare_timestamp,
    '2026-10-08 12:00:00+00'::timestamptz AS utc_timestamptz;
```
- `timestamp without time zone` blindly discards timezone context. If your server is UTC and client is in EST or JST, dates drift.
- `timestamp with time zone` (`TIMESTAMPTZ`) always converts and stores the instant in UTC internally (both take 8 bytes).
- **Rule:** Almost always default to `TIMESTAMPTZ`.

#### 3. Primary Key Choice: `INT` vs `BIGINT`
- A standard 4-byte `INTEGER` primary key caps at **2,147,483,647** rows.
- High-profile outages (e.g., Shopify, Basecamp) occurred when `INT` IDs wrapped around in high-traffic audit/event tables.
- **Rule:** Primary keys and foreign keys referencing them should default to `BIGINT` (8 bytes) or UUIDv7.

---

### Part 4: The Unindexed Foreign Key Trap

In PostgreSQL, creating a `FOREIGN KEY` does **NOT** automatically create an index on the referencing column!

Check the indexes on `order_items`:
```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'order_items';
```
Notice:
- `order_items_pkey` exists on `id`.
- There is **no index** on `order_id` or `product_id`.

**Why this is a platform nightmare:**
1. If you run `DELETE FROM orders WHERE id = 123;`, PostgreSQL must verify whether child rows exist in `order_items`.
2. Because `order_items.order_id` has no index, PostgreSQL must execute a **full table scan on 250,000 order_items**!
3. Even worse: during that check, PostgreSQL acquires a `ShareLock` on `order_items`, blocking concurrent writes.

---

## 3. Platform & Production Takeaways

1. **Alignment Rule:** When defining schemas for tables expected to hold hundreds of millions of rows, order columns from widest to narrowest (`uuid`/`bigint`/`timestamptz` &rarr; `int` &rarr; `smallint` &rarr; `boolean`).
2. **Foreign Key Index Rule:** Always index foreign key columns unless the parent table is strictly write-never / delete-never.
3. **Database Consistency:** Prefer database constraints (`CHECK`, `NOT NULL`, `FOREIGN KEY`) over pure application-level validation. Application bugs can bypass validation; the database engine guarantees invariant safety.

---

## 4. Next Session

In **Session 1.2**, we will dive into **Indexing Mechanics & The Anatomy of a B-Tree**:
- How B-Tree search trees work on disk.
- Why the query planner ignores your indexes when selectivity is low.
- Multi-column index ordering and partial indexes.
