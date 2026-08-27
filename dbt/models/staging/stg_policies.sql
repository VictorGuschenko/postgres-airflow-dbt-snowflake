with source as (select * from {{ source('raw', 'policies') }})

select
    policy_id,
    policy_number,
    customer_id,
    agent_id,
    product_id,
    status as policy_status,
    effective_date,
    expiration_date,
    annual_premium,
    payment_frequency,
    created_at,
    _loaded_at
from source
