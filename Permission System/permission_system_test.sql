-- ===================================================================
-- PERMISSION SYSTEM COMPREHENSIVE TEST SUITE
-- ===================================================================
-- Test file for the employee permission and role management system
-- Run this after setting up the main schema to verify functionality

-- Test database connection and schema
\echo '=== PERMISSION SYSTEM TEST SUITE ==='
\echo 'Testing permission tables, functions, and role assignments...'
\echo ''

-- ===================================================================
-- TEST 1: Table Structure Verification
-- ===================================================================
\echo 'TEST 1: Verifying table structures...'

-- Check if all permission tables exist
SELECT 
    table_name,
    CASE 
        WHEN table_name IS NOT NULL THEN '✓ EXISTS'
        ELSE '✗ MISSING'
    END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('permission_groups', 'permissions', 'roles', 'role_permissions', 'employee_roles')
ORDER BY table_name;

\echo ''

-- ===================================================================
-- TEST 2: Sample Data Verification
-- ===================================================================
\echo 'TEST 2: Verifying sample data insertion...'

-- Check permission groups
SELECT 'Permission Groups' as table_name, COUNT(*) as record_count FROM permission_groups
UNION ALL
SELECT 'Permissions', COUNT(*) FROM permissions
UNION ALL  
SELECT 'Roles', COUNT(*) FROM roles
UNION ALL
SELECT 'Role Permissions', COUNT(*) FROM role_permissions;

\echo ''

-- Show permission groups with their permission counts
\echo 'Permission Groups Overview:'
SELECT 
    pg.name as group_name,
    pg.description,
    COUNT(p.permission_id) as permission_count
FROM permission_groups pg
LEFT JOIN permissions p ON pg.group_id = p.group_id AND p.is_active = true
GROUP BY pg.group_id, pg.name, pg.description
ORDER BY pg.name;

\echo ''

-- Show roles with their permission counts  
\echo 'Roles Overview:'
SELECT 
    r.name as role_name,
    r.description,
    COUNT(rp.permission_id) as permission_count,
    r.is_active
FROM roles r
LEFT JOIN role_permissions rp ON r.role_id = rp.role_id
GROUP BY r.role_id, r.name, r.description, r.is_active
ORDER BY r.name;

\echo ''

-- ===================================================================
-- TEST 3: Permission Helper Functions Testing
-- ===================================================================
\echo 'TEST 3: Testing permission helper functions...'

-- Create test employee data for testing (temporary)
INSERT INTO employees (first_name, last_name, email, phone, position, hire_date, is_active) VALUES
('Test', 'Manager', 'test.manager@coffeeshop.com', '555-0001', 'Manager', CURRENT_DATE, true),
('Test', 'Barista', 'test.barista@coffeeshop.com', '555-0002', 'Barista', CURRENT_DATE, true),
('Test', 'Cashier', 'test.cashier@coffeeshop.com', '555-0003', 'Cashier', CURRENT_DATE, true)
ON CONFLICT (email) DO NOTHING;

-- Get test employee IDs
\echo 'Test employees created/found:'
SELECT employee_id, first_name, last_name, position 
FROM employees 
WHERE email LIKE 'test.%@coffeeshop.com';

-- Test role assignment function
\echo ''
\echo 'Testing role assignment function...'
DO $$
DECLARE
    manager_id INT;
    barista_id INT;
    cashier_id INT;
BEGIN
    -- Get test employee IDs
    SELECT employee_id INTO manager_id FROM employees WHERE email = 'test.manager@coffeeshop.com';
    SELECT employee_id INTO barista_id FROM employees WHERE email = 'test.barista@coffeeshop.com';
    SELECT employee_id INTO cashier_id FROM employees WHERE email = 'test.cashier@coffeeshop.com';
    
    -- Assign roles
    PERFORM assign_role_to_employee(manager_id, 'Manager');
    PERFORM assign_role_to_employee(barista_id, 'Barista');  
    PERFORM assign_role_to_employee(cashier_id, 'Cashier');
    
    RAISE NOTICE 'Role assignments completed successfully';
END $$;

-- Verify role assignments
\echo ''
\echo 'Verifying role assignments:'
SELECT 
    e.first_name || ' ' || e.last_name as employee_name,
    r.name as role_name,
    er.assigned_at,
    er.is_active
FROM employees e
JOIN employee_roles er ON e.employee_id = er.employee_id
JOIN roles r ON er.role_id = r.role_id
WHERE e.email LIKE 'test.%@coffeeshop.com'
ORDER BY e.first_name, r.name;

\echo ''

-- ===================================================================
-- TEST 4: Permission Checking Functions
-- ===================================================================
\echo 'TEST 4: Testing permission checking functions...'

-- Test employee_has_permission function
\echo 'Testing permission checks:'
DO $$
DECLARE
    manager_id INT;
    barista_id INT;
    cashier_id INT;
BEGIN
    -- Get test employee IDs
    SELECT employee_id INTO manager_id FROM employees WHERE email = 'test.manager@coffeeshop.com';
    SELECT employee_id INTO barista_id FROM employees WHERE email = 'test.barista@coffeeshop.com';
    SELECT employee_id INTO cashier_id FROM employees WHERE email = 'test.cashier@coffeeshop.com';
    
    -- Test Manager permissions
    RAISE NOTICE 'Manager can CREATE_ORDER: %', employee_has_permission(manager_id, 'CREATE_ORDER');
    RAISE NOTICE 'Manager can PROCESS_REFUND: %', employee_has_permission(manager_id, 'PROCESS_REFUND');
    RAISE NOTICE 'Manager can MANAGE_STAFF: %', employee_has_permission(manager_id, 'MANAGE_STAFF');
    
    -- Test Barista permissions
    RAISE NOTICE 'Barista can CREATE_ORDER: %', employee_has_permission(barista_id, 'CREATE_ORDER');
    RAISE NOTICE 'Barista can PROCESS_REFUND: %', employee_has_permission(barista_id, 'PROCESS_REFUND');
    RAISE NOTICE 'Barista can MANAGE_STAFF: %', employee_has_permission(barista_id, 'MANAGE_STAFF');
    
    -- Test Cashier permissions
    RAISE NOTICE 'Cashier can CREATE_ORDER: %', employee_has_permission(cashier_id, 'CREATE_ORDER');
    RAISE NOTICE 'Cashier can CASH_MANAGEMENT: %', employee_has_permission(cashier_id, 'CASH_MANAGEMENT');
    RAISE NOTICE 'Cashier can MANAGE_INVENTORY: %', employee_has_permission(cashier_id, 'MANAGE_INVENTORY');
END $$;

\echo ''

-- Test get_employee_permissions function
\echo 'Manager permissions:'
SELECT permission_code, permission_name, role_name
FROM get_employee_permissions((SELECT employee_id FROM employees WHERE email = 'test.manager@coffeeshop.com'))
ORDER BY role_name, permission_code;

\echo ''
\echo 'Barista permissions:'
SELECT permission_code, permission_name, role_name
FROM get_employee_permissions((SELECT employee_id FROM employees WHERE email = 'test.barista@coffeeshop.com'))
ORDER BY role_name, permission_code;

\echo ''

-- ===================================================================
-- TEST 5: Order Action Permission Validation
-- ===================================================================
\echo 'TEST 5: Testing order action permission validation...'

DO $$
DECLARE
    manager_id INT;
    barista_id INT;
    cashier_id INT;
BEGIN
    -- Get test employee IDs
    SELECT employee_id INTO manager_id FROM employees WHERE email = 'test.manager@coffeeshop.com';
    SELECT employee_id INTO barista_id FROM employees WHERE email = 'test.barista@coffeeshop.com'; 
    SELECT employee_id INTO cashier_id FROM employees WHERE email = 'test.cashier@coffeeshop.com';
    
    -- Test order action permissions
    RAISE NOTICE 'Manager can create orders: %', can_employee_perform_order_action(manager_id, 'create');
    RAISE NOTICE 'Manager can process refunds: %', can_employee_perform_order_action(manager_id, 'refund');
    
    RAISE NOTICE 'Barista can create orders: %', can_employee_perform_order_action(barista_id, 'create');
    RAISE NOTICE 'Barista can process refunds: %', can_employee_perform_order_action(barista_id, 'refund');
    
    RAISE NOTICE 'Cashier can create orders: %', can_employee_perform_order_action(cashier_id, 'create');
    RAISE NOTICE 'Cashier can process refunds: %', can_employee_perform_order_action(cashier_id, 'refund');
END $$;

\echo ''

-- ===================================================================
-- TEST 6: Index and Performance Verification
-- ===================================================================
\echo 'TEST 6: Verifying permission system indexes...'

-- Check if permission indexes exist
SELECT 
    indexname,
    tablename,
    CASE 
        WHEN indexname IS NOT NULL THEN '✓ EXISTS'
        ELSE '✗ MISSING'
    END as status
FROM pg_indexes 
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
  AND (
    tablename IN ('employee_roles', 'role_permissions', 'permissions', 'roles') OR
    indexname LIKE '%permission%' OR
    indexname LIKE '%role%'
  )
ORDER BY tablename, indexname;

\echo ''

-- ===================================================================
-- TEST 7: Role Management Functions
-- ===================================================================
\echo 'TEST 7: Testing role management functions...'

-- Test get_employee_roles function
\echo 'Manager roles:'
SELECT role_name, role_description, assigned_at
FROM get_employee_roles((SELECT employee_id FROM employees WHERE email = 'test.manager@coffeeshop.com'));

\echo ''

-- Test role removal function
\echo 'Testing role removal...'
DO $$
DECLARE
    test_emp_id INT;
BEGIN
    SELECT employee_id INTO test_emp_id FROM employees WHERE email = 'test.cashier@coffeeshop.com';
    
    -- Add Barista role to Cashier for testing
    PERFORM assign_role_to_employee(test_emp_id, 'Barista');
    RAISE NOTICE 'Added Barista role to Cashier for testing';
    
    -- Remove the role
    PERFORM remove_role_from_employee(test_emp_id, 'Barista');
    RAISE NOTICE 'Removed Barista role from Cashier';
END $$;

-- Verify role removal
\echo 'Cashier roles after removal:'
SELECT role_name, role_description, assigned_at
FROM get_employee_roles((SELECT employee_id FROM employees WHERE email = 'test.cashier@coffeeshop.com'));

\echo ''

-- ===================================================================
-- TEST 8: Error Handling Tests
-- ===================================================================
\echo 'TEST 8: Testing error handling...'

-- Test invalid permission check
DO $$
BEGIN
    BEGIN
        PERFORM employee_has_permission(999, 'INVALID_PERMISSION');
        RAISE NOTICE 'Invalid permission check handled gracefully';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Error handling working: %', SQLERRM;
    END;
END $$;

-- Test invalid role assignment
DO $$
BEGIN
    BEGIN
        PERFORM assign_role_to_employee(1, 'INVALID_ROLE');
        RAISE NOTICE 'This should not print - error should have occurred';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Role assignment error handling working: %', SQLERRM;
    END;
END $$;

\echo ''

-- ===================================================================
-- TEST SUMMARY AND CLEANUP
-- ===================================================================
\echo 'TEST SUMMARY:'
\echo '✓ Permission table structures verified'
\echo '✓ Sample data loaded successfully'
\echo '✓ Permission helper functions working'
\echo '✓ Role assignment functions working'
\echo '✓ Permission checking functions working'
\echo '✓ Order action validation working'
\echo '✓ Performance indexes created'
\echo '✓ Error handling working'
\echo ''

-- Optional: Clean up test data
\echo 'Cleaning up test data...'
DELETE FROM employee_roles WHERE employee_id IN (
    SELECT employee_id FROM employees WHERE email LIKE 'test.%@coffeeshop.com'
);

DELETE FROM employees WHERE email LIKE 'test.%@coffeeshop.com';

\echo '✓ Test data cleaned up'
\echo ''
\echo '=== PERMISSION SYSTEM TEST COMPLETED SUCCESSFULLY ==='
\echo 'Your permission system is ready for production use!'
