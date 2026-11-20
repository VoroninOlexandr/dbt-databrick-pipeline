WITH versions AS (

    SELECT * FROM {{ ref('job_postings_snapshot') }}

),

with_previous AS (

    SELECT
        job_id,
        job_title,
        company_name,
        salary_min,
        salary_max,
        salary_currency,
        salary_period,
        dbt_valid_from,
        LAG(dbt_valid_from)  OVER (PARTITION BY job_id ORDER BY dbt_valid_from) AS prev_valid_from,
        LAG(salary_min)      OVER (PARTITION BY job_id ORDER BY dbt_valid_from) AS prev_salary_min,
        LAG(salary_max)      OVER (PARTITION BY job_id ORDER BY dbt_valid_from) AS prev_salary_max,
        LAG(salary_currency) OVER (PARTITION BY job_id ORDER BY dbt_valid_from) AS prev_salary_currency
    FROM versions

)

SELECT
    company_name,
    job_title,
    CASE
        WHEN prev_salary_max IS NULL AND salary_max IS NOT NULL THEN 'Salary Added'
        WHEN prev_salary_max IS NOT NULL AND salary_max IS NULL THEN 'Salary Removed'
        WHEN salary_max > prev_salary_max                       THEN 'Increased'
        WHEN salary_max < prev_salary_max                       THEN 'Decreased'
        ELSE 'Range Adjusted'
    END AS change_type,
    COALESCE(salary_currency, prev_salary_currency) AS currency,
    salary_period,
    ROUND(prev_salary_min, 0) AS prev_min,
    ROUND(prev_salary_max, 0) AS prev_max,
    ROUND(salary_min, 0)      AS new_min,
    ROUND(salary_max, 0)      AS new_max,
    ROUND(salary_max - prev_salary_max, 0) AS max_diff,
    ROUND(
        (salary_max - prev_salary_max) / NULLIF(prev_salary_max, 0) * 100,
        1
    ) AS max_pct_change,
    CAST(dbt_valid_from AS DATE) AS changed_date,
    DATEDIFF(dbt_valid_from, prev_valid_from) AS days_since_prev
FROM with_previous
WHERE prev_valid_from IS NOT NULL
  AND (
    salary_min IS DISTINCT FROM prev_salary_min
    OR salary_max IS DISTINCT FROM prev_salary_max
  )

ORDER BY ABS(max_pct_change) DESC NULLS LAST