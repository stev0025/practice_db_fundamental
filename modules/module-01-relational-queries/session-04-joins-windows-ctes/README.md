# Session 1.4: High-Performance Queries, Window Functions & CTE Traps

> **Module 1:** Relational & Query Foundations (Layer A)
> **Duration:** 30 minutes
> **Lab Script:** [session-04.sql](session-04.sql)

---

## 1. Mental Model

SQL describes **what** you want, not **how**. Postgres chooses the "how". Your job is to write queries it can execute in **one set-based pass** instead of looping row by row (an N+1 pattern) or multiplying rows by accident.

---

## 2. The Three Join Algorithms

```text
Nested Loop            Hash Join                    Merge Join
for each outer row:    build hash table of A        sort A, sort B
  look up in B         probe it with each row of B  walk both in step
(fast with an index)   (needs memory: work_mem)     (great when pre-sorted)
```

| Algorithm | Best when | Weak when |
|---|---|---|
| Nested Loop | Few outer rows, index on the inner side | Many outer rows, no index (O(N × M)) |
| Hash Join | Big unsorted inputs, `=` join | Hash table exceeds `work_mem` → spills to disk (`Batches > 1`) |
| Merge Join | Both sides sorted already, huge inputs | Sorting is expensive |

---

## 3. Window Functions

A window function computes over a group of rows **without collapsing them** (unlike `GROUP BY`).

```sql
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC)
--                 ^ restart per user    ^ order inside each user
```
- `ROW_NUMBER` 1,2,3,4. `RANK` 1,1,3,4. `DENSE_RANK` 1,1,2,3.
- "Latest N per group" is one pass with `ROW_NUMBER`; the correlated-subquery version re-runs for every row.

---

## 4. CTEs (`WITH`)

Since PG 12, a CTE used **once** is inlined like a subquery, so filters can be pushed into it and indexes used. Adding `MATERIALIZED` forces it to run fully first, stored as a temp result. Use that only for an expensive CTE referenced multiple times.

---

## 5. Walkthrough

Open `make psql` and follow [session-04.sql](session-04.sql).

| Part | Goal | What to observe |
|---|---|---|
| 1 | Nested Loop vs Hash vs Merge | Plan changes with row counts; `Buckets/Batches/Memory` on the Hash node |
| 2 | `work_mem` spills | `Sort Method: external merge Disk`, `Batches > 1`, temp buffers |
| 3 | Top-N per group | Window function vs correlated subquery: time and buffers |
| 4 | CTE inlined vs `MATERIALIZED` | `CTE Scan` with `Rows Removed by Filter` vs index use |
| 5 | Cartesian and fan-out traps | 2,000,000,000 estimated rows; `SUM` inflated by the join |

### Predict before you run
1. For `WHERE u.id = 42`, will Postgres pick Nested Loop, Hash, or Merge?
2. Does the window-function version read fewer or more buffers than the correlated subquery?
3. Will the inflated `SUM` be about 2.5× larger? Why?

---

## 6. Platform & Production Takeaways

1. **Read the join node:** a Nested Loop with a big outer side and no inner index is the classic runaway query.
2. **`work_mem` is per node, per query:** many connections × several sorts/hashes can exhaust RAM. Spills show up as `Disk:` and temp buffers.
3. **Missing `ON` clause = Cartesian product:** use `EXPLAIN` (without `ANALYZE`) first on anything unfamiliar, and set a `statement_timeout`.
4. **Joining one-to-many then `SUM`-ing the "one" side double counts.** Aggregate before joining, or sum from the right table.

---

## 7. Next Session

**Module 2, Session 2.1: ACID in Practice & Write-Ahead Logging (WAL).**
