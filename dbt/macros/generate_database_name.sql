{#-
    Route every model to <base>_<TARGET>, e.g. ANALYTICS_DB_DEV / ANALYTICS_DB_PROD,
    so dev and prod are fully isolated databases picked by the DBT_TARGET env var.

    `base` is a model-level `+database:` config when set, otherwise the
    SNOWFLAKE_DATABASE env var. This keeps model SQL, the sources in
    _staging__sources.yml, and the Airflow RAW load all pointing at the same
    physical database for a given target.
-#}
{%- macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- set base = custom_database_name if custom_database_name is not none
                   else env_var('SNOWFLAKE_DATABASE', 'ANALYTICS_DB') -%}
    {{- (base ~ '_' ~ target.name) | trim | upper -}}
{%- endmacro -%}
