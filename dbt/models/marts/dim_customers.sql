with customers as (select * from {{ ref('stg_customers') }}),

policies as (
    select
        customer_id,
        count(*)                           as policy_count,
        count_if(policy_status = 'ACTIVE') as active_policy_count,
        sum(annual_premium)                as lifetime_annual_premium
    from {{ ref('stg_policies') }}
    group by 1
)

select
    c.customer_id,
    c.first_name,
    c.last_name,
    c.first_name || ' ' || c.last_name                as full_name,
    c.email,
    c.phone,
    c.date_of_birth,
    datediff('year', c.date_of_birth, current_date()) as age_years,
    c.gender,
    c.city,
    c.state,
    c.postal_code,
    c.created_at,
    coalesce(p.policy_count, 0)                       as policy_count,
    coalesce(p.active_policy_count, 0)                as active_policy_count,
    coalesce(p.lifetime_annual_premium, 0)            as lifetime_annual_premium
from customers c
left join policies p on p.customer_id = c.customer_id
