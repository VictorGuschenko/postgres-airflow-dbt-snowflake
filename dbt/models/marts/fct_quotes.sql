with quotes as (select * from {{ ref('stg_quotes') }}),

products as (select * from {{ ref('stg_products') }}),

policies as (select * from {{ ref('stg_policies') }})

select
    q.quote_id,
    q.quote_number,
    q.quote_status,
    q.is_converted,
    q.created_at,
    q.decision_date,
    datediff('day', q.created_at::date, q.decision_date) as days_to_decision,

    q.customer_id,
    q.agent_id,
    q.product_id,
    pr.product_code,
    pr.line_of_business,

    q.quoted_annual_premium,
    q.converted_policy_id,
    p.annual_premium                                     as policy_annual_premium,
    p.annual_premium - q.quoted_annual_premium           as premium_uplift
from quotes q
left join products pr on pr.product_id = q.product_id
left join policies p on p.policy_id = q.converted_policy_id
