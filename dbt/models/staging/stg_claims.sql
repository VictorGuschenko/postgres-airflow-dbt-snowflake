with source as (select * from {{ source('raw', 'claims') }})

select
    claim_id,
    claim_number,
    policy_id,
    claim_type,
    status                                        as claim_status,
    incident_date,
    reported_date,
    closed_date,
    estimated_amount,
    paid_amount,
    description
from source
