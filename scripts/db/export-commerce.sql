-- =============================================================================
-- export-commerce.sql
-- Export Drupal Commerce data: products, variations, orders, payments
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- Drupal Commerce 2.x (D8/D9/D10/D11)
-- =============================================================================

-- NOTE: Drupal Commerce 1.x (D7) used a significantly different schema.
-- D7 variants are included at the bottom but the table/column names differ
-- substantially from Commerce 2.x.

-- =============================================================================
-- DRUPAL COMMERCE 2.x (D8 / D9 / D10 / D11)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: check which commerce tables exist
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows,
    ROUND((data_length + index_length) / 1024, 2) AS size_kb
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'commerce\_%'
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 2. Product overview: counts by type
-- -----------------------------------------------------------------------------
SELECT
    type                        AS product_type,
    COUNT(*)                    AS product_count
FROM commerce_product_field_data
GROUP BY type
ORDER BY product_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Export products with store info
-- -----------------------------------------------------------------------------
SELECT
    cpfd.product_id,
    cpfd.uuid,
    cpfd.type                                   AS product_type,
    cpfd.title,
    cpfd.status                                 AS published,
    cpfd.langcode,
    FROM_UNIXTIME(cpfd.created)                 AS created_at,
    FROM_UNIXTIME(cpfd.changed)                 AS changed_at,
    cpfd.uid                                    AS author_uid,
    -- Store assignment
    cps.stores_target_id                        AS store_id,
    pa.alias                                    AS url_alias
FROM commerce_product_field_data cpfd
LEFT JOIN commerce_product__stores cps
    ON cps.entity_id = cpfd.product_id
LEFT JOIN path_alias pa
    ON pa.path = CONCAT('/product/', cpfd.product_id)
ORDER BY cpfd.product_id
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 4. Export product variations with pricing
--    commerce_product_variation_field_data stores SKU, price, etc.
--    Price is split into number + currency_code columns.
-- -----------------------------------------------------------------------------
SELECT
    cpvfd.variation_id,
    cpvfd.uuid,
    cpvfd.type                                  AS variation_type,
    cpvfd.sku,
    cpvfd.title,
    cpvfd.status                                AS active,
    cpvfd.langcode,
    cpvfd.product_id,
    cpfd.title                                  AS product_title,
    -- Price fields: stored as number + currency_code
    cpvfd.price__number                         AS price,
    cpvfd.price__currency_code                  AS currency,
    -- List price (original/compare-at price)
    cpvfd.list_price__number                    AS list_price,
    cpvfd.list_price__currency_code             AS list_price_currency,
    FROM_UNIXTIME(cpvfd.created)                AS created_at,
    FROM_UNIXTIME(cpvfd.changed)                AS changed_at
FROM commerce_product_variation_field_data cpvfd
LEFT JOIN commerce_product_field_data cpfd
    ON cpfd.product_id = cpvfd.product_id
ORDER BY cpvfd.product_id, cpvfd.variation_id
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 5. Export orders
-- -----------------------------------------------------------------------------
SELECT
    cofd.order_id,
    cofd.uuid,
    cofd.order_number,
    cofd.type                                   AS order_type,
    cofd.state                                  AS order_state,
    cofd.mail                                   AS customer_email,
    cofd.uid                                    AS customer_uid,
    ufd.name                                    AS customer_username,
    cofd.ip_address,
    -- Totals
    cofd.total_price__number                    AS total_price,
    cofd.total_price__currency_code             AS total_currency,
    cofd.total_paid__number                     AS total_paid,
    cofd.total_paid__currency_code              AS paid_currency,
    -- Store
    cofd.store_id,
    -- Timestamps
    FROM_UNIXTIME(cofd.created)                 AS created_at,
    FROM_UNIXTIME(cofd.changed)                 AS changed_at,
    FROM_UNIXTIME(cofd.placed)                  AS placed_at,
    FROM_UNIXTIME(cofd.completed)               AS completed_at,
    cofd.langcode
FROM commerce_order_field_data cofd
LEFT JOIN users_field_data ufd
    ON ufd.uid = cofd.uid
ORDER BY cofd.order_id
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 6. Export order items (line items)
-- -----------------------------------------------------------------------------
SELECT
    coifd.order_item_id,
    coifd.uuid,
    coifd.type                                  AS order_item_type,
    coifd.title                                 AS line_item_title,
    coifd.quantity,
    -- Unit price
    coifd.unit_price__number                    AS unit_price,
    coifd.unit_price__currency_code             AS unit_currency,
    -- Total price for this line
    coifd.total_price__number                   AS line_total,
    coifd.total_price__currency_code            AS line_currency,
    -- Adjusted total (after promotions/taxes)
    coifd.adjusted_total_price__number          AS adjusted_total,
    coifd.adjusted_total_price__currency_code   AS adjusted_currency,
    -- Purchased entity reference
    coifd.purchased_entity                      AS purchased_entity_id,
    -- Order reference
    coifd.order_id,
    FROM_UNIXTIME(coifd.created)                AS created_at,
    FROM_UNIXTIME(coifd.changed)                AS changed_at
FROM commerce_order_item_field_data coifd
ORDER BY coifd.order_id, coifd.order_item_id
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 7. Orders with line items summary
-- -----------------------------------------------------------------------------
SELECT
    cofd.order_id,
    cofd.order_number,
    cofd.state                                  AS order_state,
    cofd.mail                                   AS customer_email,
    cofd.total_price__number                    AS order_total,
    cofd.total_price__currency_code             AS currency,
    COUNT(coifd.order_item_id)                  AS line_item_count,
    SUM(coifd.quantity)                         AS total_quantity,
    FROM_UNIXTIME(cofd.placed)                  AS placed_at
FROM commerce_order_field_data cofd
LEFT JOIN commerce_order_item_field_data coifd
    ON coifd.order_id = cofd.order_id
GROUP BY
    cofd.order_id, cofd.order_number, cofd.state,
    cofd.mail, cofd.total_price__number,
    cofd.total_price__currency_code, cofd.placed
ORDER BY cofd.order_id
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 8. Export payments
-- -----------------------------------------------------------------------------
SELECT
    cpfd.payment_id,
    cpfd.uuid,
    cpfd.type                                   AS payment_type,
    cpfd.payment_gateway,
    cpfd.payment_gateway_mode,
    cpfd.payment_method,
    cpfd.order_id,
    cpfd.remote_id                              AS gateway_transaction_id,
    cpfd.remote_state                           AS gateway_state,
    -- Amount
    cpfd.amount__number                         AS payment_amount,
    cpfd.amount__currency_code                  AS payment_currency,
    -- Refunded
    cpfd.refunded_amount__number                AS refunded_amount,
    cpfd.refunded_amount__currency_code         AS refunded_currency,
    cpfd.state                                  AS payment_state,
    FROM_UNIXTIME(cpfd.authorized)              AS authorized_at,
    FROM_UNIXTIME(cpfd.captured)                AS captured_at,
    FROM_UNIXTIME(cpfd.completed)               AS completed_at
FROM commerce_payment_field_data cpfd
ORDER BY cpfd.order_id, cpfd.payment_id
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 9. Store details
-- -----------------------------------------------------------------------------
SELECT
    csfd.store_id,
    csfd.uuid,
    csfd.type                                   AS store_type,
    csfd.name                                   AS store_name,
    csfd.mail                                   AS store_email,
    csfd.default_currency,
    csfd.is_default,
    csfd.uid                                    AS owner_uid
FROM commerce_store_field_data csfd
ORDER BY csfd.store_id;

-- -----------------------------------------------------------------------------
-- 10. Discover custom commerce field tables
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (
       table_name LIKE 'commerce\_product\_\_field\_%'
    OR table_name LIKE 'commerce\_product\_variation\_\_field\_%'
    OR table_name LIKE 'commerce\_order\_\_field\_%'
    OR table_name LIKE 'commerce\_order\_item\_\_field\_%'
  )
ORDER BY table_name;

-- =============================================================================
-- DRUPAL COMMERCE 1.x (D7)
-- =============================================================================
-- Commerce 1.x schema differs significantly:
-- - commerce_product (entity table, not commerce_product_field_data)
-- - commerce_line_item (instead of commerce_order_item)
-- - commerce_order (flatter structure)
-- - Price stored in field_data_commerce_price

-- -----------------------------------------------------------------------------
-- 11. Export products (Commerce 1.x / D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     cp.product_id,
--     cp.revision_id,
--     cp.sku,
--     cp.title,
--     cp.type                                  AS product_type,
--     cp.status                                AS active,
--     cp.uid                                   AS author_uid,
--     FROM_UNIXTIME(cp.created)                AS created_at,
--     FROM_UNIXTIME(cp.changed)                AS changed_at,
--     -- Price
--     fcp.commerce_price_amount / 100          AS price,
--     fcp.commerce_price_currency_code         AS currency
-- FROM commerce_product cp
-- LEFT JOIN field_data_commerce_price fcp
--     ON fcp.entity_id = cp.product_id
--     AND fcp.entity_type = 'commerce_product'
-- ORDER BY cp.product_id
-- -- LIMIT 200
-- ;

-- -----------------------------------------------------------------------------
-- 12. Export orders (Commerce 1.x / D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     co.order_id,
--     co.order_number,
--     co.revision_id,
--     co.type                                  AS order_type,
--     co.status                                AS order_status,
--     co.uid                                   AS customer_uid,
--     u.name                                   AS customer_name,
--     co.mail                                  AS customer_email,
--     co.hostname                              AS ip_address,
--     -- Total
--     fcot.commerce_order_total_amount / 100   AS order_total,
--     fcot.commerce_order_total_currency_code  AS currency,
--     FROM_UNIXTIME(co.created)                AS created_at,
--     FROM_UNIXTIME(co.changed)                AS changed_at,
--     FROM_UNIXTIME(co.placed)                 AS placed_at
-- FROM commerce_order co
-- LEFT JOIN users u
--     ON u.uid = co.uid
-- LEFT JOIN field_data_commerce_order_total fcot
--     ON fcot.entity_id = co.order_id
--     AND fcot.entity_type = 'commerce_order'
-- ORDER BY co.order_id
-- -- LIMIT 200
-- ;

-- -----------------------------------------------------------------------------
-- 13. Export line items (Commerce 1.x / D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     cli.line_item_id,
--     cli.order_id,
--     cli.type                                 AS line_item_type,
--     cli.line_item_label                      AS label,
--     cli.quantity,
--     -- Unit price
--     fcup.commerce_unit_price_amount / 100    AS unit_price,
--     fcup.commerce_unit_price_currency_code   AS unit_currency,
--     -- Total
--     fct.commerce_total_amount / 100          AS line_total,
--     fct.commerce_total_currency_code         AS line_currency,
--     FROM_UNIXTIME(cli.created)               AS created_at,
--     FROM_UNIXTIME(cli.changed)               AS changed_at
-- FROM commerce_line_item cli
-- LEFT JOIN field_data_commerce_unit_price fcup
--     ON fcup.entity_id = cli.line_item_id
--     AND fcup.entity_type = 'commerce_line_item'
-- LEFT JOIN field_data_commerce_total fct
--     ON fct.entity_id = cli.line_item_id
--     AND fct.entity_type = 'commerce_line_item'
-- ORDER BY cli.order_id, cli.line_item_id
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 14. Payment transactions (Commerce 1.x / D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     cpt.transaction_id,
--     cpt.order_id,
--     cpt.payment_method,
--     cpt.instance_id                          AS payment_instance,
--     cpt.remote_id                            AS gateway_transaction_id,
--     cpt.remote_status                        AS gateway_status,
--     cpt.amount / 100                         AS amount,
--     cpt.currency_code                        AS currency,
--     cpt.status                               AS payment_status,
--     cpt.message                              AS status_message,
--     FROM_UNIXTIME(cpt.created)               AS created_at,
--     FROM_UNIXTIME(cpt.changed)               AS changed_at
-- FROM commerce_payment_transaction cpt
-- ORDER BY cpt.order_id, cpt.transaction_id
-- -- LIMIT 200
-- ;
