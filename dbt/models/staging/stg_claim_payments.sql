with source as (select * from {{ source('raw', 'claim_payments') }})

select
    claim_payment_id,
    claim_id,
    payment_date,
    amount,
    payment_type,
    payee_name,
    _loaded_at
from source
