-- =============================================================================
-- export-aliases.sql
-- Export URL path aliases for all entities
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11  (path_alias table)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: alias counts by entity type
--    Drupal stores internal paths like /node/123, /taxonomy/term/45, etc.
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN path LIKE '/node/%'          THEN 'node'
        WHEN path LIKE '/taxonomy/term/%' THEN 'taxonomy_term'
        WHEN path LIKE '/media/%'         THEN 'media'
        WHEN path LIKE '/user/%'          THEN 'user'
        ELSE 'other'
    END                                         AS entity_type,
    COUNT(*)                                    AS alias_count
FROM path_alias
GROUP BY entity_type
ORDER BY alias_count DESC;

-- -----------------------------------------------------------------------------
-- 2. Alias counts by language
-- -----------------------------------------------------------------------------
SELECT
    langcode,
    COUNT(*)                    AS alias_count
FROM path_alias
GROUP BY langcode
ORDER BY alias_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Export all path aliases (D9+)
-- -----------------------------------------------------------------------------
SELECT
    pa.id,
    pa.uuid,
    pa.path                                     AS internal_path,
    pa.alias                                    AS url_alias,
    pa.langcode,
    pa.status,
    -- Extract entity ID from the internal path
    CASE
        WHEN pa.path LIKE '/node/%'
            THEN CAST(SUBSTRING(pa.path, 7) AS UNSIGNED)
        WHEN pa.path LIKE '/taxonomy/term/%'
            THEN CAST(SUBSTRING(pa.path, 16) AS UNSIGNED)
        WHEN pa.path LIKE '/media/%'
            THEN CAST(SUBSTRING(pa.path, 8) AS UNSIGNED)
        WHEN pa.path LIKE '/user/%'
            THEN CAST(SUBSTRING(pa.path, 7) AS UNSIGNED)
        ELSE NULL
    END                                         AS entity_id,
    CASE
        WHEN pa.path LIKE '/node/%'          THEN 'node'
        WHEN pa.path LIKE '/taxonomy/term/%' THEN 'taxonomy_term'
        WHEN pa.path LIKE '/media/%'         THEN 'media'
        WHEN pa.path LIKE '/user/%'          THEN 'user'
        ELSE 'other'
    END                                         AS entity_type
FROM path_alias pa
ORDER BY pa.alias
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Node aliases with titles (D9+)
-- -----------------------------------------------------------------------------
SELECT
    pa.id                                       AS alias_id,
    pa.path                                     AS internal_path,
    pa.alias                                    AS url_alias,
    pa.langcode,
    nfd.nid,
    nfd.type                                    AS content_type,
    nfd.title,
    nfd.status                                  AS published
FROM path_alias pa
INNER JOIN node_field_data nfd
    ON nfd.nid = CAST(SUBSTRING(pa.path, 7) AS UNSIGNED)
    AND pa.path LIKE '/node/%'
WHERE nfd.default_langcode = 1
ORDER BY pa.alias
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 5. Detect duplicate aliases (same alias pointing to different paths)
-- -----------------------------------------------------------------------------
SELECT
    alias,
    langcode,
    COUNT(*)                    AS duplicate_count,
    GROUP_CONCAT(path ORDER BY id SEPARATOR ', ') AS internal_paths
FROM path_alias
GROUP BY alias, langcode
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- =============================================================================
-- DRUPAL 7 / 8 early  (url_alias table)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6. Export all URL aliases (D7/D8)
--    D7 uses `source` instead of `path`, and the table is `url_alias`
-- -----------------------------------------------------------------------------
-- SELECT
--     ua.pid                                   AS alias_id,
--     ua.source                                AS internal_path,
--     ua.alias                                 AS url_alias,
--     ua.language                              AS langcode,
--     -- Extract entity ID
--     CASE
--         WHEN ua.source LIKE 'node/%'
--             THEN CAST(SUBSTRING(ua.source, 6) AS UNSIGNED)
--         WHEN ua.source LIKE 'taxonomy/term/%'
--             THEN CAST(SUBSTRING(ua.source, 15) AS UNSIGNED)
--         ELSE NULL
--     END                                      AS entity_id,
--     CASE
--         WHEN ua.source LIKE 'node/%'          THEN 'node'
--         WHEN ua.source LIKE 'taxonomy/term/%' THEN 'taxonomy_term'
--         WHEN ua.source LIKE 'user/%'          THEN 'user'
--         ELSE 'other'
--     END                                      AS entity_type
-- FROM url_alias ua
-- ORDER BY ua.alias
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 7. Node aliases with titles (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     ua.pid                                   AS alias_id,
--     ua.source                                AS internal_path,
--     ua.alias                                 AS url_alias,
--     ua.language                              AS langcode,
--     n.nid,
--     n.type                                   AS content_type,
--     n.title,
--     n.status                                 AS published
-- FROM url_alias ua
-- INNER JOIN node n
--     ON n.nid = CAST(SUBSTRING(ua.source, 6) AS UNSIGNED)
--     AND ua.source LIKE 'node/%'
-- ORDER BY ua.alias
-- -- LIMIT 500
-- ;
