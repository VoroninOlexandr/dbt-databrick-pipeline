{%
    set extension_keywords = ["No degree mentioned", "Health insurance", "Dental insurance", "Paid time off"]
%}


With source AS(
SELECT *
FROM {{ source('jobs','raw_job_postings') }}
WHERE ERROR IS NOT TRUE
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
    job_salary,
    job_schedule_type,
    job_work_from_home,
    search_time as searched_at,
    search_date,
    search_term,
    search_location,
    {% for keyword in extension_keywords %}
    array_contains(job_extention, "{{keyword}}") AS has_{{keyword | lower | replace(' ', '_')}}
    {{"," if not loop.last}}
    {% endfor%}
FROM parsed
)

SELECT *
FROM cleaned