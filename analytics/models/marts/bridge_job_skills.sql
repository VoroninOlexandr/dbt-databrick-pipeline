WITH job_skills AS (
    SELECT * FROM {{ ref('stg_job_skills') }}
),

job_postings AS (
    SELECT * FROM {{ ref('fct_job_postings') }}
)

SELECT
    job_id,
    skill_id,
    skill_keyword
FROM job_skills
INNER JOIN job_postings USING (job_id)
