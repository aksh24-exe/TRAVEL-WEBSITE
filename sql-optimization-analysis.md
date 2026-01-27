# SQL Query Performance Analysis & Optimization (JOIN-Only Approach)

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

## Current Index Usage (from EXPLAIN)

```
users:        index_users_on_school_id_and_segment_id (school_id=1915) → 776,070 rows
user_logins:  index_user_logins_on_user_id (Using index - covering)
```

**Problems:** `Using temporary; Using filesort` on users table

---

## Performance Bottlenecks

| Issue | Impact |
|-------|--------|
| `DISTINCT` + `GROUP BY` together | Forces duplicate removal after aggregation |
| `GROUP BY user_logins.user_id` | Should be `GROUP BY users.id` |
| No covering index on users | Table lookups for every row |
| `Using temporary; Using filesort` | Full materialization + sort of 400K+ rows |

---

## Optimized Query (JOIN Only, No Subquery)

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
GROUP BY users.id
ORDER BY logins DESC 
LIMIT 30;
```

### Changes Made:
1. **Removed `DISTINCT`** — Redundant when using `GROUP BY`
2. **Changed `GROUP BY user_logins.user_id`** → **`GROUP BY users.id`** — Correct column reference
3. **Used alias `logins`** in ORDER BY — Cleaner syntax

---

## Required Index to Add

The key optimization is a **covering index** on the `users` table that includes all selected columns. This eliminates table lookups entirely.

```sql
CREATE INDEX idx_users_school_covering 
ON users (school_id, id, name, email, mobile, last_login, created_at);
```

### Why This Index Works:

| Benefit | Explanation |
|---------|-------------|
| **Eliminates table access** | All columns in SELECT are in the index |
| **Efficient filtering** | `school_id` is the first column (WHERE clause) |
| **Reduces I/O** | Index is smaller than full table rows |
| **Faster GROUP BY** | `id` is second column, helps with grouping |

---

## Index on user_logins (Already Optimal)

Your existing index is already being used as a covering index:

```sql
-- Already exists and is optimal:
CREATE INDEX index_user_logins_on_user_id ON user_logins(user_id);
```

The EXPLAIN shows `Using index` which means it's a covering index scan (no table lookup needed).

---

## Alternative: Composite Index with COUNT Optimization

If you want to optimize the COUNT operation further:

```sql
CREATE INDEX idx_user_logins_user_id_id 
ON user_logins (user_id, id);
```

This makes counting faster because both columns needed (`user_id` for join, `id` for count) are in the index.

---

## Final Optimized Setup

### Step 1: Add the covering index on users

```sql
CREATE INDEX idx_users_school_covering 
ON users (school_id, id, name, email, mobile, last_login, created_at);
```

### Step 2: Use the optimized query

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
GROUP BY users.id
ORDER BY logins DESC 
LIMIT 30;
```

### Step 3: Verify with EXPLAIN

```sql
EXPLAIN SELECT 
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
GROUP BY users.id
ORDER BY logins DESC 
LIMIT 30;
```

**Expected EXPLAIN output after optimization:**
- `Using index` on both tables (no table lookups)
- Smaller temporary table
- Faster filesort (less data to sort)

---

## Expected Performance Improvement

| Metric | Before | After (Estimated) |
|--------|--------|-------------------|
| Total Time | 39,104ms | **2,000-5,000ms** |
| Table Lookups | Yes | No (covering index) |
| Duplicate Removal | Yes (DISTINCT) | No |
| Rows in Temp Table | 414,301 | 414,301 (same, but faster) |

**Note:** Without subqueries, we still must aggregate all matching users. The covering index eliminates table lookups which is the main gain. The temporary table and filesort are unavoidable with ORDER BY on an aggregate + LIMIT.

---

## Summary

**Query fixes:**
- Remove `DISTINCT` (redundant)
- Change `GROUP BY user_logins.user_id` → `GROUP BY users.id`

**Index to add:**
```sql
CREATE INDEX idx_users_school_covering 
ON users (school_id, id, name, email, mobile, last_login, created_at);
```

This covering index will show `Using index` in EXPLAIN instead of table lookups, significantly reducing I/O.
