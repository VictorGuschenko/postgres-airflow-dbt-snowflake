with source as (select * from {{ source('raw', 'agents') }})

select
    agent_id,
    first_name,
    last_name,
    email,
    hire_date,
    region,
    commission_rate,
    is_active,
    _loaded_at
from source
