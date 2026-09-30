# Drupal Database Schema Reference

## Core Entity Tables

### Node (Content)

Drupal stores content across four tables:

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `node` | Base table. One row per node. | `nid`, `vid` (current revision), `type` (bundle), `uuid`, `langcode` |
| `node_field_data` | Translatable base fields. One row per translation. | `nid`, `vid`, `type`, `langcode`, `title`, `uid`, `status`, `created`, `changed`, `promote`, `sticky`, `default_langcode`, `revision_translation_affected` |
| `node_revision` | Revision base. One row per revision. | `nid`, `vid`, `langcode`, `revision_uid`, `revision_timestamp`, `revision_log` |
| `node_field_revision` | Revision translations. One row per revision per language. | `nid`, `vid`, `type`, `langcode`, `title`, `uid`, `status`, `created`, `changed`, `promote`, `sticky`, `default_langcode`, `revision_translation_affected` |

Primary keys:

```
node:                PRIMARY KEY (nid)
node_field_data:     PRIMARY KEY (nid, langcode)
node_revision:       PRIMARY KEY (vid)
node_field_revision: PRIMARY KEY (nid, vid, langcode)
```

### Taxonomy Term

| Table | Key Columns |
|-------|-------------|
| `taxonomy_term_data` | `tid`, `vid` (revision), `uuid`, `langcode` |
| `taxonomy_term_field_data` | `tid`, `vid`, `name`, `description__value`, `description__format`, `weight`, `changed`, `default_langcode`, `revision_translation_affected` |
| `taxonomy_term_revision` | `tid`, `vid`, `langcode`, `revision_created`, `revision_user`, `revision_log_message` |
| `taxonomy_term_field_revision` | Same columns as `taxonomy_term_field_data` but per revision |

Parent hierarchy is stored in `taxonomy_term__parent`:

```sql
-- target_id = 0 means top-level term
SELECT entity_id, parent_target_id
FROM taxonomy_term__parent;
```

### User

| Table | Key Columns |
|-------|-------------|
| `users` | `uid`, `uuid`, `langcode` |
| `users_field_data` | `uid`, `langcode`, `preferred_langcode`, `preferred_admin_langcode`, `name`, `pass`, `mail`, `timezone`, `status`, `created`, `changed`, `access`, `login`, `init`, `default_langcode` |

No revision tables. Users are not revisionable by default.

### File

| Table | Key Columns |
|-------|-------------|
| `file_managed` | `fid`, `uuid`, `langcode`, `uid`, `filename`, `uri`, `filemime`, `filesize`, `status`, `created`, `changed` |
| `file_usage` | `fid`, `module`, `type`, `id`, `count` |

### Media (D8.5+)

| Table | Key Columns |
|-------|-------------|
| `media` | `mid`, `vid`, `bundle`, `uuid`, `langcode` |
| `media_field_data` | `mid`, `vid`, `bundle`, `langcode`, `name`, `thumbnail__target_id`, `thumbnail__alt`, `thumbnail__title`, `thumbnail__width`, `thumbnail__height`, `uid`, `status`, `created`, `changed`, `default_langcode`, `revision_translation_affected` |
| `media_revision` | `mid`, `vid`, `langcode`, `revision_created`, `revision_user`, `revision_log_message` |
| `media_field_revision` | Same as field_data but per revision |

## Field Storage Pattern

Every configurable field gets two dedicated tables:

```
{entity_type}__field_{name}          -- current data
{entity_type}_revision__field_{name} -- revision data
```

Examples:

```
node__field_body
node_revision__field_body
taxonomy_term__field_icon
taxonomy_term_revision__field_icon
paragraph__field_text
paragraph_revision__field_text
```

### Standard Columns in Field Tables

Every field table has these columns:

| Column | Type | Purpose |
|--------|------|---------|
| `bundle` | varchar | Entity bundle (e.g., `article`, `page`) |
| `deleted` | tinyint | 0 = active, 1 = field deleted but data retained for purge |
| `entity_id` | int unsigned | References the entity's base table PK |
| `revision_id` | int unsigned | References the entity's revision table PK |
| `langcode` | varchar(12) | Language of this field value |
| `delta` | int unsigned | Cardinality index (0, 1, 2...) for multi-value fields |
| `field_{name}_value` | varies | The actual field value |

Primary key: `(entity_id, deleted, delta, langcode)` for current tables, `(entity_id, revision_id, deleted, delta, langcode)` for revision tables.

### Example: node__field_body

```sql
CREATE TABLE node__field_body (
  bundle        varchar(128)  NOT NULL DEFAULT '',
  deleted       tinyint(4)    NOT NULL DEFAULT 0,
  entity_id     int unsigned  NOT NULL,
  revision_id   int unsigned  NOT NULL,
  langcode      varchar(32)   NOT NULL DEFAULT '',
  delta         int unsigned  NOT NULL,
  body_value    longtext      NOT NULL,
  body_summary  longtext,
  body_format   varchar(255)
);
```

Note: The `body` field predates the `field_` prefix convention. Its columns are `body_value`, `body_summary`, `body_format` rather than `field_body_value`, `field_body_summary`, `field_body_format`.

## Key System Tables

| Table | Purpose |
|-------|---------|
| `key_value` | Persistent key-value storage. Columns: `collection`, `name`, `value` (serialized PHP). |
| `key_value_expire` | Same as key_value but entries auto-expire. Adds `expire` column. |
| `config` | Active configuration. Columns: `collection`, `name`, `data` (serialized YAML blob). |
| `cache_*` | Cache bins. Tables: `cache_default`, `cache_render`, `cache_data`, `cache_entity`, `cache_discovery`, `cache_config`, `cache_bootstrap`, `cache_menu`, `cache_toolbar`, `cache_page`, `cache_dynamic_page_cache`. Columns: `cid`, `data`, `expire`, `created`, `serialized`, `tags`, `checksum`. |
| `queue` | Job queue. Columns: `item_id`, `name`, `data` (serialized), `expire`, `created`. |
| `sessions` | User sessions. Columns: `uid`, `sid`, `hostname`, `timestamp`, `session`. |
| `watchdog` | Logging (dblog module). Columns: `wid`, `uid`, `type`, `message`, `variables` (serialized), `severity`, `link`, `location`, `referer`, `hostname`, `timestamp`. |
| `sequences` | Auto-increment tracking. Single column: `value`. |
| `batch` | Batch API state. Columns: `bid`, `token`, `timestamp`, `batch` (serialized). |
| `flood` | Rate limiting. Columns: `fid`, `event`, `identifier`, `timestamp`, `expiration`. |
| `semaphore` | Locking. Columns: `name`, `value`, `expire`. |
| `router` | Route definitions. Columns: `name`, `path`, `pattern_outline`, `fit`, `route`, `number_parts`. |

## D7 vs D9+ Schema Differences (Summary)

| Aspect | Drupal 7 | Drupal 9/10/11 |
|--------|----------|----------------|
| Node title | `node.title` | `node_field_data.title` |
| Field tables | `field_data_field_{name}`, `field_revision_field_{name}` | `{entity_type}__field_{name}`, `{entity_type}_revision__field_{name}` |
| Config | `variable` table (serialized PHP) | `config` table (serialized YAML) |
| Taxonomy hierarchy | `taxonomy_term_hierarchy` table | `taxonomy_term__parent` field table |
| URL aliases | `url_alias` (src, dst, language) | `path_alias` entity with base/data/revision tables |
| Files | `file_managed` only | `file_managed` + `media` entities |
| Modules list | `system` table | `core.extension` config |
| Field config | `field_config` + `field_config_instance` tables | `field.storage.*` + `field.field.*` config entities (YAML in config table) |
| UUIDs | Not standard | UUID column on all content entities |
| Revisions | Optional per entity type | Standard on node, media, taxonomy_term, block_content, paragraph |

## Useful Diagnostic Queries

```sql
-- List all field tables for an entity type
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'node__field_%'
ORDER BY table_name;

-- Count content by bundle
SELECT type, COUNT(*) as count
FROM node_field_data
WHERE default_langcode = 1
GROUP BY type
ORDER BY count DESC;

-- Find all field tables and their row counts
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (table_name LIKE '%__field_%' OR table_name LIKE '%_revision__field_%')
ORDER BY table_rows DESC;

-- List all bundles for an entity type
SELECT DISTINCT bundle
FROM node__field_body;
```
