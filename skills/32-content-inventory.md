# Skill 32: Content Inventory and Audit

Generate a full content inventory for migration planning. One row per content item with metadata, quality indicators, and cross-referenced orphan detection. Output as CSV, JSON, or markdown.

Run Skills 1 (site audit), 2 (content model map), 13 (taxonomy export), and 14 (media files) first. This skill consumes their output and adds inventory-specific analysis on top.

---

## What Gets Produced

### Primary Inventory Table

One row per node. Every published and unpublished node across all content types.

| Column | Source | Notes |
|---|---|---|
| `nid` | `node_field_data.nid` | Drupal node ID |
| `uuid` | `node_field_data.uuid` | Stable cross-environment identifier |
| `type` | `node_field_data.type` | Content type machine name |
| `title` | `node_field_data.title` | Plain text |
| `path` | `path_alias.alias` | URL alias. Falls back to `/node/{nid}` when no alias exists |
| `status` | `node_field_data.status` | 1 = published, 0 = unpublished |
| `author` | `users_field_data.name` | Username of the `uid` on the node |
| `author_uid` | `node_field_data.uid` | Numeric user ID |
| `created` | `node_field_data.created` | UNIX timestamp. Format to ISO 8601 in output. |
| `changed` | `node_field_data.changed` | UNIX timestamp. Format to ISO 8601 in output. |
| `word_count` | Calculated | Word count from body and text fields. See calculation section. |
| `has_image` | Calculated | `true` if any image or media image field has a value |
| `langcode` | `node_field_data.langcode` | BCP 47 language code |
| `translation_languages` | Calculated | Comma-separated list of other languages this node is translated into |
| `tags` | Calculated | Comma-separated taxonomy term names from all term reference fields |
| `moderation_state` | `content_moderation_state_field_data.moderation_state` | Only present when Content Moderation module is enabled. Values like `draft`, `published`, `archived`. |
| `is_stale` | Calculated | `true` if `changed` is older than 365 days from now |
| `days_since_update` | Calculated | Integer days between `changed` and the export date |
| `revision_count` | Calculated | Total revision count for this node |
| `empty_required_fields` | Calculated | Comma-separated list of required field names that have no value |
| `broken_internal_links` | Calculated | Count of `<a href="/node/...">` or `<a href="/...">` links in body text pointing to nonexistent nodes or aliases |
| `missing_images` | Calculated | Count of `<img>` tags in body text referencing files that do not exist in `file_managed` |

### Summary Sections

Generate these alongside the main inventory:

1. **Counts by content type**: type, total count, published count, unpublished count, average word count
2. **Counts by author**: author name, uid, total nodes, most recent publish date
3. **Counts by year-month**: year-month bucket, count of nodes created, count of nodes last updated
4. **Counts by status**: published vs unpublished, with breakdown per content type
5. **Stale content**: nodes not updated in over 365 days, grouped by content type
6. **Content quality summary**: total nodes with empty required fields, total with broken links, total with missing images

### Orphan Reports

Three orphan detection reports:

1. **Orphaned media**: Media entities not referenced by any node, paragraph, or block content entity
2. **Unused taxonomy terms**: Terms not referenced by any entity through any entity reference field
3. **Detached paragraphs**: Paragraph entities whose parent entity no longer exists or whose parent field no longer references them

---

## Prerequisites

1. **Access method** confirmed from Skill 01. Database access gives the most complete inventory. JSON:API works but requires many paginated requests. Drush sql:query bridges the gap.
2. **Content model map** from Skill 02. You need the field list per content type to know which fields are text (for word count), which are entity references to media (for has_image), which are taxonomy references (for tags), and which fields are required.
3. **Media export** from Skill 14. Needed for orphan detection. The media usage map tells you which media entities are referenced and which are not.
4. **Taxonomy export** from Skill 13. Needed for unused term detection.

---

## Access Methods

| Priority | Method | Strengths | Limitations |
|---|---|---|---|
| 1 | Database | Full access to all tables. JOINs across node, path, user, media usage in single queries. Fastest for large sites. | Requires DB credentials or tunnel |
| 2 | Drush `sql:query` | Executes SQL without direct DB access. Works over SSH. | Same SQL, just a different transport |
| 3 | JSON:API | No server access needed. Works against any D9+ site with JSON:API enabled. | Paginated. Slow for large sites. No direct orphan detection. |

Use database or Drush for sites with more than 1,000 nodes. JSON:API pagination at 50 items per page means 20 requests per 1,000 nodes, and that is before relationship resolution.

---

## Step 1: Build the Primary Inventory

### Method A: Database (D9/D10/D11)

This single query produces the core inventory row for every node:

```sql
SELECT
  n.nid,
  n.uuid,
  n.type,
  n.title,
  COALESCE(pa.alias, CONCAT('/node/', n.nid)) AS path,
  n.status,
  u.name AS author,
  n.uid AS author_uid,
  n.created,
  n.changed,
  n.langcode,
  n.default_langcode
FROM node_field_data n
LEFT JOIN path_alias pa
  ON pa.path = CONCAT('/node/', n.nid)
  AND pa.langcode = n.langcode
LEFT JOIN users_field_data u
  ON u.uid = n.uid
WHERE n.default_langcode = 1
ORDER BY n.type, n.nid;
```

Notes on this query:
- `default_langcode = 1` returns one row per node (the default translation). Translations are handled separately.
- `path_alias` joined on the system path `/node/{nid}` and matching langcode. Some aliases lack a langcode match; widen to `pa.langcode IN (n.langcode, 'und')` if aliases come back NULL on a multilingual site.
- D7 uses `url_alias` instead of `path_alias`, and `source` instead of `path`: `pa.source = CONCAT('node/', n.nid)`.

### Method A (Drush wrapper)

```bash
drush sql:query "
  SELECT
    n.nid, n.uuid, n.type, n.title,
    COALESCE(pa.alias, CONCAT('/node/', n.nid)) AS path,
    n.status, u.name AS author, n.uid AS author_uid,
    n.created, n.changed, n.langcode
  FROM node_field_data n
  LEFT JOIN path_alias pa
    ON pa.path = CONCAT('/node/', n.nid)
    AND pa.langcode = n.langcode
  LEFT JOIN users_field_data u
    ON u.uid = n.uid
  WHERE n.default_langcode = 1
  ORDER BY n.type, n.nid
" --extra-dump="--tab" > inventory_base.tsv
```

If `--extra-dump` is unavailable, pipe through `sed 's/\t/,/g'` for quick CSV conversion or use `--format=csv` if the Drush version supports it.

### Method B: JSON:API (D9+)

For each content type discovered in the Skill 02 output:

```
GET /jsonapi/node/{bundle}?fields[node--{bundle}]=title,status,created,changed,langcode,path,uid&include=uid&fields[user--user]=name&page[limit]=50&page[offset]=0&sort=nid
```

Parse each response:
- `data[].id` = UUID
- `data[].attributes.drupal_internal__nid` = NID
- `data[].attributes.title` = Title
- `data[].attributes.status` = Boolean (JSON:API returns true/false, not 1/0)
- `data[].attributes.created` = ISO 8601 timestamp
- `data[].attributes.changed` = ISO 8601 timestamp
- `data[].attributes.langcode` = Language code
- `data[].attributes.path.alias` = URL alias (null if none)
- `data[].relationships.uid.data.id` = Author UUID (resolve from `included[]`)

Follow `links.next.href` until it returns no next link. Collect all pages into one array per content type.

---

## Step 2: Translation Languages

For each node, find all translations and list the non-default language codes.

### Database

```sql
SELECT
  n.nid,
  GROUP_CONCAT(t.langcode ORDER BY t.langcode SEPARATOR ', ') AS translation_languages
FROM node_field_data n
INNER JOIN node_field_data t
  ON t.nid = n.nid
  AND t.default_langcode = 0
WHERE n.default_langcode = 1
GROUP BY n.nid;
```

Join this result to the base inventory on `nid`. Nodes without translations get an empty `translation_languages` value.

### JSON:API

JSON:API does not return sibling translations in the same response. For each node with translations, the `links` object contains `self` URLs per language. Check for the presence of the `translations` link or query each language prefix:

```
GET /{langcode}/jsonapi/node/{bundle}/{uuid}
```

This is expensive. For inventory purposes, use database access if available.

---

## Step 3: Word Count

Calculate word count from all text fields on each node. "Text fields" means fields of type `text`, `text_long`, `text_with_summary`, and `string_long`.

### Database

First, get the list of text fields per content type from the Skill 02 content model map. For each text field `field_{name}` on content type `{bundle}`:

```sql
SELECT
  entity_id AS nid,
  COALESCE(
    LENGTH(body_value) - LENGTH(REPLACE(body_value, ' ', '')) + 1,
    0
  ) AS word_count_estimate
FROM node__body
WHERE bundle = '{bundle}' AND langcode = '{langcode}';
```

That formula counts spaces. It over-counts for HTML content. For a better estimate, strip HTML tags first:

```sql
-- MySQL does not have a built-in strip_tags function.
-- Use REGEXP_REPLACE on MySQL 8+ to remove HTML tags before counting words.
SELECT
  entity_id AS nid,
  LENGTH(REGEXP_REPLACE(body_value, '<[^>]+>', ''))
    - LENGTH(REPLACE(REGEXP_REPLACE(body_value, '<[^>]+>', ''), ' ', ''))
    + 1 AS word_count
FROM node__body
WHERE bundle = '{bundle}'
  AND langcode = '{default_langcode}'
  AND deleted = 0;
```

For multiple text fields on the same content type, query each field table and sum the word counts per node:

```sql
SELECT
  b.entity_id AS nid,
  (
    COALESCE(
      LENGTH(REGEXP_REPLACE(b.body_value, '<[^>]+>', ''))
      - LENGTH(REPLACE(REGEXP_REPLACE(b.body_value, '<[^>]+>', ''), ' ', ''))
      + 1, 0
    )
    +
    COALESCE(
      LENGTH(REGEXP_REPLACE(s.field_summary_value, '<[^>]+>', ''))
      - LENGTH(REPLACE(REGEXP_REPLACE(s.field_summary_value, '<[^>]+>', ''), ' ', ''))
      + 1, 0
    )
  ) AS total_word_count
FROM node__body b
LEFT JOIN node__field_summary s
  ON s.entity_id = b.entity_id
  AND s.deleted = 0
WHERE b.bundle = '{bundle}'
  AND b.deleted = 0;
```

Adapt this pattern for every text field in the content model. The agent should generate the query dynamically based on the Skill 02 field inventory.

For paragraph-heavy content types, word count from node-level fields alone misses most of the text. Query paragraph text fields too:

```sql
-- Get paragraph IDs attached to a node
SELECT field_content_target_id AS paragraph_id
FROM node__field_content
WHERE entity_id = {nid} AND deleted = 0;

-- Then get text from paragraph text fields
SELECT entity_id, field_body_value
FROM paragraph__field_body
WHERE entity_id IN ({paragraph_ids}) AND deleted = 0;
```

Recurse through nested paragraphs by following `entity_reference_revisions` fields on paragraph types (same recursion pattern as Skill 12). Sum all text field word counts across the full paragraph tree and add them to the node's total.

### JSON:API

Request body fields with sparse fieldsets:

```
GET /jsonapi/node/{bundle}?fields[node--{bundle}]=body&page[limit]=50
```

Parse `data[].attributes.body.value` (the raw HTML). Strip tags client-side, split on whitespace, count.

For paragraph content, include paragraph relationships and their text fields. This gets complex fast. Prefer database access for word counts on paragraph-heavy sites.

### Post-Processing (any method)

After collecting raw text from all sources:

1. Strip all HTML tags
2. Decode HTML entities (`&amp;` to `&`, `&nbsp;` to space)
3. Collapse whitespace (multiple spaces, tabs, newlines to single space)
4. Split on whitespace
5. Count tokens. Ignore empty strings.

This gives a word count accurate enough for migration planning. Exact counts do not matter. What matters is identifying zero-word nodes (empty content) and distinguishing short-form content (<100 words) from long-form (>1000 words).

---

## Step 4: Has Image

Detect whether each node has at least one image. Check two sources: image/media reference fields on the node and `<img>` tags in body text.

### Database

From the Skill 02 field map, identify fields of type `image` or `entity_reference` targeting `media` with image bundles.

```sql
-- Direct image field on node
SELECT DISTINCT entity_id AS nid
FROM node__field_image
WHERE deleted = 0 AND field_image_target_id IS NOT NULL;

-- Media reference field (need to check if the media entity is an image type)
SELECT DISTINCT nr.entity_id AS nid
FROM node__field_media nr
INNER JOIN media_field_data m ON m.mid = nr.field_media_target_id
WHERE nr.deleted = 0 AND m.bundle = 'image';

-- Inline images in body text
SELECT DISTINCT entity_id AS nid
FROM node__body
WHERE body_value LIKE '%<img%'
  AND deleted = 0;
```

Union all three queries. Any node appearing in the result set gets `has_image = true`.

For paragraph-based images, follow the same paragraph tree recursion from Step 3. Check image fields on paragraphs and inline images in paragraph text fields.

### JSON:API

Include image relationships in the request:

```
GET /jsonapi/node/{bundle}?include=field_image&fields[node--{bundle}]=field_image&page[limit]=50
```

A node has an image if `data[].relationships.field_image.data` is not null and not an empty array.

---

## Step 5: Tags and Taxonomy Terms

Collect all taxonomy term names attached to each node through any term reference field.

### Database

From the Skill 02 field map, identify all fields of type `entity_reference` targeting `taxonomy_term`.

```sql
-- For each taxonomy reference field (example: field_tags)
SELECT
  nr.entity_id AS nid,
  GROUP_CONCAT(t.name ORDER BY nr.delta SEPARATOR ', ') AS tags
FROM node__field_tags nr
INNER JOIN taxonomy_term_field_data t
  ON t.tid = nr.field_tags_target_id
  AND t.default_langcode = 1
WHERE nr.deleted = 0
GROUP BY nr.entity_id;
```

Run this for every taxonomy reference field. If a node has multiple taxonomy reference fields (e.g., `field_tags`, `field_categories`, `field_topics`), union the results and concatenate all term names into a single `tags` column, or keep them in separate columns per field.

### JSON:API

```
GET /jsonapi/node/{bundle}?include=field_tags&fields[node--{bundle}]=field_tags&fields[taxonomy_term--tags]=name&page[limit]=50
```

Resolve term names from the `included[]` array by matching `data[].relationships.field_tags.data[].id` to `included[].id`.

---

## Step 6: Moderation State

Only applies when the Content Moderation module is enabled.

### Database

```sql
SELECT
  cms.content_entity_id AS nid,
  cms.moderation_state
FROM content_moderation_state_field_data cms
WHERE cms.content_entity_type_id = 'node'
  AND cms.workflow = '{workflow_id}'
ORDER BY cms.content_entity_id;
```

Discover the workflow ID first:

```sql
SELECT DISTINCT workflow FROM content_moderation_state_field_data
WHERE content_entity_type_id = 'node';
```

If the Content Moderation module is not enabled (check Skill 01 module list), skip this column.

### Drush

```bash
drush sql:query "
  SELECT content_entity_id, moderation_state
  FROM content_moderation_state_field_data
  WHERE content_entity_type_id = 'node'
" 2>/dev/null
```

If the table does not exist, the module is not enabled. Catch the error and skip.

---

## Step 7: Revision Count

```sql
SELECT nid, COUNT(*) AS revision_count
FROM node_revision
GROUP BY nid;
```

Join to the base inventory on `nid`.

For D7:

```sql
SELECT nid, COUNT(*) AS revision_count
FROM node_revision
GROUP BY nid;
```

Same query. The table name is the same in D7 and D8+.

---

## Step 8: Stale Content Detection

Calculate staleness from the `changed` timestamp. No additional query needed. Compute during output generation:

```
days_since_update = (current_unix_timestamp - changed) / 86400
is_stale = days_since_update > 365
```

Adjust the threshold if the user specifies a different staleness window. 365 days is the default.

Group stale content by content type for the summary report:

```sql
SELECT
  type,
  COUNT(*) AS stale_count,
  MIN(changed) AS oldest_update,
  MAX(changed) AS newest_update
FROM node_field_data
WHERE changed < UNIX_TIMESTAMP() - (365 * 86400)
  AND default_langcode = 1
GROUP BY type
ORDER BY stale_count DESC;
```

---

## Step 9: Content Quality Indicators

### 9a. Empty Required Fields

From the Skill 02 content model map, identify required fields per content type. A field is required when its `field.field.*.yml` config has `required: true`.

For each required field, check whether the corresponding field table has a row for each node of that content type:

```sql
-- Example: field_body is required on content type 'article'
SELECT n.nid, n.title
FROM node_field_data n
LEFT JOIN node__body b
  ON b.entity_id = n.nid AND b.deleted = 0
WHERE n.type = 'article'
  AND n.default_langcode = 1
  AND (b.body_value IS NULL OR TRIM(b.body_value) = '' OR b.entity_id IS NULL);
```

Run this for every required field on every content type. Collect the field names with empty values per node.

### 9b. Broken Internal Links

Scan body text and text fields for internal links. Check whether the link targets exist.

```sql
-- Step 1: Extract nodes with body text containing internal links
SELECT nid, body_value
FROM node__body
WHERE body_value REGEXP 'href="/(node/[0-9]+|[^"]*)"'
  AND deleted = 0;
```

For each matched link:
- Links matching `/node/{nid}`: check that the target nid exists in `node_field_data`
- Links matching a path alias: check that the alias exists in `path_alias`

This requires application-level processing. The SQL extracts candidates. The agent parses the HTML, extracts `href` values, and cross-references them.

Parse approach:

1. Extract all `href` attribute values from `<a>` tags in body text
2. Filter to internal links (start with `/`, do not start with `//` or contain `://`)
3. For links like `/node/123`, extract the nid and check existence
4. For alias links like `/about-us/team`, query `path_alias` for a matching alias
5. Count broken links per node

### 9c. Missing Images in Body Text

Scan body text for `<img>` tags referencing site files that no longer exist.

```sql
SELECT nid, body_value
FROM node__body
WHERE body_value LIKE '%<img%'
  AND deleted = 0;
```

Parse each body value:

1. Extract `src` attribute values from `<img>` tags
2. Filter to internal image paths (contain `/sites/default/files/` or match the public file path pattern)
3. Convert the path back to a Drupal URI: `/sites/default/files/2024-01/photo.jpg` becomes `public://2024-01/photo.jpg`
4. Check existence in `file_managed`:

```sql
SELECT fid FROM file_managed WHERE uri = '{converted_uri}';
```

5. If no row exists, the image is missing. Count missing images per node.

---

## Step 10: Orphan Detection

### 10a. Orphaned Media Entities

A media entity is orphaned when no other entity references it. The reference can come from any entity type: node, paragraph, block_content, or another media entity.

First, build the complete set of referenced media IDs. From the Skill 02 field map, identify every field of type `entity_reference` targeting `media` across all entity types.

```sql
-- Collect all referenced media IDs from all entity reference fields targeting media
-- Repeat this pattern for every such field table

-- From node fields
SELECT DISTINCT field_media_target_id AS mid FROM node__field_media WHERE deleted = 0
UNION
SELECT DISTINCT field_image_target_id FROM node__field_image WHERE deleted = 0
UNION
-- From paragraph fields
SELECT DISTINCT field_media_target_id FROM paragraph__field_media WHERE deleted = 0
UNION
SELECT DISTINCT field_image_target_id FROM paragraph__field_image WHERE deleted = 0
UNION
-- From block_content fields
SELECT DISTINCT field_media_target_id FROM block_content__field_media WHERE deleted = 0;
```

The agent must generate this UNION query dynamically based on the full field inventory from Skill 02. Every field of type `entity_reference` or `image` targeting media or file entities must be included.

Then find media entities not in the referenced set:

```sql
SELECT m.mid, m.uuid, m.bundle, mfd.name, mfd.created, mfd.changed
FROM media m
INNER JOIN media_field_data mfd ON mfd.mid = m.mid AND mfd.default_langcode = 1
WHERE m.mid NOT IN (
  -- paste the UNION query from above as a subquery
  SELECT DISTINCT field_media_target_id FROM node__field_media WHERE deleted = 0
  UNION
  SELECT DISTINCT field_image_target_id FROM node__field_image WHERE deleted = 0
  -- ... all other media reference fields
)
ORDER BY mfd.changed DESC;
```

Also check for inline media embeds in body text. Drupal's media embed filter uses `<drupal-media data-entity-uuid="...">` tags. Extract UUIDs from body text and add them to the referenced set:

```sql
SELECT DISTINCT
  SUBSTRING(
    body_value,
    LOCATE('data-entity-uuid="', body_value) + 18,
    36
  ) AS embedded_uuid
FROM node__body
WHERE body_value LIKE '%data-entity-uuid="%'
  AND deleted = 0;
```

Convert these UUIDs to media IDs and add them to the referenced set before calculating orphans.

### 10b. Unused Taxonomy Terms

A taxonomy term is unused when no entity references it through any entity reference field targeting `taxonomy_term`.

Build the referenced term ID set the same way as media:

```sql
-- From each taxonomy reference field across all entity types
SELECT DISTINCT field_tags_target_id AS tid FROM node__field_tags WHERE deleted = 0
UNION
SELECT DISTINCT field_categories_target_id FROM node__field_categories WHERE deleted = 0
UNION
-- ... all other term reference fields from the Skill 02 field map
```

Also check `taxonomy_index` (maintained by core for default taxonomy reference fields):

```sql
SELECT DISTINCT tid FROM taxonomy_index;
```

Find unused terms:

```sql
SELECT t.tid, t.uuid, tfd.name, tfd.vid AS vocabulary, tfd.changed
FROM taxonomy_term_data t
INNER JOIN taxonomy_term_field_data tfd
  ON tfd.tid = t.tid AND tfd.default_langcode = 1
WHERE t.tid NOT IN (
  SELECT DISTINCT tid FROM taxonomy_index
  UNION
  -- all other term reference field tables
  SELECT DISTINCT field_tags_target_id FROM node__field_tags WHERE deleted = 0
)
ORDER BY tfd.vid, tfd.name;
```

### 10c. Detached Paragraphs

A paragraph is detached when its parent entity no longer exists or no longer references it.

Paragraphs are referenced through `entity_reference_revisions` fields. Each field table stores `entity_id` (parent), `field_{name}_target_id` (paragraph ID), and `field_{name}_target_revision_id`.

```sql
-- Build the set of paragraph IDs that ARE referenced
SELECT DISTINCT field_content_target_id AS paragraph_id
FROM node__field_content WHERE deleted = 0
UNION
SELECT DISTINCT field_cards_target_id
FROM paragraph__field_cards WHERE deleted = 0
UNION
-- ... all entity_reference_revisions fields from Skill 02
```

Find detached paragraphs:

```sql
SELECT p.id, p.uuid, p.type AS bundle, pfd.langcode, pfd.created
FROM paragraphs_item p
INNER JOIN paragraphs_item_field_data pfd
  ON pfd.id = p.id AND pfd.default_langcode = 1
WHERE p.id NOT IN (
  -- referenced paragraph IDs from above
  SELECT DISTINCT field_content_target_id FROM node__field_content WHERE deleted = 0
  UNION
  SELECT DISTINCT field_cards_target_id FROM paragraph__field_cards WHERE deleted = 0
)
ORDER BY p.type, p.id;
```

---

## Step 11: Summary Aggregations

Run these after the primary inventory is built. They aggregate data that already exists in the inventory rows.

### Counts by Content Type

```sql
SELECT
  type,
  COUNT(*) AS total,
  SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS published,
  SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS unpublished
FROM node_field_data
WHERE default_langcode = 1
GROUP BY type
ORDER BY total DESC;
```

### Counts by Author

```sql
SELECT
  u.name AS author,
  n.uid,
  COUNT(*) AS total_nodes,
  MAX(FROM_UNIXTIME(n.created)) AS most_recent_created
FROM node_field_data n
INNER JOIN users_field_data u ON u.uid = n.uid
WHERE n.default_langcode = 1
GROUP BY n.uid, u.name
ORDER BY total_nodes DESC;
```

### Counts by Year-Month

```sql
SELECT
  DATE_FORMAT(FROM_UNIXTIME(created), '%Y-%m') AS year_month,
  COUNT(*) AS created_count
FROM node_field_data
WHERE default_langcode = 1
GROUP BY year_month
ORDER BY year_month;

SELECT
  DATE_FORMAT(FROM_UNIXTIME(changed), '%Y-%m') AS year_month,
  COUNT(*) AS updated_count
FROM node_field_data
WHERE default_langcode = 1
GROUP BY year_month
ORDER BY year_month;
```

### Counts by Status

```sql
SELECT
  type,
  CASE WHEN status = 1 THEN 'published' ELSE 'unpublished' END AS status_label,
  COUNT(*) AS count
FROM node_field_data
WHERE default_langcode = 1
GROUP BY type, status
ORDER BY type, status DESC;
```

---

## Step 12: Output Formats

Generate the inventory in the format the user requests. Support all three.

### CSV

Standard RFC 4180 CSV. Use double quotes around fields containing commas, newlines, or double quotes. Escape double quotes by doubling them.

Header row:

```
nid,uuid,type,title,path,status,author,author_uid,created,changed,word_count,has_image,langcode,translation_languages,tags,moderation_state,is_stale,days_since_update,revision_count,empty_required_fields,broken_internal_links,missing_images
```

Write the primary inventory to `content-inventory.csv`. Write each summary section and orphan report to separate files:

- `content-inventory.csv` (primary inventory)
- `summary-by-type.csv`
- `summary-by-author.csv`
- `summary-by-month.csv`
- `summary-by-status.csv`
- `stale-content.csv`
- `quality-issues.csv`
- `orphaned-media.csv`
- `unused-taxonomy-terms.csv`
- `detached-paragraphs.csv`

### JSON

Single JSON file with top-level keys:

```json
{
  "generated": "2024-01-15T10:30:00Z",
  "site": "https://example.com",
  "drupal_version": "10.2.3",
  "inventory": [
    {
      "nid": 1,
      "uuid": "a1b2c3d4-...",
      "type": "article",
      "title": "Example Article",
      "path": "/blog/example-article",
      "status": 1,
      "author": "admin",
      "author_uid": 1,
      "created": "2023-06-15T08:30:00Z",
      "changed": "2024-01-10T14:22:00Z",
      "word_count": 847,
      "has_image": true,
      "langcode": "en",
      "translation_languages": ["fr", "de"],
      "tags": ["Migration", "Drupal"],
      "moderation_state": "published",
      "is_stale": false,
      "days_since_update": 5,
      "revision_count": 12,
      "empty_required_fields": [],
      "broken_internal_links": 0,
      "missing_images": 0
    }
  ],
  "summaries": {
    "by_type": [...],
    "by_author": [...],
    "by_month": [...],
    "by_status": [...]
  },
  "stale_content": [...],
  "quality_issues": {
    "empty_required_fields": [...],
    "broken_links": [...],
    "missing_images": [...]
  },
  "orphans": {
    "media": [...],
    "taxonomy_terms": [...],
    "paragraphs": [...]
  }
}
```

### Markdown

Generate a markdown document with tables. Primary inventory as a table (truncate to first 100 rows with a note about total count). Summaries as separate tables under H2 headings. Orphan reports as tables under an H2 "Orphans" section.

```markdown
# Content Inventory: example.com

Generated: 2024-01-15  
Drupal version: 10.2.3  
Total nodes: 4,523  

## Inventory (first 100 of 4,523)

| NID | Type | Title | Path | Status | Author | Created | Changed | Words | Image | Stale |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | article | Example Article | /blog/example | Published | admin | 2023-06-15 | 2024-01-10 | 847 | Yes | No |

## Summary by Content Type

| Type | Total | Published | Unpublished | Avg Words |
|---|---|---|---|---|

## Stale Content (not updated in >1 year)

| Type | Count | Oldest Update | Newest Update |
|---|---|---|---|

## Orphaned Media

| MID | Bundle | Name | Created | Changed |
|---|---|---|---|---|

## Unused Taxonomy Terms

| TID | Vocabulary | Name | Changed |
|---|---|---|---|

## Detached Paragraphs

| ID | Bundle | Language | Created |
|---|---|---|---|
```

For large sites, the markdown format is a summary view. CSV or JSON is the complete export.

---

## Drupal 7 Differences

D7 uses different tables and has no UUIDs, no media entities (unless Media module contrib is installed), and no content moderation.

| D8+ Table / Feature | D7 Equivalent |
|---|---|
| `node_field_data` | `node` (base table with `nid`, `type`, `title`, `status`, `uid`, `created`, `changed`, `language`) |
| `path_alias` | `url_alias` (columns: `source`, `alias`, `language`) |
| `media` / `media_field_data` | Not present unless `media` contrib is installed. Files attach directly to nodes through `file_managed`. |
| `content_moderation_state_field_data` | Not present. D7 uses `workbench_moderation_node_history` if Workbench Moderation contrib is installed. |
| `paragraphs_item` | `paragraphs_item` (if Paragraphs contrib is installed). Different schema: `item_id`, `revision_id`, `bundle`, `field_name`. |
| `node_field_data.uuid` | Not present. Use `nid` as the identifier. |
| `node_field_data.langcode` | `node.language` |
| `node_field_data.default_langcode` | No equivalent. D7 stores the source language in `node.language` and translations as separate nodes linked through `tnid` or `entity_translation` tables. |

Adjust queries accordingly. The agent should detect the Drupal version from Skill 01 output and select the correct query set.

---

## Execution Order

1. Load Skill 01 output (version, modules, access method)
2. Load Skill 02 output (content types, fields, required fields, entity reference targets)
3. Run the primary inventory query (Step 1)
4. Run translation query (Step 2), join to inventory
5. For each content type, calculate word counts (Step 3) across node text fields and paragraph text fields
6. Detect images (Step 4), join to inventory
7. Collect taxonomy terms (Step 5), join to inventory
8. Query moderation state if module is enabled (Step 6), join to inventory
9. Query revision counts (Step 7), join to inventory
10. Calculate staleness (Step 8) during output formatting
11. Run quality checks (Step 9): empty required fields, broken links, missing images
12. Run orphan detection (Step 10): media, taxonomy, paragraphs
13. Run summary aggregations (Step 11)
14. Write output in the requested format (Step 12)

Ask the user which output format they want. Default to CSV if they do not specify.

---

## Error Handling

- **Table does not exist**: Skip the feature. If `content_moderation_state_field_data` does not exist, leave the moderation column empty. If `paragraphs_item` does not exist, skip paragraph word counts and paragraph orphan detection.
- **Permission denied on a table**: Note the gap in the output. Mark affected columns as `access_denied`.
- **Large sites (>50,000 nodes)**: Use `LIMIT/OFFSET` pagination for all queries. Process in batches of 5,000 nodes. Write output incrementally to avoid memory issues.
- **MySQL `GROUP_CONCAT` truncation**: The default `group_concat_max_len` is 1024 bytes. Run `SET SESSION group_concat_max_len = 1000000;` before queries that use `GROUP_CONCAT`.
- **REGEXP_REPLACE unavailable**: MySQL < 8.0 does not support `REGEXP_REPLACE`. Fall back to the space-counting word count method and note that HTML tags inflate the count by roughly 10-15%.

---

## Validation

After generating the inventory, run these checks:

1. **Row count matches**: `SELECT COUNT(*) FROM node_field_data WHERE default_langcode = 1` should equal the number of rows in the inventory.
2. **No duplicate NIDs**: Each nid appears exactly once.
3. **All content types represented**: The set of distinct `type` values in the inventory matches `SELECT DISTINCT type FROM node_field_data`.
4. **Path alias coverage**: Count nodes with non-null aliases. Compare to `SELECT COUNT(*) FROM path_alias WHERE path LIKE '/node/%'`.
5. **Orphan counts plausible**: Orphaned media count should be less than total media count. If every media entity appears orphaned, the reference field query is missing tables.

Report validation results at the end of the output.
