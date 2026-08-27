with source as (select * from {{ source('raw', 'products') }})

select
    product_id,
    product_code,
    product_name,
    line_of_business,
    base_annual_premium,
    _loaded_at
from source
