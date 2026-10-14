# Session 1.2: Indexing Mechanics & The Anatomy of a B-Tree

> **Module 1:** Relational & Query Foundations (Layer A)
> **Duration:** 30 minutes
> **Lab Script:** [session-02.sql](session-02.sql)

---

## 1. Mental Model

A B-tree index is an **ordered, balanced tree of `(key, ctid)` tuples** stored in its own 8KB pages:

```text
                    [ Root page ]            <- bt_metap().root
                   /      |       \
        [ Interior ]  [ Interior ]  [ Interior ]   ctid -> child INDEX page
          /    \          ...
   [ Leaf ] <-> [ Leaf ] <-> [ Leaf ] <-> ...      ctid -> HEAP (page, line pointer)
```

- Lookup = walk root -> leaf (typically 3-4 page reads even for hundreds of millions of rows), then one heap fetch per match.
- Leaves are doubly linked, so range scans and `ORDER BY` walk the leaf level in order.
- Index scan = **random I/O** per heap fetch. Seq scan = **sequential I/O**. Past some selectivity the seq scan wins.

---

## 2. Walkthrough

Open a shell with `make psql` and follow [session-02.sql](session-02.sql).

| Part | Goal | What to observe |
|------|------|-----------------|
| 1 | Inspect a B-tree with `bt_metap`, `bt_page_stats`, `bt_page_items` | Tree height, root block, interior `ctid` = child page vs leaf `ctid` = heap row |
| 2 | `(user_id, status)` vs `(status, user_id)` | Leftmost-prefix rule: which index serves a `status`-only filter |
| 3 | Selectivity cliff | Seq Scan chosen for `status='completed'` (~43% of rows) despite an index |
| 4 | Partial index `WHERE status='pending'` | Index size vs full index; query predicate must imply the index predicate |
| 5 | Expression index `LOWER(email)` | Seq Scan -> Index Scan once the indexed expression matches the query |
| Bonus | Index `order_items.order_id` | Closes the unindexed-FK trap from Session 1.1 |

### Predict before you run
Write down your guess for each, then check:
1. Height of the `order_number` index? How many pages in the root?
2. Can `WHERE status = 'pending'` use `(user_id, status)`? How well?
3. Is the partial index closer to 14% or 100% of the full index size?
4. Does `enable_seqscan = off` make the `status='completed'` query faster or slower?

---

## 3. Platform & Production Takeaways

1. **Leftmost prefix:** a composite index serves queries that constrain its leading column(s). Put equality columns first; order for the queries you actually run.
2. **"My index isn't used":** low selectivity, a function wrapped around the column, a type mismatch, or stale statistics. Check with `EXPLAIN` before blaming the planner.
3. **Partial indexes** keep hot-subset indexes small, so they stay in `shared_buffers`.
4. **Every index costs writes:** each `INSERT`/non-HOT `UPDATE` touches every index on the table. Drop unused ones (`pg_stat_user_indexes.idx_scan = 0`).
5. **Creating indexes in production:** use `CREATE INDEX CONCURRENTLY` to avoid blocking writes.

---

## 4. Next Session

**Session 1.3: Demystifying `EXPLAIN (ANALYZE, BUFFERS)` & Planner Cost Models.**
