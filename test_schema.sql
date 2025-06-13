-- Multi-Currency POS System Test Script
-- Run this after deploying the main schema to test functionality

\echo '=== Testing Multi-Currency POS System ==='
\echo ''

-- Test 1: Check if all tables were created
\echo '1. Checking table creation...'
SELECT COUNT(*) as table_count FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

-- Test 2: Verify ENUM types
\echo '2. Checking ENUM types...'
SELECT typname FROM pg_type WHERE typtype = 'e' ORDER BY typname;

-- Test 3: Check currencies setup
\echo '3. Checking currencies...'
SELECT code, name, symbol, is_base_currency FROM currencies ORDER BY code;

-- Test 4: Check exchange rates
\echo '4. Checking exchange rates...'
SELECT from_currency, to_currency, rate, effective_date 
FROM exchange_rates 
WHERE is_active = true 
ORDER BY from_currency, to_currency;

-- Test 5: Test currency conversion functions
\echo '5. Testing currency conversion...'
SELECT 
    get_exchange_rate('USD', 'LAK') as usd_to_lak_rate,
    get_exchange_rate('USD', 'THB') as usd_to_thb_rate,
    get_exchange_rate('LAK', 'THB') as lak_to_thb_rate;

SELECT 
    convert_currency(100.00, 'USD', 'LAK') as "100 USD in LAK",
    convert_currency(100.00, 'USD', 'THB') as "100 USD in THB",
    convert_currency(50000, 'LAK', 'USD') as "50000 LAK in USD";

-- Test 6: Test currency formatting
\echo '6. Testing currency formatting...'
SELECT 
    format_currency(100.00, 'USD') as formatted_usd,
    format_currency(210000, 'LAK') as formatted_lak,
    format_currency(3650.00, 'THB') as formatted_thb;

-- Test 7: Check indexes were created
\echo '7. Checking performance indexes...'
SELECT COUNT(*) as index_count FROM pg_indexes WHERE schemaname = 'public';

-- Test 8: Test materialized views
\echo '8. Checking materialized views...'
SELECT schemaname, matviewname FROM pg_matviews WHERE schemaname = 'public';

-- Test 9: Sample product price display in multiple currencies
\echo '9. Testing multi-currency product view...'
-- First insert some test data
INSERT INTO categories (name, display_order) VALUES 
('Coffee', 1), ('Pastries', 2) 
ON CONFLICT (name) DO NOTHING;

INSERT INTO products (name, description, category_id) VALUES 
('Latte', 'Espresso with steamed milk', 1),
('Cappuccino', 'Espresso with foamed milk', 1)
ON CONFLICT DO NOTHING;

INSERT INTO product_variations (product_id, size, type, base_price, sku) VALUES 
(1, 'medium', 'hot', 4.50, 'LAT-M-HOT'),
(2, 'medium', 'hot', 4.00, 'CAP-M-HOT')
ON CONFLICT (sku) DO NOTHING;

-- Test the multi-currency view
SELECT * FROM product_prices_multi_currency LIMIT 2;

-- Test 10: Sample order scenario
\echo '10. Testing sample order creation...'
-- Insert test employee and customer
INSERT INTO employees (name, pin, role) VALUES 
('Test Cashier', '123456', 'cashier')
ON CONFLICT (pin) DO NOTHING;

INSERT INTO customers (phone, name) VALUES 
('+856-20-123-4567', 'Test Customer')
ON CONFLICT (phone) DO NOTHING;

-- Create sample order in LAK
INSERT INTO orders (
    order_number, employee_id, customer_id, order_time,
    currency_code, exchange_rate, subtotal, tax_rate, tax_amount, total_amount, base_total_amount, status
) VALUES (
    'TEST-001', 1, 1, CURRENT_TIMESTAMP,
    'LAK', get_exchange_rate('USD', 'LAK'), 
    convert_currency(8.50, 'USD', 'LAK'), 
    8.5, 
    convert_currency(0.72, 'USD', 'LAK'),
    convert_currency(9.22, 'USD', 'LAK'),
    9.22,
    'paid'
) ON CONFLICT (order_number) DO NOTHING;

-- Check if order was created
SELECT order_number, currency_code, total_amount, base_total_amount, status 
FROM orders WHERE order_number = 'TEST-001';

\echo ''
\echo '=== Multi-Currency POS System Test Complete ==='
\echo 'If all tests passed, your system is ready for production!'
\echo ''
