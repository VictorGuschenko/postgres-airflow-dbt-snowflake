with source as (select * from {{ source('raw', 'premium_payments') }})

select
    premium_payment_id,
    policy_id,
    installment_number,
    due_date,
    paid_date,
    amount,
    method as payment_method,
    status as payment_status,
    _loaded_at
from source
