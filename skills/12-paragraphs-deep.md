# Skill 12: Paragraphs Deep — Recursive Paragraph Tree Resolution

Extract arbitrarily nested Drupal paragraph trees into flat, typed, portable structures. This skill handles the single hardest data extraction problem in Drupal migration: paragraph entities that reference other paragraph entities, which reference media, which reference files, N levels deep.

---

## Why This Is Hard

A Drupal node does not contain its content inline. It contains entity reference revision fields that point to paragraph entities. Each paragraph entity can contain more entity reference revision fields pointing to more paragraph entities. Each of those can reference media entities, taxonomy terms, other nodes, or more paragraphs.

The tree has no fixed depth. A real-world content page looks like this:

```
Node (landing_page)
  └── field_content (entity_reference_revisions → paragraph[])
      ├── hero_banner
      │   ├── field_title (string)
      │   ├── field_subtitle (string)
      │   └── field_background (entity_reference → media)
      │       └── image (media)
      │           └── field_media_image (image → file)
      │               └── file entity (uri, filename, filemime)
      ├── card_group
      │   ├── field_heading (string)
      │   └── field_cards (entity_reference_revisions → paragraph[])
      │       ├── card
      │       │   ├── field_title (string)
      │       │   ├── field_body (text_long)
      │       │   ├── field_link (link)
      │       │   └── field_icon (entity_reference → media)
      │       │       └── image (media)
      │       │           └── field_media_image (image → file)
      │       ├── card
      │       │   ├── field_title (string)
      │       │   ├── field_link (link)
      │       │   └── field_icon (entity_reference → media)
      │       └── card
      │           ├── field_title (string)
      │           └── field_link (link)
      └── accordion
          ├── field_heading (string)
          └── field_items (entity_reference_revisions → paragraph[])
              ├── accordion_item
              │   ├── field_heading (string)
              │   └── field_body (text_long)
              ├── accordion_item
              │   ├── field_heading (string)
              │   ├── field_body (text_long)
              │   └── field_nested (entity_reference_revisions → paragraph[])
              │       └── callout_box
              │           ├── field_text (text_long)
              │           └── field_icon (entity_reference → media)
              └── accordion_item
                  ├── field_heading (string)
                  └── field_body (text_long)
```

That tree is 5 levels deep from node to file entity. Some sites go deeper. Layout paragraphs (two-column, three-column) add structural nesting on top of content nesting. A layout paragraph wraps other paragraphs in columns, adding a level that carries no content of its own.

Every extraction method must handle this recursion. A flat database query returns paragraph rows with no tree context. JSON:API requires you to specify every relationship path up front. There is no "give me everything" button.

---

## Prerequisites

- Skill 02 (Content Model Map) completed. You have the full field inventory including paragraph types, their fields, and which fields are `entity_reference_revisions` targeting `paragraph`.
- Know the maximum nesting depth. Skill 02's output tells you which paragraph types contain `entity_reference_revisions` fields targeting other paragraph types. Trace the chains to find the longest possible path.
- At least one access method confirmed: database, Drush, JSON:API, or config export + database.

---

## Database Schema

### D8/D9/D10/D11

Paragraphs use four base tables:

| Table | Purpose |
|---|---|
| `paragraphs_item` | Entity ID, revision ID, UUID, type (bundle), langcode |
| `paragraphs_item_field_data` | Translatable base field values: type, status, langcode, parent_type, parent_id, parent_field_name, created, behavior_settings |
| `paragraphs_item_revision` | Revision tracking: id, revision_id, langcode |
| `paragraphs_item_revision_field_data` | Per-revision translatable base field values |

Field data for each paragraph field lives in per-field tables:

| Table pattern | Purpose |
|---|---|
| `paragraph__field_{name}` | Current field values for all paragraph bundles that use this field |
| `paragraph_revision__field_{name}` | Per-revision field values |

These per-field tables have columns:

| Column | Meaning |
|---|---|
| `bundle` | Paragraph type machine name |
| `deleted` | 0 or 1 |
| `entity_id` | Paragraph entity ID |
| `revision_id` | Paragraph revision ID |
| `langcode` | Language code |
| `delta` | Position index for multi-value fields (0-based) |
| `field_{name}_*` | One or more value columns depending on field type |

For `entity_reference_revisions` fields (how paragraphs reference child paragraphs):

```
field_{name}_target_id        -- child paragraph entity ID
field_{name}_target_revision_id -- child paragraph revision ID
```

For `entity_reference` fields (how paragraphs reference media, terms, nodes):

```
field_{name}_target_id        -- referenced entity ID
```

For scalar fields, the column suffix matches the field type:

| Field type | Column suffix |
|---|---|
| `string`, `string_long` | `_value` |
| `text`, `text_long`, `text_with_summary` | `_value`, `_format` (and `_summary` for summary) |
| `integer`, `decimal`, `float` | `_value` |
| `boolean` | `_value` |
| `link` | `_uri`, `_title`, `_options` |
| `image` | `_target_id`, `_alt`, `_title`, `_width`, `_height` |
| `file` | `_target_id`, `_display`, `_description` |
| `datetime` | `_value` |

### The Parent Chain

The critical columns on `paragraphs_item_field_data`:

```sql
SELECT id, type, parent_type, parent_id, parent_field_name
FROM paragraphs_item_field_data
WHERE id = 4567;
```

| Column | Value | Meaning |
|---|---|---|
| `parent_type` | `node` | The parent entity type |
| `parent_id` | `123` | The parent entity ID |
| `parent_field_name` | `field_content` | The field on the parent that holds this paragraph |

For nested paragraphs, `parent_type` is `paragraph` and `parent_id` is the parent paragraph's entity ID:

| id | type | parent_type | parent_id | parent_field_name |
|---|---|---|---|---|
| 4567 | hero_banner | node | 123 | field_content |
| 4568 | card_group | node | 123 | field_content |
| 4569 | card | paragraph | 4568 | field_cards |
| 4570 | card | paragraph | 4568 | field_cards |
| 4571 | accordion | node | 123 | field_content |
| 4572 | accordion_item | paragraph | 4571 | field_items |

This is the Rosetta Stone for tree reconstruction. Every paragraph knows its parent. You can build the tree top-down (from node, follow references) or bottom-up (from any paragraph, follow parent chain to root).

### D7

D7 paragraphs use different table names and the module was called `paragraphs` (contrib) or `field_collection` (older sites).

For the `paragraphs` module on D7:

| Table | Equivalent in D8+ |
|---|---|
| `paragraphs_item` | `paragraphs_item` (but schema differs) |
| `paragraphs_item_revision` | `paragraphs_item_revision` |
| `field_data_field_{name}` | `paragraph__field_{name}` |
| `field_revision_field_{name}` | `paragraph_revision__field_{name}` |

D7 `paragraphs_item` columns: `item_id`, `revision_id`, `bundle`, `field_name`, `archived`.

D7 stores the parent relationship differently. The `field_name` column on `paragraphs_item` records which field on the parent entity holds this paragraph. The parent entity ID comes from the parent's field data table: look in `field_data_field_{parent_field_name}` for a row where `field_{parent_field_name}_value` equals the paragraph's `item_id`.

For `field_collection` on D7:

| Table | Purpose |
|---|---|
| `field_collection_item` | item_id, revision_id, field_name, archived |
| `field_collection_item_revision` | item_id, revision_id |
| `field_data_field_{name}` | Field values on the collection item |

The extraction logic is the same: resolve the parent field, load child items, resolve their fields, recurse.

---

## Field Collections (D7)

Field collections are the predecessor to Paragraphs in Drupal 7. Any D7 site with structured content uses these instead of Paragraphs. The `field_collection` module provides a `field_collection_item` entity type that groups fields into a reusable compound field attached to a host entity.

### Schema

| Table | Purpose |
|---|---|
| `field_collection_item` | Base table: `item_id`, `revision_id`, `field_name`, `archived` |
| `field_collection_item_revision` | Revision tracking: `item_id`, `revision_id` |
| `field_data_field_{name}` | Field values on the collection item (entity_type = `field_collection_item`) |
| `field_revision_field_{name}` | Per-revision field values |

### Host Relationship

Each field collection belongs to a parent entity. There is no `parent_type`/`parent_id` like Paragraphs. The relationship is implicit through the hosting field.

The hosting field is stored in `field_data_field_{collection_name}` on the parent entity. The `field_{collection_name}_value` column points to the `field_collection_item.item_id`. The `field_name` column on `field_collection_item` records which field on the host entity owns the collection.

To resolve the parent: look in `field_data_field_{field_name}` for a row where `field_{field_name}_value` equals the item's `item_id`. That row's `entity_type` and `entity_id` identify the host.

### Fields on the Collection

Fields attached to the collection item are stored in standard D7 field tables (`field_data_field_*`) with `entity_type = 'field_collection_item'` and `entity_id` matching the `item_id`.

### Nesting

Field collections support one level of nesting. A field collection can contain another field collection field. This is rare in practice but the schema allows it.

### Detection

A site uses field collections if:
- The `field_collection` module is enabled
- `field_collection_item` entries exist in the `field_config` table

### SQL for Extraction

```sql
-- Find all field collection fields
SELECT field_name, data FROM field_config WHERE type = 'field_collection';

-- Export a field collection with its host
SELECT fci.item_id, fci.revision_id, fci.field_name,
       fd.entity_type AS host_entity_type, fd.entity_id AS host_entity_id, fd.delta
FROM field_collection_item fci
JOIN field_data_{field_name} fd ON fd.field_{field_name}_value = fci.item_id;
```

Replace `{field_name}` with the actual collection field name from the first query.

```sql
-- Load all field values for a collection item
-- For each field on the collection (from field_config_instance where entity_type = 'field_collection_item'):
SELECT *
FROM field_data_field_{field_on_collection}
WHERE entity_type = 'field_collection_item'
  AND entity_id = {item_id}
  AND deleted = 0;
```

### Batch Extraction

```sql
-- All collection items for a given field, with their hosts
SELECT fci.item_id, fci.revision_id, fci.field_name,
       fd.entity_type AS host_entity_type, fd.entity_id AS host_entity_id, fd.delta
FROM field_collection_item fci
JOIN field_data_field_address fd
  ON fd.field_address_value = fci.item_id
  AND fd.entity_type = 'node'
WHERE fci.field_name = 'field_address'
  AND fci.archived = 0
ORDER BY fd.entity_id, fd.delta;
```

### Conceptual Mapping

| Field Collection concept | Paragraphs equivalent |
|---|---|
| `field_collection_item` | Paragraph entity |
| `item_id` | Paragraph `id` |
| Host field (`field_data_field_{name}`) | `entity_reference_revisions` field |
| `field_name` column on item | `parent_field_name` on paragraph |
| Implicit host lookup | Explicit `parent_type` + `parent_id` |

The extraction logic mirrors Paragraphs: resolve the host field, load child items, resolve their fields, recurse if nested.

---

## Strategy 1: Database Queries (Top-Down)

The most reliable method. Works with any Drupal version if you have database access. No depth limits. No HTTP overhead. Full control over which revisions you resolve.

### Step 1: Find paragraph reference fields on the node

From the content model (Skill 02), identify every `entity_reference_revisions` field on the node's content type. Example: `field_content` on `landing_page`.

Query the node's field data table:

```sql
SELECT entity_id, delta,
       field_content_target_id,
       field_content_target_revision_id
FROM node__field_content
WHERE entity_id = 123
  AND deleted = 0
ORDER BY delta ASC;
```

Result:

| entity_id | delta | field_content_target_id | field_content_target_revision_id |
|---|---|---|---|
| 123 | 0 | 4567 | 8901 |
| 123 | 1 | 4568 | 8902 |
| 123 | 2 | 4571 | 8905 |

### Step 2: Load each paragraph's base data

```sql
SELECT id, type, status, langcode,
       parent_type, parent_id, parent_field_name
FROM paragraphs_item_field_data
WHERE id IN (4567, 4568, 4571)
  AND langcode = 'en';
```

Now you know each paragraph's type (bundle). The type tells you which fields to query.

### Step 3: Load field values for each paragraph

For each paragraph type, query its field tables. Suppose paragraph 4567 is type `hero_banner` with fields `field_title`, `field_subtitle`, `field_background`:

```sql
-- Scalar fields
SELECT entity_id, delta, field_title_value
FROM paragraph__field_title
WHERE entity_id = 4567 AND deleted = 0;

SELECT entity_id, delta, field_subtitle_value
FROM paragraph__field_subtitle
WHERE entity_id = 4567 AND deleted = 0;

-- Reference field (media)
SELECT entity_id, delta, field_background_target_id
FROM paragraph__field_background
WHERE entity_id = 4567 AND deleted = 0;
```

### Step 4: Recurse into child paragraphs

If any field on the paragraph is `entity_reference_revisions` targeting `paragraph`, repeat from Step 2.

For paragraph 4568 (type `card_group`) with field `field_cards`:

```sql
SELECT entity_id, delta,
       field_cards_target_id,
       field_cards_target_revision_id
FROM paragraph__field_cards
WHERE entity_id = 4568
  AND deleted = 0
ORDER BY delta ASC;
```

This returns the child paragraph IDs. Load them, resolve their fields, recurse again if they contain paragraph references.

### Step 5: Resolve media, taxonomy, and other references

When you encounter an `entity_reference` field targeting `media`:

```sql
-- Get the media entity
SELECT mid, bundle, name, status
FROM media_field_data
WHERE mid = 789;

-- Get the source field value (e.g., field_media_image for image media)
SELECT entity_id, field_media_image_target_id,
       field_media_image_alt, field_media_image_title,
       field_media_image_width, field_media_image_height
FROM media__field_media_image
WHERE entity_id = 789;

-- Get the file entity
SELECT fid, uuid, uri, filename, filemime, filesize
FROM file_managed
WHERE fid = 456;
```

For taxonomy term references:

```sql
SELECT tid, name, description__value
FROM taxonomy_term_field_data
WHERE tid = 55;
```

### Batch Optimization

Do not run one query per paragraph. Batch by type.

1. Collect all paragraph IDs from the node's reference fields.
2. Load all their base data in one query.
3. Group by type.
4. For each type, run one query per field table with `entity_id IN (...)`.
5. Collect new paragraph IDs from any `entity_reference_revisions` results.
6. Repeat until no new paragraph IDs are found.

```sql
-- Batch load all paragraphs at depth 1
SELECT id, type, status, parent_type, parent_id, parent_field_name
FROM paragraphs_item_field_data
WHERE id IN (4567, 4568, 4571)
  AND langcode = 'en'
  AND status = 1;

-- Batch load field_title for all hero_banner paragraphs
SELECT entity_id, delta, field_title_value
FROM paragraph__field_title
WHERE entity_id IN (4567)
  AND deleted = 0;

-- Batch load field_cards for all card_group paragraphs
SELECT entity_id, delta,
       field_cards_target_id,
       field_cards_target_revision_id
FROM paragraph__field_cards
WHERE entity_id IN (4568)
  AND deleted = 0
ORDER BY entity_id, delta;

-- Now you have depth-2 paragraph IDs. Batch load those.
-- Repeat.
```

This turns an N-query-per-paragraph approach into an N-query-per-type-per-depth approach. A site with 10 paragraph types and max depth 4 needs roughly 40 field queries total for one node, regardless of how many paragraphs are on the page.

### Full Recursive Query Script (SQL + pseudo-code)

```python
def resolve_paragraph_tree(node_id, node_type, field_map, db):
    """
    field_map: from Skill 02 content model.
    Structure: {
        'node': {
            'landing_page': {
                'field_content': {
                    'type': 'entity_reference_revisions',
                    'target_type': 'paragraph',
                    'target_bundles': ['hero_banner', 'card_group', 'accordion']
                }
            }
        },
        'paragraph': {
            'card_group': {
                'field_cards': {
                    'type': 'entity_reference_revisions',
                    'target_type': 'paragraph',
                    'target_bundles': ['card']
                },
                'field_heading': {
                    'type': 'string'
                }
            },
            ...
        }
    }
    """
    tree = {'_entity_type': 'node', '_bundle': node_type, '_id': node_id}

    # Step 1: Get paragraph references from node
    para_fields = [
        fname for fname, fdef in field_map['node'][node_type].items()
        if fdef['type'] == 'entity_reference_revisions'
        and fdef['target_type'] == 'paragraph'
    ]

    for fname in para_fields:
        rows = db.query(f"""
            SELECT delta, {fname}_target_id, {fname}_target_revision_id
            FROM node__{fname}
            WHERE entity_id = %s AND deleted = 0
            ORDER BY delta
        """, [node_id])
        para_ids = [r[fname + '_target_id'] for r in rows]
        tree[fname] = resolve_paragraphs(para_ids, field_map, db)

    return tree


def resolve_paragraphs(para_ids, field_map, db):
    if not para_ids:
        return []

    # Load base data
    base = db.query("""
        SELECT id, type, status, langcode,
               parent_type, parent_id, parent_field_name
        FROM paragraphs_item_field_data
        WHERE id IN %s AND langcode = 'en' AND status = 1
    """, [tuple(para_ids)])

    # Index by id, preserve original ordering
    id_order = {pid: i for i, pid in enumerate(para_ids)}
    base_by_id = {row['id']: row for row in base}

    results = [None] * len(para_ids)

    # Group by type for batch field loading
    by_type = {}
    for pid in para_ids:
        if pid not in base_by_id:
            continue
        ptype = base_by_id[pid]['type']
        by_type.setdefault(ptype, []).append(pid)

    for ptype, pids in by_type.items():
        fields = field_map.get('paragraph', {}).get(ptype, {})

        for fname, fdef in fields.items():
            table = f"paragraph__{fname}"
            rows = db.query(f"""
                SELECT entity_id, delta, *
                FROM {table}
                WHERE entity_id IN %s AND deleted = 0
                ORDER BY entity_id, delta
            """, [tuple(pids)])

            # Group results by entity_id
            by_entity = {}
            for r in rows:
                by_entity.setdefault(r['entity_id'], []).append(r)

            for pid in pids:
                idx = id_order[pid]
                if results[idx] is None:
                    results[idx] = {
                        '_type': ptype,
                        '_id': pid,
                    }

                field_rows = by_entity.get(pid, [])

                if fdef['type'] == 'entity_reference_revisions' \
                   and fdef.get('target_type') == 'paragraph':
                    # Recurse
                    child_ids = [
                        r[f'{fname}_target_id'] for r in field_rows
                    ]
                    results[idx][fname] = resolve_paragraphs(
                        child_ids, field_map, db
                    )
                elif fdef['type'] == 'entity_reference':
                    # Resolve media, term, node references
                    target_ids = [
                        r[f'{fname}_target_id'] for r in field_rows
                    ]
                    results[idx][fname] = resolve_references(
                        target_ids, fdef['target_type'], field_map, db
                    )
                else:
                    # Scalar or compound value
                    results[idx][fname] = extract_field_values(
                        field_rows, fname, fdef
                    )

    # Filter None entries (paragraphs that were missing or unpublished)
    return [r for r in results if r is not None]
```

### Drush Wrapper

If you have Drush but not direct DB access, wrap the same logic in a PHP script:

```php
<?php
/**
 * Drush script: resolve full paragraph tree for a node.
 * Run with: drush php:script resolve-paragraphs.php -- <nid>
 */

use Drupal\node\Entity\Node;
use Drupal\paragraphs\Entity\Paragraph;
use Drupal\media\Entity\Media;
use Drupal\file\Entity\File;
use Drupal\taxonomy\Entity\Term;

$nid = $extra[0] ?? NULL;
if (!$nid) {
  echo "Usage: drush php:script resolve-paragraphs.php -- <nid>\n";
  exit(1);
}

$node = Node::load($nid);
if (!$node) {
  echo json_encode(['error' => "Node $nid not found"]);
  exit(1);
}

$result = resolve_entity($node);
echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

function resolve_entity($entity, $depth = 0, $max_depth = 10) {
  if ($depth > $max_depth) {
    return ['_error' => 'max depth exceeded', '_id' => $entity->id()];
  }

  $data = [
    '_type' => $entity->bundle(),
    '_entity_type' => $entity->getEntityTypeId(),
    '_id' => (int) $entity->id(),
    '_uuid' => $entity->uuid(),
  ];

  $field_definitions = $entity->getFieldDefinitions();

  foreach ($field_definitions as $field_name => $definition) {
    // Skip base fields except a few useful ones.
    if ($definition->isBaseField()) {
      if (in_array($field_name, ['title', 'name', 'status', 'langcode', 'created', 'changed'])) {
        $data[$field_name] = $entity->get($field_name)->value;
      }
      continue;
    }

    $field_type = $definition->getType();
    $field = $entity->get($field_name);

    if ($field->isEmpty()) {
      $data[$field_name] = NULL;
      continue;
    }

    switch ($field_type) {
      case 'entity_reference_revisions':
        // Paragraph references. Recurse.
        $children = [];
        foreach ($field->referencedEntities() as $child) {
          $children[] = resolve_entity($child, $depth + 1, $max_depth);
        }
        $data[$field_name] = $children;
        break;

      case 'entity_reference':
        $target_type = $definition->getSetting('target_type');
        $refs = [];
        foreach ($field->referencedEntities() as $ref) {
          if ($target_type === 'media') {
            $refs[] = resolve_media($ref, $depth + 1, $max_depth);
          }
          elseif ($target_type === 'taxonomy_term') {
            $refs[] = [
              '_type' => $ref->bundle(),
              '_entity_type' => 'taxonomy_term',
              '_id' => (int) $ref->id(),
              'name' => $ref->getName(),
            ];
          }
          else {
            $refs[] = [
              '_entity_type' => $ref->getEntityTypeId(),
              '_type' => $ref->bundle(),
              '_id' => (int) $ref->id(),
              'label' => $ref->label(),
            ];
          }
        }
        $cardinality = $definition->getFieldStorageDefinition()->getCardinality();
        $data[$field_name] = ($cardinality === 1) ? ($refs[0] ?? NULL) : $refs;
        break;

      case 'image':
        $images = [];
        foreach ($field as $item) {
          $file = File::load($item->target_id);
          $images[] = [
            'url' => $file ? \Drupal::service('file_url_generator')->generateAbsoluteString($file->getFileUri()) : NULL,
            'uri' => $file ? $file->getFileUri() : NULL,
            'alt' => $item->alt,
            'title' => $item->title,
            'width' => (int) $item->width,
            'height' => (int) $item->height,
            'filename' => $file ? $file->getFilename() : NULL,
            'filemime' => $file ? $file->getMimeType() : NULL,
          ];
        }
        $cardinality = $definition->getFieldStorageDefinition()->getCardinality();
        $data[$field_name] = ($cardinality === 1) ? ($images[0] ?? NULL) : $images;
        break;

      case 'file':
        $files = [];
        foreach ($field as $item) {
          $file = File::load($item->target_id);
          $files[] = [
            'url' => $file ? \Drupal::service('file_url_generator')->generateAbsoluteString($file->getFileUri()) : NULL,
            'uri' => $file ? $file->getFileUri() : NULL,
            'filename' => $file ? $file->getFilename() : NULL,
            'filemime' => $file ? $file->getMimeType() : NULL,
            'filesize' => $file ? (int) $file->getSize() : NULL,
            'description' => $item->description,
          ];
        }
        $cardinality = $definition->getFieldStorageDefinition()->getCardinality();
        $data[$field_name] = ($cardinality === 1) ? ($files[0] ?? NULL) : $files;
        break;

      case 'link':
        $links = [];
        foreach ($field as $item) {
          $links[] = [
            'uri' => $item->uri,
            'title' => $item->title,
            'options' => $item->options,
          ];
        }
        $cardinality = $definition->getFieldStorageDefinition()->getCardinality();
        $data[$field_name] = ($cardinality === 1) ? ($links[0] ?? NULL) : $links;
        break;

      case 'text_with_summary':
        $data[$field_name] = [
          'value' => $field->value,
          'summary' => $field->summary,
          'format' => $field->format,
        ];
        break;

      case 'text_long':
      case 'text':
        $data[$field_name] = [
          'value' => $field->value,
          'format' => $field->format,
        ];
        break;

      default:
        // Scalars and multi-value scalars.
        $values = [];
        foreach ($field as $item) {
          $values[] = $item->value;
        }
        $cardinality = $definition->getFieldStorageDefinition()->getCardinality();
        $data[$field_name] = ($cardinality === 1) ? ($values[0] ?? NULL) : $values;
        break;
    }
  }

  return $data;
}

function resolve_media($media, $depth, $max_depth) {
  $data = [
    '_entity_type' => 'media',
    '_type' => $media->bundle(),
    '_id' => (int) $media->id(),
    'name' => $media->getName(),
  ];

  // Get the source field.
  $source = $media->getSource();
  $source_field = $source->getSourceFieldDefinition($media->bundle->entity);
  if ($source_field) {
    $source_field_name = $source_field->getName();
    $field = $media->get($source_field_name);
    if (!$field->isEmpty()) {
      $field_type = $source_field->getType();
      if ($field_type === 'image') {
        $item = $field->first();
        $file = File::load($item->target_id);
        $data['source'] = [
          'url' => $file ? \Drupal::service('file_url_generator')->generateAbsoluteString($file->getFileUri()) : NULL,
          'uri' => $file ? $file->getFileUri() : NULL,
          'alt' => $item->alt,
          'title' => $item->title,
          'width' => (int) $item->width,
          'height' => (int) $item->height,
          'filename' => $file ? $file->getFilename() : NULL,
          'filemime' => $file ? $file->getMimeType() : NULL,
        ];
      }
      elseif ($field_type === 'file') {
        $item = $field->first();
        $file = File::load($item->target_id);
        $data['source'] = [
          'url' => $file ? \Drupal::service('file_url_generator')->generateAbsoluteString($file->getFileUri()) : NULL,
          'uri' => $file ? $file->getFileUri() : NULL,
          'filename' => $file ? $file->getFilename() : NULL,
          'filemime' => $file ? $file->getMimeType() : NULL,
          'filesize' => $file ? (int) $file->getSize() : NULL,
        ];
      }
      elseif (in_array($field_type, ['string', 'string_long'])) {
        // Remote video, oembed, etc.
        $data['source'] = ['value' => $field->value];
      }
    }
  }

  return $data;
}
```

Run it:

```bash
drush php:script resolve-paragraphs.php -- 123 > node-123-tree.json
```

To export all nodes of a content type:

```bash
drush sql:query "SELECT nid FROM node_field_data WHERE type = 'landing_page' AND status = 1" | while read nid; do
  drush php:script resolve-paragraphs.php -- "$nid" > "export/node-${nid}.json"
done
```

---

## Strategy 2: JSON:API Include Chains

Works when you have HTTP access to a D8.7+ / D9+ site with JSON:API enabled but no shell or database access.

### The Problem with Includes

JSON:API returns relationships as resource identifiers by default (type + ID, no field data). To get the actual field values of related entities, you must add `include` parameters specifying each relationship path.

For nested paragraphs, you need the full dot-separated path from root to leaf:

```
include=field_content,
        field_content.field_background,
        field_content.field_background.field_media_image,
        field_content.field_cards,
        field_content.field_cards.field_icon,
        field_content.field_cards.field_icon.field_media_image,
        field_content.field_items,
        field_content.field_items.field_nested,
        field_content.field_items.field_nested.field_icon,
        field_content.field_items.field_nested.field_icon.field_media_image
```

Each additional nesting level multiplies the include paths. Miss one path and that branch comes back as a stub with no field data.

### Building Include Chains Automatically

Use the content model from Skill 02 to generate include chains. Walk the field map recursively:

```python
def build_include_chains(entity_type, bundle, field_map, prefix='', depth=0, max_depth=6):
    """
    Generate all include paths needed to fully resolve an entity.
    """
    if depth > max_depth:
        return []

    chains = []
    fields = field_map.get(entity_type, {}).get(bundle, {})

    for fname, fdef in fields.items():
        path = f"{prefix}.{fname}" if prefix else fname

        if fdef['type'] in ('entity_reference_revisions', 'entity_reference'):
            chains.append(path)
            target_type = fdef.get('target_type', '')
            target_bundles = fdef.get('target_bundles', [])

            for tbundle in target_bundles:
                chains.extend(
                    build_include_chains(
                        target_type, tbundle, field_map,
                        prefix=path, depth=depth + 1, max_depth=max_depth
                    )
                )

    return chains
```

### Depth Limits

JSON:API in Drupal core does not impose a hard include depth limit. But practical limits exist:

- **URL length**: Include chains for deep trees can exceed the 8KB URL limit on many web servers. Split across multiple requests if needed.
- **Memory**: Deep includes with many paragraphs can exhaust PHP memory. The response for a single node with 50 paragraphs across 4 levels can be 500KB+ of JSON.
- **Timeout**: Complex include resolution runs multiple entity loads on the server. PHP's `max_execution_time` can kill the request.

If any of these limits hit, split the extraction:

1. First request: fetch the node with depth-1 includes only.
2. Collect paragraph IDs from the response.
3. Second request: fetch each paragraph with its own includes.

```
GET /jsonapi/node/landing_page/123?include=field_content

# From the response, extract paragraph UUIDs and types.
# Then for paragraph types that nest:

GET /jsonapi/paragraph/card_group/uuid-4568?include=field_cards,field_cards.field_icon,field_cards.field_icon.field_media_image
```

### Parsing the JSON:API Response

JSON:API returns included entities in a flat `included` array, not nested under the parent. You must reassemble the tree yourself.

```json
{
  "data": {
    "type": "node--landing_page",
    "id": "uuid-123",
    "attributes": { "title": "My Page" },
    "relationships": {
      "field_content": {
        "data": [
          { "type": "paragraph--hero_banner", "id": "uuid-4567", "meta": { "target_revision_id": 8901 } },
          { "type": "paragraph--card_group", "id": "uuid-4568", "meta": { "target_revision_id": 8902 } }
        ]
      }
    }
  },
  "included": [
    {
      "type": "paragraph--hero_banner",
      "id": "uuid-4567",
      "attributes": { "field_title": "Welcome" },
      "relationships": {
        "field_background": {
          "data": { "type": "media--image", "id": "uuid-789" }
        }
      }
    },
    {
      "type": "paragraph--card_group",
      "id": "uuid-4568",
      "attributes": { "field_heading": "Our Services" },
      "relationships": {
        "field_cards": {
          "data": [
            { "type": "paragraph--card", "id": "uuid-4569" },
            { "type": "paragraph--card", "id": "uuid-4570" }
          ]
        }
      }
    },
    {
      "type": "paragraph--card",
      "id": "uuid-4569",
      "attributes": { "field_title": "Card 1", "field_body": { "value": "<p>Body</p>", "format": "full_html" } }
    }
  ]
}
```

Reassembly:

1. Index the `included` array by `type + id`.
2. Walk `data.relationships`. For each relationship, look up the included entity.
3. For each included entity, walk its own relationships. Recurse.

```python
def reassemble_jsonapi(response):
    included_index = {}
    for item in response.get('included', []):
        key = (item['type'], item['id'])
        included_index[key] = item

    def resolve(resource_identifier):
        key = (resource_identifier['type'], resource_identifier['id'])
        entity = included_index.get(key)
        if not entity:
            return {'_ref': key, '_unresolved': True}

        result = {
            '_type': entity['type'].split('--')[1],
            '_entity_type': entity['type'].split('--')[0],
            '_uuid': entity['id'],
        }

        # Copy attributes
        for attr_name, attr_value in entity.get('attributes', {}).items():
            if not attr_name.startswith('drupal_internal__'):
                result[attr_name] = attr_value

        # Resolve relationships
        for rel_name, rel_data in entity.get('relationships', {}).items():
            if rel_data.get('data') is None:
                result[rel_name] = None
            elif isinstance(rel_data['data'], list):
                result[rel_name] = [resolve(ref) for ref in rel_data['data']]
            else:
                result[rel_name] = resolve(rel_data['data'])

        return result

    root = response['data']
    result = {
        '_type': root['type'].split('--')[1],
        '_entity_type': root['type'].split('--')[0],
        '_uuid': root['id'],
    }

    for attr_name, attr_value in root.get('attributes', {}).items():
        if not attr_name.startswith('drupal_internal__'):
            result[attr_name] = attr_value

    for rel_name, rel_data in root.get('relationships', {}).items():
        if rel_data.get('data') is None:
            result[rel_name] = None
        elif isinstance(rel_data['data'], list):
            result[rel_name] = [resolve(ref) for ref in rel_data['data']]
        else:
            result[rel_name] = resolve(rel_data['data'])

    return result
```

---

## Strategy 3: Reverse Lookup (Bottom-Up)

Sometimes you need to find all paragraphs of a specific type across the site, then trace each back to its parent node. This is useful for auditing: "which nodes use the `video_embed` paragraph type?"

### Find all paragraphs of a type

```sql
SELECT id, parent_type, parent_id, parent_field_name
FROM paragraphs_item_field_data
WHERE type = 'video_embed'
  AND status = 1
  AND langcode = 'en';
```

### Trace to root node

```sql
-- Recursive CTE: walk from paragraph up through parent chain to node.
WITH RECURSIVE tree AS (
  -- Start: the paragraph we care about
  SELECT
    id,
    type,
    parent_type,
    parent_id,
    parent_field_name,
    1 AS depth,
    CAST(id AS CHAR(1000)) AS path
  FROM paragraphs_item_field_data
  WHERE id = 4572
    AND langcode = 'en'

  UNION ALL

  -- Walk up: if parent is a paragraph, join again
  SELECT
    p.id,
    p.type,
    p.parent_type,
    p.parent_id,
    p.parent_field_name,
    t.depth + 1,
    CONCAT(p.id, ' > ', t.path)
  FROM paragraphs_item_field_data p
  INNER JOIN tree t ON t.parent_type = 'paragraph' AND t.parent_id = p.id
  WHERE p.langcode = 'en'
    AND t.depth < 20
)
SELECT * FROM tree
WHERE parent_type = 'node'
ORDER BY depth DESC
LIMIT 1;
```

This returns the root paragraph in the chain, which tells you the parent node ID and field name. The `path` column shows the full chain of paragraph IDs from root to leaf.

### Bulk audit: all nodes using a paragraph type

```sql
WITH RECURSIVE tree AS (
  SELECT id, type, parent_type, parent_id, parent_field_name, 1 AS depth
  FROM paragraphs_item_field_data
  WHERE type = 'video_embed' AND status = 1 AND langcode = 'en'

  UNION ALL

  SELECT p.id, p.type, p.parent_type, p.parent_id, p.parent_field_name, t.depth + 1
  FROM paragraphs_item_field_data p
  INNER JOIN tree t ON t.parent_type = 'paragraph' AND t.parent_id = p.id
  WHERE p.langcode = 'en' AND t.depth < 20
)
SELECT DISTINCT parent_id AS node_id
FROM tree
WHERE parent_type = 'node';
```

---

## Strategy 4: Entity Export (default_content / single_export)

If the `default_content` or `content_sync` module is available, it handles recursion automatically. It serializes entities to HAL+JSON or YAML with embedded references.

### default_content module

```bash
# Export one node with all dependencies (paragraphs, media, files, terms)
drush default-content:export-references node 123 --folder=export/

# Export all nodes of a type
drush default-content:export-references node --bundle=landing_page --folder=export/
```

This produces one file per entity in the dependency tree. Each file contains the full entity with inline references by UUID. The paragraph tree is flattened to a directory of files, linked by UUID references.

Limitations:
- The module must be installed and enabled.
- Large sites with many paragraphs generate thousands of files.
- Export format is Drupal-specific HAL+JSON. You still need a transformation step.

### Parsing default_content output

Each exported file is a JSON-LD document:

```json
{
  "_links": {
    "type": { "href": "https://site.example/rest/type/paragraph/hero_banner" }
  },
  "uuid": [{ "value": "550e8400-e29b-41d4-a716-446655440000" }],
  "type": [{ "target_id": "hero_banner" }],
  "field_title": [{ "value": "Welcome" }],
  "field_background": [{
    "target_type": "media",
    "target_uuid": "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  }]
}
```

To reconstruct the tree:
1. Load all exported files.
2. Index by UUID.
3. For each node, follow `entity_reference_revisions` fields to paragraph UUIDs.
4. For each paragraph, follow its reference fields. Recurse.

---

## Output Format

Regardless of extraction strategy, produce the same output: a flat tree with `_type` discriminators and resolved leaf values.

### Target structure

```json
{
  "_entity_type": "node",
  "_type": "landing_page",
  "_id": 123,
  "_uuid": "a1b2c3d4-...",
  "title": "My Landing Page",
  "status": 1,
  "field_content": [
    {
      "_type": "hero_banner",
      "_id": 4567,
      "field_title": "Welcome",
      "field_subtitle": "To our site",
      "field_background": {
        "_entity_type": "media",
        "_type": "image",
        "_id": 789,
        "name": "Hero background",
        "source": {
          "url": "https://site.example/sites/default/files/hero.jpg",
          "uri": "public://hero.jpg",
          "alt": "A scenic mountain view",
          "title": null,
          "width": 1920,
          "height": 1080,
          "filename": "hero.jpg",
          "filemime": "image/jpeg"
        }
      }
    },
    {
      "_type": "card_group",
      "_id": 4568,
      "field_heading": "Our Services",
      "field_cards": [
        {
          "_type": "card",
          "_id": 4569,
          "field_title": "Service A",
          "field_body": {
            "value": "<p>Description of service A.</p>",
            "format": "full_html"
          },
          "field_link": {
            "uri": "internal:/services/a",
            "title": "Learn more"
          },
          "field_icon": {
            "_entity_type": "media",
            "_type": "image",
            "_id": 790,
            "name": "Service A icon",
            "source": {
              "url": "https://site.example/sites/default/files/icon-a.svg",
              "uri": "public://icon-a.svg",
              "alt": "Service A",
              "filename": "icon-a.svg",
              "filemime": "image/svg+xml"
            }
          }
        },
        {
          "_type": "card",
          "_id": 4570,
          "field_title": "Service B",
          "field_link": {
            "uri": "https://external.example/service-b",
            "title": "Visit"
          },
          "field_icon": null
        }
      ]
    },
    {
      "_type": "accordion",
      "_id": 4571,
      "field_heading": "FAQ",
      "field_items": [
        {
          "_type": "accordion_item",
          "_id": 4572,
          "field_heading": "What is this?",
          "field_body": {
            "value": "<p>An example.</p>",
            "format": "basic_html"
          }
        },
        {
          "_type": "accordion_item",
          "_id": 4573,
          "field_heading": "How does it work?",
          "field_body": {
            "value": "<p>Like this.</p>",
            "format": "basic_html"
          }
        }
      ]
    }
  ]
}
```

### Output rules

1. Every paragraph and referenced entity gets a `_type` field. This is the bundle machine name. Downstream transformation uses this as a component discriminator.
2. Every entity gets `_id` (Drupal integer ID) and optionally `_uuid` (useful for deduplication and default_content cross-references).
3. Multi-value fields are always arrays, even with one item. Single-value fields are scalars or objects.
4. `null` for empty references. Do not omit the key.
5. Media entities include a `source` object with the resolved file URL, URI, alt text, and dimensions. The consumer should not need to resolve another level.
6. Text fields with formats include both `value` (raw HTML) and `format` (machine name of the text format). The consumer decides whether to strip HTML, convert to markdown, or preserve it.
7. Link fields include `uri` (Drupal internal URI format like `internal:/path` or `entity:node/456` or full URLs) and `title`. Convert `internal:/` and `entity:` URIs to full paths using the URL alias table if needed.

---

## Edge Cases

### Orphaned paragraphs

Paragraphs with no valid parent. Happen when a node is deleted but its paragraphs are not cleaned up, or when a field is removed from a content type.

Detect them:

```sql
-- Orphaned: parent is a node that no longer exists
SELECT p.id, p.type, p.parent_type, p.parent_id
FROM paragraphs_item_field_data p
LEFT JOIN node_field_data n ON p.parent_type = 'node' AND p.parent_id = n.nid
WHERE p.parent_type = 'node'
  AND n.nid IS NULL
  AND p.langcode = 'en';

-- Orphaned: parent is a paragraph that no longer exists
SELECT p.id, p.type, p.parent_type, p.parent_id
FROM paragraphs_item_field_data p
LEFT JOIN paragraphs_item_field_data pp ON p.parent_type = 'paragraph' AND p.parent_id = pp.id
WHERE p.parent_type = 'paragraph'
  AND pp.id IS NULL
  AND p.langcode = 'en';
```

Skip orphaned paragraphs during export. Log them for review.

### Circular references

Rare but possible if a paragraph type can reference itself. The content model check in Skill 02 reveals this: look for `entity_reference_revisions` fields on paragraph type X that target paragraph type X (or a chain that loops back).

Guard against it. Track visited paragraph IDs during recursion. If you encounter an ID you have seen, stop and log the cycle.

### Translations

Multilingual sites store paragraph translations in `paragraphs_item_field_data` with different `langcode` values. Field data tables also have a `langcode` column.

Two approaches:
1. Export one language at a time. Filter all queries by `langcode = 'en'` (or whatever the target language is).
2. Export all languages. Return an array of translations per paragraph, keyed by langcode.

Option 1 is simpler. Use it unless the target platform needs all translations in a single import.

Watch for asymmetric translation: a node exists in English and Spanish, but some of its paragraphs are only translated to English. The Spanish tree may have gaps.

```sql
-- Find paragraphs that exist in one language but not another
SELECT en.id, en.type, es.id AS es_id
FROM paragraphs_item_field_data en
LEFT JOIN paragraphs_item_field_data es ON en.id = es.id AND es.langcode = 'es'
WHERE en.langcode = 'en'
  AND en.parent_type = 'node'
  AND en.parent_id = 123
  AND es.id IS NULL;
```

### Revisions

The default approach extracts the current published revision. If you need revision history:

- Use the `_revision` tables: `paragraphs_item_revision_field_data`, `paragraph_revision__field_{name}`.
- The node's revision field table (`node_revision__field_content`) stores which paragraph revision ID was active at each node revision.
- This is a full combinatorial explosion. A node with 20 revisions and 15 paragraphs can have 300 paragraph revision entries. Export only the revisions you need.

### Layout paragraphs (layout_paragraphs module)

Layout paragraphs add structural metadata to the standard paragraph tree. A paragraph marked as a layout section defines a grid. Its child paragraphs are assigned to regions within that grid.

The layout data is stored in `behavior_settings` on the paragraph (a serialized JSON blob in `paragraphs_item_field_data.behavior_settings`).

```json
{
  "layout_paragraphs": {
    "parent_uuid": "parent-paragraph-uuid",
    "region": "main",
    "layout": "layout_twocol_section",
    "config": {
      "column_widths": "50-50"
    }
  }
}
```

Key fields:
- `parent_uuid`: the UUID of the layout section paragraph that contains this paragraph. This creates a second tree structure (by UUID) overlaid on the entity reference tree (by ID).
- `region`: which region of the layout this paragraph is placed in.
- `layout`: the layout plugin ID defining the grid structure.

When extracting layout paragraphs:
1. Resolve the standard paragraph tree first.
2. Then parse `behavior_settings` on each paragraph.
3. Use `parent_uuid` and `region` to build the layout tree.
4. Output includes layout metadata alongside content fields.

```json
{
  "_type": "two_column_layout",
  "_id": 5000,
  "_layout": {
    "plugin": "layout_twocol_section",
    "config": { "column_widths": "50-50" }
  },
  "field_content": [
    {
      "_type": "text_block",
      "_id": 5001,
      "_layout_region": "first",
      "field_body": { "value": "<p>Left column content.</p>", "format": "full_html" }
    },
    {
      "_type": "image_block",
      "_id": 5002,
      "_layout_region": "second",
      "field_image": { "_entity_type": "media", "_type": "image", "_id": 800, "source": { "url": "..." } }
    }
  ]
}
```

### Paragraphs with behavior plugins

Beyond layout, paragraphs can have behavior plugins that store additional config in `behavior_settings`. Common examples:

- **Style**: CSS class or style preset for the paragraph.
- **Animation**: Scroll-triggered animation settings.
- **Visibility**: Conditional display rules.

Always extract `behavior_settings` as a raw JSON object on the output. Let the consumer decide what to do with it.

```json
{
  "_type": "hero_banner",
  "_id": 4567,
  "_behavior_settings": {
    "style": { "style_wrapper": { "classes": "bg-dark text-white" } }
  },
  "field_title": "Welcome"
}
```

---

## Layout Paragraphs

The `layout_paragraphs` module extends standard Paragraphs with grid and layout capabilities. It adds a two-level hierarchy on top of the standard paragraph tree: layout containers with named regions, and component paragraphs placed into those regions.

### How It Works

A paragraph in a `layout_paragraphs` field can be one of two things:

- A **layout**: a container paragraph that defines named regions (e.g., "first", "second", "content"). It uses a layout plugin like `layout_twocol`, `layout_threecol_25_50_25`, or any layout provided by Layout Discovery.
- A **component**: a content paragraph placed into a specific region of a parent layout.

This creates structure: layout paragraph → region → component paragraphs. The layout carries no content of its own. It defines columns or grids. The components carry the actual content.

### Storage

Layout Paragraphs stores its metadata in paragraph behavior plugin settings. The `layout_paragraphs_layout` behavior plugin writes to the `behavior_settings` column on `paragraphs_item_field_data`. This column holds serialized JSON.

For a layout paragraph:

```json
{
  "layout_paragraphs": {
    "layout": "layout_twocol_section",
    "config": {
      "column_widths": "50-50"
    }
  }
}
```

For a component paragraph placed inside a layout:

```json
{
  "layout_paragraphs": {
    "parent_uuid": "550e8400-e29b-41d4-a716-446655440000",
    "region": "first"
  }
}
```

Key fields in the behavior settings:

| Field | Present on | Meaning |
|---|---|---|
| `layout` | Layout paragraphs | Layout plugin ID defining the grid structure |
| `config` | Layout paragraphs | Plugin configuration (column widths, label, classes) |
| `parent_uuid` | Component paragraphs | UUID of the layout paragraph this component belongs to |
| `region` | Component paragraphs | Named region within the parent layout |

The `parent_uuid` creates a second tree structure (by UUID) overlaid on the entity reference tree (by ID). The entity reference field holds all paragraphs in a flat list. The behavior settings encode which ones are layouts and which are components nested inside them.

### Detection

```sql
-- Find paragraphs with layout_paragraphs behavior settings
SELECT id, type, behavior_settings
FROM paragraphs_item_field_data
WHERE behavior_settings LIKE '%layout_paragraphs%'
  AND langcode = 'en'
  AND status = 1;

-- Find layout paragraphs in a specific node's field
SELECT entity_id, delta, field_content_target_id, field_content_target_revision_id
FROM node__field_content
WHERE field_content_target_id IN (
  SELECT id FROM paragraphs_item_field_data
  WHERE behavior_settings LIKE '%layout_paragraphs%'
);
```

### Extraction Approach

1. Extract the standard paragraph tree first using any strategy from this skill.
2. Parse `behavior_settings` JSON on every paragraph in the tree.
3. Identify layout paragraphs (those with a `layout` key in `layout_paragraphs` settings).
4. Identify component paragraphs (those with a `parent_uuid` and `region`).
5. Match components to their parent layout by UUID.
6. Group components by region within each layout.

```python
def reconstruct_layout_tree(paragraphs):
    """
    Takes a flat list of resolved paragraphs (from standard extraction).
    Returns the same list with layout relationships encoded.
    """
    # Index by UUID
    by_uuid = {p['_uuid']: p for p in paragraphs if '_uuid' in p}

    # Identify layouts and components
    layouts = {}
    components = []

    for p in paragraphs:
        settings = p.get('_behavior_settings', {}).get('layout_paragraphs', {})
        if 'layout' in settings:
            p['_layout'] = {
                'plugin': settings['layout'],
                'config': settings.get('config', {}),
            }
            p['_regions'] = {}  # Will be filled with region_name -> [children]
            layouts[p['_uuid']] = p
        elif 'parent_uuid' in settings:
            components.append({
                'paragraph': p,
                'parent_uuid': settings['parent_uuid'],
                'region': settings.get('region', 'content'),
            })

    # Assign components to layout regions
    for comp in components:
        parent = layouts.get(comp['parent_uuid'])
        if parent:
            region = comp['region']
            parent['_regions'].setdefault(region, [])
            parent['_regions'][region].append(comp['paragraph'])
            comp['paragraph']['_layout_region'] = region

    # Return only top-level paragraphs (layouts + non-layout non-components)
    component_uuids = {c['paragraph']['_uuid'] for c in components if '_uuid' in c['paragraph']}
    return [p for p in paragraphs if p.get('_uuid') not in component_uuids]
```

### Output Format

A layout paragraph in the extracted tree:

```json
{
  "_type": "layout_section",
  "_id": 5000,
  "_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "_layout": {
    "plugin": "layout_twocol_section",
    "config": { "column_widths": "50-50" }
  },
  "_regions": {
    "first": [
      {
        "_type": "text_block",
        "_id": 5001,
        "_layout_region": "first",
        "field_body": { "value": "<p>Left column.</p>", "format": "full_html" }
      }
    ],
    "second": [
      {
        "_type": "image_block",
        "_id": 5002,
        "_layout_region": "second",
        "field_image": { "_entity_type": "media", "_type": "image", "_id": 800 }
      }
    ]
  }
}
```

Component paragraphs that belong to a layout are nested inside `_regions` on the layout. They do not appear as siblings at the top level of the field. This reflects the visual structure: the layout wraps its children.

### Mapping to Target Platforms

| Layout plugin | CSS Grid | React | Gutenberg |
|---|---|---|---|
| `layout_twocol_section` | `grid-template-columns` 2-col | `<TwoColumn>` wrapper | `core/columns` (2 cols) |
| `layout_threecol_section` | 3-col grid | `<ThreeColumn>` wrapper | `core/columns` (3 cols) |
| `layout_threecol_25_50_25` | `1fr 2fr 1fr` grid | `<ThreeColumn widths={[25,50,25]}>` | `core/columns` with width attrs |
| `layout_onecol` | Single column (no grid needed) | Fragment or `<Section>` | `core/group` |

The layout plugin ID and config translate to CSS grid definitions or component props on the target. Region names map to grid areas or child component slots.

Cross-reference: see skill 16 for Layout Builder, which solves the same problem (page layout) through a different mechanism (sections and blocks instead of paragraphs and regions).

---

## Verification

After extracting paragraph trees, verify completeness:

### Count check

```sql
-- Total paragraphs owned by node 123 (all depths)
WITH RECURSIVE tree AS (
  SELECT id FROM paragraphs_item_field_data
  WHERE parent_type = 'node' AND parent_id = 123 AND langcode = 'en'

  UNION ALL

  SELECT p.id FROM paragraphs_item_field_data p
  INNER JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = t.id
  WHERE p.langcode = 'en'
)
SELECT COUNT(*) AS total_paragraphs FROM tree;
```

Compare this count against the number of paragraph objects in your extracted JSON. They must match (minus any intentionally skipped orphans or unpublished paragraphs).

### Type distribution

```sql
WITH RECURSIVE tree AS (
  SELECT id, type FROM paragraphs_item_field_data
  WHERE parent_type = 'node' AND parent_id = 123 AND langcode = 'en'

  UNION ALL

  SELECT p.id, p.type FROM paragraphs_item_field_data p
  INNER JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = t.id
  WHERE p.langcode = 'en'
)
SELECT type, COUNT(*) AS count FROM tree GROUP BY type ORDER BY count DESC;
```

### Depth check

```sql
WITH RECURSIVE tree AS (
  SELECT id, type, 1 AS depth
  FROM paragraphs_item_field_data
  WHERE parent_type = 'node' AND parent_id = 123 AND langcode = 'en'

  UNION ALL

  SELECT p.id, p.type, t.depth + 1
  FROM paragraphs_item_field_data p
  INNER JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = t.id
  WHERE p.langcode = 'en'
)
SELECT MAX(depth) AS max_depth FROM tree;
```

If the max depth exceeds what your JSON:API include chains cover, you have missing data.

### Site-wide paragraph statistics

Run before extraction to understand scope:

```sql
-- Total paragraph count
SELECT COUNT(*) FROM paragraphs_item_field_data WHERE langcode = 'en';

-- Per-type distribution
SELECT type, COUNT(*) as count
FROM paragraphs_item_field_data
WHERE langcode = 'en'
GROUP BY type
ORDER BY count DESC;

-- Max nesting depth across the site
WITH RECURSIVE tree AS (
  SELECT id, 1 AS depth
  FROM paragraphs_item_field_data
  WHERE parent_type = 'node' AND langcode = 'en'

  UNION ALL

  SELECT p.id, t.depth + 1
  FROM paragraphs_item_field_data p
  INNER JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = t.id
  WHERE p.langcode = 'en' AND t.depth < 20
)
SELECT MAX(depth) AS site_max_depth FROM tree;

-- Nodes with the most paragraphs
WITH RECURSIVE tree AS (
  SELECT id, parent_id AS root_node_id
  FROM paragraphs_item_field_data
  WHERE parent_type = 'node' AND langcode = 'en'

  UNION ALL

  SELECT p.id, t.root_node_id
  FROM paragraphs_item_field_data p
  INNER JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = t.id
  WHERE p.langcode = 'en' AND t.root_node_id IS NOT NULL
)
SELECT root_node_id, COUNT(*) AS para_count
FROM tree
GROUP BY root_node_id
ORDER BY para_count DESC
LIMIT 20;
```

---

## Choosing a Strategy

| Situation | Strategy |
|---|---|
| Database access available | Strategy 1 (DB queries). Fastest, most reliable, no depth limits. |
| Drush access, no direct DB | Drush PHP script (Strategy 1 variant). Uses Entity API, handles revisions and access checks automatically. |
| HTTP access only, shallow trees (depth 3 or less) | Strategy 2 (JSON:API includes). Single request per node. |
| HTTP access only, deep trees (depth 4+) | Strategy 2 with request splitting. One request per depth level. |
| Need to audit paragraph usage across the site | Strategy 3 (reverse lookup). Find which nodes use specific paragraph types. |
| default_content module installed | Strategy 4 (entity export). Handles recursion automatically. Drupal-specific output format. |
| D7 with paragraphs or field_collection | Strategy 1 adapted for D7 table names and schema. |

For most migrations, use the Drush PHP script. It handles every edge case through the Entity API: translations, revisions, access control, computed fields, behavior settings. The SQL approach is faster for bulk extraction but requires you to handle each field type manually.

---

## Downstream: Mapping to Target Components

The extracted tree with `_type` discriminators maps directly to component systems on any target platform.

| Drupal paragraph type | Next.js / React | WordPress (Gutenberg) | Contentful |
|---|---|---|---|
| `hero_banner` | `<HeroBanner>` component | `core/cover` block | Hero entry type |
| `card_group` + `card` | `<CardGrid>` with `<Card>` children | `core/columns` with custom card blocks | Card Group + Card entries (linked) |
| `accordion` + `accordion_item` | `<Accordion>` with `<AccordionItem>` | `core/details` blocks (WP 6.3+) | Accordion entry with items as rich text or references |
| `two_column_layout` | CSS Grid or `<TwoColumn>` wrapper | `core/columns` | N/A (layout is presentation) |
| `text_block` | `<RichText>` or `dangerouslySetInnerHTML` | `core/paragraph` or `core/freeform` | Long Text field |
| `image_block` | `<Image>` with resolved URL | `core/image` | Media asset reference |
| `video_embed` | `<VideoEmbed>` or `<iframe>` | `core/embed` | Embedded entry |

The `_type` field is the switch key. Write a transformer function for each paragraph type that maps Drupal field names to target component props. The tree structure (arrays of children) maps to component nesting in JSX, block nesting in Gutenberg, or linked entries in headless CMS platforms.
