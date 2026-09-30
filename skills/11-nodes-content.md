# Skill 11: Node Content Export

Export every node with every field value resolved. This is the largest export in any Drupal migration. Nodes reference taxonomy terms, media entities, paragraphs, users, files, and other nodes. This skill resolves all of them to human-readable, portable JSON.

Run Skills 1 (site audit) and 2 (content model map) first. You need the content type list, field definitions, and entity reference graph before you start pulling content.

---

## Prerequisites

Confirm these before running:

1. **Content type list** from Skill 2 output. You need every bundle machine name and its fields.
2. **Field type map** from Skill 2. Each field's storage type determines how to extract and resolve its value.
3. **Access method** from Skill 0. This skill supports all six methods. Use the best one available.
4. **Dependent entity exports**. Run taxonomy (Skill 13), media (Skill 14), and user (Skill 17) exports first if possible. Node export resolves references to those entities. Having them exported already means you can cross-reference UUIDs.

---

## Access Methods

Use the highest available method. Fall back as needed.

| Priority | Method | Drupal Version | Resolves References | Handles Pagination |
|---|---|---|---|---|
| 1 | JSON:API | D9+ (core in 8.7+) | Yes, via `include` | Yes, `page[offset]` + `page[limit]` |
| 2 | Core content:export | D11.3+ | Yes, with `--with-dependencies` | Exports all at once |
| 3 | Default Content (contrib) | D8+ | Yes, recursive | Per-entity via `drush dcer` |
| 4 | Entity I/O (contrib) | D9+ | Configurable | Bulk via Drush |
| 5 | Content Sync (contrib) | D9+ | Yes, with `--include-dependencies` | Per-bundle |
| 6 | Direct database | D7+ | Manual JOINs required | Manual LIMIT/OFFSET |

---

## Method 1: JSON:API (D9+)

JSON:API is in core since Drupal 8.7. No contrib modules needed. It returns structured JSON with relationship resolution through `include` parameters.

### 1a. Discover Available Node Bundles

```
GET /jsonapi
```

Parse the response `links` object. Every key matching `node--{bundle}` is an exportable content type. Example keys: `node--article`, `node--page`, `node--event`.

### 1b. Fetch Nodes with Includes

For each bundle, build a request that includes all referenced entities:

```
GET /jsonapi/node/{bundle}?include={include_list}&page[limit]=50&page[offset]=0
```

Build `{include_list}` from the field map. For an article with an image field, a paragraph field, a taxonomy field, and an author:

```
GET /jsonapi/node/article?include=field_image,field_image.field_media_image,field_tags,uid,field_paragraphs&page[limit]=50&page[offset]=0
```

Each `include` path resolves one level of reference. Chain them with dots for deeper resolution:
- `field_image` resolves the media entity
- `field_image.field_media_image` resolves the file entity inside the media entity
- `field_tags` resolves taxonomy term entities
- `uid` resolves the author user entity
- `field_paragraphs` resolves first-level paragraph entities

Paragraph fields that contain nested paragraphs need deeper chains. Delegate deep paragraph resolution to Skill 12. For a two-level paragraph structure:

```
include=field_paragraphs,field_paragraphs.field_cards,field_paragraphs.field_cards.field_icon
```

### 1c. Sparse Fieldsets

Reduce payload size by requesting only the fields you need:

```
GET /jsonapi/node/article?fields[node--article]=title,body,field_image,field_tags,created,changed,status,path&fields[media--image]=name,field_media_image&fields[file--file]=uri,url
```

Each `fields[{type}--{bundle}]` parameter limits the response to listed fields for that resource type. Always include `title`, `created`, `changed`, `status`, and `path` as baseline fields.

### 1d. Filtering

Export published content only:

```
filter[status]=1
```

Export all content (published and unpublished). Requires an authenticated request with admin permissions:

```
# No status filter = all content
GET /jsonapi/node/article?page[limit]=50
```

Filter by date range:

```
filter[created][condition][path]=created
filter[created][condition][operator]=>
filter[created][condition][value]=2024-01-01T00:00:00Z
```

Filter by content type field value:

```
filter[field_category.id]=550e8400-e29b-41d4-a716-446655440000
```

### 1e. Pagination

JSON:API uses cursor-based pagination through `links.next`:

```json
{
  "links": {
    "self": "https://example.com/jsonapi/node/article?page[limit]=50&page[offset]=0",
    "next": "https://example.com/jsonapi/node/article?page[limit]=50&page[offset]=50"
  },
  "meta": {
    "count": 1523
  }
}
```

Follow `links.next` until it is absent. The `meta.count` field (when present) gives the total. Some Drupal configurations omit `meta.count`. In that case, paginate until `data` is an empty array.

Set `page[limit]` to 50. Drupal's JSON:API enforces a server-side maximum (default 50). Going higher returns an error or silently caps.

### 1f. Authentication

Anonymous requests only return published content and fields visible to anonymous users. For a complete export:

1. **Basic Auth**: Send `Authorization: Basic {base64(user:pass)}` header. Requires the `basic_auth` module (core).
2. **OAuth 2.0**: Use the `simple_oauth` contrib module. Obtain a token from `/oauth/token`, then send `Authorization: Bearer {token}`.
3. **Cookie Auth**: POST credentials to `/user/login?_format=json`, capture the session cookie, send it on subsequent requests.

Basic Auth is the simplest for migration scripts. Enable it:

```bash
drush pm:install basic_auth
```

### 1g. Response Structure

A JSON:API response contains two key sections:

```json
{
  "data": [
    {
      "type": "node--article",
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "attributes": {
        "title": "Example Article",
        "created": "2024-03-15T09:00:00+00:00",
        "changed": "2024-06-01T14:30:00+00:00",
        "status": true,
        "body": {
          "value": "<p>Rich text content</p>",
          "format": "full_html",
          "processed": "<p>Rich text content</p>",
          "summary": "Summary text"
        },
        "path": {
          "alias": "/blog/example-article",
          "pid": 1234,
          "langcode": "en"
        },
        "langcode": "en"
      },
      "relationships": {
        "field_image": {
          "data": {
            "type": "media--image",
            "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
          }
        },
        "field_tags": {
          "data": [
            {"type": "taxonomy_term--tags", "id": "..."},
            {"type": "taxonomy_term--tags", "id": "..."}
          ]
        },
        "uid": {
          "data": {"type": "user--user", "id": "..."}
        }
      }
    }
  ],
  "included": [
    {
      "type": "media--image",
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "attributes": {"name": "Hero Image"},
      "relationships": {
        "field_media_image": {
          "data": {"type": "file--file", "id": "..."}
        }
      }
    },
    {
      "type": "file--file",
      "id": "...",
      "attributes": {
        "uri": {"value": "public://2024-03/hero.jpg", "url": "/sites/default/files/2024-03/hero.jpg"},
        "filename": "hero.jpg",
        "filemime": "image/jpeg",
        "filesize": 245000
      }
    },
    {
      "type": "taxonomy_term--tags",
      "id": "...",
      "attributes": {"name": "Drupal", "langcode": "en"}
    },
    {
      "type": "user--user",
      "id": "...",
      "attributes": {"display_name": "admin"}
    }
  ]
}
```

`data` holds the node records. `included` holds all resolved referenced entities. Match them by `type` + `id`.

### 1h. Transform JSON:API Response to Export Format

For each node in `data`:

1. Copy `attributes` fields directly (title, body, status, created, changed, path, langcode).
2. For each `relationships` entry, find the matching entity in `included` by `type` + `id`.
3. Resolve file URLs: prepend the site base URL to the `uri.url` value from file entities.
4. Build the `_meta` block from the node's `type`, `id`, and `attributes`.

See the Output Format section below for the target schema.

---

## Method 2: Core content:export (D11.3+)

Drupal 11.3 added a core script for content export. It writes YAML files to a directory.

```bash
# Export all nodes of a bundle with referenced entities
php core/scripts/drupal content:export node --bundle=article --with-dependencies --dir=export/content

# Export all bundles
php core/scripts/drupal content:export node --with-dependencies --dir=export/content

# Export a single node by UUID
php core/scripts/drupal content:export node --uuid=550e8400-e29b-41d4-a716-446655440000 --dir=export/content
```

The `--with-dependencies` flag exports referenced entities (media, taxonomy terms, files, paragraphs) alongside the nodes. Output is one YAML file per entity, named by UUID.

Output structure:

```
export/content/
  node/
    article/
      550e8400-e29b-41d4-a716-446655440000.yml
      ...
  media/
    image/
      a1b2c3d4-e5f6-7890-abcd-ef1234567890.yml
  taxonomy_term/
    tags/
      ...
  file/
    ...
```

Each YAML file contains the entity's field values in Drupal's internal structure. Parse them into the export JSON format.

YAML node file structure:

```yaml
_meta:
  version: '1.0'
  entity_type: node
  uuid: 550e8400-e29b-41d4-a716-446655440000
  bundle: article
  default_langcode: en
default:
  title:
    - value: 'Example Article'
  status:
    - value: true
  created:
    - value: 1710493200
  changed:
    - value: 1717253400
  body:
    - value: '<p>Rich text content</p>'
      format: full_html
      summary: 'Summary text'
  field_image:
    - entity: a1b2c3d4-e5f6-7890-abcd-ef1234567890
  field_tags:
    - entity: term-uuid-1
    - entity: term-uuid-2
  uid:
    - entity: user-uuid
  path:
    - alias: /blog/example-article
      langcode: en
```

This method handles all entity reference resolution. It also exports translated content: each language variant appears under its langcode key.

Limitations:
- Only available in Drupal 11.3 and later.
- Requires shell access to the Drupal root.
- Large sites (50,000+ nodes) may hit memory limits. Batch by bundle.

---

## Method 3: Default Content (contrib)

The `default_content` module provides `drush dcer` (Default Content Export References).

```bash
# Install if not present
composer require drupal/default_content
drush pm:install default_content

# Export a single node with all referenced entities
drush dcer node 42 --folder=export/

# Export all nodes of a type (loop)
drush sql:query "SELECT nid FROM node_field_data WHERE type = 'article'" | while read nid; do
  drush dcer node "$nid" --folder=export/
done
```

Output structure mirrors core content:export. One YAML or JSON file per entity, named by UUID.

Limitations:
- Exports one entity at a time. Slow for large sites. Wrap in a batch script.
- Memory consumption grows with deeply nested paragraph trees.
- Some field types (Layout Builder, Geofield) may not serialize cleanly. Check output.

---

## Method 4: Entity I/O (contrib)

```bash
composer require drupal/entity_io
drush pm:install entity_io

# Export all nodes
drush entity-io:export --entity-type=node --all --format=json --dir=export/nodes

# Export by bundle
drush entity-io:export --entity-type=node --bundle=article --format=json --dir=export/nodes

# Include referenced entities
drush entity-io:export --entity-type=node --bundle=article --include-references --dir=export/nodes
```

Entity I/O writes one JSON file per entity. The `--include-references` flag follows entity reference fields and exports targets.

---

## Method 5: Content Sync (contrib)

```bash
composer require drupal/content_sync
drush pm:install content_sync

# Export nodes of a specific bundle with dependencies
drush content-sync:export --entity-types=node.article --include-dependencies --dir=export/content

# Export all node bundles
drush content-sync:export --entity-types=node --include-dependencies --dir=export/content
```

Content Sync writes YAML files in the same structure as Drupal's config sync directory. Cross-references use UUIDs.

---

## Method 6: Direct Database (D9/D10/D11)

When no API or Drush is available, query the database directly. This is the most complex method. Each field is stored in its own table.

### 6a. Base Node Data

```sql
SELECT
  n.nid,
  n.uuid,
  nfd.type AS bundle,
  nfd.title,
  nfd.langcode,
  nfd.status,
  nfd.created,
  nfd.changed,
  nfd.promote,
  nfd.sticky,
  nfd.default_langcode,
  u.name AS author_name,
  nfd.uid AS author_uid
FROM node n
JOIN node_field_data nfd ON n.nid = nfd.nid AND nfd.default_langcode = 1
LEFT JOIN users_field_data u ON nfd.uid = u.uid
WHERE nfd.type = 'article'
ORDER BY n.nid
LIMIT 50 OFFSET 0;
```

Remove the `WHERE nfd.type = 'article'` clause to export all bundles. Paginate with `LIMIT`/`OFFSET`.

### 6b. Path Aliases

```sql
SELECT pa.path, pa.alias, pa.langcode
FROM path_alias pa
WHERE pa.path = CONCAT('/node/', 42);
```

Or join path aliases in bulk:

```sql
SELECT
  nfd.nid,
  pa.alias
FROM node_field_data nfd
LEFT JOIN path_alias pa ON pa.path = CONCAT('/node/', nfd.nid) AND pa.langcode = nfd.langcode
WHERE nfd.type = 'article';
```

### 6c. Field Value Tables

Every configurable field on a node is stored in a table named `node__field_{field_name}`. The column names follow a pattern based on field type.

Query pattern:

```sql
SELECT entity_id, delta, field_{name}_value
FROM node__field_{name}
WHERE bundle = 'article'
AND entity_id = 42
ORDER BY delta;
```

The `delta` column indicates position for multi-value fields. Single-value fields have `delta = 0`.

### 6d. Field Type Column Patterns

Each field type stores data in columns with specific suffixes on the `node__field_{name}` table:

**Text (plain)**:
```sql
SELECT entity_id, delta, field_subtitle_value
FROM node__field_subtitle;
```

**Text (formatted / rich text / body)**:
```sql
SELECT entity_id, delta, body_value, body_format, body_summary
FROM node__body;
-- Or for custom formatted text fields:
SELECT entity_id, delta, field_description_value, field_description_format
FROM node__field_description;
```

**Integer**:
```sql
SELECT entity_id, delta, field_count_value
FROM node__field_count;
```

**Decimal / Float**:
```sql
SELECT entity_id, delta, field_price_value
FROM node__field_price;
```

**Boolean**:
```sql
SELECT entity_id, delta, field_featured_value
FROM node__field_featured;
-- Returns 0 or 1
```

**Email**:
```sql
SELECT entity_id, delta, field_email_value
FROM node__field_email;
```

**Telephone**:
```sql
SELECT entity_id, delta, field_phone_value
FROM node__field_phone;
```

**Link**:
```sql
SELECT entity_id, delta,
  field_link_uri,
  field_link_title,
  field_link_options  -- serialized PHP array
FROM node__field_link;
```

The `uri` column stores values like `internal:/node/42`, `entity:node/42`, or `https://example.com`. Resolve `internal:` and `entity:` prefixes to actual URLs or target entity UUIDs.

**List (text / integer / float)**:
```sql
SELECT entity_id, delta, field_status_value
FROM node__field_status;
-- Returns the stored key. Map to allowed_values from field storage config.
```

**Date (date-only)**:
```sql
SELECT entity_id, delta, field_event_date_value
FROM node__field_event_date;
-- Stored as 'YYYY-MM-DD' string
```

**Datetime**:
```sql
SELECT entity_id, delta, field_published_at_value
FROM node__field_published_at;
-- Stored as 'YYYY-MM-DDTHH:MM:SS' UTC string
```

**Date range**:
```sql
SELECT entity_id, delta,
  field_event_dates_value AS start_date,
  field_event_dates_end_value AS end_date
FROM node__field_event_dates;
```

**Entity reference (taxonomy, node, user, media)**:
```sql
SELECT entity_id, delta, field_tags_target_id
FROM node__field_tags;
-- target_id is the referenced entity's ID (tid, nid, uid, mid)
```

Resolve the target ID to a label and UUID:

```sql
-- Taxonomy term reference
SELECT t.tid, t.uuid, tfd.name, tfd.vid AS vocabulary
FROM node__field_tags nft
JOIN taxonomy_term_field_data tfd ON nft.field_tags_target_id = tfd.tid
JOIN taxonomy_term t ON t.tid = tfd.tid
WHERE nft.entity_id = 42;

-- User reference
SELECT u.uid, u.uuid, ufd.name
FROM node__field_reviewer nfr
JOIN users_field_data ufd ON nfr.field_reviewer_target_id = ufd.uid
JOIN users u ON u.uid = ufd.uid
WHERE nfr.entity_id = 42;

-- Media reference
SELECT m.mid, m.uuid, mfd.name, mfd.bundle AS media_type
FROM node__field_image nfi
JOIN media_field_data mfd ON nfi.field_image_target_id = mfd.mid
JOIN media m ON m.mid = mfd.mid
WHERE nfi.entity_id = 42;

-- Then resolve media to file URL:
SELECT fm.fid, fm.uuid, fm.uri, fm.filename, fm.filemime, fm.filesize
FROM media__field_media_image mfmi
JOIN file_managed fm ON mfmi.field_media_image_target_id = fm.fid
WHERE mfmi.entity_id = {mid};
-- For image fields, also get alt/title:
SELECT field_media_image_alt, field_media_image_title, field_media_image_width, field_media_image_height
FROM media__field_media_image
WHERE entity_id = {mid};

-- Node reference (entity reference to another node)
SELECT n.nid, n.uuid, nfd.title, nfd.type AS bundle
FROM node__field_related nfr
JOIN node_field_data nfd ON nfr.field_related_target_id = nfd.nid
JOIN node n ON n.nid = nfd.nid
WHERE nfr.entity_id = 42;
```

**Entity reference revisions (paragraphs)**:
```sql
SELECT entity_id, delta,
  field_content_target_id,
  field_content_target_revision_id
FROM node__field_content
WHERE entity_id = 42
ORDER BY delta;
-- target_id is the paragraph entity ID
-- target_revision_id is the specific revision
```

Delegate paragraph resolution to Skill 12. Pass the `target_id` and `target_revision_id` values.

**File field (direct, not via media)**:
```sql
SELECT entity_id, delta,
  field_attachment_target_id,
  field_attachment_display,
  field_attachment_description
FROM node__field_attachment
WHERE entity_id = 42;

-- Resolve to file:
SELECT fm.fid, fm.uuid, fm.uri, fm.filename, fm.filemime, fm.filesize
FROM file_managed fm
WHERE fm.fid = {target_id};
```

Convert `public://path/to/file.pdf` to a download URL: replace `public://` with `{site_base_url}/sites/default/files/`.

**Image field (direct, not via media)**:
```sql
SELECT entity_id, delta,
  field_photo_target_id,
  field_photo_alt,
  field_photo_title,
  field_photo_width,
  field_photo_height
FROM node__field_photo
WHERE entity_id = 42;

-- Resolve to file:
SELECT fm.fid, fm.uuid, fm.uri, fm.filename, fm.filemime, fm.filesize
FROM file_managed fm
WHERE fm.fid = {target_id};
```

**Address (address module)**:
```sql
SELECT entity_id, delta,
  field_address_langcode,
  field_address_country_code,
  field_address_administrative_area,
  field_address_locality,
  field_address_dependent_locality,
  field_address_postal_code,
  field_address_sorting_code,
  field_address_address_line1,
  field_address_address_line2,
  field_address_organization,
  field_address_given_name,
  field_address_additional_name,
  field_address_family_name
FROM node__field_address
WHERE entity_id = 42;
```

**Geofield / Geolocation**:
```sql
-- Geofield module
SELECT entity_id, delta,
  field_location_value,        -- WKT string: 'POINT(-73.935242 40.730610)'
  field_location_geo_type,
  field_location_lat,
  field_location_lon,
  field_location_left,
  field_location_top,
  field_location_right,
  field_location_bottom,
  field_location_geohash
FROM node__field_location
WHERE entity_id = 42;

-- Geolocation module
SELECT entity_id, delta,
  field_geolocation_lat,
  field_geolocation_lng
FROM node__field_geolocation
WHERE entity_id = 42;
```

### 6e. Metatag Values

If the `metatag` module is installed, metatag data is stored as a serialized field:

```sql
SELECT entity_id, delta, field_metatag_value
FROM node__field_metatag
WHERE entity_id = 42;
-- field_metatag_value is a serialized PHP array (D8/D9) or JSON (D10+)
```

The serialized value contains keys like `title`, `description`, `og_title`, `og_description`, `og_image`, `twitter_cards_type`. Unserialize with PHP or a PHP-compatible deserializer.

If metatag stores data in JSON format (D10.1+):

```sql
SELECT entity_id, field_metatag_value
FROM node__field_metatag
WHERE entity_id = 42;
-- Parse as JSON directly
```

### 6f. Content Moderation State

```sql
SELECT
  cms.content_entity_id AS nid,
  cms.moderation_state,
  cms.langcode
FROM content_moderation_state_field_data cms
WHERE cms.content_entity_type_id = 'node'
AND cms.content_entity_id = 42;
```

### 6g. Scheduler Dates

If the `scheduler` module is installed:

```sql
-- Scheduler stores dates as node base fields (D9+ scheduler)
SELECT entity_id,
  field_scheduler_publish_on_value AS publish_on,
  field_scheduler_unpublish_on_value AS unpublish_on
FROM node__field_scheduler_publish_on sp
LEFT JOIN node__field_scheduler_unpublish_on su ON sp.entity_id = su.entity_id
WHERE sp.entity_id = 42;
```

Older versions of scheduler store dates in a dedicated `scheduler` table:

```sql
SELECT nid, publish_on, unpublish_on
FROM scheduler
WHERE nid = 42;
```

### 6h. Translation Data

Translated nodes share the same `nid` but have different `langcode` values in `node_field_data`:

```sql
SELECT nfd.nid, nfd.langcode, nfd.title, nfd.status, nfd.default_langcode
FROM node_field_data nfd
WHERE nfd.nid = 42
ORDER BY nfd.default_langcode DESC;
-- Row with default_langcode=1 is the original
-- Other rows are translations
```

Field values for translations are in the same `node__field_*` tables with a `langcode` column:

```sql
SELECT entity_id, langcode, delta, body_value, body_format
FROM node__body
WHERE entity_id = 42
ORDER BY langcode, delta;
```

### 6i. Bulk Export Query (All Fields for One Bundle)

Building a single query that joins all field tables for a bundle is possible but unwieldy. A better approach: query base node data first, then loop through each node and query each field table separately. Group field table queries by type to reduce round trips.

Batch pattern:

```sql
-- Step 1: Get all node IDs for the bundle
SELECT nid FROM node_field_data WHERE type = 'article' ORDER BY nid;

-- Step 2: For each field table, query all nodes at once
SELECT entity_id, delta, body_value, body_format, body_summary
FROM node__body
WHERE bundle = 'article'
ORDER BY entity_id, delta;

SELECT entity_id, delta, field_tags_target_id
FROM node__field_tags
WHERE bundle = 'article'
ORDER BY entity_id, delta;

-- Repeat for every field on the bundle
```

Assemble per-node JSON objects in application code by matching `entity_id` across result sets.

---

## Method 6 (D7): Direct Database

D7 uses a different schema. Field tables are named `field_data_field_{name}` instead of `node__field_{name}`. Revision tables are `field_revision_field_{name}`.

### D7 Base Node Data

```sql
SELECT
  n.nid,
  n.vid,
  n.type,
  n.language,
  n.title,
  n.uid,
  n.status,
  n.created,
  n.changed,
  n.promote,
  n.sticky,
  u.name AS author_name
FROM node n
LEFT JOIN users u ON n.uid = u.uid
WHERE n.type = 'article'
ORDER BY n.nid
LIMIT 50 OFFSET 0;
```

D7 nodes have no UUID column unless the `uuid` contrib module is installed. Check:

```sql
SHOW COLUMNS FROM node LIKE 'uuid';
```

If present:

```sql
SELECT nid, uuid FROM node WHERE type = 'article';
```

### D7 Path Aliases

```sql
SELECT source, alias, language
FROM url_alias
WHERE source = CONCAT('node/', 42);
```

### D7 Field Tables

```sql
-- Body field (exists on most content types)
SELECT entity_id, delta, body_value, body_format, body_summary
FROM field_data_body
WHERE entity_type = 'node' AND bundle = 'article' AND entity_id = 42;

-- Text field
SELECT entity_id, delta, field_subtitle_value
FROM field_data_field_subtitle
WHERE entity_type = 'node' AND entity_id = 42;

-- Entity reference (entityreference module)
SELECT entity_id, delta, field_category_target_id
FROM field_data_field_category
WHERE entity_type = 'node' AND entity_id = 42;

-- Taxonomy term reference (D7 native)
SELECT entity_id, delta, field_tags_tid
FROM field_data_field_tags
WHERE entity_type = 'node' AND entity_id = 42;

-- Resolve term:
SELECT td.tid, td.name, tv.name AS vocabulary_name
FROM taxonomy_term_data td
JOIN taxonomy_vocabulary tv ON td.vid = tv.vid
WHERE td.tid = {tid};

-- File / Image field
SELECT entity_id, delta,
  field_image_fid,
  field_image_alt,
  field_image_title,
  field_image_width,
  field_image_height
FROM field_data_field_image
WHERE entity_type = 'node' AND entity_id = 42;

-- Resolve file:
SELECT fid, uri, filename, filemime, filesize
FROM file_managed
WHERE fid = {fid};

-- Link field (link module)
SELECT entity_id, delta,
  field_link_url,
  field_link_title,
  field_link_attributes  -- serialized PHP
FROM field_data_field_link
WHERE entity_type = 'node' AND entity_id = 42;

-- Date field (date module)
SELECT entity_id, delta,
  field_event_date_value,
  field_event_date_value2  -- end date for date ranges
FROM field_data_field_event_date
WHERE entity_type = 'node' AND entity_id = 42;
-- Date format depends on field config: 'YYYY-MM-DD HH:MM:SS' or Unix timestamp

-- Address field (addressfield module)
SELECT entity_id, delta,
  field_address_country,
  field_address_administrative_area,
  field_address_sub_administrative_area,
  field_address_locality,
  field_address_dependent_locality,
  field_address_postal_code,
  field_address_thoroughfare,
  field_address_premise,
  field_address_sub_premise,
  field_address_organisation_name,
  field_address_name_line,
  field_address_first_name,
  field_address_last_name
FROM field_data_field_address
WHERE entity_type = 'node' AND entity_id = 42;
```

### D7 Field Collection (proto-paragraphs)

D7 sites that predate paragraphs often use `field_collection`:

```sql
-- Get field collection item IDs from the host node
SELECT entity_id, delta, field_content_items_value AS item_id
FROM field_data_field_content_items
WHERE entity_type = 'node' AND entity_id = 42;

-- Get field collection item data
SELECT item_id, field_name, archived
FROM field_collection_item
WHERE item_id IN ({item_ids});

-- Get fields on each item (same field_data_ pattern)
SELECT entity_id, delta, field_fc_title_value
FROM field_data_field_fc_title
WHERE entity_type = 'field_collection_item' AND entity_id = {item_id};
```

### D7 Paragraphs (contrib)

D7 paragraphs use the `paragraphs_item` table:

```sql
SELECT item_id, bundle, field_name, archived
FROM paragraphs_item
WHERE field_name = 'field_content'
AND item_id IN (
  SELECT field_content_value FROM field_data_field_content
  WHERE entity_type = 'node' AND entity_id = 42
);
```

Field values on D7 paragraphs follow the same `field_data_field_{name}` pattern with `entity_type = 'paragraphs_item'`.

### D7 Metatag

```sql
SELECT entity_id, data
FROM metatag
WHERE entity_type = 'node' AND entity_id = 42;
-- `data` is serialized PHP. Unserialize to get metatag key-value pairs.
```

### D7 Scheduler

```sql
SELECT nid, publish_on, unpublish_on
FROM scheduler
WHERE nid = 42;
-- Unix timestamps
```

### D7 Translations

D7 has two translation systems. Check which is active.

**Content translation (built-in, node-level)**:
```sql
-- Nodes in a translation set share a tnid
SELECT nid, tnid, language, title
FROM node
WHERE tnid = (SELECT tnid FROM node WHERE nid = 42 AND tnid != 0);
-- Each translation is a separate node with its own nid
```

**Entity Translation (contrib, field-level)**:
```sql
-- Same nid, different language in field tables
SELECT entity_id, language, delta, body_value
FROM field_data_body
WHERE entity_type = 'node' AND entity_id = 42;
-- One row per language per delta
```

Check which system is active:

```sql
SELECT name FROM system WHERE status = 1 AND name IN ('translation', 'entity_translation');
```

---

## Handling Every Field Type: Resolution Reference

Use this table to determine how to extract and resolve each field type.

| Field Type | Storage Columns | Resolution |
|---|---|---|
| `string` | `_value` | Direct value |
| `string_long` | `_value` | Direct value |
| `text` | `_value` | Direct value |
| `text_long` | `_value`, `_format` | Value + text format name |
| `text_with_summary` | `_value`, `_format`, `_summary` | Value + format + summary |
| `integer` | `_value` | Direct value |
| `decimal` | `_value` | Direct value |
| `float` | `_value` | Direct value |
| `boolean` | `_value` | 0 or 1 |
| `email` | `_value` | Direct value |
| `telephone` | `_value` | Direct value |
| `timestamp` | `_value` | Unix timestamp, convert to ISO 8601 |
| `created` | `_value` | Unix timestamp |
| `changed` | `_value` | Unix timestamp |
| `datetime` | `_value` | `YYYY-MM-DDTHH:MM:SS` string |
| `daterange` | `_value`, `_end_value` | Start + end datetime strings |
| `list_string` | `_value` | Key from allowed values list |
| `list_integer` | `_value` | Key from allowed values list |
| `list_float` | `_value` | Key from allowed values list |
| `link` | `_uri`, `_title`, `_options` | URI + title. Resolve `internal:` and `entity:` URIs. |
| `entity_reference` | `_target_id` | ID of referenced entity. Resolve to UUID + label. |
| `entity_reference_revisions` | `_target_id`, `_target_revision_id` | Paragraph reference. Delegate to Skill 12. |
| `file` | `_target_id`, `_display`, `_description` | File entity ID. Resolve to file URL via `file_managed`. |
| `image` | `_target_id`, `_alt`, `_title`, `_width`, `_height` | File entity ID + image metadata. Resolve to file URL. |
| `address` | `_country_code`, `_administrative_area`, `_locality`, `_dependent_locality`, `_postal_code`, `_sorting_code`, `_address_line1`, `_address_line2`, `_organization`, `_given_name`, `_additional_name`, `_family_name` | All address components. |
| `geofield` | `_value` (WKT), `_geo_type`, `_lat`, `_lon`, `_left`, `_top`, `_right`, `_bottom`, `_geohash` | Use `_lat` and `_lon` for point data. |
| `geolocation` | `_lat`, `_lng` | Latitude and longitude. |
| `color_field` | `_color`, `_opacity` | Hex color + opacity. |
| `metatag` | `_value` | Serialized PHP or JSON. Unserialize. |

---

## Output Format

Produce one JSON file per content type. Name each file `nodes-{bundle}.json`. Each file contains an array of node objects.

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["_meta", "title", "status"],
    "properties": {
      "_meta": {
        "type": "object",
        "required": ["entity_type", "bundle", "nid", "uuid", "langcode", "source_url", "exported_at", "drupal_version"],
        "properties": {
          "entity_type": {"type": "string", "const": "node"},
          "bundle": {"type": "string"},
          "nid": {"type": "integer"},
          "uuid": {"type": "string", "format": "uuid"},
          "langcode": {"type": "string"},
          "source_url": {"type": "string", "format": "uri"},
          "exported_at": {"type": "string", "format": "date-time"},
          "drupal_version": {"type": "string"},
          "access_method": {"type": "string", "enum": ["jsonapi", "content_export", "default_content", "entity_io", "content_sync", "database"]},
          "translations_available": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Language codes of available translations"
          }
        }
      },
      "title": {"type": "string"},
      "status": {"type": "boolean", "description": "true = published, false = unpublished"},
      "created": {"type": "string", "format": "date-time"},
      "changed": {"type": "string", "format": "date-time"},
      "author": {
        "type": "object",
        "properties": {
          "uid": {"type": "integer"},
          "uuid": {"type": "string"},
          "name": {"type": "string"}
        }
      },
      "path_alias": {"type": ["string", "null"]},
      "promote": {"type": "boolean"},
      "sticky": {"type": "boolean"},
      "moderation_state": {"type": ["string", "null"]},
      "metatags": {
        "type": ["object", "null"],
        "properties": {
          "title": {"type": "string"},
          "description": {"type": "string"},
          "og_title": {"type": "string"},
          "og_description": {"type": "string"},
          "og_image": {"type": "string"},
          "twitter_cards_type": {"type": "string"}
        },
        "additionalProperties": {"type": "string"}
      },
      "scheduler": {
        "type": ["object", "null"],
        "properties": {
          "publish_on": {"type": ["string", "null"], "format": "date-time"},
          "unpublish_on": {"type": ["string", "null"], "format": "date-time"}
        }
      }
    },
    "additionalProperties": {
      "description": "All other fields use their field_name as key. Values depend on field type.",
      "oneOf": [
        {"type": "string"},
        {"type": "number"},
        {"type": "boolean"},
        {"type": "null"},
        {"type": "object"},
        {"type": "array"}
      ]
    }
  }
}
```

### Field Value Shapes in Output

Each field type resolves to a specific JSON shape:

**Simple scalar fields** (text, integer, decimal, float, boolean, email, telephone):
```json
"field_subtitle": "The subtitle text"
"field_count": 42
"field_price": 19.99
"field_featured": true
"field_email": "user@example.com"
"field_phone": "+1-555-0123"
```

Multi-value scalar fields become arrays:
```json
"field_tags_list": ["tag1", "tag2", "tag3"]
```

**Formatted text** (body, text_long, text_with_summary):
```json
"body": {
  "value": "<p>The HTML content</p>",
  "format": "full_html",
  "summary": "Optional summary text"
}
```

**Date / Datetime**:
```json
"field_event_date": "2024-06-15"
"field_published_at": "2024-06-15T09:00:00Z"
```

**Date range**:
```json
"field_event_dates": {
  "start": "2024-06-15T09:00:00Z",
  "end": "2024-06-17T17:00:00Z"
}
```

**Link**:
```json
"field_link": {
  "uri": "https://example.com",
  "title": "Example Site"
}
```

For internal links, resolve the URI:
```json
"field_link": {
  "uri": "entity:node/42",
  "resolved_url": "/blog/example-article",
  "resolved_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Related Article"
}
```

**List / Select**:
```json
"field_status": {
  "key": "in_progress",
  "label": "In Progress"
}
```

Include the label when the allowed values list is available from field storage config. If not, output the key alone.

**Entity reference (taxonomy)**:
```json
"field_tags": [
  {"tid": 5, "uuid": "...", "name": "Drupal", "vocabulary": "tags"},
  {"tid": 12, "uuid": "...", "name": "Migration", "vocabulary": "tags"}
]
```

**Entity reference (node)**:
```json
"field_related": [
  {"nid": 99, "uuid": "...", "title": "Related Post", "bundle": "article"}
]
```

**Entity reference (user)**:
```json
"field_reviewer": {
  "uid": 5, "uuid": "...", "name": "editor_jane"
}
```

**Media reference (image)**:
```json
"field_image": {
  "mid": 10,
  "uuid": "...",
  "name": "Hero Image",
  "media_type": "image",
  "file": {
    "fid": 234,
    "uuid": "...",
    "url": "https://example.com/sites/default/files/2024-03/hero.jpg",
    "filename": "hero.jpg",
    "filemime": "image/jpeg",
    "filesize": 245000
  },
  "alt": "Hero image alt text",
  "title": "",
  "width": 1200,
  "height": 630
}
```

**Media reference (document)**:
```json
"field_document": {
  "mid": 15,
  "uuid": "...",
  "name": "Annual Report",
  "media_type": "document",
  "file": {
    "fid": 300,
    "uuid": "...",
    "url": "https://example.com/sites/default/files/docs/report.pdf",
    "filename": "report.pdf",
    "filemime": "application/pdf",
    "filesize": 1048576
  }
}
```

**Media reference (remote video)**:
```json
"field_video": {
  "mid": 20,
  "uuid": "...",
  "name": "Product Demo",
  "media_type": "remote_video",
  "oembed_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
}
```

**File field (direct, not media entity)**:
```json
"field_attachment": {
  "fid": 400,
  "uuid": "...",
  "url": "https://example.com/sites/default/files/attachments/spec.pdf",
  "filename": "spec.pdf",
  "filemime": "application/pdf",
  "filesize": 524288,
  "description": "Technical specification"
}
```

**Image field (direct, not media entity)**:
```json
"field_photo": {
  "fid": 500,
  "uuid": "...",
  "url": "https://example.com/sites/default/files/photos/team.jpg",
  "filename": "team.jpg",
  "filemime": "image/jpeg",
  "filesize": 320000,
  "alt": "Team photo",
  "title": "",
  "width": 800,
  "height": 600
}
```

**Address**:
```json
"field_address": {
  "country_code": "US",
  "administrative_area": "CA",
  "locality": "San Francisco",
  "postal_code": "94102",
  "address_line1": "123 Main St",
  "address_line2": "Suite 400",
  "organization": "Acme Corp",
  "given_name": "Jane",
  "family_name": "Doe"
}
```

**Geofield / Geolocation**:
```json
"field_location": {
  "lat": 40.730610,
  "lng": -73.935242
}
```

**Paragraph reference** (resolved by Skill 12):
```json
"field_content": [
  {
    "_type": "hero_banner",
    "_paragraph_id": 100,
    "_paragraph_uuid": "...",
    "field_title": "Welcome",
    "field_subtitle": "To our site",
    "field_background": {
      "mid": 10,
      "uuid": "...",
      "name": "Hero BG",
      "media_type": "image",
      "file": {"url": "...", "filename": "hero-bg.jpg"}
    }
  },
  {
    "_type": "text_block",
    "_paragraph_id": 101,
    "_paragraph_uuid": "...",
    "field_body": {
      "value": "<p>Content text</p>",
      "format": "full_html"
    }
  },
  {
    "_type": "card_group",
    "_paragraph_id": 102,
    "_paragraph_uuid": "...",
    "field_cards": [
      {
        "_type": "card",
        "_paragraph_id": 200,
        "_paragraph_uuid": "...",
        "field_title": "Card 1",
        "field_link": {"uri": "https://example.com", "title": "Learn more"}
      }
    ]
  }
]
```

### Complete Node Example

```json
{
  "_meta": {
    "entity_type": "node",
    "bundle": "article",
    "nid": 42,
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "langcode": "en",
    "source_url": "https://example.com/node/42",
    "exported_at": "2025-01-15T10:30:00Z",
    "drupal_version": "10.3.1",
    "access_method": "jsonapi",
    "translations_available": ["en", "es"]
  },
  "title": "Example Article",
  "status": true,
  "created": "2024-03-15T09:00:00Z",
  "changed": "2024-06-01T14:30:00Z",
  "author": {"uid": 1, "uuid": "user-uuid-here", "name": "admin"},
  "path_alias": "/blog/example-article",
  "promote": true,
  "sticky": false,
  "moderation_state": "published",
  "metatags": {
    "title": "Custom Page Title | Site Name",
    "description": "Custom meta description for this article.",
    "og_title": "Custom Page Title",
    "og_image": "https://example.com/sites/default/files/og/article-42.jpg"
  },
  "scheduler": {
    "publish_on": null,
    "unpublish_on": "2025-12-31T23:59:59Z"
  },
  "body": {
    "value": "<p>This is the article body with <a data-entity-type=\"node\" data-entity-uuid=\"other-uuid\">a Drupal link</a>.</p>",
    "format": "full_html",
    "summary": "Article summary text"
  },
  "field_subtitle": "A deeper look at content export",
  "field_featured": true,
  "field_tags": [
    {"tid": 5, "uuid": "term-uuid-1", "name": "Drupal", "vocabulary": "tags"},
    {"tid": 12, "uuid": "term-uuid-2", "name": "Migration", "vocabulary": "tags"}
  ],
  "field_category": {
    "tid": 3, "uuid": "term-uuid-3", "name": "Technology", "vocabulary": "categories"
  },
  "field_image": {
    "mid": 10,
    "uuid": "media-uuid-here",
    "name": "Hero Image",
    "media_type": "image",
    "file": {
      "fid": 234,
      "uuid": "file-uuid-here",
      "url": "https://example.com/sites/default/files/2024-03/hero.jpg",
      "filename": "hero.jpg",
      "filemime": "image/jpeg",
      "filesize": 245000
    },
    "alt": "Hero image showing the product",
    "title": "",
    "width": 1200,
    "height": 630
  },
  "field_content": [
    {
      "_type": "hero_banner",
      "_paragraph_id": 100,
      "_paragraph_uuid": "para-uuid-1",
      "field_heading": "Welcome",
      "field_background": {
        "mid": 11,
        "uuid": "media-uuid-bg",
        "name": "Banner BG",
        "media_type": "image",
        "file": {"url": "https://example.com/sites/default/files/banners/bg.jpg"}
      }
    },
    {
      "_type": "text_block",
      "_paragraph_id": 101,
      "_paragraph_uuid": "para-uuid-2",
      "field_body": {
        "value": "<p>Intro paragraph</p>",
        "format": "full_html"
      }
    }
  ],
  "field_related": [
    {"nid": 99, "uuid": "related-uuid", "title": "Related Post", "bundle": "article"}
  ],
  "field_link": {
    "uri": "https://docs.example.com",
    "title": "Documentation"
  }
}
```

---

## Execution Procedure

Follow this sequence for each content type.

### Step 1: Build the Field Map

From Skill 2 output, list every field on the bundle. For each field, note:
- Machine name
- Field type (from the resolution reference table above)
- Cardinality (1 = single value, -1 = unlimited, N = fixed limit)
- Whether it references another entity and what type

### Step 2: Choose the Access Method

Pick the highest-priority method available. If JSON:API is available, use it. Build the `include` parameter from the field map: add every entity reference field, and chain includes for media-to-file resolution.

### Step 3: Export Base Node Data

Run the query or API call. Paginate through all nodes of the bundle.

For JSON:API: follow `links.next` until exhausted.
For database: use `LIMIT 1000 OFFSET {n}` and increment until zero rows return.
For Drush-based tools: follow tool-specific batch patterns.

### Step 4: Resolve Entity References

For JSON:API: references arrive in the `included` array. Match by `type` + `id`.

For database: run resolution queries for each reference field. Batch by collecting all `target_id` values first, then resolve them in one query per reference type:

```sql
-- Batch resolve all taxonomy references for the bundle
SELECT DISTINCT nft.field_tags_target_id AS tid, t.uuid, tfd.name, tfd.vid
FROM node__field_tags nft
JOIN taxonomy_term t ON nft.field_tags_target_id = t.tid
JOIN taxonomy_term_field_data tfd ON t.tid = tfd.tid AND tfd.default_langcode = 1
WHERE nft.bundle = 'article';
```

### Step 5: Resolve Paragraphs

Collect all paragraph `target_id` values from `entity_reference_revisions` fields. Pass them to Skill 12 for recursive resolution. Skill 12 returns the resolved paragraph tree. Insert it into the node JSON.

### Step 6: Resolve Media and Files

For each media reference, resolve the chain: media entity -> source field -> file entity -> file URL.

Batch the resolution:

```sql
-- All media IDs referenced by this bundle's image field
SELECT DISTINCT nfi.field_image_target_id AS mid
FROM node__field_image nfi
WHERE nfi.bundle = 'article';

-- Resolve all at once
SELECT m.mid, m.uuid, mfd.name, mfd.bundle,
  fm.fid, fm.uuid AS file_uuid, fm.uri, fm.filename, fm.filemime, fm.filesize,
  mfmi.field_media_image_alt AS alt,
  mfmi.field_media_image_title AS image_title,
  mfmi.field_media_image_width AS width,
  mfmi.field_media_image_height AS height
FROM media m
JOIN media_field_data mfd ON m.mid = mfd.mid
JOIN media__field_media_image mfmi ON m.mid = mfmi.entity_id
JOIN file_managed fm ON mfmi.field_media_image_target_id = fm.fid
WHERE m.mid IN ({mid_list});
```

### Step 7: Attach Metadata

For each node:
1. Query the path alias (Section 6b).
2. Query metatag values if the metatag module is installed (Section 6e).
3. Query moderation state if content_moderation is active (Section 6f).
4. Query scheduler dates if the scheduler module is present (Section 6g).

### Step 8: Handle Translations

If the site is multilingual (detected in Skill 1):

For JSON:API, request each translation:
```
GET /jsonapi/node/article/{uuid}?resourceVersion=rel:latest-version
```

Add the `Accept-Language` header or use the `filter[langcode]` parameter:
```
GET /jsonapi/node/article?filter[langcode]=es&page[limit]=50
```

For database: query `node_field_data` and each `node__field_*` table grouped by `langcode`. Produce one export object per translation, or nest translations under the default language node.

Recommended output structure for translated content:

```json
{
  "_meta": {
    "langcode": "en",
    "translations_available": ["en", "es", "fr"]
  },
  "title": "English Title",
  "_translations": {
    "es": {
      "title": "Titulo en Espanol",
      "body": {"value": "<p>Contenido en espanol</p>", "format": "full_html"}
    },
    "fr": {
      "title": "Titre en Francais",
      "body": {"value": "<p>Contenu en francais</p>", "format": "full_html"}
    }
  }
}
```

### Step 9: Assemble and Write

Build the final JSON array for each bundle. Write to `nodes-{bundle}.json`.

Run a count check:

```sql
-- Compare source count to export count
SELECT type, COUNT(*) FROM node_field_data GROUP BY type;
```

Or via JSON:API:
```
GET /jsonapi/node/{bundle}?page[limit]=1
-- Check meta.count
```

If the exported node count does not match the source count, log the discrepancy. Common causes:
- Access control filtered nodes from JSON:API responses (anonymous cannot see unpublished content)
- Pagination gap from concurrent content changes during export
- Language filter excluded non-default translations

### Step 10: Validate

Spot-check 5 nodes per bundle:
1. Compare `title` and `body` against the source site.
2. Confirm entity references resolve to correct labels.
3. Confirm file URLs are accessible (HTTP HEAD request).
4. Confirm paragraph trees have the expected depth and types.
5. Confirm timestamps are in ISO 8601 format.

---

## Edge Cases

### Unpublished Content
JSON:API requires authentication to see unpublished nodes. Database queries return everything regardless. If using JSON:API, authenticate or note the gap.

### Revisions
This skill exports the current (default) revision only. For revision history, use Skill 27. The `changed` timestamp reflects the latest revision.

### Large Sites (50,000+ Nodes)
- JSON:API: paginate in batches of 50. Expect thousands of requests per bundle. Rate-limit to avoid overloading the server. A 1-second delay between requests is a safe default.
- Database: use `LIMIT 1000 OFFSET {n}`. Process and write each batch before loading the next to control memory.
- Core content:export: may run out of memory. Split by bundle. If a single bundle is too large, export in ID ranges: filter nodes by `nid > X AND nid <= Y`.

### File URI Resolution
Convert Drupal file URIs to download URLs:
- `public://2024-01/photo.jpg` becomes `{base_url}/sites/default/files/2024-01/photo.jpg`
- `private://docs/secret.pdf` requires authenticated access. Note these files in the export but flag that download requires auth.
- `s3://bucket/path/file.pdf` requires S3 access. Export the URI and document the bucket/key.

The public files path may not be `sites/default/files/`. Check `settings.php` or `drush status` for the actual file public path:
```bash
drush status --field=files
```

### Serialized PHP Data
Metatag values, link `options` columns, and some contrib field data contain serialized PHP arrays. Use PHP's `unserialize()` or a compatible library. If no PHP runtime is available, use a regex-based parser for simple cases or flag the field as needing manual conversion.

### Empty Fields
Omit fields with no value from the JSON output. Do not output `null` for every possible field on a bundle. The schema uses `additionalProperties` to accommodate variable fields per node.

### Computed Fields
Some fields are computed at display time and not stored in the database. Examples: `changed` (stored), `path` (stored in path_alias), search index fields (not stored on the entity). Computed fields without persistent storage cannot be exported via database. JSON:API returns computed field values that the entity exposes.

### Layout Builder Content
If a content type uses Layout Builder, layout data is stored in the `layout_builder__layout` field. This field contains serialized PHP objects (section layouts, block configurations, inline block content). Export the raw serialized data and flag it for manual conversion. Skill 16 covers Layout Builder in detail.
