-- ---------------------------------------------------------------------------
-- 00_schema.sql
-- Physical schema for the CDP-style e-commerce dataset.
-- Dialect: SQLite (runs unchanged on PostgreSQL except for the PRAGMA line
-- and the TEXT date columns, which would become TIMESTAMP / DATE).
-- ---------------------------------------------------------------------------

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS web_events;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

-- One row per registered customer (the "golden record" of the CDP).
CREATE TABLE customers (
    customer_id          TEXT PRIMARY KEY,
    signup_date          TEXT NOT NULL,            -- YYYY-MM-DD
    city                 TEXT NOT NULL,
    region               TEXT NOT NULL,            -- North / Central / South
    acquisition_channel  TEXT NOT NULL,            -- organic_search, paid_social, marketplace, referral, direct
    age_band             TEXT,
    gender               TEXT
);

CREATE TABLE products (
    product_id    TEXT PRIMARY KEY,
    category      TEXT NOT NULL,
    product_name  TEXT NOT NULL,
    unit_price    INTEGER NOT NULL,                -- VND, list price
    unit_cost     INTEGER NOT NULL                 -- VND, landed cost
);

-- Order header. status: delivered | cancelled | returned | in_transit
CREATE TABLE orders (
    order_id                 TEXT PRIMARY KEY,
    customer_id              TEXT NOT NULL REFERENCES customers(customer_id),
    order_ts                 TEXT NOT NULL,        -- YYYY-MM-DD HH:MM:SS
    channel                  TEXT NOT NULL,        -- web, mobile_app, marketplace, social_commerce
    status                   TEXT NOT NULL,
    promo_code               TEXT,
    estimated_delivery_date  TEXT NOT NULL,        -- YYYY-MM-DD
    delivered_at             TEXT                  -- NULL unless delivered/returned
);

CREATE TABLE order_items (
    order_id         TEXT NOT NULL REFERENCES orders(order_id),
    item_seq         INTEGER NOT NULL,
    product_id       TEXT NOT NULL REFERENCES products(product_id),
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    unit_price       INTEGER NOT NULL,             -- price at time of sale
    discount_amount  INTEGER NOT NULL DEFAULT 0,   -- total discount on the line
    PRIMARY KEY (order_id, item_seq)
);

CREATE TABLE payments (
    payment_id      TEXT PRIMARY KEY,
    order_id        TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
    payment_method  TEXT NOT NULL,                 -- cod, e_wallet, bank_transfer, credit_card
    installments    INTEGER NOT NULL DEFAULT 1,
    shipping_fee    INTEGER NOT NULL DEFAULT 0,
    amount          INTEGER NOT NULL               -- items net of discount + shipping
);

CREATE TABLE reviews (
    review_id     TEXT PRIMARY KEY,
    order_id      TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
    review_score  INTEGER NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    created_at    TEXT NOT NULL
);

-- Clickstream. customer_id is NULL for anonymous sessions.
-- event_type: page_view -> product_view -> add_to_cart -> checkout_start -> purchase
CREATE TABLE web_events (
    event_id     INTEGER PRIMARY KEY,
    session_id   TEXT NOT NULL,
    customer_id  TEXT REFERENCES customers(customer_id),
    channel      TEXT NOT NULL,
    event_ts     TEXT NOT NULL,
    event_type   TEXT NOT NULL,
    product_id   TEXT,
    order_id     TEXT
);

-- Indexes that the analysis queries lean on
CREATE INDEX idx_orders_customer_ts ON orders (customer_id, order_ts);
CREATE INDEX idx_orders_ts          ON orders (order_ts);
CREATE INDEX idx_items_order        ON order_items (order_id);
CREATE INDEX idx_items_product      ON order_items (product_id);
CREATE INDEX idx_events_session     ON web_events (session_id, event_ts);
CREATE INDEX idx_events_type        ON web_events (event_type);
CREATE INDEX idx_events_order       ON web_events (order_id);
