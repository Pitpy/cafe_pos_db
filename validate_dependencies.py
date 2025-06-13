#!/usr/bin/env python3
"""
Schema Dependency Validator
Validates that tables are created in the correct order based on foreign key dependencies.
"""

import re
import sys

def extract_table_definitions(sql_content):
    """Extract table names and their foreign key dependencies from SQL content."""
    tables = {}
    current_table = None
    
    # Pattern to match CREATE TABLE statements
    create_table_pattern = r'CREATE TABLE IF NOT EXISTS (\w+)'
    # Pattern to match FOREIGN KEY constraints
    foreign_key_pattern = r'FOREIGN KEY \([^)]+\) REFERENCES (\w+)\('
    
    lines = sql_content.split('\n')
    
    for line in lines:
        line = line.strip()
        
        # Check for CREATE TABLE
        create_match = re.search(create_table_pattern, line, re.IGNORECASE)
        if create_match:
            current_table = create_match.group(1)
            tables[current_table] = {
                'dependencies': [],
                'line_num': len([l for l in lines[:lines.index(line)] if l.strip()])
            }
            continue
            
        # Check for FOREIGN KEY within current table
        if current_table:
            fk_match = re.search(foreign_key_pattern, line, re.IGNORECASE)
            if fk_match:
                referenced_table = fk_match.group(1)
                if referenced_table != current_table:  # Avoid self-references
                    tables[current_table]['dependencies'].append(referenced_table)
    
    return tables

def validate_dependencies(tables):
    """Validate that tables are defined before they are referenced."""
    errors = []
    table_order = list(tables.keys())
    
    for i, table_name in enumerate(table_order):
        table_info = tables[table_name]
        
        for dependency in table_info['dependencies']:
            if dependency not in tables:
                errors.append(f"Table '{table_name}' references undefined table '{dependency}'")
                continue
                
            # Check if dependency appears later in the file
            dependency_index = table_order.index(dependency) if dependency in table_order else -1
            if dependency_index > i:
                errors.append(f"Dependency error: Table '{table_name}' (position {i+1}) references table '{dependency}' (position {dependency_index+1}) which is defined later")
    
    return errors

def main():
    try:
        with open('my.sql', 'r', encoding='utf-8') as f:
            sql_content = f.read()
    except FileNotFoundError:
        print("Error: my.sql file not found")
        sys.exit(1)
    
    print("=== Schema Dependency Validation ===")
    print()
    
    # Extract table definitions
    tables = extract_table_definitions(sql_content)
    
    print(f"Found {len(tables)} tables:")
    for i, (table_name, info) in enumerate(tables.items()):
        deps_str = ", ".join(info['dependencies']) if info['dependencies'] else "none"
        print(f"  {i+1:2d}. {table_name:<20} -> depends on: {deps_str}")
    
    print()
    
    # Validate dependencies
    errors = validate_dependencies(tables)
    
    if errors:
        print("❌ VALIDATION FAILED")
        print("Dependency errors found:")
        for error in errors:
            print(f"  • {error}")
        sys.exit(1)
    else:
        print("✅ VALIDATION PASSED")
        print("All tables are defined in correct dependency order!")
        
        # Check specific case that was causing the error
        if 'employees' in tables and 'roles' in tables:
            employee_pos = list(tables.keys()).index('employees')
            roles_pos = list(tables.keys()).index('roles')
            if roles_pos < employee_pos:
                print("✅ Specific fix confirmed: 'roles' table is defined before 'employees' table")
            else:
                print("❌ Issue still exists: 'roles' table should be defined before 'employees' table")

if __name__ == "__main__":
    main()
