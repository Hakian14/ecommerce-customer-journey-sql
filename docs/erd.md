# Entity-relationship diagram

The schema follows the shape of a Customer Data Platform (CDP): one golden
customer record, transactional tables keyed on `order_id`, and a clickstream
table that links anonymous browsing to known customers and to completed orders.

```mermaid
erDiagram
    customers ||--o{ orders : places
    customers ||--o{ web_events : "browses (nullable for anonymous)"
    orders ||--|{ order_items : contains
    orders ||--|| payments : "paid by"
    orders ||--o| reviews : "rated by"
    orders ||--o| web_events : "purchase event"
    products ||--o{ order_items : "sold as"
    products ||--o{ web_events : "viewed / carted"

    customers {
        TEXT customer_id PK
        TEXT signup_date
        TEXT city
        TEXT region
        TEXT acquisition_channel
        TEXT age_band
        TEXT gender
    }
    products {
        TEXT product_id PK
        TEXT category
        TEXT product_name
        INTEGER unit_price
        INTEGER unit_cost
    }
    orders {
        TEXT order_id PK
        TEXT customer_id FK
        TEXT order_ts
        TEXT channel
        TEXT status
        TEXT promo_code
        TEXT estimated_delivery_date
        TEXT delivered_at
    }
    order_items {
        TEXT order_id PK, FK
        INTEGER item_seq PK
        TEXT product_id FK
        INTEGER quantity
        INTEGER unit_price
        INTEGER discount_amount
    }
    payments {
        TEXT payment_id PK
        TEXT order_id FK
        TEXT payment_method
        INTEGER installments
        INTEGER shipping_fee
        INTEGER amount
    }
    reviews {
        TEXT review_id PK
        TEXT order_id FK
        INTEGER review_score
        TEXT created_at
    }
    web_events {
        INTEGER event_id PK
        TEXT session_id
        TEXT customer_id FK
        TEXT channel
        TEXT event_ts
        TEXT event_type
        TEXT product_id FK
        TEXT order_id FK
    }
```

## Grain of each table

| Table | One row per | Notes |
|---|---|---|
| `customers` | registered customer | `acquisition_channel` is how the customer was first acquired; `orders.channel` is where each order was placed. They are different dimensions on purpose. |
| `products` | SKU | `unit_cost` enables gross-margin analysis. |
| `orders` | order header | `status` is the order's final state at snapshot time. Revenue analyses use `delivered` only. |
| `order_items` | order line | `unit_price` is the price at time of sale; `discount_amount` is the total discount on the line. |
| `payments` | order (1:1) | `amount = Σ(line net value) + shipping_fee`, checked in `01_data_quality_checks.sql`. |
| `reviews` | order (0..1) | Only delivered/returned orders can have a review; ~62% do. |
| `web_events` | clickstream event | A session is a sequence of events sharing `session_id`. `customer_id` is NULL for anonymous sessions; `order_id` is populated only on `purchase` events. |
