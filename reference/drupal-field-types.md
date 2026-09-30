# Drupal Field Types and Storage Patterns

Every configurable field in Drupal gets dedicated database tables. This reference covers every field type, its storage columns, and the table naming pattern.

## Table Naming

```
{entity_type}__field_{name}              -- current values
{entity_type}_revision__field_{name}     -- revision history
```

Every field table includes these standard columns before the value columns:

| Column | Type | Notes |
|--------|------|-------|
| `bundle` | varchar(128) | Entity bundle machine name |
| `deleted` | tinyint | 0 = active, 1 = pending purge |
| `entity_id` | int unsigned | FK to entity base table |
| `revision_id` | int unsigned | FK to entity revision table |
| `langcode` | varchar(32) | Translation language |
| `delta` | int unsigned | Multi-value index (0-based) |

## Text Fields

### string

Short plain text. No text format. Max 255 chars by default.

| Column | Type |
|--------|------|
| `field_{name}_value` | varchar(255) |

### string_long

Long plain text. No text format. No length limit.

| Column | Type |
|--------|------|
| `field_{name}_value` | longtext |

### text

Short formatted text. Max 255 chars with text format.

| Column | Type |
|--------|------|
| `field_{name}_value` | varchar(255) |
| `field_{name}_format` | varchar(255) |

### text_long

Long formatted text with text format.

| Column | Type |
|--------|------|
| `field_{name}_value` | longtext |
| `field_{name}_format` | varchar(255) |

### text_with_summary

Long formatted text with optional summary. Used by the default `body` field.

| Column | Type |
|--------|------|
| `field_{name}_value` | longtext |
| `field_{name}_summary` | longtext |
| `field_{name}_format` | varchar(255) |

Note: The `body` field is a special case. Its columns are `body_value`, `body_summary`, `body_format` (no `field_` prefix on column names). The table is still named `node__body`.

## Numeric Fields

### integer

| Column | Type |
|--------|------|
| `field_{name}_value` | int |

### float

| Column | Type |
|--------|------|
| `field_{name}_value` | float |

### decimal

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | numeric(precision, scale) | Default precision 10, scale 2 |

### list_integer

Integer from a predefined allowed values list.

| Column | Type |
|--------|------|
| `field_{name}_value` | int |

### list_float

Float from a predefined allowed values list.

| Column | Type |
|--------|------|
| `field_{name}_value` | float |

## Boolean

### boolean

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | tinyint | 0 or 1 |

## Date and Time Fields

### datetime

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | varchar(20) | ISO 8601 format: `2024-01-15T14:30:00` (date + time) or `2024-01-15` (date only). Stored in UTC. |

### daterange

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | varchar(20) | Start date, same format as datetime |
| `field_{name}_end_value` | varchar(20) | End date |

### timestamp

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | int | Unix timestamp |

### smartdate (Smart Date contrib)

| Column | Type |
|--------|------|
| `field_{name}_value` | int |
| `field_{name}_end_value` | int |
| `field_{name}_duration` | int |
| `field_{name}_rrule` | int |
| `field_{name}_rrule_index` | int |
| `field_{name}_timezone` | varchar(32) |

## Reference Fields

### entity_reference

References another entity by ID. Used for taxonomy terms, users, nodes, media, and any other entity type.

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_target_id` | int unsigned | FK to referenced entity's base table PK |

The referenced entity type is defined in field storage config, not in the table itself. Query the `field.storage.{entity_type}.{field_name}` config to find the target type.

### entity_reference_revisions

References a specific entity revision. Used by Paragraphs.

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_target_id` | int unsigned | FK to referenced entity's base table PK |
| `field_{name}_target_revision_id` | int unsigned | FK to referenced entity's revision table PK |

## File and Image Fields

### file

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_target_id` | int unsigned | FK to `file_managed.fid` |
| `field_{name}_display` | tinyint | Whether to show in listings |
| `field_{name}_description` | text | User-entered file description |

### image

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_target_id` | int unsigned | FK to `file_managed.fid` |
| `field_{name}_alt` | varchar(512) | Alt text |
| `field_{name}_title` | varchar(1024) | Title attribute |
| `field_{name}_width` | int unsigned | Pixel width |
| `field_{name}_height` | int unsigned | Pixel height |

## Link Field

### link

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_uri` | varchar(2048) | URI value. Internal links stored as `internal:/node/123` or `entity:node/123`. External links stored as full URL. `<front>` for homepage. |
| `field_{name}_title` | varchar(255) | Link text |
| `field_{name}_options` | longblob | Serialized PHP array. Attributes like `target`, `class`, `rel`. |

### Parsing link URIs

```python
uri = row['field_link_uri']
if uri.startswith('entity:'):
    # entity:node/123 -> /node/123
    entity_path = uri[7:]  # "node/123"
    entity_type, entity_id = entity_path.split('/')
elif uri.startswith('internal:'):
    # internal:/about-us -> /about-us
    path = uri[9:]
elif uri.startswith('route:'):
    # route:<front> -> /
    route = uri[6:]
else:
    # External URL, use as-is
    url = uri
```

## Contact Fields

### email

| Column | Type |
|--------|------|
| `field_{name}_value` | varchar(254) |

### telephone

| Column | Type |
|--------|------|
| `field_{name}_value` | varchar(256) |

## List Fields

### list_string

String from a predefined allowed values list. Dropdown, radios, checkboxes.

| Column | Type |
|--------|------|
| `field_{name}_value` | varchar(255) |

The allowed values are defined in field storage config:

```yaml
# field.storage.node.field_color
settings:
  allowed_values:
    - value: red
      label: Red
    - value: blue
      label: Blue
    - value: green
      label: Green
```

## Address Field (Address module)

### address

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_langcode` | varchar(12) | Address language |
| `field_{name}_country_code` | varchar(2) | ISO 3166-1 alpha-2 |
| `field_{name}_administrative_area` | varchar(255) | State/province code |
| `field_{name}_locality` | varchar(255) | City |
| `field_{name}_dependent_locality` | varchar(255) | District/suburb |
| `field_{name}_postal_code` | varchar(255) | ZIP/postal code |
| `field_{name}_sorting_code` | varchar(255) | Sorting code (country-specific) |
| `field_{name}_address_line1` | varchar(255) | Street address line 1 |
| `field_{name}_address_line2` | varchar(255) | Street address line 2 |
| `field_{name}_organization` | varchar(255) | Company name |
| `field_{name}_given_name` | varchar(255) | First name |
| `field_{name}_additional_name` | varchar(255) | Middle name |
| `field_{name}_family_name` | varchar(255) | Last name |

## Geolocation Fields

### geofield (Geofield module)

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | longtext | WKT (Well-Known Text), e.g. `POINT(-73.935242 40.730610)` |
| `field_{name}_geo_type` | varchar(64) | `Point`, `LineString`, `Polygon`, etc. |
| `field_{name}_lat` | float | Latitude (decimal degrees) |
| `field_{name}_lon` | float | Longitude (decimal degrees) |
| `field_{name}_left` | float | Bounding box left |
| `field_{name}_top` | float | Bounding box top |
| `field_{name}_right` | float | Bounding box right |
| `field_{name}_bottom` | float | Bounding box bottom |
| `field_{name}_geohash` | varchar(16) | Geohash string |

### geolocation (Geolocation module)

Simpler than geofield. Stores a single lat/lng pair.

| Column | Type |
|--------|------|
| `field_{name}_lat` | float |
| `field_{name}_lng` | float |
| `field_{name}_lat_sin` | float |
| `field_{name}_lat_cos` | float |
| `field_{name}_lng_rad` | float |
| `field_{name}_data` | longtext |

## Color Field (Color Field module)

### color_field

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_color` | varchar(7) | Hex color, e.g. `#FF5733` |
| `field_{name}_opacity` | float | 0.0 to 1.0 |

## Viewsreference Field (Viewsreference module)

### viewsreference

| Column | Type |
|--------|------|
| `field_{name}_target_id` | varchar(255) |
| `field_{name}_display_id` | varchar(255) |
| `field_{name}_argument` | varchar(255) |
| `field_{name}_title` | tinyint |
| `field_{name}_data` | text |

## Office Hours (Office Hours module)

### office_hours

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_day` | int | 0=Sunday through 6=Saturday |
| `field_{name}_starthours` | int | Start time as integer (e.g. 900 = 9:00) |
| `field_{name}_endhours` | int | End time as integer |
| `field_{name}_comment` | varchar(255) | Optional comment |

## Metatag (Metatag module)

### metatag

Stored as a serialized blob in a single column.

| Column | Type | Notes |
|--------|------|-------|
| `field_{name}_value` | longtext | Serialized PHP array of metatag key-value pairs |

Parse with PHP `unserialize()` or Python's `phpserialize` library.

## Field Cardinality

Field cardinality (how many values a field can hold) is stored in config:

```yaml
# field.storage.node.field_tags
cardinality: -1   # -1 = unlimited
```

Multi-value fields store one row per value, distinguished by the `delta` column:

```sql
-- Node 42 has three tags
SELECT entity_id, delta, field_tags_target_id
FROM node__field_tags
WHERE entity_id = 42;
-- 42, 0, 5
-- 42, 1, 12
-- 42, 2, 7
```

## Detecting Field Types from Database

```sql
-- Find what columns a field table has (reveals the field type)
SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'node__field_image'
  AND column_name NOT IN ('bundle','deleted','entity_id','revision_id','langcode','delta')
ORDER BY ordinal_position;
```

Column suffix patterns that reveal the type:

| Suffix Pattern | Field Type |
|---------------|-----------|
| `_value` only (varchar 255) | string or list_string |
| `_value` only (longtext) | string_long, text_long |
| `_value` + `_format` | text, text_long |
| `_value` + `_summary` + `_format` | text_with_summary |
| `_target_id` only | entity_reference |
| `_target_id` + `_target_revision_id` | entity_reference_revisions |
| `_target_id` + `_alt` + `_title` + `_width` + `_height` | image |
| `_target_id` + `_display` + `_description` | file |
| `_uri` + `_title` + `_options` | link |
| `_country_code` + `_administrative_area` + ... | address |
| `_lat` + `_lon` + `_value` | geofield |
| `_color` + `_opacity` | color_field |
| `_value` + `_end_value` (varchar 20) | daterange |
