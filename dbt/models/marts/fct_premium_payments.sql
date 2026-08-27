with payments as (select * from {{ ref('stg_premium_payments') }}),
     policies as (select * from {{ ref('stg_policies') }})

select
    pp.premium_payment_id,
    pp.policy_id,
    p.policy_number,
    p.customer_id,
    p.agent_id,
    pp.installment_number,
    pp.due_date,
    pp.paid_date,
    pp.amount,
    pp.payment_method,
    pp.payment_status,
    pp.paid_date is not null                          as is_paid,
    case
        when pp.paid_date is not null
        then datediff('day', pp.due_date, pp.paid_date)
    end                                               as days_late
from payments pp
left join policies p on p.policy_id = pp.policy_id
