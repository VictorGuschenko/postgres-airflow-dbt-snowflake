with agents as (select * from {{ ref('stg_agents') }}),

quotes as (
    select
        agent_id,
        count(*)                            as quote_count,
        count_if(quote_status = 'ACCEPTED') as quotes_accepted,
        sum(quoted_annual_premium)          as quoted_premium_total
    from {{ ref('stg_quotes') }}
    group by 1
),

policies as (
    select
        agent_id,
        count(*)                           as policy_count,
        count_if(policy_status = 'ACTIVE') as active_policy_count,
        sum(annual_premium)                as written_annual_premium
    from {{ ref('stg_policies') }}
    group by 1
)

select
    a.agent_id,
    a.first_name || ' ' || a.last_name                                  as agent_name,
    a.region,
    a.commission_rate,
    a.is_active,

    coalesce(q.quote_count, 0)                                          as quote_count,
    coalesce(q.quotes_accepted, 0)                                      as quotes_accepted,
    round(coalesce(q.quotes_accepted, 0) / nullif(q.quote_count, 0), 4) as quote_conversion_rate,

    coalesce(p.policy_count, 0)                                         as policy_count,
    coalesce(p.active_policy_count, 0)                                  as active_policy_count,
    coalesce(p.written_annual_premium, 0)                               as written_annual_premium,
    round(coalesce(p.written_annual_premium, 0) * a.commission_rate, 2) as estimated_annual_commission
from agents a
left join quotes q on q.agent_id = a.agent_id
left join policies p on p.agent_id = a.agent_id
