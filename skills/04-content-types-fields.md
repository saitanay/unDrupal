# Skill 4: Content Types and Field Definitions Export

Export the structural schema of every content type and its fields. This is structure, not data. The output describes what content looks like, not the content itself.

---

## What Gets Exported

### Per Content Type

| Property | Source |
|---|---|
| Machine name | `type` key in `node.type.*.yml` / `node_type.type` column (D7) |
| Label | `name` key |
| Description | `description` key |
| Help text | `help` key (shows on node/add form) |
| New revision default | `new_revision` (D8+) / `settings.node.options.revision` (early D8) / `node_type.custom` (D7) |
| Preview mode | `preview_mode` — 0 = disabled, 1 = optional, 2 = required |
| Display submitted | `display_submitted` — show "Submitted by [user] on [date]" |
| Publishing defaults | Pulled from `node.type.*.yml` third-party settings or `options` array: status, promote, sticky |
| Menu settings | `menu_ui` third-party settings: available menus, parent |
| Comment settings | From `field.field.node.{bundle}.comment` or `comment.type.*.yml` |
| Language settings | `language.content_settings.node.{bundle}.yml`: default_langcode, language_alterable |
| URL alias pattern | `pathauto.pattern.*.yml` where selection conditions match the bundle |

### Per Field

Two config objects define every field in D8+. In D7, two database tables hold the same split.

**Field storage** (one per field name across all bundles):
- Machine name (`field_name`)
- Field type (`type`)
- Cardinality (`cardinality` — 1 for single, -1 for unlimited, N for fixed limit)
- Entity type it belongs to (`entity_type`)
- Type-specific settings (`settings` — varies by field type, see below)
- Module that provides it (`module`)
- Locked status, translatable flag, custom storage flag

**Field instance** (one per field per bundle):
- Label, description
- Required flag
- Default value and default value callback
- Translatable flag (overrides storage-level setting)
- Field-type-specific instance settings (`settings`)

**Display configuration** (not part of this skill's primary scope, covered in Skill 6):
- Widget type and settings (form display)
- Formatter type and settings (view display)

---

## Field Type Reference

Every field type has different storage settings. The export must capture these per-type details.

### Text Fields

| Field Type | Machine Name | Key Settings |
|---|---|---|
| Plain text | `string` | `max_length` (default 255) |
| Plain text, long | `string_long` | (no length limit) |
| Formatted text | `text` | `max_length` (default 255) |
| Formatted text, long | `text_long` | (no length limit) |
| Formatted, long + summary | `text_with_summary` | (no length limit) |

Instance settings for formatted text fields:
- `text_processing`: 1 = filtered through text format, 0 = plain
- `display_summary`: boolean (text_with_summary only)
- `allowed_formats`: array of text format machine names (if restricted)

### Numeric Fields

| Field Type | Machine Name | Key Settings |
|---|---|---|
| Integer | `integer` | (none at storage level) |
| Decimal | `decimal` | `precision`, `scale` |
| Float | `float` | (none at storage level) |

Instance settings: `min`, `max`, `prefix`, `suffix`.

### List / Select Fields

| Field Type | Machine Name | Key Settings |
|---|---|---|
| List (text) | `list_string` | `allowed_values` — array of key/label pairs |
| List (integer) | `list_integer` | `allowed_values` |
| List (float) | `list_float` | `allowed_values` |

The `allowed_values` array is the critical export target. Some sites use `allowed_values_function` instead of a static list.

### Boolean

Machine name: `boolean`. Settings: `on_label`, `off_label` (display only, stored as 0/1).

### Entity Reference

Machine name: `entity_reference`.

Storage settings:
- `target_type` — the entity type being referenced (node, taxonomy_term, user, media, paragraph, etc.)

Instance settings:
- `handler` — selection handler plugin ID (usually `default:{entity_type}`)
- `handler_settings`:
  - `target_bundles` — array of allowed bundles (null = all)
  - `sort` — field and direction for autocomplete sorting
  - `auto_create` — boolean, create new entities on the fly (taxonomy terms)
  - `auto_create_bundle` — which bundle to auto-create into

### Entity Reference Revisions (Paragraphs)

Machine name: `entity_reference_revisions`. Provided by the `entity_reference_revisions` module. Used almost exclusively for Paragraphs.

Storage settings:
- `target_type` — almost always `paragraph`

Instance settings:
- `handler` — usually `default:paragraph`
- `handler_settings`:
  - `target_bundles` — which paragraph types are allowed on this field
  - `target_bundles_drag_drop` — ordering and enable/disable per paragraph type
  - `negate` — 0 = include listed bundles, 1 = exclude listed bundles

Nesting depth is not stored in config. A paragraph type that has its own entity_reference_revisions field pointing to other paragraph types creates nesting. Trace the chain by following each paragraph type's fields recursively.

### File and Image Fields

**File** — machine name: `file`.

Storage settings:
- `target_type`: `file`
- `display_field`: boolean — whether "Display" checkbox shows on upload
- `display_default`: boolean

Instance settings:
- `file_directory` — token-based upload path (e.g., `[date:custom:Y]-[date:custom:m]`)
- `file_extensions` — space-separated list (e.g., `txt pdf doc docx`)
- `max_filesize` — string like `2 MB` or empty for site default
- `description_field` — boolean, show description input

**Image** — machine name: `image`.

Storage settings:
- `target_type`: `file`
- `default_image` — UUID of default image, alt, title, width, height

Instance settings:
- `file_directory`, `file_extensions` (e.g., `png gif jpg jpeg webp`), `max_filesize`
- `max_resolution`, `min_resolution` — strings like `1920x1080` or empty
- `alt_field` — boolean (almost always 1)
- `alt_field_required` — boolean
- `title_field` — boolean
- `title_field_required` — boolean
- `default_image` — overrides storage-level default per bundle

### Link Fields

Machine name: `link`. Provided by the `link` module.

Instance settings:
- `link_type` — `LinkItemInterface::LINK_EXTERNAL` (16), `LINK_INTERNAL` (1), or `LINK_GENERIC` (17 = both)
- `title` — `LINK_TITLE_DISABLED` (0), `LINK_TITLE_OPTIONAL` (1), `LINK_TITLE_REQUIRED` (2)

### Date Fields

| Field Type | Machine Name | Key Settings |
|---|---|---|
| Date only | `datetime` | `datetime_type: date` |
| Date and time | `datetime` | `datetime_type: datetime` |
| Date range | `daterange` | `datetime_type: date` or `datetime` |

Storage settings contain `datetime_type`. No timezone is stored in config. D8+ stores dates as strings in UTC (`Y-m-d\TH:i:s` for datetime, `Y-m-d` for date-only).

### Telephone

Machine name: `telephone`. No significant settings. Stores a string.

### Email

Machine name: `email`. No significant settings. Stores a string.

### Address Fields

Machine name: `address`. Provided by the `address` module (wraps `commerceguys/addressing`).

Instance settings:
- `available_countries` — array of ISO country codes (empty = all)
- `langcode_override` — force address format to specific language
- `field_overrides` — per-property overrides: `givenName`, `familyName`, `organization`, `addressLine1`, `addressLine2`, `locality`, `administrativeArea`, `postalCode`. Each can be `hidden`, `optional`, or `required`.

### Other Common Types

| Field Type | Machine Name | Notes |
|---|---|---|
| Boolean | `boolean` | 0/1 storage |
| URI | `uri` | Raw URI string |
| Timestamp | `timestamp` | UNIX timestamp integer |
| UUID | `uuid` | Base field, not configurable |
| Map | `map` | Serialized array blob |
| Geofield | `geofield` | Contrib. Stores WKT + lat/lon/bounds |
| Color | `color_field` | Contrib. Stores hex + opacity |
| Video Embed | `video_embed_field` | Contrib. Stores URL string |
| Viewfield | `viewfield` | Contrib. Stores view ID + display |
| Smart Date | `smartdate` | Contrib. Stores start/end timestamps + duration |
| Office Hours | `office_hours` | Contrib. Stores day/starthours/endhours/comment |
| Media Library | `entity_reference` | Core in D9+. Target type = media, widget = media_library_widget |

---

## Access Patterns

### Pattern 1: Config YAML (D8/D9/D10/D11)

Fastest if you have filesystem or `drush config:export` access.

**Content types:**
```bash
# List all content types
ls sites/default/files/config_*/sync/node.type.*.yml
# Or from exported config directory
ls config/sync/node.type.*.yml
```

**Field storage definitions:**
```bash
ls config/sync/field.storage.node.*.yml
```

**Field instance definitions:**
```bash
ls config/sync/field.field.node.*.yml
# Pattern: field.field.{entity_type}.{bundle}.{field_name}.yml
```

**Config YAML structure — `node.type.article.yml`:**
```yaml
langcode: en
status: true
dependencies:
  module:
    - menu_ui
third_party_settings:
  menu_ui:
    available_menus:
      - main
    parent: 'main:'
name: Article
type: article
description: 'Use articles for time-sensitive content like news and blog posts.'
help: ''
new_revision: true
preview_mode: 1
display_submitted: true
```

**Config YAML structure — `field.storage.node.field_tags.yml`:**
```yaml
langcode: en
status: true
dependencies:
  module:
    - node
    - taxonomy
id: node.field_tags
field_name: field_tags
entity_type: node
type: entity_reference
settings:
  target_type: taxonomy_term
module: core
locked: false
cardinality: -1
translatable: true
indexes: {}
persist_with_no_fields: false
custom_storage: false
```

**Config YAML structure — `field.field.node.article.field_tags.yml`:**
```yaml
langcode: en
status: true
dependencies:
  config:
    - field.storage.node.field_tags
    - node.type.article
    - taxonomy.vocabulary.tags
  module:
    - taxonomy
id: node.article.field_tags
field_name: field_tags
entity_type: node
bundle: article
label: Tags
description: 'Tag this content for categorization.'
required: false
translatable: false
default_value: []
default_value_callback: ''
settings:
  handler: 'default:taxonomy_term'
  handler_settings:
    target_bundles:
      tags: tags
    sort:
      field: name
      direction: asc
    auto_create: true
    auto_create_bundle: tags
field_type: entity_reference
```

### Pattern 2: Drush Commands (D8+)

```bash
# Export all config to a directory
drush config:export --destination=/tmp/config-export

# Get a single content type definition
drush config:get node.type.article

# Get field storage
drush config:get field.storage.node.field_tags

# Get field instance
drush config:get field.field.node.article.field_tags

# List all field types registered in the system
drush field:types

# List all field storage configs
drush config:list --prefix=field.storage.node

# List all field instance configs
drush config:list --prefix=field.field.node

# List all content types
drush config:list --prefix=node.type

# Get entity field info (Drush 12+)
drush field:info node --bundle=article

# Get all widgets and formatters
drush field:widgets
drush field:formatters
```

**Batch export script:**
```bash
#!/usr/bin/env bash
# Export all content type + field definitions to JSON
set -euo pipefail

OUTPUT_DIR="${1:-./_schema_export}"
mkdir -p "$OUTPUT_DIR"

# Content types
for ct in $(drush config:list --prefix=node.type --format=list); do
  drush config:get "$ct" --format=json > "$OUTPUT_DIR/${ct}.json"
done

# Field storage
for fs in $(drush config:list --prefix=field.storage.node --format=list); do
  drush config:get "$fs" --format=json > "$OUTPUT_DIR/${fs}.json"
done

# Field instances
for fi in $(drush config:list --prefix=field.field.node --format=list); do
  drush config:get "$fi" --format=json > "$OUTPUT_DIR/${fi}.json"
done

echo "Exported to $OUTPUT_DIR"
```

### Pattern 3: Database Queries

#### D8/D9/D10/D11

Config lives in the `config` table (key-value store). The `name` column holds the config ID, the `data` column holds serialized PHP.

```sql
-- All content types
SELECT name, data FROM config WHERE name LIKE 'node.type.%';

-- All field storage definitions for nodes
SELECT name, data FROM config WHERE name LIKE 'field.storage.node.%';

-- All field instances for nodes
SELECT name, data FROM config WHERE name LIKE 'field.field.node.%';

-- Pathauto patterns (for URL alias patterns)
SELECT name, data FROM config WHERE name LIKE 'pathauto.pattern.%';

-- Language settings per bundle
SELECT name, data FROM config
WHERE name LIKE 'language.content_settings.node.%';
```

The `data` column contains `serialize()`-encoded PHP. Decode with:
```php
$config = unserialize($row['data']);
```

Or from the command line:
```bash
drush php:eval "print_r(unserialize(db_query(\"SELECT data FROM {config} WHERE name = 'node.type.article'\")->fetchField()));"
```

#### D7

Two tables hold field definitions. Both have a `data` column with PHP-serialized blobs containing the real configuration.

**`field_config`** (field storage):

| Column | Purpose |
|---|---|
| `id` | Primary key |
| `field_name` | Machine name (e.g., `field_tags`) |
| `type` | Field type (e.g., `taxonomy_term_reference`, `text_with_summary`, `entityreference`) |
| `module` | Module providing the type (e.g., `text`, `taxonomy`, `entityreference`) |
| `active` | 1 if the providing module is enabled |
| `storage_type` | Usually `field_sql_storage` |
| `locked` | 1 if locked against deletion |
| `cardinality` | 1, -1, or N |
| `translatable` | 0 or 1 |
| `deleted` | 0 or 1 (soft-delete flag) |
| `data` | Serialized PHP: `settings`, `indexes`, `foreign keys` |

```sql
-- All active field definitions in D7
SELECT id, field_name, type, module, cardinality, translatable, data
FROM field_config
WHERE active = 1 AND deleted = 0;
```

**`field_config_instance`** (field instances per bundle):

| Column | Purpose |
|---|---|
| `id` | Primary key |
| `field_id` | Foreign key to `field_config.id` |
| `field_name` | Machine name |
| `entity_type` | Entity type (e.g., `node`, `taxonomy_term`) |
| `bundle` | Bundle machine name (e.g., `article`, `page`) |
| `deleted` | 0 or 1 |
| `data` | Serialized PHP: `label`, `description`, `required`, `settings`, `widget`, `display`, `default_value` |

```sql
-- All field instances on nodes in D7
SELECT fci.id, fci.field_name, fci.entity_type, fci.bundle, fci.data,
       fc.type, fc.cardinality, fc.data AS storage_data
FROM field_config_instance fci
JOIN field_config fc ON fc.id = fci.field_id
WHERE fci.entity_type = 'node'
  AND fci.deleted = 0
  AND fc.deleted = 0
  AND fc.active = 1
ORDER BY fci.bundle, fci.field_name;
```

**D7 content types** live in the `node_type` table:

```sql
SELECT type, name, base, module, description, help,
       has_title, title_label, custom, modified, locked
FROM node_type
WHERE disabled = 0;
```

D7 publishing defaults are stored in the `variable` table:
```sql
-- Returns serialized PHP array
SELECT name, value FROM variable
WHERE name LIKE 'node_options_%'
   OR name LIKE 'node_preview_%'
   OR name LIKE 'node_submitted_%';
```

**Decoding D7 serialized data** — the `data` blob in both `field_config` and `field_config_instance` uses `serialize()`. The instance `data` blob contains:
```php
[
  'label' => 'Tags',
  'description' => '',
  'required' => 0,
  'settings' => [...],          // type-specific instance settings
  'widget' => [
    'type' => 'taxonomy_autocomplete',
    'settings' => [...],
    'weight' => 3,
    'module' => 'taxonomy',
  ],
  'display' => [
    'default' => [
      'label' => 'above',
      'type' => 'taxonomy_term_reference_link',
      'settings' => [],
      'module' => 'taxonomy',
      'weight' => 10,
    ],
    'teaser' => [
      'type' => 'hidden',
      'label' => 'above',
    ],
  ],
  'default_value' => null,
]
```

### Pattern 4: JSON:API (Remote, No Shell)

JSON:API exposes entity type metadata through resource type discovery, but does not directly expose field storage config. Use it as a fallback to infer structure from data.

```bash
# Discover all resource types
curl -s https://example.com/jsonapi | jq '.links | keys'

# Get articles — field names and types visible in response structure
curl -s 'https://example.com/jsonapi/node/article?page[limit]=1' | jq '.data[0].attributes | keys'

# Relationships reveal entity reference fields
curl -s 'https://example.com/jsonapi/node/article?page[limit]=1' | jq '.data[0].relationships | keys'

# Get field type info from the resource type metadata (if exposed)
curl -s 'https://example.com/jsonapi/node/article?page[limit]=1&include=field_tags' \
  | jq '.included[0].type'
```

JSON:API cannot tell you cardinality, required status, allowed values, or widget settings. It can reveal:
- Which fields exist on each content type
- Which fields are entity references (they appear in `relationships`, not `attributes`)
- The target entity type of references (from the `type` of included resources)
- Whether a field is multi-value (array vs scalar in the response)

### Pattern 5: Content First Module (D9/D10/D11)

The `content_first` contrib module provides a purpose-built drush command:

```bash
# Export field architecture to YAML
drush content-first:export-architecture --entity-types=node

# Follow references to include paragraph types, taxonomy, media
drush content-first:export-architecture --entity-types=node --follow-references

# Filter to specific bundles
drush content-first:export-architecture --entity-types=node --bundles=article,page
```

Output groups shared fields into a `_defaults` section and nests bundle-specific fields under bundle keys. Uses human-readable type names (e.g., `textarea` instead of `text_long`).

---

## D7 Field Type Name Differences

D7 uses different machine names for several field types. Map these during export.

| D7 Machine Name | D8+ Machine Name | Notes |
|---|---|---|
| `text` | `string` or `text` | D7 `text` with `text_processing=0` maps to `string`; with `text_processing=1` maps to `text` |
| `text_long` | `string_long` or `text_long` | Same processing flag distinction |
| `text_with_summary` | `text_with_summary` | Same |
| `number_integer` | `integer` | Module changed from `number` to core |
| `number_decimal` | `decimal` | Module changed from `number` to core |
| `number_float` | `float` | Module changed from `number` to core |
| `taxonomy_term_reference` | `entity_reference` | D8 unified all references under `entity_reference` |
| `node_reference` | `entity_reference` | From `references` module |
| `user_reference` | `entity_reference` | From `references` module |
| `entityreference` | `entity_reference` | D7 contrib `entityreference` module |
| `file` | `file` | Same |
| `image` | `image` | Same |
| `list_text` | `list_string` | Renamed |
| `list_number` | `list_integer` or `list_float` | Split into two types |
| `list_boolean` | `boolean` | Became a standalone type |
| `link_field` | `link` | D7 module was `link`, type was `link_field` |
| `datestamp` | `timestamp` | D7 Date module |
| `datetime` | `datetime` | D7 Date module — different storage format |
| `date` | `datetime` | D7 Date module — ISO date string |

---

## Export Output Schema

The agent must produce output conforming to this JSON schema.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Drupal Content Type and Field Schema Export",
  "type": "object",
  "required": ["drupal_version", "exported_at", "content_types", "field_storage"],
  "properties": {
    "drupal_version": {
      "type": "string",
      "description": "Major Drupal version: '7', '8', '9', '10', or '11'"
    },
    "exported_at": {
      "type": "string",
      "format": "date-time"
    },
    "content_types": {
      "type": "object",
      "description": "Keyed by content type machine name",
      "additionalProperties": {
        "$ref": "#/definitions/content_type"
      }
    },
    "field_storage": {
      "type": "object",
      "description": "Keyed by field storage ID (e.g., 'node.field_tags')",
      "additionalProperties": {
        "$ref": "#/definitions/field_storage"
      }
    }
  },
  "definitions": {
    "content_type": {
      "type": "object",
      "required": ["machine_name", "label", "fields"],
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
        "help_text": {
          "type": ["string", "null"]
        },
        "new_revision": {
          "type": "boolean",
          "description": "Create new revision by default"
        },
        "preview_mode": {
          "type": "integer",
          "enum": [0, 1, 2],
          "description": "0=disabled, 1=optional, 2=required"
        },
        "display_submitted": {
          "type": "boolean"
        },
        "publishing_defaults": {
          "type": "object",
          "properties": {
            "status": { "type": "boolean", "description": "Published by default" },
            "promote": { "type": "boolean", "description": "Promoted to front page" },
            "sticky": { "type": "boolean", "description": "Sticky at top of lists" }
          }
        },
        "menu_settings": {
          "type": ["object", "null"],
          "properties": {
            "available_menus": {
              "type": "array",
              "items": { "type": "string" }
            },
            "parent": {
              "type": "string",
              "description": "Default parent menu link, e.g. 'main:'"
            }
          }
        },
        "language_settings": {
          "type": ["object", "null"],
          "properties": {
            "default_langcode": {
              "type": "string",
              "description": "Default language code or 'site_default' or 'current_interface'"
            },
            "language_alterable": {
              "type": "boolean",
              "description": "User can select language on node form"
            },
            "translation_enabled": {
              "type": "boolean"
            }
          }
        },
        "url_alias_pattern": {
          "type": ["string", "null"],
          "description": "Pathauto pattern, e.g. '/blog/[node:title]'"
        },
        "comment_settings": {
          "type": ["object", "null"],
          "properties": {
            "status": {
              "type": "integer",
              "enum": [0, 1, 2],
              "description": "0=hidden, 1=closed, 2=open"
            },
            "comment_type": {
              "type": "string"
            },
            "per_page": {
              "type": "integer"
            },
            "anonymous": {
              "type": "integer",
              "description": "0=not allowed, 1=allowed with contact info, 2=allowed"
            },
            "form_location": {
              "type": "boolean",
              "description": "true=below content, false=separate page"
            },
            "preview": {
              "type": "integer",
              "enum": [0, 1, 2],
              "description": "0=disabled, 1=optional, 2=required"
            }
          }
        },
        "fields": {
          "type": "object",
          "description": "Keyed by field machine name",
          "additionalProperties": {
            "$ref": "#/definitions/field_instance"
          }
        }
      }
    },
    "field_storage": {
      "type": "object",
      "required": ["field_name", "field_type", "cardinality"],
      "properties": {
        "field_name": {
          "type": "string"
        },
        "field_type": {
          "type": "string",
          "description": "D8+ machine name (e.g., entity_reference, text_with_summary)"
        },
        "d7_field_type": {
          "type": ["string", "null"],
          "description": "Original D7 type if different (e.g., taxonomy_term_reference)"
        },
        "entity_type": {
          "type": "string",
          "description": "The entity type this storage is for (usually 'node')"
        },
        "cardinality": {
          "type": "integer",
          "description": "1 = single value, -1 = unlimited, N = fixed max"
        },
        "translatable": {
          "type": "boolean"
        },
        "locked": {
          "type": "boolean"
        },
        "module": {
          "type": "string",
          "description": "Module providing this field type"
        },
        "settings": {
          "type": "object",
          "description": "Type-specific storage settings"
        },
        "bundles_using": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Which bundles attach this field (field reuse detection)"
        }
      }
    },
    "field_instance": {
      "type": "object",
      "required": ["field_name", "field_type", "label"],
      "properties": {
        "field_name": {
          "type": "string"
        },
        "field_type": {
          "type": "string"
        },
        "label": {
          "type": "string"
        },
        "description": {
          "type": ["string", "null"]
        },
        "required": {
          "type": "boolean"
        },
        "translatable": {
          "type": "boolean"
        },
        "cardinality": {
          "type": "integer",
          "description": "Copied from storage for convenience"
        },
        "default_value": {
          "description": "Default value(s), type varies by field"
        },
        "settings": {
          "type": "object",
          "description": "Instance-level settings (handler_settings, file_extensions, etc.)"
        },
        "widget": {
          "type": ["object", "null"],
          "description": "D7 only — widget info is in instance data. D8+ uses separate form display config.",
          "properties": {
            "type": { "type": "string" },
            "settings": { "type": "object" },
            "weight": { "type": "integer" },
            "module": { "type": "string" }
          }
        },
        "entity_reference_target": {
          "type": ["object", "null"],
          "description": "Present for entity_reference and entity_reference_revisions fields",
          "properties": {
            "target_entity_type": {
              "type": "string",
              "description": "e.g., taxonomy_term, node, media, paragraph, user"
            },
            "target_bundles": {
              "type": ["array", "null"],
              "items": { "type": "string" },
              "description": "Allowed bundles. null = all bundles."
            },
            "selection_handler": {
              "type": "string"
            },
            "auto_create": {
              "type": "boolean"
            }
          }
        },
        "file_settings": {
          "type": ["object", "null"],
          "description": "Present for file and image fields",
          "properties": {
            "file_directory": { "type": "string" },
            "file_extensions": { "type": "string" },
            "max_filesize": { "type": "string" },
            "alt_field": { "type": "boolean" },
            "alt_field_required": { "type": "boolean" },
            "title_field": { "type": "boolean" },
            "title_field_required": { "type": "boolean" },
            "max_resolution": { "type": "string" },
            "min_resolution": { "type": "string" },
            "default_image": {
              "type": ["object", "null"],
              "properties": {
                "uuid": { "type": "string" },
                "alt": { "type": "string" },
                "title": { "type": "string" }
              }
            }
          }
        },
        "text_settings": {
          "type": ["object", "null"],
          "description": "Present for formatted text fields",
          "properties": {
            "text_processing": { "type": "boolean" },
            "allowed_formats": {
              "type": ["array", "null"],
              "items": { "type": "string" }
            },
            "display_summary": { "type": "boolean" },
            "max_length": { "type": ["integer", "null"] }
          }
        },
        "link_settings": {
          "type": ["object", "null"],
          "description": "Present for link fields",
          "properties": {
            "link_type": {
              "type": "string",
              "enum": ["internal", "external", "both"]
            },
            "title_setting": {
              "type": "string",
              "enum": ["disabled", "optional", "required"]
            }
          }
        },
        "list_settings": {
          "type": ["object", "null"],
          "description": "Present for list_string, list_integer, list_float",
          "properties": {
            "allowed_values": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "key": {},
                  "label": { "type": "string" }
                }
              }
            },
            "allowed_values_function": {
              "type": ["string", "null"]
            }
          }
        },
        "date_settings": {
          "type": ["object", "null"],
          "description": "Present for datetime and daterange fields",
          "properties": {
            "datetime_type": {
              "type": "string",
              "enum": ["date", "datetime"],
              "description": "'date' = date only, 'datetime' = date + time"
            }
          }
        },
        "address_settings": {
          "type": ["object", "null"],
          "description": "Present for address fields",
          "properties": {
            "available_countries": {
              "type": "array",
              "items": { "type": "string" }
            },
            "field_overrides": {
              "type": "object",
              "description": "Per-property overrides: givenName, familyName, etc."
            },
            "langcode_override": {
              "type": ["string", "null"]
            }
          }
        },
        "number_settings": {
          "type": ["object", "null"],
          "description": "Present for integer, decimal, float fields",
          "properties": {
            "min": { "type": ["number", "null"] },
            "max": { "type": ["number", "null"] },
            "prefix": { "type": ["string", "null"] },
            "suffix": { "type": ["string", "null"] },
            "precision": { "type": ["integer", "null"] },
            "scale": { "type": ["integer", "null"] }
          }
        }
      }
    }
  }
}
```

---

## Agent Instructions

### Step 1: Detect Drupal version and access method

Check what you have access to. Try in this order:
1. Drush on the command line (`drush core:status`)
2. Config YAML files in the filesystem (`find . -name 'node.type.*.yml'`)
3. Database access (MySQL/MariaDB/PostgreSQL)
4. JSON:API endpoint (`curl https://example.com/jsonapi`)
5. Config export archive (`.tar.gz` from admin UI export)

### Step 2: Export content type definitions

**D8+ with drush:**
```bash
for ct in $(drush config:list --prefix=node.type --format=list); do
  drush config:get "$ct" --format=json
done
```

**D8+ from database:**
```sql
SELECT name, data FROM config WHERE name LIKE 'node.type.%';
```

**D7 from database:**
```sql
SELECT type, name, description, help, has_title, title_label,
       custom, modified, locked
FROM node_type WHERE disabled = 0;

SELECT name, value FROM variable
WHERE name LIKE 'node_options_%'
   OR name LIKE 'node_preview_%'
   OR name LIKE 'node_submitted_%'
   OR name LIKE 'comment_%'
   OR name LIKE 'menu_options_%'
   OR name LIKE 'menu_parent_%';
```

### Step 3: Export field storage definitions

**D8+ with drush:**
```bash
for fs in $(drush config:list --prefix=field.storage.node --format=list); do
  drush config:get "$fs" --format=json
done
```

**D7 from database:**
```sql
SELECT field_name, type, module, cardinality, translatable, locked, data
FROM field_config
WHERE active = 1 AND deleted = 0;
```

Deserialize the `data` column to get `settings`, `indexes`, and `foreign_keys`.

### Step 4: Export field instance definitions

**D8+ with drush:**
```bash
for fi in $(drush config:list --prefix=field.field.node --format=list); do
  drush config:get "$fi" --format=json
done
```

**D7 from database:**
```sql
SELECT fci.field_name, fci.entity_type, fci.bundle, fci.data,
       fc.type AS field_type, fc.cardinality, fc.data AS storage_data
FROM field_config_instance fci
JOIN field_config fc ON fc.id = fci.field_id
WHERE fci.entity_type = 'node'
  AND fci.deleted = 0
  AND fc.deleted = 0
  AND fc.active = 1;
```

### Step 5: Export supplementary config

Collect these additional configs that affect content types:

```bash
# Pathauto patterns
drush config:list --prefix=pathauto.pattern --format=list | \
  xargs -I{} drush config:get {} --format=json

# Language content settings
drush config:list --prefix=language.content_settings.node --format=list | \
  xargs -I{} drush config:get {} --format=json

# Comment type configurations
drush config:list --prefix=comment.type --format=list | \
  xargs -I{} drush config:get {} --format=json

# Content moderation (which types use which workflow)
drush config:list --prefix=workflows.workflow --format=list | \
  xargs -I{} drush config:get {} --format=json
```

### Step 6: Assemble and validate

1. Parse all collected data into the JSON schema above.
2. For each entity reference field, verify the target bundles exist.
3. For paragraph reference fields, recursively collect the paragraph type definitions and their fields. Use `field.field.paragraph.{type}.*` configs.
4. Flag any orphaned field storage (storage exists but no instances reference it).
5. Flag any fields using `allowed_values_function` instead of static values. These need code inspection.
6. Track field reuse: if `field.storage.node.field_tags` has instances on both `article` and `blog`, note that in `bundles_using`.
7. For D7: map old field type names to D8+ names using the translation table above.

### Step 7: Output

Write the assembled JSON to `content_types_fields.json` in the export directory. Print a summary:

```
Content types: 8
  - article (12 fields)
  - page (4 fields)
  - event (15 fields)
  - blog_post (9 fields)
  - landing_page (3 fields, 6 paragraph types via field_content)
  - news (11 fields)
  - person (8 fields)
  - resource (7 fields)

Field storage definitions: 34
Fields reused across bundles: 5
Entity reference fields: 12
Paragraph reference fields: 3
  - Paragraph types referenced: 14
Fields with dynamic allowed values: 1

Warnings:
  - field_legacy_ref uses allowed_values_function — inspect code
  - field_old_image has no instances (orphaned storage)
```

---

## Common Pitfalls

**Serialized PHP in D7.** The `data` columns in `field_config` and `field_config_instance` contain PHP `serialize()` output. Do not try to parse them as JSON. Use PHP's `unserialize()` or a language-specific library.

**Field reuse.** In D8+, a single `field.storage.node.field_tags` can back instances on multiple bundles. Each bundle gets its own `field.field.node.{bundle}.field_tags` with potentially different settings (required, label, allowed bundles). Always export both the storage and all its instances.

**Base fields vs configurable fields.** Base fields (title, status, uid, created, changed, promote, sticky) do not have `field.storage` or `field.field` config entries. They are defined in code via `baseFieldDefinitions()`. The export should note their existence but cannot extract their full config from YAML. Use `drush field:info node --bundle=article` (Drush 12+) to see all fields including base fields.

**Paragraph nesting depth.** Config does not record max nesting depth. A paragraph type `accordion` with a field referencing paragraph types `accordion_item` creates one level. If `accordion_item` itself references other paragraph types, that is another level. Follow the chain.

**D7 taxonomy_term_reference.** This field type stores the vocabulary name in `settings.allowed_values[0].vocabulary`. In D8+, taxonomy references are just `entity_reference` fields with `target_type: taxonomy_term` and `handler_settings.target_bundles` listing vocabulary machine names.

**Content First module.** If the site runs Drupal 9+ and has the `content_first` module installed, use `drush content-first:export-architecture` instead of manual extraction. It handles deduplication, human-readable type names, and reference following.
