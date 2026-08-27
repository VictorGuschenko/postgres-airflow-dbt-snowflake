with policies as (select * from {{ ref('stg_policies') }}),

customers as (select * from {{ ref('stg_customers') }}),

agents as (select * from {{ ref('stg_agents') }}),

products as (select * from {{ ref('stg_products') }})

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
    c.first_name || ' ' || c.last_name     as customer_name,
    c.state                                as customer_state,

    p.agent_id,
    a.first_name || ' ' || a.last_name     as agent_name,
    a.region                               as agent_region,

    p.product_id,
    pr.product_code,
    pr.product_name,
    pr.line_of_business,

    p.effective_date <= current_date()
    and p.expiration_date > current_date() as is_in_force_by_date
from policies p
left join customers c on c.customer_id = p.customer_id
left join agents a on a.agent_id = p.agent_id
left join products pr on pr.product_id = p.product_id
