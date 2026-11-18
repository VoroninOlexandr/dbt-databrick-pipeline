{%
    set extension_keywords = ["No degree mentioned", "Health insurance", "Dental insurance", "Paid time off"]
%}


With source AS(
    SELECT *
    FROM {{ source('jobs','raw_job_postings') }}
    WHERE ERROR IS NOT TRUE AND job_id IS NOT NULL
),
parsed AS(
    SELECT *,
            FROM_JSON(job_extensions_raw,'array<string>') as job_extention
    FROM source

),
cleaned AS(
SELECT 
    job_id,
    job_title,
    TRIM(company_name) as company_name,
    job_location,
    REGEXP_REPLACE(job_via,'^via','') as source_platform,
    job_posted_at,

    job_schedule_type,
    job_work_from_home,
    search_time as searched_at,
    search_date,
    search_term,
    search_location,
    job_salary,
    {{parse_salary('min')}} AS salary_min,
    {{parse_salary('max')}} AS salary_max,
    ({{parse_salary('min')}} + {{parse_salary('max')}}) / 2 AS salary_avg,
    NULLIF(REGEXP_EXTRACT(job_salary, 'an? (year|hour|month|day|week)$', 1), '') AS salary_period,
    CASE
        WHEN job_salary IS NOT NULL
        THEN COALESCE(NULLIF(TRIM(REGEXP_EXTRACT(job_salary, '^([^0-9]+)', 1)), ''), 'USD')
    END AS salary_currency,
    {% for keyword in extension_keywords %}
    array_contains(job_extention, "{{keyword}}") AS has_{{slugify(keyword)}}
    {{- "," if not loop.last}}
    {% endfor%}
FROM parsed
)

SELECT *
FROM cleaned


