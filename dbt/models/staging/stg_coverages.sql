with source as (select * from {{ source('raw', 'coverages') }})

select
    coverage_id,
    policy_id,
    coverage_code,
    coverage_name,
    limit_amount,
    deductible,
    premium_amount,
    _loaded_at
from source
