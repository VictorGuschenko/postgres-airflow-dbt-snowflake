# Design notes

## Why Parquet, not CSV, for the Postgres → Snowflake extract

Both formats work for the `extract → PUT to stage → COPY INTO` pattern. This
project uses Parquet for a hand-rolled loader that aims to copy tables
**one-to-one** without tuning a file format per table.

- **Types travel with the data.** Parquet embeds a schema. A Postgres
  `numeric(10,2)` lands as a Parquet decimal and becomes Snowflake `NUMBER(10,2)`
  exactly; `timestamptz` keeps its offset; `boolean` stays boolean; `NULL` is
  unambiguous. In CSV every value is text and Snowflake re-parses it on load —
  empty-string-vs-`NULL`, timestamp formats, and `t`/`f` booleans from Postgres
  all become things you have to get right by hand.
- **Column-name matching.** The DAG loads with
  `MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE`. Parquet carries field names, so
  column order and extra target columns (e.g. `_loaded_at`) don't matter. CSV
  supports that mode only with a header row and `PARSE_HEADER = TRUE`.
- **Smaller and faster.** Columnar + compressed: less to `PUT`, less for `COPY`
  to scan. Negligible at ~1k rows, but the pattern scales.
- **Fewer footguns.** No decisions about quoting, embedded commas/newlines,
  encoding, or empty string vs `NULL`.

CSV is still a legitimate choice — it is human-readable (you can open a staged
file and see what's wrong) and needs no `pyarrow` dependency. It is perfectly
adequate for small, simple data. The cost is a strict, explicit `FILE_FORMAT`:

```sql
FILE_FORMAT = (TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('')
  EMPTY_FIELD_AS_NULL = FALSE
  DATE_FORMAT = 'YYYY-MM-DD'
  TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF9 TZHTZM')
```

Miss one of those and you get silent bad data rather than an error.

**The one Parquet gotcha:** `pandas.read_sql` returns Postgres `numeric` as
Python `Decimal`. Make sure `extract_to_files` does not let pandas coerce those
columns to float before `to_parquet`, or the exact decimal values are lost.

## Other choices

- **ELT, not ETL.** Data lands in `RAW` untransformed; all shaping happens in
  Snowflake with dbt. Cheaper to re-run, and the raw copy is always there to
  re-derive from.
- **Config single-sourced.** `SNOWFLAKE_*` in `.env` feeds both the Airflow
  connection (assembled in `docker-compose.yaml`) and dbt (`profiles.yml`), so
  credentials exist once.
- **Deterministic mimic data.** `setseed()` means bugs are reproducible and
  diffs are meaningful. The seed also builds in exact reconciliation properties
  (coverage premiums sum to the policy premium; indemnity payments sum to the
  claim paid amount) that become dbt tests.
- **dbt runs in its own container.** Keeps the Airflow image free of dbt's
  dependency tree; the pipeline launches dbt exactly as a CI job would.
- **Full snapshot load.** Simplest correct thing. Real pipelines add
  incremental/CDC logic; that's deliberately left as an exercise.
