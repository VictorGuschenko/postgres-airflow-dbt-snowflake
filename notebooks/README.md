# GitHub API exploration

**Branch:** `feat/github_api_jupyter_request` (exploration only — not intended to merge into `main`)

## Task

Before writing a new Airflow DAG to pull data from the GitHub API (a second
source alongside `source_postgres`), understand what that API actually
returns and how to turn it into a flat table — by hand, in a notebook,
before automating any of it.

Goal for this notebook: fetch the top 10 most-starred GitHub repositories and
end up with a flat CSV, one row per repo.

## Steps taken (`github_top_repos.ipynb`)

1. **Call the API.** `requests.get()` against GitHub's search endpoint:
   `https://api.github.com/search/repositories?q=stars:%3E0&sort=stars&order=desc&per_page=10`
   — unauthenticated, sorted by stars descending, 10 results.
2. **Inspect the raw response.** Called `.json()` on the response to see its
   shape: a dict with `total_count` and an `items` list, one big nested dict
   per repository.
3. **Explore a single repo.** Pulled out `data['items'][0]` to see which
   fields exist (`name`, `stargazers_count`, `owner`, `language`, etc.)
   before deciding what to keep.
4. **Flatten a couple of fields first.** Built a small list of
   `(name, stargazers_count)` tuples across all items, to prove the
   list-comprehension approach works before scaling it up.
5. **Flatten the full row shape.** Extended that to all the fields wanted per
   repo: `name`, `full_name`, `owner`, `stars`, `forks`, `open_issues`,
   `language`, `url`.
6. **Load into pandas and export.** Built a `pandas.DataFrame` from the list
   of dicts and wrote it out with `.to_csv()`.

## Output

`github_top_repos.csv` — one row per repo, columns as listed above. It is
**gitignored** (see repo `.gitignore`): it's a generated artifact of running
the notebook, not the work itself, the same reasoning the main pipeline
applies to `data/` (its Parquet extract staging area).

## Why this exists

This was a deliberate manual pass — no DAG, no Airflow — to understand the
API response shape and the JSON-to-flat-table step before building a real
`github_to_snowflake`-style DAG that automates: call API → save file → `PUT`
to a Snowflake stage → `COPY INTO` a `RAW` table → (optionally) a dbt staging
model. That DAG, if built, belongs on its own branch following the same
pattern as `airflow/dags/postgres_to_snowflake.py`.
