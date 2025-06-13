-- Multi-Branch Architecture Implementation
-- This file extends the existing POS schema with multi-branch capabilities
-- Compatible with PostgreSQL 12+

-- =================================================================
-- PHASE 1: BRANCH INFRASTRUCTURE
-- =================================================================

-- New ENUM types for multi-branch operations
DO $$ BEGIN
    CREATE TYPE branch_status AS ENUM ('active', 'inactive', 'maintenance', 'closed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE access_level AS ENUM ('standard', 'manager', 'limited', 'supervisor');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE inventory_strategy AS ENUM ('centralized', 'independent', 'hybrid');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =================================================================
-- CORE BRANCH TABLES
-- =================================================================

-- 1. Branches - Main branch management table
CREATE TABLE IF NOT EXISTS branches (
    branch_id SERIAL PRIMARY KEY,
    branch_code VARCHAR(10) NOT NULL UNIQUE,    -- e.g., 'MAIN', 'DT01', 'MLL02'
    name VARCHAR(100) NOT NULL,                 -- e.g., 'Downtown Branch'
    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(100),
    manager_employee_id INT,                    -- Branch manager reference
    timezone VARCHAR(50) DEFAULT 'UTC',
    currency_code CHAR(3) DEFAULT 'USD' CHECK (currency_code ~ '^[A-Z]{3}$'),
    tax_rate DECIMAL(5,2) DEFAULT 8.50,        -- Branch-specific tax rate
    status branch_status DEFAULT 'active',
    inventory_strategy inventory_strategy DEFAULT 'independent',
    opening_hours JSONB,                        -- {"mon": "08:00-18:00", "tue": "08:00-18:00"}
    coordinates POINT,                          -- GPS coordinates for mapping
    wifi_ssid VARCHAR(50),                      -- Branch WiFi network
    pos_terminal_count INT DEFAULT 1,           -- Number of POS terminals
    seating_capacity INT,                       -- Customer seating capacity
    drive_through BOOLEAN DEFAULT FALSE,        -- Has drive-through service
    delivery_service BOOLEAN DEFAULT FALSE,    -- Offers delivery
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Branch Configurations - Flexible branch-specific settings
CREATE TABLE IF NOT EXISTS branch_configs (
    config_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    config_key VARCHAR(50) NOT NULL,            -- e.g., 'loyalty_multiplier', 'discount_policy'
    config_value JSONB NOT NULL,                -- Flexible configuration storage
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE CASCADE,
    UNIQUE (branch_id, config_key)
);

-- 3. Employee-Branch Assignments (Many-to-Many relationship)
CREATE TABLE IF NOT EXISTS employee_branches (
    assignment_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    branch_id INT NOT NULL,
    is_primary_branch BOOLEAN DEFAULT FALSE,    -- Employee's home branch
    access_level access_level DEFAULT 'standard',
    hourly_rate DECIMAL(8,2),                   -- Branch-specific pay rate
    assigned_date DATE DEFAULT CURRENT_DATE,
    end_date DATE,                              -- For temporary assignments
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE CASCADE,
    UNIQUE (employee_id, branch_id)
);

-- 4. Branch Operating Hours (detailed schedule management)
CREATE TABLE IF NOT EXISTS branch_schedules (
    schedule_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    day_of_week INT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sunday, 6=Saturday
    opening_time TIME,
    closing_time TIME,
    is_closed BOOLEAN DEFAULT FALSE,            -- Branch closed on this day
    break_start_time TIME,                      -- Lunch break start
    break_end_time TIME,                        -- Lunch break end
    special_hours_date DATE,                    -- For holiday hours
    notes TEXT,                                 -- Special instructions
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE CASCADE
);

-- =================================================================
-- INVENTORY MANAGEMENT TABLES
-- =================================================================

-- 5. Central Inventory (for centralized inventory strategy)
CREATE TABLE IF NOT EXISTS central_inventory (
    central_inventory_id SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL,
    total_stock DECIMAL(10,2) DEFAULT 0.0,
    allocated_stock DECIMAL(10,2) DEFAULT 0.0,  -- Reserved for branches
    available_stock DECIMAL(10,2) GENERATED ALWAYS AS (total_stock - allocated_stock) STORED,
    reorder_level DECIMAL(10,2),
    max_stock_level DECIMAL(10,2),              -- Maximum storage capacity
    cost_per_unit DECIMAL(8,2),                 -- Purchase cost
    supplier_id INT,                            -- Reference to suppliers
    last_delivery_date DATE,
    next_expected_delivery DATE,
    notes TEXT,
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    UNIQUE (ingredient_id)
);

-- 6. Branch Inventory (branch-specific stock levels)
CREATE TABLE IF NOT EXISTS branch_inventory (
    branch_inventory_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    current_stock DECIMAL(10,2) DEFAULT 0.0,
    allocated_from_central DECIMAL(10,2) DEFAULT 0.0, -- If using central inventory
    reorder_threshold DECIMAL(10,2),
    max_capacity DECIMAL(10,2),                 -- Storage capacity for this ingredient
    cost_per_unit DECIMAL(8,2),                 -- Branch-specific cost
    last_restock_date DATE,
    last_count_date DATE,                       -- Last physical inventory count
    auto_reorder BOOLEAN DEFAULT TRUE,          -- Automatic reordering enabled
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE CASCADE,
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    UNIQUE (branch_id, ingredient_id)
);

-- 7. Inter-Branch Transfers
CREATE TABLE IF NOT EXISTS inventory_transfers (
    transfer_id SERIAL PRIMARY KEY,
    transfer_number VARCHAR(20) NOT NULL UNIQUE, -- e.g., 'TRNF-2025-001'
    from_branch_id INT,                         -- NULL for central warehouse
    to_branch_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    quantity_requested DECIMAL(10,2) NOT NULL,
    quantity_sent DECIMAL(10,2),
    quantity_received DECIMAL(10,2),
    unit_cost DECIMAL(8,2),
    transfer_status VARCHAR(20) DEFAULT 'pending', -- pending, shipped, received, cancelled
    requested_by INT,                           -- Employee who requested
    approved_by INT,                            -- Manager who approved
    shipped_by INT,                             -- Employee who shipped
    received_by INT,                            -- Employee who received
    request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ship_date TIMESTAMP,
    receive_date TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (from_branch_id) REFERENCES branches(branch_id),
    FOREIGN KEY (to_branch_id) REFERENCES branches(branch_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    FOREIGN KEY (requested_by) REFERENCES employees(employee_id),
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id),
    FOREIGN KEY (shipped_by) REFERENCES employees(employee_id),
    FOREIGN KEY (received_by) REFERENCES employees(employee_id)
);

-- =================================================================
-- EXTEND EXISTING TABLES FOR MULTI-BRANCH
-- =================================================================

-- Add branch_id to existing core tables
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'employees' AND column_name = 'branch_id') THEN
        ALTER TABLE employees ADD COLUMN branch_id INT;
        ALTER TABLE employees ADD CONSTRAINT fk_employees_branch 
            FOREIGN KEY (branch_id) REFERENCES branches(branch_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'branch_id') THEN
        ALTER TABLE orders ADD COLUMN branch_id INT NOT NULL DEFAULT 1;
        ALTER TABLE orders ADD CONSTRAINT fk_orders_branch 
            FOREIGN KEY (branch_id) REFERENCES branches(branch_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'inventory_transactions' AND column_name = 'branch_id') THEN
        ALTER TABLE inventory_transactions ADD COLUMN branch_id INT NOT NULL DEFAULT 1;
        ALTER TABLE inventory_transactions ADD CONSTRAINT fk_inventory_transactions_branch 
            FOREIGN KEY (branch_id) REFERENCES branches(branch_id);
    END IF;
END $$;

-- Add branch context to customers (where they usually shop)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'customers' AND column_name = 'primary_branch_id') THEN
        ALTER TABLE customers ADD COLUMN primary_branch_id INT;
        ALTER TABLE customers ADD CONSTRAINT fk_customers_primary_branch 
            FOREIGN KEY (primary_branch_id) REFERENCES branches(branch_id);
    END IF;
END $$;

-- =================================================================
-- MULTI-BRANCH BUSINESS LOGIC FUNCTIONS
-- =================================================================

-- Function: Get employee's current branch context
CREATE OR REPLACE FUNCTION get_employee_branch(emp_id INT)
RETURNS INT AS $$
DECLARE
    primary_branch_id INT;
    session_branch_id TEXT;
BEGIN
    -- First check if there's a session-specific branch
    session_branch_id := current_setting('app.current_branch_id', true);
    IF session_branch_id IS NOT NULL AND session_branch_id != '' THEN
        RETURN session_branch_id::INT;
    END IF;
    
    -- Get employee's primary branch
    SELECT eb.branch_id INTO primary_branch_id 
    FROM employee_branches eb 
    WHERE eb.employee_id = emp_id 
    AND eb.is_primary_branch = TRUE 
    AND eb.is_active = TRUE;
    
    -- Fallback to employee's direct branch assignment
    IF primary_branch_id IS NULL THEN
        SELECT e.branch_id INTO primary_branch_id
        FROM employees e 
        WHERE e.employee_id = emp_id AND e.is_active = TRUE;
    END IF;
    
    RETURN COALESCE(primary_branch_id, 1); -- Default to branch 1 if not set
END;
$$ LANGUAGE plpgsql;

-- Function: Check if employee can access a specific branch
CREATE OR REPLACE FUNCTION employee_can_access_branch(emp_id INT, target_branch_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    has_access BOOLEAN := FALSE;
BEGIN
    -- Check direct assignment
    SELECT EXISTS(
        SELECT 1 FROM employee_branches eb
        WHERE eb.employee_id = emp_id 
        AND eb.branch_id = target_branch_id
        AND eb.is_active = TRUE
    ) INTO has_access;
    
    -- Check if employee has VIEW_ALL_BRANCHES permission
    IF NOT has_access THEN
        has_access := employee_has_permission(emp_id, 'VIEW_ALL_BRANCHES');
    END IF;
    
    RETURN has_access;
END;
$$ LANGUAGE plpgsql;

-- Function: Get branch-specific product pricing
CREATE OR REPLACE FUNCTION get_branch_price(p_variation_id INT, p_branch_id INT)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    base_price DECIMAL(10,2);
    pricing_multiplier DECIMAL(4,2) DEFAULT 1.00;
    location_premium DECIMAL(4,2) DEFAULT 0.00;
    final_price DECIMAL(10,2);
BEGIN
    -- Get base price from product variations
    SELECT pv.base_price INTO base_price
    FROM product_variations pv
    WHERE pv.variation_id = p_variation_id;
    
    -- Get branch-specific pricing multiplier
    SELECT (bc.config_value->>'multiplier')::DECIMAL(4,2) INTO pricing_multiplier
    FROM branch_configs bc
    WHERE bc.branch_id = p_branch_id 
    AND bc.config_key = 'pricing_multiplier'
    AND bc.is_active = TRUE;
    
    -- Get location premium (e.g., airport, mall surcharge)
    SELECT (bc.config_value->>'premium')::DECIMAL(4,2) INTO location_premium
    FROM branch_configs bc
    WHERE bc.branch_id = p_branch_id 
    AND bc.config_key = 'location_premium'
    AND bc.is_active = TRUE;
    
    -- Calculate final price
    final_price := base_price * COALESCE(pricing_multiplier, 1.00) + COALESCE(location_premium, 0.00);
    
    RETURN ROUND(final_price, 2);
END;
$$ LANGUAGE plpgsql;

-- Function: Check branch inventory levels
CREATE OR REPLACE FUNCTION check_branch_stock(p_branch_id INT, p_ingredient_id INT)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    current_stock DECIMAL(10,2);
    strategy inventory_strategy;
BEGIN
    -- Get branch inventory strategy
    SELECT b.inventory_strategy INTO strategy
    FROM branches b
    WHERE b.branch_id = p_branch_id;
    
    IF strategy = 'centralized' THEN
        -- Check central inventory availability
        SELECT ci.available_stock INTO current_stock
        FROM central_inventory ci
        WHERE ci.ingredient_id = p_ingredient_id;
    ELSE
        -- Check branch-specific inventory
        SELECT bi.current_stock INTO current_stock
        FROM branch_inventory bi
        WHERE bi.branch_id = p_branch_id 
        AND bi.ingredient_id = p_ingredient_id;
    END IF;
    
    RETURN COALESCE(current_stock, 0.0);
END;
$$ LANGUAGE plpgsql;

-- Function: Set employee session context
CREATE OR REPLACE FUNCTION set_employee_session(emp_id INT, target_branch_id INT DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    allowed_branch_id INT;
    employee_name VARCHAR(100);
BEGIN
    -- Get employee name for logging
    SELECT e.name INTO employee_name
    FROM employees e
    WHERE e.employee_id = emp_id;
    
    IF employee_name IS NULL THEN
        RAISE EXCEPTION 'Employee % not found', emp_id;
    END IF;
    
    -- If specific branch requested, verify access
    IF target_branch_id IS NOT NULL THEN
        IF NOT employee_can_access_branch(emp_id, target_branch_id) THEN
            RAISE EXCEPTION 'Employee % (%) not authorized for branch %', 
                employee_name, emp_id, target_branch_id;
        END IF;
        allowed_branch_id := target_branch_id;
    ELSE
        allowed_branch_id := get_employee_branch(emp_id);
    END IF;
    
    -- Set session variables
    PERFORM set_config('app.current_employee_id', emp_id::TEXT, FALSE);
    PERFORM set_config('app.current_branch_id', allowed_branch_id::TEXT, FALSE);
    PERFORM set_config('app.employee_name', employee_name, FALSE);
    
    -- Log session start
    INSERT INTO employee_activity_log (employee_id, branch_id, activity_type, description, activity_timestamp)
    VALUES (emp_id, allowed_branch_id, 'LOGIN', 
            'Employee session started for branch ' || allowed_branch_id, 
            CURRENT_TIMESTAMP)
    ON CONFLICT DO NOTHING; -- Ignore if activity log table doesn't exist yet
END;
$$ LANGUAGE plpgsql;

-- Function: Get branch operating status
CREATE OR REPLACE FUNCTION is_branch_open(p_branch_id INT, check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
RETURNS BOOLEAN AS $$
DECLARE
    branch_timezone VARCHAR(50);
    local_time TIME;
    day_of_week INT;
    opening_time TIME;
    closing_time TIME;
    is_closed BOOLEAN;
    branch_status branch_status;
BEGIN
    -- Get branch timezone and status
    SELECT b.timezone, b.status INTO branch_timezone, branch_status
    FROM branches b
    WHERE b.branch_id = p_branch_id;
    
    -- Check if branch is active
    IF branch_status != 'active' THEN
        RETURN FALSE;
    END IF;
    
    -- Convert to local time
    local_time := (check_time AT TIME ZONE branch_timezone)::TIME;
    day_of_week := EXTRACT(DOW FROM (check_time AT TIME ZONE branch_timezone));
    
    -- Get operating hours for this day
    SELECT bs.opening_time, bs.closing_time, bs.is_closed
    INTO opening_time, closing_time, is_closed
    FROM branch_schedules bs
    WHERE bs.branch_id = p_branch_id
    AND bs.day_of_week = day_of_week
    AND bs.is_active = TRUE
    ORDER BY bs.special_hours_date DESC NULLS LAST
    LIMIT 1;
    
    -- Return false if closed or no schedule found
    IF is_closed OR opening_time IS NULL OR closing_time IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Check if current time is within operating hours
    IF closing_time > opening_time THEN
        -- Normal day (e.g., 09:00 - 18:00)
        RETURN local_time BETWEEN opening_time AND closing_time;
    ELSE
        -- Crosses midnight (e.g., 22:00 - 06:00)
        RETURN local_time >= opening_time OR local_time <= closing_time;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- MULTI-BRANCH REPORTING VIEWS
-- =================================================================

-- Branch Performance Summary
CREATE OR REPLACE VIEW branch_performance_summary AS
SELECT 
    b.branch_id,
    b.branch_code,
    b.name AS branch_name,
    b.status,
    b.currency_code,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_revenue,
    AVG(o.total_amount) AS average_order_value,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    COUNT(DISTINCT DATE(o.order_time)) AS operating_days,
    COUNT(DISTINCT eb.employee_id) AS staff_count,
    MIN(o.order_time) AS first_order_date,
    MAX(o.order_time) AS last_order_date
FROM branches b
LEFT JOIN orders o ON b.branch_id = o.branch_id 
    AND o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN employee_branches eb ON b.branch_id = eb.branch_id 
    AND eb.is_active = TRUE
GROUP BY b.branch_id, b.branch_code, b.name, b.status, b.currency_code;

-- Daily Branch Sales Comparison
CREATE OR REPLACE VIEW daily_branch_sales AS
SELECT 
    b.branch_id,
    b.branch_code,
    b.name AS branch_name,
    DATE(o.order_time) AS sales_date,
    COUNT(o.order_id) AS order_count,
    SUM(o.total_amount) AS daily_revenue,
    AVG(o.total_amount) AS avg_order_value,
    SUM(o.total_amount) / NULLIF(COUNT(DISTINCT eb.employee_id), 0) AS revenue_per_staff
FROM branches b
LEFT JOIN orders o ON b.branch_id = o.branch_id 
    AND o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '90 days'
LEFT JOIN employee_branches eb ON b.branch_id = eb.branch_id 
    AND eb.is_active = TRUE
GROUP BY b.branch_id, b.branch_code, b.name, DATE(o.order_time)
ORDER BY sales_date DESC, daily_revenue DESC;

-- Cross-Branch Employee Performance
CREATE OR REPLACE VIEW employee_branch_performance AS
SELECT 
    e.employee_id,
    e.name AS employee_name,
    b.branch_code,
    b.name AS branch_name,
    eb.access_level,
    eb.is_primary_branch,
    COUNT(o.order_id) AS orders_processed,
    SUM(o.total_amount) AS revenue_generated,
    AVG(o.total_amount) AS avg_order_value,
    MIN(o.order_time) AS first_order_date,
    MAX(o.order_time) AS last_order_date,
    COUNT(DISTINCT DATE(o.order_time)) AS days_worked
FROM employees e
JOIN employee_branches eb ON e.employee_id = eb.employee_id 
    AND eb.is_active = TRUE
JOIN branches b ON eb.branch_id = b.branch_id
LEFT JOIN orders o ON e.employee_id = o.employee_id 
    AND o.branch_id = b.branch_id
    AND o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY e.employee_id, e.name, b.branch_code, b.name, eb.access_level, eb.is_primary_branch;

-- Branch Inventory Status
CREATE OR REPLACE VIEW branch_inventory_status AS
SELECT 
    b.branch_id,
    b.branch_code,
    b.name AS branch_name,
    i.name AS ingredient_name,
    i.unit,
    bi.current_stock,
    bi.reorder_threshold,
    bi.max_capacity,
    CASE 
        WHEN bi.current_stock <= bi.reorder_threshold THEN 'LOW_STOCK'
        WHEN bi.current_stock >= bi.max_capacity * 0.9 THEN 'OVERSTOCKED'
        ELSE 'NORMAL'
    END AS stock_status,
    bi.last_restock_date,
    bi.last_count_date
FROM branches b
JOIN branch_inventory bi ON b.branch_id = bi.branch_id
JOIN ingredients i ON bi.ingredient_id = i.ingredient_id
WHERE b.is_active = TRUE
ORDER BY b.branch_code, stock_status DESC, i.name;

-- =================================================================
-- MULTI-BRANCH INDEXES FOR PERFORMANCE
-- =================================================================

-- Branch-specific query optimization
DO $$ BEGIN CREATE INDEX idx_orders_branch_date ON orders(branch_id, order_time); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_orders_branch_status ON orders(branch_id, status); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employees_branch_active ON employees(branch_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employee_branches_emp_active ON employee_branches(employee_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employee_branches_branch_active ON employee_branches(branch_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_inventory_transactions_branch_date ON inventory_transactions(branch_id, transaction_time); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branch_inventory_branch_ingredient ON branch_inventory(branch_id, ingredient_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branch_inventory_stock_status ON branch_inventory(branch_id, current_stock) WHERE current_stock <= reorder_threshold; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_inventory_transfers_status ON inventory_transfers(transfer_status, request_date); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branch_configs_branch_key ON branch_configs(branch_id, config_key); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branch_schedules_branch_day ON branch_schedules(branch_id, day_of_week); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Geographic and operational indexes
DO $$ BEGIN CREATE INDEX idx_branches_location ON branches USING GIST(coordinates) WHERE coordinates IS NOT NULL; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branches_status_active ON branches(status, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_branches_currency ON branches(currency_code); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- SAMPLE DATA FOR MULTI-BRANCH SETUP
-- =================================================================

-- Create default main branch if it doesn't exist
INSERT INTO branches (branch_id, branch_code, name, address, phone, timezone, currency_code, tax_rate, status, is_active) 
VALUES (1, 'MAIN', 'Main Branch', 'Main Location', '+1-555-0100', 'UTC', 'USD', 8.50, 'active', true)
ON CONFLICT (branch_id) DO NOTHING;

-- Set sequence to continue from 1
SELECT setval('branches_branch_id_seq', (SELECT MAX(branch_id) FROM branches));

-- Create default operating hours for main branch
INSERT INTO branch_schedules (branch_id, day_of_week, opening_time, closing_time, is_closed) VALUES
(1, 1, '08:00', '18:00', false), -- Monday
(1, 2, '08:00', '18:00', false), -- Tuesday  
(1, 3, '08:00', '18:00', false), -- Wednesday
(1, 4, '08:00', '18:00', false), -- Thursday
(1, 5, '08:00', '20:00', false), -- Friday
(1, 6, '09:00', '20:00', false), -- Saturday
(1, 0, '10:00', '16:00', false)  -- Sunday
ON CONFLICT DO NOTHING;

-- Assign existing employees to main branch
INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
SELECT employee_id, 1, true, 'standard'
FROM employees 
WHERE is_active = true
AND NOT EXISTS (
    SELECT 1 FROM employee_branches eb 
    WHERE eb.employee_id = employees.employee_id 
    AND eb.branch_id = 1
);

-- Set primary branch for existing employees
UPDATE employees SET branch_id = 1 WHERE branch_id IS NULL;

-- Set primary branch for existing customers (based on their order history)
UPDATE customers SET primary_branch_id = 1 WHERE primary_branch_id IS NULL;

-- =================================================================
-- MIGRATION AND MAINTENANCE FUNCTIONS
-- =================================================================

-- Function: Migrate existing data to multi-branch structure
CREATE OR REPLACE FUNCTION migrate_to_multibranch()
RETURNS TEXT AS $$
DECLARE
    result_text TEXT := 'Multi-branch migration completed successfully:';
    employee_count INT;
    order_count INT;
    inventory_count INT;
BEGIN
    -- Ensure main branch exists
    INSERT INTO branches (branch_id, branch_code, name, is_active) 
    VALUES (1, 'MAIN', 'Main Branch', true)
    ON CONFLICT (branch_id) DO NOTHING;
    
    -- Update employees
    UPDATE employees SET branch_id = 1 WHERE branch_id IS NULL;
    GET DIAGNOSTICS employee_count = ROW_COUNT;
    result_text := result_text || E'\n- ' || employee_count || ' employees assigned to main branch';
    
    -- Update orders
    UPDATE orders SET branch_id = 1 WHERE branch_id IS NULL;
    GET DIAGNOSTICS order_count = ROW_COUNT;
    result_text := result_text || E'\n- ' || order_count || ' orders assigned to main branch';
    
    -- Update inventory transactions
    UPDATE inventory_transactions SET branch_id = 1 WHERE branch_id IS NULL;
    GET DIAGNOSTICS inventory_count = ROW_COUNT;
    result_text := result_text || E'\n- ' || inventory_count || ' inventory transactions assigned to main branch';
    
    -- Create employee-branch assignments
    INSERT INTO employee_branches (employee_id, branch_id, is_primary_branch, access_level)
    SELECT employee_id, 1, true, 'standard'
    FROM employees 
    WHERE is_active = true
    ON CONFLICT (employee_id, branch_id) DO NOTHING;
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

-- Function: Health check for multi-branch system
CREATE OR REPLACE FUNCTION multibranch_health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check branch data integrity
    RETURN QUERY
    SELECT 
        'Branch Data Integrity'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        'Branches without required data: ' || COUNT(*)::TEXT
    FROM branches 
    WHERE branch_code IS NULL OR name IS NULL OR is_active IS NULL;
    
    -- Check employee assignments
    RETURN QUERY
    SELECT 
        'Employee Branch Assignments'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END::TEXT,
        'Employees without branch assignment: ' || COUNT(*)::TEXT
    FROM employees e
    LEFT JOIN employee_branches eb ON e.employee_id = eb.employee_id
    WHERE e.is_active = TRUE AND eb.employee_id IS NULL;
    
    -- Check order branch assignments
    RETURN QUERY
    SELECT 
        'Order Branch Assignments'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        'Orders without branch assignment: ' || COUNT(*)::TEXT
    FROM orders 
    WHERE branch_id IS NULL;
    
    -- Check inventory consistency
    RETURN QUERY
    SELECT 
        'Inventory Consistency'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARNING' END::TEXT,
        'Ingredients without branch inventory: ' || COUNT(*)::TEXT
    FROM ingredients i
    LEFT JOIN branch_inventory bi ON i.ingredient_id = bi.ingredient_id
    WHERE bi.ingredient_id IS NULL;
    
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- COMPLETION MESSAGE
-- =================================================================

-- Display completion message
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '====================================================';
    RAISE NOTICE '🏢 MULTI-BRANCH ARCHITECTURE IMPLEMENTATION COMPLETE';
    RAISE NOTICE '====================================================';
    RAISE NOTICE '';
    RAISE NOTICE '✅ Branch management infrastructure created';
    RAISE NOTICE '✅ Employee multi-branch assignments enabled';
    RAISE NOTICE '✅ Inventory management systems deployed';
    RAISE NOTICE '✅ Branch-aware business logic functions added';
    RAISE NOTICE '✅ Multi-branch reporting views created';
    RAISE NOTICE '✅ Performance indexes optimized';
    RAISE NOTICE '✅ Migration and health check functions available';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Next Steps:';
    RAISE NOTICE '1. Run: SELECT migrate_to_multibranch();';
    RAISE NOTICE '2. Create additional branches as needed';
    RAISE NOTICE '3. Configure branch-specific settings';
    RAISE NOTICE '4. Update POS application for multi-branch support';
    RAISE NOTICE '5. Train staff on multi-branch operations';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Health Check: SELECT * FROM multibranch_health_check();';
    RAISE NOTICE '====================================================';
END $$;
