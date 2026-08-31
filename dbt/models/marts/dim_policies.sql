with policies as (select * from {{ ref('stg_policies') }}),

customers as (select * from {{ ref('stg_customers') }}),

agents as (select * from {{ ref('stg_agents') }}),

products as (select * from {{ ref('stg_products') }}),

coverages as (
    select
        policy_id,
        count(*)            as coverage_count,
        sum(limit_amount)   as total_coverage_limit,
        sum(premium_amount) as total_coverage_premium
    from {{ ref('stg_coverages') }}
    group by 1
),

quotes as (
    select
        converted_policy_id as policy_id,
        quote_id,
        quoted_annual_premium,
        created_at          as quote_created_at
    from {{ ref('stg_quotes') }}
    where converted_policy_id is not null
)

select
    p.policy_id,
    p.policy_number,
    p.policy_status,
    p.effective_date,
    p.expiration_date,
    p.annual_premium,
    p.payment_frequency,
    p.created_at,

    p.customer_id,
    c.first_name || ' ' || c.last_name         as customer_name,
    c.state                                    as customer_state,

    p.agent_id,
    a.first_name || ' ' || a.last_name         as agent_name,
    a.region                                   as agent_region,

    p.product_id,
    pr.product_code,
    pr.product_name,
    pr.line_of_business,

    coalesce(cov.coverage_count, 0)            as coverage_count,
    coalesce(cov.total_coverage_limit, 0)      as total_coverage_limit,
    coalesce(cov.total_coverage_premium, 0)    as total_coverage_premium,

    q.quote_id                                 as originating_quote_id,
    q.quoted_annual_premium,
    p.annual_premium - q.quoted_annual_premium as premium_vs_quote,

    p.effective_date <= current_date()
    and p.expiration_date > current_date()     as is_in_force_by_date
from policies p
left join customers c on c.customer_id = p.customer_id
left join agents a on a.agent_id = p.agent_id
left join products pr on pr.product_id = p.product_id
left join coverages cov on cov.policy_id = p.policy_id
left join quotes q on q.policy_id = p.policy_id
