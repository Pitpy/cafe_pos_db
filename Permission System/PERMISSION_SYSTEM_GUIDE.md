# Permission System User Guide

## Overview

The Permission System provides role-based access control (RBAC) for your PostgreSQL POS system. It allows you to manage employee permissions through roles, ensuring secure access to different system functions.

## Table Structure

### Core Tables

1. **permission_groups** - Logical groupings of permissions (e.g., "Order Management", "Inventory Management")
2. **permissions** - Individual permissions (e.g., "CREATE_ORDER", "PROCESS_REFUND")
3. **roles** - Job roles (e.g., "Manager", "Barista", "Cashier")
4. **role_permissions** - Links roles to permissions (many-to-many)
5. **employee_roles** - Links employees to roles (many-to-many)

### Relationships

```
employees ←→ employee_roles ←→ roles ←→ role_permissions ←→ permissions → permission_groups
```

## Default Roles and Permissions

### Administrator

- **Purpose**: System administration and configuration
- **Permissions**: All permissions (full system access)

### Manager

- **Purpose**: Store manager with operational control
- **Key Permissions**:
  - All order operations (create, modify, cancel, refund)
  - Inventory management
  - Financial reports and cash management
  - Staff viewing and schedule management
  - All reporting functions

### Supervisor

- **Purpose**: Shift supervisor with limited management access
- **Key Permissions**:
  - Order operations (create, modify, cancel)
  - View inventory and staff
  - Payment processing and cash management
  - Basic reporting

### Barista

- **Purpose**: Coffee preparation and basic operations
- **Key Permissions**:
  - Create and modify orders
  - View inventory levels
  - Process payments

### Cashier

- **Purpose**: Order taking and payment processing
- **Key Permissions**:
  - Create orders
  - Process payments
  - Cash drawer management

### Inventory Clerk

- **Purpose**: Stock management and inventory control
- **Key Permissions**:
  - Full inventory management
  - Stock adjustments
  - Inventory reporting

## Permission Categories

### System Administration

- `SYSTEM_ADMIN` - Full system access
- `MANAGE_USERS` - Create and manage user accounts
- `SYSTEM_CONFIG` - Modify system settings

### Order Management

- `CREATE_ORDER` - Create new customer orders
- `MODIFY_ORDER` - Edit existing orders
- `CANCEL_ORDER` - Cancel customer orders
- `PROCESS_REFUND` - Process customer refunds
- `VIEW_ALL_ORDERS` - Access to all order history

### Inventory Management

- `MANAGE_INVENTORY` - Add/remove inventory items
- `STOCK_ADJUSTMENT` - Adjust stock levels
- `VIEW_INVENTORY` - View current inventory levels

### Financial Operations

- `PROCESS_PAYMENT` - Handle customer payments
- `VIEW_FINANCIAL_REPORTS` - Access financial reports
- `CASH_MANAGEMENT` - Handle cash drawer operations

### Staff Management

- `MANAGE_STAFF` - Hire, fire, and manage employees
- `VIEW_STAFF` - View employee information
- `MANAGE_SCHEDULES` - Create and modify work schedules

### Reporting

- `VIEW_REPORTS` - Access to standard reports
- `EXPORT_DATA` - Export data to external formats

## Helper Functions

### Check Employee Permission

```sql
-- Check if an employee has a specific permission
SELECT employee_has_permission(employee_id, 'CREATE_ORDER');
```

### Get Employee Permissions

```sql
-- Get all permissions for an employee
SELECT * FROM get_employee_permissions(employee_id);
```

### Get Employee Roles

```sql
-- Get all roles assigned to an employee
SELECT * FROM get_employee_roles(employee_id);
```

### Assign Role to Employee

```sql
-- Assign a role to an employee
SELECT assign_role_to_employee(employee_id, 'Manager', assigned_by_manager_id);
```

### Remove Role from Employee

```sql
-- Remove a role from an employee
SELECT remove_role_from_employee(employee_id, 'Barista');
```

### Validate Order Actions

```sql
-- Check if employee can perform specific order actions
SELECT can_employee_perform_order_action(employee_id, 'create');  -- 'create', 'modify', 'cancel', 'refund'
```

## Usage Examples

### 1. Set Up New Employee

```sql
-- Create employee
INSERT INTO employees (first_name, last_name, email, position, hire_date)
VALUES ('John', 'Doe', 'john.doe@coffeeshop.com', 'Barista', CURRENT_DATE);

-- Assign role
SELECT assign_role_to_employee(
    (SELECT employee_id FROM employees WHERE email = 'john.doe@coffeeshop.com'),
    'Barista',
    1  -- Manager ID who is assigning the role
);
```

### 2. Check Permissions Before Action

```sql
-- In your application, before allowing order creation:
DO $$
DECLARE
    emp_id INT := 5;  -- Current employee ID
BEGIN
    IF NOT employee_has_permission(emp_id, 'CREATE_ORDER') THEN
        RAISE EXCEPTION 'Access denied: You do not have permission to create orders';
    END IF;

    -- Proceed with order creation...
END $$;
```

### 3. Promote Employee

```sql
-- Promote barista to supervisor
SELECT remove_role_from_employee(employee_id, 'Barista');
SELECT assign_role_to_employee(employee_id, 'Supervisor', manager_id);
```

### 4. Audit Employee Permissions

```sql
-- View all permissions for troubleshooting
SELECT
    e.first_name || ' ' || e.last_name as employee_name,
    gep.permission_code,
    gep.permission_name,
    gep.role_name
FROM employees e
CROSS JOIN LATERAL get_employee_permissions(e.employee_id) gep
WHERE e.is_active = true
ORDER BY e.last_name, gep.role_name, gep.permission_code;
```

### 5. Custom Role Creation

```sql
-- Create custom role
INSERT INTO roles (name, description) VALUES
('Training Manager', 'Manages training programs and new employee onboarding');

-- Assign specific permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT
    (SELECT role_id FROM roles WHERE name = 'Training Manager'),
    permission_id
FROM permissions
WHERE code IN ('VIEW_STAFF', 'MANAGE_SCHEDULES', 'VIEW_REPORTS');
```

## Integration with Application Code

### PHP Example

```php
function checkPermission($employeeId, $permission) {
    $sql = "SELECT employee_has_permission(?, ?)";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$employeeId, $permission]);
    return $stmt->fetchColumn();
}

// Usage
if (!checkPermission($_SESSION['employee_id'], 'PROCESS_REFUND')) {
    die('Access denied: Insufficient permissions');
}
```

### Node.js Example

```javascript
async function checkPermission(employeeId, permission) {
  const result = await db.query("SELECT employee_has_permission($1, $2)", [
    employeeId,
    permission,
  ]);
  return result.rows[0].employee_has_permission;
}

// Usage
if (!(await checkPermission(req.user.employeeId, "CREATE_ORDER"))) {
  return res.status(403).json({ error: "Insufficient permissions" });
}
```

## Best Practices

1. **Principle of Least Privilege**: Assign only the minimum permissions needed for each role
2. **Regular Audits**: Periodically review employee permissions and remove unnecessary access
3. **Role-Based Design**: Use roles rather than assigning permissions directly to individuals
4. **Document Changes**: Use the audit fields (assigned_by, granted_by) to track permission changes
5. **Test Permissions**: Always test permission changes in a development environment first

## Security Considerations

1. **Database Access**: Ensure only authorized applications can access the permission tables
2. **Permission Caching**: If caching permissions in your application, implement cache invalidation
3. **Audit Logging**: Consider logging all permission checks for security auditing
4. **Regular Updates**: Keep role definitions up-to-date with business requirements
5. **Emergency Access**: Maintain a break-glass admin account for emergency situations

## Troubleshooting

### Employee Can't Access Feature

1. Check if employee has active role: `SELECT * FROM get_employee_roles(employee_id)`
2. Check if role has required permission: View role_permissions table
3. Verify permission is active: `SELECT * FROM permissions WHERE code = 'PERMISSION_CODE'`

### Permission Not Working

1. Verify function syntax: Ensure you're using correct permission codes
2. Check for typos in permission codes (case-sensitive)
3. Verify employee_roles.is_active = true
4. Check if role is active: roles.is_active = true

### Performance Issues

1. Ensure all recommended indexes are in place
2. Consider caching frequently-checked permissions in your application
3. Use EXPLAIN ANALYZE on permission queries to identify bottlenecks

## Testing

Run the comprehensive test suite:

```bash
psql -d your_database -f permission_system_test.sql
```

This will verify all components are working correctly and provide performance benchmarks.
