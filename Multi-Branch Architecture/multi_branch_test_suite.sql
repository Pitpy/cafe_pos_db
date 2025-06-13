-- Multi-Branch Architecture Test Suite
-- Comprehensive testing for all multi-branch functionality
-- Run this after deploying multi_branch_implementation.sql

\echo '==============================================='
\echo '🏢 MULTI-BRANCH ARCHITECTURE TEST SUITE'
\echo '==============================================='
\echo ''

-- =================================================================
-- TEST 1: Infrastructure Validation
-- =================================================================
\echo 'TEST 1: Validating multi-branch infrastructure...'

-- Check if all new tables exist
SELECT 
    CASE 
        WHEN COUNT(*) = 7 THEN '✅ All multi-branch tables created'
        ELSE '❌ Missing tables: ' || (7 - COUNT(*)) || ' tables missing'
    END as table_status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
    'branches', 'branch_configs', 'employee_branches', 
    'branch_schedules', 'central_inventory', 'branch_inventory', 
    'inventory_transfers'
);

-- Check if columns were added to existing tables
SELECT 
    t.table_name,
    CASE 
        WHEN c.column_name IS NOT NULL THEN '✅ branch_id column exists'
        ELSE '❌ branch_id column missing'
    END as column_status
FROM (
    VALUES ('employees'), ('orders'), ('inventory_transactions'), ('customers')
) t(table_name)
LEFT JOIN information_schema.columns c ON c.table_name = t.table_name 
    AND c.column_name = CASE 
        WHEN t.table_name = 'customers' THEN 'primary_branch_id'
        ELSE 'branch_id'
    END
    AND c.table_schema = 'public';

\echo ''

-- =================================================================
-- TEST 2: Migration Function Testing
-- =================================================================
\echo 'TEST 2: Testing migration function...'

-- Run migration (should handle multiple runs gracefully)
SELECT migrate_to_multibranch();

-- Verify main branch exists
SELECT 
    CASE 
        WHEN EXISTS(SELECT 1 FROM branches WHERE branch_code = 'MAIN') 
        THEN '✅ Main branch created successfully'
        ELSE '❌ Main branch not found'
    END as main_branch_status;

-- Check employee assignments
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*) || ' employees assigned to branches'
        ELSE '❌ No employee assignments found'
    END as employee_assignment_status
FROM employee_branches;

\echo ''

-- =================================================================
-- TEST 3: Health Check System
-- =================================================================
\echo 'TEST 3: Running health check system...'

SELECT 
    check_name,
    status,
    details
FROM multibranch_health_check()
ORDER BY 
    CASE status 
        WHEN 'FAIL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'PASS' THEN 3 
    END;

\echo ''

-- =================================================================
-- TEST 4: Branch Management Functions
-- =================================================================
\echo 'TEST 4: Testing branch management functions...'

-- Test get_employee_branch function
DO $$
DECLARE
    emp_branch_id INT;
    test_employee_id INT;
BEGIN
    -- Get first active employee
    SELECT employee_id INTO test_employee_id 
    FROM employees 
    WHERE is_active = TRUE 
    LIMIT 1;
    
    IF test_employee_id IS NOT NULL THEN
        emp_branch_id := get_employee_branch(test_employee_id);
        RAISE NOTICE '✅ get_employee_branch() works: Employee % assigned to branch %', 
            test_employee_id, emp_branch_id;
    ELSE
        RAISE NOTICE '❌ No active employees found for testing';
    END IF;
END $$;

-- Test employee_can_access_branch function
DO $$
DECLARE
    can_access BOOLEAN;
    test_employee_id INT;
BEGIN
    SELECT employee_id INTO test_employee_id 
    FROM employees 
    WHERE is_active = TRUE 
    LIMIT 1;
    
    IF test_employee_id IS NOT NULL THEN
        can_access := employee_can_access_branch(test_employee_id, 1);
        RAISE NOTICE '✅ employee_can_access_branch() works: Employee % can access branch 1: %', 
            test_employee_id, can_access;
    END IF;
END $$;

-- Test is_branch_open function
DO $$
DECLARE
    is_open BOOLEAN;
BEGIN
    is_open := is_branch_open(1);
    RAISE NOTICE '✅ is_branch_open() works: Main branch is currently open: %', is_open;
END $$;

\echo ''

-- =================================================================
-- TEST 5: Create Test Branches
-- =================================================================
\echo 'TEST 5: Creating test branches...'

-- Create test branch 1
INSERT INTO branches (
    branch_code, name, address, phone, 
    timezone, currency_code, tax_rate, 
    seating_capacity, drive_through, delivery_service
) VALUES (
    'TEST01', 
    'Test Downtown Branch',
    '123 Test Street, Test City',
    '+1-555-TEST1',
    'America/New_York',
    'USD',
    9.00,
    40,
    false,
    true
) ON CONFLICT (branch_code) DO UPDATE SET
    name = EXCLUDED.name,
    address = EXCLUDED.address;

-- Create test branch 2
INSERT INTO branches (
    branch_code, name, address, phone, 
    timezone, currency_code, tax_rate, 
    seating_capacity, drive_through, delivery_service
) VALUES (
    'TEST02', 
    'Test Mall Location',
    '456 Mall Drive, Shopping Center',
    '+1-555-TEST2',
    'America/New_York',
    'USD',
    8.75,
    25,
    false,
    false
) ON CONFLICT (branch_code) DO UPDATE SET
    name = EXCLUDED.name,
    address = EXCLUDED.address;

-- Verify test branches created
SELECT 
    'Test branches created: ' || COUNT(*) || ' branches'
FROM branches 
WHERE branch_code LIKE 'TEST%';

\echo ''

-- =================================================================
-- TEST 6: Branch Configuration Testing
-- =================================================================
\echo 'TEST 6: Testing branch configurations...'

-- Add test configurations
INSERT INTO branch_configs (branch_id, config_key, config_value, description)
SELECT 
    b.branch_id,
    'test_config',
    '{"test_value": "success"}',
    'Test configuration for validation'
FROM branches b
WHERE b.branch_code LIKE 'TEST%'
ON CONFLICT (branch_id, config_key) DO UPDATE SET
    config_value = EXCLUDED.config_value;

-- Test pricing multiplier
INSERT INTO branch_configs (branch_id, config_key, config_value, description)
SELECT 
    b.branch_id,
    'pricing_multiplier',
    CASE 
        WHEN b.branch_code = 'TEST01' THEN '{"multiplier": 1.1}'
        WHEN b.branch_code = 'TEST02' THEN '{"multiplier": 1.2}'
    END,
    'Test pricing multiplier'
FROM branches b
WHERE b.branch_code LIKE 'TEST%'
ON CONFLICT (branch_id, config_key) DO UPDATE SET
    config_value = EXCLUDED.config_value;

-- Verify configurations
SELECT 
    b.branch_code,
    bc.config_key,
    bc.config_value
FROM branches b
JOIN branch_configs bc ON b.branch_id = bc.branch_id
WHERE b.branch_code LIKE 'TEST%'
ORDER BY b.branch_code, bc.config_key;

\echo ''

-- =================================================================
-- TEST 7: Employee Multi-Branch Assignment
-- =================================================================
\echo 'TEST 7: Testing employee multi-branch assignments...'

-- Get test employee
DO $$
DECLARE
    test_employee_id INT;
    downtown_branch_id INT;
    mall_branch_id INT;
BEGIN
    -- Get first active employee
    SELECT employee_id INTO test_employee_id 
    FROM employees 
    WHERE is_active = TRUE 
    LIMIT 1;
    
    -- Get test branch IDs
    SELECT branch_id INTO downtown_branch_id FROM branches WHERE branch_code = 'TEST01';
    SELECT branch_id INTO mall_branch_id FROM branches WHERE branch_code = 'TEST02';
    
    IF test_employee_id IS NOT NULL AND downtown_branch_id IS NOT NULL THEN
        -- Assign employee to test branches
        INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
        VALUES 
            (test_employee_id, downtown_branch_id, false, 'standard'),
            (test_employee_id, mall_branch_id, false, 'limited')
        ON CONFLICT (employee_id, branch_id) DO UPDATE SET
            access_level = EXCLUDED.access_level;
        
        RAISE NOTICE '✅ Employee % assigned to test branches', test_employee_id;
    END IF;
END $$;

-- Verify multi-branch assignments
SELECT 
    e.name as employee_name,
    b.branch_code,
    eb.access_level,
    eb.is_primary_branch
FROM employees e
JOIN employee_branches eb ON e.employee_id = eb.employee_id
JOIN branches b ON eb.branch_id = b.branch_id
WHERE b.branch_code LIKE 'TEST%'
ORDER BY e.name, b.branch_code;

\echo ''

-- =================================================================
-- TEST 8: Branch-Aware Pricing
-- =================================================================
\echo 'TEST 8: Testing branch-aware pricing...'

-- Test pricing function with different branches
SELECT 
    pv.variation_id,
    p.name as product_name,
    pv.base_price,
    get_branch_price(pv.variation_id, 1) as main_branch_price,
    get_branch_price(pv.variation_id, (SELECT branch_id FROM branches WHERE branch_code = 'TEST01')) as test01_price,
    get_branch_price(pv.variation_id, (SELECT branch_id FROM branches WHERE branch_code = 'TEST02')) as test02_price
FROM product_variations pv
JOIN products p ON pv.product_id = p.product_id
WHERE pv.is_available = TRUE
LIMIT 3;

\echo ''

-- =================================================================
-- TEST 9: Inventory Management Testing
-- =================================================================
\echo 'TEST 9: Testing inventory management...'

-- Set up test inventory for test branches
INSERT INTO branch_inventory (branch_id, ingredient_id, current_stock, reorder_threshold, max_capacity)
SELECT 
    b.branch_id,
    i.ingredient_id,
    100.0 as current_stock,
    20.0 as reorder_threshold,
    500.0 as max_capacity
FROM branches b
CROSS JOIN (SELECT ingredient_id FROM ingredients LIMIT 3) i
WHERE b.branch_code LIKE 'TEST%'
ON CONFLICT (branch_id, ingredient_id) DO UPDATE SET
    current_stock = EXCLUDED.current_stock;

-- Test stock checking function
SELECT 
    i.name as ingredient_name,
    check_branch_stock(1, i.ingredient_id) as main_stock,
    check_branch_stock(
        (SELECT branch_id FROM branches WHERE branch_code = 'TEST01'), 
        i.ingredient_id
    ) as test01_stock
FROM ingredients i
LIMIT 3;

-- Verify inventory setup
SELECT 
    b.branch_code,
    i.name as ingredient_name,
    bi.current_stock,
    bi.reorder_threshold
FROM branches b
JOIN branch_inventory bi ON b.branch_id = bi.branch_id
JOIN ingredients i ON bi.ingredient_id = i.ingredient_id
WHERE b.branch_code LIKE 'TEST%'
ORDER BY b.branch_code, i.name;

\echo ''

-- =================================================================
-- TEST 10: Session Management
-- =================================================================
\echo 'TEST 10: Testing session management...'

-- Test session setting
DO $$
DECLARE
    test_employee_id INT;
    test_branch_id INT;
    session_employee TEXT;
    session_branch TEXT;
BEGIN
    -- Get test data
    SELECT employee_id INTO test_employee_id 
    FROM employees 
    WHERE is_active = TRUE 
    LIMIT 1;
    
    SELECT branch_id INTO test_branch_id 
    FROM branches 
    WHERE branch_code = 'TEST01';
    
    IF test_employee_id IS NOT NULL AND test_branch_id IS NOT NULL THEN
        -- Set session
        PERFORM set_employee_session(test_employee_id, test_branch_id);
        
        -- Check session variables
        session_employee := current_setting('app.current_employee_id', true);
        session_branch := current_setting('app.current_branch_id', true);
        
        RAISE NOTICE '✅ Session management works: Employee %, Branch %', 
            session_employee, session_branch;
    END IF;
END $$;

\echo ''

-- =================================================================
-- TEST 11: Reporting Views Testing
-- =================================================================
\echo 'TEST 11: Testing multi-branch reporting views...'

-- Test branch performance summary
\echo 'Branch Performance Summary:'
SELECT 
    branch_code,
    branch_name,
    total_orders,
    total_revenue,
    staff_count
FROM branch_performance_summary
ORDER BY branch_code;

\echo ''

-- Test employee branch performance (if there are orders)
\echo 'Employee Branch Performance:'
SELECT 
    employee_name,
    branch_code,
    access_level,
    is_primary_branch
FROM employee_branch_performance
WHERE branch_code LIKE 'TEST%' OR branch_code = 'MAIN'
LIMIT 5;

\echo ''

-- Test branch inventory status
\echo 'Branch Inventory Status:'
SELECT 
    branch_code,
    ingredient_name,
    current_stock,
    stock_status
FROM branch_inventory_status
WHERE branch_code LIKE 'TEST%'
LIMIT 5;

\echo ''

-- =================================================================
-- TEST 12: Inter-Branch Transfer Testing
-- =================================================================
\echo 'TEST 12: Testing inter-branch transfers...'

-- Create test transfer
DO $$
DECLARE
    from_branch_id INT;
    to_branch_id INT;
    test_ingredient_id INT;
    test_employee_id INT;
BEGIN
    -- Get test data
    SELECT branch_id INTO from_branch_id FROM branches WHERE branch_code = 'MAIN';
    SELECT branch_id INTO to_branch_id FROM branches WHERE branch_code = 'TEST01';
    SELECT ingredient_id INTO test_ingredient_id FROM ingredients LIMIT 1;
    SELECT employee_id INTO test_employee_id FROM employees WHERE is_active = TRUE LIMIT 1;
    
    IF from_branch_id IS NOT NULL AND to_branch_id IS NOT NULL THEN
        INSERT INTO inventory_transfers (
            transfer_number, from_branch_id, to_branch_id, ingredient_id,
            quantity_requested, quantity_sent, unit_cost,
            transfer_status, requested_by
        ) VALUES (
            'TEST-TRNF-001',
            from_branch_id,
            to_branch_id, 
            test_ingredient_id,
            50.0,
            50.0,
            2.50,
            'completed',
            test_employee_id
        ) ON CONFLICT (transfer_number) DO NOTHING;
        
        RAISE NOTICE '✅ Test transfer created successfully';
    END IF;
END $$;

-- Verify transfer
SELECT 
    transfer_number,
    bf.branch_code as from_branch,
    bt.branch_code as to_branch,
    i.name as ingredient,
    quantity_requested,
    transfer_status
FROM inventory_transfers it
LEFT JOIN branches bf ON it.from_branch_id = bf.branch_id
JOIN branches bt ON it.to_branch_id = bt.branch_id
JOIN ingredients i ON it.ingredient_id = i.ingredient_id
WHERE transfer_number LIKE 'TEST-%';

\echo ''

-- =================================================================
-- TEST 13: Performance Index Testing
-- =================================================================
\echo 'TEST 13: Verifying performance indexes...'

-- Check if key indexes exist
SELECT 
    indexname,
    tablename,
    CASE 
        WHEN indexname IS NOT NULL THEN '✅ EXISTS'
        ELSE '❌ MISSING'
    END as status
FROM (
    VALUES 
        ('idx_orders_branch_date', 'orders'),
        ('idx_employees_branch_active', 'employees'),
        ('idx_employee_branches_emp_active', 'employee_branches'),
        ('idx_branch_inventory_branch_ingredient', 'branch_inventory'),
        ('idx_branches_status_active', 'branches')
) expected(indexname, tablename)
LEFT JOIN pg_indexes pi ON pi.indexname = expected.indexname 
    AND pi.tablename = expected.tablename
    AND pi.schemaname = 'public';

\echo ''

-- =================================================================
-- TEST 14: Data Integrity Testing
-- =================================================================
\echo 'TEST 14: Testing data integrity...'

-- Check foreign key constraints
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ No orphaned employee-branch assignments'
        ELSE '❌ Found ' || COUNT(*) || ' orphaned employee-branch assignments'
    END as employee_integrity
FROM employee_branches eb
LEFT JOIN employees e ON eb.employee_id = e.employee_id
LEFT JOIN branches b ON eb.branch_id = b.branch_id
WHERE e.employee_id IS NULL OR b.branch_id IS NULL;

-- Check order-branch integrity
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ No orphaned order-branch references'
        ELSE '❌ Found ' || COUNT(*) || ' orphaned order-branch references'
    END as order_integrity
FROM orders o
LEFT JOIN branches b ON o.branch_id = b.branch_id
WHERE b.branch_id IS NULL;

\echo ''

-- =================================================================
-- TEST 15: Branch Operating Hours
-- =================================================================
\echo 'TEST 15: Testing branch operating hours...'

-- Add operating hours for test branches
INSERT INTO branch_schedules (branch_id, day_of_week, opening_time, closing_time, is_closed)
SELECT 
    b.branch_id,
    gs.day_of_week,
    '09:00'::TIME as opening_time,
    '18:00'::TIME as closing_time,
    false as is_closed
FROM branches b
CROSS JOIN generate_series(1, 5) gs(day_of_week)  -- Monday to Friday
WHERE b.branch_code LIKE 'TEST%'
ON CONFLICT (branch_id, day_of_week) DO UPDATE SET
    opening_time = EXCLUDED.opening_time,
    closing_time = EXCLUDED.closing_time;

-- Test operating hours function
SELECT 
    b.branch_code,
    is_branch_open(b.branch_id) as currently_open,
    is_branch_open(b.branch_id, CURRENT_DATE + TIME '10:00') as open_at_10am,
    is_branch_open(b.branch_id, CURRENT_DATE + TIME '19:00') as open_at_7pm
FROM branches b
WHERE b.branch_code LIKE 'TEST%' OR b.branch_code = 'MAIN';

\echo ''

-- =================================================================
-- FINAL SUMMARY
-- =================================================================
\echo '==============================================='
\echo '📊 MULTI-BRANCH TEST SUITE SUMMARY'
\echo '==============================================='

-- Overall system health
SELECT 
    'FINAL HEALTH CHECK:' as test_category,
    check_name,
    status,
    details
FROM multibranch_health_check()
ORDER BY 
    CASE status 
        WHEN 'FAIL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'PASS' THEN 3 
    END;

-- Branch count summary
SELECT 
    'BRANCH SUMMARY:' as test_category,
    'Total Branches' as check_name,
    COUNT(*)::TEXT as status,
    'Active branches: ' || COUNT(*) FILTER (WHERE is_active = TRUE) || ', ' ||
    'Test branches: ' || COUNT(*) FILTER (WHERE branch_code LIKE 'TEST%') as details
FROM branches;

-- Employee assignment summary
SELECT 
    'EMPLOYEE SUMMARY:' as test_category,
    'Multi-Branch Assignments' as check_name,
    COUNT(*)::TEXT as status,
    'Total assignments: ' || COUNT(*) || ', ' ||
    'Employees with multiple branches: ' || COUNT(DISTINCT employee_id) FILTER (WHERE cnt > 1) as details
FROM (
    SELECT employee_id, COUNT(*) as cnt
    FROM employee_branches 
    WHERE is_active = TRUE
    GROUP BY employee_id
) eb_counts;

\echo ''
\echo '✅ Multi-branch architecture test suite completed!'
\echo '🎯 Review any WARNING or FAIL statuses above'
\echo '📚 See MULTI_BRANCH_DEPLOYMENT.md for next steps'
\echo '==============================================='
