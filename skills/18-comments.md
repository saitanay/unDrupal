# Skill 18: Comments Export

Export comment data, threading hierarchy, comment type definitions, and per-bundle comment field settings. Produces a complete dataset of user discussion attached to content, ready for import into any target platform's comment or discussion system.

Run Skill 01 (Site Audit) first. You need the Drupal version and available access methods.

---

## What Gets Exported

### Comment Types (D8+)

Drupal 8 introduced comment types as config entities. Each type targets a single entity type. A site can have multiple comment types (e.g., `comment` for nodes, `media_comment` for media entities).

| Property | Source |
|---|---|
| Machine name | `id` in `comment.type.{name}.yml` |
| Label | `label` key |
| Target entity type | `target_entity_type_id` (usually `node`) |
| Description | `description` key |

D7 has no comment types. All comments target nodes and share one schema.

### Per Comment

| Property | D7 source | D8+ source |
|---|---|---|
| Comment ID | `comment.cid` | `comment_field_data.cid` |
| UUID | N/A (D7 has no UUID) | `comment_field_data.uuid` |
| Comment type | N/A | `comment_field_data.comment_type` |
| Target entity type | Always `node` | `comment_field_data.entity_type` |
| Target entity ID | `comment.nid` | `comment_field_data.entity_id` |
| Field name | N/A | `comment_field_data.field_name` (the entity reference field on the host entity) |
| Subject | `comment.subject` | `comment_field_data.subject` |
| Body | `field_data_comment_body.comment_body_value` | `comment__comment_body.comment_body_value` |
| Text format | `field_data_comment_body.comment_body_format` | `comment__comment_body.comment_body_format` |
| Author UID | `comment.uid` (0 = anonymous) | `comment_field_data.uid` (0 = anonymous) |
| Anonymous name | `comment.name` | `comment_field_data.name` |
| Anonymous email | `comment.mail` | `comment_field_data.mail` |
| Anonymous homepage | `comment.homepage` | `comment_field_data.homepage` |
| Created timestamp | `comment.created` | `comment_field_data.created` |
| Changed timestamp | `comment.changed` | `comment_field_data.changed` |
| Status | `comment.status` (0 = published, 1 = unpublished in D7) | `comment_field_data.status` (1 = published, 0 = unpublished in D8+) |
| Thread | `comment.thread` | `comment_field_data.thread` |
| Parent comment ID | `comment.pid` (0 = top-level) | `comment_field_data.pid` (0 or NULL = top-level) |
| Hostname / IP | `comment.hostname` | `comment_field_data.hostname` |
| Language | N/A (D7 uses `comment.language`) | `comment_field_data.langcode` |

**Status values flipped between D7 and D8+.** In D7, `status = 0` means published and `status = 1` means unpublished. D8+ reversed this: `status = 1` means published, `status = 0` means unpublished. Account for this during export.

### Comment Field Settings per Content Type

Each content type (or entity bundle) that accepts comments has a comment reference field attached. The field instance config controls comment behavior for that bundle.

**D8+ config** (`field.field.node.{bundle}.{field_name}.yml`, where field_name is typically `comment`):

| Setting | Values |
|---|---|
| `default_value.0.status` | `0` = hidden, `1` = closed (existing visible, new form hidden), `2` = open |
| `settings.default_mode` | `0` = flat list, `1` = threaded |
| `settings.per_page` | Comments per page (integer, e.g. 50) |
| `settings.form_location` | `0` = separate page, `1` = below comments |
| `settings.anonymous` | `0` = no anonymous comments, `1` = anonymous may post with contact info optional, `2` = anonymous must leave contact info |
| `settings.preview` | `0` = disabled, `1` = optional, `2` = required |

**D7 variables** stored in the `variable` table (per content type, where `{type}` is the machine name):

| Variable | Values |
|---|---|
| `comment_{type}` | `0` = hidden, `1` = closed, `2` = open |
| `comment_default_mode_{type}` | `0` = flat, `1` = threaded |
| `comment_default_per_page_{type}` | Integer |
| `comment_anonymous_{type}` | `0` = none, `1` = optional contact, `2` = required contact |
| `comment_form_location_{type}` | `0` = separate page, `1` = below comments |
| `comment_preview_{type}` | `0` = disabled, `1` = optional, `2` = required |
| `comment_subject_field_{type}` | `0` = no subject, `1` = subject field shown |

### Custom Fields on Comments

Comments are fieldable entities. Any field type that attaches to nodes can also attach to comments. Common examples: file attachments, vote/rating fields, or profile-link fields.

D8+ stores custom comment fields the same way as any entity field:
- `field.storage.comment.field_{name}.yml` for the storage definition
- `field.field.comment.{comment_type}.field_{name}.yml` for the instance on a comment type
- Database table `comment__field_{name}` for values

D7 uses the generic Field API tables:
- `field_data_field_{name}` with `entity_type = 'comment'`
- `field_revision_field_{name}` with `entity_type = 'comment'`

Export custom comment fields using the same approach as Skill 4 (Content Types and Fields). Filter by `entity_type = 'comment'`.

---

## Drupal's Threading System

The `thread` column encodes comment hierarchy as a sortable string. Understanding this format is necessary to rebuild threaded discussions on the target platform.

### Format

Every thread value ends with a `/` character. The segments between dots represent nesting depth. Each segment is a vancode number: a base-36 encoded value padded to two characters.

| Comment position | thread value |
|---|---|
| First top-level comment | `01/` |
| Second top-level comment | `02/` |
| First reply to first comment | `01.00/` |
| Second reply to first comment | `01.01/` |
| Reply to first reply of first comment | `01.00.00/` |
| Third top-level comment | `03/` |

### How vancode works

Vancode encodes integers into a sortable string. It uses characters `0-9` then `a-z` to represent values 0-35. For values beyond 35, it prefixes with a length indicator. In practice, most sites never exceed two-character segments.

Segment `00` = first child, `01` = second child, `09` = tenth child, `0a` = eleventh child, `0z` = thirty-sixth child, `10` = thirty-seventh child.

### Sorting for display

To produce a threaded display order, sort by the thread column after stripping the trailing slash:

```sql
-- D7 or D8+: threaded display order
ORDER BY SUBSTRING(thread, 1, LENGTH(thread) - 1)
```

This gives a depth-first traversal. Every reply sorts immediately after its parent, before the next sibling.

### Reconstructing parent-child from thread

The `pid` column is the direct source of parent-child relationships. Use `pid`, not `thread`, to build the reply tree. The `thread` column's purpose is sort order, not hierarchy. But if `pid` data is missing or corrupt, you can derive the parent from the thread value: strip the last `.XX` segment to get the parent's thread value, then look up the comment with that thread.

---

## Access Method 1: JSON:API (D8+)

### Fetch Comment Types

```
GET /jsonapi/comment_type/comment_type
```

### Fetch Comments by Type

```
GET /jsonapi/comment/{comment_type}?include=uid&sort=created
```

Replace `{comment_type}` with the machine name (e.g., `comment`). The endpoint returns all fields including `subject`, `created`, `changed`, `status`, `thread`, `entity_type`, `entity_id`, `field_name`.

Include the author:

```
GET /jsonapi/comment/comment?include=uid&fields[user--user]=name,mail
```

Include the comment body:

```
GET /jsonapi/comment/comment?include=uid&fields[comment--comment]=subject,comment_body,created,changed,status,thread,pid,entity_type,entity_id
```

### Pagination

JSON:API paginates by default (50 items). Follow `links.next` to crawl all comments:

```
GET /jsonapi/comment/comment?page[limit]=50&page[offset]=0
```

### Filtering

Filter by target entity:

```
GET /jsonapi/comment/comment?filter[entity_id.id]={node_uuid}&filter[entity_type]=node
```

Filter by status:

```
GET /jsonapi/comment/comment?filter[status]=1
```

### Gotchas

- Anonymous comment author data (`name`, `mail`, `homepage`) appears as direct attributes, not as a `uid` relationship.
- The `pid` field references the parent comment entity. In JSON:API output, it appears as a relationship. Include it explicitly if needed: `?include=pid`.
- Comment access control applies. The API user needs `access comments` and `administer comments` permissions to see unpublished comments.
- JSON:API does not expose D7 sites unless the `jsonapi` contrib module is installed (rare).

---

## Access Method 2: Drush

### Count Comments

```bash
drush sql:query "SELECT COUNT(*) FROM comment_field_data"
# D7
drush sql:query "SELECT COUNT(*) FROM comment"
```

### Export All Comments (D8+)

```bash
drush sql:query "
  SELECT
    cfd.cid,
    cfd.uuid,
    cfd.comment_type,
    cfd.entity_type,
    cfd.entity_id,
    cfd.field_name,
    cfd.pid,
    cfd.uid,
    cfd.subject,
    cfd.name AS anon_name,
    cfd.mail AS anon_mail,
    cfd.homepage AS anon_homepage,
    cfd.created,
    cfd.changed,
    cfd.status,
    cfd.thread,
    cfd.langcode,
    cb.comment_body_value,
    cb.comment_body_format
  FROM comment_field_data cfd
  LEFT JOIN comment__comment_body cb
    ON cb.entity_id = cfd.cid
    AND cb.langcode = cfd.langcode
  ORDER BY SUBSTRING(cfd.thread, 1, LENGTH(cfd.thread) - 1)
" --extra-dump
```

### Export All Comments (D7)

```bash
drush sql:query "
  SELECT
    c.cid,
    c.pid,
    c.nid,
    c.uid,
    c.subject,
    c.name AS anon_name,
    c.mail AS anon_mail,
    c.homepage AS anon_homepage,
    c.hostname,
    c.created,
    c.changed,
    c.status,
    c.thread,
    c.language,
    cb.comment_body_value,
    cb.comment_body_format
  FROM comment c
  LEFT JOIN field_data_comment_body cb
    ON cb.entity_id = c.cid
    AND cb.entity_type = 'comment'
  ORDER BY c.nid, SUBSTRING(c.thread, 1, LENGTH(c.thread) - 1)
"
```

### Export Comment Field Settings (D8+)

```bash
# List all comment type configs
drush config:list --prefix=comment.type --format=list

# Export a specific comment type
drush config:get comment.type.comment --format=yaml

# List all comment field instances on nodes
drush config:list --prefix=field.field.node --format=list | grep comment
```

### Export Comment Field Settings (D7)

```bash
drush sql:query "
  SELECT name, value FROM variable
  WHERE name LIKE 'comment_%'
  ORDER BY name
"
```

Each `value` is PHP-serialized. Unserialize to get the actual setting.

### Export Custom Fields on Comments

```bash
# D8+: list field storage definitions for comments
drush config:list --prefix=field.storage.comment --format=list

# D8+: list field instances per comment type
drush config:list --prefix=field.field.comment --format=list

# D8+: export a specific custom field's values
drush sql:query "SELECT * FROM comment__field_rating LIMIT 10"
```

---

## Access Method 3: Database Direct

### D8+ Schema

**comment_field_data** (main comment entity table):

| Column | Type | Notes |
|---|---|---|
| cid | int | Primary key |
| comment_type | varchar(32) | References `comment.type.*.yml` |
| uuid | varchar(128) | |
| langcode | varchar(12) | |
| pid | int | Parent comment ID. 0 or NULL = top-level |
| entity_id | int | ID of the host entity (node, media, etc.) |
| entity_type | varchar(32) | Host entity type (`node`, `media`, etc.) |
| field_name | varchar(32) | Field on host entity that holds this comment reference |
| uid | int | Author user ID. 0 = anonymous |
| subject | varchar(64) | |
| name | varchar(60) | Anonymous author name |
| mail | varchar(254) | Anonymous author email |
| homepage | varchar(255) | Anonymous author homepage URL |
| hostname | varchar(128) | IP address |
| created | int | Unix timestamp |
| changed | int | Unix timestamp |
| status | tinyint | 1 = published, 0 = unpublished |
| thread | varchar(255) | Threading sort string |
| default_langcode | tinyint | 1 if this is the original language |

**comment__comment_body** (body field values):

| Column | Type |
|---|---|
| bundle | varchar(128) |
| entity_id | int (cid) |
| revision_id | int |
| langcode | varchar(32) |
| delta | int |
| comment_body_value | longtext |
| comment_body_format | varchar(255) |

**Custom field tables** follow the pattern `comment__field_{name}` with the same structure: `bundle`, `entity_id`, `revision_id`, `langcode`, `delta`, plus field-specific value columns.

### D7 Schema

**comment** (single table for all comment data):

| Column | Type | Notes |
|---|---|---|
| cid | int | Primary key |
| pid | int | Parent comment ID. 0 = top-level |
| nid | int | Node ID the comment is attached to |
| uid | int | Author user ID. 0 = anonymous |
| subject | varchar(64) | |
| hostname | varchar(128) | IP address |
| created | int | Unix timestamp |
| changed | int | Unix timestamp |
| status | int | **0 = published, 1 = unpublished** (reversed from D8+) |
| thread | varchar(255) | Threading sort string |
| name | varchar(60) | Anonymous author display name |
| mail | varchar(64) | Anonymous author email |
| homepage | varchar(255) | Anonymous author homepage URL |
| language | varchar(12) | Language code (empty string if monolingual) |

**field_data_comment_body**:

| Column | Type |
|---|---|
| entity_type | varchar(128) (always `comment`) |
| bundle | varchar(128) |
| entity_id | int (cid) |
| revision_id | int |
| language | varchar(32) |
| delta | int |
| comment_body_value | longtext |
| comment_body_format | varchar(255) |

**D7 node comment statistics**: The `node_comment_statistics` table tracks per-node comment counts and the last comment timestamp. Useful for validating completeness:

```sql
SELECT nid, cid AS last_comment_id, last_comment_timestamp,
       last_comment_name, last_comment_uid, comment_count
FROM node_comment_statistics
WHERE comment_count > 0
ORDER BY comment_count DESC;
```

### Full Export Queries

**D8+ with author usernames:**

```sql
SELECT
  cfd.cid,
  cfd.uuid,
  cfd.comment_type,
  cfd.entity_type,
  cfd.entity_id,
  cfd.field_name,
  cfd.pid,
  cfd.uid,
  u.name AS author_username,
  cfd.subject,
  cfd.name AS anon_name,
  cfd.mail AS anon_mail,
  cfd.homepage AS anon_homepage,
  cfd.created,
  cfd.changed,
  cfd.status,
  cfd.thread,
  cfd.langcode,
  cb.comment_body_value,
  cb.comment_body_format
FROM comment_field_data cfd
LEFT JOIN users_field_data u ON u.uid = cfd.uid
LEFT JOIN comment__comment_body cb
  ON cb.entity_id = cfd.cid
  AND cb.langcode = cfd.langcode
ORDER BY cfd.entity_type, cfd.entity_id,
  SUBSTRING(cfd.thread, 1, LENGTH(cfd.thread) - 1);
```

**D7 with author usernames:**

```sql
SELECT
  c.cid,
  c.pid,
  c.nid,
  c.uid,
  u.name AS author_username,
  c.subject,
  c.name AS anon_name,
  c.mail AS anon_mail,
  c.homepage AS anon_homepage,
  c.hostname,
  c.created,
  c.changed,
  c.status,
  c.thread,
  c.language,
  cb.comment_body_value,
  cb.comment_body_format
FROM comment c
LEFT JOIN users u ON u.uid = c.uid
LEFT JOIN field_data_comment_body cb
  ON cb.entity_id = c.cid
  AND cb.entity_type = 'comment'
ORDER BY c.nid, SUBSTRING(c.thread, 1, LENGTH(c.thread) - 1);
```

### Export Custom Comment Fields

```sql
-- D8+: find all custom field tables for comments
SELECT table_name FROM information_schema.tables
WHERE table_name LIKE 'comment__field_%'
ORDER BY table_name;

-- D7: find all field data tables that contain comment data
SELECT DISTINCT field_name FROM field_config_instance
WHERE entity_type = 'comment'
ORDER BY field_name;
```

For each custom field, export its values joined to the comment:

```sql
-- D8+ example: a custom "rating" field
SELECT cfd.cid, cfd.entity_id, cr.field_rating_value
FROM comment_field_data cfd
JOIN comment__field_rating cr ON cr.entity_id = cfd.cid
ORDER BY cfd.cid;

-- D7 example: a custom "rating" field
SELECT c.cid, c.nid, fr.field_rating_value
FROM comment c
JOIN field_data_field_rating fr
  ON fr.entity_id = c.cid
  AND fr.entity_type = 'comment'
ORDER BY c.cid;
```

---

## Access Method 4: Config YAML (D8+)

Config files define comment types and field settings. They do not contain comment data (that lives in the database).

### Comment Type Definitions

File: `config/sync/comment.type.{machine_name}.yml`

```yaml
uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
langcode: en
status: true
dependencies:
  module:
    - node
id: comment
label: 'Default comments'
target_entity_type_id: node
description: 'Allows commenting on content.'
```

List all comment types:

```bash
ls config/sync/comment.type.*.yml
```

### Comment Field Storage

File: `config/sync/field.storage.node.comment.yml` (or whatever the field name is)

```yaml
uuid: b2c3d4e5-f678-9012-bcde-f12345678901
langcode: en
status: true
dependencies:
  module:
    - comment
id: node.comment
field_name: comment
entity_type: node
type: comment
settings:
  comment_type: comment
module: comment
locked: false
cardinality: 1
translatable: true
```

### Comment Field Instance per Bundle

File: `config/sync/field.field.node.{bundle}.comment.yml`

```yaml
uuid: c3d4e5f6-7890-1234-cdef-123456789012
langcode: en
status: true
dependencies:
  config:
    - comment.type.comment
    - field.storage.node.comment
    - node.type.article
  module:
    - comment
id: node.article.comment
field_name: comment
entity_type: node
bundle: article
label: Comments
description: ''
required: false
translatable: true
default_value:
  - status: 2
    cid: 0
    last_comment_timestamp: 0
    last_comment_name: null
    last_comment_uid: 0
    comment_count: 0
settings:
  default_mode: 1
  per_page: 50
  anonymous: 0
  form_location: true
  preview: 1
```

The `default_value.0.status` field controls whether comments are open:
- `0` = hidden (comment form and existing comments suppressed)
- `1` = closed (existing comments shown, no new submissions)
- `2` = open

The `settings` block controls display and posting rules for this bundle.

### Custom Fields on Comment Types

```bash
ls config/sync/field.storage.comment.field_*.yml
ls config/sync/field.field.comment.*.field_*.yml
```

---

## Export Procedure

### Step 1: Identify Comment Types

**D8+:**

```bash
# Config
ls config/sync/comment.type.*.yml

# Or Drush
drush config:list --prefix=comment.type --format=list

# Or database
SELECT DISTINCT comment_type FROM comment_field_data;
```

**D7:** Skip this step. There is one implicit comment type targeting nodes.

### Step 2: Export Comment Type Definitions (D8+)

For each comment type, capture:
- Machine name, label, target entity type
- Description

```bash
for ct in $(drush config:list --prefix=comment.type --format=list); do
  drush config:get "$ct" --format=yaml
done
```

### Step 3: Export Comment Field Settings per Bundle

**D8+:**

```bash
# Find all comment field instances
for cfg in $(drush config:list --prefix=field.field --format=list | grep '\.comment'); do
  echo "--- $cfg ---"
  drush config:get "$cfg" --format=yaml
done
```

**D7:**

```sql
SELECT name, value FROM variable
WHERE name LIKE 'comment_%'
ORDER BY name;
```

Unserialize each value. Group by content type suffix.

### Step 4: Export Comment Data

Run the full export query from Access Method 3 (database) or paginate through JSON:API.

For large sites (100k+ comments), export in batches:

```sql
-- D8+ batched export
SELECT ... FROM comment_field_data cfd
LEFT JOIN comment__comment_body cb ON cb.entity_id = cfd.cid
WHERE cfd.cid > {last_cid}
ORDER BY cfd.cid
LIMIT 10000;
```

### Step 5: Export Custom Comment Fields

Check for custom fields:

```bash
# D8+
drush config:list --prefix=field.storage.comment.field_ --format=list

# D7
drush sql:query "SELECT DISTINCT field_name FROM field_config_instance WHERE entity_type = 'comment'"
```

For each custom field found, export its values using the queries from Access Method 3.

### Step 6: Validate Counts

```sql
-- D8+: total comments per type
SELECT comment_type, status, COUNT(*) as cnt
FROM comment_field_data
GROUP BY comment_type, status
ORDER BY comment_type, status;

-- D7: total comments per status
SELECT status, COUNT(*) as cnt FROM comment GROUP BY status;

-- D7: validate against node_comment_statistics
SELECT SUM(comment_count) FROM node_comment_statistics;
```

Compare the total from `node_comment_statistics` (D7) against the actual row count in the `comment` table. Mismatches indicate orphaned comments or stale statistics.

### Step 7: Validate Threading Integrity

```sql
-- Find comments with pid pointing to a non-existent parent (D8+)
SELECT c.cid, c.pid
FROM comment_field_data c
LEFT JOIN comment_field_data p ON p.cid = c.pid
WHERE c.pid > 0 AND p.cid IS NULL;

-- Same check for D7
SELECT c.cid, c.pid
FROM comment c
LEFT JOIN comment c2 ON c2.cid = c.pid
WHERE c.pid > 0 AND c2.cid IS NULL;
```

Orphaned child comments (parent deleted but child remains) are common. Decide whether to re-parent them as top-level or discard them.

---

## Mapping to Target Platforms

### Flat comment systems (WordPress, Ghost, most blog platforms)

Strip threading. Keep `pid` as a `parent_id` reference if the target supports single-level replies. Flatten deeper nesting by prepending "@parentauthor" to the body text or dropping the nesting.

Map fields:
- `cid` to target comment ID
- `entity_id` / `nid` to the target post ID
- `uid` to the target user ID (requires user migration first)
- `name` / `mail` / `homepage` to anonymous commenter fields
- `comment_body_value` to comment content (strip or convert text format markup)
- `created` to comment date
- `status` to approved/pending (watch the D7 inversion)

### Threaded systems (Discourse, custom forums)

Use `pid` to build the reply tree. The `thread` column provides sort order within that tree. If the target supports arbitrary nesting, reconstruct the full hierarchy from `pid` chains. If the target limits nesting depth, flatten deeper levels.

### Disqus, Commento, or external comment services

Most external services accept a flat import with optional `parent_id`. Export `cid`, `pid`, body, author info, timestamp. The external service handles rendering and threading.

### Static site generators (Hugo, Gatsby, Astro)

Comments need a third-party service or a flat-file format. Export each comment as a data file (JSON or YAML) keyed by the content path or slug. Include the `pid` for targets that support client-side threading (e.g., Staticman, utterances).

---

## Edge Cases

**Anonymous comments with uid 0.** The `name`, `mail`, and `homepage` columns hold the anonymous author's self-reported identity. These may be empty. Do not attempt to look up uid 0 in the users table; it maps to a placeholder "Anonymous" user.

**Comments on deleted content.** Drupal does not cascade-delete comments when a node is deleted (by default). The `comment_field_data.entity_id` may reference a non-existent entity. Check for orphans:

```sql
-- D8+: comments pointing to deleted nodes
SELECT cfd.cid, cfd.entity_id
FROM comment_field_data cfd
LEFT JOIN node n ON n.nid = cfd.entity_id
WHERE cfd.entity_type = 'node' AND n.nid IS NULL;
```

**Multilingual comments.** D8+ stores translations in `comment_field_data` with different `langcode` rows for the same `cid`. Group by `cid` and export all language variants.

**Empty subject lines.** D8+ sites often hide the subject field. The column may contain auto-generated subjects (truncated body text) or be blank. Do not assume every comment has a meaningful subject.

**Hostname / IP data.** The `hostname` column stores the commenter's IP address. This is personally identifiable information. Consider stripping it during export unless the target platform needs it for spam detection. GDPR and similar regulations may apply.

**Text formats in comment bodies.** The `comment_body_format` column references a text format (e.g., `basic_html`, `full_html`, `plain_text`). Use Skill 7 (Text Formats) to map these formats and convert markup during migration.
