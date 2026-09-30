# Skill 33: Experience Builder (XB)

Extract content, component trees, and configuration from Drupal's Experience Builder. XB is Drupal's next-generation page builder, shipping as a contributed module for Drupal 11 under the Starshot initiative. It replaces Layout Builder long-term with a canvas-style drag-and-drop interface built on React, using Single Directory Components (SDC) as its component source.

XB is still pre-1.0. Its data model has changed multiple times since mid-2024 and will change again. Pin your extraction to the exact XB version on the source site. This skill documents the architecture as of mid-2025 (0.x branch).

Run Skill 01 (Site Audit) first. You need the Drupal version, active theme(s), and which page-building modules are enabled.

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Config directory** (YAML) | Component config entities, ContentTemplate definitions, PageRegion configs, field definitions |
| **Drush** | Module status, config export, entity queries, component tree field data |
| **Database** | Raw component tree storage (tree, inputs columns), revision data, dependency tracking |
| **Admin UI** | Component listing (`/admin/appearance/component`), XB editor on content |

---

## 1. Detection

XB and Layout Builder can coexist on the same site. Check which systems are active.

### 1a. Module Status

```bash
# Is XB enabled?
drush pm:list --status=enabled --filter=experience_builder --format=json

# Is Layout Builder also enabled?
drush pm:list --status=enabled --filter=layout_builder --format=json

# Check XB version
drush pm:list --filter=experience_builder --fields=version --format=list
```

The module machine name is `experience_builder`. The config prefix is `experience_builder.*`.

### 1b. Which Content Types Use XB vs Layout Builder

XB uses a custom field type (`experience_builder_component_tree`) on content entities. Layout Builder uses third-party settings on EntityViewDisplay config. They target different storage mechanisms.

```bash
# Find all fields using XB's field type
drush field:info --entity-type=node --format=json | grep -i "experience_builder\|component_tree"

# Check for XB field instances in config
ls config/sync/field.field.*.field_xb*.yml 2>/dev/null
ls config/sync/field.storage.*.field_xb*.yml 2>/dev/null

# Check for Layout Builder on view displays
grep -l "layout_builder" config/sync/core.entity_view_display.*.yml
```

### 1c. Content Templates

XB introduces `ContentTemplate` config entities. These define default component trees per content-type, bundle, and view mode. They replace the role that EntityViewDisplay plays in Layout Builder.

```bash
# List all ContentTemplate config entities
drush config:list --prefix=experience_builder.content_template --format=list

# Export one
drush config:get experience_builder.content_template.node.article.default --format=yaml
```

A ContentTemplate config entity looks like:

```yaml
id: node.article.default
content_entity_type_id: node
content_entity_type_bundle: article
content_entity_type_view_mode: default
component_tree: { ... }
exposed_content_type_slots:
  hero_area:
    label: 'Hero Area'
    subtree:
      instance: 28bcab26-e434-4ad4-9eaf-0520bdb32fcc
      slot_name: content
```

| Field | Meaning |
|---|---|
| `id` | `{entity_type}.{bundle}.{view_mode}` |
| `component_tree` | The default component tree (JSON structure) |
| `exposed_content_type_slots` | Named regions where content editors can override the template |

### 1d. Page Regions and Page Templates

XB can also control site chrome (headers, footers, sidebars) through `PageRegion` and `PageTemplate` config entities.

```bash
# Page regions
drush config:list --prefix=experience_builder.page_region --format=list

# Page templates
drush config:list --prefix=experience_builder.page_template --format=list
```

---

## 2. Component Model

XB uses three component sources: Single Directory Components (SDC), Code Components (JavaScript/React), and Block plugins. Each gets a `Component` config entity.

### 2a. Component Config Entities

Every component available in XB is a `Component` config entity with ID prefix `experience_builder.component.`:

```bash
# List all XB component config entities
drush config:list --prefix=experience_builder.component --format=list

# Count by source type
drush config:list --prefix=experience_builder.component.sdc --format=list | wc -l
drush config:list --prefix=experience_builder.component.block --format=list | wc -l
drush config:list --prefix=experience_builder.component.js --format=list | wc -l
```

A Component config entity:

```yaml
# experience_builder.component.sdc.my_theme.hero_banner.yml
id: sdc.my_theme.hero_banner
label: 'Hero Banner'
category: 'Content'
source: sdc
source_local_id: 'my_theme:hero-banner'
provider: my_theme
status: true
versioned_properties:
  current: a1b2c3d4e5f67890
  a1b2c3d4e5f67890:
    settings:
      local_source_id: 'my_theme:hero-banner'
      prop_field_definitions:
        heading:
          field_type: string
          field_widget: string_textfield
          field_storage_settings: {}
          field_instance_settings: {}
          default_value:
            - { value: 'Default heading' }
          expression: 'ℹ︎string␟value'
        image:
          field_type: image
          field_widget: image_image
          field_storage_settings: {}
          field_instance_settings: {}
          default_value: []
          expression: 'ℹ︎image␟{src↝entity...}'
    fallback_metadata:
      slots:
        content:
          title: 'Content'
```

Key fields:

| Field | Meaning |
|---|---|
| `source` | Component source plugin: `sdc`, `js`, or `block` |
| `source_local_id` | Provider-specific ID (e.g., `my_theme:hero-banner` for SDC) |
| `versioned_properties` | Contains versioned settings; `current` points to the active version hash |
| `prop_field_definitions` | Maps each SDC prop to a Drupal field type, widget, and default value |
| `fallback_metadata.slots` | Slot definitions extracted from the SDC metadata |

### 2b. SDC Component Definitions

SDC components live in `components/` directories inside themes or modules. Each component is a directory containing at minimum:

- `{name}.component.yml` (metadata, props schema, slots)
- `{name}.twig` (template)
- Optional: `{name}.css`, `{name}.js`, images, etc.

```bash
# Find all SDC component definitions
find web/themes web/modules -name "*.component.yml" -not -path "*/node_modules/*"
```

A typical `*.component.yml`:

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Hero Banner
status: stable
group: Content

props:
  type: object
  required:
    - heading
  properties:
    heading:
      title: Heading
      type: string
      examples:
        - 'Welcome to our site'
    image:
      title: Hero Image
      $ref: json-schema-definitions://experience_builder.module/image
      type: object
    style:
      title: Style Variant
      type: string
      enum:
        - primary
        - secondary
        - dark

slots:
  content:
    title: Content
    description: 'Main content area below the heading'
```

**Props** are typed properties using JSON Schema. XB reads the schema and maps each prop to a Drupal field type for editing:

| JSON Schema type | XB field type mapping |
|---|---|
| `string` | `string` (StringTextfieldWidget) |
| `string` + `enum` | `list_string` (OptionsSelectWidget) |
| `integer` | `integer` (NumberWidget) |
| `number` | `float` (NumberWidget) |
| `boolean` | `boolean` (BooleanCheckboxWidget) |
| `string` + `format: uri` | `uri` (UriWidget) |
| `string` + `format: date` | `datetime` (DateTimeWidget) |
| `object` + `$ref: .../image` | `image` or `entity_reference` (MediaLibraryWidget if media_library installed) |
| `array` + `items: {type}` | Multi-value field of the items type |

**Slots** are named regions in the component template where child components or content can be placed. In Twig, they render as `{% block slot_name %}`:

```twig
<div class="hero-banner hero-banner--{{ style }}">
  <h1>{{ heading }}</h1>
  {% if image %}
    <img src="{{ image.src }}" alt="{{ image.alt }}">
  {% endif %}
  {% block content %}
    {# Child components placed here by XB #}
  {% endblock %}
</div>
```

### 2c. Code Components (JavaScript/React)

Code components are written in React with Tailwind CSS, stored as `JavaScriptComponent` config entities. They are created through the XB UI (not files).

```bash
# List JS/Code component configs
drush config:list --prefix=experience_builder.js_component --format=list

# Export one
drush config:get experience_builder.js_component.{id} --format=yaml
```

Code components store their source code (JSX, CSS) directly in config.

### 2d. Block Components

XB auto-creates `Component` config entities for eligible block plugins. These wrap existing Drupal blocks.

```bash
# List block-sourced components
drush config:list --prefix=experience_builder.component.block --format=list
```

---

## 3. Storage Format

XB stores component trees differently from Layout Builder. Layout Builder serializes PHP `Section` objects in a field column. XB uses a JSON-based data model with two main field properties: `tree` (structure) and `inputs` (prop values).

### 3a. The XB Field Type

XB defines `ComponentTreeItem` as a field type. Each field value stores:

| Column | Contains |
|---|---|
| `tree` | JSON: the component tree structure (parent-child nesting via slots) |
| `inputs` | JSON: prop values for each component instance |

After mid-2025 refactoring, each component instance in a tree gets its own row in the field data table, with these columns per row:

| Column | Contains |
|---|---|
| `component_id` | Reference to the `Component` config entity ID |
| `version` | Hash of the component version used when this instance was created |
| `parent_id` | UUID of the parent component instance (or root UUID) |
| `slot` | Slot name in the parent where this instance is placed |
| `uuid` | Unique ID for this component instance |
| `inputs` | JSON: the prop values for this instance |

### 3b. Component Tree Structure

The tree is a nested structure. Each component instance has a UUID, a component ID, and placement information (parent + slot):

```json
{
  "ROOT_UUID": {
    "component": "root",
    "slots": {
      "root": ["uuid-1", "uuid-2"]
    }
  },
  "uuid-1": {
    "component": "sdc.my_theme.two_column",
    "slots": {
      "left": ["uuid-3"],
      "right": ["uuid-4"]
    }
  },
  "uuid-3": {
    "component": "sdc.my_theme.hero_banner"
  },
  "uuid-4": {
    "component": "block.system_branding_block"
  }
}
```

The root is a hardcoded UUID constant (`ComponentTreeStructure::ROOT_UUID`).

### 3c. Component Inputs (Prop Values)

Each component instance stores its prop values as inputs. There are multiple source types:

**StaticPropSource**: Fixed values stored inline.

```json
{
  "heading": {
    "sourceType": "static:field_item:string",
    "value": "Welcome",
    "expression": "ℹ︎string␟value"
  }
}
```

After component versioning (mid-2025), static inputs are simplified to just the value:

```json
{
  "heading": "Welcome",
  "style": "primary"
}
```

The field type, widget, and expression details are looked up from the referenced component version.

**DynamicPropSource**: Values pulled from the host entity's fields.

```json
{
  "image": {
    "sourceType": "dynamic",
    "expression": "ℹ︎␜entity:node:article␝field_hero␞␟{src↝entity...}"
  }
}
```

The expression syntax uses Unicode control characters as delimiters. The format is: `ℹ︎` (info) + entity type path + field name + field prop(s).

### 3d. Database Tables

For a node field named `field_xb_demo`:

```sql
-- Current data
SELECT * FROM node__field_xb_demo;

-- Revision data
SELECT * FROM node_revision__field_xb_demo;
```

Post-refactoring (one row per component instance), the table has columns like:
- `entity_id`, `revision_id`, `langcode`, `delta`
- `field_xb_demo_component_id`
- `field_xb_demo_version`
- `field_xb_demo_parent_id`
- `field_xb_demo_slot`
- `field_xb_demo_uuid`
- `field_xb_demo_inputs`

### 3e. Extracting Raw Component Trees

```bash
# Via Drush: export all article component trees
drush sql:query "SELECT entity_id, revision_id, delta, \
  field_xb_demo_component_id, field_xb_demo_inputs \
  FROM node__field_xb_demo ORDER BY entity_id, delta"

# Export as JSON via entity load
drush php:eval "
  \$nodes = \Drupal::entityTypeManager()->getStorage('node')->loadByProperties(['type' => 'article']);
  foreach (\$nodes as \$node) {
    if (\$node->hasField('field_xb_demo')) {
      echo json_encode([
        'nid' => \$node->id(),
        'tree' => \$node->get('field_xb_demo')->getValue(),
      ], JSON_PRETTY_PRINT) . PHP_EOL;
    }
  }
"
```

---

## 4. Per-Entity Overrides vs Default Layouts

XB separates defaults from overrides using ContentTemplate config entities and the XB field on content entities.

### How It Works

1. A **ContentTemplate** defines the default component tree for a content type + view mode.
2. ContentTemplates can expose **Content Type Slots**: named regions where editors can add/remove components per entity.
3. The content entity's XB field stores only the per-entity overrides (content placed in exposed slots).
4. At render time, XB merges the ContentTemplate tree with per-entity overrides.

If no ContentTemplate exists for a view mode, that view mode renders nothing from XB. If a ContentTemplate has zero exposed slots, editors can only populate the entity's fields (structured data). They cannot modify the component tree.

This is different from Layout Builder, where per-entity overrides store the complete layout (a full copy).

### Extracting Defaults and Overrides

```bash
# Default tree for article (full view mode)
drush config:get experience_builder.content_template.node.article.default \
  --format=yaml

# Per-entity data (overrides in exposed slots)
drush sql:query "SELECT entity_id, field_xb_demo_inputs \
  FROM node__field_xb_demo WHERE bundle = 'article'"
```

---

## 5. Component Library Extraction

### 5a. Enumerate All Components

```bash
# Full component listing with source type and status
drush php:eval "
  \$components = \Drupal::entityTypeManager()
    ->getStorage('experience_builder_component')
    ->loadMultiple();
  foreach (\$components as \$component) {
    echo implode(' | ', [
      \$component->id(),
      \$component->label(),
      \$component->get('source'),
      \$component->status() ? 'enabled' : 'disabled',
    ]) . PHP_EOL;
  }
"
```

### 5b. Extract Prop Schemas for All SDC Components

```bash
# Dump prop schemas from component.yml files
find web/themes web/modules -name "*.component.yml" \
  -not -path "*/node_modules/*" \
  -exec echo "=== {} ===" \; \
  -exec cat {} \;
```

### 5c. Extract Prop-to-Field Mappings from Config

The `prop_field_definitions` in each Component config entity tells you how XB maps each SDC prop to a Drupal field type:

```bash
# Export all SDC component configs
for f in config/sync/experience_builder.component.sdc.*.yml; do
  echo "=== $(basename $f) ==="
  grep -A 50 "prop_field_definitions:" "$f"
  echo ""
done
```

### 5d. Slot Definitions

```bash
# Extract slot definitions from component YAMLs
find web/themes web/modules -name "*.component.yml" \
  -not -path "*/node_modules/*" \
  -exec grep -l "^slots:" {} \; | while read f; do
  echo "=== $f ==="
  sed -n '/^slots:/,/^[^ ]/p' "$f"
done
```

---

## 6. Asset Extraction

### 6a. CSS and JS per Component

SDC bundles assets with the component. Files named `{component-name}.css` and `{component-name}.js` auto-attach.

```bash
# Find all SDC component assets
find web/themes web/modules -path "*/components/*" \
  \( -name "*.css" -o -name "*.js" -o -name "*.twig" \) \
  -not -path "*/node_modules/*" | sort
```

### 6b. Library Overrides

Components can declare extra dependencies or override library settings in their `*.component.yml`:

```yaml
libraryOverrides:
  dependencies:
    - core/drupal
    - core/once
  js:
    my-component.js: { attributes: { defer: true } }
```

```bash
# Find components with library overrides
grep -rl "libraryOverrides:" web/themes/*/components/ web/modules/*/components/
```

### 6c. Code Component Assets

Code components (React/JSX) store their code in config. CSS lives in `JavaScriptComponent` config entities and in `AssetLibrary` config entities:

```bash
# Export code component source
drush config:list --prefix=experience_builder.js_component --format=list | while read name; do
  drush config:get "$name" --format=yaml
done

# Global CSS asset libraries
drush config:list --prefix=experience_builder.asset_library --format=list
```

---

## 7. Export Approach

XB is new. No established migration tools exist yet. Extraction is manual.

### 7a. Full Config Export

```bash
# Export all XB config
drush config:export --destination=/tmp/xb-export

# Filter XB-specific config
ls /tmp/xb-export/experience_builder.* 2>/dev/null
ls /tmp/xb-export/field.field.*.field_xb*.yml 2>/dev/null
ls /tmp/xb-export/field.storage.*.field_xb*.yml 2>/dev/null
```

### 7b. Content Export Script

```php
<?php
/**
 * Export all XB component trees from content entities.
 * Run with: drush php:script export_xb_trees.php
 */

$field_map = \Drupal::service('entity_field.manager')
  ->getFieldMapByFieldType('experience_builder_component_tree');

$export = [];

foreach ($field_map as $entity_type_id => $fields) {
  foreach ($fields as $field_name => $field_info) {
    foreach ($field_info['bundles'] as $bundle) {
      $storage = \Drupal::entityTypeManager()->getStorage($entity_type_id);
      $ids = $storage->getQuery()
        ->condition('type', $bundle)
        ->accessCheck(FALSE)
        ->execute();

      foreach ($storage->loadMultiple($ids) as $entity) {
        $field_values = $entity->get($field_name)->getValue();
        if (!empty($field_values)) {
          $export[] = [
            'entity_type' => $entity_type_id,
            'bundle' => $bundle,
            'id' => $entity->id(),
            'label' => $entity->label(),
            'field_name' => $field_name,
            'component_tree' => $field_values,
          ];
        }
      }
    }
  }
}

file_put_contents('/tmp/xb_trees.json', json_encode($export, JSON_PRETTY_PRINT));
echo "Exported " . count($export) . " entities to /tmp/xb_trees.json\n";
```

### 7c. SDC Component Export Script

```bash
#!/bin/bash
# Export all SDC components with their assets
OUTPUT_DIR="/tmp/xb-components"
mkdir -p "$OUTPUT_DIR"

find web/themes web/modules -path "*/components/*" -name "*.component.yml" \
  -not -path "*/node_modules/*" | while read yml; do
  COMP_DIR=$(dirname "$yml")
  COMP_NAME=$(basename "$COMP_DIR")
  cp -r "$COMP_DIR" "$OUTPUT_DIR/$COMP_NAME"
  echo "Exported: $COMP_NAME"
done

echo "Components exported to $OUTPUT_DIR"
```

---

## 8. Target Platform Mapping

### 8a. XB Components to React/Vue/Svelte

SDC components map almost directly to frontend framework components. The `*.component.yml` props schema becomes your component props interface.

| XB concept | React equivalent | Vue equivalent |
|---|---|---|
| SDC component | Functional component | SFC (.vue file) |
| Props (JSON Schema) | PropTypes / TypeScript interface | `defineProps()` with types |
| Slots | `{children}` or named render props | `<slot>` / named `<slot name="x">` |
| Twig template | JSX return | `<template>` block |
| `*.component.css` | CSS module or styled-components | `<style scoped>` |
| `enum` prop | Union type literal | Validator array |

Example conversion from SDC to React:

```yaml
# hero-banner.component.yml
props:
  type: object
  required: [heading]
  properties:
    heading: { type: string, title: Heading }
    style: { type: string, enum: [primary, secondary, dark] }
slots:
  content: { title: Content }
```

```tsx
// HeroBanner.tsx
interface HeroBannerProps {
  heading: string;
  style?: 'primary' | 'secondary' | 'dark';
  children?: React.ReactNode; // the "content" slot
}

export function HeroBanner({ heading, style = 'primary', children }: HeroBannerProps) {
  return (
    <div className={`hero-banner hero-banner--${style}`}>
      <h1>{heading}</h1>
      {children && <div className="hero-banner__content">{children}</div>}
    </div>
  );
}
```

### 8b. XB Component Trees to Portable Text (Sanity)

XB's tree structure (parent UUID, slot, component ID, inputs) translates to Sanity's portable text blocks or custom object types.

| XB concept | Sanity equivalent |
|---|---|
| Component instance | Custom block type in portable text |
| Props (static) | Block fields |
| Slots with children | Nested portable text or array of references |
| DynamicPropSource | Sanity reference field |
| ContentTemplate | Document-level schema defaults |

### 8c. XB to WordPress Gutenberg Blocks

| XB concept | Gutenberg equivalent |
|---|---|
| SDC component | `registerBlockType()` |
| Props | Block attributes |
| Slots | `InnerBlocks` |
| Component tree | Serialized block HTML comments |
| ContentTemplate | Block template on post type |
| Exposed Content Type Slot | `InnerBlocks` with `templateLock: false` |

### 8d. XB to Headless CMS (Contentful, Storyblok)

| XB concept | Headless CMS equivalent |
|---|---|
| Component config entity | Content model / component schema |
| Prop field definitions | Field definitions on the model |
| Slots | Rich text field or nested component array |
| Component tree | Structured content tree (JSON) |
| ContentTemplate | Default content / template entry |
| Static prop values | Inline field values |
| Dynamic prop values | Reference fields to other entries |

---

## 9. XB vs Layout Builder Comparison

If the site uses both, or you are deciding which data to extract:

| Aspect | Layout Builder | Experience Builder |
|---|---|---|
| Storage | Serialized PHP Section objects | JSON (tree + inputs columns) |
| Component source | Block plugins only | SDC + Code Components + Block plugins |
| Field type | `layout_builder__layout` | `experience_builder_component_tree` |
| Per-entity overrides | Full copy of all sections | Only content for exposed slots |
| Default layouts | Third-party settings on EntityViewDisplay | ContentTemplate config entity |
| Config prefix | `core.entity_view_display.*` (third_party) | `experience_builder.content_template.*` |
| UI | Server-rendered, modal-based | React SPA, canvas-style |
| Status | Stable in core | Pre-1.0 contributed module |

---

## Cross-References

- **Skill 16** (blocks-layouts.md): Layout Builder extraction. XB is the successor. Sites may use both during transition.
- **Skill 12** (paragraphs-deep.md): Paragraphs is an alternative content building approach. XB aims to replace this use case too.
- **Skill 04** (content-types-fields.md): Field storage patterns. XB's prop-to-field mapping reuses core field types.
- **Skill 06** (display-modes.md): View modes. XB ContentTemplates replace EntityViewDisplay for XB-managed content types.
