# Skill 28: Scheduled Content (Publish/Unpublish Dates)

Export scheduled publish and unpublish dates from the Drupal Scheduler module. Capture per-node scheduling data and per-content-type scheduler configuration so the target platform can recreate timed publishing rules.

Run Skill 01 (Site Audit) first. You need the Drupal version and access methods. Run Skill 09 (Workflows & Moderation) if the site uses Content Moderation with scheduled transitions.

---

## When to Use This Skill

The site uses the `scheduler` contrib module. Look for these signs:

- `scheduler` appears in `drush pm:list --status=enabled` or `core.extension.yml`
- The database contains a `scheduler` table (D7) or `publish_on` / `unpublish_on` columns in `node_field_data` (D8+)
- Config files matching `node.type.*.yml` contain `third_party_settings.scheduler` keys
- The node edit form shows "Scheduling options" fieldsets with date pickers

If none of these are present, skip this skill. The site does not use scheduled publishing.

### Related Module: scheduler_content_moderation_integration

In D8+, the `scheduler_content_moderation_integration` module (bundled with Scheduler 2.x) connects Scheduler to Content Moderation workflows. Instead of scheduling a simple publish/unpublish toggle, editors schedule transitions between moderation states (Draft, Published, Archived, etc.). Check for this module separately:

```bash
drush pm:list --filter=name=scheduler_content_moderation_integration --format=json
```

If present, you need to export the scheduled moderation state alongside the dates. See Section 5.

---

## Background: D7 vs D8+ Storage

### Drupal 7

Scheduler stores data in a dedicated `scheduler` table. The node table itself knows nothing about scheduling.

| Column | Type | Meaning |
|---|---|---|
| `nid` | int | Node ID (foreign key to `node.nid`) |
| `publish_on` | int | Unix timestamp for scheduled publish. `0` = not scheduled. |
| `unpublish_on` | int | Unix timestamp for scheduled unpublish. `0` = not scheduled. |

One row per node. Nodes without scheduling have no row in the table. When cron fires and the current time exceeds `publish_on`, Scheduler publishes the node and removes the timestamp. Same for `unpublish_on`.

### Drupal 8 / 9 / 10 / 11

Scheduler registers `publish_on` and `unpublish_on` as base fields on node entities. These columns live directly in `node_field_data` and `node_field_revision`. No separate table.

| Column | Type | Meaning |
|---|---|---|
| `publish_on` | int (nullable) | Unix timestamp. `NULL` = not scheduled. |
| `unpublish_on` | int (nullable) | Unix timestamp. `NULL` = not scheduled. |

The fields only appear on entity types where Scheduler is enabled. Scheduler adds them dynamically through `hook_entity_base_field_info()`. They are not configurable fields; they are base fields attached to the entity type.

Starting with Scheduler 2.x (D9+), scheduling support extends beyond nodes. Media, taxonomy terms, and commerce products can also have scheduled dates. The base fields are the same (`publish_on`, `unpublish_on`) but stored in the respective entity data tables (`media_field_data`, `taxonomy_term_field_data`, etc.).

---

## Access Methods

| Priority | Method | Drupal Version | What It Gets |
|---|---|---|---|
| 1 | Drush | D7+ | SQL queries, config export, entity queries |
| 2 | Database | D7+ | Direct table access for dates and config |
| 3 | Config YAML | D8+ | Per-bundle scheduler settings (no content data) |
| 4 | JSON:API | D9+ | Scheduled dates on nodes if fields are exposed |

---

## 1. Detect Scheduler Presence and Version

### Via Drush

```bash
# Check if scheduler is installed
drush pm:list --filter=name=scheduler --format=json
```

The output includes the module version. Scheduler 1.x (D8) uses a dedicated database table similar to D7. Scheduler 2.x (D9+) uses entity base fields. The version determines your export strategy.

```bash
# Check scheduler version specifically
drush pm:list --filter=name=scheduler --fields=version --format=string
```

### Via Database (D8+)

```sql
-- Check if scheduler is enabled
SELECT name FROM key_value
WHERE collection = 'system.schema' AND name = 'scheduler';
```

### Via Config YAML

Look for scheduler references in content type config:

```bash
grep -rl 'third_party_settings' config/sync/node.type.*.yml | \
  xargs grep -l 'scheduler'
```

---

## 2. Export Per-Content-Type Scheduler Settings

Scheduler is enabled per content type (per bundle). Each content type has its own scheduler configuration stored in `third_party_settings`.

### 2a. Via Config YAML (D8+)

Open each `node.type.{bundle}.yml` and look for the `third_party_settings.scheduler` block:

```yaml
third_party_settings:
  scheduler:
    publish_enable: true
    unpublish_enable: true
    publish_past_date: publish
    publish_past_date_created: false
    publish_required: false
    publish_revision: true
    publish_touch: true
    unpublish_required: false
    unpublish_revision: true
    expand_fieldset: when_required
    fields_display_mode: vertical_tab
    show_message_extra: false
```

Extract these settings for every content type:

| Setting | Meaning |
|---|---|
| `publish_enable` | Scheduled publishing is available for this type |
| `unpublish_enable` | Scheduled unpublishing is available for this type |
| `publish_past_date` | What happens when a publish date is in the past: `error`, `publish`, `schedule` |
| `publish_past_date_created` | Use the scheduled date as the node's created date |
| `publish_required` | A publish date is mandatory on node creation |
| `publish_revision` | Create a new revision when scheduler publishes |
| `publish_touch` | Update the node's changed timestamp on scheduled publish |
| `unpublish_required` | An unpublish date is mandatory |
| `unpublish_revision` | Create a new revision when scheduler unpublishes |
| `expand_fieldset` | When to expand the scheduling fieldset: `always`, `when_required`, `never` |
| `fields_display_mode` | Where to show scheduling fields: `vertical_tab`, `fieldset` |

### 2b. Via Drush (D8+)

```bash
# Export all node type configs and extract scheduler settings
for type in $(drush config:list --format=list | grep '^node.type.'); do
  echo "=== $type ==="
  drush config:get "$type" third_party_settings.scheduler --format=yaml 2>/dev/null
done
```

### 2c. Via Database (D8+)

```sql
SELECT name, data FROM config
WHERE name LIKE 'node.type.%';
```

The `data` column is a PHP-serialized blob. Unserialize it and read the `third_party_settings.scheduler` key.

```php
// Via drush php:eval
$types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
$results = [];
foreach ($types as $type) {
  $settings = $type->getThirdPartySettings('scheduler');
  if (!empty($settings)) {
    $results[$type->id()] = $settings;
  }
}
echo json_encode($results, JSON_PRETTY_PRINT);
```

### 2d. Via Database (D7)

D7 stores scheduler settings as variables in the `variable` table. Each setting is keyed per content type:

```sql
SELECT name, value FROM variable
WHERE name LIKE 'scheduler_%'
ORDER BY name;
```

Variable names follow the pattern `scheduler_{setting}_{content_type}`. Examples:

- `scheduler_publish_enable_article` = `i:1;` (serialized PHP integer)
- `scheduler_unpublish_enable_article` = `i:1;`
- `scheduler_publish_past_date_article` = `s:7:"publish";`
- `scheduler_publish_required_article` = `i:0;`

Unserialize each value. Group by content type.

---

## 3. Export Scheduled Dates

### 3a. Drupal 7: scheduler Table

```sql
SELECT
  s.nid,
  n.type AS content_type,
  n.title,
  n.status AS current_status,
  s.publish_on,
  s.unpublish_on,
  FROM_UNIXTIME(s.publish_on) AS publish_on_readable,
  FROM_UNIXTIME(s.unpublish_on) AS unpublish_on_readable
FROM scheduler s
INNER JOIN node n ON n.nid = s.nid
WHERE s.publish_on > 0 OR s.unpublish_on > 0
ORDER BY s.nid;
```

Via Drush:

```bash
drush sql:query "
  SELECT s.nid, n.type, n.title, n.status,
         s.publish_on, s.unpublish_on
  FROM scheduler s
  INNER JOIN node n ON n.nid = s.nid
  WHERE s.publish_on > 0 OR s.unpublish_on > 0
  ORDER BY s.nid
" --result-file=scheduler_d7.tsv
```

Note: rows exist only for nodes that have (or had) scheduling. After Scheduler processes a node, it sets the timestamp to `0` but keeps the row. Rows with both values at `0` are stale. Filter them out.

### 3b. Drupal 8 (Scheduler 1.x): scheduler Table

Scheduler 1.x on D8 still uses a dedicated `scheduler` table, identical to the D7 schema. Use the same queries from 3a, substituting the D8 node table:

```sql
SELECT
  s.nid,
  nfd.type AS content_type,
  nfd.title,
  nfd.status AS current_status,
  s.publish_on,
  s.unpublish_on,
  FROM_UNIXTIME(s.publish_on) AS publish_on_readable,
  FROM_UNIXTIME(s.unpublish_on) AS unpublish_on_readable
FROM scheduler s
INNER JOIN node_field_data nfd ON nfd.nid = s.nid
WHERE s.publish_on > 0 OR s.unpublish_on > 0
ORDER BY s.nid;
```

### 3c. Drupal 9 / 10 / 11 (Scheduler 2.x): Base Fields

Scheduler 2.x stores dates as base fields on the entity. Query `node_field_data` directly:

```sql
SELECT
  nid,
  type AS content_type,
  title,
  status AS current_status,
  publish_on,
  unpublish_on,
  FROM_UNIXTIME(publish_on) AS publish_on_readable,
  FROM_UNIXTIME(unpublish_on) AS unpublish_on_readable
FROM node_field_data
WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL
ORDER BY nid;
```

Via Drush:

```bash
drush sql:query "
  SELECT nid, type, title, status, publish_on, unpublish_on
  FROM node_field_data
  WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL
  ORDER BY nid
" --result-file=scheduler_d9.tsv
```

Export as JSON with entity API:

```php
// Run with: drush php:eval 'include "export_scheduler.php";'
$nids = \Drupal::entityQuery('node')
  ->accessCheck(FALSE)
  ->condition('publish_on', NULL, 'IS NOT NULL')
  ->execute();

$nids_unpub = \Drupal::entityQuery('node')
  ->accessCheck(FALSE)
  ->condition('unpublish_on', NULL, 'IS NOT NULL')
  ->execute();

$all_nids = array_unique(array_merge($nids, $nids_unpub));
$nodes = \Drupal::entityTypeManager()->getStorage('node')->loadMultiple($all_nids);
$results = [];

foreach ($nodes as $node) {
  $results[] = [
    'nid' => (int) $node->id(),
    'uuid' => $node->uuid(),
    'type' => $node->bundle(),
    'title' => $node->getTitle(),
    'status' => (bool) $node->isPublished(),
    'publish_on' => $node->get('publish_on')->value,
    'publish_on_iso' => $node->get('publish_on')->value
      ? date('c', $node->get('publish_on')->value) : null,
    'unpublish_on' => $node->get('unpublish_on')->value,
    'unpublish_on_iso' => $node->get('unpublish_on')->value
      ? date('c', $node->get('unpublish_on')->value) : null,
  ];
}

file_put_contents('scheduled_content.json', json_encode($results, JSON_PRETTY_PRINT));
echo count($results) . " nodes with scheduling data exported.\n";
```

### 3d. Include Revision History

Scheduled dates in revisions show the history of scheduling changes. Useful when editors changed a publish date multiple times.

D9+ (base fields):

```sql
SELECT
  nfr.nid,
  nfr.vid,
  nfr.publish_on,
  nfr.unpublish_on,
  nfr.revision_timestamp,
  nfr.revision_log
FROM node_field_revision nfr
WHERE nfr.publish_on IS NOT NULL OR nfr.unpublish_on IS NOT NULL
ORDER BY nfr.nid, nfr.vid;
```

### 3e. Non-Node Entities (Scheduler 2.x)

Scheduler 2.x supports media, taxonomy terms, and commerce products. Query their data tables the same way:

```sql
-- Media
SELECT mid, bundle, name, publish_on, unpublish_on
FROM media_field_data
WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL;

-- Taxonomy terms
SELECT tid, vid AS vocabulary, name, publish_on, unpublish_on
FROM taxonomy_term_field_data
WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL;

-- Commerce products
SELECT product_id, type, title, publish_on, unpublish_on
FROM commerce_product_field_data
WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL;
```

Check which entity types have scheduler enabled before querying. If the columns do not exist on the table, Scheduler is not enabled for that entity type.

```php
// Check which entity types have scheduler base fields
$entity_types = ['node', 'media', 'taxonomy_term', 'commerce_product'];
foreach ($entity_types as $type_id) {
  $definitions = \Drupal::service('entity_field.manager')
    ->getBaseFieldDefinitions($type_id);
  if (isset($definitions['publish_on'])) {
    echo "$type_id: scheduler enabled\n";
  }
}
```

---

## 4. Export via JSON:API (D9+)

JSON:API exposes `publish_on` and `unpublish_on` if the fields exist on the entity. They appear as Unix timestamps in the attributes.

### 4a. Fetch Nodes with Scheduling Data

```
GET /jsonapi/node/{bundle}?filter[has-publish][condition][path]=publish_on&filter[has-publish][condition][operator]=IS NOT NULL&page[limit]=50
```

JSON:API does not natively support `IS NOT NULL` filters. Instead, filter for values greater than zero:

```
GET /jsonapi/node/{bundle}?filter[publish_on][condition][path]=publish_on&filter[publish_on][condition][operator]=%3E&filter[publish_on][condition][value]=0&page[limit]=50
```

The response includes `publish_on` and `unpublish_on` in the `attributes` block:

```json
{
  "type": "node--article",
  "id": "uuid-here",
  "attributes": {
    "title": "Upcoming Product Launch",
    "status": false,
    "publish_on": 1735689600,
    "unpublish_on": 1738368000
  }
}
```

### 4b. Pagination

Follow `links.next` to page through all results. See Skill 11 Section 1e for pagination details.

---

## 5. Scheduler + Content Moderation Integration

When the `scheduler_content_moderation_integration` module is active, Scheduler does not just toggle publish/unpublish. It triggers moderation state transitions. A node scheduled to "publish" might transition from "Draft" to "Published". A node scheduled to "unpublish" might transition from "Published" to "Archived".

### 5a. Detect the Integration Module

```bash
drush pm:list --filter=name=scheduler_content_moderation_integration --format=json
```

Or check config:

```bash
grep 'scheduler_content_moderation_integration' config/sync/core.extension.yml
```

### 5b. How It Stores Scheduled Transitions

The integration adds two fields to the node edit form:

- **Publish state**: the moderation state to transition to on the scheduled publish date
- **Unpublish state**: the moderation state to transition to on the scheduled unpublish date

These values are stored as additional base fields on the entity:

| Field | Column in `node_field_data` | Stores |
|---|---|---|
| `publish_state` | `publish_state` | Machine name of the target moderation state (e.g., `published`) |
| `unpublish_state` | `unpublish_state` | Machine name of the target moderation state (e.g., `archived`) |

### 5c. Export Scheduled Moderation Transitions

```sql
SELECT
  nid,
  type AS content_type,
  title,
  publish_on,
  unpublish_on,
  publish_state,
  unpublish_state
FROM node_field_data
WHERE publish_on IS NOT NULL
   OR unpublish_on IS NOT NULL
ORDER BY nid;
```

Via entity API:

```php
$nids = \Drupal::entityQuery('node')
  ->accessCheck(FALSE)
  ->condition('publish_on', NULL, 'IS NOT NULL')
  ->execute();

$nids_unpub = \Drupal::entityQuery('node')
  ->accessCheck(FALSE)
  ->condition('unpublish_on', NULL, 'IS NOT NULL')
  ->execute();

$all_nids = array_unique(array_merge($nids, $nids_unpub));
$nodes = \Drupal::entityTypeManager()->getStorage('node')->loadMultiple($all_nids);
$results = [];

foreach ($nodes as $node) {
  $entry = [
    'nid' => (int) $node->id(),
    'uuid' => $node->uuid(),
    'type' => $node->bundle(),
    'title' => $node->getTitle(),
    'publish_on' => $node->get('publish_on')->value,
    'unpublish_on' => $node->get('unpublish_on')->value,
  ];

  // These fields only exist when scheduler_content_moderation_integration is active
  if ($node->hasField('publish_state')) {
    $entry['publish_state'] = $node->get('publish_state')->value;
  }
  if ($node->hasField('unpublish_state')) {
    $entry['unpublish_state'] = $node->get('unpublish_state')->value;
  }

  $results[] = $entry;
}

file_put_contents('scheduled_moderation.json', json_encode($results, JSON_PRETTY_PRINT));
```

### 5d. Export Allowed Moderation Transitions for Scheduling

The integration module respects the workflow transitions defined in Skill 09. Extract which transitions are valid for scheduling:

```php
$workflow_manager = \Drupal::service('content_moderation.moderation_information');
$types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
$results = [];

foreach ($types as $type) {
  if (!$workflow_manager->shouldModerateEntitiesOfBundle(
    \Drupal::entityTypeManager()->getDefinition('node'), $type->id()
  )) {
    continue;
  }
  $workflow = $workflow_manager->getWorkflowForEntityTypeAndBundle('node', $type->id());
  if (!$workflow) continue;

  $plugin = $workflow->getTypePlugin();
  $states = [];
  foreach ($plugin->getStates() as $state_id => $state) {
    $states[$state_id] = [
      'label' => $state->label(),
      'published' => $state->isPublishedState(),
      'default_revision' => $state->isDefaultRevisionState(),
    ];
  }

  $results[$type->id()] = [
    'workflow' => $workflow->id(),
    'workflow_label' => $workflow->label(),
    'states' => $states,
  ];
}

echo json_encode($results, JSON_PRETTY_PRINT);
```

---

## 6. Summary Statistics

Before exporting, get a count of what you are dealing with:

### D7

```sql
SELECT
  n.type AS content_type,
  COUNT(*) AS total_scheduled,
  SUM(CASE WHEN s.publish_on > 0 THEN 1 ELSE 0 END) AS pending_publish,
  SUM(CASE WHEN s.unpublish_on > 0 THEN 1 ELSE 0 END) AS pending_unpublish,
  MIN(FROM_UNIXTIME(NULLIF(s.publish_on, 0))) AS earliest_publish,
  MAX(FROM_UNIXTIME(NULLIF(s.publish_on, 0))) AS latest_publish,
  MIN(FROM_UNIXTIME(NULLIF(s.unpublish_on, 0))) AS earliest_unpublish,
  MAX(FROM_UNIXTIME(NULLIF(s.unpublish_on, 0))) AS latest_unpublish
FROM scheduler s
INNER JOIN node n ON n.nid = s.nid
WHERE s.publish_on > 0 OR s.unpublish_on > 0
GROUP BY n.type;
```

### D9+ (Scheduler 2.x)

```sql
SELECT
  type AS content_type,
  COUNT(*) AS total_scheduled,
  SUM(CASE WHEN publish_on IS NOT NULL THEN 1 ELSE 0 END) AS pending_publish,
  SUM(CASE WHEN unpublish_on IS NOT NULL THEN 1 ELSE 0 END) AS pending_unpublish,
  MIN(FROM_UNIXTIME(publish_on)) AS earliest_publish,
  MAX(FROM_UNIXTIME(publish_on)) AS latest_publish,
  MIN(FROM_UNIXTIME(unpublish_on)) AS earliest_unpublish,
  MAX(FROM_UNIXTIME(unpublish_on)) AS latest_unpublish
FROM node_field_data
WHERE publish_on IS NOT NULL OR unpublish_on IS NOT NULL
GROUP BY type;
```

---

## 7. Output Format

Combine content type settings and per-node scheduling data into one export:

```json
{
  "scheduler_settings": {
    "article": {
      "publish_enable": true,
      "unpublish_enable": true,
      "publish_past_date": "publish",
      "publish_required": false,
      "unpublish_required": false,
      "publish_revision": true,
      "unpublish_revision": true
    },
    "event": {
      "publish_enable": true,
      "unpublish_enable": true,
      "publish_past_date": "error",
      "publish_required": false,
      "unpublish_required": true,
      "publish_revision": true,
      "unpublish_revision": true
    }
  },
  "scheduled_content": [
    {
      "nid": 142,
      "uuid": "a1b2c3d4-...",
      "type": "article",
      "title": "Upcoming Feature Announcement",
      "status": false,
      "publish_on": 1735689600,
      "publish_on_iso": "2025-01-01T00:00:00+00:00",
      "unpublish_on": null,
      "unpublish_on_iso": null,
      "publish_state": "published",
      "unpublish_state": null
    },
    {
      "nid": 298,
      "uuid": "e5f6a7b8-...",
      "type": "event",
      "title": "Summer Conference 2025",
      "status": true,
      "publish_on": null,
      "publish_on_iso": null,
      "unpublish_on": 1756684800,
      "unpublish_on_iso": "2025-09-01T00:00:00+00:00",
      "publish_state": null,
      "unpublish_state": "archived"
    }
  ],
  "summary": {
    "total_content_types_with_scheduler": 2,
    "total_scheduled_nodes": 2,
    "pending_publish": 1,
    "pending_unpublish": 1
  }
}
```

---

## 8. Gotchas

**Timestamps are Unix integers, not ISO dates.** Scheduler stores all dates as Unix timestamps (seconds since epoch) in every Drupal version. Convert to ISO 8601 during export. The site's timezone setting (`system.date` config, `date_default_timezone` variable in D7) determines how editors see these dates in the UI, but storage is always UTC-epoch.

**Processed nodes lose their timestamps.** When cron runs and Scheduler publishes or unpublishes a node, it clears the timestamp (sets to `0` in D7, `NULL` in D9+). Your export captures only future scheduled actions. Past scheduling data is gone unless you have revision history (D9+ base fields track this in `node_field_revision`).

**Scheduler 1.x vs 2.x on D8.** Some D8 sites run Scheduler 1.x, which uses a `scheduler` table. Others upgraded to 2.x, which uses base fields. Check the module version. If the `scheduler` table exists and has data, you are on 1.x. If `node_field_data` has `publish_on` columns, you are on 2.x.

**Content Moderation changes the semantics.** Without Content Moderation, `publish_on` means "set status to 1." With Content Moderation, `publish_on` means "transition to the state defined in `publish_state`." Export both the date and the target state. A publish date without the target state is ambiguous on moderated content.

**Timezone display vs storage.** Editors enter dates in the site's configured timezone. Scheduler converts to UTC Unix timestamp for storage. When exporting ISO dates, use UTC. Document the site's display timezone separately so the target platform can present dates the same way editors expect.

**Non-node entities (Scheduler 2.x).** Do not assume only nodes are scheduled. Check media, taxonomy terms, and commerce products. Use the entity field manager check from Section 3e to discover all scheduled entity types before running queries.
