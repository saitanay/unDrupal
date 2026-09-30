-- =============================================================================
-- export-revisions.sql
-- Export node revisions with metadata and revision author
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: revision counts per content type
-- -----------------------------------------------------------------------------
SELECT
    nfd.type                    AS content_type,
    COUNT(DISTINCT nfd.nid)     AS node_count,
    COUNT(nr.vid)               AS total_revisions,
    ROUND(COUNT(nr.vid) / COUNT(DISTINCT nfd.nid), 1) AS avg_revisions_per_node
FROM node_revision nr
INNER JOIN node_field_data nfd
    ON nfd.nid = nr.nid
    AND nfd.default_langcode = 1
GROUP BY nfd.type
ORDER BY total_revisions DESC;

-- -----------------------------------------------------------------------------
-- 2. Nodes with the most revisions (potential bloat or heavy editing)
-- -----------------------------------------------------------------------------
SELECT
    nr.nid,
    nfd.title,
    nfd.type                    AS content_type,
    COUNT(nr.vid)               AS revision_count,
    MIN(FROM_UNIXTIME(nr.revision_timestamp))   AS first_revision,
    MAX(FROM_UNIXTIME(nr.revision_timestamp))   AS latest_revision
FROM node_revision nr
INNER JOIN node_field_data nfd
    ON nfd.nid = nr.nid
    AND nfd.default_langcode = 1
GROUP BY nr.nid, nfd.title, nfd.type
ORDER BY revision_count DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- 3. Export all revisions with metadata (D9+)
--    node_revision holds the revision timestamp, author, and log message.
--    node_field_revision holds the per-revision field values.
-- -----------------------------------------------------------------------------
SELECT
    nr.nid,
    nr.vid                                      AS revision_id,
    nfd.type                                    AS content_type,
    nfr.title                                   AS revision_title,
    nfr.status                                  AS revision_published,
    nfr.langcode,
    -- Revision metadata
    nr.revision_uid,
    ufd.name                                    AS revision_author,
    FROM_UNIXTIME(nr.revision_timestamp)        AS revision_date,
    nr.revision_log                             AS revision_log_message,
    nr.revision_default                         AS is_current_revision,
    -- Body at this revision (if exists)
    nfrb.body_value                             AS body_html,
    nfrb.body_format                            AS text_format
FROM node_revision nr
INNER JOIN node_field_revision nfr
    ON nfr.nid = nr.nid
    AND nfr.vid = nr.vid
LEFT JOIN node_field_data nfd
    ON nfd.nid = nr.nid
    AND nfd.default_langcode = 1
LEFT JOIN users_field_data ufd
    ON ufd.uid = nr.revision_uid
LEFT JOIN node_revision__body nfrb
    ON nfrb.entity_id = nr.nid
    AND nfrb.revision_id = nr.vid
    AND nfrb.deleted = 0
WHERE nfr.default_langcode = 1
ORDER BY nr.nid, nr.vid
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Revision diff helper: get two adjacent revisions for a node
--    Replace <NID> with the target node ID
-- -----------------------------------------------------------------------------
-- SELECT
--     nr.vid                                   AS revision_id,
--     nfr.title,
--     nfr.status,
--     FROM_UNIXTIME(nr.revision_timestamp)     AS revision_date,
--     nr.revision_log,
--     ufd.name                                 AS revision_author,
--     nfrb.body_value                          AS body_html
-- FROM node_revision nr
-- INNER JOIN node_field_revision nfr
--     ON nfr.nid = nr.nid AND nfr.vid = nr.vid
-- LEFT JOIN users_field_data ufd
--     ON ufd.uid = nr.revision_uid
-- LEFT JOIN node_revision__body nfrb
--     ON nfrb.entity_id = nr.nid
--     AND nfrb.revision_id = nr.vid
--     AND nfrb.deleted = 0
-- WHERE nr.nid = <NID>
--   AND nfr.default_langcode = 1
-- ORDER BY nr.vid DESC
-- LIMIT 2;

-- -----------------------------------------------------------------------------
-- 5. Content moderation states per revision (if workflows module is enabled)
-- -----------------------------------------------------------------------------
-- SELECT
--     cms.content_entity_id                    AS nid,
--     cms.content_entity_revision_id           AS vid,
--     cmsfd.moderation_state                   AS state,
--     cmsfd.uid                                AS state_author_uid,
--     FROM_UNIXTIME(nr.revision_timestamp)     AS revision_date
-- FROM content_moderation_state_field_data cmsfd
-- INNER JOIN content_moderation_state cms
--     ON cms.id = cmsfd.id
-- INNER JOIN node_revision nr
--     ON nr.nid = cms.content_entity_id
--     AND nr.vid = cms.content_entity_revision_id
-- WHERE cms.content_entity_type_id = 'node'
-- ORDER BY cms.content_entity_id, cms.content_entity_revision_id
-- -- LIMIT 500
-- ;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6. Export all node revisions (D7)
--    D7 uses `node_revision` with title, body in `field_revision_body`
-- -----------------------------------------------------------------------------
-- SELECT
--     nr.nid,
--     nr.vid                                   AS revision_id,
--     n.type                                   AS content_type,
--     nr.title                                 AS revision_title,
--     nr.status                                AS revision_published,
--     nr.uid                                   AS revision_author_uid,
--     u.name                                   AS revision_author,
--     FROM_UNIXTIME(nr.timestamp)              AS revision_date,
--     nr.log                                   AS revision_log_message,
--     -- Body at this revision
--     frb.body_value                           AS body_html,
--     frb.body_format                          AS text_format
-- FROM node_revision nr
-- INNER JOIN node n
--     ON n.nid = nr.nid
-- LEFT JOIN users u
--     ON u.uid = nr.uid
-- LEFT JOIN field_revision_body frb
--     ON frb.entity_id = nr.nid
--     AND frb.revision_id = nr.vid
--     AND frb.entity_type = 'node'
-- ORDER BY nr.nid, nr.vid
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 7. Revision count per node (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     n.nid,
--     n.type                                   AS content_type,
--     n.title,
--     COUNT(nr.vid)                            AS revision_count,
--     MIN(FROM_UNIXTIME(nr.timestamp))         AS first_revision,
--     MAX(FROM_UNIXTIME(nr.timestamp))         AS latest_revision
-- FROM node n
-- INNER JOIN node_revision nr
--     ON nr.nid = n.nid
-- GROUP BY n.nid, n.type, n.title
-- ORDER BY revision_count DESC
-- -- LIMIT 50
-- ;
