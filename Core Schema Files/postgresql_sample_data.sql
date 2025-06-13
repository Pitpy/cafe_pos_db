-- PostgreSQL Sample Data and Common Queries
-- This file provides sample data insertion and useful queries for the cafe POS system

-- Insert sample categories
INSERT INTO categories (name, display_order) VALUES
('Coffee', 1),
('Tea', 2),
('Pastries', 3),
('Sandwiches', 4),
('Desserts', 5);

-- Insert sample products
INSERT INTO products (name, description, category_id, is_active) VALUES
('Latte', 'Rich espresso with steamed milk', 1, true),
('Cappuccino', 'Espresso with steamed milk foam', 1, true),
('Green Tea', 'Fresh green tea leaves', 2, true),
('Croissant', 'Buttery, flaky pastry', 3, true),
('Club Sandwich', 'Triple-decker with turkey and bacon', 4, true);

-- Insert sample product variations
INSERT INTO product_variations (product_id, size, type, price, cost, sku, is_available) VALUES
-- Latte variations
(1, 'small', 'hot', 4.50, 1.20, 'LAT-SM-HOT', true),
(1, 'medium', 'hot', 5.50, 1.50, 'LAT-MD-HOT', true),
(1, 'large', 'hot', 6.50, 1.80, 'LAT-LG-HOT', true),
(1, 'small', 'ice', 4.75, 1.25, 'LAT-SM-ICE', true),
(1, 'medium', 'ice', 5.75, 1.55, 'LAT-MD-ICE', true),
(1, 'large', 'ice', 6.75, 1.85, 'LAT-LG-ICE', true),

-- Cappuccino variations
(2, 'small', 'hot', 4.25, 1.10, 'CAP-SM-HOT', true),
(2, 'medium', 'hot', 5.25, 1.40, 'CAP-MD-HOT', true),
(2, 'large', 'hot', 6.25, 1.70, 'CAP-LG-HOT', true),

-- Green Tea variations
(3, 'small', 'hot', 3.00, 0.50, 'GRT-SM-HOT', true),
(3, 'medium', 'hot', 3.50, 0.60, 'GRT-MD-HOT', true),
(3, 'small', 'ice', 3.25, 0.55, 'GRT-SM-ICE', true),

-- Pastries and food (no size/type variations)
(4, 'medium', 'none', 3.50, 1.00, 'CRO-MD-NONE', true),
(5, 'large', 'none', 12.99, 4.50, 'CLS-LG-NONE', true);

-- Insert sample ingredients
INSERT INTO ingredients (name, unit, current_stock, reorder_level, supplier_info) VALUES
('Coffee Beans - Arabica', 'kg', 50.0, 10.0, 'Premium Coffee Co. - Order #: 555-COFFEE'),
('Milk - Whole', 'L', 100.0, 20.0, 'Local Dairy Farm - Daily delivery'),
('Sugar', 'kg', 25.0, 5.0, 'Sweet Supplies Inc.'),
('Green Tea Leaves', 'kg', 15.0, 3.0, 'Tea Masters Ltd.'),
('Flour', 'kg', 40.0, 10.0, 'Baker Supply Co.'),
('Butter', 'kg', 20.0, 5.0, 'Dairy Products Ltd.'),
('Turkey Slices', 'kg', 5.0, 2.0, 'Deli Meats Express'),
('Bacon', 'kg', 3.0, 1.0, 'Meat Market Pro');

-- Insert sample employees
INSERT INTO employees (name, pin, role_id, is_active) VALUES
('Alice Johnson', '123456', 1, true),    -- Manager role
('Bob Smith', '234567', 3, true),        -- Barista role  
('Carol Davis', '345678', 4, true),      -- Cashier role
('David Wilson', '456789', 3, true);     -- Barista role

-- Insert sample customers
INSERT INTO customers (phone, name, email, loyalty_points, last_visit) VALUES
('+1-555-0101', 'John Doe', 'john.doe@email.com', 150, '2025-06-05'),
('+1-555-0102', 'Jane Smith', 'jane.smith@email.com', 230, '2025-06-04'),
('+1-555-0103', 'Mike Brown', 'mike.brown@email.com', 75, '2025-06-03');

-- Sample recipes (ingredient requirements per product variation)
INSERT INTO recipes (variation_id, ingredient_id, quantity) VALUES
-- Small Hot Latte ingredients
(1, 1, 0.020),  -- 20g coffee beans
(1, 2, 0.200),  -- 200ml milk

-- Medium Hot Latte ingredients  
(2, 1, 0.025),  -- 25g coffee beans
(2, 2, 0.300),  -- 300ml milk

-- Large Hot Latte ingredients
(3, 1, 0.030),  -- 30g coffee beans
(3, 2, 0.400),  -- 400ml milk

-- Small Green Tea ingredients
(10, 4, 0.005), -- 5g tea leaves

-- Croissant ingredients
(13, 5, 0.150), -- 150g flour
(13, 6, 0.050); -- 50g butter

-- Common PostgreSQL queries for the cafe POS system

-- 1. Get menu with all variations and prices
/*
SELECT 
    c.name AS category,
    p.name AS product,
    pv.size,
    pv.type,
    pv.price,
    pv.sku
FROM categories c
JOIN products p ON c.category_id = p.category_id
JOIN product_variations pv ON p.product_id = pv.product_id
WHERE p.is_active = true AND pv.is_available = true
ORDER BY c.display_order, p.name, pv.size, pv.type;
*/

-- 2. Create a new order with items
/*
BEGIN;

-- Insert order
INSERT INTO orders (order_number, employee_id, customer_id, order_time, total_amount, status, payment_method, tax_amount)
VALUES ('CAFE-2025-1001', 1, 1, CURRENT_TIMESTAMP, 11.00, 'open', 'card', 0.88);

-- Get the order_id
-- In application: order_id = cursor.fetchone()[0] after INSERT with RETURNING
-- INSERT INTO orders (...) RETURNING order_id;

-- Insert order items (assuming order_id = 1)
INSERT INTO order_items (order_id, variation_id, quantity, unit_price, modifiers) VALUES
(1, 2, 1, 5.50, '{"extra_shot": true}'),  -- Medium Hot Latte with extra shot
(1, 13, 1, 3.50, NULL),                   -- Croissant
(1, 10, 1, 3.00, '{"sugar": 2}');        -- Small Green Tea with 2 sugars

COMMIT;
*/

-- 3. Daily sales report
/*
SELECT 
    DATE(o.order_time) AS sale_date,
    COUNT(o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_revenue,
    SUM(o.tax_amount) AS total_tax,
    AVG(o.total_amount) AS avg_order_value
FROM orders o
WHERE o.status = 'paid' 
    AND o.order_time >= CURRENT_DATE
    AND o.order_time < CURRENT_DATE + INTERVAL '1 day'
GROUP BY DATE(o.order_time)
ORDER BY sale_date DESC;
*/

-- 4. Popular products report
/*
SELECT 
    p.name AS product,
    pv.size,
    pv.type,
    SUM(oi.quantity) AS total_sold,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN product_variations pv ON oi.variation_id = pv.variation_id
JOIN products p ON pv.product_id = p.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'paid'
    AND o.order_time >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY p.product_id, p.name, pv.variation_id, pv.size, pv.type
ORDER BY total_sold DESC
LIMIT 10;
*/

-- 5. Low stock alert
/*
SELECT 
    ingredient_id,
    name,
    current_stock,
    reorder_level,
    unit,
    (current_stock - reorder_level) AS stock_difference
FROM ingredients
WHERE current_stock <= reorder_level
ORDER BY stock_difference ASC;
*/

-- 6. Employee performance (orders processed)
/*
SELECT 
    e.name AS employee,
    e.role,
    COUNT(o.order_id) AS orders_processed,
    SUM(o.total_amount) AS total_sales,
    DATE(o.order_time) AS work_date
FROM employees e
JOIN orders o ON e.employee_id = o.employee_id
WHERE o.status = 'paid'
    AND o.order_time >= CURRENT_DATE
GROUP BY e.employee_id, e.name, e.role, DATE(o.order_time)
ORDER BY total_sales DESC;
*/

-- 7. Customer loyalty report
/*
SELECT 
    c.name,
    c.phone,
    c.loyalty_points,
    COUNT(o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    c.last_visit
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status = 'paid'
WHERE c.loyalty_points > 0
GROUP BY c.customer_id, c.name, c.phone, c.loyalty_points, c.last_visit
ORDER BY c.loyalty_points DESC
LIMIT 20;
*/

-- 8. Inventory usage tracking
/*
SELECT 
    i.name AS ingredient,
    i.unit,
    SUM(CASE WHEN it.transaction_type = 'sale' THEN ABS(it.change_amount) ELSE 0 END) AS used_today,
    SUM(CASE WHEN it.transaction_type = 'restock' THEN it.change_amount ELSE 0 END) AS restocked_today,
    i.current_stock
FROM ingredients i
LEFT JOIN inventory_transactions it ON i.ingredient_id = it.ingredient_id
    AND DATE(it.transaction_time) = CURRENT_DATE
GROUP BY i.ingredient_id, i.name, i.unit, i.current_stock
ORDER BY used_today DESC;
*/
