#!/usr/bin/env python3
"""
Schema Structure Validator
Checks for duplicate table definitions and dependency issues in the PostgreSQL schema
"""

import re
from pathlib import Path

def check_schema_structure(file_path: str):
    """Check the PostgreSQL schema for structural issues"""
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    print("🔍 PostgreSQL Schema Structure Checker")
    print("=" * 50)
    
    # Check for table definitions
    table_pattern = r'CREATE TABLE.*?(\w+)\s*\('
    tables = re.findall(table_pattern, content, re.IGNORECASE | re.DOTALL)
    
    print(f"📊 Found {len(tables)} table definitions:")
    table_counts = {}
    for table in tables:
        table_name = table.strip()
        if table_name in table_counts:
            table_counts[table_name] += 1
        else:
            table_counts[table_name] = 1
        print(f"   • {table_name}")
    
    # Check for duplicates
    duplicates = {name: count for name, count in table_counts.items() if count > 1}
    if duplicates:
        print(f"\n❌ DUPLICATE TABLES FOUND:")
        for name, count in duplicates.items():
            print(f"   • {name}: {count} definitions")
        return False
    else:
        print(f"\n✅ No duplicate tables found")
    
    # Check for foreign key dependencies
    fk_pattern = r'FOREIGN KEY.*?REFERENCES\s+(\w+)'
    foreign_keys = re.findall(fk_pattern, content, re.IGNORECASE)
    
    print(f"\n🔗 Found {len(foreign_keys)} foreign key references:")
    for fk in set(foreign_keys):
        print(f"   • References: {fk}")
    
    # Check if referenced tables exist
    missing_refs = []
    for fk_table in set(foreign_keys):
        if fk_table not in [t.strip() for t in tables]:
            missing_refs.append(fk_table)
    
    if missing_refs:
        print(f"\n❌ MISSING REFERENCED TABLES:")
        for ref in missing_refs:
            print(f"   • {ref}")
        return False
    else:
        print(f"\n✅ All foreign key references are valid")
    
    # Check for type definitions
    type_pattern = r'CREATE TYPE\s+(\w+)'
    types = re.findall(type_pattern, content, re.IGNORECASE)
    print(f"\n📝 Found {len(types)} custom types:")
    for type_name in types:
        print(f"   • {type_name}")
    
    # Summary
    print(f"\n📋 SCHEMA SUMMARY:")
    print(f"   • Tables: {len(set(tables))}")
    print(f"   • Custom Types: {len(types)}")
    print(f"   • Foreign Keys: {len(foreign_keys)}")
    
    if not duplicates and not missing_refs:
        print(f"\n🎉 Schema structure validation PASSED!")
        return True
    else:
        print(f"\n💥 Schema structure validation FAILED!")
        return False

if __name__ == "__main__":
    print("Starting schema check...")
    schema_file = Path(__file__).parent / "my.sql"
    print(f"Checking file: {schema_file}")
    if schema_file.exists():
        print(f"File exists, size: {schema_file.stat().st_size} bytes")
        check_schema_structure(str(schema_file))
    else:
        print("Schema file not found!")
