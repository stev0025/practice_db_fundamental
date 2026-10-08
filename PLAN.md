# Database Fundamentals (DB 101) - Hands-on Curriculum Plan

> **Target Audience:** Half-Backend, Half-Platform Engineer  
> **Philosophy:** No engine theory dumps. Mental Model &rarr; Execute &rarr; Inspect Internals ("Make me SEE it") &rarr; Production Incident Context.  
> **Structure:** 16 bite-sized, 30-minute hands-on lab sessions.

---

## Architecture Overview

```text
               +----------------------------------------------------+
               |                   Developer Host                   |
               +----------------------------------------------------+
                               |                   |
                     Port 6432 |         Port 5432 | Port 6379
                               v                   v       v
+-------------------------------------------------------------------------------+
| Docker Bridge Network (db101_net)                                             |
|                                                                               |
|   +-----------------------+              +--------------------------------+   |
|   |   db101_pgbouncer     |  Pooled Conn |         db101_postgres         |   |
|   |     (PgBouncer)       |------------->|        (PostgreSQL 16)         |   |
|   |  Transaction Pooling  |              |  - pg_stat_statements         |   |
|   |  Port 5432 (int:5432) |              |  - pg_buffercache              |   |
|   +-----------------------+              |  - pageinspect                 |   |
|                                          |  - track_io_timing = on        |   |
|                                          +--------------------------------+   |
|                                                                               |
|   +-----------------------+                                                   |
|   |      db101_redis      |                                                   |
|   |       (Redis 7)       |                                                   |
|   |  AOF Persistence      |                                                   |
|   |  Memory Limit: 64MB   |                                                   |
|   +-----------------------+                                                   |
+-------------------------------------------------------------------------------+
```

---

## Detailed Curriculum Roadmap (16 Sessions @ 30 Mins)

### Module 1: Relational & Query Foundations (Layer A)

#### Session 1.1: Schema Modeling, Constraints & The 8KB Page
* **Mental Model:** A table isn't an abstract spreadsheet; it is an array of 8KB disk pages containing row pointers and tuple headers. Constraints aren't validation boilerplate; they are engine-level consistency invariants.
* **Invisible Made Visible:**
  - Raw page header inspection using `pageinspect` (`get_raw_page`, `page_header`).
  - Constraint violations and foreign key index locks.
  - Column ordering and data type alignment padding (how ordering types saves disk space).
* **Hands-on Lab:**
  1. Inspect the 8KB page structure of the `users` table.
  2. Test `CHECK`, `NOT NULL`, `UNIQUE`, and `FOREIGN KEY` cascades.
  3. Compare disk footprint: `NUMERIC` vs `INT`/`BIGINT`, `TIMESTAMP` vs `TIMESTAMPTZ`, and `JSONB` vs normalized columns.
* **Platform/Backend Takeaway:** Why missing an FK index causes table locks during parent deletes, and how column ordering can save gigabytes at scale.

---

#### Session 1.2: Indexing Mechanics & The Anatomy of a B-Tree
* **Mental Model:** A B-Tree index is an ordered, balanced search tree of `(key, ctid)` tuples pointing to heap pages. Index scans require random I/O; sequential scans require sequential I/O.
* **Invisible Made Visible:**
  - B-tree root, interior, and leaf pages using `bt_page_items` from `pageinspect`.
  - The "Leftmost Prefix" rule in composite indexes.
  - Why Postgres chooses a sequential scan even when an index exists (selectivity cliff).
* **Hands-on Lab:**
  1. Inspect B-Tree leaf pages to see physical `(data_value, ctid)` pointers.
  2. Compare single-column vs multi-column indexes (`(user_id, status)` vs `(status, user_id)`).
  3. Build a partial index (`WHERE status = 'pending'`) and measure index size reduction.
  4. Create an expression index (`LOWER(email)`) and observe the planner switch from Seq Scan to Index Scan.
* **Platform/Backend Takeaway:** Why your index wasn't used in production despite existing, and how partial indexes save 90% of index RAM.

---

#### Session 1.3: Demystifying `EXPLAIN (ANALYZE, BUFFERS)` & Planner Cost Models
* **Mental Model:** `EXPLAIN` shows the planner's guess; `EXPLAIN (ANALYZE, BUFFERS)` runs the query and records exact execution time, row count errors, and memory/disk buffer hits (`shared hit`, `read`, `written`).
* **Invisible Made Visible:**
  - `shared hit` (memory cache hit) vs `read` (OS page cache / NVMe read).
  - Seq Scan vs Index Scan vs Index Only Scan vs Bitmap Index Scan.
  - Estimated cost formula: `(disk_pages * seq_page_cost) + (cpu_tuples * cpu_tuple_cost)`.
* **Hands-on Lab:**
  1. Run queries with varying selectivity across 100k orders and observe the transition: Index Scan &rarr; Bitmap Heap Scan &rarr; Sequential Scan.
  2. Force an Index Only Scan by creating a covering index with `INCLUDE`.
  3. Interpret `track_io_timing` read times.
* **Platform/Backend Takeaway:** How to diagnose whether a slow query is CPU-bound, disk-bound, or suffering from stale planner statistics (`ANALYZE`).

---

#### Session 1.4: High-Performance Queries, Window Functions & CTE Traps
* **Mental Model:** SQL is set-based, not procedural. Naive queries cause $O(N \cdot M)$ Cartesian products or N+1 roundtrips. Modern CTEs (`WITH`) can be inlined (since PG 12), but unoptimized subqueries destroy performance.
* **Invisible Made Visible:**
  - Nested Loop vs Hash Join vs Merge Join in query plans.
  - Window functions (`ROW_NUMBER()`, `DENSE_RANK()`, `SUM() OVER ()`) without self-joins.
  - Memory consumption of temporary work files during joins.
* **Hands-on Lab:**
  1. Solve top-N per category (e.g. latest 3 orders per user) using `ROW_NUMBER() OVER (PARTITION BY ...)` vs correlated subqueries.
  2. Compare materialized CTEs (`WITH x AS MATERIALIZED (...)`) vs inlined CTEs.
  3. Identify and eliminate a Cartesian explosion trap.
* **Platform/Backend Takeaway:** Preventing runaway joins from exhausting database memory and blocking API response threads.

---

### Module 2: Concurrency, Transactions & Safety (Layer B)

#### Session 2.1: ACID in Practice & Write-Ahead Logging (WAL)
* **Mental Model:** When Postgres confirms a `COMMIT`, your data is NOT immediately written to the table heap files on disk. It is written sequentially to the Write-Ahead Log (WAL) and `fsync`'d. Heap updates happen later in memory.
* **Invisible Made Visible:**
  - WAL current Log Sequence Number (`pg_current_wal_lsn()`).
  - Crash recovery simulation: kill PostgreSQL abruptly with `kill -9` during heavy writes and observe the WAL replay log during startup.
* **Hands-on Lab:**
  1. Track WAL generation per transaction (`pg_walfile_name`, LSN offsets).
  2. Observe checkpoint activity and dirty page flushing.
  3. Simulate an abrupt container kill and inspect the PostgreSQL startup logs replaying WAL records.
* **Platform/Backend Takeaway:** Understanding RPO/RTO, why WAL throughput is the bottleneck for write-heavy systems, and how checkpoints impact I/O latency.

---

#### Session 2.2: MVCC Deep Dive: Row Versions, Dead Tuples & Heap Structure
* **Mental Model:** In PostgreSQL, `UPDATE` never overwrites data in-place; it creates a new row version (tuple) and marks the old one as dead. `DELETE` only sets an expiration marker (`xmax`).
* **Invisible Made Visible:**
  - Tuple headers: `xmin`, `xmax`, `t_ctid`, `t_infomask` via `pageinspect`.
  - Dead tuples accumulating in `pg_stat_user_tables` (`n_dead_tup`).
* **Hands-on Lab:**
  1. Insert a row, inspect its `xmin` and `ctid`.
  2. Update the row 5 times; view all 5 physical tuple versions stored on the raw disk page.
  3. Observe how a long-running transaction prevents old tuples from being cleaned up.
* **Platform/Backend Takeaway:** Why high-throughput UPDATE workloads degrade read latency over time, and the role of HOT (Heap-Only Tuples) optimization.

---

#### Session 2.3: Transaction Isolation Levels & Concurrency Anomalies
* **Mental Model:** Concurrency is an illusion managed by snapshot visibility. Different isolation levels (`READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`) guard against different anomalies at varying performance costs.
* **Invisible Made Visible:**
  - Dirty reads (prevented by default in PG).
  - Non-repeatable reads and Phantom reads demonstrated side-by-side across two concurrent `psql` sessions.
  - Serialization failure (`40001: could not serialize access due to read/write dependencies among transactions`).
* **Hands-on Lab:**
  1. Open two concurrent terminal sessions (`Terminal A` and `Terminal B`).
  2. Reproduce the classic "Lost Update" bug under `READ COMMITTED`.
  3. Fix the lost update using `REPEATABLE READ` and handle the resulting serialization error.
  4. Test optimistic concurrency control (`version` column) vs pessimistic locking.
* **Platform/Backend Takeaway:** Choosing the right isolation level for financial/inventory logic vs analytics, and handling retry loops gracefully in backend code.

---

#### Session 2.4: Locking Mechanics, Row Locks, Deadlocks & Lock Trees
* **Mental Model:** Every SQL statement acquires locks. Lock contention occurs when two transactions request incompatible locks on the same object. Deadlocks occur when circular dependencies form.
* **Invisible Made Visible:**
  - Real-time lock queue inspection via `pg_locks` joined with `pg_stat_activity`.
  - Deadlock detection graph printed in Postgres logs.
  - `SELECT ... FOR UPDATE` vs `SELECT ... FOR UPDATE SKIP LOCKED`.
* **Hands-on Lab:**
  1. Trigger an intentional 2-session deadlock and observe Postgres kill one with error `40P01`.
  2. Build a lock monitoring query showing the "blocking query" and the "waiting query".
  3. Implement a high-throughput job queue worker with `FOR UPDATE SKIP LOCKED` and verify zero lock contention between concurrent workers.
* **Platform/Backend Takeaway:** How to resolve "database hung" alerts caused by unindexed FK lock cascades or uncommitted transactions holding locks.

---

### Module 3: PostgreSQL Performance & Operations (Layer C)

#### Session 3.1: Table Bloat, `VACUUM`, Free Space Maps & Autovacuum Tuning
* **Mental Model:** Dead tuples consume disk space. Standard `VACUUM` marks space in the Free Space Map (FSM) for reuse by future INSERTs, but does NOT shrink the file. `VACUUM FULL` rewrites the table but locks it exclusively.
* **Invisible Made Visible:**
  - Table bloat percentage using disk size vs live tuple count.
  - Autovacuum trigger thresholds (`autovacuum_vacuum_threshold` + `scale_factor * live_tuples`).
  - Progress tracking via `pg_stat_progress_vacuum`.
* **Hands-on Lab:**
  1. Create synthetic bloat by updating 50k rows.
  2. Watch `autovacuum` kick in via `pg_stat_activity` and verify `n_dead_tup` resetting.
  3. Compare `VACUUM`, `VACUUM (VERBOSE, ANALYZE)`, and `VACUUM FULL`.
  4. Tune table-level autovacuum parameters for write-intensive tables.
* **Platform/Backend Takeaway:** Preventing disk runaway alerts and query slowdowns on tables that experience frequent updates or deletes.

---

#### Session 3.2: Memory Architecture & Resource Sizing
* **Mental Model:** Postgres memory is split into: Shared Memory (`shared_buffers`, WAL buffers) shared by all backends, and Local Memory (`work_mem`, `maintenance_work_mem`) allocated per query operation per connection.
* **Invisible Made Visible:**
  - Inspecting what tables and indexes are cached in RAM using `pg_buffercache`.
  - `work_mem` exhaustion causing `Sort Method: external merge Disk: ...` in `EXPLAIN ANALYZE`.
* **Hands-on Lab:**
  1. Query `pg_buffercache` to view the percentage of `shared_buffers` occupied by `orders` vs `users`.
  2. Trigger an in-memory sort vs a disk-spill sort by toggling `work_mem` between `64kB` and `32MB`.
  3. Calculate safe memory limits for a 8GB/16GB/32GB production database node.
* **Platform/Backend Takeaway:** Why setting `work_mem` too high causes the Linux OOM Killer to terminate PostgreSQL, and how to size instances properly.

---

#### Session 3.3: Connection Pooling with PgBouncer
* **Mental Model:** PostgreSQL uses a process-per-connection architecture (`fork()` model). Each connection consumes 5-10MB of RAM and incurs CPU context switching overhead. PgBouncer multiplexes thousands of client connections onto a small pool of Postgres processes.
* **Invisible Made Visible:**
  - Connection benchmark comparison using `pgbench` (500 connections directly to PG vs 500 connections to PgBouncer).
  - PgBouncer admin console: `SHOW POOLS`, `SHOW CLIENTS`, `SHOW SERVERS`, `SHOW STATS`.
  - The three pool modes: `session`, `transaction`, and `statement` (and their caveats with prepared statements / temp tables).
* **Hands-on Lab:**
  1. Connect to PgBouncer admin console and inspect pool metrics.
  2. Run `pgbench` against Postgres directly on 5432 and watch CPU/connection exhaustion.
  3. Run `pgbench` through PgBouncer on 6432 with identical concurrency and compare throughput and latency.
* **Platform/Backend Takeaway:** Architecting database access in Kubernetes (where each pod replica opens connection pools) to prevent connection saturation.

---

#### Session 3.4: Disaster Recovery & Backup Fundamentals
* **Mental Model:** Logical backups (`pg_dump`) export SQL commands; they are portable across versions but slow for large datasets. Physical backups (Basebackup + WAL streaming) copy raw data files; they enable Point-In-Time Recovery (PITR) to any second in history.
* **Invisible Made Visible:**
  - `pg_dump` format differences: plain SQL vs custom (`-Fc`) with parallel restore (`pg_restore -j`).
  - Simulating data corruption or accidental drop (`DROP TABLE orders;`) and recovery workflow.
* **Hands-on Lab:**
  1. Perform a selective table backup and restore using `pg_dump -Fc` and `pg_restore`.
  2. Inspect WAL archiving mechanics and understand how tools like pgBackRest and CloudNativePG implement continuous physical backup and PITR.
* **Platform/Backend Takeaway:** Designing backup policies, calculating Recovery Point Objective (RPO) and Recovery Time Objective (RTO), and verifying backup restores.

---

### Module 4: Redis in the Real World

#### Session 4.1: Redis Memory & Core Data Structures Beyond Strings
* **Mental Model:** Redis is an in-memory data structures server. Using the right data structure (Hash vs String, Sorted Set vs List) reduces memory by 5-10x and provides $O(1)$ or $O(\log N)$ access.
* **Invisible Made Visible:**
  - Memory consumption per key using `MEMORY USAGE <key>`.
  - Internal encoding types (`ziplist`/`listpack`, `hashtable`, `skiplist`) using `OBJECT ENCODING <key>`.
* **Hands-on Lab:**
  1. Benchmark storing 10,000 user profiles as flat JSON strings vs Redis Hashes (`HSET`, `HGETALL`).
  2. Build a sliding-window rate limiter using Sorted Sets (`ZSET`, `ZADD`, `ZREMRANGEBYSCORE`).
  3. Build an event queue with Redis Lists (`LPUSH`, `RPOP`, `BRPOP`).
* **Platform/Backend Takeaway:** Slashing Redis cloud costs by choosing memory-efficient encodings and avoiding $O(N)$ operations (`KEYS *`) that block the single-threaded event loop.

---

#### Session 4.2: Production Caching Architecture & Preventing Stampedes
* **Mental Model:** Caching isn't just `GET` and `SET`. Naive cache-aside setups crash when a hot key expires and 10,000 concurrent web requests hammer PostgreSQL at the exact same millisecond (Cache Stampede / Dog-Piling).
* **Invisible Made Visible:**
  - Cache hit/miss metrics (`INFO stats`).
  - Simulating a stampede: expire a hot product record under simulated traffic and observe database query spike.
* **Hands-on Lab:**
  1. Implement standard Cache-Aside pattern with Python.
  2. Reproduce the Cache Stampede failure mode.
  3. Mitigate the stampede using:
     - Distributed Mutex Lock (only 1 request queries Postgres; others wait/retry).
     - Probabilistic Early Expiration (XFetch algorithm).
* **Platform/Backend Takeaway:** Designing resilient caching layers that protect downstream relational databases during traffic spikes.

---

#### Session 4.3: Memory Limits, Expiration & Eviction Policies
* **Mental Model:** Redis is bounded by RAM. When `maxmemory` is reached, Redis enforces an eviction policy. Without proper TTLs and eviction policies, writes will fail with `OOM command not allowed`.
* **Invisible Made Visible:**
  - Watching `evicted_keys` increment during memory saturation (`INFO stats`).
  - Eviction policy behavior: `noeviction` vs `allkeys-lru` vs `volatile-lru` vs `allkeys-lfu`.
* **Hands-on Lab:**
  1. Fill the lab's 64MB Redis container with keys until it hits capacity.
  2. Observe `OOM` errors under `noeviction`.
  3. Reconfigure to `allkeys-lru` and `allkeys-lfu` at runtime (`CONFIG SET maxmemory-policy ...`) and observe automatic eviction.
  4. Compare LRU (Least Recently Used) vs LFU (Least Frequently Used) behavior.
* **Platform/Backend Takeaway:** Configuring Redis memory policies safely so background caches drop expendable data without dropping critical session state.

---

#### Session 4.4: Distributed Locks & Event Streaming
* **Mental Model:** Distributed locks synchronize actions across multiple microservices. Simple locks fail during worker crashes or slow execution. Redis Streams provide a durable, partitioned log with consumer groups (like a lightweight Apache Kafka).
* **Invisible Made Visible:**
  - Safe distributed lock implementation: `SET resource_id token NX PX 30000` + Lua script atomic unlock.
  - Redis Streams consumer groups, pending entries list (PEL), and acknowledgements (`XACK`).
* **Hands-on Lab:**
  1. Implement an atomic distributed lock and verify protection against race conditions.
  2. Test lock expiration edge cases (worker takes longer than TTL) and why token checking is mandatory.
  3. Create a Redis Stream (`XADD`), register a Consumer Group (`XGROUP CREATE`), read messages (`XREADGROUP`), and inspect the PEL for dead consumer recovery (`XPENDING`, `XCLAIM`).
* **Platform/Backend Takeaway:** Knowing when Redis Streams is the right operational choice vs Kafka or RabbitMQ, and implementing crash-safe distributed locks.

---

## Session Execution Structure (The DB 101 Formula)

Each session strictly adheres to the **DB 101 Formula**:

```text
+-------------------------------------------------------------+
| 1. Mental Model (5 mins)                                    |
|    - The 1-page intuition and architectural diagram.         |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
| 2. Hands-on Experiment (15 mins)                            |
|    - Ready-to-run commands via `make` or SQL scripts.       |
|    - Concrete scenarios with observable before/after state.  |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
| 3. Inspect the Internals (5 mins)                           |
|    - "Make me SEE it": pageinspect, pg_stat_*, EXPLAIN,     |
|      pg_buffercache, or Redis INFO/MEMORY.                  |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
| 4. Platform & Production Takeaway (5 mins)                  |
|    - Real incident post-mortem context.                     |
|    - Runbook rules and monitoring alerts to set up.         |
+-------------------------------------------------------------+
```
