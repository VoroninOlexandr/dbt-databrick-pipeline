{{config(materialized = 'ephemeral')}}

SELECT
    *
FROM {{ ref('stg_job_postings') }}
WHERE 
    search_date <= CAST('{{var('as_of', run_started_at)}}' AS DATE)
QUALIFY row_number() over(partition by job_id order by searched_at desc) = 1