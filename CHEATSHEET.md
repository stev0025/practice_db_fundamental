# Database Fundamentals Cheatsheet

### Session 1.1: Schema Modeling & The 8KB Page
1. **The 8KB Page:** PostgreSQL reads and writes data in 8KB disk blocks; rows are unsorted heap tuples referenced by `ctid = (page, line_pointer)`.
2. **Column Alignment:** Order columns widest-to-narrowest (`BIGINT`/`TIMESTAMPTZ` → `INT` → `SMALLINT` → `BOOLEAN` → `VARCHAR`) to eliminate CPU padding waste.
3. **Data Types:** Use `BIGINT` (cents) over `FLOAT` for money, always default to `TIMESTAMPTZ`, and avoid 32-bit `INT` IDs to prevent the 2.14B wraparound cliff.
4. **Foreign Key Indexes:** PostgreSQL never auto-indexes foreign keys; always index FK columns to prevent full table scans and lock contention on parent deletes.
