with coverages as (select * from {{ ref('stg_coverages') }}),

policies as (select * from {{ ref('stg_policies') }}),

products as (select * from {{ ref('stg_products') }})

select
    cv.coverage_id,
    cv.coverage_code,
    cv.coverage_name,
    cv.limit_amount,
    cv.deductible,
    cv.premium_amount,

    cv.policy_id,
    p.policy_number,
    p.policy_status,
    p.customer_id,
    p.agent_id,
    pr.line_of_business,

    round(cv.premium_amount / nullif(p.annual_premium, 0), 4) as share_of_policy_premium
from coverages cv
left join policies p on p.policy_id = cv.policy_id
left join products pr on pr.product_id = p.product_id
