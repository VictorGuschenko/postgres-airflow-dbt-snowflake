with claims as (select * from {{ ref('stg_claims') }}),

policies as (select * from {{ ref('stg_policies') }}),

products as (select * from {{ ref('stg_products') }}),

claim_payments as (
    select
        claim_id,
        sum(amount)                                                      as total_paid,
        sum(case when payment_type = 'INDEMNITY' then amount else 0 end) as indemnity_paid,
        sum(case when payment_type = 'EXPENSE' then amount else 0 end)   as expense_paid,
        count(*)                                                         as payment_count
    from {{ ref('stg_claim_payments') }}
    group by 1
)

select
    cl.claim_id,
    cl.claim_number,
    cl.claim_type,
    cl.claim_status,
    cl.incident_date,
    cl.reported_date,
    cl.closed_date,
    datediff('day', cl.incident_date, cl.reported_date)       as days_to_report,
    datediff('day', cl.reported_date, cl.closed_date)         as days_to_close,

    cl.policy_id,
    p.policy_number,
    p.customer_id,
    p.agent_id,
    pr.line_of_business,

    cl.estimated_amount,
    cl.paid_amount,
    round(cl.paid_amount / nullif(cl.estimated_amount, 0), 4) as paid_to_estimate_ratio,

    coalesce(cp.total_paid, 0)                                as claim_payments_total,
    coalesce(cp.indemnity_paid, 0)                            as claim_payments_indemnity,
    coalesce(cp.expense_paid, 0)                              as claim_payments_expense,
    coalesce(cp.payment_count, 0)                             as claim_payment_count
from claims cl
left join policies p on p.policy_id = cl.policy_id
left join products pr on pr.product_id = p.product_id
left join claim_payments cp on cp.claim_id = cl.claim_id
