# SQL Query Performance Analysis & Optimization

## Original Query

```sql
SELECT DISTINCT users.id, users.name, users.email, users.mobile, users.last_login, 
       count(user_logins.id) logins, users.created_at 
FROM users 
INNER JOIN user_logins ON user_logins.user_id = users.id 
WHERE users.school_id = 1915 
GROUP BY user_logins.user_id 
ORDER BY count(user_logins.id) DESC 
LIMIT 30 OFFSET 0
```

## Performance Bottlenecks Identified

From the EXPLAIN ANALYZE output:

| Stage | Time | Rows Processed | Problem |
|-------|------|----------------|---------|
| Index lookup on users | 1,387ms | 440,790 rows | Large user base for school |
| Nested loop join | 5,245ms | **9.03 million rows** | Full join explosion |
| Temporary table aggregation | 27,157ms | 414,301 rows | **MAJOR BOTTLENECK** |
| Sort with duplicate removal | 39,104ms | 414,301 rows | Sorting huge dataset |

**Total query time: ~39 seconds**

### Root Causes

1. **Redundant DISTINCT + GROUP BY**: Using both `DISTINCT` and `GROUP BY` is redundant and forces extra duplicate removal work.

2. **Incorrect GROUP BY column**: `GROUP BY user_logins.user_id` instead of `GROUP BY users.id` causes confusion.

3. **Full aggregation before LIMIT**: The query aggregates ALL 414,301 users before sorting and limiting to 30 rows.

4. **9 million row join**: Every user login record is joined before aggregation.

---

## Optimized Solutions

### Solution 1: Fix Query Structure (Easy)

```sql
SELECT 
    users.id, 
    users.name, 
    users.email, 
    users.mobile, 
    users.last_login, 
    COUNT(user_logins.id) AS logins, 
    users.created_at 
FROM users 
INNER JOIN user_logins ON user_logins.user_id = users.id 
WHERE users.school_id = 1915 
GROUP BY users.id, users.name, users.email, users.mobile, users.last_login, users.created_at
ORDER BY logins DESC 
LIMIT 30 OFFSET 0;
```

**Changes:**
- Removed `DISTINCT` (GROUP BY already ensures uniqueness)
- Fixed `GROUP BY` to include all selected columns
- Used alias `logins` in ORDER BY

---

### Solution 2: Subquery Approach (Recommended)

Push the aggregation and sorting into a subquery that only returns 30 user IDs:

```sql
SELECT 
    u.id, 
    u.name, 
    u.email, 
    u.mobile, 
    u.last_login, 
    top_users.logins, 
    u.created_at 
FROM (
    SELECT 
        users.id,
        COUNT(user_logins.id) AS logins
    FROM users 
    INNER JOIN user_logins ON user_logins.user_id = users.id 
    WHERE users.school_id = 1915 
    GROUP BY users.id
    ORDER BY logins DESC 
    LIMIT 30 OFFSET 0
) AS top_users
INNER JOIN users u ON u.id = top_users.id
ORDER BY top_users.logins DESC;
```

**Why this is faster:**
- Inner query only returns 30 rows with IDs and counts
- Outer query fetches user details for only those 30 users
- Reduces data shuffling significantly

---

### Solution 3: Pre-aggregate Logins (Best for Pagination)

```sql
SELECT 
    u.id, 
    u.name, 
    u.email, 
    u.mobile, 
    u.last_login, 
    login_counts.logins, 
    u.created_at 
FROM users u
INNER JOIN (
    SELECT 
        ul.user_id,
        COUNT(*) AS logins
    FROM user_logins ul
    INNER JOIN users us ON us.id = ul.user_id AND us.school_id = 1915
    GROUP BY ul.user_id
    ORDER BY logins DESC
    LIMIT 30 OFFSET 0
) AS login_counts ON login_counts.user_id = u.id
ORDER BY login_counts.logins DESC;
```

---

## Index Recommendations

### Required Indexes

```sql
-- If not already present, ensure these indexes exist:

-- 1. Index on user_logins for counting (you already have this)
CREATE INDEX index_user_logins_on_user_id ON user_logins(user_id);

-- 2. Composite index on users for school filtering
CREATE INDEX index_users_on_school_id ON users(school_id);

-- 3. BETTER: Covering index to avoid table lookups
CREATE INDEX index_users_school_covering ON users(school_id, id, name, email, mobile, last_login, created_at);
```

### Verify with EXPLAIN

After applying optimizations, verify with:

```sql
EXPLAIN ANALYZE 
SELECT ... (your optimized query)
```

---

## Expected Performance Improvement

| Metric | Before | After (Estimated) |
|--------|--------|-------------------|
| Total Time | 39,104ms | < 500ms |
| Rows Processed | 9.03 million | ~450,000 (for aggregation only) |
| Temporary Table Size | 414,301 rows | 30 rows |

---

## Summary

The main issue is that the query processes **9 million joined rows** and aggregates **400,000+ groups** just to return **30 rows**.

**Quick wins:**
1. Remove `DISTINCT` (it's redundant with `GROUP BY`)
2. Fix `GROUP BY` to reference `users.id`
3. Use a subquery to limit before fetching all columns

**Best solution:** Solution 2 or 3 - use a subquery to find the top 30 user IDs first, then join to get full details.
