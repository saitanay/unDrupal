-- =============================================================================
-- export-media-files.sql
-- Export media entities with associated file_managed records
-- Build download URLs from file URIs (public://, private://)
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11  (Media module in core)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Media overview: counts by bundle (image, document, video, etc.)
-- -----------------------------------------------------------------------------
SELECT
    bundle                      AS media_type,
    COUNT(*)                    AS total_count
FROM media_field_data
GROUP BY bundle
ORDER BY total_count DESC;

-- -----------------------------------------------------------------------------
-- 2. File managed overview: files by MIME type
-- -----------------------------------------------------------------------------
SELECT
    filemime,
    COUNT(*)                    AS file_count,
    ROUND(SUM(filesize) / 1024 / 1024, 2) AS total_size_mb
FROM file_managed
GROUP BY filemime
ORDER BY file_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Export media entities with file details (D9+)
--    Covers the core image media type (field_media_image).
--    For other media types, adjust the field table name:
--      - media__field_media_document
--      - media__field_media_video_file
--      - media__field_media_audio_file
--      - media__field_media_oembed_video
-- -----------------------------------------------------------------------------
SELECT
    mfd.mid,
    mfd.uuid,
    mfd.bundle                                  AS media_type,
    mfd.name                                    AS media_name,
    mfd.langcode,
    mfd.status,
    mfd.uid                                     AS author_uid,
    FROM_UNIXTIME(mfd.created)                  AS created_at,
    FROM_UNIXTIME(mfd.changed)                  AS changed_at,
    -- File reference (for image media)
    fmi.field_media_image_target_id              AS file_id,
    fmi.field_media_image_alt                    AS alt_text,
    fmi.field_media_image_title                  AS title_text,
    fmi.field_media_image_width                  AS width,
    fmi.field_media_image_height                 AS height,
    -- File details
    fm.filename,
    fm.uri                                      AS file_uri,
    fm.filemime,
    fm.filesize,
    fm.status                                   AS file_status,
    -- Build a relative download URL from the URI
    -- public://images/photo.jpg => /sites/default/files/images/photo.jpg
    CASE
        WHEN fm.uri LIKE 'public://%'
            THEN CONCAT('/sites/default/files/', SUBSTRING(fm.uri, 10))
        WHEN fm.uri LIKE 'private://%'
            THEN CONCAT('/system/files/', SUBSTRING(fm.uri, 11))
        ELSE fm.uri
    END                                         AS download_path
FROM media_field_data mfd
LEFT JOIN media__field_media_image fmi
    ON fmi.entity_id = mfd.mid
    AND fmi.deleted = 0
LEFT JOIN file_managed fm
    ON fm.fid = fmi.field_media_image_target_id
WHERE mfd.bundle = 'image'
ORDER BY mfd.mid
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 4. Export document media (D9+)
--    Uses media__field_media_document
-- -----------------------------------------------------------------------------
SELECT
    mfd.mid,
    mfd.name                                    AS media_name,
    mfd.bundle                                  AS media_type,
    fmd.field_media_document_target_id           AS file_id,
    fm.filename,
    fm.uri                                      AS file_uri,
    fm.filemime,
    fm.filesize,
    CASE
        WHEN fm.uri LIKE 'public://%'
            THEN CONCAT('/sites/default/files/', SUBSTRING(fm.uri, 10))
        WHEN fm.uri LIKE 'private://%'
            THEN CONCAT('/system/files/', SUBSTRING(fm.uri, 11))
        ELSE fm.uri
    END                                         AS download_path
FROM media_field_data mfd
LEFT JOIN media__field_media_document fmd
    ON fmd.entity_id = mfd.mid
    AND fmd.deleted = 0
LEFT JOIN file_managed fm
    ON fm.fid = fmd.field_media_document_target_id
WHERE mfd.bundle = 'document'
ORDER BY mfd.mid
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 5. All files NOT referenced by any media entity
--    Helps identify orphan files or files referenced directly from nodes
-- -----------------------------------------------------------------------------
SELECT
    fm.fid,
    fm.filename,
    fm.uri,
    fm.filemime,
    fm.filesize,
    fm.status,
    FROM_UNIXTIME(fm.created)                   AS created_at,
    FROM_UNIXTIME(fm.changed)                   AS changed_at,
    CASE
        WHEN fm.uri LIKE 'public://%'
            THEN CONCAT('/sites/default/files/', SUBSTRING(fm.uri, 10))
        WHEN fm.uri LIKE 'private://%'
            THEN CONCAT('/system/files/', SUBSTRING(fm.uri, 11))
        ELSE fm.uri
    END                                         AS download_path
FROM file_managed fm
WHERE fm.fid NOT IN (
    SELECT field_media_image_target_id FROM media__field_media_image WHERE deleted = 0
)
AND fm.fid NOT IN (
    SELECT field_media_document_target_id FROM media__field_media_document WHERE deleted = 0
)
ORDER BY fm.fid
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 6. Discover all media field tables (to find custom media types)
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'media\_\_field\_%'
ORDER BY table_name;

-- =============================================================================
-- DRUPAL 7 (no Media module in core — uses file_managed directly)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 7. Export all managed files (D7)
--    D7 nodes reference files via field_data_field_* tables.
--    The file_managed table is the same.
-- -----------------------------------------------------------------------------
-- SELECT
--     fm.fid,
--     fm.uid,
--     fm.filename,
--     fm.uri,
--     fm.filemime,
--     fm.filesize,
--     fm.status,
--     FROM_UNIXTIME(fm.timestamp)              AS uploaded_at,
--     CASE
--         WHEN fm.uri LIKE 'public://%'
--             THEN CONCAT('/sites/default/files/', SUBSTRING(fm.uri, 10))
--         WHEN fm.uri LIKE 'private://%'
--             THEN CONCAT('/system/files/', SUBSTRING(fm.uri, 11))
--         ELSE fm.uri
--     END                                      AS download_path
-- FROM file_managed fm
-- ORDER BY fm.fid
-- -- LIMIT 200
-- ;

-- -----------------------------------------------------------------------------
-- 8. File usage: which entities reference which files (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     fu.fid,
--     fm.filename,
--     fm.uri,
--     fu.module,
--     fu.type                                  AS entity_type,
--     fu.id                                    AS entity_id,
--     fu.count                                 AS usage_count
-- FROM file_usage fu
-- INNER JOIN file_managed fm
--     ON fm.fid = fu.fid
-- ORDER BY fu.fid
-- -- LIMIT 500
-- ;
