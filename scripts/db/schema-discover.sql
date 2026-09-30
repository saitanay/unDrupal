-- =============================================================================
-- schema-discover.sql
-- Discover all entity/field tables, custom entity types, and table sizes
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- Works with: Drupal 7, 8, 9, 10, 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Database overview: total tables and approximate size
-- -----------------------------------------------------------------------------
SELECT
    table_schema                              AS db_name,
    COUNT(*)                                  AS total_tables,
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_size_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
GROUP BY table_schema;

-- -----------------------------------------------------------------------------
-- 2. All entity field tables (D9+/D10+)
--    Pattern: {entity_type}__{field_name}
--    Examples: node__field_body, taxonomy_term__field_tags,
--              paragraph__field_text, media__field_media_image
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                AS approx_rows,
    ROUND((data_length + index_length) / 1024, 2) AS size_kb,
    SUBSTRING_INDEX(table_name, '__', 1)      AS entity_type,
    SUBSTRING_INDEX(table_name, '__', -1)     AS field_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE '%\_\_field\_%'
ORDER BY entity_type, field_name;

-- -----------------------------------------------------------------------------
-- 3. All entity field tables (D7)
--    Pattern: field_data_{field_name} and field_revision_{field_name}
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                AS approx_rows,
    ROUND((data_length + index_length) / 1024, 2) AS size_kb,
    CASE
        WHEN table_name LIKE 'field_data_%'     THEN 'field_data'
        WHEN table_name LIKE 'field_revision_%' THEN 'field_revision'
    END                                       AS table_type,
    CASE
        WHEN table_name LIKE 'field_data_%'
            THEN SUBSTRING(table_name, 12)
        WHEN table_name LIKE 'field_revision_%'
            THEN SUBSTRING(table_name, 16)
    END                                       AS field_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (table_name LIKE 'field\_data\_%' OR table_name LIKE 'field\_revision\_%')
ORDER BY field_name, table_type;

-- -----------------------------------------------------------------------------
-- 4. Entity base tables and field-data tables (D9+)
--    Covers: node, taxonomy_term, paragraph, media, block_content,
--            comment, user, menu_link_content, file, etc.
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                AS approx_rows,
    ROUND((data_length + index_length) / 1024, 2) AS size_kb
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (
       table_name LIKE 'node%'
    OR table_name LIKE 'taxonomy\_term%'
    OR table_name LIKE 'paragraph%'
    OR table_name LIKE 'paragraphs\_item%'
    OR table_name LIKE 'media%'
    OR table_name LIKE 'block\_content%'
    OR table_name LIKE 'comment%'
    OR table_name LIKE 'user%'
    OR table_name LIKE 'menu\_link\_content%'
    OR table_name LIKE 'file\_%'
    OR table_name LIKE 'path\_alias%'
    OR table_name LIKE 'redirect%'
    OR table_name LIKE 'commerce\_%'
    OR table_name LIKE 'webform\_%'
  )
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 5. Identify custom / contrib entity type tables
--    Heuristic: any table with double-underscore that is NOT a core entity type
-- -----------------------------------------------------------------------------
SELECT
    SUBSTRING_INDEX(table_name, '__', 1) AS entity_type,
    COUNT(*)                              AS field_table_count,
    SUM(table_rows)                       AS total_approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE '%\_\_%'
  AND SUBSTRING_INDEX(table_name, '__', 1) NOT IN (
      'node', 'taxonomy_term', 'paragraph', 'paragraphs_item',
      'media', 'block_content', 'comment', 'user',
      'menu_link_content', 'shortcut', 'contact_message',
      'content_moderation_state', 'workspace'
  )
GROUP BY entity_type
ORDER BY field_table_count DESC;

-- -----------------------------------------------------------------------------
-- 6. Revision tables — useful for estimating data volume
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                AS approx_rows,
    ROUND((data_length + index_length) / 1024, 2) AS size_kb
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (table_name LIKE '%\_revision%' OR table_name LIKE '%\_r\_\_%')
ORDER BY table_rows DESC;

-- -----------------------------------------------------------------------------
-- 7. Top 50 largest tables (quick size audit)
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                AS approx_rows,
    ROUND(data_length / 1024 / 1024, 2)      AS data_mb,
    ROUND(index_length / 1024 / 1024, 2)     AS index_mb,
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- 8. Content types in use (D9+)
-- -----------------------------------------------------------------------------
SELECT
    type                        AS content_type,
    COUNT(*)                    AS node_count
FROM node_field_data
GROUP BY type
ORDER BY node_count DESC;

-- -----------------------------------------------------------------------------
-- 9. Content types in use (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     type                     AS content_type,
--     COUNT(*)                 AS node_count
-- FROM node
-- GROUP BY type
-- ORDER BY node_count DESC;
