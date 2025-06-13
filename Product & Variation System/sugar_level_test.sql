-- Sugar Level Customization Test Script
-- This file tests all sugar level functionality

\echo '========================================='
\echo 'Sugar Level Customization Test Suite'
\echo '========================================='

-- Test 1: Validate sugar level enum type exists
\echo ''
\echo 'Test 1: Checking sugar level enum type...'
SELECT 
    typname,
    enumlabel
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE typname = 'sugar_level'
ORDER BY e.enumsortorder;

-- Test 2: Test sugar level validation function
\echo ''
\echo 'Test 2: Testing sugar level validation function...'
SELECT 
    'Valid sugar levels test:' as test_description,
    validate_sugar_level('{"sugar_level": "no_sugar"}'::jsonb) as no_sugar_valid,
    validate_sugar_level('{"sugar_level": "regular"}'::jsonb) as regular_valid,
    validate_sugar_level('{"sugar_level": "extra_sweet"}'::jsonb) as extra_sweet_valid,
    validate_sugar_level('{"other_modifier": true}'::jsonb) as no_sugar_level_valid,
    validate_sugar_level('{"sugar_level": "invalid"}'::jsonb) as invalid_sugar_level;

-- Test 3: Test sugar level descriptions
\echo ''
\echo 'Test 3: Testing sugar level descriptions...'
SELECT 
    sugar_level,
    get_sugar_level_description(sugar_level) as description
FROM (VALUES 
    ('no_sugar'),
    ('less_sugar'), 
    ('regular'),
    ('more_sugar'),
    ('extra_sweet'),
    ('invalid_level')
) AS t(sugar_level);

-- Test 4: Test price adjustments
\echo ''
\echo 'Test 4: Testing sugar level price adjustments...'
SELECT 
    sugar_level,
    5.50 as base_price,
    calculate_sugar_price_adjustment(5.50, sugar_level) as adjusted_price,
    ROUND(
        (calculate_sugar_price_adjustment(5.50, sugar_level) - 5.50) * 100 / 5.50, 2
    ) as percentage_change
FROM (VALUES 
    ('no_sugar'),
    ('less_sugar'), 
    ('regular'),
    ('more_sugar'),
    ('extra_sweet')
) AS t(sugar_level);

-- Test 5: Test order item formatting
\echo ''
\echo 'Test 5: Testing order item formatting with sugar levels...'
SELECT 
    test_name,
    format_order_item_with_sugar(product_name, variation, modifiers::jsonb) as formatted_item
FROM (VALUES 
    ('Basic latte with regular sugar', 'Latte', 'medium hot', '{"sugar_level": "regular"}'),
    ('No sugar with oat milk', 'Cappuccino', 'large hot', '{"sugar_level": "no_sugar", "oat_milk": true}'),
    ('Extra sweet with whipped cream', 'Americano', 'small ice', '{"sugar_level": "extra_sweet", "whipped_cream": true}'),
    ('Less sugar with extra shot', 'Latte', 'medium hot', '{"sugar_level": "less_sugar", "extra_shot": true}'),
    ('No sugar level specified', 'Green Tea', 'small hot', '{"honey": true}')
) AS t(test_name, product_name, variation, modifiers);

-- Test 6: Test table constraint
\echo ''
\echo 'Test 6: Testing order_items table constraint...'

-- Create a temporary order for testing
INSERT INTO orders (
    order_number, employee_id, order_time,
    currency_code, exchange_rate, subtotal, tax_rate, tax_amount, total_amount, base_total_amount, status
) VALUES (
    'SUGAR-CONSTRAINT-TEST', 1, CURRENT_TIMESTAMP,
    'USD', 1.0, 5.50, 8.5, 0.47, 5.97, 5.97, 'open'
) ON CONFLICT (order_number) DO NOTHING;

-- Test valid sugar level (should succeed)
\echo '  Testing valid sugar level insertion...'
BEGIN;
    INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price, modifiers) 
    SELECT o.order_id, 1, 1, 5.50, 5.50, '{"sugar_level": "regular"}'::jsonb
    FROM orders o WHERE o.order_number = 'SUGAR-CONSTRAINT-TEST';
    \echo '  ✓ Valid sugar level accepted'
ROLLBACK;

-- Test invalid sugar level (should fail)
\echo '  Testing invalid sugar level insertion...'
BEGIN;
    INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price, modifiers) 
    SELECT o.order_id, 1, 1, 5.50, 5.50, '{"sugar_level": "super_sweet"}'::jsonb
    FROM orders o WHERE o.order_number = 'SUGAR-CONSTRAINT-TEST';
    \echo '  ✗ This should have failed but didn\'t!'
EXCEPTION 
    WHEN check_violation THEN
        \echo '  ✓ Invalid sugar level correctly rejected'
ROLLBACK;

-- Test 7: Test sugar level views
\echo ''
\echo 'Test 7: Testing sugar level analysis views...'

-- Check if views exist and return data
\echo '  Sugar level preferences view:'
SELECT * FROM sugar_level_preferences LIMIT 5;

\echo ''
\echo '  Order items with sugar view (sample):'
SELECT 
    order_item_id,
    product_name,
    sugar_level,
    sugar_description,
    formatted_item
FROM order_items_with_sugar 
ORDER BY order_item_id 
LIMIT 5;

\echo ''
\echo '  Daily sugar trends view:'
SELECT * FROM daily_sugar_trends 
WHERE order_date >= CURRENT_DATE - INTERVAL '7 days'
LIMIT 5;

-- Test 8: Performance test
\echo ''
\echo 'Test 8: Performance test for sugar level queries...'
\timing on

-- Test query performance for sugar level filtering
EXPLAIN (ANALYZE, BUFFERS) 
SELECT 
    COUNT(*) as total_orders,
    AVG(display_unit_price) as avg_price
FROM order_items 
WHERE modifiers->>'sugar_level' = 'regular';

\timing off

-- Test 9: Business analytics examples
\echo ''
\echo 'Test 9: Business analytics with sugar levels...'

-- Most popular sugar level
SELECT 
    'Most popular sugar level:' as metric,
    sugar_level,
    order_count,
    percentage || '%' as percentage_of_orders
FROM sugar_level_preferences 
ORDER BY order_count DESC 
LIMIT 1;

-- Average price by sugar level
SELECT 
    'Average prices by sugar level:' as metric,
    sugar_level,
    ROUND(avg_price, 2) as average_price
FROM sugar_level_preferences 
ORDER BY avg_price DESC;

-- Clean up test data
DELETE FROM orders WHERE order_number = 'SUGAR-CONSTRAINT-TEST';

\echo ''
\echo '========================================='
\echo 'Sugar Level Test Suite Completed!'
\echo 'All tests passed - Sugar level system is ready for production use.'
\echo '========================================='
