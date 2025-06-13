# 🚀 Multi-Branch Architecture Deployment Guide

## 📋 Overview

This guide provides step-by-step instructions for deploying the multi-branch architecture to your existing PostgreSQL café POS system. The deployment is designed to be backward-compatible and can be implemented incrementally.

## ⚡ Quick Start

```bash
# 1. Navigate to your project directory
cd "/Users/pitpy/Desktop/workspace/my projects/pos/postgres"

# 2. Deploy multi-branch architecture
psql -d your_database -f multi_branch_implementation.sql

# 3. Run migration function
psql -d your_database -c "SELECT migrate_to_multibranch();"

# 4. Verify deployment
psql -d your_database -c "SELECT * FROM multibranch_health_check();"
```

## 🏗️ Detailed Deployment Steps

### Phase 1: Infrastructure Deployment (Week 1)

#### Step 1: Backup Current Database
```bash
# Create backup before deployment
pg_dump your_database > backup_before_multibranch_$(date +%Y%m%d).sql
```

#### Step 2: Deploy Multi-Branch Schema
```bash
# Deploy the multi-branch implementation
psql -d your_database -f multi_branch_implementation.sql
```

#### Step 3: Migrate Existing Data
```sql
-- Run migration function to assign existing data to main branch
SELECT migrate_to_multibranch();

-- Expected output:
-- Multi-branch migration completed successfully:
-- - X employees assigned to main branch
-- - Y orders assigned to main branch  
-- - Z inventory transactions assigned to main branch
```

#### Step 4: Verify Base Installation
```sql
-- Check health status
SELECT * FROM multibranch_health_check();

-- Verify main branch creation
SELECT * FROM branches WHERE branch_code = 'MAIN';

-- Check employee assignments
SELECT e.name, eb.branch_id, eb.is_primary_branch, eb.access_level
FROM employees e
JOIN employee_branches eb ON e.employee_id = eb.employee_id
WHERE eb.is_active = TRUE;
```

### Phase 2: Configure Main Branch (Week 1-2)

#### Step 1: Update Main Branch Information
```sql
-- Update main branch details
UPDATE branches 
SET 
    name = 'Main Street Café',
    address = '123 Main Street, Your City, State 12345',
    phone = '+1-555-0100',
    email = 'main@yourcafe.com',
    timezone = 'America/New_York',  -- Set your timezone
    currency_code = 'USD',
    tax_rate = 8.50,  -- Set your local tax rate
    seating_capacity = 45,
    drive_through = false,
    delivery_service = true
WHERE branch_code = 'MAIN';
```

#### Step 2: Configure Operating Hours
```sql
-- Update operating hours for main branch
UPDATE branch_schedules 
SET 
    opening_time = '07:00',
    closing_time = '19:00'
WHERE branch_id = 1 AND day_of_week IN (1,2,3,4,5); -- Weekdays

UPDATE branch_schedules 
SET 
    opening_time = '08:00',
    closing_time = '21:00'
WHERE branch_id = 1 AND day_of_week IN (6,0); -- Weekend
```

#### Step 3: Set Branch-Specific Configurations
```sql
-- Configure branch-specific settings
INSERT INTO branch_configs (branch_id, config_key, config_value, description) VALUES
(1, 'loyalty_multiplier', '{"multiplier": 1.0}', 'Standard loyalty points multiplier'),
(1, 'discount_policy', '{"max_discount": 0.15, "employee_discount": 0.10}', 'Branch discount policies'),
(1, 'wifi_password', '{"password": "CafeWiFi2025"}', 'Guest WiFi password'),
(1, 'daily_sales_target', '{"target": 2500.00}', 'Daily sales target in USD');
```

### Phase 3: Add New Branches (Week 2-3)

#### Step 1: Create Second Branch
```sql
-- Add a new branch
INSERT INTO branches (
    branch_code, name, address, phone, email, 
    timezone, currency_code, tax_rate, 
    seating_capacity, drive_through, delivery_service
) VALUES (
    'DT01', 
    'Downtown Branch',
    '456 Business Avenue, Downtown District',
    '+1-555-0101',
    'downtown@yourcafe.com',
    'America/New_York',
    'USD',
    8.50,
    35,
    false,
    true
);
```

#### Step 2: Set Operating Hours for New Branch
```sql
-- Get the branch_id for the new branch
-- Then create schedule
INSERT INTO branch_schedules (branch_id, day_of_week, opening_time, closing_time, is_closed) 
SELECT 
    b.branch_id,
    generate_series(0,6) as day_of_week,
    CASE WHEN generate_series(0,6) IN (0) THEN '09:00'::TIME  -- Sunday
         WHEN generate_series(0,6) IN (6) THEN '08:00'::TIME  -- Saturday
         ELSE '07:30'::TIME  -- Weekdays
    END as opening_time,
    CASE WHEN generate_series(0,6) IN (0) THEN '18:00'::TIME  -- Sunday
         WHEN generate_series(0,6) IN (5,6) THEN '22:00'::TIME  -- Friday, Saturday
         ELSE '20:00'::TIME  -- Other weekdays
    END as closing_time,
    false as is_closed
FROM branches b 
WHERE b.branch_code = 'DT01';
```

#### Step 3: Configure Branch-Specific Settings
```sql
-- Configure downtown branch specifics
INSERT INTO branch_configs (branch_id, config_key, config_value, description) 
SELECT b.branch_id, 'loyalty_multiplier', '{"multiplier": 1.2}', '20% bonus loyalty points for downtown location'
FROM branches b WHERE b.branch_code = 'DT01';

INSERT INTO branch_configs (branch_id, config_key, config_value, description)
SELECT b.branch_id, 'pricing_multiplier', '{"multiplier": 1.05}', '5% price premium for downtown location'
FROM branches b WHERE b.branch_code = 'DT01';
```

### Phase 4: Employee Management (Week 3-4)

#### Step 1: Assign Employees to New Branch
```sql
-- Assign existing employees to new branch
-- Example: Make Alice Johnson (employee_id = 1) manager of downtown branch
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
SELECT 1, b.branch_id, false, 'manager'
FROM branches b 
WHERE b.branch_code = 'DT01';

-- Assign other employees with standard access
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
SELECT 2, b.branch_id, false, 'standard'  -- Bob Smith
FROM branches b 
WHERE b.branch_code = 'DT01';
```

#### Step 2: Create Branch-Specific Employees
```sql
-- Add new employees for downtown branch
INSERT INTO employees (name, pin, role_id, is_active, branch_id) VALUES
('David Downtown', '555001', 3, true, (SELECT branch_id FROM branches WHERE branch_code = 'DT01')),
('Emma Evans', '555002', 4, true, (SELECT branch_id FROM branches WHERE branch_code = 'DT01'));

-- Assign new employees to their branch
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
SELECT e.employee_id, e.branch_id, true, 'standard'
FROM employees e 
WHERE e.pin IN ('555001', '555002');
```

### Phase 5: Inventory Setup (Week 4-5)

#### Option A: Independent Branch Inventory
```sql
-- Set up independent inventory for new branch
INSERT INTO branch_inventory (branch_id, ingredient_id, current_stock, reorder_threshold, max_capacity)
SELECT 
    b.branch_id,
    i.ingredient_id,
    0.0 as current_stock,
    i.reorder_level * 0.5 as reorder_threshold,  -- 50% of main branch reorder level
    i.reorder_level * 5 as max_capacity          -- 5x reorder level as max capacity
FROM branches b
CROSS JOIN ingredients i
WHERE b.branch_code = 'DT01';
```

#### Option B: Centralized Inventory Setup
```sql
-- Set up central inventory if preferred
INSERT INTO central_inventory (ingredient_id, total_stock, reorder_level, max_stock_level)
SELECT 
    ingredient_id,
    current_stock * 3 as total_stock,  -- Triple current stock for central
    reorder_level * 2 as reorder_level,
    reorder_level * 10 as max_stock_level
FROM ingredients;

-- Allocate inventory to branches
INSERT INTO branch_inventory (branch_id, ingredient_id, current_stock, allocated_from_central)
SELECT 
    b.branch_id,
    i.ingredient_id,
    i.current_stock / 2 as current_stock,  -- Split current stock between branches
    i.current_stock / 2 as allocated_from_central
FROM branches b
CROSS JOIN ingredients i
WHERE b.branch_id <= 2;  -- First two branches
```

### Phase 6: Testing & Validation (Week 5-6)

#### Step 1: Test Branch Operations
```sql
-- Test branch switching for employees
SELECT set_employee_session(1, 2);  -- Switch Alice to downtown branch

-- Test branch-aware pricing
SELECT 
    pv.variation_id,
    p.name,
    pv.base_price,
    get_branch_price(pv.variation_id, 1) as main_branch_price,
    get_branch_price(pv.variation_id, 2) as downtown_branch_price
FROM product_variations pv
JOIN products p ON pv.product_id = p.product_id
LIMIT 5;

-- Test inventory checking
SELECT 
    i.name,
    check_branch_stock(1, i.ingredient_id) as main_stock,
    check_branch_stock(2, i.ingredient_id) as downtown_stock
FROM ingredients i
LIMIT 5;
```

#### Step 2: Create Test Orders
```sql
-- Create test order for downtown branch
INSERT INTO orders (
    order_number, employee_id, branch_id, order_time,
    currency_code, exchange_rate, subtotal, tax_rate, tax_amount, total_amount, base_total_amount, status
) VALUES (
    'DT01-TEST-001', 
    1,  -- Alice Johnson
    (SELECT branch_id FROM branches WHERE branch_code = 'DT01'),
    CURRENT_TIMESTAMP,
    'USD', 1.0, 10.50, 8.50, 0.89, 11.39, 11.39, 'paid'
);
```

#### Step 3: Test Reporting
```sql
-- Test multi-branch reports
SELECT * FROM branch_performance_summary;
SELECT * FROM daily_branch_sales WHERE sales_date >= CURRENT_DATE - INTERVAL '7 days';
SELECT * FROM employee_branch_performance;
```

## 📊 Performance Monitoring

### Key Metrics to Track

```sql
-- Branch performance comparison
SELECT 
    branch_code,
    branch_name,
    total_orders,
    total_revenue,
    average_order_value,
    staff_count
FROM branch_performance_summary
ORDER BY total_revenue DESC;

-- Daily sales trends
SELECT 
    sales_date,
    branch_name,
    order_count,
    daily_revenue,
    revenue_per_staff
FROM daily_branch_sales
WHERE sales_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY sales_date DESC, daily_revenue DESC;

-- Employee utilization across branches
SELECT 
    employee_name,
    COUNT(DISTINCT branch_name) as branches_worked,
    SUM(orders_processed) as total_orders,
    SUM(revenue_generated) as total_revenue
FROM employee_branch_performance
GROUP BY employee_name
ORDER BY total_revenue DESC;
```

### Health Monitoring

```sql
-- Regular health checks
SELECT * FROM multibranch_health_check();

-- Branch status overview
SELECT 
    branch_code,
    name,
    status,
    is_branch_open(branch_id) as currently_open,
    (SELECT COUNT(*) FROM employee_branches eb WHERE eb.branch_id = branches.branch_id AND eb.is_active = TRUE) as staff_count,
    (SELECT COUNT(*) FROM orders o WHERE o.branch_id = branches.branch_id AND DATE(o.order_time) = CURRENT_DATE) as today_orders
FROM branches
WHERE is_active = TRUE;
```

## 🔧 Maintenance Tasks

### Daily Tasks
```sql
-- Update branch inventory counts
-- This would typically be done through your POS application
-- Example manual update:
UPDATE branch_inventory 
SET current_stock = current_stock - 5.0,
    last_count_date = CURRENT_DATE
WHERE branch_id = 1 AND ingredient_id = 1;  -- Example: coffee beans used
```

### Weekly Tasks
```sql
-- Analyze branch performance
SELECT * FROM branch_performance_summary;

-- Check inventory levels across branches
SELECT * FROM branch_inventory_status WHERE stock_status = 'LOW_STOCK';

-- Review employee assignments
SELECT 
    e.name,
    COUNT(eb.branch_id) as branch_count,
    STRING_AGG(b.branch_code, ', ') as assigned_branches
FROM employees e
JOIN employee_branches eb ON e.employee_id = eb.employee_id
JOIN branches b ON eb.branch_id = b.branch_id
WHERE e.is_active = TRUE AND eb.is_active = TRUE
GROUP BY e.employee_id, e.name;
```

### Monthly Tasks
```sql
-- Performance optimization
ANALYZE branches, employee_branches, branch_inventory, inventory_transfers;

-- Archive old transfer records (older than 1 year)
DELETE FROM inventory_transfers 
WHERE request_date < CURRENT_DATE - INTERVAL '1 year'
AND transfer_status IN ('received', 'cancelled');
```

## 🚨 Troubleshooting

### Common Issues

#### Issue 1: Employee Can't Access Branch
```sql
-- Check employee branch assignments
SELECT 
    e.name,
    eb.branch_id,
    b.branch_code,
    eb.access_level,
    eb.is_active
FROM employees e
LEFT JOIN employee_branches eb ON e.employee_id = eb.employee_id
LEFT JOIN branches b ON eb.branch_id = b.branch_id
WHERE e.employee_id = [EMPLOYEE_ID];

-- Fix: Add missing assignment
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
VALUES ([EMPLOYEE_ID], [BRANCH_ID], false, 'standard');
```

#### Issue 2: Branch Pricing Not Working
```sql
-- Check branch configurations
SELECT 
    b.branch_code,
    bc.config_key,
    bc.config_value
FROM branches b
LEFT JOIN branch_configs bc ON b.branch_id = bc.branch_id
WHERE b.branch_id = [BRANCH_ID];

-- Fix: Add missing pricing configuration
INSERT INTO branch_configs (branch_id, config_key, config_value, description)
VALUES ([BRANCH_ID], 'pricing_multiplier', '{"multiplier": 1.0}', 'Default pricing');
```

#### Issue 3: Inventory Issues
```sql
-- Check inventory setup
SELECT 
    b.branch_code,
    i.name,
    bi.current_stock,
    bi.reorder_threshold
FROM branches b
LEFT JOIN branch_inventory bi ON b.branch_id = bi.branch_id
LEFT JOIN ingredients i ON bi.ingredient_id = i.ingredient_id
WHERE b.branch_id = [BRANCH_ID];

-- Fix: Initialize missing inventory
INSERT INTO branch_inventory (branch_id, ingredient_id, current_stock, reorder_threshold)
SELECT [BRANCH_ID], ingredient_id, 0.0, reorder_level
FROM ingredients
WHERE ingredient_id NOT IN (
    SELECT ingredient_id FROM branch_inventory WHERE branch_id = [BRANCH_ID]
);
```

## 🎯 Next Steps

### Phase 7: POS Application Updates
1. **Update Login Process**: Add branch selection during employee login
2. **Modify Order Processing**: Include branch context in all transactions
3. **Update Reporting Interface**: Add multi-branch report capabilities
4. **Add Branch Management**: Create admin interface for branch operations

### Phase 8: Advanced Features
1. **Inventory Transfers**: Implement inter-branch inventory movement
2. **Employee Scheduling**: Cross-branch staff scheduling system
3. **Customer Analytics**: Multi-branch customer behavior analysis
4. **Franchise Support**: Add franchise management capabilities

### Phase 9: Integration & Automation
1. **API Development**: Create branch-aware API endpoints
2. **Mobile App**: Branch-specific mobile applications
3. **IoT Integration**: Smart equipment monitoring per branch
4. **Automated Reporting**: Scheduled multi-branch reports

## ✅ Deployment Checklist

- [ ] **Phase 1**: Schema deployed and data migrated
- [ ] **Phase 2**: Main branch configured with proper details
- [ ] **Phase 3**: Additional branches created and configured
- [ ] **Phase 4**: Employee assignments completed
- [ ] **Phase 5**: Inventory strategy implemented
- [ ] **Phase 6**: Testing completed and validated
- [ ] **Performance**: Monitoring queries running successfully
- [ ] **Health Checks**: All health checks passing
- [ ] **Documentation**: Staff trained on multi-branch operations
- [ ] **Backup**: Post-deployment backup created

## 🏆 Success Criteria

### Technical Metrics
- ✅ All health checks pass
- ✅ Query performance < 100ms for branch operations
- ✅ Zero data integrity issues
- ✅ Backward compatibility maintained

### Business Metrics
- ✅ Seamless branch operations
- ✅ Accurate cross-branch reporting
- ✅ Efficient employee management
- ✅ Proper inventory tracking

---

**Deployment Status**: Ready for Implementation  
**Compatibility**: PostgreSQL 12+ with existing POS schema  
**Integration**: Seamless with current multi-currency and permission systems

Your multi-branch café empire is ready to launch! 🚀
