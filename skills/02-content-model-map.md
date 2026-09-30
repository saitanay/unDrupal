# Skill 02: Content Model Map

Reverse-engineer the complete Drupal content model into a structured, portable JSON document. This document becomes the single source of truth for every downstream migration skill.

## Goal

Produce a `content-model.json` file containing every entity type, bundle, field definition, entity reference relationship, and field reuse pattern in the source Drupal site.

## Prerequisites

- Skill 01 (Site Inventory) completed. You know the Drupal version, installed modules, and available access methods.
- At least one access method confirmed: config export directory, Drush CLI, database access, or JSON:API endpoint.

## Access Methods (priority order)

Try each method in order. Stop at the first one that yields results. Fall back to the next if blocked.

### 1. Config Export YAML

The fastest, most complete source. Works for D8/D9/D10/D11.

Config exports live in one of these locations:
- `config/sync/` (default sync directory)
- `sites/default/files/config_*/sync/` (hash-based directory)
- A custom path set in `$settings['config_sync_directory']` in `settings.php`
- An exported tarball from `drush config:export`

Key file patterns:

| Pattern | Contains |
|---|---|
| `node.type.*.yml` | Content type definitions (machine name, label, description) |
| `field.storage.{entity_type}.*.yml` | Field storage: type, cardinality, translatable, settings, module |
| `field.field.{entity_type}.{bundle}.*.yml` | Field instance: label, description, required, default_value, settings (handler, target_bundles, allowed_values, file_extensions, max_filesize, text format) |
| `paragraphs.paragraphs_type.*.yml` | Paragraph type definitions (id, label, description, behavior_plugins) |
| `media.type.*.yml` | Media type definitions (id, label, source, source_configuration) |
| `taxonomy.vocabulary.*.yml` | Vocabulary definitions (vid, name, description) |
| `block_content.type.*.yml` | Block type definitions |
| `comment.type.*.yml` | Comment type definitions |
| `core.entity_form_display.*.*.default.yml` | Widget assignments per bundle |
| `core.entity_view_display.*.*.default.yml` | Formatter assignments per bundle |

#### Reading a field.storage YAML

```yaml
# field.storage.node.field_tags.yml
id: node.field_tags
field_name: field_tags
entity_type: node
type: entity_reference          # field type plugin ID
settings:
  target_type: taxonomy_term    # for entity_reference fields only
module: core
locked: false
cardinality: -1                 # -1 = unlimited, positive int = fixed
translatable: true
indexes: {}
persist_with_no_fields: false
custom_storage: false
```

Immutable properties after data exists: `id`, `field_name`, `entity_type`, `type`.

Storage is scoped to one entity type. The same `field_name` on `node` and `block_content` means two separate storages. Within one entity type, a single storage can be instanced across multiple bundles (field reuse).

#### Reading a field.field YAML (instance)

```yaml
# field.field.node.article.field_tags.yml
id: node.article.field_tags
field_name: field_tags
entity_type: node
bundle: article
label: Tags
description: 'Tag this content.'
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
      direction: ASC
    auto_create: true
    auto_create_bundle: tags
field_type: entity_reference
```

Instance-level settings vary by field type:

| Field type | Key instance settings |
|---|---|
| `entity_reference` | `handler`, `handler_settings.target_bundles`, `handler_settings.auto_create` |
| `entity_reference_revisions` | Same as entity_reference (used for Paragraphs) |
| `image` | `file_extensions`, `max_filesize`, `max_resolution`, `min_resolution`, `alt_field`, `alt_field_required`, `title_field`, `title_field_required`, `file_directory` |
| `file` | `file_extensions`, `max_filesize`, `file_directory`, `description_field` |
| `text`, `text_long`, `text_with_summary` | `allowed_formats` (D10.1+), display_summary (text_with_summary only) |
| `list_string`, `list_integer`, `list_float` | `allowed_values` (on storage, not instance) |
| `link` | `link_type` (LinkItemInterface constants), `title` (LINK_TITLE_DISABLED/OPTIONAL/REQUIRED) |
| `datetime` | `datetime_type` ('date' or 'datetime', on storage) |
| `daterange` | `datetime_type` (on storage) |

#### Extracting the model from YAML files

For each `field.storage.{entity_type}.*.yml`:

1. Parse `entity_type`, `field_name`, `type`, `cardinality`, `settings`, `translatable`, `module`.
2. For `entity_reference` and `entity_reference_revisions` types, record `settings.target_type`.

For each `field.field.{entity_type}.{bundle}.*.yml`:

1. Parse `bundle`, `label`, `description`, `required`, `default_value`, `settings`, `field_type`.
2. For reference fields, extract `settings.handler_settings.target_bundles`.
3. For file/image fields, extract `settings.file_extensions`, `settings.max_filesize`.
4. For list fields, the `allowed_values` live on the storage YAML under `settings.allowed_values`.

To detect field reuse: group all `field.field.*.*.{field_name}.yml` files that share the same `field_name` and `entity_type`. If more than one bundle appears, that field storage is reused.

### 2. Drush CLI

When config export files are not available but you have Drush access.

```bash
# List all content types
drush entity:type:list --filter=node

# List all field storages for an entity type
drush field:info --entity-type=node

# Export full config for one item
drush config:get field.storage.node.field_tags

# Export all config matching a pattern
drush config:list | grep '^field.storage.node' | while read name; do
  drush config:get "$name" --format=yaml > "export/$name.yml"
done

# List paragraph types
drush config:list | grep '^paragraphs.paragraphs_type'

# List media types
drush config:list | grep '^media.type'

# List taxonomy vocabularies
drush config:list | grep '^taxonomy.vocabulary'

# List block content types
drush config:list | grep '^block_content.type'

# Bulk export everything needed
drush config:export --destination=/tmp/config_export
```

For D9/D10/D11, `drush field:info` accepts `--entity-type` and `--bundle` filters. Parse its output into the same structure as the YAML approach.

### 3. Database Direct

When neither config export nor Drush is available. Works for D7 through D11.

#### D9/D10/D11 database

Config is serialized in the `config` table:

```sql
-- All content types
SELECT name, data FROM config WHERE name LIKE 'node.type.%';

-- All field storages for nodes
SELECT name, data FROM config WHERE name LIKE 'field.storage.node.%';

-- All field instances for nodes
SELECT name, data FROM config WHERE name LIKE 'field.field.node.%';

-- Paragraph types
SELECT name, data FROM config WHERE name LIKE 'paragraphs.paragraphs_type.%';

-- Media types
SELECT name, data FROM config WHERE name LIKE 'media.type.%';

-- Taxonomy vocabularies
SELECT name, data FROM config WHERE name LIKE 'taxonomy.vocabulary.%';
```

The `data` column contains PHP-serialized YAML. Deserialize with `unserialize()` in PHP or parse the blob in your language of choice.

#### D7 database

D7 stores field definitions in dedicated tables, not config YAML.

```sql
-- Field storage definitions
SELECT * FROM field_config;
-- Columns: id, field_name, type, module, active, storage_type,
--          storage_module, locked, data (serialized blob with
--          cardinality, settings, indexes, translatable), cardinality

-- Field instances
SELECT * FROM field_config_instance;
-- Columns: id, field_id, field_name, entity_type, bundle,
--          data (serialized blob with label, description, required,
--          default_value, settings, widget, display)

-- Content types
SELECT * FROM node_type;
-- Columns: type, name, description, module, locked
```

The `data` column in both `field_config` and `field_config_instance` is a PHP-serialized array. It contains the equivalent of what D9+ stores in YAML.

D7 field data tables follow this pattern:
- `field_data_{field_name}` (current values)
- `field_revision_{field_name}` (all revision values)

Both tables share columns: `entity_type`, `bundle`, `deleted`, `entity_id`, `revision_id`, `language`, `delta`, plus type-specific value columns named `{field_name}_{column}`.

D7 fields can span multiple entity types in a single storage table. D9+ restricts field storage to one entity type.

### 4. JSON:API

When you only have HTTP access to a running Drupal 8+ site with JSON:API enabled (core in D9+, contrib in D8).

```
# Discover all resource types
GET /jsonapi

# List nodes of a specific type
GET /jsonapi/node/article

# Inspect field structure from any response
# Fields appear under data.attributes (scalar) and data.relationships (references)
```

JSON:API does not expose field storage config directly. You can infer field names and rough types from response payloads, but you cannot determine cardinality, allowed values, or handler settings. Use this method only as a last resort to discover which fields exist. Combine with other methods for full metadata.

## Drupal Field Types Reference

### Core field types (D9/D10/D11)

| Machine name | Label | Module | Notes |
|---|---|---|---|
| `boolean` | Boolean | core | |
| `changed` | Last changed | core | Base field, UNIX timestamp |
| `created` | Created | core | Base field, UNIX timestamp |
| `comment` | Comments | comment | |
| `datetime` | Date | datetime | Storage setting: `datetime_type` = 'date' or 'datetime' |
| `daterange` | Date range | datetime_range | Start + end date |
| `decimal` | Number (decimal) | core | Fixed precision |
| `email` | Email | core | |
| `entity_reference` | Entity reference | core | `settings.target_type` on storage |
| `entity_reference_revisions` | Entity reference revisions | entity_reference_revisions (contrib) | Used by Paragraphs |
| `file` | File | file | |
| `float` | Number (float) | core | |
| `image` | Image | image | Extends file, adds alt/title/width/height |
| `integer` | Number (integer) | core | |
| `language` | Language | core | Base field |
| `link` | Link | link | URI + title + attributes |
| `list_float` | List (float) | options | `settings.allowed_values` on storage |
| `list_integer` | List (integer) | options | `settings.allowed_values` on storage |
| `list_string` | List (text) | options | `settings.allowed_values` on storage |
| `map` | Map | core | Serialized array, no schema |
| `path` | Path | path | Base field |
| `string` | Text (plain) | core | Max 255 chars |
| `string_long` | Text (plain, long) | core | No length limit |
| `telephone` | Telephone | telephone | |
| `text` | Text (formatted) | text | With text format, max 255 chars |
| `text_long` | Text (formatted, long) | text | No length limit |
| `text_with_summary` | Text (formatted, long, with summary) | text | Body field default |
| `timestamp` | Timestamp | core | UNIX integer |
| `uri` | URI | core | |
| `uuid` | UUID | core | Base field |

### Common contrib field types

| Machine name | Module | Notes |
|---|---|---|
| `address` | address | Country, admin area, locality, postal code, address lines |
| `geolocation` | geolocation | Lat/lng pair |
| `office_hours` | office_hours | Weekly schedule |
| `color_field` | color_field | Hex color + opacity |
| `viewsreference` | viewsreference | Reference to a View display |
| `custom` | custom_field | Compound field with configurable columns |
| `metatag` | metatag | Serialized metatag values |
| `double_field` | double_field | Two sub-values in one field |
| `tablefield` | tablefield | Table data in serialized format |
| `yearonly` | yearonly | Year integer |

### D7 field types that changed in D9+

| D7 type | D9+ equivalent | Notes |
|---|---|---|
| `text` | `string` or `text` | D7 `text` with no format becomes `string` |
| `text_long` | `string_long` or `text_long` | Depends on whether text format was used |
| `text_with_summary` | `text_with_summary` | Same |
| `number_integer` | `integer` | Renamed |
| `number_decimal` | `decimal` | Renamed |
| `number_float` | `float` | Renamed |
| `taxonomy_term_reference` | `entity_reference` | `target_type: taxonomy_term` |
| `node_reference` (CCK/References) | `entity_reference` | `target_type: node` |
| `user_reference` (CCK/References) | `entity_reference` | `target_type: user` |
| `entityreference` | `entity_reference` | Same concept, different plugin ID |
| `file` | `file` | Column `fid` became `target_id` |
| `image` | `image` | Column `fid` became `target_id` |
| `link_field` | `link` | Different settings structure |
| `datestamp` | `timestamp` | |
| `datetime` | `datetime` | Different storage format (ISO 8601 vs custom) |
| `date` | `datetime` | Was ISO string, remains ISO string |
| `field_collection` | `entity_reference_revisions` (Paragraphs) | Complete architectural change |

## Entity Types to Inventory

Check for all of these. Not every site uses all of them. Record which ones exist and their bundles.

| Entity type ID | Config prefix for bundles | Database tables (D9+) | Common? |
|---|---|---|---|
| `node` | `node.type.*` | `node`, `node_field_data`, `node_field_revision` | Always |
| `taxonomy_term` | `taxonomy.vocabulary.*` | `taxonomy_term_data`, `taxonomy_term_field_data`, `taxonomy_term__parent` | Almost always |
| `media` | `media.type.*` | `media`, `media_field_data`, `media_field_revision` | D8.5+ |
| `paragraph` | `paragraphs.paragraphs_type.*` | `paragraphs_item`, `paragraphs_item_field_data`, `paragraphs_item_revision`, `paragraphs_item_revision_field_data` | Common (contrib) |
| `block_content` | `block_content.type.*` | `block_content`, `block_content_field_data` | Common |
| `user` | (single bundle: `user`) | `users`, `users_field_data` | Always |
| `comment` | `comment.type.*` | `comment`, `comment_field_data` | Common |
| `file` | (no bundles) | `file_managed` | Always |
| `menu_link_content` | (single bundle: `menu_link_content`) | `menu_link_content_data` | Always |
| `redirect` | (no bundles) | `redirect` | Common (contrib) |
| `webform_submission` | (per-webform, not config entity bundles) | `webform_submission`, `webform_submission_data` | Common (contrib) |
| `commerce_product` | `commerce_product.commerce_product_type.*` | `commerce_product`, `commerce_product_field_data` | Commerce sites |
| `commerce_product_variation` | `commerce_product.commerce_product_variation_type.*` | `commerce_product_variation` | Commerce sites |
| `commerce_order` | `commerce_order.commerce_order_type.*` | `commerce_order` | Commerce sites |
| `commerce_order_item` | `commerce_order.commerce_order_item_type.*` | `commerce_order_item` | Commerce sites |
| `crop` | `crop.type.*` | `crop`, `crop_field_data` | With media (contrib) |

## Base Fields vs Configurable Fields

Every entity type has base fields defined in code. These are not stored in `field.storage.*.yml` or `field.field.*.yml`. They appear in the entity's `baseFieldDefinitions()` method.

Common base fields for `node`:
- `nid`, `uuid`, `vid`, `langcode`, `type`, `revision_timestamp`, `revision_uid`, `revision_log`, `status`, `uid`, `title`, `created`, `changed`, `promote`, `sticky`, `default_langcode`, `revision_default`, `revision_translation_affected`, `path`

Common base fields for `taxonomy_term`:
- `tid`, `uuid`, `vid`, `langcode`, `revision_id`, `name`, `description`, `weight`, `changed`, `default_langcode`, `parent`, `status`, `revision_default`

Common base fields for `paragraph`:
- `id`, `uuid`, `revision_id`, `langcode`, `type`, `status`, `parent_id`, `parent_type`, `parent_field_name`, `behavior_settings`, `created`, `default_langcode`, `revision_default`

Common base fields for `media`:
- `mid`, `uuid`, `vid`, `langcode`, `bundle`, `revision_created`, `revision_user`, `revision_log_message`, `status`, `uid`, `name`, `thumbnail`, `created`, `changed`, `default_langcode`, `revision_default`

Do not confuse base fields with configurable fields. Base fields are not in the config export. They travel with the code. Include them in the model output so downstream skills know the full picture, but mark them as `"base_field": true`.

## Paragraph Architecture

Paragraphs are content entities (`paragraph`) with bundles defined by `paragraphs_type` config entities. They are referenced from parent entities through `entity_reference_revisions` fields.

Key properties:
- Each paragraph stores `parent_id`, `parent_type`, `parent_field_name` as base fields. These track which entity and field owns the paragraph.
- Paragraphs can nest. A paragraph type can have an `entity_reference_revisions` field targeting other paragraph types.
- Paragraphs are revision-tracked. The parent holds a revision ID reference, not just an entity ID.
- Paragraph types have `behavior_plugins` for layout, style, and other behavioral configuration.

To extract paragraph architecture:
1. List all `paragraphs.paragraphs_type.*.yml` files for type definitions.
2. List all `field.storage.paragraph.*.yml` for fields on paragraph types.
3. List all `field.field.paragraph.{type}.*.yml` for per-type field instances.
4. Identify nesting: any `entity_reference_revisions` field on a paragraph type that targets `paragraph`.

## Field Collections (D7)

Field collections are the D7 predecessor to Paragraphs. The `field_collection` module creates a `field_collection_item` entity type where each bundle corresponds to a field collection field on a host entity.

### Storage layout

Three table groups hold field collection data:

1. `field_collection_item` table stores the entity itself (item_id, revision_id, field_name, archived).
2. `field_data_field_{collection_field_name}` on the host entity stores the reference from parent to collection item. The value column is `field_{name}_value` holding the `item_id`, plus `field_{name}_revision_id`.
3. `field_data_field_*` tables for each field attached to the collection item store the actual field values, with `entity_type` = `field_collection_item`.

### Host entity relationship

Every field collection item is owned by a single parent entity. The `field_name` column on `field_collection_item` records which field on the host entity holds the reference. Unlike Paragraphs, which track `parent_id`, `parent_type`, and `parent_field_name` as base fields, field collections rely on the `field_name` column plus the host entity's reference field to establish ownership.

### Nesting

Field collections support one level of nesting in practice. A field collection item can technically host another field collection field, but the module does not handle deep nesting well. Most sites keep field collections flat.

### Detection

To confirm a D7 site uses field collections:

```sql
-- Check for the module
SELECT name, status FROM system WHERE name = 'field_collection';

-- Find all field collection fields
SELECT id, field_name, type FROM field_config WHERE type = 'field_collection';

-- List all field collection bundles (each bundle name matches a field name)
SELECT DISTINCT field_name FROM field_collection_item;
```

Also check for `field_collection` in the module list from Skill 01.

### Migration path

Field collections map to Paragraphs in D9+. Each field collection bundle becomes a paragraph type. Each field on the collection item becomes a field on the paragraph type. The host entity's field collection reference field becomes an `entity_reference_revisions` field targeting the new paragraph types. Record field collections in the content model with `"d9_equivalent": "paragraph"` so downstream skills know the conversion target.

## Layout Paragraphs

The `layout_paragraphs` module extends standard Paragraphs with layout capabilities. A single `entity_reference_revisions` field becomes a page-building tool where paragraphs serve as both layout containers and content components.

### How it works

Each paragraph in a layout_paragraphs field has one of two roles:

- **Layout**: a container paragraph that defines a layout (e.g., `layout_twocol`, `layout_threecol_section`) and exposes named regions.
- **Component**: a content paragraph placed inside a specific region of a layout paragraph.

The module stores layout metadata in the `behavior_settings` base field on each paragraph entity. This is the same field used by other paragraph behavior plugins, stored as a serialized JSON blob.

### Behavior settings structure

For a layout paragraph:
```json
{
  "layout_paragraphs": {
    "layout": "layout_twocol",
    "config": {
      "label": "",
      "column_widths": "50-50"
    }
  }
}
```

For a component paragraph placed in a layout:
```json
{
  "layout_paragraphs": {
    "parent_uuid": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
    "region": "first"
  }
}
```

`parent_uuid` links the component to its layout paragraph. `region` specifies which region of the layout holds the component. Paragraphs without a `parent_uuid` in their behavior settings are top-level items (either layouts or standalone components).

### Detection

Check for the module in config or the database:

```yaml
# In core.extension.yml
module:
  layout_paragraphs: 0
```

Check `paragraphs.paragraphs_type.*.yml` for behavior plugin references:
```yaml
behavior_plugins:
  layout_paragraphs: {}
```

### Difference from standard Paragraphs

Standard Paragraphs store content data only. Layout Paragraphs adds spatial information: which layout template wraps a group of paragraphs, and which region each paragraph occupies. The content model map must capture both the paragraph type definitions (content structure) and the layout behavior settings (spatial structure). Record layout-enabled paragraph types with `"layout_paragraphs": true` in the bundle definition.

### Extracting layout data

1. List paragraph types with `layout_paragraphs` in their `behavior_plugins`.
2. For each `entity_reference_revisions` field that targets paragraph types, check whether any of the allowed types are layout-enabled.
3. In the content model output, annotate those fields with `"uses_layout_paragraphs": true`.
4. Record which layout plugins are in use by scanning `behavior_settings` values in the `paragraphs_item_field_data` table or by checking available layouts in `core.extension.yml` (e.g., `layout_discovery`, `layout_builder` providing layout definitions).

## Content Builder Detection

A single content type can use multiple content building approaches on different fields. One content type might use Paragraphs for a `field_sections` field, Gutenberg for the `body` field, and Layout Builder for page-level layout. Field collections (D7) can coexist with other field types on the same entity.

The content model map must record which building approach each field uses. During extraction:

1. For each `entity_reference_revisions` field targeting paragraphs, check whether the referenced types use layout_paragraphs behavior. Record `"content_builder": "layout_paragraphs"` or `"content_builder": "paragraphs"` on the field.
2. For `text_long` or `text_with_summary` fields, check whether the Gutenberg module is active and whether the field's widget is `gutenberg_text_widget` (in `core.entity_form_display.*.yml`). Record `"content_builder": "gutenberg"` if so.
3. For Layout Builder usage, check `core.entity_view_display.{entity_type}.{bundle}.default.yml` for `third_party_settings.layout_builder.enabled: true`. This is a display-level setting, not a field-level one. Record `"layout_builder_enabled": true` on the bundle.
4. For D7 field collection fields (`type: field_collection` in `field_config`), record `"content_builder": "field_collection"` on the field.

This per-field annotation gives downstream skills the information they need to choose the right migration strategy for each piece of content.

## Media Architecture

Media entities wrap file assets with structured metadata. Each media type has a source plugin that determines the primary asset field.

In `media.type.*.yml`:
```yaml
id: image
label: Image
source: image                    # source plugin ID
source_configuration:
  source_field: field_media_image  # the field that holds the actual file/value
```

Common source plugins: `image`, `file`, `video_file`, `audio_file`, `oembed:video`.

To extract media architecture:
1. List all `media.type.*.yml` for type definitions and source field mappings.
2. List all `field.storage.media.*.yml` for media field storages.
3. List all `field.field.media.{type}.*.yml` for per-type field instances.
4. Record the `source_configuration.source_field` as the primary field for each media type.

## Entity Reference Graph

Build a directed graph of entity relationships. For every `entity_reference` or `entity_reference_revisions` field:

1. Source: `{entity_type}.{bundle}`
2. Target: `{target_type}.{target_bundle}` (for each bundle in `handler_settings.target_bundles`)
3. Field: `field_name`
4. Cardinality: from storage
5. Required: from instance

This graph reveals:
- Which content types reference which taxonomy vocabularies.
- Which nodes reference other nodes (and of which types).
- Which entities use paragraphs, and which paragraph types they allow.
- Which entities reference media, and which media types they allow.
- Circular references (node A references node B which references node A).

## Taxonomy Usage Map

For each vocabulary, find every field instance that references it:

1. Scan all `field.field.*.*.*.yml` where `field_type` is `entity_reference`.
2. Check `settings.handler_settings.target_bundles` for the vocabulary machine name.
3. Record the `entity_type`, `bundle`, `field_name`, and `cardinality`.

This produces a vocabulary-to-usage map showing which content types use each vocabulary and through which fields.

## Field Reuse Detection

A field is reused when a single `field.storage.{entity_type}.{field_name}` has multiple `field.field.{entity_type}.{bundle_a}.{field_name}` and `field.field.{entity_type}.{bundle_b}.{field_name}` instances.

To detect:
1. Group all field instance files by `entity_type` + `field_name`.
2. Any group with more than one bundle entry is a reused field.
3. Record the list of bundles sharing each storage.

Reused fields share cardinality, type, and storage settings. Instance settings (label, description, required, handler_settings, file_extensions) can differ per bundle.

## Procedure

### Step 1: Identify access method

Check for config export directory, Drush access, database access, JSON:API in that order. Use the first available.

### Step 2: Enumerate entity types

Collect every entity type that has bundles or field attachments. Use the entity types table above as a checklist. For each entity type found, list all bundles.

### Step 3: Extract field storages

For each entity type, collect all field storage definitions. Record: `field_name`, `type`, `cardinality`, `settings`, `translatable`, `module`, `locked`.

### Step 4: Extract field instances

For each entity type + bundle combination, collect all field instance definitions. Record: `field_name`, `label`, `description`, `required`, `default_value`, `settings`, `field_type`.

### Step 5: Extract bundle definitions

For each bundle, collect its definition. Record: `id`, `label`, `description`, plus any type-specific properties (e.g., `source` and `source_configuration` for media types).

### Step 6: Build reference graph

Walk every entity_reference and entity_reference_revisions field. Build edges from source entity+bundle to target entity+bundle(s).

### Step 7: Build taxonomy usage map

Invert the reference graph for taxonomy_term targets. Group by vocabulary.

### Step 8: Detect field reuse

Group field instances by entity_type + field_name. Flag groups with multiple bundles.

### Step 9: Identify base fields

For each entity type, list the known base fields. Mark them separately from configurable fields.

### Step 10: Write content-model.json

Assemble all collected data into the output schema below.

## Output Schema

Write `content-model.json` to the project root. The file must validate against this structure:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Drupal Content Model",
  "type": "object",
  "required": ["meta", "entity_types"],
  "properties": {
    "meta": {
      "type": "object",
      "required": ["drupal_version", "extracted_at", "access_method"],
      "properties": {
        "drupal_version": {
          "type": "string",
          "description": "Major Drupal version, e.g. '10' or '7'"
        },
        "extracted_at": {
          "type": "string",
          "format": "date-time"
        },
        "access_method": {
          "type": "string",
          "enum": ["config_yaml", "drush", "database", "jsonapi"]
        },
        "site_name": { "type": "string" },
        "site_uuid": { "type": "string" }
      }
    },
    "entity_types": {
      "type": "object",
      "description": "Keyed by entity type ID",
      "additionalProperties": {
        "type": "object",
        "required": ["label", "bundles"],
        "properties": {
          "label": { "type": "string" },
          "provider": {
            "type": "string",
            "description": "Module providing this entity type"
          },
          "base_fields": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["field_name", "type", "label"],
              "properties": {
                "field_name": { "type": "string" },
                "type": { "type": "string" },
                "label": { "type": "string" },
                "required": { "type": "boolean" },
                "translatable": { "type": "boolean" },
                "revisionable": { "type": "boolean" }
              }
            }
          },
          "bundles": {
            "type": "object",
            "description": "Keyed by bundle machine name",
            "additionalProperties": {
              "type": "object",
              "required": ["label", "fields"],
              "properties": {
                "label": { "type": "string" },
                "description": { "type": "string" },
                "source_plugin": {
                  "type": "string",
                  "description": "Media type source plugin ID"
                },
                "source_field": {
                  "type": "string",
                  "description": "Media type source field name"
                },
                "behavior_plugins": {
                  "type": "object",
                  "description": "Paragraph type behavior plugin config"
                },
                "fields": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "required": ["field_name", "field_type", "label", "cardinality"],
                    "properties": {
                      "field_name": { "type": "string" },
                      "field_type": { "type": "string" },
                      "label": { "type": "string" },
                      "description": { "type": "string" },
                      "cardinality": {
                        "type": "integer",
                        "description": "-1 for unlimited"
                      },
                      "required": { "type": "boolean" },
                      "translatable": { "type": "boolean" },
                      "base_field": {
                        "type": "boolean",
                        "description": "true if this is a base field, not configurable"
                      },
                      "default_value": {},
                      "module": {
                        "type": "string",
                        "description": "Module providing the field type"
                      },
                      "storage_settings": {
                        "type": "object",
                        "description": "Raw settings from field.storage YAML"
                      },
                      "instance_settings": {
                        "type": "object",
                        "description": "Raw settings from field.field YAML"
                      },
                      "reused_in_bundles": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Other bundles sharing this field storage"
                      },
                      "target_type": {
                        "type": "string",
                        "description": "For entity_reference fields: target entity type"
                      },
                      "target_bundles": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "For entity_reference fields: allowed target bundles"
                      },
                      "allowed_values": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "properties": {
                            "value": { "type": "string" },
                            "label": { "type": "string" }
                          }
                        },
                        "description": "For list fields: allowed value/label pairs"
                      },
                      "file_extensions": {
                        "type": "string",
                        "description": "For file/image fields: space-separated extensions"
                      },
                      "max_filesize": {
                        "type": "string",
                        "description": "For file/image fields: e.g. '2 MB'"
                      },
                      "text_format_restrictions": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "For formatted text fields: allowed format machine names"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "reference_graph": {
      "type": "array",
      "description": "Directed edges between entity bundles",
      "items": {
        "type": "object",
        "required": ["source_entity_type", "source_bundle", "field_name", "target_entity_type"],
        "properties": {
          "source_entity_type": { "type": "string" },
          "source_bundle": { "type": "string" },
          "field_name": { "type": "string" },
          "field_type": { "type": "string" },
          "cardinality": { "type": "integer" },
          "required": { "type": "boolean" },
          "target_entity_type": { "type": "string" },
          "target_bundles": {
            "type": "array",
            "items": { "type": "string" }
          }
        }
      }
    },
    "taxonomy_usage_map": {
      "type": "object",
      "description": "Keyed by vocabulary machine name",
      "additionalProperties": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "entity_type": { "type": "string" },
            "bundle": { "type": "string" },
            "field_name": { "type": "string" },
            "cardinality": { "type": "integer" },
            "required": { "type": "boolean" }
          }
        }
      }
    },
    "field_reuse_map": {
      "type": "object",
      "description": "Keyed by '{entity_type}.{field_name}'",
      "additionalProperties": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Bundle machine names sharing this storage"
      }
    }
  }
}
```

## Example Output Fragment

```json
{
  "meta": {
    "drupal_version": "10",
    "extracted_at": "2025-01-15T14:30:00Z",
    "access_method": "config_yaml",
    "site_name": "Example Corp",
    "site_uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "entity_types": {
    "node": {
      "label": "Content",
      "provider": "node",
      "bundles": {
        "article": {
          "label": "Article",
          "description": "Use articles for time-sensitive content.",
          "fields": [
            {
              "field_name": "field_tags",
              "field_type": "entity_reference",
              "label": "Tags",
              "cardinality": -1,
              "required": false,
              "translatable": false,
              "module": "core",
              "target_type": "taxonomy_term",
              "target_bundles": ["tags"],
              "reused_in_bundles": ["page"],
              "storage_settings": {
                "target_type": "taxonomy_term"
              },
              "instance_settings": {
                "handler": "default:taxonomy_term",
                "handler_settings": {
                  "target_bundles": { "tags": "tags" },
                  "auto_create": true
                }
              }
            },
            {
              "field_name": "field_image",
              "field_type": "image",
              "label": "Image",
              "cardinality": 1,
              "required": false,
              "translatable": false,
              "module": "image",
              "file_extensions": "png gif jpg jpeg webp",
              "max_filesize": "2 MB",
              "storage_settings": {},
              "instance_settings": {
                "file_extensions": "png gif jpg jpeg webp",
                "max_filesize": "2 MB",
                "alt_field": true,
                "alt_field_required": true,
                "title_field": false,
                "file_directory": "article-images"
              }
            }
          ]
        }
      }
    },
    "paragraph": {
      "label": "Paragraph",
      "provider": "paragraphs",
      "bundles": {
        "text_block": {
          "label": "Text Block",
          "description": "A rich text paragraph.",
          "behavior_plugins": {},
          "fields": [
            {
              "field_name": "field_body",
              "field_type": "text_long",
              "label": "Body",
              "cardinality": 1,
              "required": true,
              "translatable": true,
              "module": "text"
            }
          ]
        }
      }
    }
  },
  "reference_graph": [
    {
      "source_entity_type": "node",
      "source_bundle": "article",
      "field_name": "field_tags",
      "field_type": "entity_reference",
      "cardinality": -1,
      "required": false,
      "target_entity_type": "taxonomy_term",
      "target_bundles": ["tags"]
    },
    {
      "source_entity_type": "node",
      "source_bundle": "article",
      "field_name": "field_content",
      "field_type": "entity_reference_revisions",
      "cardinality": -1,
      "required": false,
      "target_entity_type": "paragraph",
      "target_bundles": ["text_block", "image_block"]
    }
  ],
  "taxonomy_usage_map": {
    "tags": [
      {
        "entity_type": "node",
        "bundle": "article",
        "field_name": "field_tags",
        "cardinality": -1,
        "required": false
      }
    ]
  },
  "field_reuse_map": {
    "node.field_tags": ["article", "page"]
  }
}
```

## Validation Checklist

Run these checks after generating the output:

- [ ] Every `field.storage` has at least one corresponding `field.field` instance (or it is orphaned; flag it).
- [ ] Every `entity_reference` field has a `target_type` in storage settings.
- [ ] Every `entity_reference` field instance has `handler_settings.target_bundles` (empty means "all bundles"; record that).
- [ ] Every paragraph type referenced in `target_bundles` exists in `entity_types.paragraph.bundles`.
- [ ] Every media type referenced in `target_bundles` exists in `entity_types.media.bundles`.
- [ ] Every vocabulary referenced in `target_bundles` exists in `entity_types.taxonomy_term.bundles`.
- [ ] `reference_graph` contains one edge per reference field instance.
- [ ] `field_reuse_map` entries match the count of unique bundles per storage.
- [ ] No `field_name` exceeds 32 characters.
- [ ] Cardinality is either -1 or a positive integer for every field.
- [ ] For D7 sources: field type names are recorded as D7 names, with a `d9_equivalent` annotation.

## Error Handling

| Situation | Action |
|---|---|
| Config export directory is empty or missing | Fall back to Drush |
| Drush not available or returns errors | Fall back to database |
| Database access denied | Fall back to JSON:API |
| JSON:API disabled | Report failure; list what could not be extracted |
| PHP serialized data in database cannot be parsed | Use a PHP one-liner: `php -r "print_r(unserialize(file_get_contents('php://stdin')));"` with piped input |
| Unknown field type found | Record it as-is with `"type": "unknown:{raw_type}"`. Flag for manual review. |
| Orphaned field storage (no instances) | Include in output with `"orphaned": true` |
| Field instance references nonexistent bundle | Include with `"bundle_missing": true`. This signals a broken config. |
