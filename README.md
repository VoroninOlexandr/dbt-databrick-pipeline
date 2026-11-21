# Job Market Analytics Pipeline (dbt + Databricks)

End-to-end analytics engineering pipeline that ingests ~843K raw job scrapes and ~3.3M skill records into Databricks Unity Catalog, transforms them with dbt 2.0 into a tested Star Schema (**491,140 unique job postings** across **65,970 companies**), tracks daily changes with SCD Type 2 snapshots, and powers six market and salary analyses.

## Tech Stack

- **Data Platform:** Databricks (Unity Catalog, Serverless SQL Warehouse, Delta Lake)
- **Transformation & Testing:** dbt 2.0, SQL, Jinja, `dbt_utils`
- **Ingestion & Tooling:** Python 3.12, `uv`

## What Was Built

1. **Automated Raw Ingestion (`scripts/load_raw.py`):** Downloads 12 months of Parquet files (~85 MB) directly into a Unity Catalog Volume and lands them as untouched Bronze tables (`raw.jobs.raw_job_postings`, `raw.jobs.raw_job_skills`).
2. **Staging & Parsing (`models/staging/`):** Filters scraper errors, parses free-text salary ranges into numeric `salary_min` / `salary_max` / `salary_avg` via a custom regex Jinja macro (`parse_salary`), extracts currency/period, and expands JSON benefit arrays into boolean flags using a Jinja loop + `slugify` macro.
3. **Star Schema & Incremental Loading (`models/intermediate/`, `models/marts/`):**
   - `fct_job_postings`: Incremental `merge` model keyed on `job_id` with `QUALIFY row_number()` deduplication.
   - `dim_company`: Company-level posting volume and average annual USD salary.
   - `dim_skill`: Skill taxonomy enriched with a static `seeds/skill_categories.csv` lookup.
   - `bridge_job_skills`: Many-to-many bridge linking job postings to skills.
4. **Historical Change Tracking (`snapshots/snapshots.yml`):** SCD Type 2 snapshot (`job_postings_snapshot`) monitoring 13 attributes via the `check` strategy to preserve every historical edit to a posting or its salary band.
5. **Multi-Layer Data Quality (`tests/`, `models/*/*.yml`):**
   - **Unit test:** `test_parse_salary_shape` validates regex salary parsing edge cases.
   - **Custom generic tests:** `not_empty_string`, `not_negative`.
   - **Singular test:** `assert_salary_sane` enforces business bounds on salary fields.
   - **Schema tests:** Uniqueness, non-null, and foreign-key relationship checks across all mart tables.

## Architecture

```text
GitHub Parquet Releases (~85 MB, 12 months)
   |
   v  [scripts/load_raw.py]
Bronze (raw.jobs)
   |-- raw_job_postings (843K rows)
   |-- raw_job_skills   (3.3M rows)
   |
   v  [dbt build / dbt snapshot]
Staging (dev.staging)
   |-- stg_job_postings          (view: regex salary parsing, JSON benefits flags)
   |-- stg_job_skills            (view: normalized skill links)
   |-- stg_job_postings_current  (ephemeral: point-in-time deduplicated feed)
   |
   +--> Snapshots (dev.snapshots)
   |       |-- job_postings_snapshot  (SCD Type 2 history of posting & salary edits)
   |
   v
Intermediate (dev.intermediate)
   |-- int_skill_observations    (view: skill demand aggregations)
   |
   v
Marts (dev.marts) -- Star Schema
   |-- fct_job_postings          (incremental table, merge on job_id)
   |-- dim_company               (table: company volume & avg annual salary)
   |-- dim_skill                 (table: skill taxonomy enriched with seeds)
   |-- bridge_job_skills         (table: many-to-many posting-to-skill bridge)
```

## Analyses & Key Results

Six SQL analyses were built in `analytics/analyses/` on top of the Star Schema and SCD Type 2 snapshot:

### 1. Most In-Demand Skills (`in_demand_skills.sql`)
Ranks skills by frequency across all 491,140 unique postings (supports role filtering via `--vars '{"job_title": "..."}'`).

| Skill | Category | Postings | Market Share |
| :--- | :--- | ---: | ---: |
| SQL | Programming Languages | 270,017 | 55.0% |
| Python | Programming Languages | 269,380 | 54.8% |
| AWS | Infrastructure | 140,433 | 28.6% |
| Azure | Infrastructure | 134,663 | 27.4% |
| Spark | Infrastructure | 116,730 | 23.8% |

### 2. Top-Paying Skills (`top_skills_by_salary.sql`)
Ranks skills by average annual USD salary without a minimum volume filter.
- **Finding:** Specialized AI and web-data tools top raw averages — **Firecrawl** ($440,000), **Common Crawl** ($400,000), **NVIDIA DGX Cloud** ($351,625), **Tenstorrent** ($325,000), and **Nuro** ($264,198) — but appear in only 1 to 22 postings, demonstrating why volume filtering is required for reliable benchmarks.

### 3. Optimal Skills (`optimal_skills.sql`)
Balances compensation and market demand by filtering for skills with at least 100 salaried annual USD postings.

| Skill | Category | Salaried Postings | Avg Annual Salary (USD) |
| :--- | :--- | ---: | ---: |
| Domino | Machine Learning & AI | 195 | $228,699 |
| Magic | Applications | 140 | $198,645 |
| Loops | Analytics | 327 | $198,385 |
| Microsoft Planner | Applications | 114 | $196,027 |
| Ramp | Applications | 442 | $188,737 |

### 4. Top Posting Editors (`top_posting_editors.sql`)
Identifies which companies modify their active job postings most frequently using `job_postings_snapshot`.

| Company | Jobs Edited |
| :--- | ---: |
| Meta | 415 |
| Capital One | 387 |
| The Hertz Corporation | 228 |
| SynergisticIT | 157 |
| PwC | 144 |

### 5. Historical Salary Revisions (`salary_changers.sql`)
Uses `LAG()` window functions and `IS DISTINCT FROM` over `job_postings_snapshot` to track every version-over-version salary edit.
- **Finding:** Detected **8,541 salary revision events** across **6,383 unique job postings**, capturing range increases, decreases, newly added salaries, and removed salary disclosures.

### 6. Largest Salary Swings (`salary_swings.sql`)
Measures the spread between the lowest and highest historical `salary_max` recorded for the same USD job posting.
- **Finding:** Surfaced extreme spreads of **$850,000 to $940,000** (jumps up to a $1,000,000 ceiling), helping distinguish aggressive compensation updates from upstream scraper anomalies.

## Project Structure

```text
dbt-databrick-pipeline/
├── scripts/
│   └── load_raw.py                  # EL notebook: downloads Parquet files into Unity Catalog
└── analytics/
    ├── dbt_project.yml              # dbt configuration and layer materializations
    ├── packages.yml                 # dbt_utils dependency
    ├── models/
    │   ├── sources.yml              # Bronze source definitions
    │   ├── staging/                 # Cleaning, JSON parsing, salary extraction, unit tests
    │   ├── intermediate/            # Reusable intermediate aggregations
    │   └── marts/                   # Star schema (fact, dimensions, bridge)
    ├── snapshots/
    │   └── snapshots.yml            # SCD Type 2 snapshot configuration
    ├── seeds/
    │   └── skill_categories.csv     # Static skill-to-category mapping
    ├── macros/                      # parse_salary, slugify, generate_schema_name
    ├── tests/                       # Custom generic and singular data quality tests
    └── analyses/                    # 6 market & salary-change analytical SQL queries
```

## Quick Start

### Prerequisites
- Python 3.12+ and `uv`
- Databricks workspace with Unity Catalog and a SQL Warehouse
- Configured `~/.dbt/profiles.yml` targeting your Databricks warehouse

### Run the Pipeline
```bash
# 1. Load Bronze tables by running scripts/load_raw.py in Databricks

# 2. Install Python and dbt dependencies
uv sync
cd analytics
dbt deps

# 3. Load seeds, build all models, run tests, and capture snapshots
dbt seed
dbt build
dbt snapshot

# 4. Run a parameterized analysis (optional)
dbt show --select in_demand_skills --vars '{"job_title": "Data Engineer"}'
```
