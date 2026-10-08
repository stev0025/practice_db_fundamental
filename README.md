# Database Fundamentals (DB 101) Hands-on Lab

A production-grade, hands-on personal training lab designed for **Half-Backend, Half-Platform Engineers** to master PostgreSQL, PgBouncer, and Redis fundamentals from the inside out.

No engine theory dumps. Every concept is accompanied by runnable commands, direct inspections of engine internals (`pageinspect`, `pg_buffercache`, `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_*`), and platform incident context.

---

## 🚀 Quick Start (60 Seconds)

### 1. Start the Environment
```bash
make up
```
This spins up:
- **PostgreSQL 16**: Port `5432` (with `pg_stat_statements`, `pg_buffercache`, and `pageinspect` preloaded)
- **PgBouncer**: Port `6432` (configured for transaction pooling)
- **Redis 7**: Port `6379` (with AOF persistence and 64MB memory quota)

### 2. Verify Services & Seed Data
```bash
make test
make seed
```
This populates a realistic e-commerce and audit log dataset:
- `users`: 20,000 rows
- `products`: 2,000 rows
- `orders`: 100,000 rows
- `order_items`: 250,000 rows
- `audit_logs`: 50,000 rows

### 3. Open an Interactive Session
```bash
# Connect directly to PostgreSQL
make psql

# Connect through PgBouncer
make psql-bouncer

# Connect to PgBouncer Admin Console (SHOW POOLS, etc.)
make psql-admin

# Connect to Redis
make redis-cli
```

---

## 🛠️ Lab Command Center (`Makefile`)

| Command | Description |
| :--- | :--- |
| `make up` | Start PostgreSQL, PgBouncer, and Redis in the background |
| `make down` | Stop all containers |
| `make ps` | Check container health and exposed ports |
| `make logs` | Tail logs from all containers |
| `make psql` | Direct interactive psql session to PostgreSQL (`db_fundamentals`) |
| `make psql-bouncer` | Interactive psql session routed through PgBouncer (`port 6432`) |
| `make psql-admin` | Interactive psql session to PgBouncer Admin Console |
| `make redis-cli` | Interactive Redis CLI session |
| `make seed` | Re-load the 400k+ record test dataset |
| `make reset` | Clean-slate reset: wipe all volumes, re-initialize, and re-seed |
| `make stats` | Display active connections, buffer cache hit ratios, and table sizes |
| `make test` | Run connectivity smoke tests across all three services |

---

## 📚 Curriculum Plan

See [PLAN.md](file:///home/steven/projects/practice_db_fundamental/PLAN.md) for the complete 16-session curriculum roadmap.

### Summary of Modules

* **[Module 1: Relational & Query Foundations](file:///home/steven/projects/practice_db_fundamental/modules/module-01-relational-queries)**
  - Session 1.1: Schema Integrity, Constraints & The 8KB Page
  - Session 1.2: Indexing Mechanics & The Anatomy of a B-Tree
  - Session 1.3: Demystifying `EXPLAIN (ANALYZE, BUFFERS)` & Planner Cost Models
  - Session 1.4: High-Performance Queries, Window Functions & CTE Traps

* **[Module 2: Concurrency, Transactions & Safety](file:///home/steven/projects/practice_db_fundamental/modules/module-02-concurrency-transactions)**
  - Session 2.1: ACID in Practice & Write-Ahead Logging (WAL)
  - Session 2.2: MVCC Under the Hood: Row Versions & Dead Tuples
  - Session 2.3: Transaction Isolation Levels & Concurrency Anomalies
  - Session 2.4: Locking Mechanics, Row Locks & Deadlock Detection

* **[Module 3: PostgreSQL Performance & Operations](file:///home/steven/projects/practice_db_fundamental/modules/module-03-performance-operations)**
  - Session 3.1: Table Bloat, `VACUUM`, and Autovacuum Tuning
  - Session 3.2: Memory Architecture & Sizing (`shared_buffers`, `work_mem`)
  - Session 3.3: Connection Pooling with PgBouncer Benchmarked
  - Session 3.4: Disaster Recovery & Backup Fundamentals (Logical vs Physical)

* **[Module 4: Redis in the Real World](file:///home/steven/projects/practice_db_fundamental/modules/module-04-redis-real-world)**
  - Session 4.1: Memory & Core Data Structures Beyond Strings
  - Session 4.2: Production Caching Architecture & Preventing Stampedes
  - Session 4.3: Memory Limits, Expiration & Eviction Policies (LRU/LFU)
  - Session 4.4: Distributed Locks (`SET NX PX`) & Event Streaming with Streams

---

## 📂 Repository Structure

```text
.
├── docker-compose.yml         # Postgres 16 + PgBouncer + Redis 7 definition
├── Makefile                   # Lab automation and shortcut commands
├── PLAN.md                    # Detailed 16-session syllabus & learning contracts
├── README.md                  # Project overview and quick start guide
├── config/
│   └── postgres/
│       └── postgresql.conf    # Custom configuration with observability tuning
├── scripts/
│   ├── 01-init.sql            # Extension loading (pageinspect, pg_stat_statements, etc.)
│   └── seed_data.sql          # 422,000+ realistic rows generator
└── modules/
    ├── module-01-relational-queries/
    ├── module-02-concurrency-transactions/
    ├── module-03-performance-operations/
    └── module-04-redis-real-world/
```

---

## 🎯 Getting Started with Session 1
To start the first session, head to [Module 1 Session 1 Guide](file:///home/steven/projects/practice_db_fundamental/modules/module-01-relational-queries/session-01-schema-constraints/README.md) or run:
```bash
make psql
```
