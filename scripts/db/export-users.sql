-- =============================================================================
-- export-users.sql
-- Export user accounts and roles (EXCLUDING password hashes)
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: user counts by status
-- -----------------------------------------------------------------------------
SELECT
    CASE status
        WHEN 1 THEN 'active'
        WHEN 0 THEN 'blocked'
    END                                         AS user_status,
    COUNT(*)                                    AS user_count
FROM users_field_data
GROUP BY status;

-- -----------------------------------------------------------------------------
-- 2. Role overview: how many users per role
-- -----------------------------------------------------------------------------
SELECT
    ur.roles_target_id                          AS role_id,
    COUNT(*)                                    AS user_count
FROM user__roles ur
GROUP BY ur.roles_target_id
ORDER BY user_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Export all users with roles (D9+)
--    IMPORTANT: pass column is intentionally excluded for security
-- -----------------------------------------------------------------------------
SELECT
    ufd.uid,
    ufd.uuid,
    ufd.name                                    AS username,
    ufd.mail                                    AS email,
    -- Deliberately excluded: ufd.pass (password hash)
    ufd.status                                  AS active,
    ufd.langcode,
    ufd.preferred_langcode,
    ufd.preferred_admin_langcode,
    ufd.timezone,
    ufd.default_langcode,
    FROM_UNIXTIME(ufd.created)                  AS created_at,
    FROM_UNIXTIME(ufd.changed)                  AS changed_at,
    FROM_UNIXTIME(ufd.access)                   AS last_access,
    FROM_UNIXTIME(ufd.login)                    AS last_login,
    ufd.init                                    AS initial_email,
    -- Roles aggregated into a comma-separated list
    GROUP_CONCAT(
        ur.roles_target_id
        ORDER BY ur.roles_target_id
        SEPARATOR ', '
    )                                           AS roles
FROM users_field_data ufd
LEFT JOIN user__roles ur
    ON ur.entity_id = ufd.uid
WHERE ufd.uid > 0  -- Exclude anonymous user (uid=0)
GROUP BY
    ufd.uid, ufd.uuid, ufd.name, ufd.mail,
    ufd.status, ufd.langcode, ufd.preferred_langcode,
    ufd.preferred_admin_langcode, ufd.timezone,
    ufd.default_langcode, ufd.created, ufd.changed,
    ufd.access, ufd.login, ufd.init
ORDER BY ufd.uid
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Users with a specific role (D9+)
-- -----------------------------------------------------------------------------
SELECT
    ufd.uid,
    ufd.name                                    AS username,
    ufd.mail                                    AS email,
    ufd.status                                  AS active,
    ur.roles_target_id                          AS role
FROM users_field_data ufd
INNER JOIN user__roles ur
    ON ur.entity_id = ufd.uid
WHERE ur.roles_target_id = 'administrator'
   -- Change 'administrator' to any role machine name
ORDER BY ufd.uid
-- LIMIT 100
;

-- -----------------------------------------------------------------------------
-- 5. Users with custom profile fields (D9+)
--    Discover which user__field_* tables exist first
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'user\_\_field\_%'
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 6. Path aliases for user profiles (D9+)
-- -----------------------------------------------------------------------------
SELECT
    ufd.uid,
    ufd.name                                    AS username,
    pa.alias                                    AS profile_alias
FROM users_field_data ufd
INNER JOIN path_alias pa
    ON pa.path = CONCAT('/user/', ufd.uid)
ORDER BY ufd.uid
-- LIMIT 200
;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 7. Export all users with roles (D7)
--    D7 uses `users` table + `users_roles` + `role` tables
--    IMPORTANT: pass column is intentionally excluded
-- -----------------------------------------------------------------------------
-- SELECT
--     u.uid,
--     u.name                                   AS username,
--     u.mail                                   AS email,
--     -- Deliberately excluded: u.pass (password hash)
--     u.status                                 AS active,
--     u.language,
--     u.timezone,
--     FROM_UNIXTIME(u.created)                 AS created_at,
--     FROM_UNIXTIME(u.access)                  AS last_access,
--     FROM_UNIXTIME(u.login)                   AS last_login,
--     u.init                                   AS initial_email,
--     u.picture                                AS picture_fid,
--     -- Roles
--     GROUP_CONCAT(
--         r.name
--         ORDER BY r.name
--         SEPARATOR ', '
--     )                                        AS roles
-- FROM users u
-- LEFT JOIN users_roles ur
--     ON ur.uid = u.uid
-- LEFT JOIN role r
--     ON r.rid = ur.rid
-- WHERE u.uid > 0
-- GROUP BY
--     u.uid, u.name, u.mail, u.status,
--     u.language, u.timezone, u.created,
--     u.access, u.login, u.init, u.picture
-- ORDER BY u.uid
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 8. User picture files (D7)
--    D7 stores user pictures as file IDs in the users.picture column
-- -----------------------------------------------------------------------------
-- SELECT
--     u.uid,
--     u.name                                   AS username,
--     fm.fid,
--     fm.filename,
--     fm.uri                                   AS file_uri,
--     CASE
--         WHEN fm.uri LIKE 'public://%'
--             THEN CONCAT('/sites/default/files/', SUBSTRING(fm.uri, 10))
--         ELSE fm.uri
--     END                                      AS picture_url
-- FROM users u
-- INNER JOIN file_managed fm
--     ON fm.fid = u.picture
-- WHERE u.uid > 0
--   AND u.picture > 0
-- ORDER BY u.uid
-- -- LIMIT 200
-- ;
