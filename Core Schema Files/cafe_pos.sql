-- PostgreSQL POS System Database Schema
-- Compatible with PostgreSQL 12+

-- Create custom ENUM types (with IF NOT EXISTS to prevent conflicts)
DO $$ BEGIN
    CREATE TYPE product_size AS ENUM ('small', 'medium', 'large');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE product_type AS ENUM ('hot', 'ice', 'shake', 'none');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('open', 'paid', 'canceled', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('sale', 'restock', 'waste', 'adjustment');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Note: employee_role ENUM removed - now using roles table with foreign key relationship
-- DO $$ BEGIN
--     CREATE TYPE employee_role AS ENUM ('cashier', 'barista', 'manager');
-- EXCEPTION
--     WHEN duplicate_object THEN null;
-- END $$;

DO $$ BEGIN
    CREATE TYPE sugar_level AS ENUM (
        'no_sugar',     -- 0% sugar
        'less_sugar',   -- 25% sugar
        'regular',      -- 50% sugar (default)
        'more_sugar',   -- 75% sugar
        'extra_sweet'   -- 100% sugar
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Multi-Branch ENUM Types
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

-- Removed fixed currency_code ENUM - now using CHAR(3) for flexibility

-- Core Tables (Revised) - Using IF NOT EXISTS to prevent conflicts
-- 1. Table: categories
CREATE TABLE IF NOT EXISTS categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    display_order INT,
    is_active BOOLEAN DEFAULT TRUE
);

-- 2. Table: roles (moved here to resolve dependency)
CREATE TABLE IF NOT EXISTS roles (
    role_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,   -- e.g., "Manager", "Barista"
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Table: branches (Multi-Branch Infrastructure)
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

-- 4. Table: branch_configs (Branch-specific settings)
CREATE TABLE IF NOT EXISTS branch_configs (
    config_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL,
    config_key VARCHAR(50) NOT NULL,            -- e.g., 'loyalty_multiplier', 'pricing_multiplier'
    config_value JSONB NOT NULL,                -- Flexible configuration storage
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE CASCADE,
    UNIQUE (branch_id, config_key)
);

-- 5. Table: branch_schedules (Operating hours management)
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

-- 6. Table: employees
CREATE TABLE IF NOT EXISTS employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    pin CHAR(6) NOT NULL UNIQUE,         -- 6-digit PIN for login
    role_id INT,                         -- References roles table
    branch_id INT,                       -- Primary branch assignment
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (role_id) REFERENCES roles(role_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
);

-- 7. Table: employee_branches (Employee-Branch assignments)
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

-- 8. Table: customers
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    phone VARCHAR(20) UNIQUE,            
    name VARCHAR(100),
    email VARCHAR(100),
    loyalty_points INT DEFAULT 0,
    visit_count INT DEFAULT 0,
    last_visit DATE,
    primary_branch_id INT,               -- Customer's preferred branch
    FOREIGN KEY (primary_branch_id) REFERENCES branches(branch_id)
);

-- 9. Table: payment_methods
CREATE TABLE IF NOT EXISTS payment_methods (
    method_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,   -- e.g., "Cash", "Credit Card"
    processor VARCHAR(50),              -- e.g., "Stripe", "Square"
    requires_terminal BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE
);

-- 10. Table: products
CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- e.g., "Latte", "Croissant"
    description TEXT,
    category_id INT NOT NULL,
    has_variants BOOLEAN DEFAULT FALSE,  -- Flag for UI/backend handling
    base_price DECIMAL(10,2) NOT NULL,  -- Price in base currency
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);


-- =================================================================
-- FLEXIBLE VARIANT SYSTEM TABLES (PostgreSQL)
-- =================================================================

-- 11. Table: variant_templates
-- Variant Types (Size/Type Templates)
CREATE TABLE IF NOT EXISTS variant_templates (
    template_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,  -- "Coffee Size", "Temperature", etc.
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 12. Table: variant_options
-- Variant Options (Predefined Values)
CREATE TABLE IF NOT EXISTS variant_options (
    option_id SERIAL PRIMARY KEY,
    template_id INT NOT NULL,
    value VARCHAR(50) NOT NULL,       -- "small", "hot", etc.
    display_name VARCHAR(100),        -- "Small (8oz)", "Hot", etc.
    display_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (template_id, value),
    FOREIGN KEY (template_id) REFERENCES variant_templates(template_id) ON DELETE CASCADE
);

-- 13. Table: product_variations
CREATE TABLE IF NOT EXISTS product_variations (
    variation_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,  -- Price in base currency
    cost DECIMAL(10,2),                 -- Production cost in base currency
    sku VARCHAR(20) UNIQUE,             -- e.g., "LAT-M-ICE"
    is_available BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- 14. Table: variation_templates
-- Variation Templates (Size/Type Combinations)
-- Variation-Option Links (Many-to-Many)
CREATE TABLE IF NOT EXISTS variation_options (
    variation_id INT NOT NULL,
    option_id INT NOT NULL,
    PRIMARY KEY (variation_id, option_id),
    FOREIGN KEY (variation_id) REFERENCES product_variations(variation_id) ON DELETE CASCADE,
    FOREIGN KEY (option_id) REFERENCES variant_options(option_id) ON DELETE CASCADE
);

-- 15. Table: orders
CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(20) NOT NULL UNIQUE, -- "CAFE-2025-1001"
    employee_id INT NOT NULL,            
    customer_id INT,                     -- Loyalty program link
    branch_id INT NOT NULL DEFAULT 1,    -- Branch where order was placed
    order_time TIMESTAMP NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD' CHECK (currency_code ~ '^[A-Z]{3}$'),
    exchange_rate DECIMAL(15,6) DEFAULT 1.0, -- Rate used for this order
    subtotal DECIMAL(12,2) NOT NULL,     -- In order currency
    tax_rate DECIMAL(5,2) NOT NULL,      -- e.g., 8.5
    tax_amount DECIMAL(10,2) NOT NULL,   -- In order currency
    tip_amount DECIMAL(10,2) DEFAULT 0.00, -- In order currency
    total_amount DECIMAL(12,2) NOT NULL, -- Final amount in order currency
    base_total_amount DECIMAL(12,2) NOT NULL, -- Total in base currency (USD)
    status order_status DEFAULT 'open',
    notes TEXT,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
);

-- 16. Table: order_payments
CREATE TABLE IF NOT EXISTS order_payments (
    payment_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    method_id INT NOT NULL,
    currency_code CHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
    amount DECIMAL(12,2) NOT NULL,       -- Amount in payment currency
    base_amount DECIMAL(12,2) NOT NULL,  -- Amount in base currency (USD)
    exchange_rate DECIMAL(15,6) NOT NULL, -- Rate used for this payment
    tip_amount DECIMAL(10,2) DEFAULT 0.00,-- Tip portion in payment currency
    transaction_id VARCHAR(100),          -- Processor reference
    card_last4 CHAR(4),                  -- For card payments
    status payment_status DEFAULT 'completed',
    payment_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (method_id) REFERENCES payment_methods(method_id)
);

-- 17. Table: order_items
CREATE TABLE IF NOT EXISTS order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    variation_id INT NOT NULL,           
    quantity INT NOT NULL DEFAULT 1,
    base_unit_price DECIMAL(10,2) NOT NULL,    -- Price in base currency
    display_unit_price DECIMAL(10,2) NOT NULL, -- Price in order currency
    modifiers JSONB,                     -- e.g., {"whipped_cream": true, "sugar_level": "regular"}
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (variation_id) REFERENCES product_variations(variation_id),
    -- Constraint to validate sugar level in modifiers
    CONSTRAINT valid_sugar_level CHECK (
        modifiers IS NULL OR 
        NOT modifiers ? 'sugar_level' OR 
        modifiers->>'sugar_level' IN ('no_sugar', 'less_sugar', 'regular', 'more_sugar', 'extra_sweet')
    )
);

-- Inventory & Recipe Tables
-- 18. Table: ingredients
CREATE TABLE IF NOT EXISTS ingredients (
    ingredient_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,  -- e.g., "Coffee Beans", "Oat Milk"
    unit VARCHAR(20) NOT NULL,          -- e.g., "kg", "L"
    current_stock DECIMAL(10,2) DEFAULT 0.0,
    reorder_level DECIMAL(10,2),
    supplier VARCHAR(100)
);

-- 19. Table: recipes
CREATE TABLE IF NOT EXISTS recipes (
    recipe_id SERIAL PRIMARY KEY,
    variation_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    quantity DECIMAL(8,4) NOT NULL,      -- e.g., 0.03 (kg per item)
    FOREIGN KEY (variation_id) REFERENCES product_variations(variation_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    UNIQUE (variation_id, ingredient_id)
);

-- 20. Table: inventory_transactions
CREATE TABLE IF NOT EXISTS inventory_transactions (
    transaction_id SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL,
    change DECIMAL(10,2) NOT NULL,       -- +ve = add, -ve = deduct
    transaction_type transaction_type,
    related_order_id INT,                -- For sales deductions
    employee_id INT,                     -- Who performed
    branch_id INT NOT NULL DEFAULT 1,    -- Branch where transaction occurred
    transaction_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
);

-- Multi-Branch Inventory Management Tables
-- 21. Table: central_inventory (for centralized inventory strategy)
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

-- 22. Table: branch_inventory (branch-specific stock levels)
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

-- 23. Table: inventory_transfers (inter-branch transfers)
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

-- Multi-Currency Support Tables
-- 24. Table: currencies
CREATE TABLE IF NOT EXISTS currencies (
    currency_id SERIAL PRIMARY KEY,
    code CHAR(3) NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{3}$'),
    name VARCHAR(50) NOT NULL,          -- e.g., "US Dollar", "Lao Kip", "Thai Baht"
    symbol VARCHAR(10) NOT NULL,        -- e.g., "$", "₭", "฿", "€", "¥", "£"
    decimal_places SMALLINT DEFAULT 2,  -- e.g., 2 for USD, 0 for LAK
    is_base_currency BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE
);

-- 25. Table: exchange_rates
CREATE TABLE IF NOT EXISTS exchange_rates (
    rate_id SERIAL PRIMARY KEY,
    from_currency CHAR(3) NOT NULL CHECK (from_currency ~ '^[A-Z]{3}$'),
    to_currency CHAR(3) NOT NULL CHECK (to_currency ~ '^[A-Z]{3}$'),
    rate DECIMAL(15,6) NOT NULL,        -- High precision for accurate conversion
    effective_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (from_currency, to_currency, effective_date)
);

-- 26. Table: exchange_rate_history
CREATE TABLE IF NOT EXISTS exchange_rate_history (
    history_id SERIAL PRIMARY KEY,
    rate_id INT NOT NULL,
    from_currency CHAR(3) NOT NULL CHECK (from_currency ~ '^[A-Z]{3}$'),
    to_currency CHAR(3) NOT NULL CHECK (to_currency ~ '^[A-Z]{3}$'),
    rate DECIMAL(15,6) NOT NULL,
    effective_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (rate_id) REFERENCES exchange_rates(rate_id)
);

-- 27. Table: permission_groups
CREATE TABLE IF NOT EXISTS permission_groups (
    group_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,   -- e.g., "Admin", "Staff"
    description TEXT
);

-- 28. Table: permissions
CREATE TABLE IF NOT EXISTS permissions (
    permission_id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,  -- e.g., "CREATE_ORDER", "PROCESS_REFUND"
    name VARCHAR(100) NOT NULL,         -- e.g., "Create Order", "Process Refund"
    description TEXT,                   -- Detailed description of the permission
    group_id INT NOT NULL,              -- Link to permission group
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES permission_groups(group_id)
);

-- 29. Table: role_permissions
CREATE TABLE IF NOT EXISTS role_permissions (
    role_permission_id SERIAL PRIMARY KEY,
    role_id INT NOT NULL,
    permission_id INT NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    granted_by INT,  -- Employee who granted this permission
    FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE,
    FOREIGN KEY (granted_by) REFERENCES employees(employee_id),
    UNIQUE (role_id, permission_id)
);

-- 30. Table: employee_roles (Many-to-Many: Employee to Role)
CREATE TABLE IF NOT EXISTS employee_roles (
    employee_role_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    role_id INT NOT NULL,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_by INT,  -- Manager who assigned this role
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_by) REFERENCES employees(employee_id),
    UNIQUE (employee_id, role_id)
);

-- Multi-Currency Helper Functions
-- Function to get current exchange rate
CREATE OR REPLACE FUNCTION get_exchange_rate(
    from_curr CHAR(3),
    to_curr CHAR(3)
) RETURNS DECIMAL(15,6) AS $$
BEGIN
    -- If same currency, return 1
    IF from_curr = to_curr THEN
        RETURN 1.0;
    END IF;
    
    -- Get latest exchange rate
    RETURN (
        SELECT rate 
        FROM exchange_rates 
        WHERE from_currency = from_curr 
          AND to_currency = to_curr 
          AND is_active = true
        ORDER BY effective_date DESC 
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;

-- Function to convert amount between currencies
CREATE OR REPLACE FUNCTION convert_currency(
    amount DECIMAL(12,2),
    from_curr CHAR(3),
    to_curr CHAR(3)
) RETURNS DECIMAL(12,2) AS $$
DECLARE
    rate DECIMAL(15,6);
BEGIN
    rate := get_exchange_rate(from_curr, to_curr);
    IF rate IS NULL THEN
        RAISE EXCEPTION 'No exchange rate found for % to %', from_curr, to_curr;
    END IF;
    
    RETURN ROUND(amount * rate, 2);
END;
$$ LANGUAGE plpgsql;

-- Function to format currency display
CREATE OR REPLACE FUNCTION format_currency(
    amount DECIMAL(12,2),
    curr_code CHAR(3)
) RETURNS TEXT AS $$
DECLARE
    curr_symbol VARCHAR(10);
    decimal_places SMALLINT;
BEGIN
    SELECT symbol, decimal_places 
    INTO curr_symbol, decimal_places
    FROM currencies 
    WHERE code = curr_code;
    
    -- Handle currencies without decimals (LAK, JPY, VND)
    IF curr_code IN ('LAK', 'JPY', 'VND') THEN
        RETURN curr_symbol || TO_CHAR(amount, 'FM999,999,999');
    ELSE
        -- Format with decimals for most currencies
        RETURN curr_symbol || TO_CHAR(amount, 'FM999,999,999.00');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Sample Data for Multi-Currency Setup (Flexible Currency Support)
INSERT INTO currencies (code, name, symbol, decimal_places, is_base_currency, is_active) VALUES
('USD', 'US Dollar', '$', 2, true, true),
('LAK', 'Lao Kip', '₭', 0, false, true),
('THB', 'Thai Baht', '฿', 2, false, true),
('EUR', 'Euro', '€', 2, false, true),
('JPY', 'Japanese Yen', '¥', 0, false, true),
('GBP', 'British Pound', '£', 2, false, true),
('CNY', 'Chinese Yuan', '¥', 2, false, true),
('SGD', 'Singapore Dollar', 'S$', 2, false, true),
('VND', 'Vietnamese Dong', '₫', 0, false, true);

-- Sample exchange rates (you should update these regularly)
INSERT INTO exchange_rates (from_currency, to_currency, rate, effective_date) VALUES
-- USD to other currencies
('USD', 'LAK', 21000.00, CURRENT_TIMESTAMP),
('USD', 'THB', 36.50, CURRENT_TIMESTAMP),
('USD', 'EUR', 0.85, CURRENT_TIMESTAMP),
('USD', 'JPY', 110.00, CURRENT_TIMESTAMP),
('USD', 'GBP', 0.73, CURRENT_TIMESTAMP),
('USD', 'CNY', 6.45, CURRENT_TIMESTAMP),
('USD', 'SGD', 1.35, CURRENT_TIMESTAMP),
('USD', 'VND', 23000.00, CURRENT_TIMESTAMP),

-- Other currencies to USD
('LAK', 'USD', 0.0000476, CURRENT_TIMESTAMP),
('THB', 'USD', 0.0274, CURRENT_TIMESTAMP),
('EUR', 'USD', 1.18, CURRENT_TIMESTAMP),
('JPY', 'USD', 0.0091, CURRENT_TIMESTAMP),
('GBP', 'USD', 1.37, CURRENT_TIMESTAMP),
('CNY', 'USD', 0.155, CURRENT_TIMESTAMP),
('SGD', 'USD', 0.74, CURRENT_TIMESTAMP),
('VND', 'USD', 0.0000435, CURRENT_TIMESTAMP),

-- Cross rates (LAK to THB and vice versa)
('LAK', 'THB', 0.00174, CURRENT_TIMESTAMP),
('THB', 'LAK', 575.34, CURRENT_TIMESTAMP);

-- Views for easier currency operations
-- View: product_prices_multi_currency (showing major currencies)
CREATE OR REPLACE VIEW product_prices_multi_currency AS
SELECT 
    pv.variation_id,
    p.name as product_name,
    pv.size,
    pv.type,
    pv.sku,
    pv.base_price as usd_price,
    convert_currency(pv.base_price, 'USD', 'LAK') as lak_price,
    convert_currency(pv.base_price, 'USD', 'THB') as thb_price,
    convert_currency(pv.base_price, 'USD', 'EUR') as eur_price,
    format_currency(pv.base_price, 'USD') as usd_formatted,
    format_currency(convert_currency(pv.base_price, 'USD', 'LAK'), 'LAK') as lak_formatted,
    format_currency(convert_currency(pv.base_price, 'USD', 'THB'), 'THB') as thb_formatted,
    format_currency(convert_currency(pv.base_price, 'USD', 'EUR'), 'EUR') as eur_formatted
FROM product_variations pv
JOIN products p ON pv.product_id = p.product_id
WHERE pv.is_available = true;

-- =================================================================
-- PERFORMANCE OPTIMIZATION FOR POS SYSTEM
-- =================================================================

-- Critical Missing Foreign Key Constraints
ALTER TABLE products ADD CONSTRAINT fk_products_category 
    FOREIGN KEY (category_id) REFERENCES categories(category_id);

ALTER TABLE orders ADD CONSTRAINT fk_orders_customer 
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

ALTER TABLE inventory_transactions ADD CONSTRAINT fk_inventory_related_order
    FOREIGN KEY (related_order_id) REFERENCES orders(order_id);

ALTER TABLE inventory_transactions ADD CONSTRAINT fk_inventory_employee
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id);

-- =================================================================
-- COMPREHENSIVE INDEXING STRATEGY (with conflict prevention)
-- =================================================================

-- Core Business Logic Indexes
-- Products and Variations
DO $$ BEGIN
    CREATE INDEX idx_products_category_active ON products(category_id, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_products_name_search ON products USING gin(to_tsvector('english', name));
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_product_variations_product_available ON product_variations(product_id, is_available);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_product_variations_sku_lookup ON product_variations(sku) WHERE sku IS NOT NULL;
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_product_variations_size_type ON product_variations(size, type);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- Orders - Critical for POS Performance
DO $$ BEGIN
    CREATE INDEX idx_orders_time_status ON orders(order_time DESC, status);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_employee_time ON orders(employee_id, order_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_customer_time ON orders(customer_id, order_time DESC) WHERE customer_id IS NOT NULL;
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_status_time ON orders(status, order_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_date_only ON orders(DATE(order_time));
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_number_lookup ON orders(order_number);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_orders_currency_time ON orders(currency_code, order_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- Order Items - For Cart/Receipt Operations
DO $$ BEGIN
    CREATE INDEX idx_order_items_order_variation ON order_items(order_id, variation_id);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_order_items_variation_quantity ON order_items(variation_id, quantity);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- Payments - For Financial Reporting
DO $$ BEGIN
    CREATE INDEX idx_order_payments_order_method ON order_payments(order_id, method_id);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_order_payments_time_status ON order_payments(payment_time DESC, status);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_order_payments_method_time ON order_payments(method_id, payment_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_order_payments_currency_time ON order_payments(currency_code, payment_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_order_payments_status_time ON order_payments(status, payment_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- Inventory Management
DO $$ BEGIN
    CREATE INDEX idx_ingredients_stock_alert ON ingredients(current_stock, reorder_level) 
        WHERE reorder_level IS NOT NULL;
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_ingredients_name_search ON ingredients USING gin(to_tsvector('english', name));
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_inventory_transactions_ingredient_time ON inventory_transactions(ingredient_id, transaction_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_inventory_transactions_type_time ON inventory_transactions(transaction_type, transaction_time DESC);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_inventory_transactions_order_lookup ON inventory_transactions(related_order_id) 
        WHERE related_order_id IS NOT NULL;
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_inventory_transactions_employee_time ON inventory_transactions(employee_id, transaction_time DESC)
        WHERE employee_id IS NOT NULL;
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- Recipe Lookups
DO $$ BEGIN CREATE INDEX idx_recipes_variation_ingredient ON recipes(variation_id, ingredient_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_recipes_ingredient_variation ON recipes(ingredient_id, variation_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Customer Management
DO $$ BEGIN CREATE INDEX idx_customers_phone_lookup ON customers(phone) WHERE phone IS NOT NULL; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_customers_email_lookup ON customers(email) WHERE email IS NOT NULL; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_customers_loyalty_points ON customers(loyalty_points DESC) WHERE loyalty_points > 0; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_customers_last_visit ON customers(last_visit DESC) WHERE last_visit IS NOT NULL; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Employee Operations
DO $$ BEGIN CREATE INDEX idx_employees_pin_lookup ON employees(pin); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employees_role_active ON employees(role_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Payment Methods
DO $$ BEGIN CREATE INDEX idx_payment_methods_active ON payment_methods(is_active, name); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Multi-Currency Specific Indexes
DO $$ BEGIN CREATE INDEX idx_exchange_rates_lookup ON exchange_rates(from_currency, to_currency, effective_date DESC); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_exchange_rates_active_latest ON exchange_rates(is_active, effective_date DESC) WHERE is_active = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_currencies_code_active ON currencies(code, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- PARTIAL INDEXES FOR BETTER PERFORMANCE (with conflict prevention)
-- =================================================================

-- Only index active/available items
DO $$ BEGIN CREATE INDEX idx_products_active_only ON products(category_id, name) WHERE is_active = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_product_variations_available_only ON product_variations(product_id, base_price) WHERE is_available = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employees_active_only ON employees(role_id, name) WHERE is_active = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Only index recent orders (last 1 year)
DO $$ BEGIN CREATE INDEX idx_orders_recent ON orders(order_time DESC, status) WHERE order_time >= CURRENT_DATE - INTERVAL '1 year'; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Only index completed payments
DO $$ BEGIN CREATE INDEX idx_payments_completed ON order_payments(payment_time DESC, currency_code) WHERE status = 'completed'; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- COMPOSITE INDEXES FOR COMMON QUERIES (with conflict prevention)
-- =================================================================

-- Daily sales reporting
DO $$ BEGIN CREATE INDEX idx_daily_sales ON orders(DATE(order_time), status, currency_code, total_amount); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Employee performance tracking
DO $$ BEGIN CREATE INDEX idx_employee_performance ON orders(employee_id, DATE(order_time), status, total_amount); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Popular products analysis
DO $$ BEGIN CREATE INDEX idx_product_popularity ON order_items(variation_id, quantity, display_unit_price); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Inventory usage tracking
DO $$ BEGIN CREATE INDEX idx_inventory_usage ON inventory_transactions(ingredient_id, transaction_type, transaction_time, change); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Customer loyalty analysis
DO $$ BEGIN CREATE INDEX idx_customer_loyalty ON orders(customer_id, status, order_time, total_amount) WHERE customer_id IS NOT NULL; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- MISSING CRITICAL INDEXES FOR POS PERFORMANCE
-- =================================================================

-- Branch-related indexes (MISSING - Critical for multi-branch)
DO $$ BEGIN CREATE INDEX idx_orders_branch_time ON orders(branch_id, order_time DESC); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_orders_branch_status ON orders(branch_id, status, order_time DESC); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_inventory_transactions_branch_time ON inventory_transactions(branch_id, transaction_time DESC); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employees_branch_active ON employees(branch_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_employee_branches_active ON employee_branches(branch_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Variant system indexes (MISSING - Critical for product variations)
DO $$ BEGIN CREATE INDEX idx_variation_options_variation ON variation_options(variation_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_variation_options_option ON variation_options(option_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_variant_options_template ON variant_options(template_id, display_order); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_variant_templates_active ON variant_templates(is_active, name); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Product pricing indexes (CRITICAL for menu display)
DO $$ BEGIN CREATE INDEX idx_product_variations_price_range ON product_variations(price, is_available) WHERE is_available = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_products_category_price ON products(category_id, base_price, is_active) WHERE is_active = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Real-time inventory tracking (CRITICAL for stock management)
DO $$ BEGIN CREATE INDEX idx_recipes_bulk_lookup ON recipes(ingredient_id, quantity); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_ingredients_supplier_stock ON ingredients(supplier, current_stock, reorder_level); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Order processing optimization (CRITICAL for POS speed)
DO $$ BEGIN CREATE INDEX idx_order_items_modifiers ON order_items USING gin(modifiers); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_orders_employee_branch ON orders(employee_id, branch_id, order_time DESC); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Permission system performance (Important for security checks)
DO $$ BEGIN CREATE INDEX idx_employee_roles_active ON employee_roles(employee_id, is_active); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_role_permissions_lookup ON role_permissions(role_id, permission_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_permissions_code_lookup ON permissions(code, is_active) WHERE is_active = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Financial reporting optimization
DO $$ BEGIN CREATE INDEX idx_orders_branch_currency_date ON orders(branch_id, currency_code, DATE(order_time), status) WHERE status = 'paid'; EXCEPTION WHEN duplicate_table THEN NULL; END $$;
DO $$ BEGIN CREATE INDEX idx_order_payments_branch_time ON order_payments(order_id, payment_time DESC, status) WHERE status = 'completed'; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- REDUNDANCY ANALYSIS & OPTIMIZATION NOTES
-- =================================================================

-- REDUNDANT INDEXES IDENTIFIED:
-- 1. idx_orders_time_status vs idx_orders_recent - Consider dropping idx_orders_time_status
-- 2. idx_orders_status_time has similar coverage to idx_orders_time_status
-- 3. Multiple payment time indexes could be consolidated

-- MISSING COMPOSITE INDEXES FOR COMMON POS QUERIES:
-- These indexes support the most frequent POS operations

-- Menu loading with branch context
DO $$ BEGIN CREATE INDEX idx_menu_display ON product_variations(product_id, branch_id, is_available, price) WHERE is_available = true; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Order completion workflow
DO $$ BEGIN CREATE INDEX idx_order_completion ON orders(status, order_time DESC, branch_id, total_amount) WHERE status IN ('open', 'paid'); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Inventory depletion tracking
DO $$ BEGIN CREATE INDEX idx_inventory_depletion ON inventory_transactions(ingredient_id, branch_id, transaction_type, transaction_time DESC) WHERE transaction_type = 'sale'; EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- =================================================================
-- INDEX USAGE MONITORING QUERIES (Commented for reference)
-- =================================================================

/*
-- Monitor index usage efficiency
SELECT 
    schemaname, tablename, indexname, 
    idx_scan, idx_tup_read, idx_tup_fetch,
    idx_tup_read::float / NULLIF(idx_scan, 0) as avg_tuples_per_scan
FROM pg_stat_user_indexes 
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Find unused indexes
SELECT schemaname, tablename, indexname
FROM pg_stat_user_indexes 
WHERE idx_scan = 0 AND indexname NOT LIKE '%_pkey%'
ORDER BY schemaname, tablename;

-- Check for duplicate/overlapping indexes
SELECT 
    t.schemaname, t.tablename, 
    i1.indexname as index1, i2.indexname as index2,
    i1.indexdef, i2.indexdef
FROM pg_indexes i1
JOIN pg_indexes i2 ON i1.tablename = i2.tablename 
    AND i1.indexname < i2.indexname
JOIN pg_tables t ON i1.tablename = t.tablename
WHERE t.schemaname = 'public'
    AND i1.indexdef SIMILAR TO i2.indexdef
ORDER BY t.tablename;
*/

-- Sugar Level Management System
-- Add sugar level options for coffee shop drinks

-- Sugar level enum type
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sugar_level') THEN
        CREATE TYPE sugar_level AS ENUM (
            'no_sugar',     -- 0% sugar
            'less_sugar',   -- 25% sugar
            'regular',      -- 50% sugar (default)
            'more_sugar',   -- 75% sugar
            'extra_sweet'   -- 100% sugar
        );
    END IF;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Function to validate sugar level in modifiers
CREATE OR REPLACE FUNCTION validate_sugar_level(modifiers_json JSONB)
RETURNS BOOLEAN AS $$
BEGIN
    -- If no sugar level specified, it's valid (defaults to regular)
    IF NOT modifiers_json ? 'sugar_level' THEN
        RETURN TRUE;
    END IF;
    
    -- Check if sugar level is valid
    RETURN modifiers_json->>'sugar_level' IN ('no_sugar', 'less_sugar', 'regular', 'more_sugar', 'extra_sweet');
END;
$$ LANGUAGE plpgsql;

-- Function to get sugar level description
CREATE OR REPLACE FUNCTION get_sugar_level_description(sugar_level_value TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN CASE sugar_level_value
        WHEN 'no_sugar' THEN 'No Sugar (0%)'
        WHEN 'less_sugar' THEN 'Less Sugar (25%)'
        WHEN 'regular' THEN 'Regular Sugar (50%)'
        WHEN 'more_sugar' THEN 'More Sugar (75%)'
        WHEN 'extra_sweet' THEN 'Extra Sweet (100%)'
        ELSE 'Regular Sugar (50%)'
    END;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate sugar-based price adjustment
CREATE OR REPLACE FUNCTION calculate_sugar_price_adjustment(
    base_price DECIMAL(10,2),
    sugar_level_value TEXT DEFAULT 'regular'
)
RETURNS DECIMAL(10,2) AS $$
DECLARE
    adjustment_factor DECIMAL(4,3) := 1.000;
BEGIN
    -- Different sugar levels may have different costs
    adjustment_factor := CASE sugar_level_value
        WHEN 'no_sugar' THEN 0.950      -- 5% discount for no sugar
        WHEN 'less_sugar' THEN 0.975    -- 2.5% discount for less sugar
        WHEN 'regular' THEN 1.000       -- No adjustment
        WHEN 'more_sugar' THEN 1.025    -- 2.5% premium for more sugar
        WHEN 'extra_sweet' THEN 1.050   -- 5% premium for extra sweet
        ELSE 1.000
    END;
    
    RETURN ROUND(base_price * adjustment_factor, 2);
END;
$$ LANGUAGE plpgsql;

-- Function to format order item with sugar level
CREATE OR REPLACE FUNCTION format_order_item_with_sugar(
    product_name TEXT,
    variation_name TEXT,
    modifiers_json JSONB
)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
    sugar_level_text TEXT;
BEGIN
    result := product_name;
    
    IF variation_name IS NOT NULL AND variation_name != '' THEN
        result := result || ' (' || variation_name || ')';
    END IF;
    
    -- Add sugar level information
    IF modifiers_json ? 'sugar_level' THEN
        sugar_level_text := get_sugar_level_description(modifiers_json->>'sugar_level');
        result := result || ' - ' || sugar_level_text;
    ELSE
        result := result || ' - Regular Sugar (50%)';
    END IF;
    
    -- Add other modifiers
    IF modifiers_json ? 'whipped_cream' AND (modifiers_json->>'whipped_cream')::boolean THEN
        result := result || ' + Whipped Cream';
    END IF;
    
    IF modifiers_json ? 'extra_shot' AND (modifiers_json->>'extra_shot')::boolean THEN
        result := result || ' + Extra Shot';
    END IF;
    
    IF modifiers_json ? 'oat_milk' AND (modifiers_json->>'oat_milk')::boolean THEN
        result := result || ' + Oat Milk';
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Sugar Level Analysis Views
CREATE OR REPLACE VIEW sugar_level_preferences AS
SELECT 
    COALESCE(oi.modifiers->>'sugar_level', 'regular') as sugar_level,
    get_sugar_level_description(COALESCE(oi.modifiers->>'sugar_level', 'regular')) as sugar_description,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage,
    AVG(oi.display_unit_price) as avg_price
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'completed'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
    AND oi.modifiers IS NOT NULL
GROUP BY COALESCE(oi.modifiers->>'sugar_level', 'regular')
ORDER BY order_count DESC;

-- Order Items with Sugar Level Details
CREATE OR REPLACE VIEW order_items_with_sugar AS
SELECT 
    oi.order_item_id,
    oi.order_id,
    o.order_time,
    p.name as product_name,
    pv.size as variation_size,
    pv.type as variation_type,
    oi.quantity,
    COALESCE(oi.modifiers->>'sugar_level', 'regular') as sugar_level,
    get_sugar_level_description(COALESCE(oi.modifiers->>'sugar_level', 'regular')) as sugar_description,
    oi.base_unit_price,
    oi.display_unit_price,
    calculate_sugar_price_adjustment(oi.base_unit_price, COALESCE(oi.modifiers->>'sugar_level', 'regular')) as suggested_price,
    format_order_item_with_sugar(p.name, CONCAT(pv.size, ' ', pv.type), oi.modifiers) as formatted_item,
    o.currency_code,
    oi.modifiers
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN product_variations pv ON oi.variation_id = pv.variation_id
JOIN products p ON pv.product_id = p.product_id
ORDER BY o.order_time DESC;

-- Daily Sugar Level Trends
CREATE OR REPLACE VIEW daily_sugar_trends AS
SELECT 
    DATE(o.order_time) as order_date,
    COALESCE(oi.modifiers->>'sugar_level', 'regular') as sugar_level,
    get_sugar_level_description(COALESCE(oi.modifiers->>'sugar_level', 'regular')) as sugar_description,
    COUNT(*) as order_count,
    SUM(oi.quantity) as total_quantity,
    AVG(oi.display_unit_price) as avg_price
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'completed'
    AND o.order_time >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(o.order_time), COALESCE(oi.modifiers->>'sugar_level', 'regular')
ORDER BY order_date DESC, order_count DESC;

-- =================================================================
-- SAMPLE DATA WITH SUGAR LEVEL EXAMPLES
-- =================================================================

-- Sample categories
INSERT INTO categories (name, display_order) VALUES
('Coffee', 1),
('Tea', 2),
('Pastries', 3),
('Sandwiches', 4),
('Cold Drinks', 5)
ON CONFLICT (name) DO NOTHING;

-- Sample products
INSERT INTO products (name, description, category_id, is_active) VALUES
('Latte', 'Rich espresso with steamed milk', 1, true),
('Cappuccino', 'Espresso with steamed milk foam', 1, true),
('Americano', 'Espresso with hot water', 1, true),
('Green Tea', 'Fresh green tea leaves', 2, true),
('Croissant', 'Buttery, flaky pastry', 3, true),
('Iced Coffee', 'Cold brew coffee served over ice', 5, true)
ON CONFLICT DO NOTHING;

-- Sample product variations
INSERT INTO product_variations (product_id, size, type, base_price, cost, sku, is_available) VALUES
-- Latte variations
(1, 'small', 'hot', 4.50, 1.20, 'LAT-SM-HOT', true),
(1, 'medium', 'hot', 5.50, 1.50, 'LAT-MD-HOT', true),
(1, 'large', 'hot', 6.50, 1.80, 'LAT-LG-HOT', true),
(1, 'small', 'ice', 4.75, 1.25, 'LAT-SM-ICE', true),
-- Cappuccino variations
(2, 'small', 'hot', 4.25, 1.10, 'CAP-SM-HOT', true),
(2, 'medium', 'hot', 5.25, 1.40, 'CAP-MD-HOT', true),
-- Americano variations
(3, 'small', 'hot', 3.50, 0.80, 'AME-SM-HOT', true),
(3, 'medium', 'hot', 4.00, 0.90, 'AME-MD-HOT', true),
-- Tea variations
(4, 'small', 'hot', 3.00, 0.50, 'GRT-SM-HOT', true),
-- Pastries (no size/type variations)
(5, 'medium', 'none', 3.50, 1.00, 'CRO-MD-NONE', true),
-- Iced Coffee
(6, 'medium', 'ice', 4.50, 1.20, 'ICE-MD-ICE', true),
(6, 'large', 'ice', 5.50, 1.50, 'ICE-LG-ICE', true)
ON CONFLICT (sku) DO NOTHING;

-- Sample employees
INSERT INTO employees (name, pin, role, is_active) VALUES
('Alice Manager', '123456', 'manager', true),
('Bob Barista', '234567', 'barista', true),
('Carol Cashier', '345678', 'cashier', true)
ON CONFLICT (pin) DO NOTHING;

-- Sample customers
INSERT INTO customers (phone, name, email, loyalty_points, last_visit) VALUES
('+1-555-0101', 'John Coffee Lover', 'john@email.com', 150, CURRENT_DATE - INTERVAL '1 day'),
('+1-555-0102', 'Jane Sweet Tooth', 'jane@email.com', 230, CURRENT_DATE - INTERVAL '2 days'),
('+1-555-0103', 'Mike Health Conscious', 'mike@email.com', 75, CURRENT_DATE - INTERVAL '3 days')
ON CONFLICT (phone) DO NOTHING;

-- Sample payment methods
INSERT INTO payment_methods (name, processor, requires_terminal, is_active) VALUES
('Cash', NULL, false, true),
('Credit Card', 'Stripe', true, true),
('Debit Card', 'Square', true, true),
('Mobile Payment', 'Apple Pay', true, true)
ON CONFLICT (name) DO NOTHING;

-- Sample orders with various sugar levels
INSERT INTO orders (
    order_number, employee_id, customer_id, order_time,
    currency_code, exchange_rate, subtotal, tax_rate, tax_amount, total_amount, base_total_amount, status
) VALUES
-- Order 1: Customer who likes no sugar
('SUGAR-TEST-001', 1, 1, CURRENT_TIMESTAMP - INTERVAL '2 hours',
 'USD', 1.0, 4.50, 8.5, 0.38, 4.88, 4.88, 'paid'),
-- Order 2: Customer who likes extra sweet
('SUGAR-TEST-002', 2, 2, CURRENT_TIMESTAMP - INTERVAL '1 hour',
 'USD', 1.0, 5.50, 8.5, 0.47, 5.97, 5.97, 'paid'),
-- Order 3: Health conscious customer
('SUGAR-TEST-003', 2, 3, CURRENT_TIMESTAMP - INTERVAL '30 minutes',
 'USD', 1.0, 3.50, 8.5, 0.30, 3.80, 3.80, 'paid'),
-- Order 4: Regular customer with mixed preferences
('SUGAR-TEST-004', 1, 1, CURRENT_TIMESTAMP - INTERVAL '10 minutes',
 'USD', 1.0, 10.00, 8.5, 0.85, 10.85, 10.85, 'paid')
ON CONFLICT (order_number) DO NOTHING;

-- Sample order items with different sugar levels
INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price, modifiers) VALUES
-- Order 1: No sugar preference
(1, 1, 1, 4.50, 4.50, '{"sugar_level": "no_sugar", "oat_milk": true}'),
-- Order 2: Extra sweet preference
(2, 2, 1, 5.50, 5.50, '{"sugar_level": "extra_sweet", "whipped_cream": true}'),
-- Order 3: Health conscious - Americano with no sugar
(3, 7, 1, 3.50, 3.50, '{"sugar_level": "no_sugar"}'),
-- Order 4: Mixed order with different sugar levels
(4, 3, 1, 6.50, 6.50, '{"sugar_level": "regular", "extra_shot": true}'), -- Large Latte
(4, 12, 1, 4.50, 4.50, '{"sugar_level": "less_sugar"}') -- Iced Coffee
ON CONFLICT DO NOTHING;

-- =================================================================
-- VARIANT SYSTEM HELPER FUNCTIONS
-- =================================================================

-- Function to get variation options for a product variation
CREATE OR REPLACE FUNCTION get_variation_options(p_variation_id INT)
RETURNS TABLE (
    template_name VARCHAR(50),
    option_value VARCHAR(50),
    option_display_name VARCHAR(100)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vt.name as template_name,
        vo.value as option_value,
        COALESCE(vo.display_name, vo.value) as option_display_name
    FROM variation_options vop
    JOIN variant_options vo ON vop.option_id = vo.option_id
    JOIN variant_templates vt ON vo.template_id = vt.template_id
    WHERE vop.variation_id = p_variation_id
    ORDER BY vt.name, vo.display_order;
END;
$$ LANGUAGE plpgsql;

-- Function to create a product variation with options
CREATE OR REPLACE FUNCTION create_product_variation(
    p_product_id INT,
    p_price DECIMAL(10,2),
    p_cost DECIMAL(10,2) DEFAULT NULL,
    p_sku VARCHAR(20) DEFAULT NULL,
    p_option_ids INT[] DEFAULT ARRAY[]::INT[]
)
RETURNS INT AS $$
DECLARE
    new_variation_id INT;
    option_id INT;
BEGIN
    -- Insert the product variation
    INSERT INTO product_variations (product_id, price, cost, sku, is_available)
    VALUES (p_product_id, p_price, p_cost, p_sku, TRUE)
    RETURNING variation_id INTO new_variation_id;
    
    -- Link the variation to options
    IF array_length(p_option_ids, 1) > 0 THEN
        FOREACH option_id IN ARRAY p_option_ids
        LOOP
            INSERT INTO variation_options (variation_id, option_id)
            VALUES (new_variation_id, option_id);
        END LOOP;
    END IF;
    
    RETURN new_variation_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get product display name with variation options
CREATE OR REPLACE FUNCTION get_variation_display_name(
    p_product_name TEXT,
    p_variation_id INT
)
RETURNS TEXT AS $$
DECLARE
    variation_options_text TEXT := '';
    option_text TEXT;
BEGIN
    -- Get all options for this variation
    FOR option_text IN
        SELECT COALESCE(vo.display_name, vo.value)
        FROM variation_options vop
        JOIN variant_options vo ON vop.option_id = vo.option_id
        JOIN variant_templates vt ON vo.template_id = vt.template_id
        WHERE vop.variation_id = p_variation_id
        ORDER BY vt.name, vo.display_order
    LOOP
        IF variation_options_text = '' THEN
            variation_options_text := option_text;
        ELSE
            variation_options_text := variation_options_text || ', ' || option_text;
        END IF;
    END LOOP;
    
    -- Return formatted name
    IF variation_options_text = '' THEN
        RETURN p_product_name;
    ELSE
        RETURN p_product_name || ' (' || variation_options_text || ')';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- VARIANT SYSTEM SAMPLE DATA
-- =================================================================

-- Sample product with variants
INSERT INTO products (name, description, category_id, has_variants, base_price, is_active) VALUES
('Latte', 'Rich espresso with steamed milk', 1, true, 4.50, true)
ON CONFLICT (name) DO NOTHING;

-- Sample product variations with options
INSERT INTO product_variations (product_id, price, cost, sku, is_available) VALUES
-- Latte variations
(1, 4.50, 1.20, 'LAT-SM-HOT', true),
(1, 5.50, 1.50, 'LAT-MD-HOT', true),
(1, 6.50, 1.80, 'LAT-LG-HOT', true),
(1, 4.75, 1.25, 'LAT-SM-ICE', true),
(1, 5.75, 1.55, 'LAT-MD-ICE', true),
(1, 6.75, 1.85, 'LAT-LG-ICE', true)
ON CONFLICT (sku) DO NOTHING;

-- Link variations to size options
INSERT INTO variation_options (variation_id, option_id) VALUES
-- Hot variations
(1, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
-- Iced variations
(4, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to temperature options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to milk type options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to strength options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- =================================================================
-- VARIANT SYSTEM HELPER FUNCTIONS
-- =================================================================

-- Function to get variation options for a product variation
CREATE OR REPLACE FUNCTION get_variation_options(p_variation_id INT)
RETURNS TABLE (
    template_name VARCHAR(50),
    option_value VARCHAR(50),
    option_display_name VARCHAR(100)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vt.name as template_name,
        vo.value as option_value,
        COALESCE(vo.display_name, vo.value) as option_display_name
    FROM variation_options vop
    JOIN variant_options vo ON vop.option_id = vo.option_id
    JOIN variant_templates vt ON vo.template_id = vt.template_id
    WHERE vop.variation_id = p_variation_id
    ORDER BY vt.name, vo.display_order;
END;
$$ LANGUAGE plpgsql;

-- Function to create a product variation with options
CREATE OR REPLACE FUNCTION create_product_variation(
    p_product_id INT,
    p_price DECIMAL(10,2),
    p_cost DECIMAL(10,2) DEFAULT NULL,
    p_sku VARCHAR(20) DEFAULT NULL,
    p_option_ids INT[] DEFAULT ARRAY[]::INT[]
)
RETURNS INT AS $$
DECLARE
    new_variation_id INT;
    option_id INT;
BEGIN
    -- Insert the product variation
    INSERT INTO product_variations (product_id, price, cost, sku, is_available)
    VALUES (p_product_id, p_price, p_cost, p_sku, TRUE)
    RETURNING variation_id INTO new_variation_id;
    
    -- Link the variation to options
    IF array_length(p_option_ids, 1) > 0 THEN
        FOREACH option_id IN ARRAY p_option_ids
        LOOP
            INSERT INTO variation_options (variation_id, option_id)
            VALUES (new_variation_id, option_id);
        END LOOP;
    END IF;
    
    RETURN new_variation_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get product display name with variation options
CREATE OR REPLACE FUNCTION get_variation_display_name(
    p_product_name TEXT,
    p_variation_id INT
)
RETURNS TEXT AS $$
DECLARE
    variation_options_text TEXT := '';
    option_text TEXT;
BEGIN
    -- Get all options for this variation
    FOR option_text IN
        SELECT COALESCE(vo.display_name, vo.value)
        FROM variation_options vop
        JOIN variant_options vo ON vop.option_id = vo.option_id
        JOIN variant_templates vt ON vo.template_id = vt.template_id
        WHERE vop.variation_id = p_variation_id
        ORDER BY vt.name, vo.display_order
    LOOP
        IF variation_options_text = '' THEN
            variation_options_text := option_text;
        ELSE
            variation_options_text := variation_options_text || ', ' || option_text;
        END IF;
    END LOOP;
    
    -- Return formatted name
    IF variation_options_text = '' THEN
        RETURN p_product_name;
    ELSE
        RETURN p_product_name || ' (' || variation_options_text || ')';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- VARIANT SYSTEM SAMPLE DATA
-- =================================================================

-- Sample product with variants
INSERT INTO products (name, description, category_id, has_variants, base_price, is_active) VALUES
('Latte', 'Rich espresso with steamed milk', 1, true, 4.50, true)
ON CONFLICT (name) DO NOTHING;

-- Sample product variations with options
INSERT INTO product_variations (product_id, price, cost, sku, is_available) VALUES
-- Latte variations
(1, 4.50, 1.20, 'LAT-SM-HOT', true),
(1, 5.50, 1.50, 'LAT-MD-HOT', true),
(1, 6.50, 1.80, 'LAT-LG-HOT', true),
(1, 4.75, 1.25, 'LAT-SM-ICE', true),
(1, 5.75, 1.55, 'LAT-MD-ICE', true),
(1, 6.75, 1.85, 'LAT-LG-ICE', true)
ON CONFLICT (sku) DO NOTHING;

-- Link variations to size options
INSERT INTO variation_options (variation_id, option_id) VALUES
-- Hot variations
(1, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
-- Iced variations
(4, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to temperature options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to milk type options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to strength options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- =================================================================
-- VARIANT SYSTEM HELPER FUNCTIONS
-- =================================================================

-- Function to get variation options for a product variation
CREATE OR REPLACE FUNCTION get_variation_options(p_variation_id INT)
RETURNS TABLE (
    template_name VARCHAR(50),
    option_value VARCHAR(50),
    option_display_name VARCHAR(100)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vt.name as template_name,
        vo.value as option_value,
        COALESCE(vo.display_name, vo.value) as option_display_name
    FROM variation_options vop
    JOIN variant_options vo ON vop.option_id = vo.option_id
    JOIN variant_templates vt ON vo.template_id = vt.template_id
    WHERE vop.variation_id = p_variation_id
    ORDER BY vt.name, vo.display_order;
END;
$$ LANGUAGE plpgsql;

-- Function to create a product variation with options
CREATE OR REPLACE FUNCTION create_product_variation(
    p_product_id INT,
    p_price DECIMAL(10,2),
    p_cost DECIMAL(10,2) DEFAULT NULL,
    p_sku VARCHAR(20) DEFAULT NULL,
    p_option_ids INT[] DEFAULT ARRAY[]::INT[]
)
RETURNS INT AS $$
DECLARE
    new_variation_id INT;
    option_id INT;
BEGIN
    -- Insert the product variation
    INSERT INTO product_variations (product_id, price, cost, sku, is_available)
    VALUES (p_product_id, p_price, p_cost, p_sku, TRUE)
    RETURNING variation_id INTO new_variation_id;
    
    -- Link the variation to options
    IF array_length(p_option_ids, 1) > 0 THEN
        FOREACH option_id IN ARRAY p_option_ids
        LOOP
            INSERT INTO variation_options (variation_id, option_id)
            VALUES (new_variation_id, option_id);
               END LOOP;
    END IF;
    
    RETURN new_variation_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get product display name with variation options
CREATE OR REPLACE FUNCTION get_variation_display_name(
    p_product_name TEXT,
    p_variation_id INT
)
RETURNS TEXT AS $$
DECLARE
    variation_options_text TEXT := '';
    option_text TEXT;
BEGIN
    -- Get all options for this variation
    FOR option_text IN
        SELECT COALESCE(vo.display_name, vo.value)
        FROM variation_options vop
        JOIN variant_options vo ON vop.option_id = vo.option_id
        JOIN variant_templates vt ON vo.template_id = vt.template_id
        WHERE vop.variation_id = p_variation_id
        ORDER BY vt.name, vo.display_order
    LOOP
        IF variation_options_text = '' THEN
            variation_options_text := option_text;
        ELSE
            variation_options_text := variation_options_text || ', ' || option_text;
        END IF;
    END LOOP;
    
    -- Return formatted name
    IF variation_options_text = '' THEN
        RETURN p_product_name;
    ELSE
        RETURN p_product_name || ' (' || variation_options_text || ')';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- VARIANT SYSTEM SAMPLE DATA
-- =================================================================

-- Sample product with variants
INSERT INTO products (name, description, category_id, has_variants, base_price, is_active) VALUES
('Latte', 'Rich espresso with steamed milk', 1, true, 4.50, true)
ON CONFLICT (name) DO NOTHING;

-- Sample product variations with options
INSERT INTO product_variations (product_id, price, cost, sku, is_available) VALUES
-- Latte variations
(1, 4.50, 1.20, 'LAT-SM-HOT', true),
(1, 5.50, 1.50, 'LAT-MD-HOT', true),
(1, 6.50, 1.80, 'LAT-LG-HOT', true),
(1, 4.75, 1.25, 'LAT-SM-ICE', true),
(1, 5.75, 1.55, 'LAT-MD-ICE', true),
(1, 6.75, 1.85, 'LAT-LG-ICE', true)
ON CONFLICT (sku) DO NOTHING;

-- Link variations to size options
INSERT INTO variation_options (variation_id, option_id) VALUES
-- Hot variations
(1, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
-- Iced variations
(4, (SELECT option_id FROM variant_options WHERE value = 'small' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'medium' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'large' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Size')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to temperature options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'hot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'iced' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Temperature')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to milk type options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'whole' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'skim' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'oat' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Milk Type')))
ON CONFLICT (variation_id, option_id) DO NOTHING;

-- Link variations to strength options
INSERT INTO variation_options (variation_id, option_id) VALUES
(1, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(2, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(3, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(4, (SELECT option_id FROM variant_options WHERE value = 'regular' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(5, (SELECT option_id FROM variant_options WHERE value = 'extra_shot' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength'))),
(6, (SELECT option_id FROM variant_options WHERE value = 'decaf' AND template_id = (SELECT template_id FROM variant_templates WHERE name = 'Strength')))
ON CONFLICT (variation_id, option_id) DO NOTHING;