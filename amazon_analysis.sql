-- ============================================================
-- Amazon Sales Analytics — SQL Analysis
-- Dataset: 100,000 synthetic Amazon-style e-commerce transactions
-- Tool: MySQL Workbench (MySQL 8.0+ required for window functions/CTEs)
-- Author: [Musa Barrow ]



-- ============================================================
-- SECTION 0: DATABASE & TABLE SETUP

CREATE DATABASE IF NOT EXISTS amazon_sales;
USE amazon_sales;

DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    OrderID        VARCHAR(50) PRIMARY KEY,
    OrderDate      DATE,
    CustomerID     VARCHAR(50),
    CustomerName   VARCHAR(100),
    ProductID      VARCHAR(50),
    ProductName    VARCHAR(200),
    Category       VARCHAR(100),
    Brand          VARCHAR(100),
    Quantity       INT,
    UnitPrice      DECIMAL(10,2),
    Discount       DECIMAL(5,2),   -- stored as a fraction, e.g. 0.10 = 10%
    Tax            DECIMAL(10,2),
    ShippingCost   DECIMAL(10,2),
    TotalAmount    DECIMAL(10,2),
    PaymentMethod  VARCHAR(50),
    OrderStatus    VARCHAR(30),
    City           VARCHAR(100),
    State          VARCHAR(100),
    Country        VARCHAR(100),
    SellerID       VARCHAR(50)
);


SELECT COUNT(*) AS total_rows FROM amazon1;   


-- ============================================================
-- SECTION 1: BASIC BUSINESS QUERIES


-- Q1: Which product category generates the most total revenue?
SELECT
    Category,
    SUM(TotalAmount) AS Revenue
FROM amazon1
GROUP BY Category
ORDER BY Revenue DESC;


-- Q2: Top 10 customers by total amount spent
SELECT
    CustomerID,
    CustomerName,
    SUM(TotalAmount) AS TotalSpent
FROM amazon1
GROUP BY CustomerID, CustomerName
ORDER BY TotalSpent DESC
LIMIT 10;


-- Q3: Order status breakdown — what % of orders were Cancelled or Returned?
SELECT
    OrderStatus,
    COUNT(*) AS Total,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) AS PctOfAllOrders
FROM amazon1
GROUP BY OrderStatus
ORDER BY Total DESC;


-- Q4: Monthly revenue trend — are there seasonal peaks?
SELECT
    DATE_FORMAT(OrderDate, '%Y-%m') AS Month,
    SUM(TotalAmount) AS Revenue,
    COUNT(*) AS Orders
FROM amazon1
GROUP BY Month
ORDER BY Month;


-- Q5: Average order value per category
SELECT
    Category,
    ROUND(AVG(TotalAmount), 2) AS AvgOrderValue
FROM amazon1
GROUP BY Category
ORDER BY AvgOrderValue DESC;


-- Q6: Does a higher discount % lead to more cancellations?
SELECT
    CASE
        WHEN Discount = 0 THEN 'No Discount'
        WHEN Discount < 0.20 THEN 'Low (0–20%)'
        ELSE 'High (20%+)'
    END AS DiscountBand,
    COUNT(*) AS TotalOrders,
    SUM(CASE WHEN OrderStatus = 'Cancelled' THEN 1 ELSE 0 END) AS CancelledOrders,
    ROUND(SUM(CASE WHEN OrderStatus = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CancelRatePct
FROM amazon1
GROUP BY DiscountBand
ORDER BY CancelRatePct DESC;


-- Q7: Top 5 brands by revenue
SELECT
    Brand,
    SUM(TotalAmount) AS Revenue
FROM amazon1
GROUP BY Brand
ORDER BY Revenue DESC
LIMIT 5;


-- Q8: Most popular payment method
SELECT
    PaymentMethod,
    COUNT(*) AS OrderCount,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) AS PctOfOrders
FROM amazon1
GROUP BY PaymentMethod
ORDER BY OrderCount DESC;


-- Q9: Which city has the highest number of DELIVERED orders?
SELECT
    City,
    COUNT(*) AS DeliveredOrders
FROM amazon1
WHERE OrderStatus = 'Delivered'
GROUP BY City
ORDER BY DeliveredOrders DESC
LIMIT 10;


-- Q10: Rank products by revenue within their category (Window Function)
SELECT
    Category,
    ProductName,
    Revenue,
    RankInCategory
FROM (
    SELECT
        Category,
        ProductName,
        SUM(TotalAmount) AS Revenue,
        RANK() OVER (PARTITION BY Category ORDER BY SUM(TotalAmount) DESC) AS RankInCategory
    FROM amazon1
    GROUP BY Category, ProductName
) ranked
WHERE RankInCategory <= 5
ORDER BY Category, RankInCategory;


-- ============================================================
-- SECTION 2: ADVANCED QUERIES (CTEs, Window Functions, Subqueries)


-- A1: CTE — Customer Lifetime Value tiers

WITH customer_spend AS (
    SELECT
        CustomerID,
        CustomerName,
        SUM(TotalAmount) AS LifetimeSpend,
        COUNT(*) AS OrderCount
    FROM amazon1
    GROUP BY CustomerID, CustomerName
),
customer_tiers AS (
    SELECT
        *,
        CASE
            WHEN LifetimeSpend >= 2000 THEN 'High Value'
            WHEN LifetimeSpend >= 800  THEN 'Medium Value'
            ELSE 'Low Value'
        END AS CustomerTier
    FROM customer_spend
)
SELECT
    CustomerTier,
    COUNT(*) AS NumCustomers,
    ROUND(AVG(LifetimeSpend), 2) AS AvgLifetimeSpend,
    ROUND(AVG(OrderCount), 2) AS AvgOrdersPerCustomer
FROM customer_tiers
GROUP BY CustomerTier
ORDER BY AvgLifetimeSpend DESC;


-- A2: CTE + Window Function — Month-over-month revenue growth %
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(OrderDate, '%Y-%m') AS Month,
        SUM(TotalAmount) AS Revenue
    FROM amazon1
    GROUP BY Month
)
SELECT
    Month,
    Revenue,
    LAG(Revenue) OVER (ORDER BY Month) AS PrevMonthRevenue,
    ROUND(
        (Revenue - LAG(Revenue) OVER (ORDER BY Month)) * 100.0
        / LAG(Revenue) OVER (ORDER BY Month), 2
    ) AS MoM_GrowthPct
FROM monthly_revenue
ORDER BY Month;


-- A3: Running total of revenue over time (Window Function)
WITH daily_revenue AS (
    SELECT
        OrderDate,
        SUM(TotalAmount) AS DailyRevenue
    FROM amazon1
    GROUP BY OrderDate
)
SELECT
    OrderDate,
    DailyRevenue,
    SUM(DailyRevenue) OVER (ORDER BY OrderDate) AS RunningTotalRevenue
FROM daily_revenue
ORDER BY OrderDate;


-- A4: Repeat customers — customers with more than 1 order, and what share of revenue they drive
WITH customer_orders AS (
    SELECT
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpend
    FROM amazon1
    GROUP BY CustomerID
)
SELECT
    CASE WHEN OrderCount > 1 THEN 'Repeat Customer' ELSE 'One-Time Customer' END AS CustomerType,
    COUNT(*) AS NumCustomers,
    SUM(TotalSpend) AS TotalRevenue,
    ROUND(SUM(TotalSpend) * 100.0 / (SELECT SUM(TotalAmount) FROM orders), 2) AS PctOfTotalRevenue
FROM customer_orders
GROUP BY CustomerType;


-- A5: Subquery — Products that sell above the average UnitPrice of their category
SELECT
    o.Category,
    o.ProductName,
    o.UnitPrice
FROM amazon1 o
WHERE o.UnitPrice > (
    SELECT AVG(UnitPrice)
    FROM amazon1 o2
    WHERE o2.Category = o.Category
)
GROUP BY o.Category, o.ProductName, o.UnitPrice
ORDER BY o.Category, o.UnitPrice DESC;


-- A6: Window Function — Each city's % contribution to its country's total revenue
WITH city_revenue AS (
    SELECT
        Country,
        City,
        SUM(TotalAmount) AS CityRevenue
    FROM amazon1
    GROUP BY Country, City
)
SELECT
    Country,
    City,
    CityRevenue,
    ROUND(CityRevenue * 100.0 / SUM(CityRevenue) OVER (PARTITION BY Country), 2) AS PctOfCountryRevenue
FROM city_revenue
ORDER BY Country, CityRevenue DESC;


-- A7: CTE — Cancellation rate by category, ranked worst to best
WITH category_stats AS (
    SELECT
        Category,
        COUNT(*) AS TotalOrders,
        SUM(CASE WHEN OrderStatus = 'Cancelled' THEN 1 ELSE 0 END) AS Cancelled
    FROM amazon1
    GROUP BY Category
)
SELECT
    Category,
    TotalOrders,
    Cancelled,
    ROUND(Cancelled * 100.0 / TotalOrders, 2) AS CancellationRatePct
FROM category_stats
ORDER BY CancellationRatePct DESC;


-- A8: Window Function — Top 3 best-selling products per seller
WITH seller_products AS (
    SELECT
        SellerID,
        ProductName,
        SUM(TotalAmount) AS Revenue,
        ROW_NUMBER() OVER (PARTITION BY SellerID ORDER BY SUM(TotalAmount) DESC) AS rn
    FROM amazon1
    GROUP BY SellerID, ProductName
)
SELECT SellerID, ProductName, Revenue
FROM seller_products
WHERE rn <= 3
ORDER BY SellerID, Revenue DESC;


-- A9: Year-over-year comparison using a CTE
WITH yearly_revenue AS (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        SUM(TotalAmount) AS Revenue,
        COUNT(*) AS Orders
    FROM amazon1
    GROUP BY YEAR(OrderDate)
)
SELECT
    OrderYear,
    Revenue,
    Orders,
    ROUND(Revenue / Orders, 2) AS AvgOrderValue
FROM yearly_revenue
ORDER BY OrderYear;


-- A10: Payment method preference by country (helps with regional insight)
SELECT
    Country,
    PaymentMethod,
    COUNT(*) AS OrderCount,
    RANK() OVER (PARTITION BY Country ORDER BY COUNT(*) DESC) AS RankInCountry
FROM amazon1
GROUP BY Country, PaymentMethod
HAVING RankInCountry <= 1 
ORDER BY Country;
