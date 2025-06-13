-- =================================================================
-- FLEXIBLE CURRENCY SUPPORT DEMONSTRATION
-- =================================================================
-- Test script showing the new CHAR(3) currency flexibility

-- Test 1: Insert sample currencies (beyond the original USD, LAK, THB)
SELECT 'Testing flexible currency support...' as test_status;

-- Test 2: Show all supported currencies
SELECT 
    code,
    name,
    symbol,
    decimal_places,
    is_base_currency
FROM currencies 
ORDER BY is_base_currency DESC, code;

-- Test 3: Test currency conversion with new currencies
SELECT 
    'Currency Conversion Tests' as test_category,
    get_exchange_rate('USD', 'EUR') as usd_to_eur_rate,
    get_exchange_rate('USD', 'JPY') as usd_to_jpy_rate,
    get_exchange_rate('USD', 'SGD') as usd_to_sgd_rate;

-- Test 4: Convert $100 USD to various currencies
SELECT 
    'Converting $100 USD to other currencies' as test_category,
    format_currency(100.00, 'USD') as original_amount,
    format_currency(convert_currency(100.00, 'USD', 'EUR'), 'EUR') as in_euros,
    format_currency(convert_currency(100.00, 'USD', 'JPY'), 'JPY') as in_yen,
    format_currency(convert_currency(100.00, 'USD', 'LAK'), 'LAK') as in_lak,
    format_currency(convert_currency(100.00, 'USD', 'THB'), 'THB') as in_baht,
    format_currency(convert_currency(100.00, 'USD', 'SGD'), 'SGD') as in_singapore_dollar;

-- Test 5: Show product prices in multiple currencies
SELECT 
    product_name,
    size,
    type,
    usd_formatted,
    eur_formatted,
    lak_formatted,
    thb_formatted
FROM product_prices_multi_currency
LIMIT 5;

-- Test 6: Test adding a new currency (example: Korean Won)
INSERT INTO currencies (code, name, symbol, decimal_places, is_base_currency, is_active) 
VALUES ('KRW', 'Korean Won', '₩', 0, false, true);

-- Add exchange rate for KRW
INSERT INTO exchange_rates (from_currency, to_currency, rate, effective_date) 
VALUES 
('USD', 'KRW', 1200.00, CURRENT_TIMESTAMP),
('KRW', 'USD', 0.000833, CURRENT_TIMESTAMP);

-- Test conversion with new currency
SELECT 
    'Testing newly added Korean Won' as test_category,
    format_currency(100.00, 'USD') as original,
    format_currency(convert_currency(100.00, 'USD', 'KRW'), 'KRW') as korean_won;

-- Test 7: Verify currency code constraints
-- This should fail with invalid currency code
-- INSERT INTO currencies (code, name, symbol) VALUES ('INVALID', 'Invalid Currency', '?');

-- Test 8: Show exchange rate matrix
SELECT 
    from_currency,
    to_currency,
    rate,
    effective_date
FROM exchange_rates 
WHERE is_active = true
ORDER BY from_currency, to_currency;

SELECT 'All currency flexibility tests completed successfully!' as final_status;
