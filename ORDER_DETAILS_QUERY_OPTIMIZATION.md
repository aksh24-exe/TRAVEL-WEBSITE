# Order Details Query Optimization Analysis

## Executive Summary

The order details query is experiencing severe performance issues, taking approximately **11 seconds** to execute. The root cause is an inefficient index selection by the MySQL query optimizer, resulting in a full backward scan of the PRIMARY key index across **10.5 million rows**.

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
Orders Table Scan: 10.5 million rows scanned
Rows After Filter: 118,218 rows
Final Result: 10 rows (with LIMIT)
```

## Root Cause Analysis

### Primary Issue: Suboptimal Index Selection

The query optimizer is choosing to use the **PRIMARY key (id)** with a backward index scan instead of using more selective indexes. This is happening because:

1. **ORDER BY Conflict**: The query likely uses `ORDER BY orders.id DESC` (or similar), causing the optimizer to prefer the PRIMARY key for ordering
2. **Large IN Clause**: The `course_id IN (...)` clause contains ~900+ values, making the optimizer hesitant to use `index_orders_on_school_id_and_course_id`
3. **Multiple Filter Conditions**: The combination of `school_id`, `transaction_status`, `type_of_payment`, and `course_id` filters don't have a covering composite index

### Available Indexes on Orders Table

```sql
PRIMARY                                          -- Currently being used (inefficiently)
index_orders_on_course_id                        -- Single column
index_orders_on_school_id_and_course_id          -- Could help with school_id + course_id
index_orders_on_school_id_and_learner_invoice_id -- Not relevant to main filter
index_orders_on_school_id_and_address_id         -- Not relevant to main filter
index_orders_on_school_id                        -- Single column
index_orders_on_transaction_status               -- Single column
```

### Query Filter Conditions

```sql
WHERE orders.school_id = 1915
  AND orders.transaction_status = 2
  AND orders.type_of_payment <> 2
  AND orders.course_id IN (246060, 246059, ... ~900 values)
```

## Recommended Optimizations

### Option 1: Create Optimized Composite Index (Recommended)

Create a new composite index that matches the query's filter pattern:

```sql
CREATE INDEX index_orders_on_school_transaction_payment_course 
ON orders (school_id, transaction_status, type_of_payment, course_id, id);
```

**Rationale:**
- `school_id` is the most selective filter (single value)
- `transaction_status` is the second filter (single value = 2)
- `type_of_payment` is used for exclusion (<> 2)
- `course_id` for the IN clause
- `id` at the end allows index-only ordering

**Expected Improvement:** 95%+ reduction in query time (from 11s to <500ms)

### Option 2: Composite Index with Covered Ordering

```sql
CREATE INDEX index_orders_for_order_details 
ON orders (school_id, transaction_status, course_id, id DESC)
WHERE type_of_payment <> 2;
```

Note: Partial indexes (with WHERE clause) are supported in PostgreSQL but not MySQL. For MySQL, use:

```sql
CREATE INDEX index_orders_for_order_details 
ON orders (school_id, transaction_status, course_id, id);
```

### Option 3: Force Index Hint (Quick Fix)

If creating a new index isn't immediately possible, add an index hint:

```sql
SELECT ... 
FROM orders FORCE INDEX (index_orders_on_school_id_and_course_id)
LEFT JOIN courses ...
WHERE orders.school_id = 1915
  AND orders.transaction_status = 2
  ...
```

**Warning:** This is a temporary fix and may not be optimal for all query variations.

### Option 4: Query Restructuring

Break the query into two parts using a subquery or CTE:

```sql
-- Step 1: Get order IDs efficiently
WITH filtered_orders AS (
  SELECT id, user_id, course_id, tracking_id
  FROM orders
  WHERE school_id = 1915
    AND transaction_status = 2
    AND type_of_payment <> 2
    AND course_id IN (...)
  ORDER BY id DESC
  LIMIT 10
)
-- Step 2: Join with other tables
SELECT fo.*, c.*, u.*, li.*, cc.*, a.*
FROM filtered_orders fo
LEFT JOIN courses c ON ...
LEFT JOIN users u ON ...
...
```

## Implementation Priority

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 1 | Add composite index (Option 1) | Medium | High |
| 2 | Use FORCE INDEX hint (Option 3) | Low | Medium |
| 3 | Query restructuring (Option 4) | High | High |

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

## Conclusion

The order details query performance can be improved from **11 seconds to under 500ms** by adding an appropriate composite index. The recommended approach is to create `index_orders_on_school_transaction_payment_course` which aligns with the query's filter and ordering requirements.

---

*Analysis Date: January 28, 2026*
*Query Execution Plan: MySQL 8.x EXPLAIN ANALYZE output*
