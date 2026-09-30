# Drupal 7 vs Drupal 9/10/11 Schema Differences

This reference covers the structural differences between Drupal 7 and modern Drupal (9, 10, 11). Understanding these differences is critical when building migration tools that must support both versions.

## Entity Storage Architecture

### Drupal 7

Entities use flat tables. Nodes have a single `node` table with all base fields. Fields use a global naming scheme.

```
node                          -- nid, vid, type, language, title, uid, status, created, changed, ...
node_revision                 -- nid, vid, uid, title, log, timestamp, status, comment, promote, sticky
field_data_field_{name}       -- entity_type, bundle, deleted, entity_id, revision_id, language, delta, field_{name}_value
field_revision_field_{name}   -- same structure, one row per revision
```

### Drupal 9+

Entities split base fields across multiple tables. Fields use entity-type-scoped naming.

```
node                          -- nid, vid, type, uuid, langcode
node_field_data               -- nid, vid, type, langcode, title, uid, status, created, changed, promote, sticky, ...
node_revision                 -- nid, vid, langcode, revision_uid, revision_timestamp, revision_log
node_field_revision           -- nid, vid, type, langcode, title, uid, status, created, changed, promote, sticky, ...
node__field_{name}            -- bundle, deleted, entity_id, revision_id, langcode, delta, field_{name}_value
node_revision__field_{name}   -- same structure, one row per revision
```

## Difference Table

| Aspect | Drupal 7 | Drupal 9/10/11 |
|--------|----------|----------------|
| **Node title** | `node.title` | `node_field_data.title` |
| **Node status** | `node.status` | `node_field_data.status` |
| **Node uid** | `node.uid` | `node_field_data.uid` |
| **Node language** | `node.language` (2-char code, `und` for none) | `node.langcode` and `node_field_data.langcode` |
| **UUID** | Not present by default (added by `uuid` contrib) | `node.uuid` on all content entities |
| **Field tables (current)** | `field_data_field_{name}` | `{entity_type}__field_{name}` |
| **Field tables (revision)** | `field_revision_field_{name}` | `{entity_type}_revision__field_{name}` |
| **Field table entity scope** | All entity types share one table per field name | Tables are per entity type. `node__field_tags` and `taxonomy_term__field_tags` are separate tables. |
| **Language column** | `language` | `langcode` |
| **Body field table** | `field_data_body` / `field_revision_body` | `node__body` / `node_revision__body` |
| **Revisions** | `node_revision` stores title, uid, status | `node_revision` stores only vid/nid/langcode. `node_field_revision` stores title, uid, status per revision per language. |

## Taxonomy

### Drupal 7

```
taxonomy_term_data            -- tid, vid (vocabulary ID, not revision), name, description, format, weight
taxonomy_term_hierarchy        -- tid, parent (0 = root)
taxonomy_vocabulary           -- vid, machine_name, name, description, ...
```

`vid` in `taxonomy_term_data` references the vocabulary, not a revision. D7 taxonomy terms are not revisionable.

### Drupal 9+

```
taxonomy_term_data            -- tid, vid (revision ID), uuid, langcode
taxonomy_term_field_data      -- tid, vid, name, description__value, description__format, weight, changed, ...
taxonomy_term_revision        -- tid, vid, langcode, revision_created, revision_user, revision_log_message
taxonomy_term_field_revision  -- tid, vid, name, description__value, ...
taxonomy_term__parent         -- entity_id, parent_target_id (field table format)
```

Vocabulary is a config entity: `taxonomy.vocabulary.{vid}`. The `vid` column in `taxonomy_term_data` is now the revision ID. Vocabulary membership is determined by the bundle column in field tables, not by a vocabulary ID column on the term.

### Migration Watch

```sql
-- D7: Get terms with vocabulary name
SELECT t.tid, t.name, v.machine_name as vocabulary
FROM taxonomy_term_data t
JOIN taxonomy_vocabulary v ON t.vid = v.vid;

-- D9+: Get terms with vocabulary
SELECT t.tid, tfd.name, tfd.vid as revision_id
FROM taxonomy_term_data t
JOIN taxonomy_term_field_data tfd ON t.tid = tfd.tid
WHERE tfd.default_langcode = 1;
-- Bundle is on field tables: SELECT DISTINCT bundle FROM taxonomy_term__parent;
```

## Files and Media

### Drupal 7

No media entity layer. Files are stored in `file_managed` and referenced directly by file or image fields.

```
file_managed                  -- fid, uid, filename, uri, filemime, filesize, status, timestamp
file_usage                    -- fid, module, type, id, count
```

Image fields reference `file_managed.fid` directly:

```
field_data_field_image        -- entity_id, field_image_fid, field_image_alt, field_image_title, field_image_width, field_image_height
```

Note: D7 uses `field_image_fid` while D9+ uses `field_image_target_id`.

### Drupal 9+

Files are wrapped in media entities. Image fields on nodes typically reference media entities, not files directly.

```
file_managed                  -- fid, uuid, langcode, uid, filename, uri, filemime, filesize, status, created, changed
media                         -- mid, vid, bundle, uuid, langcode
media_field_data              -- mid, vid, bundle, name, thumbnail__target_id, uid, status, created, changed, ...
media__field_media_image      -- entity_id (mid), field_media_image_target_id (fid), field_media_image_alt, ...
```

Reference chain: `node → media entity → file entity → physical file`

```sql
-- D9+: Resolve a node's image to its file URI
SELECT fm.uri, fm.filename
FROM node__field_image ni           -- node references media
JOIN media_field_data mfd ON ni.field_image_target_id = mfd.mid
JOIN media__field_media_image mi ON mfd.mid = mi.entity_id
JOIN file_managed fm ON mi.field_media_image_target_id = fm.fid
WHERE ni.entity_id = 42;
```

### Migration Watch

D7 sites without the `media` contrib module have a flat file reference. D7 sites with `media` (1.x or 2.x) have a `file_entity` table or use the `media_entity` module with different table structures than D9+ core media.

## URL Aliases

### Drupal 7

```
url_alias                     -- pid, source, alias, language
```

- `source`: Internal path like `node/123`
- `alias`: URL alias like `about/our-team`
- `language`: Language code or `und`

### Drupal 9+

Path aliases are a content entity with revision support.

```
path_alias                    -- id, revision_id, uuid, langcode
path_alias_revision           -- id, revision_id, path, alias, langcode, status
```

- `path`: Internal path like `/node/123` (note the leading slash, D7 omits it)
- `alias`: URL alias like `/about/our-team` (leading slash)

## Configuration Storage

### Drupal 7

```
variable                      -- name, value (serialized PHP)
system                        -- filename, name, type, owner, status, bootstrap, schema_version, weight, info
```

```sql
-- D7: Get site name
SELECT value FROM variable WHERE name = 'site_name';
-- Returns: s:11:"My Site Name";   (PHP serialized)

-- D7: List enabled modules
SELECT name FROM system WHERE type = 'module' AND status = 1;
```

### Drupal 9+

```
config                        -- collection, name, data (serialized YAML blob)
key_value                     -- collection, name, value (serialized PHP)
```

```sql
-- D9+: Get site name
SELECT data FROM config WHERE name = 'system.site';
-- Returns serialized blob containing 'name' key

-- D9+: List enabled modules
SELECT data FROM config WHERE name = 'core.extension';
-- Returns serialized blob with 'module' key listing all enabled modules with weights
```

Configuration is typically managed as YAML files in the filesystem:

```yaml
# config/sync/system.site.yml
name: 'My Site Name'
mail: admin@example.com
slogan: ''
page:
  front: /node
```

## Field Configuration

### Drupal 7

```
field_config                  -- id, field_name, type, module, active, storage_type, storage_module, locked, data, cardinality, translatable, deleted
field_config_instance         -- id, field_id, field_name, entity_type, bundle, data, deleted
```

Field settings are stored as serialized PHP in the `data` column.

```sql
-- D7: List all fields and their types
SELECT field_name, type, cardinality FROM field_config WHERE deleted = 0;

-- D7: List field instances (which bundles use which fields)
SELECT field_name, entity_type, bundle FROM field_config_instance WHERE deleted = 0;
```

### Drupal 9+

Field storage and instance config are config entities:

```sql
-- D9+: List all field storage definitions
SELECT name FROM config WHERE name LIKE 'field.storage.%';
-- Returns: field.storage.node.field_body, field.storage.node.field_tags, ...

-- D9+: List all field instances
SELECT name FROM config WHERE name LIKE 'field.field.%';
-- Returns: field.field.node.article.field_body, field.field.node.article.field_tags, ...
```

Or from YAML:

```yaml
# field.storage.node.field_tags
id: node.field_tags
field_name: field_tags
entity_type: node
type: entity_reference
cardinality: -1
settings:
  target_type: taxonomy_term

# field.field.node.article.field_tags
id: node.article.field_tags
field_name: field_tags
entity_type: node
bundle: article
field_type: entity_reference
label: Tags
required: false
settings:
  handler: 'default:taxonomy_term'
  handler_settings:
    target_bundles:
      tags: tags
```

## Comment System

### Drupal 7

Comments are their own entity with a flat table. Comment settings live on the node type.

```
comment                       -- cid, pid (parent), nid, uid, subject, hostname, created, changed, status, thread, name, mail, homepage, language
```

### Drupal 9+

Comments are a typed entity. The `comment_type` config entity defines which entity types accept comments.

```
comment                       -- cid, uuid, comment_type, langcode
comment_field_data            -- cid, comment_type, pid, entity_id, entity_type, field_name, uid, subject, name, mail, homepage, hostname, created, changed, status, thread
```

Key difference: D9+ comments reference any entity type via `entity_type` and `entity_id`, not just nodes.

## Block System

### Drupal 7

Custom blocks stored in:

```
block_custom                  -- bid, body, info, format
block                         -- bid, module, delta, theme, status, weight, region, custom, visibility, pages, title, cache
```

### Drupal 9+

Custom blocks are `block_content` entities. Block placement is config (`block.block.{id}`).

## Menu System

### Drupal 7

```
menu_custom                   -- menu_name, title, description
menu_links                    -- mlid, menu_name, plid (parent), link_path, router_path, link_title, options, module, hidden, external, has_children, expanded, weight, depth, customized, p1-p9
```

### Drupal 9+

Menus are config entities (`system.menu.{name}`). Custom menu links are `menu_link_content` entities. System-defined links are plugins, not stored in the database.

## User Roles and Permissions

### Drupal 7

```
role                          -- rid, name, weight
role_permission               -- rid, permission, module
users_roles                   -- uid, rid
```

### Drupal 9+

Roles are config entities (`user.role.{id}`) with permissions embedded:

```yaml
# user.role.editor
id: editor
label: Editor
is_admin: false
permissions:
  - 'access content'
  - 'create article content'
  - 'edit any article content'
```

User role assignments stored in field table: `user__roles`.

## Quick Detection: Which Version?

```sql
-- If this table exists, it's D7
SELECT 1 FROM information_schema.tables WHERE table_name = 'variable' AND table_schema = DATABASE();

-- If this table exists, it's D8+
SELECT 1 FROM information_schema.tables WHERE table_name = 'node_field_data' AND table_schema = DATABASE();

-- D7 field tables start with field_data_
SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'field_data_%' AND table_schema = DATABASE() LIMIT 1;

-- D8+ field tables contain double underscore
SELECT table_name FROM information_schema.tables WHERE table_name LIKE '%__field_%' AND table_schema = DATABASE() LIMIT 1;
```
