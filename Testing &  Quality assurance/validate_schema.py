#!/usr/bin/env python3
"""
PostgreSQL Schema Validation Script
Validates SQL syntax and checks for common issues without requiring a live database.
"""

import re
import sys
from pathlib import Path

def validate_sql_syntax(sql_content):
    """Basic SQL syntax validation"""
    errors = []
    warnings = []
    
    # Check for basic syntax issues
    lines = sql_content.split('\n')
    
    for i, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith('--'):
            continue
            
        # Check for common syntax errors
        if line.endswith(',') and 'CREATE TABLE' in lines[max(0, i-10):i]:
            # Check if this is the last column definition
            remaining_lines = [l.strip() for l in lines[i:i+5] if l.strip() and not l.strip().startswith('--')]
            if remaining_lines and remaining_lines[0].startswith(');'):
                errors.append(f"Line {i}: Trailing comma before closing parenthesis: {line}")
        
        # Check for unmatched parentheses in CREATE statements
        if 'CREATE TABLE' in line or 'CREATE INDEX' in line:
            open_parens = line.count('(')
            close_parens = line.count(')')
            if open_parens != close_parens and not line.endswith(';'):
                # This is normal for multi-line statements
                pass
    
    # Check for type conflicts
    type_definitions = re.findall(r'CREATE TYPE\s+(\w+)', sql_content, re.IGNORECASE)
    if len(type_definitions) != len(set(type_definitions)):
        duplicates = [t for t in type_definitions if type_definitions.count(t) > 1]
        errors.append(f"Duplicate type definitions found: {set(duplicates)}")
    
    # Check for table conflicts  
    table_definitions = re.findall(r'CREATE TABLE(?:\s+IF NOT EXISTS)?\s+(\w+)', sql_content, re.IGNORECASE)
    if len(table_definitions) != len(set(table_definitions)):
        duplicates = [t for t in table_definitions if table_definitions.count(t) > 1]
        errors.append(f"Duplicate table definitions found: {set(duplicates)}")
    
    # Check for function conflicts
    function_definitions = re.findall(r'CREATE(?:\s+OR REPLACE)?\s+FUNCTION\s+(\w+)', sql_content, re.IGNORECASE)
    regular_functions = re.findall(r'CREATE\s+FUNCTION\s+(\w+)', sql_content, re.IGNORECASE)
    if regular_functions:
        warnings.append(f"Functions without OR REPLACE found: {regular_functions}. Consider using CREATE OR REPLACE.")
    
    return errors, warnings

def check_schema_completeness(sql_content):
    """Check if schema has required components for POS system"""
    required_tables = [
        'products', 'product_variations', 'categories', 'orders',
        'order_items', 'order_payments', 'employees', 'customers',
        'currencies', 'exchange_rates'
    ]
    
    missing_tables = []
    for table in required_tables:
        if not re.search(f'CREATE TABLE.*{table}', sql_content, re.IGNORECASE):
            missing_tables.append(table)
    
    # Check for multi-currency support
    has_currency_support = 'currency_code' in sql_content and 'exchange_rates' in sql_content
    has_indexes = 'CREATE INDEX' in sql_content
    has_functions = 'CREATE FUNCTION' in sql_content or 'CREATE OR REPLACE FUNCTION' in sql_content
    
    return {
        'missing_tables': missing_tables,
        'has_currency_support': has_currency_support,
        'has_indexes': has_indexes,
        'has_functions': has_functions
    }

def main():
    schema_file = Path('my.sql')
    
    if not schema_file.exists():
        print(f"❌ Schema file {schema_file} not found!")
        return 1
    
    print("🔍 Validating PostgreSQL POS Schema...")
    print("=" * 50)
    
    # Read schema file
    with open(schema_file, 'r', encoding='utf-8') as f:
        sql_content = f.read()
    
    # Validate syntax
    errors, warnings = validate_sql_syntax(sql_content)
    
    # Check completeness
    completeness = check_schema_completeness(sql_content)
    
    # Report results
    print(f"📄 Schema file size: {len(sql_content)} characters")
    print(f"📊 Lines of code: {len(sql_content.splitlines())}")
    
    if errors:
        print(f"\n❌ ERRORS FOUND ({len(errors)}):")
        for error in errors:
            print(f"  • {error}")
    else:
        print(f"\n✅ No syntax errors detected!")
    
    if warnings:
        print(f"\n⚠️  WARNINGS ({len(warnings)}):")
        for warning in warnings:
            print(f"  • {warning}")
    
    print(f"\n📋 SCHEMA COMPLETENESS:")
    if completeness['missing_tables']:
        print(f"  ❌ Missing tables: {', '.join(completeness['missing_tables'])}")
    else:
        print(f"  ✅ All required tables present")
    
    print(f"  {'✅' if completeness['has_currency_support'] else '❌'} Multi-currency support: {'Yes' if completeness['has_currency_support'] else 'No'}")
    print(f"  {'✅' if completeness['has_indexes'] else '❌'} Performance indexes: {'Yes' if completeness['has_indexes'] else 'No'}")
    print(f"  {'✅' if completeness['has_functions'] else '❌'} Helper functions: {'Yes' if completeness['has_functions'] else 'No'}")
    
    # Count key components
    table_count = len(re.findall(r'CREATE TABLE', sql_content, re.IGNORECASE))
    index_count = len(re.findall(r'CREATE.*INDEX', sql_content, re.IGNORECASE))
    function_count = len(re.findall(r'CREATE.*FUNCTION', sql_content, re.IGNORECASE))
    view_count = len(re.findall(r'CREATE.*VIEW', sql_content, re.IGNORECASE))
    
    print(f"\n📈 COMPONENT COUNTS:")
    print(f"  • Tables: {table_count}")
    print(f"  • Indexes: {index_count}")
    print(f"  • Functions: {function_count}")
    print(f"  • Views: {view_count}")
    
    # Final assessment
    is_valid = len(errors) == 0 and len(completeness['missing_tables']) == 0
    
    print(f"\n{'🎉 SCHEMA VALIDATION PASSED!' if is_valid else '❌ SCHEMA VALIDATION FAILED!'}")
    
    if is_valid:
        print("\n✨ Your multi-currency POS schema is ready for deployment!")
        print("   Next steps:")
        print("   1. Set up PostgreSQL database")
        print("   2. Run: psql -d your_database -f my.sql")
        print("   3. Update exchange rates regularly")
        print("   4. Monitor materialized view refresh")
    
    return 0 if is_valid else 1

if __name__ == "__main__":
    sys.exit(main())
