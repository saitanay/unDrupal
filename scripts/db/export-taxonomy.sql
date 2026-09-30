-- =============================================================================
-- export-taxonomy.sql
-- Export taxonomy terms with vocabulary and hierarchy (parent terms)
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- =============================================================================

-- =============================================================================
-- DRUPAL 9+ / 10 / 11
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Vocabulary overview: term counts per vocabulary
-- -----------------------------------------------------------------------------
SELECT
    vid                         AS vocabulary,
    COUNT(*)                    AS term_count
FROM taxonomy_term_field_data
GROUP BY vid
ORDER BY term_count DESC;

-- -----------------------------------------------------------------------------
-- 2. Export all terms with parent hierarchy (D9+)
--    parent_target_id = 0 means root-level term
-- -----------------------------------------------------------------------------
SELECT
    ttfd.tid,
    ttfd.uuid,
    ttfd.vid                                    AS vocabulary,
    ttfd.name,
    ttfd.description__value                     AS description,
    ttfd.description__format                    AS description_format,
    ttfd.weight,
    ttfd.langcode,
    ttfd.status,
    ttfd.default_langcode,
    FROM_UNIXTIME(ttfd.changed)                 AS changed_at,
    -- Parent term (0 = root)
    ttp.parent_target_id                        AS parent_tid,
    parent_term.name                            AS parent_name,
    -- Path alias
    pa.alias                                    AS url_alias
FROM taxonomy_term_field_data ttfd
LEFT JOIN taxonomy_term__parent ttp
    ON ttp.entity_id = ttfd.tid
    AND ttp.langcode = ttfd.langcode
LEFT JOIN taxonomy_term_field_data parent_term
    ON parent_term.tid = ttp.parent_target_id
    AND parent_term.default_langcode = 1
LEFT JOIN path_alias pa
    ON pa.path = CONCAT('/taxonomy/term/', ttfd.tid)
    AND (pa.langcode = ttfd.langcode OR pa.langcode = 'und')
WHERE ttfd.default_langcode = 1
ORDER BY ttfd.vid, ttfd.weight, ttfd.name
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 3. Recursive taxonomy tree (MySQL 8.0+ / MariaDB 10.2+)
--    Builds full term path: "Grandparent > Parent > Child"
-- -----------------------------------------------------------------------------
WITH RECURSIVE term_tree AS (
    -- Root terms (parent = 0)
    SELECT
        ttfd.tid,
        ttfd.vid                                AS vocabulary,
        ttfd.name,
        ttfd.weight,
        0                                       AS depth,
        CAST(ttfd.name AS CHAR(1000))           AS term_path,
        CAST(LPAD(ttfd.weight, 5, '0') AS CHAR(500)) AS sort_path
    FROM taxonomy_term_field_data ttfd
    INNER JOIN taxonomy_term__parent ttp
        ON ttp.entity_id = ttfd.tid
    WHERE ttp.parent_target_id = 0
      AND ttfd.default_langcode = 1

    UNION ALL

    -- Child terms
    SELECT
        child.tid,
        child.vid,
        child.name,
        child.weight,
        tt.depth + 1,
        CONCAT(tt.term_path, ' > ', child.name),
        CONCAT(tt.sort_path, '/', LPAD(child.weight, 5, '0'))
    FROM taxonomy_term_field_data child
    INNER JOIN taxonomy_term__parent ttp
        ON ttp.entity_id = child.tid
    INNER JOIN term_tree tt
        ON tt.tid = ttp.parent_target_id
    WHERE child.default_langcode = 1
      AND tt.depth < 10  -- safety limit
)
SELECT
    tid,
    vocabulary,
    name,
    depth,
    term_path,
    weight
FROM term_tree
ORDER BY vocabulary, sort_path
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Terms referenced by nodes (entity reference fields)
--    Lists all taxonomy_term entity-reference field tables
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'node\_\_field\_%'
  AND table_name IN (
      -- Find tables that have a column ending in _target_id
      -- which reference taxonomy terms. Common patterns:
      -- node__field_tags, node__field_category, etc.
      SELECT DISTINCT table_name
      FROM information_schema.columns
      WHERE table_schema = DATABASE()
        AND column_name LIKE '%_target_id'
        AND table_name LIKE 'node\_\_field\_%'
  )
ORDER BY table_name;

-- =============================================================================
-- DRUPAL 7
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5. Vocabulary overview (D7)
-- -----------------------------------------------------------------------------
-- SELECT
--     v.name                   AS vocabulary_name,
--     v.machine_name           AS vocabulary_machine_name,
--     COUNT(td.tid)            AS term_count
-- FROM taxonomy_vocabulary v
-- LEFT JOIN taxonomy_term_data td
--     ON td.vid = v.vid
-- GROUP BY v.vid, v.name, v.machine_name
-- ORDER BY term_count DESC;

-- -----------------------------------------------------------------------------
-- 6. Export all terms with parent hierarchy (D7)
--    D7 uses taxonomy_term_data + taxonomy_term_hierarchy
-- -----------------------------------------------------------------------------
-- SELECT
--     td.tid,
--     td.vid,
--     v.machine_name                           AS vocabulary,
--     td.name,
--     td.description,
--     td.format                                AS description_format,
--     td.weight,
--     -- Parent term (0 = root)
--     th.parent                                AS parent_tid,
--     parent_td.name                           AS parent_name,
--     -- Path alias
--     ua.alias                                 AS url_alias
-- FROM taxonomy_term_data td
-- INNER JOIN taxonomy_vocabulary v
--     ON v.vid = td.vid
-- LEFT JOIN taxonomy_term_hierarchy th
--     ON th.tid = td.tid
-- LEFT JOIN taxonomy_term_data parent_td
--     ON parent_td.tid = th.parent
-- LEFT JOIN url_alias ua
--     ON ua.source = CONCAT('taxonomy/term/', td.tid)
-- ORDER BY v.machine_name, td.weight, td.name
-- -- LIMIT 500
-- ;

-- -----------------------------------------------------------------------------
-- 7. Node-term relationships (D7)
--    D7 stores term references in field_data_field_* or taxonomy_index
-- -----------------------------------------------------------------------------
-- SELECT
--     ti.nid,
--     n.title                                  AS node_title,
--     n.type                                   AS content_type,
--     ti.tid,
--     td.name                                  AS term_name,
--     v.machine_name                           AS vocabulary
-- FROM taxonomy_index ti
-- INNER JOIN node n
--     ON n.nid = ti.nid
-- INNER JOIN taxonomy_term_data td
--     ON td.tid = ti.tid
-- INNER JOIN taxonomy_vocabulary v
--     ON v.vid = td.vid
-- ORDER BY ti.nid, v.machine_name, td.name
-- -- LIMIT 500
-- ;
