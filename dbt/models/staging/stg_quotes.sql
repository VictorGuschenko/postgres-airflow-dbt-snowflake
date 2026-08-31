with source as (select * from {{ source('raw', 'quotes') }})

select
    quote_id,
    quote_number,
    customer_id,
    agent_id,
    product_id,
    status                          as quote_status,
    quoted_annual_premium,
    created_at,
    decision_date,
    converted_policy_id,
    converted_policy_id is not null as is_converted,
    _loaded_at
from source
