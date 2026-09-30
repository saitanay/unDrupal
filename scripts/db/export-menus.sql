-- =============================================================================
-- export-menus.sql
-- Export menu link content entities with tree structure
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Available menus and link counts
-- -----------------------------------------------------------------------------
SELECT
    menu_name,
    COUNT(*)                    AS link_count
FROM menu_link_content_data
GROUP BY menu_name
ORDER BY link_count DESC;

-- -----------------------------------------------------------------------------
-- 2. Export all menu links with hierarchy (D9+)
--    menu_link_content_data holds the link title and menu name.
--    menu_tree stores the materialized path (p1..p9) and depth.
-- -----------------------------------------------------------------------------
SELECT
    mlcd.id,
    mlcd.uuid,
    mlcd.menu_name,
    mlcd.title,
    mlcd.description,
    mlcd.langcode,
    mlcd.enabled,
    mlcd.expanded,
    mlcd.weight,
    -- Link target from the link field
    mlcl.link_uri                               AS uri,
    mlcl.link_title                             AS link_title,
    mlcl.link_options                           AS link_options,
    -- Parent link (from menu_tree or parent field)
    mlcp.parent_target_id                       AS parent_id,
    parent_link.title                           AS parent_title
FROM menu_link_content_data mlcd
LEFT JOIN menu_link_content__link mlcl
    ON mlcl.entity_id = mlcd.id
    AND mlcl.langcode = mlcd.langcode
LEFT JOIN menu_link_content__parent mlcp
    ON mlcp.entity_id = mlcd.id
LEFT JOIN menu_link_content_data parent_link
    ON parent_link.id = mlcp.parent_target_id
WHERE mlcd.default_langcode = 1
ORDER BY mlcd.menu_name, mlcd.weight, mlcd.title
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 3. Alternative: using menu_tree table directly (D9+)
--    The menu_tree table stores the full materialized path.
--    This works even for non-content menu links (system, views, etc.)
-- -----------------------------------------------------------------------------
-- Note: menu_tree may not exist on all installs. Drupal stores menu trees
-- in the key_value store or uses menu_tree_* tables per menu.
-- Check with: SHOW TABLES LIKE 'menu_tree%';

-- If your site uses the `menu_link_content` entity (most D9+ sites):
-- The parent relationship is in the `parent` field on the entity.
-- For system-generated links, check the `menu_tree` KV storage.

-- -----------------------------------------------------------------------------
-- 4. Recursive menu tree (MySQL 8.0+ / MariaDB 10.2+)
-- -----------------------------------------------------------------------------
WITH RECURSIVE menu_hierarchy AS (
    -- Root links (no parent)
    SELECT
        mlcd.id,
        mlcd.menu_name,
        mlcd.title,
        mlcd.weight,
        mlcl.link_uri                           AS uri,
        mlcd.enabled,
        0                                       AS depth,
        CAST(mlcd.title AS CHAR(1000))          AS tree_path,
        CAST(LPAD(mlcd.weight + 50, 3, '0') AS CHAR(500)) AS sort_key
    FROM menu_link_content_data mlcd
    LEFT JOIN menu_link_content__link mlcl
        ON mlcl.entity_id = mlcd.id
        AND mlcl.langcode = mlcd.langcode
    LEFT JOIN menu_link_content__parent mlcp
        ON mlcp.entity_id = mlcd.id
    WHERE (mlcp.parent_target_id IS NULL OR mlcp.parent_target_id = 0)
      AND mlcd.default_langcode = 1

    UNION ALL

    -- Children
    SELECT
        child.id,
        child.menu_name,
        child.title,
        child.weight,
        cl.link_uri,
        child.enabled,
        mh.depth + 1,
        CONCAT(mh.tree_path, ' > ', child.title),
        CONCAT(mh.sort_key, '/', LPAD(child.weight + 50, 3, '0'))
    FROM menu_link_content_data child
    INNER JOIN menu_link_content__parent cp
        ON cp.entity_id = child.id
    INNER JOIN menu_hierarchy mh
        ON mh.id = cp.parent_target_id
    LEFT JOIN menu_link_content__link cl
        ON cl.entity_id = child.id
        AND cl.langcode = child.langcode
    WHERE child.default_langcode = 1
      AND mh.depth < 10
)
SELECT
    id,
    menu_name,
    title,
    uri,
    enabled,
    depth,
    tree_path,
    weight
FROM menu_hierarchy
ORDER BY menu_name, sort_key
-- LIMIT 500
;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5. Available menus (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     menu_name,
--     title                    AS menu_title,
--     description
-- FROM menu_custom
-- ORDER BY menu_name;

-- -----------------------------------------------------------------------------
-- 6. Export all menu links (D7)
--    D7 uses `menu_links` table with `plid` (parent link id) for hierarchy
--    and p1-p9 columns for materialized path.
-- -----------------------------------------------------------------------------
-- SELECT
--     ml.mlid,
--     ml.menu_name,
--     ml.link_title,
--     ml.link_path,
--     ml.router_path,
--     ml.module,
--     ml.hidden,
--     ml.external,
--     ml.weight,
--     ml.depth,
--     ml.plid                                  AS parent_link_id,
--     parent.link_title                        AS parent_title,
--     -- Materialized path columns
--     ml.p1, ml.p2, ml.p3, ml.p4, ml.p5,
--     ml.options
-- FROM menu_links ml
-- LEFT JOIN menu_links parent
--     ON parent.mlid = ml.plid
-- WHERE ml.menu_name IN ('main-menu', 'management', 'navigation', 'user-menu')
-- ORDER BY ml.menu_name, ml.p1, ml.p2, ml.p3, ml.p4, ml.p5, ml.weight
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 7. D7 menu tree with indented display
-- -----------------------------------------------------------------------------
-- SELECT
--     ml.mlid,
--     ml.menu_name,
--     CONCAT(REPEAT('  ', ml.depth - 1), ml.link_title) AS indented_title,
--     ml.link_path,
--     ml.depth,
--     ml.weight,
--     ml.hidden
-- FROM menu_links ml
-- WHERE ml.menu_name = 'main-menu'
-- ORDER BY ml.p1, ml.p2, ml.p3, ml.p4, ml.p5, ml.weight
-- -- LIMIT 200
-- ;
