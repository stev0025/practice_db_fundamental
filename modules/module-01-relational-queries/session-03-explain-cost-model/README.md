# Session 1.3: Demystifying `EXPLAIN (ANALYZE, BUFFERS)` & Planner Cost Models

> **Module 1:** Relational & Query Foundations (Layer A)
> **Duration:** 30 minutes
> **Lab Script:** [session-03.sql](session-03.sql)

---

## 1. Mental Model

Before running a query, Postgres **plans** it: it lists possible ways (scan types), estimates a **cost** for each from table statistics, and picks the cheapest.

| Command | Runs the query? | Shows |
|---|---|---|
| `EXPLAIN` | No | The plan and cost *estimates* |
| `EXPLAIN (ANALYZE)` | **Yes** | Plan + real time + real row counts |
| `EXPLAIN (ANALYZE, BUFFERS)` | **Yes** | Also the pages touched (`shared hit` / `read`) |

> Because `ANALYZE` really executes the query, wrap `INSERT/UPDATE/DELETE` in `BEGIN; ... ROLLBACK;`.

### How to read a plan (you already did this in Session 1.2)
1. Read the **innermost (most indented)** line first. It feeds the line above it.
2. Compare `rows=` (estimate) with `actual rows=` (reality). A large gap = bad statistics.
3. Check `Buffers`: pages touched. `hit` = in memory, `read` = from disk/OS cache.
4. `cost=` is in abstract units, only useful to compare plans. `actual time=` is real milliseconds.

---

## 2. The cost formula (just arithmetic)

Postgres keeps a price list (`pg_settings`) and table statistics (`pg_class`):

```text
Seq Scan cost = relpages  * seq_page_cost      (1.0    per page read)
              + reltuples * cpu_tuple_cost     (0.01   per row processed)
              + reltuples * cpu_operator_cost  (0.0025 per row filtered)
```
For `orders` (1,177 pages, 100,000 rows): `1177 + 1000 + 250 = 2427`, the exact number you saw in earlier Seq Scan plans.

An index scan adds `random_page_cost` (4.0) per table page it jumps to, which is why index plans lose when many rows match.

---

## 3. Walkthrough

Open `make psql` and follow [session-03.sql](session-03.sql).

| Part | Goal | What to observe |
|---|---|---|
| 1 | `EXPLAIN` vs `EXPLAIN ANALYZE` | Estimate vs actual; why to `ROLLBACK` DML |
| 2 | Recompute a plan's cost by hand | Your number equals the planner's `2427` |
| 3 | Selectivity ladder | Index Scan → Bitmap Heap Scan → Seq Scan as the row fraction grows |
| 4 | `INCLUDE` covering index | Index Only Scan, `Heap Fetches: 0`, fewer buffers |
| 5 | Stale statistics | Estimate vs actual diverges after a big `UPDATE`; `ANALYZE` fixes it |
| 6 | Hit vs read, I/O timings | Warm cache makes the same query faster |

### Predict before you run
1. At about what fraction of rows does the plan stop being an Index Scan?
2. Will `INCLUDE (total_amount_cents)` make the query touch fewer pages? Why?
3. After the big `UPDATE`, will the planner's estimate be too high or too low?

---

## 4. Platform & Production Takeaways: "Why is this query slow?"

| Symptom in the plan | Diagnosis | Fix |
|---|---|---|
| Estimated rows ≫ or ≪ actual rows | Stale or missing statistics | `ANALYZE` the table; check autovacuum |
| High `read`, high `I/O Timings` | Disk-bound (cold cache or too much data) | Better index, more memory, fewer columns |
| All `hit`, still slow | CPU-bound: too many rows processed | More selective filter or index |
| `Index Scan` with `Heap Fetches` large | Index doesn't cover the query | `INCLUDE` the needed columns |

---

## 5. Next Session

**Session 1.4: High-Performance Queries, Window Functions & CTE Traps.**
