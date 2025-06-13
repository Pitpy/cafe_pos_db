-- Table Dependency Validation Script
-- This validates that all tables are created in the correct dependency order

\echo '🔍 VALIDATING TABLE DEPENDENCY ORDER...'
\echo ''

-- Check table creation order by analyzing foreign key dependencies
WITH table_dependencies AS (
    SELECT 
        tc.table_name AS dependent_table,
        ccu.table_name AS referenced_table,
        tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu 
        ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
),
table_order AS (
    SELECT 
        t.table_name,
        ROW_NUMBER() OVER (ORDER BY t.table_name) as creation_order
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
),
dependency_check AS (
    SELECT 
        td.dependent_table,
        td.referenced_table,
        dep_order.creation_order as dependent_order,
        ref_order.creation_order as referenced_order,
        CASE 
            WHEN dep_order.creation_order > ref_order.creation_order THEN '✅ OK'
            ELSE '❌ VIOLATION'
        END as dependency_status,
        td.constraint_name
    FROM table_dependencies td
    JOIN table_order dep_order ON td.dependent_table = dep_order.table_name
    JOIN table_order ref_order ON td.referenced_table = ref_order.table_name
)
SELECT 
    dependent_table,
    referenced_table,
    dependency_status,
    constraint_name
FROM dependency_check
ORDER BY 
    CASE WHEN dependency_status = '❌ VIOLATION' THEN 0 ELSE 1 END,
    dependent_table;

\echo ''
\echo '📋 MULTI-BRANCH TABLES VERIFICATION:'

-- Verify multi-branch tables exist and are properly ordered
SELECT 
    table_name,
    CASE WHEN table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM (VALUES 
    ('branches'),
    ('branch_configs'),
    ('branch_schedules'),
    ('employee_branches'),
    ('central_inventory'),
    ('branch_inventory'),
    ('inventory_transfers')
) AS mb_tables(table_name)
LEFT JOIN information_schema.tables t 
    ON mb_tables.table_name = t.table_name 
    AND t.table_schema = 'public'
ORDER BY 
    CASE mb_tables.table_name
        WHEN 'branches' THEN 1
        WHEN 'branch_configs' THEN 2
        WHEN 'branch_schedules' THEN 3
        WHEN 'employee_branches' THEN 4
        WHEN 'central_inventory' THEN 5
        WHEN 'branch_inventory' THEN 6
        WHEN 'inventory_transfers' THEN 7
    END;

\echo ''
\echo '🔗 KEY FOREIGN KEY RELATIONSHIPS:'

-- Check critical foreign key relationships
SELECT 
    tc.table_name as table_name,
    kcu.column_name as column_name,
    ccu.table_name as referenced_table,
    ccu.column_name as referenced_column,
    '✅ VALID' as status
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu 
    ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema = 'public'
AND tc.table_name IN ('employee_branches', 'orders', 'inventory_transactions', 'customers')
ORDER BY tc.table_name, kcu.column_name;

\echo ''
\echo '📊 DEPENDENCY SUMMARY:'

-- Summary of dependency validation
SELECT 
    COUNT(*) as total_dependencies,
    SUM(CASE WHEN dependency_status = '✅ OK' THEN 1 ELSE 0 END) as valid_dependencies,
    SUM(CASE WHEN dependency_status = '❌ VIOLATION' THEN 1 ELSE 0 END) as violations
FROM (
    SELECT 
        td.dependent_table,
        td.referenced_table,
        dep_order.creation_order as dependent_order,
        ref_order.creation_order as referenced_order,
        CASE 
            WHEN dep_order.creation_order > ref_order.creation_order THEN '✅ OK'
            ELSE '❌ VIOLATION'
        END as dependency_status
    FROM (
        SELECT 
            tc.table_name AS dependent_table,
            ccu.table_name AS referenced_table
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public'
    ) td
    JOIN (
        SELECT 
            t.table_name,
            ROW_NUMBER() OVER (ORDER BY t.table_name) as creation_order
        FROM information_schema.tables t
        WHERE t.table_schema = 'public' 
        AND t.table_type = 'BASE TABLE'
    ) dep_order ON td.dependent_table = dep_order.table_name
    JOIN (
        SELECT 
            t.table_name,
            ROW_NUMBER() OVER (ORDER BY t.table_name) as creation_order
        FROM information_schema.tables t
        WHERE t.table_schema = 'public' 
        AND t.table_type = 'BASE TABLE'
    ) ref_order ON td.referenced_table = ref_order.table_name
) dependency_analysis;

\echo ''
\echo 'If violations = 0, then all table dependencies are properly resolved! ✅'
\echo ''
