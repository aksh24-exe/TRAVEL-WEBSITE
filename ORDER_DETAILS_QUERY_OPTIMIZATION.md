# Order Details Query Optimization Analysis

## Executive Summary

The order details query is experiencing severe performance issues, taking approximately **11 seconds** to execute. The root cause is an inefficient index selection by the MySQL query optimizer, resulting in a full backward scan of the PRIMARY key index across **10.5 million rows** (~35M total rows in table).

## Current Query Execution Analysis

### EXPLAIN Output Summary

| Table | Type | Key Used | Rows Scanned | Issue |
|-------|------|----------|--------------|-------|
| orders | index | PRIMARY | 2442 (estimated) / 10.5M (actual) | Backward index scan - **PROBLEM** |
| courses | eq_ref | PRIMARY | 1 | OK |
| users | eq_ref | PRIMARY | 1 | OK |
| learner_invoices | ref | school_id_and_order_id | 1 | OK |
| coupon_codes | eq_ref | PRIMARY | 1 | OK |
| addresses | ref | school_id_and_user_id | 1 | OK |

### Performance Metrics from EXPLAIN ANALYZE

```
Total Execution Time: 11,015 ms (~11 seconds)
Orders Table Scan: 10.5 million rows scanned (out of 35M total)
Rows After Filter: 118,218 rows
Final Result: 10 rows (with LIMIT)
```

## Root Cause Analysis

### Primary Issue: ORDER BY Prevents Index Usage

The query optimizer is choosing to use the **PRIMARY key (id)** with a backward index scan instead of using more selective indexes. The critical reason:

**The `ORDER BY id DESC` clause forces MySQL to prefer the PRIMARY key** because:
1. Using any other index would require a filesort operation after filtering
2. MySQL estimates that scanning PRIMARY in reverse order and filtering is "cheaper" than index lookup + sort
3. This estimation is WRONG for this query pattern

### Why Existing Indexes Are Not Used

| Index | Columns | Why Not Used |
|-------|---------|--------------|
| `index_orders_on_school_id_and_course_id` | (school_id, course_id) | ORDER BY id DESC requires filesort |
| `index_orders_on_transaction_status` | (transaction_status, school_id) | ORDER BY id DESC requires filesort |
| `index_orders_on_school_id` | (school_id) | ORDER BY id DESC requires filesort |

**The optimizer is avoiding a filesort but paying a much higher price by scanning 10.5M rows.**

### Actual Index Structure on Orders Table (35M rows)

```sql
PRIMARY (id)                                              -- Cardinality: 35,285,692
index_orders_on_pg_order_id_and_school_id (pg_order_id, school_id)  -- UNIQUE
index_orders_on_course_id (course_id)                     -- Cardinality: 199,624
index_orders_on_user_id (user_id)                         -- Cardinality: 7,726,906
index_orders_on_school_id_and_course_id (school_id, course_id)      -- Cardinality: 287,707
index_orders_on_school_id_and_learner_invoice_id (school_id, learner_invoice_id)
index_orders_on_school_id_and_address_id (school_id, address_id)
index_orders_on_transaction_id (transaction_id)
index_orders_on_school_id (school_id)                     -- Cardinality: 29,636
index_orders_on_transaction_status (transaction_status, school_id)  -- Cardinality: 38,688
index_orders_on_product_pricing_id (product_pricing_id)
index_orders_on_ancestry (ancestry)
index_orders_on_payment_gateway_id (payment_gateway_id)
```

### Query Filter Conditions

```sql
WHERE orders.school_id = 1915
  AND orders.transaction_status = 2
  AND orders.type_of_payment <> 2
  AND orders.course_id IN (246060, 246059, ... ~900 values)
ORDER BY orders.id DESC
LIMIT 10
```

## Recommended Optimizations

### Option 1: Create Composite Index with ID (BEST SOLUTION)

Create a new composite index that includes `id` at the end to eliminate the filesort:

```sql
CREATE INDEX index_orders_on_school_status_course_id 
ON orders (school_id, transaction_status, course_id, id);
```

**Why this works:**
- `school_id = 1915` → Uses first column (equality)
- `transaction_status = 2` → Uses second column (equality)  
- `course_id IN (...)` → Uses third column (range/IN)
- `id` → Already sorted within each (school_id, transaction_status, course_id) group

**Expected Improvement:** 95%+ reduction in query time (from 11s to <200ms)

**Index size estimate:** ~35M rows × ~16 bytes = ~560MB additional storage

### Option 2: Modify Existing Index (Lower Risk)

Extend the existing `index_orders_on_school_id_and_course_id` to include `id`:

```sql
-- Drop old index
DROP INDEX index_orders_on_school_id_and_course_id ON orders;

-- Create new index with id column
CREATE INDEX index_orders_on_school_id_and_course_id 
ON orders (school_id, course_id, id);
```

**Pros:** Replaces existing index, minimal additional storage
**Cons:** Doesn't include transaction_status, slightly less optimal

### Option 3: Force Index Hint (IMMEDIATE FIX)

Use a hint to force MySQL to use the existing index and accept the filesort:

```sql
SELECT ... 
FROM orders FORCE INDEX (index_orders_on_school_id_and_course_id)
LEFT JOIN courses ...
WHERE orders.school_id = 1915
  AND orders.transaction_status = 2
  AND orders.type_of_payment <> 2
  AND orders.course_id IN (...)
ORDER BY orders.id DESC
LIMIT 10
```

**Why this helps even with filesort:**
- Index filters to ~287K rows (vs 10.5M with PRIMARY scan)
- Filesort on 287K rows is much faster than scanning 10.5M rows
- Expected time: 1-3 seconds (better than 11s, but not optimal)

**For Rails/ActiveRecord:**
```ruby
Order.from('orders FORCE INDEX (index_orders_on_school_id_and_course_id)')
     .where(school_id: 1915, transaction_status: 2)
     .where.not(type_of_payment: 2)
     .where(course_id: course_ids)
     .order(id: :desc)
     .limit(10)
```

### Option 4: Subquery Approach (No Index Change Required)

Force the optimizer to filter first, then sort:

```sql
SELECT orders.*, courses.*, users.*, learner_invoices.*, coupon_codes.*, addresses.*
FROM (
  SELECT * FROM orders
  WHERE school_id = 1915
    AND transaction_status = 2
    AND type_of_payment <> 2
    AND course_id IN (...)
  ORDER BY id DESC
  LIMIT 10
) AS orders
LEFT JOIN courses ON courses.id = orders.course_id
LEFT JOIN users ON users.id = orders.user_id
LEFT JOIN learner_invoices ON ...
LEFT JOIN coupon_codes ON ...
LEFT JOIN addresses ON ...
```

**Why this works:**
- Inner query can use `index_orders_on_school_id_and_course_id`
- Filesort happens on filtered subset only
- Outer joins happen on just 10 rows

### Option 5: Optimizer Hint (MySQL 8.0+)

Use optimizer hints to control index selection:

```sql
SELECT /*+ INDEX(orders index_orders_on_school_id_and_course_id) */ ...
FROM orders
...
```

## Implementation Priority

| Priority | Action | Effort | Impact | Downtime |
|----------|--------|--------|--------|----------|
| 1 | FORCE INDEX hint (Option 3) | Low | Medium | None |
| 2 | Subquery approach (Option 4) | Low | Medium | None |
| 3 | New composite index (Option 1) | Medium | High | Brief (index creation) |
| 4 | Modify existing index (Option 2) | Medium | High | Brief |

## Recommended Implementation Plan

### Phase 1: Immediate (No Downtime)
Apply Option 3 (FORCE INDEX) or Option 4 (Subquery) to get immediate relief.

### Phase 2: Permanent Fix (Scheduled Maintenance)
```sql
-- Run during low-traffic period
-- MySQL 8.0+ can create index without blocking writes (ALGORITHM=INPLACE)
CREATE INDEX index_orders_on_school_status_course_id 
ON orders (school_id, transaction_status, course_id, id)
ALGORITHM=INPLACE, LOCK=NONE;
```

### Phase 3: Verify and Remove Hints
After new index is created:
1. Verify EXPLAIN shows new index being used
2. Remove FORCE INDEX hints from application code
3. Monitor query performance

## Monitoring Recommendations

After implementing the optimization:

1. **Verify Index Usage:**
   ```sql
   EXPLAIN SELECT ... -- Confirm new index is being used
   ```

2. **Monitor Query Performance:**
   ```sql
   SHOW STATUS LIKE 'Handler_read%';
   ```

3. **Check Index Statistics:**
   ```sql
   ANALYZE TABLE orders;
   SHOW INDEX FROM orders;
   ```

## Additional Considerations

### Index Maintenance

The new composite index will:
- Add ~50-100 bytes per row of storage overhead
- Slightly slow down INSERT/UPDATE operations on the orders table
- Require periodic `ANALYZE TABLE` to maintain accurate statistics

### Application Changes

If using an ORM (like ActiveRecord), ensure the query builder generates queries that can use the new index:

```ruby
# Rails example - ensure proper ordering
Order.where(school_id: 1915, transaction_status: 2)
     .where.not(type_of_payment: 2)
     .where(course_id: course_ids)
     .order(id: :desc)
     .limit(10)
```

## Why Existing Indexes Are Ignored - Technical Deep Dive

MySQL's query optimizer uses a cost-based model. For this query:

**Cost with PRIMARY key (current):**
- No filesort needed (already ordered by id)
- But must scan 10.5M rows to find 118K matches
- Estimated cost appears "low" because backward scan is efficient

**Cost with index_orders_on_school_id_and_course_id:**
- Quick lookup: ~287K rows matching school_id + course_id
- But requires filesort on those 287K rows
- Optimizer overestimates filesort cost

**The optimizer is WRONG here** because:
1. It underestimates the cost of scanning 10.5M rows with filter evaluation
2. It overestimates the filesort cost on 287K rows
3. The LIMIT 10 isn't properly factored in (filesort with LIMIT uses heap, very fast)

### How to Verify

Run this to see the actual costs:

```sql
-- Check what the optimizer thinks
EXPLAIN FORMAT=TREE 
SELECT * FROM orders 
WHERE school_id = 1915 AND transaction_status = 2 
  AND course_id IN (...) 
ORDER BY id DESC LIMIT 10;

-- Force index and compare
EXPLAIN FORMAT=TREE 
SELECT * FROM orders FORCE INDEX (index_orders_on_school_id_and_course_id)
WHERE school_id = 1915 AND transaction_status = 2 
  AND course_id IN (...) 
ORDER BY id DESC LIMIT 10;
```

## Conclusion

The order details query takes 11 seconds because **MySQL chooses the PRIMARY key to avoid a filesort, but this forces a scan of 10.5M rows**. The existing `index_orders_on_school_id_and_course_id` would be much faster even WITH a filesort.

### Immediate Fix (No Downtime)
Use `FORCE INDEX (index_orders_on_school_id_and_course_id)` to force the optimizer to use the correct index. Expected improvement: 11s → 1-3s.

### Permanent Fix (Requires Index Creation)
Create a new index: `(school_id, transaction_status, course_id, id)` to eliminate filesort entirely. Expected improvement: 11s → <200ms.

---

*Analysis Date: January 28, 2026*
*Table Size: ~35 million rows*
*Query Execution Plan: MySQL 8.x EXPLAIN ANALYZE output*
