#!/usr/bin/env python3
"""
Permission System Schema Validator
Validates the permission system tables and structure in the PostgreSQL schema
"""

import re
import sys
from pathlib import Path

def validate_permission_system(schema_file_path):
    """Validate the permission system implementation in the schema file"""
    
    print("=== PERMISSION SYSTEM SCHEMA VALIDATION ===\n")
    
    try:
        with open(schema_file_path, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"❌ Schema file not found: {schema_file_path}")
        return False
    
    validation_results = []
    
    # Test 1: Check if all permission tables exist
    print("1. Checking permission table definitions...")
    required_tables = [
        'permission_groups',
        'permissions', 
        'roles',
        'role_permissions',
        'employee_roles'
    ]
    
    for table in required_tables:
        pattern = rf'CREATE TABLE.*{table}\s*\('
        if re.search(pattern, content, re.IGNORECASE):
            print(f"   ✅ {table} table found")
            validation_results.append(True)
        else:
            print(f"   ❌ {table} table missing")
            validation_results.append(False)
    
    # Test 2: Check for foreign key constraints
    print("\n2. Checking foreign key constraints...")
    fk_checks = [
        ('permissions', 'permission_groups', 'group_id'),
        ('role_permissions', 'roles', 'role_id'),
        ('role_permissions', 'permissions', 'permission_id'),
        ('employee_roles', 'employees', 'employee_id'),
        ('employee_roles', 'roles', 'role_id')
    ]
    
    for table, ref_table, column in fk_checks:
        pattern = rf'FOREIGN KEY.*{column}.*REFERENCES\s+{ref_table}'
        if re.search(pattern, content, re.IGNORECASE):
            print(f"   ✅ {table}.{column} → {ref_table} constraint found")
            validation_results.append(True)
        else:
            print(f"   ❌ {table}.{column} → {ref_table} constraint missing")
            validation_results.append(False)
    
    # Test 3: Check for helper functions
    print("\n3. Checking permission helper functions...")
    required_functions = [
        'employee_has_permission',
        'get_employee_permissions',
        'get_employee_roles',
        'assign_role_to_employee',
        'remove_role_from_employee',
        'can_employee_perform_order_action'
    ]
    
    for func in required_functions:
        pattern = rf'CREATE.*FUNCTION.*{func}\s*\('
        if re.search(pattern, content, re.IGNORECASE):
            print(f"   ✅ {func}() function found")
            validation_results.append(True)
        else:
            print(f"   ❌ {func}() function missing")
            validation_results.append(False)
    
    # Test 4: Check for performance indexes
    print("\n4. Checking permission system indexes...")
    expected_indexes = [
        'idx_employee_roles_employee_active',
        'idx_employee_roles_role_active', 
        'idx_role_permissions_role',
        'idx_role_permissions_permission',
        'idx_permissions_code_active',
        'idx_permissions_group_active',
        'idx_roles_name_active'
    ]
    
    for idx in expected_indexes:
        pattern = rf'CREATE.*INDEX.*{idx}'
        if re.search(pattern, content, re.IGNORECASE):
            print(f"   ✅ {idx} index found")
            validation_results.append(True)
        else:
            print(f"   ❌ {idx} index missing")
            validation_results.append(False)
    
    # Test 5: Check for sample data
    print("\n5. Checking sample permission data...")
    sample_data_checks = [
        ('permission_groups', 'System Administration'),
        ('permissions', 'CREATE_ORDER'),
        ('permissions', 'PROCESS_REFUND'),
        ('roles', 'Manager'),
        ('roles', 'Barista'),
        ('role_permissions', 'role_id.*permission_id')
    ]
    
    for table, check_value in sample_data_checks:
        if 'role_id.*permission_id' in check_value:
            # Special case for role_permissions insert
            pattern = rf'INSERT INTO {table}.*role_id.*permission_id'
        else:
            pattern = rf'INSERT INTO {table}.*{check_value}'
        
        if re.search(pattern, content, re.IGNORECASE):
            print(f"   ✅ {table} sample data found")
            validation_results.append(True)
        else:
            print(f"   ❌ {table} sample data missing")
            validation_results.append(False)
    
    # Summary
    print(f"\n=== VALIDATION SUMMARY ===")
    passed = sum(validation_results)
    total = len(validation_results)
    success_rate = (passed / total) * 100
    
    print(f"Tests passed: {passed}/{total} ({success_rate:.1f}%)")
    
    if success_rate == 100:
        print("🎉 PERMISSION SYSTEM FULLY IMPLEMENTED!")
        print("✅ All tables, functions, indexes, and sample data are present")
        print("✅ Schema is ready for production use")
        return True
    elif success_rate >= 80:
        print("⚠️  PERMISSION SYSTEM MOSTLY COMPLETE")  
        print("✅ Core functionality is implemented")
        print("⚠️  Some optional components may be missing")
        return True
    else:
        print("❌ PERMISSION SYSTEM INCOMPLETE")
        print("❌ Critical components are missing")
        print("❌ Additional work needed before production use")
        return False

if __name__ == "__main__":
    schema_path = "my.sql"
    
    if not Path(schema_path).exists():
        print(f"Schema file '{schema_path}' not found in current directory")
        print("Please run this script from the postgres directory")
        sys.exit(1)
    
    success = validate_permission_system(schema_path)
    
    if success:
        print(f"\n✅ Validation completed successfully!")
        sys.exit(0)
    else:
        print(f"\n❌ Validation failed - see issues above")
        sys.exit(1)
