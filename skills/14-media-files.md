# Skill 14: Media Entities and File Export

Export every media entity, its source file metadata, and the physical files themselves. Build a download manifest that maps Drupal file URIs to retrievable URLs with deduplication hashes. Map which content references which media.

D7 sites have no media entities. Files attach to nodes through file and image fields on `file_managed`. D8+ introduced the Media module (experimental in 8.4, stable in 8.6). Both paths are covered.

---

## What Gets Exported

### Per Media Entity (D8+)

| Property | Source |
|---|---|
| `mid` | Media entity ID |
| `uuid` | UUID |
| `name` | Admin label (often the filename, sometimes edited by authors) |
| `bundle` | Media type machine name: `image`, `document`, `audio`, `video`, `remote_video`, or custom |
| `status` | Published (1) or unpublished (0) |
| `uid` | Author user ID |
| `created` | UNIX timestamp |
| `changed` | UNIX timestamp |
| `langcode` | Language code |
| `default_langcode` | Boolean, 1 = this is the default translation |

### Per Source File

The source field differs by media type. Each media type config declares a `source_configuration.source_field` that points to the field holding the actual file reference or URL.

| Media Type | Source Field (default) | Resolves To |
|---|---|---|
| `image` | `field_media_image` | `file_managed` row. Includes `fid`, `uri`, `filename`, `filemime`, `filesize`. Field columns: `alt`, `title`, `width`, `height`. |
| `document` | `field_media_document` | `file_managed` row. `fid`, `uri`, `filename`, `filemime`, `filesize`. |
| `audio` | `field_media_audio_file` | `file_managed` row. Same columns as document. |
| `video` | `field_media_video_file` | `file_managed` row. Same columns as document. |
| `remote_video` | `field_media_oembed_video` | Plain string column. Stores the YouTube/Vimeo URL. No file on disk. |
| Custom types | Varies | Check `media.type.{bundle}.yml` for `source_configuration.source_field`. |

### File Download Manifest Fields

| Field | Purpose |
|---|---|
| `fid` | Drupal file ID |
| `uri` | Internal URI (`public://2024-01/photo.jpg`) |
| `download_url` | Full HTTP URL or filesystem path |
| `filename` | Original filename |
| `filemime` | MIME type |
| `filesize` | Bytes |
| `sha256` | Hash for deduplication |
| `usage_count` | How many entities reference this file |
| `scheme` | `public`, `private`, `s3`, `temporary` |

### Media Usage Map

Which nodes, paragraphs, or other entities reference which media entities. Output as a table: `entity_type`, `entity_id`, `bundle`, `field_name`, `media_id`, `media_bundle`.

---

## File URI Schemes

Drupal stores file paths as URIs with a scheme prefix. Each scheme maps to a different physical location.

| Scheme | Resolves To | Export Approach |
|---|---|---|
| `public://` | `sites/default/files/` (web-accessible) | Direct HTTP download or filesystem copy |
| `private://` | Outside webroot (not web-accessible) | Drush file copy, database dump, or authenticated download via `system/files/` route |
| `temporary://` | System temp directory | Skip. These are transient uploads. |
| `s3://` | Amazon S3 bucket (requires `s3fs` module) | `aws s3 sync` or S3 API |

Check which schemes exist on the site:

```sql
-- D8+
SELECT DISTINCT SUBSTRING_INDEX(uri, '://', 1) AS scheme, COUNT(*) AS file_count
FROM file_managed
GROUP BY scheme
ORDER BY file_count DESC;

-- D7: same query, same table
```

If `s3://` appears, the `s3fs` module is in play. Its config holds the bucket name and prefix:

```bash
drush config:get s3fs.settings bucket --format=json
drush config:get s3fs.settings root_folder --format=json
drush config:get s3fs.settings public_folder --format=json
```

---

## Step 1: Discover Media Types and Source Fields

Before exporting entities, discover what media types exist and which field holds the source for each.

### Method A: Config YAML

```bash
find config/sync -name "media.type.*.yml" | sort
```

Each file contains:

```yaml
id: image
label: Image
source: 'image'
source_configuration:
  source_field: field_media_image
queue_thumbnail_downloads: false
new_revision: true
```

Extract the mapping:

```bash
for f in config/sync/media.type.*.yml; do
  bundle=$(basename "$f" .yml | sed 's/^media\.type\.//')
  source_field=$(grep 'source_field:' "$f" | awk '{print $2}')
  source_plugin=$(grep '^source:' "$f" | awk '{print $2}' | tr -d "'")
  echo "$bundle|$source_plugin|$source_field"
done
```

### Method B: Drush

```bash
# List all media type configs
drush config:list | grep '^media\.type\.'

# Export each
for mt in $(drush config:list | grep '^media\.type\.'); do
  drush config:get "$mt" --format=json
done > media_types_all.json
```

### Method C: Database

```sql
SELECT name, data FROM config
WHERE name LIKE 'media.type.%'
ORDER BY name;
```

The `data` column is serialized PHP. Deserialize to read `source_configuration.source_field`.

```php
$rows = \Drupal::database()->select('config', 'c')
  ->fields('c', ['name', 'data'])
  ->condition('name', 'media.type.%', 'LIKE')
  ->execute();
$types = [];
foreach ($rows as $row) {
  $config = unserialize($row->data);
  $types[$config['id']] = [
    'label' => $config['label'],
    'source_plugin' => $config['source'],
    'source_field' => $config['source_configuration']['source_field'] ?? null,
  ];
}
file_put_contents('media_types.json', json_encode($types, JSON_PRETTY_PRINT));
```

---

## Step 2: Export Media Entities

### Method A: JSON:API (D8+)

JSON:API exposes media entities at `/jsonapi/media/{bundle}`. Include the source field's file entity to get file metadata in one request.

```bash
# Image media with file data included
curl -s 'https://example.com/jsonapi/media/image?include=field_media_image&page[limit]=50' \
  -H 'Accept: application/vnd.api+json' | python3 -m json.tool > media_image_page1.json
```

The response `data[]` array holds media entities. The `included[]` array holds the referenced `file--file` entities with `uri.url` (relative path) and `uri.value` (internal URI like `public://photo.jpg`).

Paginate using `links.next.href`:

```bash
#!/bin/bash
BUNDLE="image"
BASE_URL="https://example.com"
URL="${BASE_URL}/jsonapi/media/${BUNDLE}?include=field_media_image&page[limit]=50"
PAGE=1

while [ -n "$URL" ]; do
  echo "Fetching page $PAGE..." >&2
  curl -s "$URL" -H 'Accept: application/vnd.api+json' > "media_${BUNDLE}_page${PAGE}.json"
  URL=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('links', {}).get('next', {}).get('href', ''))
" "media_${BUNDLE}_page${PAGE}.json")
  PAGE=$((PAGE + 1))
done
```

Repeat for each bundle: `document`, `audio`, `video`, `remote_video`, and any custom types discovered in Step 1. Change the `include` parameter to match each bundle's source field.

```bash
# Document media
curl -s 'https://example.com/jsonapi/media/document?include=field_media_document&page[limit]=50' \
  -H 'Accept: application/vnd.api+json'

# Remote video (no file include needed, URL is a plain field)
curl -s 'https://example.com/jsonapi/media/remote_video?page[limit]=50' \
  -H 'Accept: application/vnd.api+json'
```

**Authentication for unpublished media:** JSON:API respects entity access. Anonymous requests return only published media. For unpublished items, send an authenticated request:

```bash
# Basic auth (if enabled)
curl -s -u admin:password 'https://example.com/jsonapi/media/image?include=field_media_image'

# OAuth2 bearer token
curl -s -H "Authorization: Bearer ${TOKEN}" \
  'https://example.com/jsonapi/media/image?include=field_media_image'
```

### Method B: Drush Entity Query

```bash
# Count media per bundle
drush php:eval '
$types = \Drupal::entityTypeManager()->getStorage("media_type")->loadMultiple();
foreach ($types as $type) {
  $count = \Drupal::entityQuery("media")
    ->condition("bundle", $type->id())
    ->accessCheck(FALSE)
    ->count()
    ->execute();
  echo $type->id() . ": " . $count . "\n";
}
'
```

Full export with source field data:

```php
// save as export_media.php, run with: drush php:script export_media.php
$storage = \Drupal::entityTypeManager()->getStorage('media');
$type_storage = \Drupal::entityTypeManager()->getStorage('media_type');
$types = $type_storage->loadMultiple();

$output = [];
foreach ($types as $type) {
  $source_field = $type->getSource()->getConfiguration()['source_field'];
  $ids = \Drupal::entityQuery('media')
    ->condition('bundle', $type->id())
    ->accessCheck(FALSE)
    ->execute();

  foreach (array_chunk($ids, 100) as $chunk) {
    $entities = $storage->loadMultiple($chunk);
    foreach ($entities as $media) {
      $row = [
        'mid' => $media->id(),
        'uuid' => $media->uuid(),
        'name' => $media->getName(),
        'bundle' => $media->bundle(),
        'status' => (int) $media->isPublished(),
        'uid' => (int) $media->getOwnerId(),
        'created' => (int) $media->getCreatedTime(),
        'changed' => (int) $media->getChangedTime(),
        'langcode' => $media->language()->getId(),
      ];

      // Source field value
      $source_value = $media->get($source_field);
      if ($source_value->entity) {
        // File-backed media
        $file = $source_value->entity;
        $row['file'] = [
          'fid' => (int) $file->id(),
          'uuid' => $file->uuid(),
          'uri' => $file->getFileUri(),
          'url' => \Drupal::service('file_url_generator')->generateAbsoluteString($file->getFileUri()),
          'filename' => $file->getFilename(),
          'filemime' => $file->getMimeType(),
          'filesize' => (int) $file->getSize(),
        ];
        // Image-specific columns
        if ($media->bundle() === 'image') {
          $row['file']['alt'] = $source_value->alt ?? '';
          $row['file']['title'] = $source_value->title ?? '';
          $row['file']['width'] = (int) ($source_value->width ?? 0);
          $row['file']['height'] = (int) ($source_value->height ?? 0);
        }
      } else {
        // Remote media (oEmbed) or empty
        $row['source_value'] = $source_value->value ?? null;
      }

      // Custom fields on the media entity
      $custom_fields = [];
      foreach ($media->getFieldDefinitions() as $field_name => $definition) {
        if ($definition->getFieldStorageDefinition()->isBaseField()) continue;
        if ($field_name === $source_field) continue;
        $field = $media->get($field_name);
        if (!$field->isEmpty()) {
          $custom_fields[$field_name] = $field->getValue();
        }
      }
      if ($custom_fields) {
        $row['custom_fields'] = $custom_fields;
      }

      $output[] = $row;
    }
  }
}

file_put_contents('media_export.json', json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "Exported " . count($output) . " media entities.\n";
```

### Method C: Database Queries (D8+)

The media module uses these tables:

| Table | Purpose |
|---|---|
| `media` | Base table: `mid`, `vid` (revision), `bundle`, `uuid`, `langcode` |
| `media_field_data` | Data table: `mid`, `vid`, `bundle`, `langcode`, `name`, `status`, `uid`, `created`, `changed`, `default_langcode` |
| `media_field_revision` | Revision data |
| `media__field_media_image` | Image source field values (entity_id = mid, field_media_image_target_id = fid, plus alt/title/width/height columns) |
| `media__field_media_document` | Document source field values (entity_id = mid, field_media_document_target_id = fid) |
| `media__field_media_oembed_video` | Remote video source (entity_id = mid, field_media_oembed_video_value = URL string) |
| `media__field_media_audio_file` | Audio source field values |
| `media__field_media_video_file` | Video file source field values |
| `file_managed` | All files: `fid`, `uuid`, `uid`, `filename`, `uri`, `filemime`, `filesize`, `status`, `created`, `changed` |

Export image media with file data:

```sql
SELECT
  mfd.mid,
  mfd.uuid,
  mfd.name,
  mfd.bundle,
  mfd.status,
  mfd.uid,
  mfd.created,
  mfd.changed,
  mfd.langcode,
  fmi.field_media_image_target_id AS fid,
  fmi.field_media_image_alt AS alt,
  fmi.field_media_image_title AS title,
  fmi.field_media_image_width AS width,
  fmi.field_media_image_height AS height,
  fm.uri,
  fm.filename,
  fm.filemime,
  fm.filesize
FROM media_field_data mfd
JOIN media__field_media_image fmi
  ON fmi.entity_id = mfd.mid AND fmi.langcode = mfd.langcode
JOIN file_managed fm
  ON fm.fid = fmi.field_media_image_target_id
WHERE mfd.bundle = 'image'
  AND mfd.default_langcode = 1
ORDER BY mfd.mid;
```

Export document media:

```sql
SELECT
  mfd.mid,
  mfd.uuid,
  mfd.name,
  mfd.bundle,
  mfd.status,
  mfd.uid,
  mfd.created,
  mfd.changed,
  fmd.field_media_document_target_id AS fid,
  fm.uri,
  fm.filename,
  fm.filemime,
  fm.filesize
FROM media_field_data mfd
JOIN media__field_media_document fmd
  ON fmd.entity_id = mfd.mid AND fmd.langcode = mfd.langcode
JOIN file_managed fm
  ON fm.fid = fmd.field_media_document_target_id
WHERE mfd.bundle = 'document'
  AND mfd.default_langcode = 1
ORDER BY mfd.mid;
```

Export remote video media:

```sql
SELECT
  mfd.mid,
  mfd.uuid,
  mfd.name,
  mfd.bundle,
  mfd.status,
  mfd.uid,
  mfd.created,
  mfd.changed,
  ov.field_media_oembed_video_value AS oembed_url
FROM media_field_data mfd
JOIN media__field_media_oembed_video ov
  ON ov.entity_id = mfd.mid AND ov.langcode = mfd.langcode
WHERE mfd.bundle = 'remote_video'
  AND mfd.default_langcode = 1
ORDER BY mfd.mid;
```

For custom media types, find the source field table name. Field tables follow the pattern `media__{field_name}`. The target column is `{field_name}_target_id` for file references or `{field_name}_value` for string/URL sources.

```sql
-- Find all media field tables
SHOW TABLES LIKE 'media\_\_%';
```

### Method D: Database Queries (D7)

D7 has no media entities. Files live in `file_managed` and attach to nodes through field tables.

```sql
-- All managed files
SELECT
  fid,
  uid,
  filename,
  uri,
  filemime,
  filesize,
  status,
  timestamp AS created
FROM file_managed
ORDER BY fid;

-- File usage: which entities reference each file
SELECT
  f.fid,
  f.filename,
  f.uri,
  fu.module,
  fu.type AS entity_type,
  fu.id AS entity_id,
  fu.count
FROM file_managed f
JOIN file_usage fu ON fu.fid = f.fid
ORDER BY f.fid;

-- Image field data on nodes (example: field_image on article content type)
SELECT
  n.nid,
  n.type,
  fi.field_image_fid AS fid,
  fi.field_image_alt AS alt,
  fi.field_image_title AS title,
  fi.field_image_width AS width,
  fi.field_image_height AS height,
  fm.uri,
  fm.filename,
  fm.filemime,
  fm.filesize
FROM node n
JOIN field_data_field_image fi ON fi.entity_id = n.nid AND fi.entity_type = 'node'
JOIN file_managed fm ON fm.fid = fi.field_image_fid
ORDER BY n.nid;
```

To find all file/image fields on nodes in D7:

```sql
-- All fields that reference files
SELECT fc.field_name, fc.data
FROM field_config fc
WHERE fc.type IN ('file', 'image')
  AND fc.active = 1
  AND fc.deleted = 0
ORDER BY fc.field_name;
```

The `data` column is serialized PHP containing field settings. Each field stores data in `field_data_{field_name}` and `field_revision_{field_name}` tables.

---

## Step 3: Export Custom Fields on Media Entities

Media entities can carry fields beyond the source field. Common examples: `field_caption`, `field_credit`, `field_tags`, `field_category`.

### Find Custom Fields per Media Bundle

```bash
# Config YAML
find config/sync -name "field.field.media.*.yml" | sort
```

Each file defines one field instance on a media bundle. The filename pattern is `field.field.media.{bundle}.{field_name}.yml`.

```bash
# Drush
drush field:info --entity-type=media --format=json
```

```sql
-- Database (D8+)
SELECT name, data FROM config
WHERE name LIKE 'field.field.media.%'
ORDER BY name;
```

### Export Custom Field Values

For each custom field, a `media__{field_name}` table exists. Query it the same way as source field tables:

```sql
SELECT entity_id AS mid, bundle, delta, *
FROM media__field_caption
ORDER BY entity_id, delta;
```

For entity reference fields on media (e.g., `field_tags` pointing to taxonomy terms):

```sql
SELECT
  mft.entity_id AS mid,
  mft.bundle,
  mft.field_tags_target_id AS tid,
  td.name AS term_name
FROM media__field_tags mft
JOIN taxonomy_term_field_data td ON td.tid = mft.field_tags_target_id
ORDER BY mft.entity_id, mft.delta;
```

---

## Step 4: Build the Media Usage Map

Track which content entities reference which media entities. This map tells you which media to keep and where each file appears in the target platform.

### Method A: Database (D8+)

Every entity reference field pointing to media creates a table like `node__{field_name}` or `paragraph__{field_name}`. The column `{field_name}_target_id` holds the media entity ID.

```sql
-- Find all entity reference fields targeting media
SELECT fc.field_name, fci.entity_type, fci.bundle
FROM config fc_config
-- Better approach: query the field config directly
SELECT name, data FROM config
WHERE name LIKE 'field.storage.%.%'
AND data LIKE '%"target_type";s:5:"media"%';
```

A more reliable approach using Drush:

```php
// save as media_usage_map.php, run with: drush php:script media_usage_map.php
$entity_field_manager = \Drupal::service('entity_field.manager');
$entity_type_manager = \Drupal::entityTypeManager();

// Find all entity reference fields targeting media
$usage = [];
$field_map = $entity_field_manager->getFieldMapByFieldType('entity_reference');

foreach ($field_map as $entity_type_id => $fields) {
  foreach ($fields as $field_name => $field_info) {
    foreach ($field_info['bundles'] as $bundle) {
      $field_definitions = $entity_field_manager->getFieldDefinitions($entity_type_id, $bundle);
      if (!isset($field_definitions[$field_name])) continue;
      $field_def = $field_definitions[$field_name];
      $settings = $field_def->getSettings();
      if (($settings['target_type'] ?? '') !== 'media') continue;

      // Query this field's data table
      $table = $entity_type_id . '__' . $field_name;
      $column = $field_name . '_target_id';
      try {
        $results = \Drupal::database()->select($table, 't')
          ->fields('t', ['entity_id', 'bundle', $column])
          ->execute();
        foreach ($results as $row) {
          $usage[] = [
            'entity_type' => $entity_type_id,
            'entity_id' => (int) $row->entity_id,
            'bundle' => $row->bundle,
            'field_name' => $field_name,
            'media_id' => (int) $row->{$column},
          ];
        }
      } catch (\Exception $e) {
        // Table might not exist if no data was ever saved
      }
    }
  }
}

file_put_contents('media_usage_map.json', json_encode($usage, JSON_PRETTY_PRINT));
echo "Found " . count($usage) . " media references.\n";
```

### Method B: Entity Usage Module

If the `entity_usage` module is installed, it maintains a dedicated tracking table:

```sql
SELECT
  source_type,
  source_id,
  source_langcode,
  target_type,
  target_id,
  method,
  field_name,
  count
FROM entity_usage
WHERE target_type = 'media'
ORDER BY target_id;
```

This table also catches media embedded in WYSIWYG fields via `<drupal-media>` tags, which field-level entity reference queries miss.

### Method C: WYSIWYG Embedded Media

D8+ CKEditor can embed media using `<drupal-media>` tags in formatted text fields. These references do not appear in entity reference field tables.

```sql
-- Search all long text fields for embedded media tags
-- Check body fields first
SELECT
  nfd.nid,
  nfd.type AS bundle,
  nfd.body_value
FROM node__body nfd
WHERE nfd.body_value LIKE '%<drupal-media%'
ORDER BY nfd.nid;
```

Parse the `data-entity-uuid` attribute from each `<drupal-media>` tag:

```php
// Extract embedded media UUIDs from body fields
$results = \Drupal::database()->select('node__body', 'b')
  ->fields('b', ['entity_id', 'bundle', 'body_value'])
  ->condition('body_value', '%<drupal-media%', 'LIKE')
  ->execute();

$embedded = [];
foreach ($results as $row) {
  preg_match_all('/data-entity-uuid="([^"]+)"/', $row->body_value, $matches);
  foreach ($matches[1] as $uuid) {
    $embedded[] = [
      'node_id' => (int) $row->entity_id,
      'bundle' => $row->bundle,
      'field' => 'body',
      'media_uuid' => $uuid,
    ];
  }
}
file_put_contents('embedded_media.json', json_encode($embedded, JSON_PRETTY_PRINT));
echo count($embedded) . " embedded media references found.\n";
```

Check other long text fields too. Find them:

```sql
SHOW TABLES LIKE 'node\_\_field\_%';
-- Then check which ones have a *_value column containing <drupal-media
```

### Method D: D7 File Usage

D7 tracks file usage in the `file_usage` table:

```sql
SELECT
  fu.fid,
  fu.module,
  fu.type AS entity_type,
  fu.id AS entity_id,
  fu.count,
  fm.uri,
  fm.filename
FROM file_usage fu
JOIN file_managed fm ON fm.fid = fu.fid
ORDER BY fu.type, fu.id;
```

---

## Step 5: Build the File Download Manifest

Create a manifest that maps every file to a downloadable URL with deduplication metadata.

### Generate the Manifest

```php
// save as build_manifest.php, run with: drush php:script build_manifest.php
$db = \Drupal::database();
$file_url_generator = \Drupal::service('file_url_generator');

$files = $db->select('file_managed', 'fm')
  ->fields('fm', ['fid', 'uuid', 'uid', 'filename', 'uri', 'filemime', 'filesize', 'status', 'created', 'changed'])
  ->orderBy('fid')
  ->execute();

// Count usage per file
$usage_counts = $db->query("
  SELECT fu.fid, SUM(fu.count) AS total_usage
  FROM file_usage fu
  GROUP BY fu.fid
")->fetchAllKeyed();

$manifest = [];
foreach ($files as $file) {
  $scheme = parse_url($file->uri, PHP_URL_SCHEME) ?: 'unknown';
  $row = [
    'fid' => (int) $file->fid,
    'uuid' => $file->uuid,
    'uri' => $file->uri,
    'filename' => $file->filename,
    'filemime' => $file->filemime,
    'filesize' => (int) $file->filesize,
    'status' => (int) $file->status,
    'scheme' => $scheme,
    'usage_count' => (int) ($usage_counts[$file->fid] ?? 0),
  ];

  // Generate download URL
  if ($scheme === 'public') {
    $row['download_url'] = $file_url_generator->generateAbsoluteString($file->uri);
  } elseif ($scheme === 'private') {
    // Private files route through Drupal
    $row['download_url'] = $file_url_generator->generateAbsoluteString($file->uri);
    $row['requires_auth'] = true;
  } elseif ($scheme === 's3') {
    $row['download_url'] = $file_url_generator->generateAbsoluteString($file->uri);
    $row['s3_uri'] = $file->uri;
  } else {
    $row['download_url'] = null;
    $row['note'] = 'Unknown scheme: ' . $scheme;
  }

  // File hash for deduplication (compute from disk)
  $realpath = \Drupal::service('file_system')->realpath($file->uri);
  if ($realpath && file_exists($realpath)) {
    $row['sha256'] = hash_file('sha256', $realpath);
  } else {
    $row['sha256'] = null;
  }

  $manifest[] = $row;
}

file_put_contents('file_manifest.json', json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "Manifest: " . count($manifest) . " files.\n";

// Dedup report
$hashes = array_filter(array_column($manifest, 'sha256'));
$unique = count(array_unique($hashes));
$dupes = count($hashes) - $unique;
echo "Unique files by hash: $unique. Duplicates: $dupes.\n";
```

### D7 Manifest

D7 uses the same `file_managed` and `file_usage` tables. The main difference: no `file_url_generator` service. Build URLs manually.

```php
// D7 manifest script (run with drush scr)
$files = db_query("
  SELECT fm.fid, fm.uid, fm.filename, fm.uri, fm.filemime, fm.filesize, fm.status, fm.timestamp
  FROM {file_managed} fm
  ORDER BY fm.fid
");

$usage_counts = db_query("
  SELECT fid, SUM(count) AS total_usage
  FROM {file_usage}
  GROUP BY fid
")->fetchAllKeyed();

$manifest = [];
foreach ($files as $file) {
  $scheme = file_uri_scheme($file->uri);
  $manifest[] = [
    'fid' => (int) $file->fid,
    'uri' => $file->uri,
    'download_url' => file_create_url($file->uri),
    'filename' => $file->filename,
    'filemime' => $file->filemime,
    'filesize' => (int) $file->filesize,
    'scheme' => $scheme,
    'usage_count' => (int) ($usage_counts[$file->fid] ?? 0),
    'sha256' => drupal_realpath($file->uri) ? hash_file('sha256', drupal_realpath($file->uri)) : null,
  ];
}

file_put_contents('file_manifest_d7.json', json_encode($manifest, JSON_PRETTY_PRINT));
echo "D7 manifest: " . count($manifest) . " files.\n";
```

---

## Step 6: Download Files

Use the manifest to download every file. Handle each URI scheme differently.

### Public Files: wget Mirror

```bash
# Parse manifest and download all public:// files
python3 -c "
import json, os
manifest = json.load(open('file_manifest.json'))
with open('download_urls.txt', 'w') as f:
    for item in manifest:
        if item['scheme'] == 'public' and item['download_url']:
            f.write(item['download_url'] + '\n')
print(f'Wrote {sum(1 for i in manifest if i[\"scheme\"] == \"public\")} URLs')
"

# Download with wget, preserving directory structure
wget --input-file=download_urls.txt \
  --no-clobber \
  --directory-prefix=exported_files \
  --force-directories \
  --no-host-directories \
  --cut-dirs=2 \
  --timeout=30 \
  --tries=3 \
  --wait=0.5
```

### Public Files: rsync (if you have SSH)

```bash
# Fastest method when you have filesystem access
rsync -avz --progress \
  user@server:/var/www/html/sites/default/files/ \
  ./exported_files/
```

### Private Files: Drush Copy

Private files are not web-accessible. Copy them through Drush or direct filesystem access.

```php
// save as download_private.php, run with: drush php:script download_private.php
$manifest = json_decode(file_get_contents('file_manifest.json'), true);
$fs = \Drupal::service('file_system');
$dest_base = 'exported_files/private';

foreach ($manifest as $item) {
  if ($item['scheme'] !== 'private') continue;

  $realpath = $fs->realpath($item['uri']);
  if (!$realpath || !file_exists($realpath)) {
    echo "MISSING: {$item['uri']}\n";
    continue;
  }

  // Preserve directory structure
  $relative = str_replace('private://', '', $item['uri']);
  $dest = $dest_base . '/' . $relative;
  $dest_dir = dirname($dest);
  if (!is_dir($dest_dir)) {
    mkdir($dest_dir, 0755, true);
  }

  copy($realpath, $dest);
}
echo "Private file copy complete.\n";
```

### S3 Files

```bash
# Get bucket config
BUCKET=$(drush config:get s3fs.settings bucket --format=string)
PREFIX=$(drush config:get s3fs.settings root_folder --format=string)

# Sync all files from S3
aws s3 sync "s3://${BUCKET}/${PREFIX}" ./exported_files/s3/ \
  --no-sign-request  # Remove this flag if auth is needed
```

### Remote Video URLs

Remote videos (YouTube, Vimeo) have no files to download. Export only the URLs.

```bash
# Extract remote video URLs from media export
python3 -c "
import json
media = json.load(open('media_export.json'))
remote = [m for m in media if m['bundle'] == 'remote_video']
with open('remote_video_urls.json', 'w') as f:
    json.dump([{
        'mid': m['mid'],
        'name': m['name'],
        'url': m.get('source_value', ''),
    } for m in remote], f, indent=2)
print(f'{len(remote)} remote video URLs exported')
"
```

These URLs can be used as-is in the target platform. YouTube and Vimeo embed codes work the same everywhere.

---

## Step 7: Validate the Export

### File Count Check

```bash
# Compare manifest count to actual downloaded files
MANIFEST_COUNT=$(python3 -c "
import json
m = json.load(open('file_manifest.json'))
print(sum(1 for f in m if f['scheme'] in ('public', 'private', 's3')))
")
DISK_COUNT=$(find exported_files -type f | wc -l | tr -d ' ')
echo "Manifest: $MANIFEST_COUNT files, Disk: $DISK_COUNT files"
```

### Hash Verification

```bash
# Verify downloaded files match manifest hashes
python3 << 'EOF'
import json, hashlib, os

manifest = json.load(open('file_manifest.json'))
base = 'exported_files'
ok = 0
mismatch = 0
missing = 0

for item in manifest:
    if not item.get('sha256') or item['scheme'] == 'temporary':
        continue

    # Build local path from URI
    uri = item['uri']
    if uri.startswith('public://'):
        local = os.path.join(base, uri.replace('public://', ''))
    elif uri.startswith('private://'):
        local = os.path.join(base, 'private', uri.replace('private://', ''))
    elif uri.startswith('s3://'):
        local = os.path.join(base, 's3', uri.replace('s3://', ''))
    else:
        continue

    if not os.path.exists(local):
        missing += 1
        print(f"MISSING: {local}")
        continue

    local_hash = hashlib.sha256(open(local, 'rb').read()).hexdigest()
    if local_hash == item['sha256']:
        ok += 1
    else:
        mismatch += 1
        print(f"MISMATCH: {item['uri']} expected={item['sha256'][:16]}... got={local_hash[:16]}...")

print(f"\nResults: {ok} OK, {mismatch} mismatch, {missing} missing")
EOF
```

### Orphan Detection

Files in `file_managed` with zero usage count are orphans. They exist on disk but nothing references them.

```sql
-- D8+: Files with no usage record
SELECT fm.fid, fm.uri, fm.filename, fm.filesize
FROM file_managed fm
LEFT JOIN file_usage fu ON fu.fid = fm.fid
WHERE fu.fid IS NULL
ORDER BY fm.filesize DESC;

-- D7: same query
```

Decide whether to include orphans in the export. They inflate transfer size but might contain files referenced by hardcoded URLs in templates or custom code.

---

## Output Files

| File | Contents |
|---|---|
| `media_types.json` | Media type definitions with source field mappings |
| `media_export.json` | All media entities with source file metadata and custom fields |
| `media_usage_map.json` | Entity-to-media reference map |
| `embedded_media.json` | Media embedded in WYSIWYG fields via `<drupal-media>` tags |
| `file_manifest.json` | Every file: URI, download URL, hash, size, MIME type, usage count |
| `remote_video_urls.json` | YouTube/Vimeo URLs from remote_video media |
| `exported_files/` | Downloaded files preserving directory structure |
| `file_manifest_d7.json` | D7-specific manifest (when running against D7) |

---

## Gotchas

**Missing files on disk.** `file_managed` can reference files that were deleted from the filesystem. The manifest builder logs these as `sha256: null`. Run `drush file:sanitize` or check the missing files report at `/admin/reports/status` before exporting.

**Multilingual media.** Media entities can have translations. Each translation appears in `media_field_data` with a different `langcode`. The Drush export script handles this through entity API translation loading. The database queries filter on `default_langcode = 1` for the primary version. Export translations separately if needed:

```sql
SELECT mid, langcode, name, status
FROM media_field_data
WHERE default_langcode = 0
ORDER BY mid, langcode;
```

**file_managed status column.** Status 0 means "temporary" (not yet attached to an entity, pending garbage collection). Status 1 means "permanent." Temporary files can be skipped unless you want to preserve in-progress uploads.

**Large file counts.** Sites with 100k+ files need batch processing. The manifest builder and download scripts handle this, but hash computation is CPU-intensive. Skip hashing for the initial export and compute hashes on the downloaded copy instead.

**Image derivatives.** Drupal generates derivative images (thumbnails, crops) in `sites/default/files/styles/`. These are regenerable on any Drupal site and do not need to be migrated. Only export originals. The `file_managed` table contains only originals. The `styles/` directory can be excluded from rsync/wget.

```bash
# rsync excluding generated image styles
rsync -avz --progress \
  --exclude='styles/' \
  user@server:/var/www/html/sites/default/files/ \
  ./exported_files/
```

**Private file authentication.** The `system/files/` route in Drupal checks entity access. An anonymous request returns 403. Use a session cookie or basic auth:

```bash
# Get a session cookie
curl -c cookies.txt -X POST 'https://example.com/user/login' \
  -d 'name=admin&pass=password&form_id=user_login_form'

# Download a private file using the session
curl -b cookies.txt -o output.pdf \
  'https://example.com/system/files/private/document.pdf'
```

**D7 Media module (contrib).** Some D7 sites installed the contrib `media` module, which adds a `media` entity type on top of `file_managed`. If `SHOW TABLES LIKE 'media%'` returns results on a D7 site, that contrib module is installed. Its schema differs from D8+ core media. Query the `media` table for entity data and `file_managed` for file data.

```sql
-- D7 contrib media module entities
SELECT m.fid, m.type AS bundle, fm.uri, fm.filename, fm.filemime, fm.filesize
FROM media m
JOIN file_managed fm ON fm.fid = m.fid
ORDER BY m.fid;
```
