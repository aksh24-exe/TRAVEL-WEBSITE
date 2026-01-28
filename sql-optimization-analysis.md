# SQL Query Performance Analysis & Optimization

## Summary of Optimizations

| Query | Before | After | Improvement |
|-------|--------|-------|-------------|
| User Logins Query | 39 seconds | ~5 seconds | **8x faster** |
| User Quizzes Query | 76 seconds | 4.5 seconds | **17x faster** |

---

# Query 1: User Logins Query

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

## Problems Identified

| Issue | Impact |
|-------|--------|
| `DISTINCT` + `GROUP BY` together | Forces duplicate removal after aggregation |
| `GROUP BY user_logins.user_id` | Should be `GROUP BY users.id` |

## Optimized Query

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
2. **Changed `GROUP BY user_logins.user_id`** → **`GROUP BY users.id`**
3. **Used alias `logins`** in ORDER BY

### Optional Index (if performance still slow):

```sql
CREATE INDEX idx_users_school_id ON users (school_id, id);
```

---

# Query 2: User Quizzes Query (Subjective Answers)

## Original Query

```sql
SELECT DISTINCT courses.id, courses.title, courses.course_type, quizzes.mode, 
       user_quizzes.quiz_id, max(user_quizzes.submitted_time) as submitted_time 
FROM courses USE INDEX(index_courses_on_school_id_and_status) 
INNER JOIN quizzes ON courses.id = quizzes.course_id AND quizzes.school_id = courses.school_id 
INNER JOIN user_quizzes ON user_quizzes.quiz_id = quizzes.id 
INNER JOIN user_courses ON user_courses.school_id = courses.school_id 
    AND user_courses.user_id = user_quizzes.user_id 
    AND (user_courses.course_id = courses.id 
         OR user_courses.course_id IN (SELECT pack_id FROM packages WHERE packages.course_id = courses.id)) 
WHERE courses.status IN (2, 4) AND courses.school_id = 1915 
    AND user_quizzes.is_subjective_answered = 1 AND quizzes.mode = 0 
    AND user_quizzes.submitted_time IS NOT NULL 
GROUP BY quizzes.course_id 
ORDER BY submitted_time DESC LIMIT 30 OFFSET 0
```

**Original execution time: 76 seconds**

## Problems Identified

| Issue | Impact |
|-------|--------|
| `DISTINCT` + `GROUP BY` | Redundant duplicate removal |
| `USE INDEX` hint | Forces suboptimal index |
| `GROUP BY quizzes.course_id` only | Incorrect, missing other columns |
| user_quizzes scans 66 rows, keeps 0.23 | 99.7% wasted reads |

## Optimized Query

```sql
SELECT 
    courses.id, 
    courses.title, 
    courses.course_type, 
    quizzes.mode, 
    uq.quiz_id, 
    MAX(uq.submitted_time) AS submitted_time 
FROM user_quizzes uq
INNER JOIN quizzes ON quizzes.id = uq.quiz_id 
    AND quizzes.mode = 0 
    AND quizzes.school_id = 1915
INNER JOIN courses ON courses.id = quizzes.course_id 
    AND courses.school_id = 1915 
    AND courses.status IN (2, 4)
INNER JOIN user_courses ON user_courses.school_id = 1915 
    AND user_courses.user_id = uq.user_id 
    AND (user_courses.course_id = courses.id 
         OR user_courses.course_id IN (SELECT pack_id FROM packages WHERE packages.course_id = courses.id))
WHERE uq.is_subjective_answered = 1 
AND uq.submitted_time IS NOT NULL 
GROUP BY courses.id, courses.title, courses.course_type, quizzes.mode, uq.quiz_id
ORDER BY submitted_time DESC 
LIMIT 30;
```

**Optimized execution time: 4.5 seconds (17x faster)**

### Changes Made:
1. **Removed `DISTINCT`** — Redundant with GROUP BY
2. **Removed `USE INDEX` hint** — Let optimizer choose
3. **Fixed `GROUP BY`** — Include all non-aggregated columns
4. **Reordered query** — Cleaner structure for optimizer

## Performance Comparison

| Metric | Before | After |
|--------|--------|-------|
| Total Time | 76,701ms | 4,550ms |
| Improvement | - | **17x faster** |

## Remaining Bottleneck

```
user_quizzes: scans 66.4 rows per loop, keeps 0.23
17,008 loops × 66 rows = 1.13 million rows scanned
```

### Would fix it (if index creation allowed):
```sql
CREATE INDEX idx_user_quizzes_subjective 
ON user_quizzes (quiz_id, is_subjective_answered, submitted_time, user_id);
```

---

# General Optimization Principles

## 1. Remove Redundant DISTINCT

If using `GROUP BY`, `DISTINCT` is almost always unnecessary.

## 2. Fix GROUP BY Columns

Include all non-aggregated SELECT columns in GROUP BY.

## 3. Avoid USE INDEX Hints

Let the optimizer choose unless you have a specific reason.

## 4. Check EXPLAIN ANALYZE Output

Look for:
- High `loops` count with low `rows` kept = inefficient filter
- `Using temporary; Using filesort` = potential for optimization
- `filtered` percentage < 50% = index not selective enough

## 5. Index Recommendations

| Scenario | Recommended Index |
|----------|-------------------|
| WHERE + ORDER BY + LIMIT | (where_col, order_col) |
| JOIN with filter after | (join_col, filter_col) |
| GROUP BY with aggregate | (group_col, aggregate_col) |
