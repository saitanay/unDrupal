-- =============================================================================
-- export-nodes.sql
-- Export nodes with base fields: title, type, status, author, dates, path alias
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Row count by content type (sanity check before full export)
-- -----------------------------------------------------------------------------
SELECT
    nfd.type                    AS content_type,
    COUNT(*)                    AS total,
    SUM(nfd.status)             AS published,
    COUNT(*) - SUM(nfd.status)  AS unpublished
FROM node_field_data nfd
GROUP BY nfd.type
ORDER BY total DESC;

-- -----------------------------------------------------------------------------
-- Full node export with author and path alias (D9+)
-- -----------------------------------------------------------------------------
SELECT
    n.nid,
    n.uuid,
    nfd.type                                    AS content_type,
    nfd.title,
    nfd.langcode,
    nfd.status                                  AS published,
    nfd.promote,
    nfd.sticky,
    FROM_UNIXTIME(nfd.created)                  AS created_at,
    FROM_UNIXTIME(nfd.changed)                  AS changed_at,
    nfd.default_langcode,
    -- Author info
    ufd.uid                                     AS author_uid,
    ufd.name                                    AS author_name,
    ufd.mail                                    AS author_email,
    -- Path alias (if any)
    pa.alias                                    AS url_alias,
    pa.langcode                                 AS alias_langcode
FROM node n
INNER JOIN node_field_data nfd
    ON nfd.nid = n.nid
LEFT JOIN users_field_data ufd
    ON ufd.uid = nfd.uid
LEFT JOIN path_alias pa
    ON pa.path = CONCAT('/node/', n.nid)
    AND (pa.langcode = nfd.langcode OR pa.langcode = 'und')
WHERE nfd.default_langcode = 1
ORDER BY n.nid
-- LIMIT 100
;

-- -----------------------------------------------------------------------------
-- Nodes with body field (D9+)
-- The body is stored in node__body (or node__field_body on some installs)
-- -----------------------------------------------------------------------------
SELECT
    n.nid,
    nfd.type                                    AS content_type,
    nfd.title,
    nb.body_value                               AS body_html,
    nb.body_summary                             AS summary,
    nb.body_format                              AS text_format,
    FROM_UNIXTIME(nfd.created)                  AS created_at,
    FROM_UNIXTIME(nfd.changed)                  AS changed_at
FROM node n
INNER JOIN node_field_data nfd
    ON nfd.nid = n.nid
LEFT JOIN node__body nb
    ON nb.entity_id = n.nid
    AND nb.deleted = 0
    AND nb.langcode = nfd.langcode
WHERE nfd.default_langcode = 1
ORDER BY n.nid
-- LIMIT 100
;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Row count by content type (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     n.type                   AS content_type,
--     COUNT(*)                 AS total,
--     SUM(n.status)            AS published,
--     COUNT(*) - SUM(n.status) AS unpublished
-- FROM node n
-- GROUP BY n.type
-- ORDER BY total DESC;

-- -----------------------------------------------------------------------------
-- Full node export (D7)
-- D7 stores title, status, created, changed directly on `node` table.
-- Author is joined via `users` table. Path alias via `url_alias`.
-- -----------------------------------------------------------------------------
-- SELECT
--     n.nid,
--     n.type                                   AS content_type,
--     n.title,
--     n.language,
--     n.status                                 AS published,
--     n.promote,
--     n.sticky,
--     FROM_UNIXTIME(n.created)                 AS created_at,
--     FROM_UNIXTIME(n.changed)                 AS changed_at,
--     -- Author
--     u.uid                                    AS author_uid,
--     u.name                                   AS author_name,
--     u.mail                                   AS author_email,
--     -- Path alias
--     ua.alias                                 AS url_alias
-- FROM node n
-- LEFT JOIN users u
--     ON u.uid = n.uid
-- LEFT JOIN url_alias ua
--     ON ua.source = CONCAT('node/', n.nid)
-- ORDER BY n.nid
-- -- LIMIT 100
-- ;

-- -----------------------------------------------------------------------------
-- Nodes with body field (D7)
-- Body is in field_data_body table
-- -----------------------------------------------------------------------------
-- SELECT
--     n.nid,
--     n.type                                   AS content_type,
--     n.title,
--     fdb.body_value                           AS body_html,
--     fdb.body_summary                         AS summary,
--     fdb.body_format                          AS text_format,
--     FROM_UNIXTIME(n.created)                 AS created_at,
--     FROM_UNIXTIME(n.changed)                 AS changed_at
-- FROM node n
-- LEFT JOIN field_data_body fdb
--     ON fdb.entity_id = n.nid
--     AND fdb.entity_type = 'node'
--     AND fdb.deleted = 0
-- ORDER BY n.nid
-- -- LIMIT 100
-- ;
