-- =============================================================================
-- export-redirects.sql
-- Export URL redirects (contrib redirect module)
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11  (redirect module)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: redirect counts by status code
-- -----------------------------------------------------------------------------
SELECT
    status_code,
    COUNT(*)                    AS redirect_count
FROM redirect
GROUP BY status_code
ORDER BY redirect_count DESC;

-- -----------------------------------------------------------------------------
-- 2. Redirect counts by language
-- -----------------------------------------------------------------------------
SELECT
    language                    AS langcode,
    COUNT(*)                    AS redirect_count
FROM redirect
GROUP BY language
ORDER BY redirect_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Export all redirects (D9+)
--    redirect_source__path: the old path that triggers the redirect
--    redirect_redirect__uri: the target URL
-- -----------------------------------------------------------------------------
SELECT
    r.rid,
    r.uuid,
    r.redirect_source__path                     AS source_path,
    r.redirect_source__query                    AS source_query,
    r.redirect_redirect__uri                    AS redirect_target,
    r.redirect_redirect__title                  AS redirect_title,
    r.status_code,
    r.language                                  AS langcode,
    r.type                                      AS redirect_type,
    r.hash                                      AS redirect_hash,
    r.uid                                       AS created_by_uid,
    FROM_UNIXTIME(r.created)                    AS created_at
FROM redirect r
ORDER BY r.redirect_source__path
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Redirects pointing to nodes (with node title)
-- -----------------------------------------------------------------------------
SELECT
    r.rid,
    r.redirect_source__path                     AS source_path,
    r.redirect_redirect__uri                    AS redirect_target,
    r.status_code,
    r.language                                  AS langcode,
    -- Extract nid from internal: URIs like 'internal:/node/123' or 'entity:node/123'
    CASE
        WHEN r.redirect_redirect__uri LIKE 'internal:/node/%'
            THEN CAST(SUBSTRING(r.redirect_redirect__uri, 16) AS UNSIGNED)
        WHEN r.redirect_redirect__uri LIKE 'entity:node/%'
            THEN CAST(SUBSTRING(r.redirect_redirect__uri, 13) AS UNSIGNED)
        ELSE NULL
    END                                         AS target_nid,
    nfd.title                                   AS target_node_title,
    nfd.type                                    AS target_content_type,
    nfd.status                                  AS target_published
FROM redirect r
LEFT JOIN node_field_data nfd
    ON nfd.nid = CASE
        WHEN r.redirect_redirect__uri LIKE 'internal:/node/%'
            THEN CAST(SUBSTRING(r.redirect_redirect__uri, 16) AS UNSIGNED)
        WHEN r.redirect_redirect__uri LIKE 'entity:node/%'
            THEN CAST(SUBSTRING(r.redirect_redirect__uri, 13) AS UNSIGNED)
        ELSE NULL
    END
    AND nfd.default_langcode = 1
WHERE r.redirect_redirect__uri LIKE '%node/%'
ORDER BY r.redirect_source__path
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 5. Detect redirect chains (A -> B -> C)
--    A redirect whose target is itself a source of another redirect
-- -----------------------------------------------------------------------------
SELECT
    r1.rid                                      AS first_rid,
    r1.redirect_source__path                    AS first_source,
    r1.redirect_redirect__uri                   AS first_target,
    r1.status_code                              AS first_status,
    r2.rid                                      AS second_rid,
    r2.redirect_source__path                    AS second_source,
    r2.redirect_redirect__uri                   AS final_target,
    r2.status_code                              AS second_status
FROM redirect r1
INNER JOIN redirect r2
    ON r2.redirect_source__path = REPLACE(
        REPLACE(r1.redirect_redirect__uri, 'internal:/', ''),
        'entity:node/', 'node/'
    )
ORDER BY r1.redirect_source__path
-- LIMIT 100
;

-- =============================================================================
-- DRUPAL 7  (redirect module, same table name but different column structure)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6. Export all redirects (D7)
--    D7 redirect module uses `source` and `redirect` columns directly
-- -----------------------------------------------------------------------------
-- SELECT
--     r.rid,
--     r.source                                 AS source_path,
--     r.source_options                         AS source_options,
--     r.redirect                               AS redirect_target,
--     r.redirect_options                       AS redirect_options,
--     r.status_code,
--     r.language                               AS langcode,
--     r.type                                   AS redirect_type,
--     r.uid                                    AS created_by_uid,
--     r.access                                 AS last_accessed,
--     r.count                                  AS access_count
-- FROM redirect r
-- ORDER BY r.source
-- -- LIMIT 500
-- ;
