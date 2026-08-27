with source as (select * from {{ source('raw', 'customers') }})

select
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    gender,
    address_line1,
    city,
    state,
    postal_code,
    created_at,
    _loaded_at
from source
