# Drupal Paragraph Patterns

Paragraphs are Drupal's component-based content model. A node references paragraphs via `entity_reference_revisions` fields. Each paragraph is a typed entity with its own fields.

## Database Tables

### Core Paragraph Tables

| Table | PK | Purpose |
|-------|-----|---------|
| `paragraphs_item` | `id` | Base table. One row per paragraph. |
| `paragraphs_item_field_data` | `(id, langcode)` | Translatable base fields. Parent tracking. |
| `paragraphs_item_revision` | `revision_id` | Revision tracking. |
| `paragraphs_item_field_revision` | `(id, revision_id, langcode)` | Revision translations. |

### Key Columns in paragraphs_item_field_data

| Column | Type | Notes |
|--------|------|-------|
| `id` | int | Paragraph entity ID |
| `revision_id` | int | Current revision ID |
| `type` | varchar | Paragraph type machine name (bundle) |
| `langcode` | varchar | Language |
| `status` | tinyint | Published status |
| `parent_id` | varchar | ID of the host entity |
| `parent_type` | varchar | Entity type of the host (e.g., `node`, `paragraph`) |
| `parent_field_name` | varchar | Field name on the host that references this paragraph |
| `behavior_settings` | longtext | Serialized paragraph behavior plugin settings |
| `created` | int | Unix timestamp |
| `changed` | int | Unix timestamp |
| `default_langcode` | tinyint | 1 if this is the original language |

### Paragraph Field Tables

Each paragraph type has field tables following the standard pattern:

```
paragraph__field_{name}
paragraph_revision__field_{name}
```

## How References Work

A node references paragraphs through an `entity_reference_revisions` field:

```
node__field_content_blocks
├── entity_id = 42 (node ID)
├── field_content_blocks_target_id = 100 (paragraph ID)
├── field_content_blocks_target_revision_id = 200 (paragraph revision ID)
└── delta = 0 (position)
```

The paragraph stores its parent relationship:

```
paragraphs_item_field_data
├── id = 100
├── parent_type = 'node'
├── parent_id = '42'
└── parent_field_name = 'field_content_blocks'
```

## Nested Paragraphs

Paragraphs can reference other paragraphs. A card group paragraph contains card paragraphs. An accordion paragraph contains accordion item paragraphs.

```
node 42
└── field_content_blocks (entity_reference_revisions)
    ├── paragraph 100 (type: hero)
    │   ├── field_title: "Welcome"
    │   ├── field_image: media 55
    │   └── field_cta: {uri: "internal:/about", title: "Learn More"}
    ├── paragraph 101 (type: card_group)
    │   └── field_cards (entity_reference_revisions)
    │       ├── paragraph 102 (type: card)
    │       │   ├── field_title: "Service A"
    │       │   └── field_body: "Description..."
    │       └── paragraph 103 (type: card)
    │           ├── field_title: "Service B"
    │           └── field_body: "Description..."
    └── paragraph 104 (type: accordion)
        └── field_items (entity_reference_revisions)
            ├── paragraph 105 (type: accordion_item)
            │   ├── field_title: "FAQ 1"
            │   └── field_body: "Answer 1"
            └── paragraph 106 (type: accordion_item)
                ├── field_title: "FAQ 2"
                └── field_body: "Answer 2"
```

For nested paragraphs, `parent_type` is `paragraph` and `parent_id` is the parent paragraph's ID.

## Common Paragraph Types

These are the most frequently encountered paragraph bundles across Drupal sites:

### Layout / Structure

| Type | Typical Fields | Purpose |
|------|---------------|---------|
| `section` | `field_layout`, `field_background`, `field_content` | Page section wrapper |
| `columns` / `grid` | `field_columns` (paragraph ref), `field_column_count` | Multi-column layout |
| `container` | `field_content` (paragraph ref), `field_width` | Width-constrained wrapper |
| `spacer` / `divider` | `field_size` | Vertical spacing |
| `tab_group` | `field_tabs` (paragraph ref) | Tabbed interface |
| `tab` | `field_title`, `field_content` (paragraph ref) | Single tab |

### Content

| Type | Typical Fields | Purpose |
|------|---------------|---------|
| `text` / `wysiwyg` | `field_body` (text_long) | Rich text block |
| `hero` / `banner` | `field_title`, `field_subtitle`, `field_image`, `field_cta`, `field_overlay` | Hero section |
| `card` | `field_title`, `field_body`, `field_image`, `field_link` | Card component |
| `card_group` | `field_cards` (paragraph ref) | Card grid |
| `cta` / `call_to_action` | `field_title`, `field_body`, `field_link`, `field_style` | Call to action |
| `quote` / `blockquote` | `field_quote`, `field_attribution`, `field_image` | Pull quote |
| `accordion` | `field_items` (paragraph ref) | Accordion wrapper |
| `accordion_item` | `field_title`, `field_body` | Single accordion panel |
| `gallery` / `image_gallery` | `field_images` (image or media ref, multi-value) | Image gallery |
| `video` | `field_video` (media ref or remote video URL) | Video embed |
| `slideshow` / `carousel` | `field_slides` (paragraph ref) | Rotating content |
| `slide` | `field_image`, `field_title`, `field_body`, `field_link` | Single slide |
| `embed` / `view_embed` | `field_view` (viewsreference) | Embedded view |
| `webform` | `field_webform` (entity ref to webform) | Embedded form |
| `map` | `field_location` (geofield or address) | Map embed |
| `table` | `field_table` (tablefield) | Data table |
| `timeline` | `field_items` (paragraph ref) | Timeline display |
| `testimonial` | `field_quote`, `field_author`, `field_image`, `field_role` | Testimonial |
| `stat` / `counter` | `field_number`, `field_label`, `field_icon` | Statistic counter |
| `logo_group` | `field_logos` (image or media ref) | Logo wall |
| `person` / `team_member` | `field_name`, `field_role`, `field_image`, `field_bio`, `field_links` | Staff profile |

## Resolving Paragraphs: SQL Queries

### Get all paragraphs for a node

```sql
-- First level: paragraphs directly on the node
SELECT
  p.id,
  p.type,
  p.parent_type,
  p.parent_id,
  p.parent_field_name,
  ref.delta
FROM paragraphs_item_field_data p
JOIN node__field_content_blocks ref
  ON ref.field_content_blocks_target_id = p.id
WHERE ref.entity_id = 42
  AND p.default_langcode = 1
ORDER BY ref.delta;
```

### Recursively resolve nested paragraphs

```sql
-- All paragraphs at any depth for a node, using parent tracking
WITH RECURSIVE tree AS (
  -- Root level: paragraphs whose parent is the node
  SELECT id, type, parent_type, parent_id, parent_field_name, 0 AS depth
  FROM paragraphs_item_field_data
  WHERE parent_type = 'node'
    AND parent_id = '42'
    AND default_langcode = 1

  UNION ALL

  -- Children: paragraphs whose parent is another paragraph in the tree
  SELECT p.id, p.type, p.parent_type, p.parent_id, p.parent_field_name, t.depth + 1
  FROM paragraphs_item_field_data p
  JOIN tree t ON p.parent_type = 'paragraph' AND p.parent_id = CAST(t.id AS CHAR)
  WHERE p.default_langcode = 1
    AND t.depth < 10  -- safety limit
)
SELECT * FROM tree ORDER BY depth, id;
```

### Reverse lookup: find the node that owns a paragraph

```sql
-- Walk up the parent chain until parent_type is not 'paragraph'
WITH RECURSIVE chain AS (
  SELECT id, parent_type, parent_id, parent_field_name
  FROM paragraphs_item_field_data
  WHERE id = 105 AND default_langcode = 1

  UNION ALL

  SELECT p.id, p.parent_type, p.parent_id, p.parent_field_name
  FROM paragraphs_item_field_data p
  JOIN chain c ON p.id = CAST(c.parent_id AS UNSIGNED)
  WHERE c.parent_type = 'paragraph'
    AND p.default_langcode = 1
)
SELECT parent_type, parent_id
FROM chain
WHERE parent_type != 'paragraph';
```

## Max Nesting Depth

There is no hard limit on paragraph nesting depth. In practice, most sites go 2-3 levels deep. Some patterns:

| Depth | Example |
|-------|---------|
| 1 | Node → Hero, Text, CTA |
| 2 | Node → Card Group → Card |
| 3 | Node → Section → Accordion → Accordion Item |
| 4+ | Rare. Node → Layout → Column → Card Group → Card |

Set a safety limit of 10 in recursive queries. If you hit it, the data is likely circular (a bug, not a feature).

## Asymmetric Translations

Paragraphs support asymmetric translations: different languages can have different paragraph structures. English might have 3 cards while French has 4.

When this is enabled:
- Each translation can add or remove paragraph references
- The `field_content_blocks` table may have different rows for different `langcode` values
- Paragraph entities themselves may or may not be translated

Check for asymmetric translations:

```sql
-- Compare paragraph counts across languages for a node
SELECT langcode, COUNT(*) as paragraph_count
FROM node__field_content_blocks
WHERE entity_id = 42
GROUP BY langcode;
```

## Migration Considerations

1. Always resolve the full paragraph tree before migrating a node. Flat extraction misses nested content.
2. Preserve delta ordering. It controls render order.
3. The `target_revision_id` in the reference field matters. It pins which version of the paragraph the node revision sees.
4. Paragraphs are not reusable by default. Each paragraph belongs to exactly one host entity. The `entity_reference_revisions` field type enforces this by tracking revisions.
5. If the site uses the `paragraphs_library` module (Paragraph Library), paragraphs can be reused. These are `paragraphs_library_item` entities referencing shared paragraphs.
6. Export paragraph type definitions from config to understand field structure: `paragraph.type.{bundle}` and `field.field.paragraph.{bundle}.{field_name}`.
