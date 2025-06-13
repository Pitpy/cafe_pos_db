# 🏢 Multi-Branch Café Architecture Design

## 📋 Executive Summary

This document outlines a comprehensive multi-branch architecture for your existing PostgreSQL café POS system. The design maintains your current robust infrastructure while adding enterprise-grade multi-location capabilities.

## 🎯 Design Objectives

### Primary Goals

- **Seamless Integration**: Build upon existing schema without breaking current operations
- **Branch Isolation**: Each branch operates independently with local autonomy
- **Centralized Control**: Head office maintains oversight and consolidated reporting
- **Data Consistency**: Ensure synchronization across branches while maintaining performance
- **Scalability**: Support 2-50+ branches with minimal architectural changes

### Business Requirements

- **Individual Branch Operations**: Each location functions independently during network outages
- **Cross-Branch Employee Access**: Staff can work at multiple locations
- **Centralized Inventory**: Option for shared or individual inventory management
- **Consolidated Reporting**: Real-time and batch reporting across all branches
- **Branch-Specific Configurations**: Customizable menus, pricing, and policies per location

---

## 🏗️ Architecture Overview

### 1. **Centralized Database with Branch Partitioning**

**Recommended Approach**: Single database with branch-aware tables

**Benefits**:

- Immediate consistency across branches
- Simplified backup and maintenance
- Real-time consolidated reporting
- Easier staff management across branches

**Trade-offs**:

- Single point of failure (mitigated with high availability)
- Requires robust network connectivity
- Higher database server requirements

### 2. **Distributed Database with Synchronization**

**Alternative Approach**: Separate database per branch with sync

**Benefits**:

- Branch independence during network issues
- Reduced latency for local operations
- Isolated failure impact

**Trade-offs**:

- Complex synchronization logic
- Eventual consistency challenges
- Higher maintenance overhead

---

## 📊 Recommended Solution: Centralized with Branch Awareness

Based on your current infrastructure and typical café operations, we recommend the **Centralized Database with Branch Partitioning** approach.

### Core Implementation Strategy

1. **Add Branch Context**: Extend existing tables with `branch_id`
2. **Maintain Compatibility**: Current single-branch operations continue unchanged
3. **Smart Defaults**: Auto-assign branch context based on user session
4. **Incremental Migration**: Deploy multi-branch features progressively

---

## 🔧 Technical Implementation

### Phase 1: Branch Infrastructure

#### New Tables

```sql
-- Branch Management
CREATE TABLE branches (
    branch_id SERIAL PRIMARY KEY,
    branch_code VARCHAR(10) NOT NULL UNIQUE,    -- e.g., 'MAIN', 'DT01', 'MLL02'
    name VARCHAR(100) NOT NULL,                 -- e.g., 'Downtown Branch'
    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(100),
    manager_employee_id INT,                    -- Branch manager
    timezone VARCHAR(50) DEFAULT 'UTC',
    currency_code CHAR(3) DEFAULT 'USD',       -- Primary branch currency
    tax_rate DECIMAL(5,2) DEFAULT 8.50,        -- Branch-specific tax rate
    is_active BOOLEAN DEFAULT TRUE,
    opening_hours JSONB,                        -- {"mon": "08:00-18:00", "tue": "08:00-18:00"}
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (manager_employee_id) REFERENCES employees(employee_id)
);

-- Branch-Specific Configurations
CREATE TABLE branch_configs (
    config_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    config_key VARCHAR(50) NOT NULL,            -- e.g., 'loyalty_multiplier', 'discount_policy'
    config_value JSONB NOT NULL,                -- Flexible configuration storage
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id),
    UNIQUE (branch_id, config_key)
);

-- Employee-Branch Assignments (Many-to-Many)
CREATE TABLE employee_branches (
    assignment_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    branch_id INT NOT NULL,
    is_primary_branch BOOLEAN DEFAULT FALSE,    -- Employee's home branch
    access_level VARCHAR(20) DEFAULT 'standard', -- 'standard', 'manager', 'limited'
    assigned_date DATE DEFAULT CURRENT_DATE,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id),
    UNIQUE (employee_id, branch_id)
);
```

#### Extended Core Tables

```sql
-- Add branch_id to existing tables
ALTER TABLE employees ADD COLUMN branch_id INT;
ALTER TABLE employees ADD CONSTRAINT fk_employees_branch
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id);

ALTER TABLE orders ADD COLUMN branch_id INT NOT NULL DEFAULT 1;
ALTER TABLE orders ADD CONSTRAINT fk_orders_branch
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id);

ALTER TABLE inventory_transactions ADD COLUMN branch_id INT NOT NULL DEFAULT 1;
ALTER TABLE inventory_transactions ADD CONSTRAINT fk_inventory_branch
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id);

-- Create indexes for branch-aware queries
CREATE INDEX idx_orders_branch_date ON orders(branch_id, order_time);
CREATE INDEX idx_employees_branch_active ON employees(branch_id, is_active);
CREATE INDEX idx_inventory_branch_ingredient ON inventory_transactions(branch_id, ingredient_id);
```

### Phase 2: Inventory Management Strategy

#### Option A: Centralized Inventory

```sql
-- Shared inventory across branches
CREATE TABLE central_inventory (
    inventory_id SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL,
    total_stock DECIMAL(10,2) DEFAULT 0.0,
    allocated_stock DECIMAL(10,2) DEFAULT 0.0,  -- Reserved for branches
    available_stock DECIMAL(10,2) GENERATED ALWAYS AS (total_stock - allocated_stock) STORED,
    reorder_level DECIMAL(10,2),
    supplier VARCHAR(100),
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id)
);

-- Branch inventory allocations
CREATE TABLE branch_inventory (
    allocation_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    allocated_quantity DECIMAL(10,2) NOT NULL,
    current_stock DECIMAL(10,2) DEFAULT 0.0,
    reorder_threshold DECIMAL(10,2),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    UNIQUE (branch_id, ingredient_id)
);
```

#### Option B: Independent Branch Inventory

```sql
-- Each branch manages its own inventory
ALTER TABLE ingredients ADD COLUMN branch_id INT;
ALTER TABLE ingredients ADD CONSTRAINT fk_ingredients_branch
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id);

-- Branch-specific ingredient tracking
CREATE INDEX idx_ingredients_branch_stock ON ingredients(branch_id, current_stock);
```

### Phase 3: Branch-Aware Business Logic

#### Enhanced Functions

```sql
-- Get employee's current branch context
CREATE OR REPLACE FUNCTION get_employee_branch(emp_id INT)
RETURNS INT AS $$
DECLARE
    branch_id INT;
BEGIN
    SELECT e.branch_id INTO branch_id
    FROM employees e
    WHERE e.employee_id = emp_id AND e.is_active = TRUE;

    RETURN COALESCE(branch_id, 1); -- Default to branch 1 if not set
END;
$$ LANGUAGE plpgsql;

-- Branch-aware product pricing
CREATE OR REPLACE FUNCTION get_branch_price(variation_id INT, target_branch_id INT)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    base_price DECIMAL(10,2);
    branch_multiplier DECIMAL(4,2) DEFAULT 1.00;
    final_price DECIMAL(10,2);
BEGIN
    -- Get base price
    SELECT pv.base_price INTO base_price
    FROM product_variations pv
    WHERE pv.variation_id = get_branch_price.variation_id;

    -- Get branch-specific pricing multiplier
    SELECT (bc.config_value->>'multiplier')::DECIMAL(4,2) INTO branch_multiplier
    FROM branch_configs bc
    WHERE bc.branch_id = target_branch_id
    AND bc.config_key = 'pricing_multiplier';

    final_price := base_price * COALESCE(branch_multiplier, 1.00);

    RETURN final_price;
END;
$$ LANGUAGE plpgsql;

-- Branch inventory check
CREATE OR REPLACE FUNCTION check_branch_stock(
    target_branch_id INT,
    target_ingredient_id INT
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    current_stock DECIMAL(10,2);
BEGIN
    SELECT bi.current_stock INTO current_stock
    FROM branch_inventory bi
    WHERE bi.branch_id = target_branch_id
    AND bi.ingredient_id = target_ingredient_id;

    RETURN COALESCE(current_stock, 0.0);
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 Multi-Branch Reporting & Analytics

### Consolidated Views

```sql
-- Branch performance overview
CREATE VIEW branch_performance_summary AS
SELECT
    b.branch_id,
    b.name AS branch_name,
    b.branch_code,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_revenue,
    AVG(o.total_amount) AS average_order_value,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    COUNT(DISTINCT DATE(o.order_time)) AS operating_days
FROM branches b
LEFT JOIN orders o ON b.branch_id = o.branch_id
    AND o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY b.branch_id, b.name, b.branch_code;

-- Multi-branch sales comparison
CREATE VIEW daily_branch_sales AS
SELECT
    b.branch_id,
    b.name AS branch_name,
    DATE(o.order_time) AS sales_date,
    COUNT(o.order_id) AS order_count,
    SUM(o.total_amount) AS daily_revenue,
    AVG(o.total_amount) AS avg_order_value
FROM branches b
LEFT JOIN orders o ON b.branch_id = o.branch_id
    AND o.status = 'paid'
WHERE o.order_time >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY b.branch_id, b.name, DATE(o.order_time)
ORDER BY sales_date DESC, daily_revenue DESC;

-- Cross-branch employee performance
CREATE VIEW employee_branch_performance AS
SELECT
    e.employee_id,
    e.name AS employee_name,
    b.name AS branch_name,
    COUNT(o.order_id) AS orders_processed,
    SUM(o.total_amount) AS revenue_generated,
    AVG(o.total_amount) AS avg_order_value,
    DATE(MIN(o.order_time)) AS first_order_date,
    DATE(MAX(o.order_time)) AS last_order_date
FROM employees e
JOIN branches b ON e.branch_id = b.branch_id
LEFT JOIN orders o ON e.employee_id = o.employee_id
    AND o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY e.employee_id, e.name, b.name;
```

### Real-Time Dashboard Queries

```sql
-- Live branch status dashboard
CREATE OR REPLACE FUNCTION get_live_branch_status()
RETURNS TABLE (
    branch_id INT,
    branch_name VARCHAR(100),
    is_open BOOLEAN,
    current_orders INT,
    today_revenue DECIMAL(12,2),
    staff_on_duty INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.branch_id,
        b.name,
        CASE
            WHEN EXTRACT(hour FROM CURRENT_TIME) BETWEEN 8 AND 20
            THEN TRUE ELSE FALSE
        END AS is_open,
        COUNT(DISTINCT o.order_id)::INT AS current_orders,
        COALESCE(SUM(o.total_amount), 0)::DECIMAL(12,2) AS today_revenue,
        COUNT(DISTINCT e.employee_id)::INT AS staff_on_duty
    FROM branches b
    LEFT JOIN orders o ON b.branch_id = o.branch_id
        AND DATE(o.order_time) = CURRENT_DATE
        AND o.status IN ('open', 'paid')
    LEFT JOIN employees e ON b.branch_id = e.branch_id
        AND e.is_active = TRUE
    GROUP BY b.branch_id, b.name;
END;
$$ LANGUAGE plpgsql;
```

---

## 🔐 Security & Access Control

### Branch-Level Permissions

```sql
-- Branch-specific permissions
INSERT INTO permissions (code, name, description, group_id) VALUES
('MANAGE_BRANCH', 'Manage Branch', 'Full branch management access',
    (SELECT group_id FROM permission_groups WHERE name = 'System Administration')),
('VIEW_ALL_BRANCHES', 'View All Branches', 'Access to all branch data',
    (SELECT group_id FROM permission_groups WHERE name = 'Reporting')),
('TRANSFER_INVENTORY', 'Transfer Inventory', 'Move inventory between branches',
    (SELECT group_id FROM permission_groups WHERE name = 'Inventory Management')),
('CROSS_BRANCH_REPORTS', 'Cross-Branch Reports', 'Generate multi-branch reports',
    (SELECT group_id FROM permission_groups WHERE name = 'Reporting'));

-- Row Level Security for branch isolation
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY orders_branch_isolation ON orders
    FOR ALL TO pos_users
    USING (
        branch_id = get_employee_branch(current_setting('app.current_employee_id')::INT)
        OR
        employee_has_permission(
            current_setting('app.current_employee_id')::INT,
            'VIEW_ALL_BRANCHES'
        )
    );
```

### Session Management

```sql
-- Set employee context for session
CREATE OR REPLACE FUNCTION set_employee_session(emp_id INT, target_branch_id INT DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    allowed_branch_id INT;
BEGIN
    -- Verify employee can access the branch
    IF target_branch_id IS NOT NULL THEN
        SELECT eb.branch_id INTO allowed_branch_id
        FROM employee_branches eb
        WHERE eb.employee_id = emp_id
        AND eb.branch_id = target_branch_id
        AND eb.is_active = TRUE;

        IF allowed_branch_id IS NULL THEN
            RAISE EXCEPTION 'Employee % not authorized for branch %', emp_id, target_branch_id;
        END IF;
    END IF;

    -- Set session variables
    PERFORM set_config('app.current_employee_id', emp_id::TEXT, FALSE);
    PERFORM set_config('app.current_branch_id',
        COALESCE(target_branch_id, get_employee_branch(emp_id))::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;
```

---

## 📱 POS Application Integration

### API Changes Required

```sql
-- Branch-aware API endpoints
-- GET /api/branches - List all branches
-- GET /api/branches/{id} - Get branch details
-- POST /api/employees/{id}/switch-branch - Change employee's current branch
-- GET /api/inventory/{branch_id} - Branch-specific inventory
-- GET /api/reports/branch/{id} - Branch-specific reports
-- GET /api/reports/consolidated - Multi-branch reports
```

### Frontend Modifications

1. **Branch Selector**: Add branch dropdown in POS interface
2. **Branch Indicator**: Show current branch in header/status bar
3. **Cross-Branch Features**: Enable inventory transfers, employee assignments
4. **Reporting Dashboard**: Multi-branch analytics and comparisons
5. **Administration Panel**: Branch management interface

---

## 🚀 Deployment Strategy

### Phase 1: Foundation (Week 1-2)

- [ ] Create branch management tables
- [ ] Set up initial branch record
- [ ] Add branch_id to core tables
- [ ] Create branch-aware indexes

### Phase 2: Business Logic (Week 3-4)

- [ ] Implement branch-aware functions
- [ ] Create employee-branch assignments
- [ ] Set up inventory management strategy
- [ ] Deploy branch-specific configurations

### Phase 3: Reporting & Analytics (Week 5-6)

- [ ] Create multi-branch views
- [ ] Implement consolidated reporting
- [ ] Set up performance monitoring
- [ ] Create branch comparison dashboards

### Phase 4: Security & Access Control (Week 7-8)

- [ ] Implement row-level security
- [ ] Create branch-specific permissions
- [ ] Set up employee session management
- [ ] Test access control scenarios

### Phase 5: POS Integration (Week 9-10)

- [ ] Update POS application for multi-branch
- [ ] Add branch selection interface
- [ ] Implement cross-branch features
- [ ] Deploy and test end-to-end

---

## 💾 Sample Implementation

```sql
-- Sample branch setup
INSERT INTO branches (branch_code, name, address, phone, timezone, currency_code, tax_rate) VALUES
('MAIN', 'Main Street Café', '123 Main Street, Downtown', '+1-555-0100', 'America/New_York', 'USD', 8.50),
('DT01', 'Downtown Branch', '456 Business Ave, Downtown', '+1-555-0101', 'America/New_York', 'USD', 8.50),
('MLL02', 'Mall Location', 'Shopping Mall, Level 2, Store 205', '+1-555-0102', 'America/New_York', 'USD', 9.00);

-- Assign employees to branches
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level) VALUES
(1, 1, true, 'manager'),  -- Alice Johnson - Main branch manager
(2, 1, true, 'standard'), -- Bob Smith - Main branch barista
(3, 2, true, 'manager'),  -- Carol Davis - Downtown branch manager
(1, 2, false, 'manager'), -- Alice can also manage Downtown
(1, 3, false, 'manager'); -- Alice can manage Mall location

-- Branch-specific configurations
INSERT INTO branch_configs (branch_id, config_key, config_value, description) VALUES
(1, 'loyalty_multiplier', '{"multiplier": 1.0}', 'Standard loyalty points'),
(2, 'loyalty_multiplier', '{"multiplier": 1.2}', '20% bonus loyalty points'),
(3, 'pricing_multiplier', '{"multiplier": 1.1}', '10% price premium for mall location'),
(3, 'opening_hours', '{"mon": "10:00-22:00", "tue": "10:00-22:00", "wed": "10:00-22:00", "thu": "10:00-22:00", "fri": "10:00-23:00", "sat": "10:00-23:00", "sun": "11:00-21:00"}', 'Mall operating hours');
```

---

## 📈 Performance Considerations

### Database Optimization

1. **Partitioning**: Consider table partitioning by branch_id for large datasets
2. **Indexing**: Ensure all branch-aware queries have appropriate indexes
3. **Connection Pooling**: Implement branch-aware connection pooling
4. **Caching**: Cache branch configurations and employee permissions

### Scalability Planning

- **2-5 Branches**: Current architecture handles easily
- **6-15 Branches**: Consider read replicas for reporting
- **16-50 Branches**: Implement table partitioning and regional databases
- **50+ Branches**: Move to distributed architecture with data sharding

### Monitoring & Alerts

```sql
-- Branch performance monitoring
CREATE OR REPLACE FUNCTION monitor_branch_performance()
RETURNS TABLE (
    branch_id INT,
    branch_name VARCHAR(100),
    alert_type VARCHAR(50),
    alert_message TEXT,
    severity VARCHAR(20)
) AS $$
BEGIN
    RETURN QUERY
    -- Low sales alert
    SELECT
        b.branch_id,
        b.name,
        'LOW_SALES'::VARCHAR(50),
        'Daily sales below threshold'::TEXT,
        'WARNING'::VARCHAR(20)
    FROM branches b
    LEFT JOIN orders o ON b.branch_id = o.branch_id
        AND DATE(o.order_time) = CURRENT_DATE
        AND o.status = 'paid'
    GROUP BY b.branch_id, b.name
    HAVING COALESCE(SUM(o.total_amount), 0) < 500.00

    UNION ALL

    -- High refund rate alert
    SELECT
        b.branch_id,
        b.name,
        'HIGH_REFUNDS'::VARCHAR(50),
        'Refund rate above 5%'::TEXT,
        'CRITICAL'::VARCHAR(20)
    FROM branches b
    JOIN orders o ON b.branch_id = o.branch_id
        AND o.order_time >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY b.branch_id, b.name
    HAVING (COUNT(*) FILTER (WHERE o.status = 'refunded'))::FLOAT / COUNT(*) > 0.05;
END;
$$ LANGUAGE plpgsql;
```

---

## 🎯 Migration Path from Current System

### Step 1: Backward Compatibility

Your existing single-branch operations will continue to work unchanged. The system defaults to `branch_id = 1` for all existing data.

### Step 2: Gradual Migration

1. Deploy multi-branch schema extensions
2. Create initial branch record for current operation
3. Gradually enable multi-branch features
4. Train staff on new capabilities
5. Add new branches incrementally

### Step 3: Data Migration Script

```sql
-- Migrate existing data to multi-branch
BEGIN;

-- Create default branch
INSERT INTO branches (branch_id, branch_code, name, address, is_active)
VALUES (1, 'MAIN', 'Main Branch', 'Current Location', true);

-- Set all existing employees to main branch
UPDATE employees SET branch_id = 1 WHERE branch_id IS NULL;

-- Set all existing orders to main branch
UPDATE orders SET branch_id = 1 WHERE branch_id IS NULL;

-- Create employee-branch assignments for existing staff
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
SELECT employee_id, 1, true, 'standard'
FROM employees
WHERE is_active = true;

COMMIT;
```

---

## 🔮 Future Enhancements

### Advanced Features

1. **Franchise Management**: Support for franchisee operations
2. **Regional Clustering**: Group branches by region/district
3. **Mobile Workforce**: Support for delivery and catering services
4. **IoT Integration**: Smart equipment monitoring across branches
5. **AI Analytics**: Predictive analytics for inventory and staffing

### Integration Opportunities

1. **Central Kitchen**: Centralized food preparation coordination
2. **Delivery Platforms**: Multi-branch delivery service integration
3. **Corporate Accounts**: Business customer management across branches
4. **Seasonal Operations**: Temporary or pop-up location support

---

## ✅ Success Metrics

### Technical KPIs

- **Query Performance**: < 100ms for branch-aware queries
- **Data Consistency**: 99.9% synchronization accuracy
- **System Availability**: 99.95% uptime across all branches
- **Scalability**: Support 10x growth without architecture changes

### Business KPIs

- **Cross-Branch Efficiency**: 20% reduction in operational overhead
- **Reporting Speed**: Real-time consolidated reports in < 5 seconds
- **Staff Flexibility**: 50% of staff working across multiple branches
- **Inventory Optimization**: 15% reduction in waste through better distribution

---

## 📞 Implementation Support

This architecture design provides a complete roadmap for implementing multi-branch capabilities in your existing café POS system. The design maintains backward compatibility while providing enterprise-grade multi-location features.

**Next Steps:**

1. Review the proposed architecture
2. Prioritize features based on business needs
3. Begin with Phase 1 implementation
4. Plan branch rollout strategy

The multi-branch system will seamlessly integrate with your existing:

- ✅ **Multi-currency support** (USD, LAK, THB, EUR, JPY, GBP, CNY, SGD, VND)
- ✅ **RBAC permission system** (6 roles, 17 permissions)
- ✅ **Sugar level customization** (5 levels with pricing adjustments)
- ✅ **Performance optimization** (49 indexes)
- ✅ **Coffee shop features** (loyalty, inventory, recipes)

Your production-ready foundation provides the perfect base for scaling to a multi-branch enterprise!
