# Skill 27: Revision History Export

Export every node revision record: version IDs, timestamps, authors, log messages, moderation states, and (optionally) full field values per revision. The output gives the target platform a complete audit trail and the ability to reconstruct content versioning.

Run Skill 01 (Site Audit) first. You need the Drupal version and available access methods. Run Skill 09 (Workflows & Moderation) if the site uses content moderation. Moderation states are stored per revision, and that skill maps the workflow definitions you need to interpret them.

---

## What Gets Exported

### Per Revision Record

| Property | D7 source | D9+ source |
|---|---|---|
| Revision ID | `node_revision.vid` | `node_revision.vid` |
| Node ID | `node_revision.nid` | `node_revision.nid` |
| Title | `node_revision.title` | `node_field_revision.title` |
| Revision author UID | `node_revision.uid` | `node_revision.revision_uid` |
| Revision author name | `users.name` (JOIN on `uid`) | `users_field_data.name` (JOIN on `revision_uid`) |
| Timestamp | `node_revision.timestamp` | `node_revision.revision_timestamp` |
| Log message | `node_revision.log` | `node_revision.revision_log` |
| Published status | `node_revision.status` | `node_field_revision.status` |
| Default revision flag | N/A (D7 tracks current vid on `node.vid`) | `node_field_revision.revision_default` |
| Langcode | N/A (D7 uses `node_revision.language` if i18n enabled) | `node_field_revision.langcode` |
| Moderation state | `workbench_moderation_node_history.state` (if module enabled) | `content_moderation_state_field_revision.moderation_state` |

### Active vs Default Revision

In D9+, a node can have multiple revision types in play at once:

- **Default revision**: The revision shown to anonymous users. Marked by `revision_default = 1` in `node_field_revision`.
- **Latest revision**: The most recent `vid` for a given `nid`. May be a forward draft that is not yet published.
- **Current revision**: The `vid` stored in `node_field_data.vid`. This always matches the default revision.

In D7, the concept is simpler. The `node.vid` column points to the current revision. All other revisions for that `nid` are historical.

### Revision Counts

Export revision counts per node to identify content with heavy edit histories. Nodes with hundreds of revisions may need special handling during import.

### Full Field Values per Revision (Optional)

Every field on a node stores revision data in a separate table. For a field named `field_body` on D9+:

- Current values: `node__field_body`
- Revision values: `node_revision__field_body`

For D7:

- Current values: `field_data_field_body`
- Revision values: `field_revision_field_body`

Exporting full field values per revision produces large datasets. A node with 50 revisions and 10 fields generates 500 field-value rows. Only export full revision field data when the target platform needs content diffs or full version reconstruction.

---

## Database Schema Reference

### D9+: node_revision table

| Column | Type | Description |
|---|---|---|
| `nid` | int | Node ID |
| `vid` | int (PK) | Revision ID |
| `langcode` | varchar | Language of the revision |
| `revision_uid` | int | UID of the user who created this revision |
| `revision_timestamp` | int | Unix timestamp when revision was created |
| `revision_log` | longtext | Free-text log message entered at save time |
| `revision_default` | tinyint | 1 if this is the default revision, 0 otherwise (added in Drupal 8.8) |

### D9+: node_field_revision table

Stores per-revision values for base fields (title, status, created, changed, promote, sticky, uid). One row per revision per language.

| Column | Type | Description |
|---|---|---|
| `nid` | int | Node ID |
| `vid` | int | Revision ID |
| `langcode` | varchar | Language |
| `title` | varchar | Node title at this revision |
| `uid` | int | Node author UID (not the revision author) |
| `status` | tinyint | 1 = published, 0 = unpublished |
| `created` | int | Original creation timestamp |
| `changed` | int | Last changed timestamp for this revision |
| `promote` | tinyint | Promoted to front page |
| `sticky` | tinyint | Sticky at top of lists |
| `revision_translation_affected` | tinyint | Whether this revision changed the translation |
| `default_langcode` | tinyint | 1 if this is the default language |
| `revision_default` | tinyint | 1 if this is the default revision |

### D9+: content_moderation_state_field_revision table

Stores the moderation state per entity revision. Only exists if the Content Moderation module is enabled.

| Column | Type | Description |
|---|---|---|
| `id` | int | Row ID |
| `revision_id` | int | Row revision ID (not the entity vid) |
| `langcode` | varchar | Language |
| `content_entity_type_id` | varchar | Entity type (e.g., `node`) |
| `content_entity_id` | int | Entity ID (nid) |
| `content_entity_revision_id` | int | Entity revision ID (vid) |
| `moderation_state` | varchar | Machine name of the state (e.g., `draft`, `published`) |
| `workflow` | varchar | Machine name of the workflow |

### D7: node_revision table

| Column | Type | Description |
|---|---|---|
| `nid` | int | Node ID |
| `vid` | int (PK) | Revision ID |
| `uid` | int | UID of the revision author |
| `title` | varchar | Node title at this revision |
| `log` | longtext | Revision log message |
| `timestamp` | int | Unix timestamp |
| `status` | int | 1 = published, 0 = unpublished |
| `comment` | int | Comment setting (0 = hidden, 1 = closed, 2 = open) |
| `promote` | int | Promoted to front page |
| `sticky` | int | Sticky at top of lists |

### D7: workbench_moderation_node_history table (if module enabled)

| Column | Type | Description |
|---|---|---|
| `hid` | int (PK) | History row ID |
| `vid` | int | Revision ID |
| `nid` | int | Node ID |
| `from_state` | varchar | Previous state machine name |
| `state` | varchar | New state machine name |
| `uid` | int | UID of the user who made the transition |
| `stamp` | int | Unix timestamp of the transition |
| `published` | tinyint | Whether this transition resulted in a published state |
| `is_current` | tinyint | 1 if this is the current moderation record for the revision |

---

## Access Method 1: Direct Database (D9+)

The database is the most reliable source for revision data. JSON:API has limited revision support and Drush has no built-in revision export command.

### 1a. List All Revisions for a Single Node

```sql
SELECT nr.vid,
       nr.nid,
       nfr.title,
       nr.revision_uid,
       u.name AS revision_author,
       nr.revision_timestamp,
       FROM_UNIXTIME(nr.revision_timestamp) AS revision_date,
       nr.revision_log,
       nfr.status,
       nfr.revision_default
FROM node_revision nr
JOIN node_field_revision nfr
  ON nr.vid = nfr.vid AND nr.nid = nfr.nid AND nfr.langcode = nr.langcode
LEFT JOIN users_field_data u
  ON nr.revision_uid = u.uid
WHERE nr.nid = 42
ORDER BY nr.vid;
```

### 1b. Revision Counts per Node

Identify nodes with heavy edit histories before deciding whether to export full revision field data.

```sql
SELECT nr.nid,
       nfd.title,
       nfd.type,
       COUNT(nr.vid) AS revision_count,
       MIN(nr.revision_timestamp) AS first_revision,
       MAX(nr.revision_timestamp) AS last_revision
FROM node_revision nr
JOIN node_field_data nfd ON nr.nid = nfd.nid AND nfd.default_langcode = 1
GROUP BY nr.nid, nfd.title, nfd.type
ORDER BY revision_count DESC;
```

Use this to scope the export. A site with 10,000 nodes averaging 3 revisions each produces 30,000 revision rows. A site where editors revise aggressively might have nodes with 200+ revisions.

### 1c. Bulk Export All Revision Metadata

```sql
SELECT nr.vid,
       nr.nid,
       nfd.type AS content_type,
       nfr.title,
       nr.revision_uid,
       u.name AS revision_author,
       nr.revision_timestamp,
       nr.revision_log,
       nfr.status,
       nfr.revision_default,
       nfr.langcode
FROM node_revision nr
JOIN node_field_revision nfr
  ON nr.vid = nfr.vid AND nr.nid = nfr.nid AND nfr.langcode = nr.langcode
JOIN node_field_data nfd
  ON nr.nid = nfd.nid AND nfd.default_langcode = 1
LEFT JOIN users_field_data u
  ON nr.revision_uid = u.uid
ORDER BY nr.nid, nr.vid;
```

Run via Drush for TSV output:

```bash
drush sql:query --extra="--batch" < revision_export.sql > revisions.tsv
```

Or export as CSV with headers:

```bash
drush sql:query "SELECT 'vid','nid','content_type','title','revision_uid','revision_author','revision_timestamp','revision_log','status','revision_default','langcode' UNION ALL SELECT nr.vid, nr.nid, nfd.type, nfr.title, nr.revision_uid, IFNULL(u.name,''), nr.revision_timestamp, IFNULL(nr.revision_log,''), nfr.status, nfr.revision_default, nfr.langcode FROM node_revision nr JOIN node_field_revision nfr ON nr.vid = nfr.vid AND nr.nid = nfr.nid AND nfr.langcode = nr.langcode JOIN node_field_data nfd ON nr.nid = nfd.nid AND nfd.default_langcode = 1 LEFT JOIN users_field_data u ON nr.revision_uid = u.uid ORDER BY nr.nid, nr.vid" --extra="--batch" > revisions.csv
```

### 1d. Include Moderation States

Join the content moderation revision table to get the moderation state at each revision. Only works if the Content Moderation module is enabled.

```sql
SELECT nr.vid,
       nr.nid,
       nfr.title,
       nr.revision_uid,
       u.name AS revision_author,
       nr.revision_timestamp,
       nr.revision_log,
       nfr.status,
       nfr.revision_default,
       cms.moderation_state,
       cms.workflow
FROM node_revision nr
JOIN node_field_revision nfr
  ON nr.vid = nfr.vid AND nr.nid = nfr.nid AND nfr.langcode = nr.langcode
LEFT JOIN users_field_data u
  ON nr.revision_uid = u.uid
LEFT JOIN content_moderation_state_field_revision cms
  ON cms.content_entity_type_id = 'node'
  AND cms.content_entity_id = nr.nid
  AND cms.content_entity_revision_id = nr.vid
WHERE nr.nid = 42
ORDER BY nr.vid;
```

Check if the table exists first:

```bash
drush sql:query "SHOW TABLES LIKE 'content_moderation_state_field_revision'"
```

### 1e. Export Full Field Values per Revision

Each configurable field has a revision table. The naming pattern is `node_revision__{field_name}`.

Discover all revision field tables for nodes:

```bash
drush sql:query "SHOW TABLES LIKE 'node_revision__%'"
```

Export a specific field's revision values:

```sql
SELECT entity_id AS nid,
       revision_id AS vid,
       delta,
       field_body_value,
       field_body_format
FROM node_revision__field_body
WHERE entity_id = 42
ORDER BY revision_id, delta;
```

To export all field revision data for one node, query each `node_revision__*` table filtered by `entity_id`.

For a complete export script that iterates all revision field tables:

```bash
#!/bin/bash
# Export all revision field data for a content type
CONTENT_TYPE="article"
OUTPUT_DIR="./revision_fields"
mkdir -p "$OUTPUT_DIR"

# Get all node_revision__ tables
TABLES=$(drush sql:query "SHOW TABLES LIKE 'node_revision__%'" --extra="--batch")

for TABLE in $TABLES; do
  FIELD_NAME="${TABLE#node_revision__}"
  echo "Exporting $TABLE..."
  drush sql:query --extra="--batch" \
    "SELECT r.entity_id, r.revision_id, r.delta, r.*
     FROM $TABLE r
     JOIN node_field_data nfd ON r.entity_id = nfd.nid
     WHERE nfd.type = '$CONTENT_TYPE'
     ORDER BY r.entity_id, r.revision_id, r.delta" \
    > "$OUTPUT_DIR/${FIELD_NAME}.tsv"
done
```

### 1f. Identify the Active/Default Revision per Node

The default revision is the one visible to anonymous visitors. Find it for every node:

```sql
SELECT nfd.nid,
       nfd.vid AS current_vid,
       nfd.title,
       nfd.type,
       nfd.status,
       (SELECT MAX(nr2.vid) FROM node_revision nr2 WHERE nr2.nid = nfd.nid) AS latest_vid
FROM node_field_data nfd
WHERE nfd.default_langcode = 1;
```

When `current_vid` differs from `latest_vid`, the node has a forward revision (a draft or pending review state newer than the published version). Flag these nodes in the export. The target platform needs to decide whether to import only the published version or also carry over the pending draft.

### 1g. Multilingual Revision Data

For multilingual sites, `node_field_revision` stores one row per revision per language. The same `vid` can have different titles, statuses, and field values across languages.

```sql
SELECT nr.vid,
       nr.nid,
       nfr.langcode,
       nfr.title,
       nfr.status,
       nfr.revision_default,
       nfr.revision_translation_affected
FROM node_revision nr
JOIN node_field_revision nfr
  ON nr.vid = nfr.vid AND nr.nid = nfr.nid
WHERE nr.nid = 42
ORDER BY nr.vid, nfr.langcode;
```

The `revision_translation_affected` column indicates whether this specific translation was changed in this revision. A value of `1` means yes. A value of `0` or `NULL` means the revision only changed other translations.

---

## Access Method 2: Direct Database (D7)

### 2a. List All Revisions for a Single Node

```sql
SELECT nr.vid,
       nr.nid,
       nr.title,
       nr.uid AS revision_uid,
       u.name AS revision_author,
       nr.timestamp,
       FROM_UNIXTIME(nr.timestamp) AS revision_date,
       nr.log,
       nr.status,
       CASE WHEN n.vid = nr.vid THEN 1 ELSE 0 END AS is_current
FROM node_revision nr
JOIN node n ON nr.nid = n.nid
LEFT JOIN users u ON nr.uid = u.uid
WHERE nr.nid = 42
ORDER BY nr.vid;
```

The `is_current` flag compares each revision's `vid` against the `node.vid` column, which holds the active revision.

### 2b. Revision Counts per Node (D7)

```sql
SELECT nr.nid,
       n.title,
       n.type,
       COUNT(nr.vid) AS revision_count,
       MIN(nr.timestamp) AS first_revision,
       MAX(nr.timestamp) AS last_revision
FROM node_revision nr
JOIN node n ON nr.nid = n.nid
GROUP BY nr.nid, n.title, n.type
ORDER BY revision_count DESC;
```

### 2c. Bulk Export All Revision Metadata (D7)

```sql
SELECT nr.vid,
       nr.nid,
       n.type AS content_type,
       nr.title,
       nr.uid AS revision_uid,
       u.name AS revision_author,
       nr.timestamp,
       nr.log,
       nr.status,
       CASE WHEN n.vid = nr.vid THEN 1 ELSE 0 END AS is_current
FROM node_revision nr
JOIN node n ON nr.nid = n.nid
LEFT JOIN users u ON nr.uid = u.uid
ORDER BY nr.nid, nr.vid;
```

### 2d. Include Workbench Moderation History (D7)

If the `workbench_moderation` module is installed:

```bash
# Check if the table exists
drush sql-query "SHOW TABLES LIKE 'workbench_moderation_node_history'"
```

```sql
SELECT nr.vid,
       nr.nid,
       nr.title,
       nr.uid AS revision_uid,
       u.name AS revision_author,
       nr.timestamp,
       nr.log,
       nr.status,
       wmh.from_state,
       wmh.state AS moderation_state,
       wmh.published AS moderation_published,
       CASE WHEN n.vid = nr.vid THEN 1 ELSE 0 END AS is_current
FROM node_revision nr
JOIN node n ON nr.nid = n.nid
LEFT JOIN users u ON nr.uid = u.uid
LEFT JOIN workbench_moderation_node_history wmh
  ON wmh.vid = nr.vid AND wmh.nid = nr.nid AND wmh.is_current = 1
ORDER BY nr.nid, nr.vid;
```

The `is_current = 1` filter on `workbench_moderation_node_history` gets the final moderation state for each revision. Without it, you get every state transition a revision went through.

To get the full state transition history (useful for audit trails):

```sql
SELECT wmh.nid,
       wmh.vid,
       wmh.from_state,
       wmh.state,
       wmh.uid AS transition_uid,
       u.name AS transition_author,
       wmh.stamp AS transition_timestamp,
       FROM_UNIXTIME(wmh.stamp) AS transition_date,
       wmh.published
FROM workbench_moderation_node_history wmh
LEFT JOIN users u ON wmh.uid = u.uid
WHERE wmh.nid = 42
ORDER BY wmh.stamp;
```

### 2e. Export Field Values per Revision (D7)

D7 stores field revision data in `field_revision_{field_name}` tables.

Discover all field revision tables:

```bash
drush sql-query "SHOW TABLES LIKE 'field_revision_%'"
```

Export a specific field's revision data:

```sql
SELECT entity_id AS nid,
       revision_id AS vid,
       delta,
       field_body_value,
       field_body_format
FROM field_revision_field_body
WHERE entity_type = 'node' AND entity_id = 42
ORDER BY revision_id, delta;
```

The `entity_type = 'node'` filter matters because D7 field tables are shared across entity types. Without it, you might get comment or user field data mixed in.

### 2f. Identify the Active Revision (D7)

```sql
SELECT n.nid,
       n.vid AS current_vid,
       n.title,
       n.type,
       n.status
FROM node n;
```

The `node.vid` column is the active revision. Compare against revision data to flag historical revisions.

---

## Access Method 3: JSON:API (D9+)

JSON:API has limited revision support. Drupal core added revision endpoints, but they come with constraints.

### 3a. Fetch the Latest Revision

Standard JSON:API endpoints return the default (published) revision:

```
GET /jsonapi/node/{bundle}/{uuid}
```

To get the latest revision (which may be a forward draft), add the `resourceVersion` query parameter:

```
GET /jsonapi/node/{bundle}/{uuid}?resourceVersion=rel:latest-version
```

To get the current (default/published) revision explicitly:

```
GET /jsonapi/node/{bundle}/{uuid}?resourceVersion=rel:working-copy
```

### 3b. Fetch a Specific Revision by ID

```
GET /jsonapi/node/{bundle}/{uuid}?resourceVersion=id:{vid}
```

Replace `{vid}` with the numeric revision ID. This returns the full entity data as it existed at that revision.

### 3c. Limitations

JSON:API has no endpoint to list all revisions of a node. You cannot paginate through revision history via JSON:API alone. The `resourceVersion` parameter fetches one revision at a time, and you need to know the `vid` in advance.

Practical approach: query the database for revision IDs, then use JSON:API to fetch full field data per revision if you need resolved entity references.

```bash
# Step 1: Get all vids from the database
VIDS=$(drush sql:query "SELECT vid FROM node_revision WHERE nid = 42 ORDER BY vid")

# Step 2: Get the node UUID
UUID=$(drush sql:query "SELECT uuid FROM node WHERE nid = 42")

# Step 3: Fetch each revision via JSON:API
for VID in $VIDS; do
  curl -s "https://example.com/jsonapi/node/article/${UUID}?resourceVersion=id:${VID}" \
    -H "Authorization: Basic $(echo -n 'user:pass' | base64)" \
    > "revision_${VID}.json"
done
```

This hybrid approach gives you resolved entity references (media, taxonomy, paragraphs) per revision, which pure SQL cannot provide without complex JOINs.

### 3d. Authentication

Fetching non-default revisions requires authentication. Anonymous users can only see the published default revision. Use Basic Auth, OAuth, or cookie authentication as described in Skill 11.

---

## Access Method 4: Drush

Drush has no built-in command to export revision history. Use `drush sql:query` (D9+) or `drush sql-query` (D7) to run the SQL queries above.

### 4a. Drush Entity Commands

Load a specific revision programmatically:

```bash
# D9+: Load a specific revision via Drush eval
drush eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('node');
  \$revision = \$storage->loadRevision(123);
  print_r([
    'vid' => \$revision->getRevisionId(),
    'title' => \$revision->getTitle(),
    'status' => \$revision->isPublished(),
    'revision_user' => \$revision->getRevisionUser()->getAccountName(),
    'revision_created' => \$revision->getRevisionCreationTime(),
    'revision_log' => \$revision->getRevisionLogMessage(),
  ]);
"
```

List all revision IDs for a node:

```bash
# D9+
drush eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('node');
  \$vids = \$storage->revisionIds(\Drupal::entityTypeManager()->getStorage('node')->load(42));
  echo implode(PHP_EOL, \$vids);
"
```

### 4b. Export Revisions with Full Field Data via Drush

```bash
# D9+: Export all revisions of a node as JSON
drush eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('node');
  \$node = \$storage->load(42);
  \$vids = \$storage->revisionIds(\$node);
  \$serializer = \Drupal::service('serializer');
  \$revisions = [];
  foreach (\$vids as \$vid) {
    \$revision = \$storage->loadRevision(\$vid);
    \$revisions[] = [
      'vid' => \$revision->getRevisionId(),
      'title' => \$revision->getTitle(),
      'status' => \$revision->isPublished(),
      'revision_uid' => \$revision->getRevisionUserId(),
      'revision_created' => \$revision->getRevisionCreationTime(),
      'revision_log' => \$revision->getRevisionLogMessage(),
      'fields' => json_decode(\$serializer->serialize(\$revision, 'json', ['plugin_id' => 'entity'])),
    ];
  }
  echo json_encode(\$revisions, JSON_PRETTY_PRINT);
" > node_42_revisions.json
```

This uses Drupal's serializer service to convert each revision to JSON with all field values resolved. The output includes computed fields and entity reference labels.

---

## Output Format

### Revision Metadata (revisions.json)

```json
[
  {
    "vid": 101,
    "nid": 42,
    "content_type": "article",
    "title": "Initial Draft",
    "revision_uid": 5,
    "revision_author": "editor1",
    "revision_timestamp": 1700000000,
    "revision_date": "2023-11-14T22:13:20+00:00",
    "revision_log": null,
    "status": 0,
    "revision_default": false,
    "moderation_state": "draft",
    "langcode": "en"
  },
  {
    "vid": 105,
    "nid": 42,
    "content_type": "article",
    "title": "Updated Title",
    "revision_uid": 3,
    "revision_author": "admin",
    "revision_timestamp": 1700100000,
    "revision_date": "2023-11-16T02:00:00+00:00",
    "revision_log": "Revised intro paragraph and updated hero image",
    "status": 1,
    "revision_default": true,
    "moderation_state": "published",
    "langcode": "en"
  }
]
```

### Revision Counts (revision_counts.json)

```json
[
  {
    "nid": 42,
    "title": "Updated Title",
    "content_type": "article",
    "revision_count": 12,
    "first_revision": 1700000000,
    "last_revision": 1700100000
  },
  {
    "nid": 85,
    "title": "About Us",
    "content_type": "page",
    "revision_count": 3,
    "first_revision": 1695000000,
    "last_revision": 1698000000
  }
]
```

### Moderation State Transitions (D7 workbench only)

```json
[
  {
    "nid": 42,
    "vid": 101,
    "from_state": null,
    "state": "draft",
    "transition_uid": 5,
    "transition_author": "editor1",
    "transition_timestamp": 1700000000
  },
  {
    "nid": 42,
    "vid": 105,
    "from_state": "draft",
    "state": "published",
    "transition_uid": 3,
    "transition_author": "admin",
    "transition_timestamp": 1700100000
  }
]
```

---

## Step-by-Step Procedure

### Step 1: Check Revision Storage

Confirm the site stores revisions and identify the volume.

**D9+:**

```bash
# Total revision count
drush sql:query "SELECT COUNT(*) FROM node_revision"

# Revision count by content type
drush sql:query "SELECT nfd.type, COUNT(nr.vid) AS rev_count FROM node_revision nr JOIN node_field_data nfd ON nr.nid = nfd.nid AND nfd.default_langcode = 1 GROUP BY nfd.type ORDER BY rev_count DESC"
```

**D7:**

```bash
# Total revision count
drush sql-query "SELECT COUNT(*) FROM {node_revision}"

# Revision count by content type
drush sql-query "SELECT n.type, COUNT(nr.vid) AS rev_count FROM {node_revision} nr JOIN {node} n ON nr.nid = n.nid GROUP BY n.type ORDER BY rev_count DESC"
```

### Step 2: Check for Content Moderation

**D9+:**

```bash
# Is content_moderation enabled?
drush pm:list --status=enabled --filter=content_moderation

# Does the moderation state revision table exist?
drush sql:query "SHOW TABLES LIKE 'content_moderation_state_field_revision'"
```

**D7:**

```bash
drush pm-list --status=enabled --filter=workbench_moderation
drush sql-query "SHOW TABLES LIKE 'workbench_moderation_node_history'"
```

### Step 3: Export Revision Metadata

Run the bulk export query from section 1c (D9+) or 2c (D7). Include moderation state joins from 1d or 2d if applicable.

Save to `revisions.tsv` or convert to JSON for the target platform.

### Step 4: Export Revision Counts

Run the revision count query from section 1b (D9+) or 2b (D7). Use this to decide which nodes need full field revision data.

### Step 5: Flag Forward Revisions (D9+)

```sql
SELECT nfd.nid,
       nfd.vid AS default_vid,
       MAX(nr.vid) AS latest_vid,
       nfd.title,
       nfd.type
FROM node_field_data nfd
JOIN node_revision nr ON nfd.nid = nr.nid
WHERE nfd.default_langcode = 1
GROUP BY nfd.nid, nfd.vid, nfd.title, nfd.type
HAVING default_vid != latest_vid;
```

These nodes have unpublished drafts newer than the published version. Document them. The target platform may want both versions.

### Step 6: Export Full Field Revision Data (Optional)

Only run this step if the target platform needs content diffs or full version history. Use the script from section 1e (D9+) or query each `field_revision_*` table from section 2e (D7).

### Step 7: Validate

Run these checks on the exported data:

```sql
-- D9+: Every node should have at least one revision
SELECT n.nid FROM node n
LEFT JOIN node_revision nr ON n.nid = nr.nid
WHERE nr.vid IS NULL;

-- D9+: The default revision vid should match node_field_data.vid
SELECT nfd.nid, nfd.vid AS expected_vid, nfr.vid AS revision_vid
FROM node_field_data nfd
JOIN node_field_revision nfr ON nfd.nid = nfr.nid AND nfd.vid = nfr.vid
WHERE nfr.revision_default != 1
  AND nfd.default_langcode = 1
  AND nfr.default_langcode = 1;

-- D7: Every node should have at least one revision
SELECT n.nid FROM node n
LEFT JOIN node_revision nr ON n.nid = n.nid AND nr.vid = n.vid
WHERE nr.vid IS NULL;
```

If the first query returns rows, you have orphaned nodes without revisions. This is a data integrity issue in the source site.

If the second query returns rows, the default revision flag is inconsistent with `node_field_data.vid`. This can happen after database migrations or manual SQL updates.

---

## Edge Cases

**Deleted revision authors.** When a user account is deleted in Drupal, the `revision_uid` may point to uid 0 or a non-existent user. The LEFT JOIN on `users_field_data` handles this by returning NULL for the name. Map these to a placeholder like "deleted user" in the target platform.

**Revisions without log messages.** Most revisions have NULL or empty log messages. Only a fraction of editors write log messages at save time. Do not treat missing logs as an error.

**Revision pruning.** Some sites run `drush entity:delete-revisions` or contrib modules like `node_revision_delete` to prune old revisions. The export only captures what exists at export time. There is no way to recover pruned revisions.

**Large revision counts.** Nodes with 100+ revisions are common on sites with forced revision creation (the "Create new revision" checkbox enabled by default). Body field revisions for these nodes can be several megabytes. Paginate exports for these nodes.

**Multilingual revisions.** A single `vid` can map to multiple rows in `node_field_revision`, one per language. The export must preserve the `langcode` column. When importing to a monolingual target, filter by `default_langcode = 1` to get only the primary language.

**D7 status values.** D7 uses the same status semantics as D8+ for nodes: `1 = published`, `0 = unpublished`. Unlike comments (where the values flipped between D7 and D8+), node status is consistent across versions.

**Content moderation without revisions.** Rare, but possible if someone disabled the "Create new revision" setting on a content type that uses moderation. Drupal will warn about this in the UI. The moderation state table may have entries that map to revision IDs that are also the current revision, with no separate draft revisions.
