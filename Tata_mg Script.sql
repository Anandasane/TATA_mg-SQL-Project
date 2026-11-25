use tata1mg_db;

select count(*) from orders;

select count(order_id) total_orders from orders
where year(order_datetime) = 2026 and month(order_datetime)=10;

select count(order_id) delivered_orders from orders
where order_status = 'Delivered' and year(order_datetime)=2026 and month(order_datetime) = 10;

select sum(order_value) revenue from orders
where order_status = 'Delivered' and year(order_datetime)=2026 and month(order_datetime) = 10;

select round(sum(order_value)/count(order_id),2) AOV from orders
where year(order_datetime) = 2026 and month(order_datetime) = 10;

SELECT
  COUNT(*) AS total_orders,
  SUM(order_status = 'Delivered') AS delivered_orders,
  SUM(CASE WHEN order_status = 'Delivered' THEN order_value END) AS revenue,
  ROUND(AVG(CASE WHEN order_status = 'Delivered' THEN order_value END), 2) AS aov
FROM orders
WHERE order_datetime >= '2026-10-01'
  AND order_datetime < '2026-11-01';
  
  SELECT
  c.city_name,
  COUNT(*) AS orders,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_share
FROM orders o
JOIN customers cu ON cu.customer_id = o.customer_id
JOIN cities c     ON c.city_id = cu.city_id
GROUP BY c.city_name
ORDER BY orders DESC
LIMIT 10;

WITH express AS (
  SELECT
    c.city_name,
    TIMESTAMPDIFF(MINUTE, o.order_datetime, o.delivered_datetime) AS mins
  FROM orders o
  JOIN customers cu ON cu.customer_id = o.customer_id
  JOIN cities c     ON c.city_id = cu.city_id
  WHERE o.delivery_type = 'Express'
    AND o.delivered_datetime IS NOT NULL
)
SELECT
  city_name,
  COUNT(*) AS express_orders,
  SUM(mins > 60) AS breached,
  ROUND(100 * SUM(mins > 60) / COUNT(*), 2) AS breach_pct
FROM express
GROUP BY city_name
ORDER BY breach_pct DESC;

WITH season AS (
  SELECT
    c.region,
    SUM(CASE WHEN YEAR(o.order_datetime) = 2025
             THEN oi.quantity * oi.unit_price ELSE 0 END) AS sales_2025,
    SUM(CASE WHEN YEAR(o.order_datetime) = 2026
             THEN oi.quantity * oi.unit_price ELSE 0 END) AS sales_2026
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN products p     ON p.product_id = oi.product_id
  JOIN customers cu   ON cu.customer_id = o.customer_id
  JOIN cities c       ON c.city_id = cu.city_id
  WHERE p.category = 'Fever & Cold'
    AND oi.item_status = 'Fulfilled'
    AND o.order_status = 'Delivered'
    AND MONTH(o.order_datetime) IN (9, 10)
  GROUP BY c.region
)


SELECT
  region,
  sales_2025,
  sales_2026,
  ROUND(100 * (sales_2026 - sales_2025) / sales_2025, 1) AS yoy_growth_pct
FROM season
ORDER BY yoy_growth_pct DESC;

WITH weekly AS (
  SELECT
    c.city_name,
    YEARWEEK(b.booking_datetime, 3) AS yr_wk,
    COUNT(*) AS bookings
  FROM lab_bookings b
  JOIN lab_tests t        ON t.test_id = b.test_id
  JOIN phlebotomists ph   ON ph.phlebotomist_id = b.phlebotomist_id
  JOIN cities c           ON c.city_id = ph.city_id
  WHERE t.test_category = 'Fever Panel'
    AND b.booking_datetime >= '2026-08-01'
  GROUP BY c.city_name, yr_wk
),
wow AS (
  SELECT
    *,
    LAG(bookings) OVER (PARTITION BY city_name ORDER BY yr_wk) AS prev_week
  FROM weekly
)
SELECT
  city_name,
  yr_wk,
  prev_week,
  bookings,
  ROUND(100 * (bookings - prev_week) / prev_week, 1) AS wow_growth_pct
FROM wow
WHERE bookings >= 15
  AND (bookings - prev_week) / prev_week > 0.5
ORDER BY yr_wk, city_name;


SELECT
  c.city_name,
  p.product_name,
  COUNT(DISTINCT oi.order_id) AS orders_affected,
  SUM(oi.quantity)            AS units_lost
FROM order_items oi
JOIN orders o      ON o.order_id = oi.order_id
JOIN products p    ON p.product_id = oi.product_id
JOIN customers cu  ON cu.customer_id = o.customer_id
JOIN cities c      ON c.city_id = cu.city_id
WHERE oi.item_status = 'Out of Stock'
  AND p.category = 'Fever & Cold'
  AND o.order_datetime >= '2026-09-01'
  AND o.order_datetime <  '2026-11-01'
GROUP BY c.city_name, p.product_name
HAVING orders_affected >= 5
ORDER BY orders_affected DESC;

WITH perf AS (
  SELECT
    c.city_name,
    ph.phlebotomist_id,
    ph.phlebotomist_name,
    SUM(b.collection_status = 'Collected') AS collected,
    SUM(b.collection_status = 'Missed')    AS missed
  FROM lab_bookings b
  JOIN phlebotomists ph ON ph.phlebotomist_id = b.phlebotomist_id
  JOIN cities c         ON c.city_id = ph.city_id
  GROUP BY c.city_name, ph.phlebotomist_id, ph.phlebotomist_name
),
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (PARTITION BY city_name ORDER BY collected DESC) AS rnk
  FROM perf
)
SELECT
  city_name,
  rnk, phlebotomist_name, collected, missed
FROM ranked
WHERE rnk <= 3
ORDER BY city_name, rnk;

WITH perf AS (
  SELECT
    c.city_name,
    ph.phlebotomist_id,
    ph.phlebotomist_name,
    SUM(b.collection_status = 'Collected') AS collected,
    SUM(b.collection_status = 'Missed')    AS missed
  FROM lab_bookings b
  JOIN phlebotomists ph ON ph.phlebotomist_id = b.phlebotomist_id
  JOIN cities c         ON c.city_id = ph.city_id
  GROUP BY c.city_name, ph.phlebotomist_id, ph.phlebotomist_name
),
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (PARTITION BY city_name ORDER BY collected DESC) AS rnk
  FROM perf
)
SELECT
  city_name,
  rnk, phlebotomist_name, collected, missed
FROM ranked
WHERE rnk <= 3
ORDER BY city_name, rnk;


SELECT
  bought.category,
  COUNT(*) AS total_items,
  SUM(oi.substituted_from_product_id IS NOT NULL) AS switched_items,
  ROUND(100 * SUM(oi.substituted_from_product_id IS NOT NULL) / COUNT(*), 2) AS switched_pct,
  ROUND(SUM((original.selling_price - oi.unit_price) * oi.quantity), 2) AS customer_savings
FROM order_items oi
JOIN products bought ON bought.product_id = oi.product_id
LEFT JOIN products original ON original.product_id = oi.substituted_from_product_id
WHERE oi.item_status = 'Fulfilled'
GROUP BY bought.category
ORDER BY customer_savings DESC;





