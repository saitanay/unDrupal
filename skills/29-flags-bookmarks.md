# Skill 29: Flags and Bookmarks Export

Export user-flagged content relationships from the Drupal Flag module. Flags track bookmarks, likes, follows, watches, spam reports, and any custom per-user or global boolean relationship between a user and an entity.

Run Skill 01 (Site Audit) first. You need the Drupal version and confirmed access methods.

---

## What You Are Extracting

| Component | Where It Lives | What It Contains |
|---|---|---|
| **Flag definitions** | `flag.flag.*.yml` config (D8+), `flags` table (D7) | Machine name, label, entity type, scope, bundles, flag/unflag text |
| **Flagging records** | `flagging` entity table (D8+), `flagging` table (D7) | Who flagged what, when, with which flag |
| **Flag counts** | `flag_counts` table (D7), computed or cached (D8+) | Per-entity totals for each flag type |

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Drush** | Config export, SQL queries, entity queries |
| **Database** | Direct access to `flagging`, `flag_counts` tables |
| **Config YAML** | Flag type definitions from `flag.flag.*.yml` |
| **JSON:API** | Flagging entities (D9+): `/jsonapi/flagging/{flag_type}` if exposed |

---

## 1. Flag Definitions

A flag definition describes the relationship type. "Bookmark" is a flag. "Like" is a flag. "Report as spam" is a flag. Each flag targets one entity type and optionally restricts to specific bundles.

### 1a. Config YAML (D8 / D9 / D10 / D11)

Flag definitions live in `flag.flag.{machine_name}.yml`. Each file contains the full flag configuration.

```bash
# List all flag config files
find config/sync -name 'flag.flag.*.yml' | sort
```

Parse each file for these fields:

| YAML Key | Meaning |
|---|---|
| `id` | Machine name of the flag (`bookmark`, `like`, `follow`) |
| `label` | Human-readable label |
| `entity_type` | Target entity type: `node`, `user`, `comment`, `taxonomy_term`, etc. |
| `bundles` | Array of bundles this flag applies to. Empty array means all bundles of the entity type. |
| `flag_short` | Text shown on the flag action link ("Bookmark this", "Like") |
| `unflag_short` | Text shown on the unflag action link ("Remove bookmark", "Unlike") |
| `flag_long` | Optional longer description shown on flag confirmation |
| `unflag_long` | Optional longer description shown on unflag confirmation |
| `flag_message` | Confirmation message after flagging |
| `unflag_message` | Confirmation message after unflagging |
| `global` | `true` = one flag state shared by all users. `false` = per-user flag state. |
| `flag_type` | Plugin ID. Typically `entity:{entity_type}` (e.g. `entity:node`). |
| `link_type` | How the flag link renders: `reload`, `ajax_link`, `confirm`, `field_entry` |
| `flagTypeConfig` | Additional settings specific to the flag type plugin |
| `third_party_settings` | Settings from other modules that extend flag behavior |

Example flag config:

```yaml
# flag.flag.bookmark.yml
uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
langcode: en
status: true
dependencies:
  module:
    - node
    - user
id: bookmark
label: Bookmark
entity_type: node
bundles:
  - article
  - page
flag_short: 'Bookmark this'
flag_long: 'Add this content to your bookmarks'
flag_message: 'This item has been bookmarked.'
unflag_short: 'Remove bookmark'
unflag_long: 'Remove this content from your bookmarks'
unflag_message: 'Bookmark removed.'
global: false
flag_type: entity:node
link_type: ajax_link
flagTypeConfig:
  show_as_field: true
  show_on_form: false
  show_contextual_link: false
```

Via Drush:

```bash
# List all flag configs
drush config:list --format=list | grep '^flag.flag\.'

# Export a specific flag definition
drush config:get flag.flag.bookmark --format=yaml

# Export all flag definitions at once
for flag in $(drush config:list --format=list | grep '^flag.flag\.'); do
  echo "---"
  echo "# $flag"
  drush config:get "$flag" --format=yaml
done
```

### 1b. Database (D7)

Drupal 7 stores flag definitions in the `flags` table. The schema differs from D8+.

```sql
SELECT fid,
       content_type AS entity_type,
       name AS machine_name,
       title AS label,
       global,
       options
FROM flags
ORDER BY name;
```

| Column | Meaning |
|---|---|
| `fid` | Numeric flag ID. Foreign key used in `flagging` table. |
| `content_type` | Entity type this flag targets: `node`, `user`, `comment` |
| `name` | Machine name of the flag |
| `title` | Human-readable label |
| `global` | `1` = global (shared), `0` = per-user |
| `options` | PHP-serialized array containing flag/unflag text, link type, roles, bundle restrictions |

Unserialize the `options` column to extract:

```php
$options = unserialize($row['options']);
// $options['flag_short']        — flag link text
// $options['unflag_short']      — unflag link text
// $options['flag_long']         — flag confirmation text
// $options['unflag_long']       — unflag confirmation text
// $options['flag_message']      — post-flag message
// $options['unflag_message']    — post-unflag message
// $options['show_in_links']     — array of view modes
// $options['show_as_field']     — boolean
// $options['show_on_form']      — boolean
// $options['access']['roles']   — array of role IDs that can use this flag
// $options['types']             — array of bundles (e.g. ['article', 'page'])
```

Via Drush (D7):

```bash
drush sql:query "SELECT fid, content_type, name, title, global FROM flags ORDER BY name;"
```

Bundle restrictions in D7 live in a separate table:

```sql
SELECT fc.fid,
       f.name AS flag_name,
       fc.type AS bundle
FROM flag_types fc
JOIN flags f ON f.fid = fc.fid
ORDER BY f.name, fc.type;
```

---

## 2. Flagging Records

Flagging records are the actual data: user X flagged entity Y with flag Z at time T. This is the core export.

### 2a. Database (D9 / D10 / D11)

D8+ stores flaggings as content entities in the `flagging` table. Each row is one flag action.

```sql
SELECT id,
       flag_id,
       entity_type,
       entity_id,
       uid,
       session_id,
       created
FROM flagging
ORDER BY flag_id, created;
```

| Column | Meaning |
|---|---|
| `id` | Primary key (flagging entity ID) |
| `flag_id` | Machine name of the flag definition (e.g. `bookmark`) |
| `entity_type` | Target entity type (`node`, `user`, `comment`, etc.) |
| `entity_id` | Target entity ID |
| `uid` | User who created the flagging. `0` for anonymous (session-based). |
| `session_id` | Session ID for anonymous flaggings. `NULL` for authenticated users. |
| `created` | Unix timestamp when the flag was set |

Get total counts:

```sql
-- Total flaggings per flag type
SELECT flag_id, COUNT(*) AS total
FROM flagging
GROUP BY flag_id
ORDER BY total DESC;

-- Flaggings per flag type per entity type
SELECT flag_id, entity_type, COUNT(*) AS total
FROM flagging
GROUP BY flag_id, entity_type
ORDER BY flag_id, total DESC;
```

Export with human-readable context (join against node titles for node flags):

```sql
SELECT f.id,
       f.flag_id,
       f.entity_type,
       f.entity_id,
       n.title AS entity_title,
       f.uid,
       u.name AS username,
       FROM_UNIXTIME(f.created) AS flagged_at
FROM flagging f
LEFT JOIN node_field_data n
  ON f.entity_type = 'node' AND f.entity_id = n.nid
LEFT JOIN users_field_data u
  ON f.uid = u.uid
ORDER BY f.flag_id, f.created;
```

Via Drush:

```bash
# Count flaggings per type
drush sql:query "SELECT flag_id, COUNT(*) AS total FROM flagging GROUP BY flag_id ORDER BY total DESC;"

# Full export
drush sql:query "SELECT id, flag_id, entity_type, entity_id, uid, session_id, created FROM flagging ORDER BY flag_id, created;" --extra=--batch
```

### 2b. Database (D8)

Same schema as D9+. The `flagging` table structure is identical from Flag 4.x (the D8 version) onward.

```sql
SELECT id, flag_id, entity_type, entity_id, uid, session_id, created
FROM flagging
ORDER BY flag_id, created;
```

### 2c. Database (D7)

D7 uses a `flagging` table with numeric `fid` references instead of machine name strings.

```sql
SELECT fl.flagging_id,
       fl.fid,
       f.name AS flag_name,
       fl.entity_type,
       fl.entity_id,
       fl.uid,
       fl.sid AS session_id,
       fl.timestamp AS created
FROM flagging fl
JOIN flags f ON fl.fid = f.fid
ORDER BY f.name, fl.timestamp;
```

| Column | Meaning |
|---|---|
| `flagging_id` | Primary key |
| `fid` | Numeric foreign key to `flags.fid` |
| `entity_type` | Target entity type |
| `entity_id` | Target entity ID |
| `uid` | User ID. `0` for anonymous. |
| `sid` | Session ID for anonymous flaggings |
| `timestamp` | Unix timestamp |

The `fid` column is numeric. Always join against `flags` to get the machine name. Your export should include the machine name, not the numeric ID.

Counts per flag:

```sql
SELECT f.name AS flag_name,
       fl.entity_type,
       COUNT(*) AS total
FROM flagging fl
JOIN flags f ON fl.fid = f.fid
GROUP BY f.name, fl.entity_type
ORDER BY f.name, total DESC;
```

---

## 3. Flag Counts

Flag counts aggregate the total number of flaggings per entity per flag type. Some target platforms need the count as a denormalized field (e.g. a "likes" integer on a post).

### 3a. D7 Flag Counts

D7's flag module maintains a `flag_counts` table automatically.

```sql
SELECT fc.fid,
       f.name AS flag_name,
       fc.entity_type,
       fc.entity_id,
       fc.count,
       fc.last_updated
FROM flag_counts fc
JOIN flags f ON fc.fid = f.fid
ORDER BY f.name, fc.count DESC;
```

| Column | Meaning |
|---|---|
| `fid` | Numeric flag ID |
| `entity_type` | Target entity type |
| `entity_id` | Target entity ID |
| `count` | Total number of times this entity was flagged with this flag |
| `last_updated` | Unix timestamp of the most recent flagging |

### 3b. D8+ Flag Counts

D8+ Flag module (4.x) stores counts in the `flag_counts` table with the same structure but uses the flag machine name instead of numeric ID.

```sql
SELECT flag_id,
       entity_type,
       entity_id,
       count,
       last_updated
FROM flag_counts
ORDER BY flag_id, count DESC;
```

If the `flag_counts` table does not exist, compute counts from the `flagging` table:

```sql
SELECT flag_id,
       entity_type,
       entity_id,
       COUNT(*) AS count,
       MAX(created) AS last_updated
FROM flagging
GROUP BY flag_id, entity_type, entity_id
ORDER BY flag_id, count DESC;
```

Check if the table exists:

```bash
drush sql:query "SHOW TABLES LIKE 'flag_counts';"
```

---

## 4. Use Case Mapping

Flags carry semantic meaning that differs by use case. Map each flag to its target platform equivalent before migrating.

### Common Flag Patterns

| Flag Pattern | Typical machine_name | Scope | Target Platform Equivalent |
|---|---|---|---|
| Bookmarks / Favorites | `bookmark`, `favorite`, `save` | Per-user | User collection, saved items list, wishlist |
| Likes / Hearts | `like`, `heart`, `upvote` | Per-user | Like count + per-user boolean, reaction system |
| Follow / Subscribe | `follow`, `subscribe`, `watch` | Per-user | Subscription record, notification preference |
| Spam / Abuse report | `spam`, `report`, `abuse` | Per-user | Moderation queue entry, content flag |
| Feature / Promote | `featured`, `promoted`, `sticky` | Global | Boolean field on content, editorial flag |
| Approval / Review | `approved`, `reviewed` | Global | Workflow state, moderation status |

### Mapping Decisions

For each flag definition, decide:

1. **Keep as a relationship?** Bookmarks and follows are user-to-entity relationships. The target platform needs a many-to-many join or a dedicated relationship entity.

2. **Collapse to a count?** Likes often migrate as a single integer field on the target entity. You lose per-user tracking but simplify the data model.

3. **Collapse to a boolean field?** Global flags like "featured" are a boolean on the entity. No user relationship needed.

4. **Map to a workflow state?** Flags used for editorial workflow (approved, reviewed, needs_review) map to content moderation states or status fields.

5. **Drop it?** Session-based anonymous flags, spam reports on already-moderated content, and test flags may not be worth migrating.

Record each decision. The export should include the mapping alongside the data.

---

## 5. JSON:API Access (D9+)

If database access is unavailable, flagging entities may be exposed through JSON:API.

```bash
# Check if flagging entity type is exposed
curl -s 'https://example.com/jsonapi' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key in data.get('links', {}):
    if 'flagging' in key:
        print(key, data['links'][key]['href'])
"
```

If exposed, query flaggings by flag type:

```bash
# Get all bookmark flaggings with pagination
curl -s 'https://example.com/jsonapi/flagging/bookmark?page[limit]=50&sort=created' \
  -H 'Accept: application/vnd.api+json'
```

JSON:API responses include `flag_id`, `entity_type`, `entity_id`, `uid`, and `created` as attributes. Paginate using the `next` link in the response until exhausted.

JSON:API access requires authentication for flagging data. Anonymous users cannot read other users' flaggings. Use a session cookie or OAuth token from an admin account.

---

## 6. Full Export Procedure

### Step 1: Verify Flag Module Presence

```bash
# D8+
drush pm:list --format=json | python3 -c "
import sys, json
modules = json.load(sys.stdin)
for name in ['flag']:
    if name in modules:
        print(f\"{name}: {modules[name]['status']} (v{modules[name].get('version', 'unknown')})\")
    else:
        print(f\"{name}: not installed\")
"
```

```sql
-- D7
SELECT name, status, info FROM system WHERE name = 'flag';
```

If the flag module is not installed, stop. There are no flags to export.

### Step 2: Export Flag Definitions

```bash
# D8+: Export all flag definitions to JSON
drush eval "
  \$flags = \Drupal::entityTypeManager()->getStorage('flag')->loadMultiple();
  \$output = [];
  foreach (\$flags as \$flag) {
    \$output[] = [
      'id' => \$flag->id(),
      'label' => \$flag->label(),
      'entity_type' => \$flag->getFlaggableEntityTypeId(),
      'bundles' => \$flag->getBundles(),
      'global' => \$flag->isGlobal(),
      'flag_short' => \$flag->getShortText('flag'),
      'unflag_short' => \$flag->getShortText('unflag'),
      'link_type' => \$flag->getLinkTypePlugin()->getPluginId(),
    ];
  }
  echo json_encode(\$output, JSON_PRETTY_PRINT);
"
```

### Step 3: Export Flagging Records

Choose the SQL query from Section 2 matching your Drupal version. For large datasets, export in batches:

```bash
# Batch export for large flagging tables (D8+)
BATCH_SIZE=10000
OFFSET=0
while true; do
  RESULT=$(drush sql:query "SELECT id, flag_id, entity_type, entity_id, uid, session_id, created FROM flagging ORDER BY id LIMIT $BATCH_SIZE OFFSET $OFFSET;" --extra=--batch)
  if [ -z "$RESULT" ]; then
    break
  fi
  echo "$RESULT"
  OFFSET=$((OFFSET + BATCH_SIZE))
done
```

### Step 4: Export Flag Counts

```bash
# D8+
drush sql:query "SELECT flag_id, entity_type, entity_id, count, last_updated FROM flag_counts ORDER BY flag_id, count DESC;" --extra=--batch
```

If `flag_counts` does not exist, compute from `flagging` (see Section 3b).

### Step 5: Cross-Reference Entity Data

Flagging records contain entity IDs but no titles or URLs. Join against entity tables to produce a useful export:

```sql
-- D9+: Flagged nodes with title and type
SELECT f.flag_id,
       f.entity_id,
       n.type AS bundle,
       n.title,
       pa.alias AS url_alias,
       f.uid,
       u.name AS username,
       FROM_UNIXTIME(f.created) AS flagged_at
FROM flagging f
JOIN node_field_data n ON f.entity_type = 'node' AND f.entity_id = n.nid
LEFT JOIN path_alias pa ON pa.path = CONCAT('/node/', f.entity_id)
LEFT JOIN users_field_data u ON f.uid = u.uid
ORDER BY f.flag_id, f.created;
```

```sql
-- D7: Flagged nodes with title and type
SELECT f.name AS flag_name,
       fl.entity_id,
       n.type AS bundle,
       n.title,
       ua.alias AS url_alias,
       fl.uid,
       u.name AS username,
       FROM_UNIXTIME(fl.timestamp) AS flagged_at
FROM flagging fl
JOIN flags f ON fl.fid = f.fid
JOIN node n ON fl.entity_type = 'node' AND fl.entity_id = n.nid
LEFT JOIN url_alias ua ON ua.source = CONCAT('node/', fl.entity_id)
LEFT JOIN users u ON fl.uid = u.uid
ORDER BY f.name, fl.timestamp;
```

### Step 6: Validate

```sql
-- Check for orphaned flaggings (flagged entities that no longer exist)
-- D9+
SELECT f.flag_id, f.entity_type, f.entity_id, f.uid
FROM flagging f
LEFT JOIN node_field_data n ON f.entity_type = 'node' AND f.entity_id = n.nid
WHERE f.entity_type = 'node' AND n.nid IS NULL;

-- Repeat for each entity type that has flags (user, comment, taxonomy_term)
SELECT f.flag_id, f.entity_type, f.entity_id, f.uid
FROM flagging f
LEFT JOIN users_field_data u ON f.entity_type = 'user' AND f.entity_id = u.uid
WHERE f.entity_type = 'user' AND u.uid IS NULL;
```

```sql
-- Check for flaggings by deleted users
-- D9+
SELECT f.flag_id, f.uid, COUNT(*) AS orphaned_count
FROM flagging f
LEFT JOIN users_field_data u ON f.uid = u.uid
WHERE u.uid IS NULL AND f.uid > 0
GROUP BY f.flag_id, f.uid;
```

Report orphaned flaggings. Decide per flag whether to drop orphans or preserve them with a placeholder reference.

---

## 7. Output Format

Produce three output files:

### `flag_definitions.json`

```json
[
  {
    "id": "bookmark",
    "label": "Bookmark",
    "entity_type": "node",
    "bundles": ["article", "page"],
    "global": false,
    "flag_short": "Bookmark this",
    "unflag_short": "Remove bookmark",
    "link_type": "ajax_link",
    "migration_mapping": "user_saved_items"
  }
]
```

### `flagging_records.csv`

```
flag_id,entity_type,entity_id,entity_title,uid,username,session_id,created
bookmark,node,42,"How to Migrate Off Drupal",7,jsmith,,1698451200
bookmark,node,108,"Platform Comparison Guide",7,jsmith,,1698537600
like,node,42,"How to Migrate Off Drupal",12,agarcia,,1698624000
```

### `flag_counts.csv`

```
flag_id,entity_type,entity_id,entity_title,count,last_updated
like,node,42,"How to Migrate Off Drupal",47,1698624000
like,node,108,"Platform Comparison Guide",23,1698537600
bookmark,node,42,"How to Migrate Off Drupal",12,1698451200
```

Include the `migration_mapping` field from your use case mapping decisions (Section 4) in the definitions file. Downstream migration skills use this field to route each flag type to the correct target platform construct.
