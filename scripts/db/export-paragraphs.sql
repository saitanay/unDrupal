-- =============================================================================
-- export-paragraphs.sql
-- Resolve paragraph entity chains: parent references and nested trees
-- Compatible: MySQL 5.7+ / MariaDB 10.2+
-- Drupal 8/9/10/11 only (Paragraphs module)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overview: paragraph types and counts
-- -----------------------------------------------------------------------------
SELECT
    type                        AS paragraph_type,
    COUNT(*)                    AS total_count
FROM paragraphs_item_field_data
GROUP BY type
ORDER BY total_count DESC;

-- -----------------------------------------------------------------------------
-- 2. All paragraphs with parent context
--    parent_type: entity type of the parent (node, paragraph, etc.)
--    parent_id:   entity ID of the parent
--    parent_field_name: the field on the parent that references this paragraph
-- -----------------------------------------------------------------------------
SELECT
    pifd.id                                     AS paragraph_id,
    pifd.revision_id,
    pifd.type                                   AS paragraph_type,
    pifd.langcode,
    pifd.status,
    pifd.parent_type,
    pifd.parent_id,
    pifd.parent_field_name,
    pifd.behavior_settings,
    FROM_UNIXTIME(pifd.created)                 AS created_at,
    FROM_UNIXTIME(pifd.changed)                 AS changed_at
FROM paragraphs_item_field_data pifd
ORDER BY pifd.parent_type, pifd.parent_id, pifd.parent_field_name, pifd.id
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 3. Paragraphs attached to nodes (most common case)
--    Shows the node title alongside the paragraph for context
-- -----------------------------------------------------------------------------
SELECT
    pifd.id                                     AS paragraph_id,
    pifd.type                                   AS paragraph_type,
    pifd.parent_field_name,
    nfd.nid                                     AS parent_nid,
    nfd.type                                    AS node_type,
    nfd.title                                   AS node_title,
    pifd.langcode,
    pifd.status
FROM paragraphs_item_field_data pifd
INNER JOIN node_field_data nfd
    ON nfd.nid = pifd.parent_id
    AND pifd.parent_type = 'node'
ORDER BY nfd.nid, pifd.parent_field_name, pifd.id
-- LIMIT 500
;

-- -----------------------------------------------------------------------------
-- 4. Nested paragraphs (paragraphs inside paragraphs)
--    Useful for identifying complex nesting
-- -----------------------------------------------------------------------------
SELECT
    child.id                                    AS child_paragraph_id,
    child.type                                  AS child_type,
    child.parent_field_name                     AS parent_field,
    parent.id                                   AS parent_paragraph_id,
    parent.type                                 AS parent_type_name,
    parent.parent_type                          AS grandparent_entity_type,
    parent.parent_id                            AS grandparent_id
FROM paragraphs_item_field_data child
INNER JOIN paragraphs_item_field_data parent
    ON parent.id = child.parent_id
    AND child.parent_type = 'paragraph'
ORDER BY parent.id, child.id
-- LIMIT 200
;

-- -----------------------------------------------------------------------------
-- 5. Recursive paragraph tree (MySQL 8.0+ / MariaDB 10.2+)
--    Walks from top-level (node-attached) paragraphs down through nested children.
--    `depth` and `tree_path` columns help reconstruct the hierarchy.
-- -----------------------------------------------------------------------------
WITH RECURSIVE paragraph_tree AS (
    -- Base case: paragraphs directly attached to a node
    SELECT
        pifd.id                                 AS paragraph_id,
        pifd.type                               AS paragraph_type,
        pifd.parent_type,
        pifd.parent_id,
        pifd.parent_field_name,
        1                                       AS depth,
        CAST(pifd.id AS CHAR(500))              AS tree_path,
        pifd.parent_id                          AS root_node_id
    FROM paragraphs_item_field_data pifd
    WHERE pifd.parent_type = 'node'

    UNION ALL

    -- Recursive: paragraphs whose parent is another paragraph
    SELECT
        child.id                                AS paragraph_id,
        child.type                              AS paragraph_type,
        child.parent_type,
        child.parent_id,
        child.parent_field_name,
        pt.depth + 1                            AS depth,
        CONCAT(pt.tree_path, ' > ', child.id)  AS tree_path,
        pt.root_node_id
    FROM paragraphs_item_field_data child
    INNER JOIN paragraph_tree pt
        ON pt.paragraph_id = child.parent_id
        AND child.parent_type = 'paragraph'
    WHERE pt.depth < 10  -- safety limit
)
SELECT
    pt.root_node_id,
    nfd.title                                   AS node_title,
    nfd.type                                    AS node_type,
    pt.paragraph_id,
    pt.paragraph_type,
    pt.depth,
    pt.tree_path,
    pt.parent_field_name
FROM paragraph_tree pt
LEFT JOIN node_field_data nfd
    ON nfd.nid = pt.root_node_id
ORDER BY pt.root_node_id, pt.tree_path
-- LIMIT 1000
;

-- -----------------------------------------------------------------------------
-- 6. Paragraph field values: discover what field tables exist for paragraphs
--    Run this to see which paragraph__field_* tables to query next
-- -----------------------------------------------------------------------------
SELECT
    table_name,
    table_rows                                  AS approx_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'paragraph\_\_field\_%'
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 7. Example: export a specific paragraph field (e.g., field_text)
--    Adapt the table/column names to your paragraph types
-- -----------------------------------------------------------------------------
-- SELECT
--     pft.entity_id                            AS paragraph_id,
--     pft.field_text_value                     AS text_value,
--     pft.field_text_format                    AS text_format,
--     pifd.type                                AS paragraph_type,
--     pifd.parent_type,
--     pifd.parent_id,
--     pifd.parent_field_name
-- FROM paragraph__field_text pft
-- INNER JOIN paragraphs_item_field_data pifd
--     ON pifd.id = pft.entity_id
-- WHERE pft.deleted = 0
-- ORDER BY pft.entity_id
-- -- LIMIT 200
-- ;
