SELECT
    search_term,
    count(*) as postings
FROM raw.jobs.raw_job_postings
    GROUP BY search_term
    ORDER BY postings DESC
