-- =============================================================================
-- export-comments.sql
-- Export comments with threading (parent/child) and host entity context
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: comment counts by type and status
-- -----------------------------------------------------------------------------
SELECT
    comment_type                AS comment_bundle,
    CASE status
        WHEN 1 THEN 'published'
        WHEN 0 THEN 'unpublished'
    END                                         AS comment_status,
    COUNT(*)                                    AS total
FROM comment_field_data
GROUP BY comment_type, status
ORDER BY comment_type, status;

-- -----------------------------------------------------------------------------
-- 2. Export all comments with threading and author info (D9+)
--    thread column: materialized path for threading (e.g., "01/01.00/")
--    pid: parent comment ID (0 = top-level)
-- -----------------------------------------------------------------------------
SELECT
    cfd.cid,
    cfd.uuid,
    cfd.comment_type                            AS bundle,
    cfd.langcode,
    cfd.status                                  AS published,
    cfd.subject,
    cfd.name                                    AS author_name_provided,
    cfd.mail                                    AS author_mail_provided,
    cfd.homepage                                AS author_homepage,
    -- Author (registered user)
    cfd.uid                                     AS author_uid,
    ufd.name                                    AS registered_author_name,
    -- Threading
    cfd.pid                                     AS parent_comment_id,
    cfd.thread                                  AS thread_path,
    -- Host entity
    cfd.entity_type                             AS host_entity_type,
    cfd.entity_id                               AS host_entity_id,
    cfd.field_name                              AS host_field,
    -- Timestamps
    FROM_UNIXTIME(cfd.created)                  AS created_at,
    FROM_UNIXTIME(cfd.changed)                  AS changed_at,
    -- Comment body
    cb.comment_body_value                       AS body_html,
    cb.comment_body_format                      AS text_format
FROM comment_field_data cfd
LEFT JOIN users_field_data ufd
    ON ufd.uid = cfd.uid
LEFT JOIN comment__comment_body cb
    ON cb.entity_id = cfd.cid
    AND cb.deleted = 0
    AND cb.langcode = cfd.langcode
WHERE cfd.default_langcode = 1
ORDER BY cfd.entity_type, cfd.entity_id, cfd.thread
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 3. Comments on nodes with node context (D9+)
-- -----------------------------------------------------------------------------
SELECT
    cfd.cid,
    cfd.subject,
    cb.comment_body_value                       AS body_html,
    cfd.status                                  AS published,
    cfd.pid                                     AS parent_comment_id,
    cfd.thread                                  AS thread_path,
    -- Author
    cfd.uid                                     AS author_uid,
    COALESCE(ufd.name, cfd.name)                AS author_name,
    -- Host node
    nfd.nid,
    nfd.type                                    AS content_type,
    nfd.title                                   AS node_title,
    -- Timestamps
    FROM_UNIXTIME(cfd.created)                  AS commented_at,
    FROM_UNIXTIME(cfd.changed)                  AS edited_at
FROM comment_field_data cfd
INNER JOIN node_field_data nfd
    ON nfd.nid = cfd.entity_id
    AND cfd.entity_type = 'node'
LEFT JOIN users_field_data ufd
    ON ufd.uid = cfd.uid
LEFT JOIN comment__comment_body cb
    ON cb.entity_id = cfd.cid
    AND cb.deleted = 0
WHERE cfd.default_langcode = 1
  AND nfd.default_langcode = 1
ORDER BY nfd.nid, cfd.thread
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Comment thread depth analysis (D9+)
--    The thread column uses format "01/", "01/01.00/", "01/01.00/01.00/"
--    Depth = number of "/" segments minus 1
-- -----------------------------------------------------------------------------
SELECT
    cfd.entity_type,
    cfd.entity_id,
    -- Calculate nesting depth from thread
    (LENGTH(cfd.thread) - LENGTH(REPLACE(cfd.thread, '/', ''))) - 1 AS depth,
    COUNT(*)                                    AS comments_at_depth
FROM comment_field_data cfd
WHERE cfd.default_langcode = 1
GROUP BY cfd.entity_type, cfd.entity_id, depth
ORDER BY cfd.entity_type, cfd.entity_id, depth
-- LIMIT 200
;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5. Export all comments (D7)
--    D7 uses a single `comment` table with thread/pid columns
-- -----------------------------------------------------------------------------
-- SELECT
--     c.cid,
--     c.nid,
--     n.title                                  AS node_title,
--     n.type                                   AS content_type,
--     c.subject,
--     -- D7 stores body in field_data_comment_body
--     fcb.comment_body_value                   AS body_html,
--     fcb.comment_body_format                  AS text_format,
--     c.status                                 AS published,
--     c.pid                                    AS parent_comment_id,
--     c.thread                                 AS thread_path,
--     -- Author
--     c.uid                                    AS author_uid,
--     COALESCE(u.name, c.name)                 AS author_name,
--     c.mail                                   AS author_email,
--     c.homepage                               AS author_homepage,
--     -- Language and timestamps
--     c.language                               AS langcode,
--     FROM_UNIXTIME(c.created)                 AS created_at,
--     FROM_UNIXTIME(c.changed)                 AS changed_at
-- FROM comment c
-- INNER JOIN node n
--     ON n.nid = c.nid
-- LEFT JOIN users u
--     ON u.uid = c.uid
-- LEFT JOIN field_data_comment_body fcb
--     ON fcb.entity_id = c.cid
--     AND fcb.entity_type = 'comment'
-- ORDER BY c.nid, c.thread
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 6. Comment counts per node (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     n.nid,
--     n.type                                   AS content_type,
--     n.title,
--     ncs.comment_count,
--     FROM_UNIXTIME(ncs.last_comment_timestamp) AS last_comment_at,
--     ncs.last_comment_name,
--     ncs.last_comment_uid
-- FROM node_comment_statistics ncs
-- INNER JOIN node n
--     ON n.nid = ncs.nid
-- WHERE ncs.comment_count > 0
-- ORDER BY ncs.comment_count DESC
-- -- LIMIT 200
-- ;
