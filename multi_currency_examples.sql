-- Multi-Currency POS System Examples
-- This file shows how to use the multi-currency features

-- 1. View menu prices in all currencies
SELECT 
    product_name,
    size,
    type,
    usd_formatted as "USD Price",
    lak_formatted as "LAK Price", 
    thb_formatted as "THB Price"
FROM product_prices_multi_currency
ORDER BY product_name, size;

-- 2. Create an order in LAK currency
-- Step 1: Calculate prices in LAK
SELECT 
    variation_id,
    product_name,
    lak_price,
    lak_formatted
FROM product_prices_multi_currency 
WHERE variation_id IN (1, 2); -- Example: Latte variations

-- Step 2: Create order in LAK
BEGIN;

-- Insert order with LAK currency
INSERT INTO orders (
    order_number, 
    employee_id, 
    customer_id, 
    order_time, 
    currency_code, 
    exchange_rate,
    subtotal, 
    tax_rate, 
    tax_amount, 
    total_amount,
    base_total_amount,
    status
) VALUES (
    'CAFE-2025-1002',
    1, -- employee_id
    1, -- customer_id
    CURRENT_TIMESTAMP,
    'LAK',
    get_exchange_rate('LAK', 'USD'),
    115500, -- subtotal in LAK (5.50 USD * 21000)
    8.5, -- tax rate
    9817.5, -- tax in LAK
    125317.5, -- total in LAK
    convert_currency(125317.5, 'LAK', 'USD'), -- total in USD
    'paid'
) RETURNING order_id;

-- Assuming order_id = 2, insert order items
INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price) VALUES
(2, 2, 1, 5.50, 115500); -- Medium Latte: $5.50 = ₭115,500

-- Insert payment in LAK
INSERT INTO order_payments (
    order_id, 
    method_id, 
    currency_code, 
    amount, 
    base_amount, 
    exchange_rate,
    status
) VALUES (
    2,
    1, -- Cash payment method
    'LAK',
    125317.5, -- amount in LAK
    convert_currency(125317.5, 'LAK', 'USD'), -- amount in USD
    get_exchange_rate('LAK', 'USD'),
    'completed'
);

COMMIT;

-- 3. Create an order in THB currency
BEGIN;

INSERT INTO orders (
    order_number, 
    employee_id, 
    order_time, 
    currency_code, 
    exchange_rate,
    subtotal, 
    tax_rate, 
    tax_amount, 
    total_amount,
    base_total_amount,
    status
) VALUES (
    'CAFE-2025-1003',
    2, -- employee_id
    CURRENT_TIMESTAMP,
    'THB',
    get_exchange_rate('THB', 'USD'),
    200.75, -- subtotal in THB (5.50 USD * 36.5)
    8.5, -- tax rate
    17.06, -- tax in THB
    217.81, -- total in THB
    convert_currency(217.81, 'THB', 'USD'), -- total in USD
    'paid'
) RETURNING order_id;

-- Insert order items and payment...
COMMIT;

-- 4. Mixed currency payments (customer pays with multiple currencies)
-- Example: Order total $10 USD, customer pays $5 USD + ₭105,000 LAK
BEGIN;

INSERT INTO orders (
    order_number, 
    employee_id, 
    order_time, 
    currency_code, 
    exchange_rate,
    subtotal, 
    tax_rate, 
    tax_amount, 
    total_amount,
    base_total_amount,
    status
) VALUES (
    'CAFE-2025-1004',
    1,
    CURRENT_TIMESTAMP,
    'USD', -- Display currency
    1.0,
    9.26, -- subtotal
    8.0, -- tax rate
    0.74, -- tax
    10.00, -- total
    10.00, -- same as total since USD is base
    'paid'
) RETURNING order_id;

-- Payment 1: $5 USD
INSERT INTO order_payments (
    order_id, method_id, currency_code, amount, base_amount, exchange_rate
) VALUES (
    4, 1, 'USD', 5.00, 5.00, 1.0
);

-- Payment 2: ₭105,000 LAK (equivalent to $5 USD)
INSERT INTO order_payments (
    order_id, method_id, currency_code, amount, base_amount, exchange_rate
) VALUES (
    4, 1, 'LAK', 105000, convert_currency(105000, 'LAK', 'USD'), get_exchange_rate('LAK', 'USD')
);

COMMIT;

-- 5. Daily sales report by currency
SELECT 
    DATE(o.order_time) as sale_date,
    o.currency_code,
    COUNT(o.order_id) as total_orders,
    SUM(o.total_amount) as total_revenue_display_currency,
    SUM(o.base_total_amount) as total_revenue_usd,
    c.symbol as currency_symbol
FROM orders o
JOIN currencies c ON o.currency_code = c.code
WHERE o.status = 'paid'
    AND o.order_time >= CURRENT_DATE
GROUP BY DATE(o.order_time), o.currency_code, c.symbol
ORDER BY sale_date DESC, o.currency_code;

-- 6. Payment method usage by currency
SELECT 
    pm.name as payment_method,
    op.currency_code,
    COUNT(*) as transaction_count,
    SUM(op.amount) as total_amount_currency,
    SUM(op.base_amount) as total_amount_usd,
    c.symbol
FROM order_payments op
JOIN payment_methods pm ON op.method_id = pm.method_id
JOIN currencies c ON op.currency_code = c.code
WHERE op.status = 'completed'
    AND op.payment_time >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY pm.name, op.currency_code, c.symbol
ORDER BY pm.name, op.currency_code;

-- 7. Update exchange rates (should be done regularly)
-- This would typically be automated via API
INSERT INTO exchange_rates (from_currency, to_currency, rate, effective_date) VALUES
('USD', 'LAK', 21050.00, CURRENT_TIMESTAMP), -- Updated rate
('USD', 'THB', 36.75, CURRENT_TIMESTAMP),
('LAK', 'USD', 0.0000475, CURRENT_TIMESTAMP),
('THB', 'USD', 0.0272, CURRENT_TIMESTAMP)
ON CONFLICT (from_currency, to_currency, effective_date) 
DO UPDATE SET rate = EXCLUDED.rate;

-- 8. Currency conversion helper queries
-- Convert $10 USD to all supported currencies
SELECT 
    'USD' as from_currency,
    code as to_currency,
    10.00 as original_amount,
    convert_currency(10.00, 'USD', code) as converted_amount,
    format_currency(convert_currency(10.00, 'USD', code), code) as formatted
FROM currencies 
WHERE is_active = true;

-- 9. Cash drawer balance by currency
SELECT 
    op.currency_code,
    c.symbol,
    SUM(CASE WHEN pm.name = 'Cash' THEN op.amount ELSE 0 END) as cash_total,
    format_currency(
        SUM(CASE WHEN pm.name = 'Cash' THEN op.amount ELSE 0 END), 
        op.currency_code
    ) as cash_formatted
FROM order_payments op
JOIN payment_methods pm ON op.method_id = pm.method_id
JOIN currencies c ON op.currency_code = c.code
WHERE op.status = 'completed'
    AND DATE(op.payment_time) = CURRENT_DATE
GROUP BY op.currency_code, c.symbol
ORDER BY op.currency_code;

-- 10. Exchange rate history
SELECT 
    from_currency,
    to_currency,
    rate,
    effective_date,
    LAG(rate) OVER (PARTITION BY from_currency, to_currency ORDER BY effective_date) as previous_rate,
    ROUND(
        ((rate - LAG(rate) OVER (PARTITION BY from_currency, to_currency ORDER BY effective_date)) 
         / LAG(rate) OVER (PARTITION BY from_currency, to_currency ORDER BY effective_date)) * 100, 
        4
    ) as rate_change_percent
FROM exchange_rates
WHERE is_active = true
ORDER BY from_currency, to_currency, effective_date DESC;
