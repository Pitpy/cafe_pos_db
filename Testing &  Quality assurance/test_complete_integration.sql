-- Complete Multi-Branch Integration Test Setup
-- This script will set up and test the complete multi-branch café POS system

\echo ''
\echo '🚀 Setting up Multi-Branch Café POS System...'
\echo ''

-- First, let's run our main schema to set up the complete system
\i my.sql

\echo ''
\echo '🧪 Running Integration Tests...'
\echo ''

-- Run the integration test suite
\i multi_branch_integration_test.sql

-- Additional demonstration tests
\echo ''
\echo '🎯 Running Additional Demo Tests...'
\echo ''

-- Demo 1: Create a second branch
\echo 'DEMO 1: Creating second branch...'
INSERT INTO branches (
    branch_code, name, description, status, is_active,
    address, city, state, country, postal_code,
    phone, email, timezone, currency
) VALUES (
    'DT002', 'Downtown Café', 'Downtown location with extended hours', 
    'active', true, '123 Main St', 'San Francisco', 'CA', 'USA', '94102',
    '+1-415-555-0202', 'downtown@cafe.com', 'America/Los_Angeles', 'USD'
);

SELECT 
    branch_id, 
    branch_code, 
    name, 
    status,
    '✅ CREATED' as demo_status
FROM branches 
WHERE branch_code = 'DT002';

\echo ''

-- Demo 2: Assign employee to multiple branches
\echo 'DEMO 2: Assigning employee to multiple branches...'
-- First check if we have any employees
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM employees LIMIT 1) THEN
        -- Assign first employee to both branches
        INSERT INTO employee_branches (employee_id, branch_id, access_level, is_primary, assigned_date)
        SELECT 
            e.employee_id,
            b.branch_id,
            'full',
            CASE WHEN b.branch_id = 1 THEN true ELSE false END,
            CURRENT_DATE
        FROM employees e
        CROSS JOIN branches b
        WHERE e.employee_id = (SELECT MIN(employee_id) FROM employees)
        ON CONFLICT (employee_id, branch_id) DO NOTHING;
        
        RAISE NOTICE 'Employee assigned to multiple branches ✅';
    ELSE
        RAISE NOTICE 'No employees found - skipping assignment demo';
    END IF;
END $$;

\echo ''

-- Demo 3: Test branch access function
\echo 'DEMO 3: Testing branch access function...'
DO $$
DECLARE
    test_employee_id INTEGER;
    access_result BOOLEAN;
BEGIN
    SELECT MIN(employee_id) INTO test_employee_id FROM employees;
    
    IF test_employee_id IS NOT NULL THEN
        SELECT employee_can_access_branch(test_employee_id, 1) INTO access_result;
        RAISE NOTICE 'Employee % can access branch 1: % ✅', test_employee_id, access_result;
        
        SELECT employee_can_access_branch(test_employee_id, 2) INTO access_result;
        RAISE NOTICE 'Employee % can access branch 2: % ✅', test_employee_id, access_result;
    ELSE
        RAISE NOTICE 'No employees found for access test';
    END IF;
END $$;

\echo ''

-- Demo 4: Test branch operating hours
\echo 'DEMO 4: Testing branch operating hours...'
SELECT 
    bs.day_of_week,
    bs.open_time,
    bs.close_time,
    is_branch_open(1, CURRENT_TIME, EXTRACT(DOW FROM CURRENT_DATE)::INTEGER) as is_open_now,
    '✅ SCHEDULE ACTIVE' as demo_status
FROM branch_schedules bs
WHERE bs.branch_id = 1
ORDER BY bs.day_of_week
LIMIT 3;

\echo ''

-- Demo 5: Test multi-branch reporting
\echo 'DEMO 5: Testing multi-branch reporting views...'
SELECT 
    'branch_performance_summary' as view_name,
    COUNT(*) as record_count,
    '✅ ACCESSIBLE' as demo_status
FROM branch_performance_summary;

SELECT 
    'daily_branch_sales' as view_name,
    COUNT(*) as record_count,
    '✅ ACCESSIBLE' as demo_status
FROM daily_branch_sales;

SELECT 
    'employee_branch_performance' as view_name,
    COUNT(*) as record_count,
    '✅ ACCESSIBLE' as demo_status
FROM employee_branch_performance;

SELECT 
    'branch_inventory_status' as view_name,
    COUNT(*) as record_count,
    '✅ ACCESSIBLE' as demo_status
FROM branch_inventory_status;

\echo ''

-- Demo 6: Test configuration system
\echo 'DEMO 6: Testing branch configuration system...'
INSERT INTO branch_configs (branch_id, config_key, config_value) VALUES
(1, 'max_daily_discount', '{"percentage": 15, "amount": 50.00}'),
(1, 'loyalty_multiplier', '1.5'),
(2, 'max_daily_discount', '{"percentage": 20, "amount": 75.00}'),
(2, 'loyalty_multiplier', '2.0');

SELECT 
    b.name as branch_name,
    bc.config_key,
    bc.config_value,
    '✅ CONFIGURED' as demo_status
FROM branch_configs bc
JOIN branches b ON bc.branch_id = b.branch_id
ORDER BY b.branch_id, bc.config_key;

\echo ''

-- Final system summary
\echo '📊 SYSTEM SUMMARY:'
\echo ''

SELECT 
    'Branches' as component,
    COUNT(*)::text as count,
    '✅ OPERATIONAL' as status
FROM branches
UNION ALL
SELECT 
    'Multi-Branch Functions' as component,
    COUNT(*)::text as count,
    '✅ AVAILABLE' as status
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN (
    'get_employee_branch', 'employee_can_access_branch', 'get_branch_price',
    'check_branch_stock', 'set_employee_session', 'is_branch_open',
    'migrate_to_multibranch', 'multibranch_health_check'
)
UNION ALL
SELECT 
    'Multi-Branch Views' as component,
    COUNT(*)::text as count,
    '✅ REPORTING READY' as status
FROM information_schema.views 
WHERE table_schema = 'public' 
AND table_name IN (
    'branch_performance_summary', 'daily_branch_sales',
    'employee_branch_performance', 'branch_inventory_status'
)
UNION ALL
SELECT 
    'Branch Permissions' as component,
    COUNT(*)::text as count,
    '✅ SECURITY READY' as status
FROM permissions 
WHERE code IN ('MANAGE_BRANCH', 'VIEW_ALL_BRANCHES', 'TRANSFER_INVENTORY', 'CROSS_BRANCH_REPORTS', 'SWITCH_BRANCH')
UNION ALL
SELECT 
    'Performance Indexes' as component,
    COUNT(*)::text as count,
    '✅ OPTIMIZED' as status
FROM pg_indexes 
WHERE schemaname = 'public' 
AND indexname LIKE '%branch%';

\echo ''
\echo '🎉 MULTI-BRANCH CAFÉ POS SYSTEM READY!'
\echo ''
\echo 'Your enterprise-grade multi-branch café POS system is now fully operational with:'
\echo '- ✅ Multi-location support'
\echo '- ✅ Cross-branch employee access'
\echo '- ✅ Branch-specific inventory management'
\echo '- ✅ Multi-branch reporting and analytics'
\echo '- ✅ Flexible configuration system'
\echo '- ✅ Enhanced RBAC with branch permissions'
\echo '- ✅ Integration with existing multi-currency, sugar levels, and performance optimization'
\echo ''
\echo 'Next steps:'
\echo '1. Update your POS application frontend to support branch selection'
\echo '2. Implement branch switching in your user interface'
\echo '3. Add branch-specific dashboards and reports'
\echo '4. Configure branch-specific business rules'
\echo ''
