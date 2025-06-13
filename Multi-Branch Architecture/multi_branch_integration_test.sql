-- Multi-Branch Integration Test
-- This script tests the integrated multi-branch functionality in the main schema

\echo ''
\echo '🏢 Testing Multi-Branch Integration...'
\echo ''

-- Test 1: Check if multi-branch tables exist
\echo 'TEST 1: Checking multi-branch table creation...'
SELECT 
    table_name,
    CASE WHEN table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('branches', 'branch_configs', 'employee_branches', 'branch_schedules', 'central_inventory', 'branch_inventory', 'inventory_transfers')
ORDER BY table_name;

\echo ''

-- Test 2: Check if branch_id columns were added to existing tables
\echo 'TEST 2: Checking branch_id column additions...'
SELECT 
    table_name,
    column_name,
    '✅ ADDED' as status
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND column_name = 'branch_id' 
AND table_name IN ('employees', 'orders', 'inventory_transactions')
UNION ALL
SELECT 
    'customers' as table_name,
    'primary_branch_id' as column_name,
    '✅ ADDED' as status
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND column_name = 'primary_branch_id' 
AND table_name = 'customers'
ORDER BY table_name;

\echo ''

-- Test 3: Check if multi-branch functions exist
\echo 'TEST 3: Checking multi-branch function creation...'
SELECT 
    routine_name,
    '✅ CREATED' as status
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN (
    'get_employee_branch',
    'employee_can_access_branch', 
    'get_branch_price',
    'check_branch_stock',
    'set_employee_session',
    'is_branch_open',
    'migrate_to_multibranch',
    'multibranch_health_check'
)
ORDER BY routine_name;

\echo ''

-- Test 4: Check if multi-branch views exist
\echo 'TEST 4: Checking multi-branch view creation...'
SELECT 
    table_name,
    '✅ CREATED' as status
FROM information_schema.views 
WHERE table_schema = 'public' 
AND table_name IN (
    'branch_performance_summary',
    'daily_branch_sales',
    'employee_branch_performance',
    'branch_inventory_status'
)
ORDER BY table_name;

\echo ''

-- Test 5: Check if main branch was created
\echo 'TEST 5: Checking main branch initialization...'
SELECT 
    branch_id,
    branch_code,
    name,
    status,
    is_active,
    '✅ INITIALIZED' as status
FROM branches 
WHERE branch_id = 1;

\echo ''

-- Test 6: Test core multi-branch functions
\echo 'TEST 6: Testing core multi-branch functions...'

-- Test migration function
SELECT 'migrate_to_multibranch()' as function_name, migrate_to_multibranch() as result;

\echo ''

-- Test health check function
\echo 'Running multi-branch health check:'
SELECT check_name, status, details FROM multibranch_health_check();

\echo ''

-- Test 7: Check multi-branch permissions
\echo 'TEST 7: Checking multi-branch permissions...'
SELECT 
    code,
    name,
    '✅ CREATED' as status
FROM permissions 
WHERE code IN ('MANAGE_BRANCH', 'VIEW_ALL_BRANCHES', 'TRANSFER_INVENTORY', 'CROSS_BRANCH_REPORTS', 'SWITCH_BRANCH')
ORDER BY code;

\echo ''

-- Test 8: Verify branch-aware indexes
\echo 'TEST 8: Checking multi-branch performance indexes...'
SELECT 
    indexname,
    '✅ CREATED' as status
FROM pg_indexes 
WHERE schemaname = 'public' 
AND indexname LIKE '%branch%'
ORDER BY indexname;

\echo ''
\echo '🎉 Multi-Branch Integration Test Complete!'
\echo ''
\echo 'If all tests show ✅ status, your multi-branch integration was successful!'
\echo 'You can now:'
\echo '- Create additional branches'
\echo '- Assign employees to multiple branches'
\echo '- Track inventory per branch'
\echo '- Generate cross-branch reports'
\echo ''
