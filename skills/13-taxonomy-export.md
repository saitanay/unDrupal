# Skill 13: Taxonomy Export

Extract every vocabulary, term, and hierarchy relationship from a Drupal site. Output: a portable JSON document containing vocabulary definitions, term data with full parent chains, custom fields on terms, path aliases, translations, and a usage map showing which content types reference which vocabularies through which fields.

---

## When to Use This Skill

The site has taxonomy vocabularies. Almost every Drupal site does. Taxonomy powers tags, categories, product types, locations, and any other classification scheme.

Check for vocabularies:
- Config files: `taxonomy.vocabulary.*.yml` exists
- Drush: `drush entity:list taxonomy_term` returns results
- Database (D8+): `SELECT * FROM taxonomy_term_data LIMIT 1` returns rows
- Database (D7): `SELECT * FROM taxonomy_term_data LIMIT 1` returns rows
- JSON:API: `/jsonapi/taxonomy_vocabulary/taxonomy_vocabulary` returns data

If no vocabularies exist, skip this skill.

---

## Background: Taxonomy Architecture

### D8/D9/D10/D11

Taxonomy terms are fieldable content entities. Each vocabulary is a config entity. Terms support revisions (D8.6+), translations, and custom fields just like nodes.

Core tables:

| Table | Purpose |
|---|---|
| `taxonomy_term_data` | Base table. Stores `tid`, `revision_id`, `vid` (vocabulary machine name), `uuid`, `langcode` |
| `taxonomy_term_field_data` | Data table. Stores `tid`, `revision_id`, `vid`, `langcode`, `name`, `description__value`, `description__format`, `weight`, `changed`, `default_langcode`, `revision_translation_affected`, `status`, `publish_on`, `unpublish_on` (if scheduler enabled) |
| `taxonomy_term_field_revision` | Revision data table. Same columns as `taxonomy_term_field_data` but per-revision |
| `taxonomy_term__parent` | Parent references. Stores `entity_id` (child tid), `parent_target_id` (parent tid). A term with no parent has a row where `parent_target_id = 0`. Multiple rows per `entity_id` means polyhierarchy. |
| `taxonomy_term_revision` | Revision base table. Stores `tid`, `revision_id`, `langcode`, `revision_user`, `revision_created`, `revision_log_message`, `revision_default` |
| `taxonomy_term__field_*` | Custom field value tables. One table per custom field attached to taxonomy terms. |

Key facts:
- `vid` in D8+ is the vocabulary machine name (string), not a numeric ID.
- The `parent` field is stored in `taxonomy_term__parent`, not in `taxonomy_term_field_data`. It is a core base field, but Drupal stores it in a dedicated table because it has unlimited cardinality (polyhierarchy).
- A root-level term has exactly one row in `taxonomy_term__parent` with `parent_target_id = 0`.
- A term with two parents has two rows in `taxonomy_term__parent`, both with different `parent_target_id` values.
- The `status` column (D9.2+) supports unpublished terms. Older D8 sites may lack this column.
- Translations are stored as additional rows in `taxonomy_term_field_data` with different `langcode` values and `default_langcode = 0`.

### Drupal 7

D7 taxonomy is simpler. No revisions, no custom entity fields through config (fields are attached via Field API but stored differently), no built-in translation entity support.

Core tables:

| Table | Purpose |
|---|---|
| `taxonomy_vocabulary` | Vocabulary definitions. `vid` (numeric), `name`, `machine_name`, `description`, `hierarchy` (0 = flat, 1 = single parent, 2 = multiple parents), `module`, `weight` |
| `taxonomy_term_data` | Term data. `tid`, `vid` (numeric, FK to `taxonomy_vocabulary.vid`), `name`, `description`, `format`, `weight` |
| `taxonomy_term_hierarchy` | Parent references. `tid` (child), `parent` (parent tid). Root terms have `parent = 0`. Multiple rows per tid = polyhierarchy. |
| `field_data_field_*` | Custom fields on terms. Same pattern as node fields. Entity type = `taxonomy_term`. |
| `taxonomy_index` | Maps terms to nodes. `nid`, `tid`, `sticky`, `created`. Only populated for fields using the core taxonomy reference type. |

Key differences from D8+:
- `vid` is numeric in D7, a machine name string in D8+.
- The hierarchy table is `taxonomy_term_hierarchy` in D7, `taxonomy_term__parent` in D8+.
- D7 tracks the hierarchy type on the vocabulary itself (`hierarchy` column: 0, 1, or 2). D8+ has no such column. You derive hierarchy from the parent data.
- D7 has no `uuid` column on terms. No `status` column (all terms are published). No `langcode` base column.
- D7 term translations use the `i18n_taxonomy` module (part of `i18n` contrib). Translation data lives in `locales_source` / `locales_target` tables or in linked translation sets depending on the i18n mode.
- The `taxonomy_index` table in D7 is actively used for node-term lookups. D8+ maintains it too but it only covers the default taxonomy reference field, not all entity reference fields targeting terms.

---

## What Gets Exported

### Per Vocabulary

| Property | D8+ Source | D7 Source |
|---|---|---|
| Machine name | `vid` key in `taxonomy.vocabulary.*.yml` | `machine_name` column in `taxonomy_vocabulary` |
| Label | `name` key | `name` column |
| Description | `description` key | `description` column |
| Weight | `weight` key | `weight` column |
| Langcode | `langcode` key | N/A |
| Hierarchy type | Derived from parent data | `hierarchy` column (0, 1, 2) |
| Custom fields | `field.field.taxonomy_term.{vid}.*.yml` | `field_config_instance` where `entity_type = 'taxonomy_term'` and `bundle = vid` |
| Third-party settings | `third_party_settings` key | N/A |

### Per Term

| Property | D8+ Source | D7 Source |
|---|---|---|
| tid | `taxonomy_term_data.tid` | `taxonomy_term_data.tid` |
| uuid | `taxonomy_term_data.uuid` | N/A |
| Vocabulary | `taxonomy_term_data.vid` (machine name) | `taxonomy_term_data.vid` (numeric, join to `taxonomy_vocabulary` for machine name) |
| Name | `taxonomy_term_field_data.name` | `taxonomy_term_data.name` |
| Description (value) | `taxonomy_term_field_data.description__value` | `taxonomy_term_data.description` |
| Description (format) | `taxonomy_term_field_data.description__format` | `taxonomy_term_data.format` |
| Weight | `taxonomy_term_field_data.weight` | `taxonomy_term_data.weight` |
| Status | `taxonomy_term_field_data.status` (1=published, 0=unpublished) | Always published (no column) |
| Language | `taxonomy_term_field_data.langcode` | Via `i18n_taxonomy` if enabled |
| Changed timestamp | `taxonomy_term_field_data.changed` | N/A |
| Parent tids | `taxonomy_term__parent.parent_target_id` | `taxonomy_term_hierarchy.parent` |
| Depth | Calculated from parent chain | Calculated from parent chain |
| Path alias | `path_alias` entity or `url_alias` table | `url_alias` table |
| Custom field values | `taxonomy_term__field_*` tables | `field_data_field_*` tables where `entity_type = 'taxonomy_term'` |

### Usage Map

For each vocabulary, list every entity reference field that targets it. This tells the migration which content types depend on which vocabularies.

| Property | Source |
|---|---|
| Referencing entity type | `field.storage.*.*.yml` where `settings.target_type = 'taxonomy_term'` |
| Referencing bundle | `field.field.*.*.*.yml` where `settings.handler_settings.target_bundles` includes the vocabulary |
| Field name | The field machine name |
| Cardinality | From the field storage config |
| Auto-create | Whether the field creates new terms on the fly |
| Selection handler | `default:taxonomy_term` or custom |

---

## Access Methods

Try each method in order. Stop at the first one that produces results.

### Method 1: Config YAML + Database (D8+)

Config YAML gives you vocabulary definitions and field schemas. The database gives you term data. Use both together.

#### Vocabulary Definitions

```bash
# List all vocabularies
ls config/sync/taxonomy.vocabulary.*.yml
```

File structure:

```yaml
# taxonomy.vocabulary.tags.yml
uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
langcode: en
status: true
dependencies: {}
name: Tags
vid: tags
description: 'Use tags to group articles on similar topics.'
weight: 0
third_party_settings: {}
```

#### Field Definitions on Terms

```bash
# Field storage for taxonomy term fields
ls config/sync/field.storage.taxonomy_term.*.yml

# Field instances per vocabulary
ls config/sync/field.field.taxonomy_term.*.yml
```

Example custom field on terms:

```yaml
# field.storage.taxonomy_term.field_icon.yml
id: taxonomy_term.field_icon
field_name: field_icon
entity_type: taxonomy_term
type: image
settings:
  target_type: file
  default_image:
    uuid: null
    alt: ''
    title: ''
    width: null
    height: null
module: image
cardinality: 1
translatable: true
```

```yaml
# field.field.taxonomy_term.categories.field_icon.yml
id: taxonomy_term.categories.field_icon
field_name: field_icon
entity_type: taxonomy_term
bundle: categories
label: Icon
description: 'Category icon displayed in navigation.'
required: false
translatable: false
settings:
  file_directory: 'taxonomy/icons'
  file_extensions: 'png svg'
  max_filesize: '512 KB'
  alt_field: true
  alt_field_required: true
  title_field: false
  title_field_required: false
field_type: image
```

#### Term Data from Database

```sql
-- All terms with vocabulary, sorted by vocabulary and weight
SELECT
  td.tid,
  td.uuid,
  tfd.vid,
  tfd.langcode,
  tfd.name,
  tfd.description__value,
  tfd.description__format,
  tfd.weight,
  tfd.status,
  tfd.changed,
  tfd.default_langcode
FROM taxonomy_term_data td
JOIN taxonomy_term_field_data tfd ON td.tid = tfd.tid
WHERE tfd.default_langcode = 1
ORDER BY tfd.vid, tfd.weight, tfd.name;
```

#### Hierarchy from Database

```sql
-- All parent relationships
SELECT
  entity_id AS tid,
  parent_target_id AS parent_tid
FROM taxonomy_term__parent
ORDER BY entity_id;
```

Root terms have `parent_target_id = 0`. Filter those out when building the tree, but keep the rows to distinguish root terms from terms with missing parent data.

Polyhierarchy check:

```sql
-- Terms with multiple parents
SELECT entity_id AS tid, COUNT(*) AS parent_count
FROM taxonomy_term__parent
WHERE parent_target_id != 0
GROUP BY entity_id
HAVING COUNT(*) > 1;
```

If this query returns rows, the site uses polyhierarchy. Flag it in the export. Most target platforms do not support multiple parents per term.

#### Translations from Database

```sql
-- All term translations (non-default languages)
SELECT
  tfd.tid,
  tfd.vid,
  tfd.langcode,
  tfd.name,
  tfd.description__value,
  tfd.description__format
FROM taxonomy_term_field_data tfd
WHERE tfd.default_langcode = 0
ORDER BY tfd.tid, tfd.langcode;
```

#### Path Aliases

D8+ stores path aliases as entities in the `path_alias` table (D9.0+) or the `url_alias` table (D8.x).

```sql
-- D9/D10/D11: path_alias table
SELECT
  pa.path,
  pa.alias,
  pa.langcode
FROM path_alias pa
WHERE pa.path LIKE '/taxonomy/term/%'
  AND pa.status = 1
ORDER BY pa.path;
```

```sql
-- D8: url_alias table
SELECT
  source AS path,
  alias,
  langcode
FROM url_alias
WHERE source LIKE '/taxonomy/term/%'
ORDER BY source;
```

Extract the tid from the path column: `/taxonomy/term/42` gives tid `42`.

#### Custom Field Values

For each custom field on taxonomy terms, query its dedicated table:

```sql
-- Example: field_icon on taxonomy terms
SELECT
  entity_id AS tid,
  bundle AS vid,
  langcode,
  delta,
  field_icon_target_id,
  field_icon_alt,
  field_icon_title,
  field_icon_width,
  field_icon_height
FROM taxonomy_term__field_icon
ORDER BY entity_id, delta;
```

The table name pattern is `taxonomy_term__field_{field_name}`. Each table has `entity_id`, `revision_id`, `bundle`, `delta`, `langcode`, `deleted`, and one or more value columns named `{field_name}_{property}`.

List all custom field tables for taxonomy terms:

```sql
-- Find all taxonomy term field tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name LIKE 'taxonomy_term__field_%'
ORDER BY table_name;
```

#### Usage Map from Config

```bash
# Find all entity_reference field storages targeting taxonomy_term
grep -rl "target_type: taxonomy_term" config/sync/field.storage.*.yml
```

For each match, read the storage file to get the field name and entity type. Then find all instances of that field:

```bash
# For field_tags on nodes
ls config/sync/field.field.node.*.field_tags.yml
```

Each instance file's `settings.handler_settings.target_bundles` tells you which vocabularies that field references.

Batch script:

```bash
#!/usr/bin/env bash
# Build vocabulary usage map from config YAML
set -euo pipefail

CONFIG_DIR="${1:-config/sync}"

echo "=== Vocabulary Usage Map ==="

for storage_file in "$CONFIG_DIR"/field.storage.*.yml; do
  # Check if this field targets taxonomy_term
  if grep -q "target_type: taxonomy_term" "$storage_file" 2>/dev/null; then
    field_name=$(grep "^field_name:" "$storage_file" | awk '{print $2}')
    entity_type=$(grep "^entity_type:" "$storage_file" | awk '{print $2}')
    cardinality=$(grep "^cardinality:" "$storage_file" | awk '{print $2}')

    echo ""
    echo "Field: $entity_type.$field_name (cardinality: $cardinality)"

    # Find all instances of this field
    for instance_file in "$CONFIG_DIR"/field.field."$entity_type".*."$field_name".yml; do
      if [ -f "$instance_file" ]; then
        bundle=$(echo "$instance_file" | sed "s|.*field\.field\.$entity_type\.\(.*\)\.$field_name\.yml|\1|")
        # Extract target bundles
        target_bundles=$(grep -A 20 "target_bundles:" "$instance_file" | grep -E "^\s+\w+:" | head -10 | awk '{print $1}' | tr -d ':' | tr '\n' ', ' | sed 's/,$//')
        auto_create=$(grep "auto_create:" "$instance_file" | head -1 | awk '{print $2}')
        echo "  $entity_type.$bundle -> vocabularies: $target_bundles (auto_create: ${auto_create:-false})"
      fi
    done
  fi
done
```

### Method 2: Drush (D8+)

```bash
# Export all taxonomy vocabulary config
for vocab in $(drush config:list --prefix=taxonomy.vocabulary --format=list); do
  drush config:get "$vocab" --format=json
done

# Export all taxonomy term field storage configs
for fs in $(drush config:list --prefix=field.storage.taxonomy_term --format=list); do
  drush config:get "$fs" --format=json
done

# Export all taxonomy term field instance configs
for fi in $(drush config:list --prefix=field.field.taxonomy_term --format=list); do
  drush config:get "$fi" --format=json
done

# Count terms per vocabulary
drush sql:query "SELECT vid, COUNT(*) as count FROM taxonomy_term_field_data WHERE default_langcode = 1 GROUP BY vid ORDER BY vid;"

# Export all terms as JSON using entity:load
drush php:eval '
$vids = \Drupal::entityTypeManager()->getStorage("taxonomy_vocabulary")->loadMultiple();
foreach ($vids as $vid => $vocab) {
  $terms = \Drupal::entityTypeManager()->getStorage("taxonomy_term")->loadTree($vid, 0, NULL, TRUE);
  echo json_encode([
    "vocabulary" => $vid,
    "count" => count($terms),
  ]) . "\n";
}
'
```

Full term export with hierarchy via Drush:

```bash
drush php:eval '
use Drupal\taxonomy\Entity\Term;

$vids = array_keys(\Drupal::entityTypeManager()
  ->getStorage("taxonomy_vocabulary")
  ->loadMultiple());

$export = [];
foreach ($vids as $vid) {
  $tids = \Drupal::entityQuery("taxonomy_term")
    ->condition("vid", $vid)
    ->accessCheck(FALSE)
    ->execute();

  foreach (Term::loadMultiple($tids) as $term) {
    $parents = array_map(function ($p) {
      return (int) $p->get("target_id")->getValue();
    }, $term->get("parent")->referencedEntities());

    // If parent list is empty, it is a root term
    $parent_ids = [];
    foreach ($term->get("parent") as $item) {
      $parent_ids[] = (int) $item->target_id;
    }

    $export[] = [
      "tid" => (int) $term->id(),
      "uuid" => $term->uuid(),
      "vid" => $vid,
      "name" => $term->getName(),
      "description" => $term->getDescription(),
      "description_format" => $term->getFormat(),
      "weight" => (int) $term->getWeight(),
      "status" => (int) $term->isPublished(),
      "langcode" => $term->language()->getId(),
      "parent_tids" => array_filter($parent_ids),
      "changed" => $term->getChangedTime(),
    ];
  }
}
echo json_encode($export, JSON_PRETTY_PRINT);
' > taxonomy_terms_export.json
```

For large vocabularies (10,000+ terms), use batch queries instead of loading all terms at once:

```bash
drush php:eval '
$vid = "tags";
$batch_size = 500;
$offset = 0;
$fp = fopen("taxonomy_${vid}.jsonl", "w");

while (TRUE) {
  $tids = \Drupal::entityQuery("taxonomy_term")
    ->condition("vid", $vid)
    ->accessCheck(FALSE)
    ->sort("tid")
    ->range($offset, $batch_size)
    ->execute();

  if (empty($tids)) break;

  $terms = \Drupal\taxonomy\Entity\Term::loadMultiple($tids);
  foreach ($terms as $term) {
    $parent_ids = [];
    foreach ($term->get("parent") as $item) {
      $parent_ids[] = (int) $item->target_id;
    }
    $row = [
      "tid" => (int) $term->id(),
      "uuid" => $term->uuid(),
      "vid" => $vid,
      "name" => $term->getName(),
      "weight" => (int) $term->getWeight(),
      "status" => (int) $term->isPublished(),
      "parent_tids" => array_filter($parent_ids),
    ];
    fwrite($fp, json_encode($row) . "\n");
  }

  $offset += $batch_size;
  \Drupal::entityTypeManager()->getStorage("taxonomy_term")->resetCache();
}
fclose($fp);
echo "Exported to taxonomy_${vid}.jsonl\n";
'
```

### Method 3: JSON:API (Remote, No Shell)

JSON:API exposes taxonomy terms as resources. Each vocabulary has its own endpoint.

#### Discover Vocabularies

```bash
# List all vocabulary resource types
curl -s 'https://example.com/jsonapi/taxonomy_vocabulary/taxonomy_vocabulary' \
  | jq '.data[] | {id: .id, vid: .attributes.drupal_internal__vid, name: .attributes.name, description: .attributes.description}'
```

#### Fetch Terms with Parents

```bash
# Fetch terms from the "tags" vocabulary, include parent references
curl -s 'https://example.com/jsonapi/taxonomy_term/tags?include=parent&page[limit]=50&sort=weight,name' \
  | jq '{
    data: [.data[] | {
      tid: .attributes.drupal_internal__tid,
      uuid: .id,
      name: .attributes.name,
      description: .attributes.description,
      weight: .attributes.weight,
      status: .attributes.status,
      langcode: .attributes.langcode,
      changed: .attributes.changed,
      parents: [.relationships.parent.data[]? | .id]
    }],
    next: .links.next.href
  }'
```

The `parent` relationship returns UUIDs, not tids. Build a UUID-to-tid map from the response data or from the `included` array.

JSON:API uses cursor-based pagination. Follow `links.next.href` until it is absent:

```bash
#!/usr/bin/env bash
# Paginate through all terms in a vocabulary via JSON:API
set -euo pipefail

BASE_URL="https://example.com"
VOCABULARY="tags"
OUTPUT_FILE="taxonomy_${VOCABULARY}.json"
PAGE_SIZE=50

URL="${BASE_URL}/jsonapi/taxonomy_term/${VOCABULARY}?include=parent&page[limit]=${PAGE_SIZE}&sort=weight,name"
ALL_DATA="[]"

while [ -n "$URL" ]; do
  RESPONSE=$(curl -s "$URL")

  # Extract term data from this page
  PAGE_DATA=$(echo "$RESPONSE" | jq '[.data[] | {
    tid: .attributes.drupal_internal__tid,
    uuid: .id,
    name: .attributes.name,
    description: .attributes.description,
    weight: .attributes.weight,
    status: .attributes.status,
    langcode: .attributes.langcode,
    parents: [.relationships.parent.data[]? | select(.id != "virtual") | .meta.drupal_internal__target_id // .id]
  }]')

  ALL_DATA=$(echo "$ALL_DATA" "$PAGE_DATA" | jq -s '.[0] + .[1]')

  # Get next page URL
  URL=$(echo "$RESPONSE" | jq -r '.links.next.href // empty')
done

echo "$ALL_DATA" | jq '.' > "$OUTPUT_FILE"
echo "Exported $(echo "$ALL_DATA" | jq 'length') terms to $OUTPUT_FILE"
```

JSON:API limitations for taxonomy export:
- Parent references return UUIDs. The `drupal_internal__target_id` in `meta` gives the tid, but only if the server includes it (D9.3+).
- Custom fields on terms appear in `attributes` (scalar fields) or `relationships` (entity reference fields).
- Path aliases are not included in the default response. Query `/jsonapi/path_alias/path_alias?filter[path][operator]=STARTS_WITH&filter[path][value]=/taxonomy/term/` separately.
- Translation data requires `?filter[langcode]=fr` or using the language prefix: `/fr/jsonapi/taxonomy_term/tags`.
- No way to get the usage map (which fields reference which vocabularies). Use config YAML or Drush for that.

#### Fetch Term Path Aliases via JSON:API

```bash
curl -s 'https://example.com/jsonapi/path_alias/path_alias?filter[path-filter][condition][path][operator]=STARTS_WITH&filter[path-filter][condition][path][value]=/taxonomy/term/&page[limit]=50' \
  | jq '.data[] | {path: .attributes.path, alias: .attributes.alias, langcode: .attributes.langcode}'
```

#### Fetch Term Translations

```bash
# Fetch French translations of tags
curl -s 'https://example.com/fr/jsonapi/taxonomy_term/tags?page[limit]=50' \
  | jq '.data[] | {tid: .attributes.drupal_internal__tid, name: .attributes.name, langcode: .attributes.langcode}'
```

### Method 4: Database Direct (D8+)

Use when you have database access but no Drush or config export.

#### Vocabulary Definitions from Config Table

```sql
-- Extract vocabulary config from the config table
SELECT
  REPLACE(name, 'taxonomy.vocabulary.', '') AS vid,
  data
FROM config
WHERE name LIKE 'taxonomy.vocabulary.%';
```

The `data` column contains PHP-serialized arrays. Decode them:

```bash
drush php:eval '
$rows = \Drupal::database()->query("SELECT name, data FROM {config} WHERE name LIKE :pattern", [":pattern" => "taxonomy.vocabulary.%"]);
foreach ($rows as $row) {
  $config = unserialize($row->data);
  echo json_encode([
    "vid" => $config["vid"],
    "name" => $config["name"],
    "description" => $config["description"],
    "weight" => $config["weight"],
  ]) . "\n";
}
'
```

If you have no Drush but can run raw SQL, use a PHP script or external tool to deserialize. Or query the data tables directly since vocabulary metadata is also readable from term data:

```sql
-- Vocabularies present in the system (from term data)
SELECT DISTINCT vid FROM taxonomy_term_field_data ORDER BY vid;
```

This gives machine names but not labels or descriptions. For those you need the config table.

#### Complete Term Export via SQL

```sql
-- Full term export with parent hierarchy
SELECT
  td.tid,
  td.uuid,
  tfd.vid,
  tfd.langcode,
  tfd.name,
  tfd.description__value AS description,
  tfd.description__format AS description_format,
  tfd.weight,
  tfd.status,
  tfd.changed,
  tfd.default_langcode,
  GROUP_CONCAT(ttp.parent_target_id ORDER BY ttp.parent_target_id) AS parent_tids
FROM taxonomy_term_data td
JOIN taxonomy_term_field_data tfd
  ON td.tid = tfd.tid AND tfd.default_langcode = 1
LEFT JOIN taxonomy_term__parent ttp
  ON td.tid = ttp.entity_id
GROUP BY td.tid, td.uuid, tfd.vid, tfd.langcode, tfd.name,
         tfd.description__value, tfd.description__format,
         tfd.weight, tfd.status, tfd.changed, tfd.default_langcode
ORDER BY tfd.vid, tfd.weight, tfd.name;
```

The `parent_tids` column will contain comma-separated parent tids. A value of `0` means root. A value like `0,15` means the term is both a root and a child of tid 15 (unusual but possible with polyhierarchy). Filter out `0` values when building the parent list.

#### Depth Calculation

Drupal does not store term depth. Calculate it by walking the parent chain.

SQL-only approach using a recursive CTE (MySQL 8.0+, MariaDB 10.2+, PostgreSQL):

```sql
-- Calculate depth for all terms
WITH RECURSIVE term_tree AS (
  -- Base case: root terms (parent = 0)
  SELECT
    ttp.entity_id AS tid,
    0 AS depth
  FROM taxonomy_term__parent ttp
  WHERE ttp.parent_target_id = 0
    AND ttp.entity_id NOT IN (
      SELECT entity_id FROM taxonomy_term__parent WHERE parent_target_id != 0
    )

  UNION ALL

  -- Recursive case: children
  SELECT
    ttp.entity_id AS tid,
    tt.depth + 1
  FROM taxonomy_term__parent ttp
  JOIN term_tree tt ON ttp.parent_target_id = tt.tid
  WHERE ttp.parent_target_id != 0
)
SELECT
  tfd.vid,
  tt.tid,
  tfd.name,
  tt.depth
FROM term_tree tt
JOIN taxonomy_term_field_data tfd ON tt.tid = tfd.tid AND tfd.default_langcode = 1
ORDER BY tfd.vid, tt.depth, tfd.weight, tfd.name;
```

For polyhierarchical terms (multiple parents), this CTE produces multiple rows per term with different depths. Take the minimum depth if you need a single value. Flag these terms in the export.

Simpler depth calculation via Drush (uses Drupal's built-in tree builder):

```bash
drush php:eval '
$vids = array_keys(\Drupal::entityTypeManager()
  ->getStorage("taxonomy_vocabulary")
  ->loadMultiple());

foreach ($vids as $vid) {
  $tree = \Drupal::entityTypeManager()
    ->getStorage("taxonomy_term")
    ->loadTree($vid);
  foreach ($tree as $term) {
    echo json_encode([
      "tid" => $term->tid,
      "vid" => $vid,
      "name" => $term->name,
      "depth" => $term->depth,
      "parents" => $term->parents,
    ]) . "\n";
  }
}
'
```

`loadTree()` returns a flat array with a `depth` property (0-indexed) and a `parents` array. It handles polyhierarchy by including the term once per parent path.

### Method 5: Database Direct (D7)

#### Vocabulary Definitions

```sql
SELECT
  vid,
  name,
  machine_name,
  description,
  hierarchy,
  module,
  weight
FROM taxonomy_vocabulary
ORDER BY weight, name;
```

The `hierarchy` column values:
- `0` = no hierarchy (flat list)
- `1` = single parent hierarchy
- `2` = multiple parent hierarchy (polyhierarchy)

This column is advisory. Drupal sets it based on observed data but does not enforce it.

#### Term Data

```sql
SELECT
  td.tid,
  td.vid,
  tv.machine_name AS vocabulary_machine_name,
  td.name,
  td.description,
  td.format,
  td.weight
FROM taxonomy_term_data td
JOIN taxonomy_vocabulary tv ON td.vid = tv.vid
ORDER BY tv.machine_name, td.weight, td.name;
```

#### Hierarchy

```sql
SELECT
  tid,
  parent
FROM taxonomy_term_hierarchy
ORDER BY tid;
```

Same pattern as D8+: `parent = 0` means root. Multiple rows per tid means polyhierarchy.

#### Depth Calculation (D7)

Recursive CTE (MySQL 8.0+):

```sql
WITH RECURSIVE term_tree AS (
  SELECT
    th.tid,
    0 AS depth
  FROM taxonomy_term_hierarchy th
  WHERE th.parent = 0
    AND th.tid NOT IN (
      SELECT tid FROM taxonomy_term_hierarchy WHERE parent != 0
    )

  UNION ALL

  SELECT
    th.tid,
    tt.depth + 1
  FROM taxonomy_term_hierarchy th
  JOIN term_tree tt ON th.parent = tt.tid
  WHERE th.parent != 0
)
SELECT
  td.tid,
  tv.machine_name AS vid,
  td.name,
  tt.depth
FROM term_tree tt
JOIN taxonomy_term_data td ON tt.tid = td.tid
JOIN taxonomy_vocabulary tv ON td.vid = tv.vid
ORDER BY tv.machine_name, tt.depth, td.weight, td.name;
```

For MySQL 5.x (common with D7 sites), recursive CTEs are not available. Use Drush or an iterative PHP script:

```bash
drush php-eval '
$vocabs = taxonomy_get_vocabularies();
foreach ($vocabs as $vocab) {
  $tree = taxonomy_get_tree($vocab->vid);
  foreach ($tree as $term) {
    echo json_encode([
      "tid" => (int) $term->tid,
      "vid" => $vocab->machine_name,
      "name" => $term->name,
      "depth" => (int) $term->depth,
      "parents" => $term->parents,
    ]) . "\n";
  }
}
'
```

#### D7 Custom Fields on Terms

```sql
-- Find all fields attached to taxonomy terms in D7
SELECT
  fci.field_name,
  fci.bundle,
  fc.type AS field_type,
  fc.cardinality,
  fci.data AS instance_data,
  fc.data AS storage_data
FROM field_config_instance fci
JOIN field_config fc ON fc.id = fci.field_id
WHERE fci.entity_type = 'taxonomy_term'
  AND fci.deleted = 0
  AND fc.deleted = 0
  AND fc.active = 1
ORDER BY fci.bundle, fci.field_name;
```

Then query each field's data table:

```sql
-- Example: field_category_color on taxonomy terms
SELECT
  entity_id AS tid,
  bundle,
  delta,
  field_category_color_value
FROM field_data_field_category_color
WHERE entity_type = 'taxonomy_term'
ORDER BY entity_id, delta;
```

#### D7 Term Path Aliases

```sql
SELECT
  source,
  alias,
  language
FROM url_alias
WHERE source LIKE 'taxonomy/term/%'
ORDER BY source;
```

Note: D7 paths do not have a leading slash. The source is `taxonomy/term/42`, not `/taxonomy/term/42`.

#### D7 Term Translations (i18n_taxonomy)

The `i18n_taxonomy` module supports three translation modes per vocabulary:

| Mode | How It Works |
|---|---|
| Localize | Terms stay the same; names and descriptions are translated via the locale system (`locales_source` / `locales_target`) |
| Translate | Each term has a translation set. Separate term entities per language, linked by `i18n_tsid` in `taxonomy_term_data` (if the column exists) or via the `i18n_translation` table |
| Fixed language | Each term is in one language. No translation. |

For Localize mode:

```sql
-- Get translated term names
SELECT
  ls.source AS original_name,
  ls.context,
  lt.translation,
  lt.language
FROM locales_source ls
JOIN locales_target lt ON ls.lid = lt.lid
WHERE ls.textgroup = 'taxonomy'
ORDER BY ls.source, lt.language;
```

For Translate mode:

```sql
-- Get translation sets
SELECT
  ts.tsid,
  ts.type,
  td.tid,
  td.name,
  td.language
FROM i18n_translation_set ts
JOIN taxonomy_term_data td ON td.tid = ... -- join depends on i18n version
WHERE ts.type = 'taxonomy_term'
ORDER BY ts.tsid, td.language;
```

The exact join depends on whether the site uses `i18n_tsid` column on `taxonomy_term_data` or the `i18n_translation` mapping table. Check which exists:

```sql
-- Check if i18n_tsid column exists
SHOW COLUMNS FROM taxonomy_term_data LIKE 'i18n_tsid';

-- Check if i18n_translation table exists
SHOW TABLES LIKE 'i18n_translation%';
```

#### D7 Usage Map (taxonomy_index)

```sql
-- Which nodes reference which terms (core taxonomy reference fields only)
SELECT
  ti.tid,
  td.name AS term_name,
  tv.machine_name AS vocabulary,
  COUNT(DISTINCT ti.nid) AS node_count
FROM taxonomy_index ti
JOIN taxonomy_term_data td ON ti.tid = td.tid
JOIN taxonomy_vocabulary tv ON td.vid = tv.vid
GROUP BY ti.tid, td.name, tv.machine_name
ORDER BY tv.machine_name, node_count DESC;
```

For entityreference fields targeting taxonomy terms (not tracked by `taxonomy_index`):

```sql
-- Find entityreference fields targeting taxonomy_term
SELECT fc.field_name, fc.data
FROM field_config fc
WHERE fc.type = 'entityreference'
  AND fc.deleted = 0
  AND fc.active = 1;
-- Then check the serialized data for target_type = 'taxonomy_term'
```

---

## Polyhierarchy Handling

Most target platforms support single-parent hierarchies only. When the export detects polyhierarchy, the agent must:

1. Flag it. Include a `polyhierarchy_detected` boolean in the export.
2. List affected terms. Include a `polyhierarchical_terms` array with each term's tid, name, and list of parent tids.
3. Recommend a resolution strategy. Options:
   - **Primary parent**: Keep only the first (lowest weight) parent. Discard additional parents.
   - **Duplicate**: Create copies of the term under each parent. Requires de-duplication logic for references.
   - **Tag-based**: Flatten the hierarchy into a flat tag system. Loses hierarchy but preserves all associations.
   - **Preserve**: If the target supports it (some graph-based systems do), keep all parent relationships.

The agent should not make this decision. Present the options and let the user choose.

---

## Term Depth Calculation

Depth is the distance from a root term. Root terms have depth 0. Direct children of root terms have depth 1. And so on.

For polyhierarchical terms, the same term can appear at different depths depending on which parent path you follow. The export should include:
- `min_depth`: shortest path to a root
- `max_depth`: longest path to a root
- `depth`: same as `min_depth` (used by most target platforms)

Calculate depth after loading all terms and parents. Algorithm:

```
1. Build adjacency list: term -> [parent_tids]
2. Identify roots: terms where all parent_tids are 0 or empty
3. BFS from all roots simultaneously:
   - Set depth = 0 for all roots
   - For each root, visit its children (terms that list it as parent)
   - Set child depth = parent depth + 1 (keep minimum if already set)
4. Terms with no path to a root: flag as orphans
```

Orphan detection:

```sql
-- D8+ orphan terms: reference a parent that does not exist
SELECT
  ttp.entity_id AS tid,
  tfd.name,
  tfd.vid,
  ttp.parent_target_id AS missing_parent_tid
FROM taxonomy_term__parent ttp
JOIN taxonomy_term_field_data tfd ON ttp.entity_id = tfd.tid AND tfd.default_langcode = 1
LEFT JOIN taxonomy_term_data td_parent ON ttp.parent_target_id = td_parent.tid
WHERE ttp.parent_target_id != 0
  AND td_parent.tid IS NULL;
```

```sql
-- D7 orphan terms
SELECT
  th.tid,
  td.name,
  tv.machine_name AS vid,
  th.parent AS missing_parent_tid
FROM taxonomy_term_hierarchy th
JOIN taxonomy_term_data td ON th.tid = td.tid
JOIN taxonomy_vocabulary tv ON td.vid = tv.vid
LEFT JOIN taxonomy_term_data td_parent ON th.parent = td_parent.tid
WHERE th.parent != 0
  AND td_parent.tid IS NULL;
```

---

## Export Output Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Drupal Taxonomy Export",
  "type": "object",
  "required": ["drupal_version", "exported_at", "vocabularies", "terms"],
  "properties": {
    "drupal_version": {
      "type": "string",
      "description": "Major version: '7', '8', '9', '10', or '11'"
    },
    "exported_at": {
      "type": "string",
      "format": "date-time"
    },
    "polyhierarchy_detected": {
      "type": "boolean",
      "description": "True if any term has multiple parents"
    },
    "orphan_terms_detected": {
      "type": "boolean",
      "description": "True if any term references a non-existent parent"
    },
    "vocabularies": {
      "type": "object",
      "description": "Keyed by vocabulary machine name",
      "additionalProperties": {
        "$ref": "#/definitions/vocabulary"
      }
    },
    "terms": {
      "type": "array",
      "items": {
        "$ref": "#/definitions/term"
      }
    },
    "usage_map": {
      "type": "array",
      "description": "Which fields on which bundles reference each vocabulary",
      "items": {
        "$ref": "#/definitions/usage_entry"
      }
    },
    "polyhierarchical_terms": {
      "type": "array",
      "description": "Terms with multiple parents. Empty if polyhierarchy_detected is false.",
      "items": {
        "type": "object",
        "properties": {
          "tid": { "type": "integer" },
          "name": { "type": "string" },
          "vid": { "type": "string" },
          "parent_tids": {
            "type": "array",
            "items": { "type": "integer" }
          }
        }
      }
    },
    "orphan_terms": {
      "type": "array",
      "description": "Terms referencing non-existent parents",
      "items": {
        "type": "object",
        "properties": {
          "tid": { "type": "integer" },
          "name": { "type": "string" },
          "vid": { "type": "string" },
          "missing_parent_tid": { "type": "integer" }
        }
      }
    }
  },
  "definitions": {
    "vocabulary": {
      "type": "object",
      "required": ["machine_name", "label"],
      "properties": {
        "machine_name": {
          "type": "string"
        },
        "label": {
          "type": "string"
        },
        "description": {
          "type": ["string", "null"]
        },
        "langcode": {
          "type": ["string", "null"],
          "description": "D8+ only"
        },
        "weight": {
          "type": "integer"
        },
        "hierarchy_type": {
          "type": "string",
          "enum": ["flat", "single", "multiple"],
          "description": "flat = no parents, single = tree, multiple = polyhierarchy. Derived from data in D8+. From hierarchy column in D7."
        },
        "term_count": {
          "type": "integer",
          "description": "Total terms in this vocabulary (default language only)"
        },
        "max_depth": {
          "type": "integer",
          "description": "Deepest nesting level (0 = flat)"
        },
        "custom_fields": {
          "type": "array",
          "description": "Custom fields attached to terms in this vocabulary",
          "items": {
            "type": "object",
            "properties": {
              "field_name": { "type": "string" },
              "field_type": { "type": "string" },
              "label": { "type": "string" },
              "required": { "type": "boolean" },
              "cardinality": { "type": "integer" },
              "settings": { "type": "object" }
            }
          }
        },
        "languages": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Language codes with translated terms in this vocabulary"
        }
      }
    },
    "term": {
      "type": "object",
      "required": ["tid", "vid", "name"],
      "properties": {
        "tid": {
          "type": "integer"
        },
        "uuid": {
          "type": ["string", "null"],
          "description": "D8+ only"
        },
        "vid": {
          "type": "string",
          "description": "Vocabulary machine name"
        },
        "name": {
          "type": "string"
        },
        "description": {
          "type": ["string", "null"]
        },
        "description_format": {
          "type": ["string", "null"],
          "description": "Text format machine name (e.g., basic_html, full_html)"
        },
        "weight": {
          "type": "integer"
        },
        "status": {
          "type": "integer",
          "enum": [0, 1],
          "description": "1 = published, 0 = unpublished. Always 1 in D7."
        },
        "langcode": {
          "type": "string"
        },
        "parent_tids": {
          "type": "array",
          "items": { "type": "integer" },
          "description": "Empty array for root terms. Multiple entries for polyhierarchical terms."
        },
        "depth": {
          "type": "integer",
          "description": "Minimum depth from root (0 = root term)"
        },
        "path_alias": {
          "type": ["string", "null"],
          "description": "URL alias if one exists (e.g., /topics/javascript)"
        },
        "changed": {
          "type": ["integer", "null"],
          "description": "UNIX timestamp of last change. D8+ only."
        },
        "translations": {
          "type": "array",
          "description": "Non-default-language versions of this term",
          "items": {
            "type": "object",
            "properties": {
              "langcode": { "type": "string" },
              "name": { "type": "string" },
              "description": { "type": ["string", "null"] }
            }
          }
        },
        "custom_fields": {
          "type": "object",
          "description": "Keyed by field machine name. Values vary by field type.",
          "additionalProperties": {}
        }
      }
    },
    "usage_entry": {
      "type": "object",
      "required": ["vocabulary", "referencing_entity_type", "referencing_bundle", "field_name"],
      "properties": {
        "vocabulary": {
          "type": "string",
          "description": "Vocabulary machine name"
        },
        "referencing_entity_type": {
          "type": "string",
          "description": "e.g., node, block_content, paragraph, media"
        },
        "referencing_bundle": {
          "type": "string",
          "description": "e.g., article, page, hero_banner"
        },
        "field_name": {
          "type": "string"
        },
        "cardinality": {
          "type": "integer",
          "description": "1, -1, or N"
        },
        "auto_create": {
          "type": "boolean",
          "description": "Whether this field creates new terms on save"
        },
        "required": {
          "type": "boolean"
        }
      }
    }
  }
}
```

---

## Example Output

```json
{
  "drupal_version": "10",
  "exported_at": "2025-01-15T14:30:00Z",
  "polyhierarchy_detected": false,
  "orphan_terms_detected": false,
  "vocabularies": {
    "tags": {
      "machine_name": "tags",
      "label": "Tags",
      "description": "Use tags to group articles on similar topics.",
      "langcode": "en",
      "weight": 0,
      "hierarchy_type": "flat",
      "term_count": 47,
      "max_depth": 0,
      "custom_fields": [],
      "languages": ["en"]
    },
    "categories": {
      "machine_name": "categories",
      "label": "Categories",
      "description": "Site-wide content categories.",
      "langcode": "en",
      "weight": 0,
      "hierarchy_type": "single",
      "term_count": 12,
      "max_depth": 2,
      "custom_fields": [
        {
          "field_name": "field_icon",
          "field_type": "image",
          "label": "Icon",
          "required": false,
          "cardinality": 1,
          "settings": {
            "file_extensions": "png svg",
            "alt_field_required": true
          }
        },
        {
          "field_name": "field_color",
          "field_type": "string",
          "label": "Brand Color",
          "required": true,
          "cardinality": 1,
          "settings": {}
        }
      ],
      "languages": ["en", "fr", "es"]
    }
  },
  "terms": [
    {
      "tid": 1,
      "uuid": "a1b2c3d4-e5f6-7890-abcd-000000000001",
      "vid": "categories",
      "name": "Technology",
      "description": "Articles about technology and software.",
      "description_format": "basic_html",
      "weight": 0,
      "status": 1,
      "langcode": "en",
      "parent_tids": [],
      "depth": 0,
      "path_alias": "/topics/technology",
      "changed": 1705334400,
      "translations": [
        {"langcode": "fr", "name": "Technologie", "description": "Articles sur la technologie."},
        {"langcode": "es", "name": "Tecnologia", "description": "Articulos sobre tecnologia."}
      ],
      "custom_fields": {
        "field_icon": {
          "target_id": 42,
          "alt": "Technology icon",
          "title": "",
          "width": 64,
          "height": 64
        },
        "field_color": "#0066CC"
      }
    },
    {
      "tid": 5,
      "uuid": "a1b2c3d4-e5f6-7890-abcd-000000000005",
      "vid": "categories",
      "name": "Web Development",
      "description": null,
      "description_format": null,
      "weight": 0,
      "status": 1,
      "langcode": "en",
      "parent_tids": [1],
      "depth": 1,
      "path_alias": "/topics/web-development",
      "changed": 1705334500,
      "translations": [
        {"langcode": "fr", "name": "Developpement Web", "description": null}
      ],
      "custom_fields": {
        "field_icon": null,
        "field_color": "#0099FF"
      }
    }
  ],
  "usage_map": [
    {
      "vocabulary": "tags",
      "referencing_entity_type": "node",
      "referencing_bundle": "article",
      "field_name": "field_tags",
      "cardinality": -1,
      "auto_create": true,
      "required": false
    },
    {
      "vocabulary": "categories",
      "referencing_entity_type": "node",
      "referencing_bundle": "article",
      "field_name": "field_category",
      "cardinality": 1,
      "auto_create": false,
      "required": true
    },
    {
      "vocabulary": "categories",
      "referencing_entity_type": "node",
      "referencing_bundle": "page",
      "field_name": "field_category",
      "cardinality": 1,
      "auto_create": false,
      "required": false
    }
  ],
  "polyhierarchical_terms": [],
  "orphan_terms": []
}
```

---

## Execution Order

1. **Detect vocabularies.** Use config YAML, Drush, or database. Count them.
2. **Export vocabulary definitions.** Machine name, label, description, weight.
3. **Export field definitions on terms.** Custom fields per vocabulary.
4. **Export terms.** All terms with name, description, weight, status, langcode.
5. **Export hierarchy.** Parent relationships for all terms. Detect polyhierarchy.
6. **Calculate depth.** Walk the parent chain. Flag orphans.
7. **Export path aliases.** Match aliases to term tids.
8. **Export translations.** Non-default-language term names and descriptions.
9. **Build usage map.** Scan entity reference fields targeting `taxonomy_term`. Map each to its vocabulary via `handler_settings.target_bundles`.
10. **Assemble output.** Combine all data into the schema above. Validate.

---

## Edge Cases

### Empty Vocabularies

Some sites define vocabularies with zero terms. Still export the vocabulary definition and its custom fields. Set `term_count: 0` and `max_depth: 0`.

### Deleted Terms

D8+ soft-deletes terms. The `taxonomy_term__parent` table has a `deleted` column. Filter it:

```sql
SELECT entity_id, parent_target_id
FROM taxonomy_term__parent
WHERE deleted = 0;
```

D7 has no soft-delete for terms. Deleted terms are gone.

### Very Large Vocabularies

Some sites have vocabularies with 100,000+ terms (product categories, geographic locations). For these:
- Use batched SQL queries with `LIMIT`/`OFFSET` or cursor-based pagination on tid.
- Stream to JSONL instead of building one large JSON array in memory.
- Calculate depth iteratively, not recursively, to avoid stack overflow.

### Vocabulary with No Hierarchy Column (D8+)

D8+ does not store a hierarchy type. Derive it:

```sql
-- Check hierarchy type for each vocabulary
SELECT
  tfd.vid,
  CASE
    WHEN MAX(ttp.parent_target_id) = 0 THEN 'flat'
    WHEN MAX(parent_count) > 1 THEN 'multiple'
    ELSE 'single'
  END AS hierarchy_type
FROM taxonomy_term_field_data tfd
LEFT JOIN taxonomy_term__parent ttp ON tfd.tid = ttp.entity_id AND ttp.deleted = 0
LEFT JOIN (
  SELECT entity_id, COUNT(*) AS parent_count
  FROM taxonomy_term__parent
  WHERE parent_target_id != 0 AND deleted = 0
  GROUP BY entity_id
) pc ON tfd.tid = pc.entity_id
WHERE tfd.default_langcode = 1
GROUP BY tfd.vid;
```

### Terms Referenced by Non-Standard Handlers

Some entity reference fields use custom selection handlers (`views`, `og`, etc.) instead of `default:taxonomy_term`. The usage map query should check the `handler` setting. If it is `views`, the allowed vocabularies are filtered by the View's configuration, not by `target_bundles`. Note this in the export but do not attempt to parse the View's filters here. Cross-reference with Skill 05 output.

### D7 taxonomy_term_reference vs entityreference

D7 has two field types that reference taxonomy terms:
- `taxonomy_term_reference` (core): uses the `taxonomy_index` table. Stored in `field_data_field_{name}` with a `{field_name}_tid` column.
- `entityreference` (contrib): targets `taxonomy_term`. Stored in `field_data_field_{name}` with a `{field_name}_target_id` column.

The usage map must check both. The `taxonomy_index` table only tracks `taxonomy_term_reference` fields, not `entityreference` fields.

```sql
-- D7: Find all taxonomy_term_reference fields
SELECT fc.field_name, fci.bundle, fci.entity_type, fc.data AS storage_data
FROM field_config fc
JOIN field_config_instance fci ON fc.id = fci.field_id
WHERE fc.type = 'taxonomy_term_reference'
  AND fc.deleted = 0 AND fc.active = 1
  AND fci.deleted = 0;

-- D7: Find all entityreference fields targeting taxonomy_term
SELECT fc.field_name, fci.bundle, fci.entity_type, fc.data AS storage_data
FROM field_config fc
JOIN field_config_instance fci ON fc.id = fci.field_id
WHERE fc.type = 'entityreference'
  AND fc.deleted = 0 AND fc.active = 1
  AND fci.deleted = 0;
-- Then filter by deserializing storage_data and checking
-- settings.target_type = 'taxonomy_term'
```
