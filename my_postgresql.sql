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

-- 3. Table: employees
CREATE TABLE IF NOT EXISTS employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    pin CHAR(6) NOT NULL UNIQUE,         -- 6-digit PIN for login
    role_id INT,                         -- References roles table
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

-- 4. Table: customers
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    phone VARCHAR(20) UNIQUE,            
    name VARCHAR(100),
    email VARCHAR(100),
    loyalty_points INT DEFAULT 0,
    visit_count INT DEFAULT 0,
    last_visit DATE
);

-- 5. Table: payment_methods
CREATE TABLE IF NOT EXISTS payment_methods (
    method_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,   -- e.g., "Cash", "Credit Card"
    processor VARCHAR(50),              -- e.g., "Stripe", "Square"
    requires_terminal BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE
);

-- 6. Table: products
CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- e.g., "Latte", "Croissant"
    description TEXT,
    category_id INT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- 7. Table: product_variations
CREATE TABLE IF NOT EXISTS product_variations (
    variation_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    size product_size NOT NULL,
    type product_type DEFAULT 'none',
    base_price DECIMAL(10,2) NOT NULL,  -- Price in base currency (USD)
    cost DECIMAL(10,2),                 -- Production cost in base currency
    sku VARCHAR(20) UNIQUE,             -- e.g., "LAT-M-ICE"
    is_available BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Transaction Tables (Enhanced)
-- 8. Table: orders
CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(20) NOT NULL UNIQUE, -- "CAFE-2025-1001"
    employee_id INT NOT NULL,            
    customer_id INT,                     -- Loyalty program link
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
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- 9. Table: order_payments
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

-- 10. Table: order_items
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
-- 11. Table: ingredients
CREATE TABLE IF NOT EXISTS ingredients (
    ingredient_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,  -- e.g., "Coffee Beans", "Oat Milk"
    unit VARCHAR(20) NOT NULL,          -- e.g., "kg", "L"
    current_stock DECIMAL(10,2) DEFAULT 0.0,
    reorder_level DECIMAL(10,2),
    supplier VARCHAR(100)
);

-- 12. Table: recipes
CREATE TABLE IF NOT EXISTS recipes (
    recipe_id SERIAL PRIMARY KEY,
    variation_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    quantity DECIMAL(8,4) NOT NULL,      -- e.g., 0.03 (kg per item)
    FOREIGN KEY (variation_id) REFERENCES product_variations(variation_id),
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id),
    UNIQUE (variation_id, ingredient_id)
);

-- 13. Table: inventory_transactions
CREATE TABLE IF NOT EXISTS inventory_transactions (
    transaction_id SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL,
    change DECIMAL(10,2) NOT NULL,       -- +ve = add, -ve = deduct
    transaction_type transaction_type,
    related_order_id INT,                -- For sales deductions
    employee_id INT,                     -- Who performed
    transaction_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(ingredient_id)
);

-- Multi-Currency Support Tables
-- 14. Table: currencies
CREATE TABLE IF NOT EXISTS currencies (
    currency_id SERIAL PRIMARY KEY,
    code CHAR(3) NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{3}$'),
    name VARCHAR(50) NOT NULL,          -- e.g., "US Dollar", "Lao Kip", "Thai Baht"
    symbol VARCHAR(10) NOT NULL,        -- e.g., "$", "₭", "฿", "€", "¥", "£"
    decimal_places SMALLINT DEFAULT 2,  -- e.g., 2 for USD, 0 for LAK
    is_base_currency BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE
);

-- 15. Table: exchange_rates
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

-- 16. Table: exchange_rate_history
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

-- 17. Table: permission_groups
CREATE TABLE IF NOT EXISTS permission_groups (
    group_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,   -- e.g., "Admin", "Staff"
    description TEXT
);

-- 18. Table: permissions
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

-- 19. Table: role_permissions
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

-- 20. Table: employee_roles (Many-to-Many: Employee to Role)
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
-- PERFORMANCE VIEWS FOR COMMON OPERATIONS (with conflict prevention)
-- =================================================================

-- Daily Sales Summary (Optimized)
DROP MATERIALIZED VIEW IF EXISTS daily_sales_summary CASCADE;
CREATE MATERIALIZED VIEW daily_sales_summary AS
SELECT 
    DATE(o.order_time) as sale_date,
    o.currency_code,
    COUNT(*) as order_count,
    SUM(o.total_amount) as total_revenue,
    SUM(o.base_total_amount) as total_revenue_usd,
    AVG(o.total_amount) as avg_order_value,
    SUM(o.tax_amount) as total_tax
FROM orders o
WHERE o.status = 'paid' 
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(o.order_time), o.currency_code;

DO $$ BEGIN CREATE UNIQUE INDEX idx_daily_sales_summary ON daily_sales_summary(sale_date, currency_code); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Popular Products View (Optimized)
DROP MATERIALIZED VIEW IF EXISTS popular_products_summary CASCADE;
CREATE MATERIALIZED VIEW popular_products_summary AS
SELECT 
    pv.variation_id,
    p.name as product_name,
    pv.size,
    pv.type,
    pv.sku,
    COUNT(oi.order_item_id) as order_count,
    SUM(oi.quantity) as total_quantity_sold,
    SUM(oi.quantity * oi.base_unit_price) as total_revenue_usd,
    AVG(oi.display_unit_price) as avg_selling_price
FROM order_items oi
JOIN product_variations pv ON oi.variation_id = pv.variation_id
JOIN products p ON pv.product_id = p.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY pv.variation_id, p.name, pv.size, pv.type, pv.sku;

DO $$ BEGIN CREATE UNIQUE INDEX idx_popular_products_summary ON popular_products_summary(variation_id); EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- Low Stock Alert View
CREATE OR REPLACE VIEW low_stock_alert AS
SELECT 
    i.ingredient_id,
    i.name,
    i.current_stock,
    i.reorder_level,
    i.unit,
    (i.current_stock - i.reorder_level) as stock_difference,
    CASE 
        WHEN i.current_stock <= 0 THEN 'OUT_OF_STOCK'
        WHEN i.current_stock <= i.reorder_level * 0.5 THEN 'CRITICAL'
        WHEN i.current_stock <= i.reorder_level THEN 'LOW'
        ELSE 'OK'
    END as stock_status
FROM ingredients i
WHERE i.reorder_level IS NOT NULL
ORDER BY stock_difference ASC;

-- =================================================================
-- MAINTENANCE PROCEDURES
-- =================================================================

-- Refresh materialized views (run daily)
CREATE OR REPLACE FUNCTION refresh_performance_views() 
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales_summary;
    REFRESH MATERIALIZED VIEW CONCURRENTLY popular_products_summary;
END;
$$ LANGUAGE plpgsql;

-- Clean old data procedure
CREATE OR REPLACE FUNCTION cleanup_old_data(days_to_keep INT DEFAULT 365)
RETURNS void AS $$
BEGIN
    -- Archive old exchange rates (keep only last rate per currency pair)
    DELETE FROM exchange_rates 
    WHERE effective_date < CURRENT_DATE - INTERVAL '30 days'
    AND rate_id NOT IN (
        SELECT DISTINCT ON (from_currency, to_currency) rate_id
        FROM exchange_rates
        ORDER BY from_currency, to_currency, effective_date DESC
    );
    
    -- Clean old inventory transactions (keep 1 year)
    DELETE FROM inventory_transactions 
    WHERE transaction_time < CURRENT_DATE - (days_to_keep || ' days')::INTERVAL;
    
    RAISE NOTICE 'Cleanup completed for data older than % days', days_to_keep;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- PERFORMANCE MONITORING QUERIES
-- =================================================================

-- Check index usage
/*
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan
FROM pg_stat_user_indexes 
ORDER BY idx_scan DESC;
*/

-- Check slow queries
/*
SELECT 
    query,
    mean_exec_time,
    calls,
    total_exec_time
FROM pg_stat_statements 
ORDER BY mean_exec_time DESC 
LIMIT 10;
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

-- Sugar Level Usage Examples and Test Queries

-- Example 1: View sugar level preferences summary
-- SELECT * FROM sugar_level_preferences;

-- Example 2: View orders with sugar level details
-- SELECT * FROM order_items_with_sugar ORDER BY order_time DESC LIMIT 10;

-- Example 3: Check daily sugar trends
-- SELECT * FROM daily_sugar_trends WHERE order_date >= CURRENT_DATE - INTERVAL '7 days';

-- Example 4: Calculate price adjustments for different sugar levels
-- SELECT 
--     'no_sugar' as level,
--     calculate_sugar_price_adjustment(5.50, 'no_sugar') as adjusted_price,
--     (calculate_sugar_price_adjustment(5.50, 'no_sugar') - 5.50) as price_difference
-- UNION ALL
-- SELECT 
--     'extra_sweet' as level,
--     calculate_sugar_price_adjustment(5.50, 'extra_sweet') as adjusted_price,
--     (calculate_sugar_price_adjustment(5.50, 'extra_sweet') - 5.50) as price_difference;

-- Example 5: Format order items with sugar level descriptions
-- SELECT 
--     order_item_id,
--     format_order_item_with_sugar(
--         'Latte', 
--         'medium hot', 
--         '{"sugar_level": "extra_sweet", "whipped_cream": true}'::jsonb
--     ) as formatted_description;

-- Example 6: Test constraint validation
-- This should work:
-- INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price, modifiers) 
-- VALUES (1, 1, 1, 4.50, 4.50, '{"sugar_level": "regular"}');

-- This should fail due to constraint:
-- INSERT INTO order_items (order_id, variation_id, quantity, base_unit_price, display_unit_price, modifiers) 
-- VALUES (1, 1, 1, 4.50, 4.50, '{"sugar_level": "invalid_level"}');

-- =================================================================
-- PERMISSION SYSTEM HELPER FUNCTIONS
-- =================================================================

-- Function to check if an employee has a specific permission
CREATE OR REPLACE FUNCTION employee_has_permission(
    emp_id INT,
    permission_code VARCHAR(50)
) RETURNS BOOLEAN AS $$
DECLARE
    has_perm BOOLEAN := FALSE;
BEGIN
    SELECT EXISTS(
        SELECT 1 
        FROM employee_roles er
        JOIN role_permissions rp ON er.role_id = rp.role_id
        JOIN permissions p ON rp.permission_id = p.permission_id
        WHERE er.employee_id = emp_id 
          AND p.code = permission_code
          AND er.is_active = TRUE
          AND p.is_active = TRUE
    ) INTO has_perm;
    
    RETURN has_perm;
END;
$$ LANGUAGE plpgsql;

-- Function to get all permissions for an employee
CREATE OR REPLACE FUNCTION get_employee_permissions(emp_id INT)
RETURNS TABLE(
    permission_code VARCHAR(50),
    permission_name VARCHAR(100),
    permission_description TEXT,
    role_name VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        p.code,
        p.name,
        p.description,
        r.name as role_name
    FROM employee_roles er
    JOIN roles r ON er.role_id = r.role_id
    JOIN role_permissions rp ON r.role_id = rp.role_id
    JOIN permissions p ON rp.permission_id = p.permission_id
    WHERE er.employee_id = emp_id 
      AND er.is_active = TRUE
      AND r.is_active = TRUE
      AND p.is_active = TRUE
    ORDER BY r.name, p.code;
END;
$$ LANGUAGE plpgsql;

-- Function to get all roles for an employee
CREATE OR REPLACE FUNCTION get_employee_roles(emp_id INT)
RETURNS TABLE(
    role_id INT,
    role_name VARCHAR(50),
    role_description TEXT,
    assigned_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.role_id,
        r.name,
        r.description,
        er.assigned_at
    FROM employee_roles er
    JOIN roles r ON er.role_id = r.role_id
    WHERE er.employee_id = emp_id 
      AND er.is_active = TRUE
      AND r.is_active = TRUE
    ORDER BY er.assigned_at;
END;
$$ LANGUAGE plpgsql;

-- Function to assign role to employee
CREATE OR REPLACE FUNCTION assign_role_to_employee(
    emp_id INT,
    role_name VARCHAR(50),
    assigned_by_id INT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    target_role_id INT;
    existing_assignment BOOLEAN;
BEGIN
    -- Get role ID
    SELECT role_id INTO target_role_id 
    FROM roles 
    WHERE name = role_name AND is_active = TRUE;
    
    IF target_role_id IS NULL THEN
        RAISE EXCEPTION 'Role % not found or inactive', role_name;
    END IF;
    
    -- Check if assignment already exists
    SELECT EXISTS(
        SELECT 1 FROM employee_roles 
        WHERE employee_id = emp_id AND role_id = target_role_id
    ) INTO existing_assignment;
    
    IF existing_assignment THEN
        -- Reactivate if exists but inactive
        UPDATE employee_roles 
        SET is_active = TRUE, assigned_at = CURRENT_TIMESTAMP, assigned_by = assigned_by_id
        WHERE employee_id = emp_id AND role_id = target_role_id;
    ELSE
        -- Create new assignment
        INSERT INTO employee_roles (employee_id, role_id, assigned_by)
        VALUES (emp_id, target_role_id, assigned_by_id);
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to remove role from employee
CREATE OR REPLACE FUNCTION remove_role_from_employee(
    emp_id INT,
    role_name VARCHAR(50)
) RETURNS BOOLEAN AS $$
DECLARE
    target_role_id INT;
BEGIN
    -- Get role ID
    SELECT role_id INTO target_role_id 
    FROM roles 
    WHERE name = role_name;
    
    IF target_role_id IS NULL THEN
        RAISE EXCEPTION 'Role % not found', role_name;
    END IF;
    
    -- Deactivate the role assignment
    UPDATE employee_roles 
    SET is_active = FALSE 
    WHERE employee_id = emp_id AND role_id = target_role_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to validate order operation permission
CREATE OR REPLACE FUNCTION can_employee_perform_order_action(
    emp_id INT,
    action_type VARCHAR(20)  -- 'create', 'modify', 'cancel', 'refund'
) RETURNS BOOLEAN AS $$
DECLARE
    required_permission VARCHAR(50);
BEGIN
    CASE action_type
        WHEN 'create' THEN required_permission := 'CREATE_ORDER';
        WHEN 'modify' THEN required_permission := 'MODIFY_ORDER';
        WHEN 'cancel' THEN required_permission := 'CANCEL_ORDER';
        WHEN 'refund' THEN required_permission := 'PROCESS_REFUND';
        ELSE 
            RAISE EXCEPTION 'Invalid action type: %', action_type;
    END CASE;
    
    RETURN employee_has_permission(emp_id, required_permission);
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- PERMISSION SYSTEM INDEXES FOR PERFORMANCE
-- =================================================================

-- Indexes for permission tables (with conflict prevention)
DO $$ BEGIN
    CREATE INDEX idx_employee_roles_employee_active ON employee_roles(employee_id, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_employee_roles_role_active ON employee_roles(role_id, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_id);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_permissions_code_active ON permissions(code, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_permissions_group_active ON permissions(group_id, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE INDEX idx_roles_name_active ON roles(name, is_active);
EXCEPTION
    WHEN duplicate_table THEN NULL;
END $$;

-- =================================================================
-- PERMISSION SYSTEM SAMPLE DATA
-- =================================================================

-- Sample Permission Groups
INSERT INTO permission_groups (name, description) VALUES
('System Administration', 'Full system access and configuration'),
('Order Management', 'Create, modify, and process orders'),
('Inventory Management', 'Stock control and ingredient management'),
('Financial Operations', 'Payment processing and financial reports'),
('Staff Management', 'Employee and scheduling operations'),
('Reporting', 'Access to reports and analytics')
ON CONFLICT (name) DO NOTHING;

-- Sample Permissions
INSERT INTO permissions (code, name, description, group_id) VALUES
-- System Administration
('SYSTEM_ADMIN', 'System Administrator', 'Full system access', 
    (SELECT group_id FROM permission_groups WHERE name = 'System Administration')),
('MANAGE_USERS', 'Manage Users', 'Create and manage user accounts',
    (SELECT group_id FROM permission_groups WHERE name = 'System Administration')),
('SYSTEM_CONFIG', 'System Configuration', 'Modify system settings',
    (SELECT group_id FROM permission_groups WHERE name = 'System Administration')),

-- Order Management
('CREATE_ORDER', 'Create Order', 'Create new customer orders',
    (SELECT group_id FROM permission_groups WHERE name = 'Order Management')),
('MODIFY_ORDER', 'Modify Order', 'Edit existing orders',
    (SELECT group_id FROM permission_groups WHERE name = 'Order Management')),
('CANCEL_ORDER', 'Cancel Order', 'Cancel customer orders',
    (SELECT group_id FROM permission_groups WHERE name = 'Order Management')),
('PROCESS_REFUND', 'Process Refund', 'Process customer refunds',
    (SELECT group_id FROM permission_groups WHERE name = 'Order Management')),
('VIEW_ALL_ORDERS', 'View All Orders', 'Access to all order history',
    (SELECT group_id FROM permission_groups WHERE name = 'Order Management')),

-- Inventory Management
('MANAGE_INVENTORY', 'Manage Inventory', 'Add/remove inventory items',
    (SELECT group_id FROM permission_groups WHERE name = 'Inventory Management')),
('STOCK_ADJUSTMENT', 'Stock Adjustment', 'Adjust stock levels',
    (SELECT group_id FROM permission_groups WHERE name = 'Inventory Management')),
('VIEW_INVENTORY', 'View Inventory', 'View current inventory levels',
    (SELECT group_id FROM permission_groups WHERE name = 'Inventory Management')),

-- Financial Operations
('PROCESS_PAYMENT', 'Process Payment', 'Handle customer payments',
    (SELECT group_id FROM permission_groups WHERE name = 'Financial Operations')),
('VIEW_FINANCIAL_REPORTS', 'View Financial Reports', 'Access financial reports',
    (SELECT group_id FROM permission_groups WHERE name = 'Financial Operations')),
('CASH_MANAGEMENT', 'Cash Management', 'Handle cash drawer operations',
    (SELECT group_id FROM permission_groups WHERE name = 'Financial Operations')),

-- Staff Management
('MANAGE_STAFF', 'Manage Staff', 'Hire, fire, and manage employees',
    (SELECT group_id FROM permission_groups WHERE name = 'Staff Management')),
('VIEW_STAFF', 'View Staff', 'View employee information',
    (SELECT group_id FROM permission_groups WHERE name = 'Staff Management')),
('MANAGE_SCHEDULES', 'Manage Schedules', 'Create and modify work schedules',
    (SELECT group_id FROM permission_groups WHERE name = 'Staff Management')),

-- Reporting
('VIEW_REPORTS', 'View Reports', 'Access to standard reports',
    (SELECT group_id FROM permission_groups WHERE name = 'Reporting')),
('EXPORT_DATA', 'Export Data', 'Export data to external formats',
    (SELECT group_id FROM permission_groups WHERE name = 'Reporting'))
ON CONFLICT (code) DO NOTHING;

-- Sample Roles
INSERT INTO roles (name, description) VALUES
('Manager', 'Store manager with full operational access'),
('Supervisor', 'Shift supervisor with limited management access'),
('Barista', 'Coffee preparation and basic order processing'),
('Cashier', 'Order taking and payment processing'),
('Inventory Clerk', 'Stock management and inventory control'),
('Administrator', 'System administration and configuration')
ON CONFLICT (name) DO NOTHING;

-- Sample Role-Permission Assignments
-- Administrator Role (Full Access)
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Administrator'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Manager Role (Most Permissions)
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Manager' 
  AND p.code IN (
    'CREATE_ORDER', 'MODIFY_ORDER', 'CANCEL_ORDER', 'PROCESS_REFUND', 
    'VIEW_ALL_ORDERS', 'MANAGE_INVENTORY', 'STOCK_ADJUSTMENT', 'VIEW_INVENTORY',
    'PROCESS_PAYMENT', 'VIEW_FINANCIAL_REPORTS', 'CASH_MANAGEMENT',
    'VIEW_STAFF', 'MANAGE_SCHEDULES', 'VIEW_REPORTS', 'EXPORT_DATA'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Supervisor Role (Limited Management)
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Supervisor' 
  AND p.code IN (
    'CREATE_ORDER', 'MODIFY_ORDER', 'CANCEL_ORDER', 'VIEW_ALL_ORDERS',
    'VIEW_INVENTORY', 'PROCESS_PAYMENT', 'CASH_MANAGEMENT',
    'VIEW_STAFF', 'VIEW_REPORTS'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Barista Role (Order and Basic Operations)
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Barista' 
  AND p.code IN (
    'CREATE_ORDER', 'MODIFY_ORDER', 'VIEW_INVENTORY', 'PROCESS_PAYMENT'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Cashier Role (Orders and Payments)
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Cashier' 
  AND p.code IN (
    'CREATE_ORDER', 'PROCESS_PAYMENT', 'CASH_MANAGEMENT'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Inventory Clerk Role (Stock Management)  
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE r.name = 'Inventory Clerk' 
  AND p.code IN (
    'MANAGE_INVENTORY', 'STOCK_ADJUSTMENT', 'VIEW_INVENTORY', 'VIEW_REPORTS'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;