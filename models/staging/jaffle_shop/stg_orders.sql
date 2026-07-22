{{
    config(
        materialized = 'table',
        unique_key = 'order_id'
    )
}}

with

source as (

    select * from {{ source('jaffle_shop', 'orders') }}

),

renamed as (

    select

        ----------  ids
        id as order_id,
        user_id as customer_id,

        ---------- properties
        status as order_status,

        ---------- timestamps
        order_date as ordered_at

    from source

)

select * from renamed