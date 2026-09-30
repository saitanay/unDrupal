# Skill 16: Blocks, Block Types, and Layout Builder

Export block types, block content, block placements, and Layout Builder configuration. This covers the two systems Drupal uses to place content into page regions: the block placement system (all versions) and Layout Builder (D8.6+).

Run Skill 01 (Site Audit) first. You need the Drupal version, the active theme(s), and whether Layout Builder is enabled.

### Related page builder skills

This skill covers the block placement system and Layout Builder. Drupal has other page building tools, each with its own export approach. Check which modules are enabled before choosing a skill.

| Module | Skill | When to use |
|---|---|---|
| Layout Builder (core D8.6+) | This skill (16) | Default core page builder. Sections, regions, blocks. |
| Experience Builder (core D11+) | Skill 33 | Canvas-based page builder replacing Layout Builder. Component-driven. |
| Site Studio / Cohesion (Acquia) | Skill 34 | Acquia's visual builder with its own component and style system. |
| Gutenberg (`gutenberg` module) | Skill 35 | WordPress-style block editor ported to Drupal. |

Detection: run `drush pm:list --status=enabled --format=list` and search for `layout_builder`, `experience_builder`, `cohesion`, or `gutenberg`. A site may have more than one enabled.

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Config directory** (YAML) | Block placements, block type definitions, Layout Builder defaults per view mode |
| **Drush** | Entity queries for block_content, Layout Builder field data, config export |
| **Database** | Full block_content field data, serialized Layout Builder sections, D7 block tables |
| **Admin UI** | Block layout page (`/admin/structure/block`), Layout Builder UI. Manual review only. |

---

## 1. Block Types (Custom Block Bundles)

Block types define reusable block structures. They work like content types but for blocks instead of nodes. A "Hero Banner" block type might have fields for heading, image, CTA link, and background color.

### 1a. Via Config YAML (D8+)

Block type definitions live in `block_content.type.{machine_name}.yml`:

```yaml
# block_content.type.hero_banner.yml
uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
langcode: en
status: true
dependencies: {}
id: hero_banner
label: 'Hero Banner'
description: 'Full-width banner with heading, image, and call to action.'
revision: 1
```

| Field | Meaning |
|---|---|
| `id` | Machine name of the block type |
| `label` | Human-readable name |
| `description` | Admin description shown on the block creation page |
| `revision` | Whether new revisions are created by default (1 = yes, 0 = no) |

Export all block type configs:

```bash
# From config sync directory
ls config/sync/block_content.type.*.yml

# Via Drush
drush config:list --prefix=block_content.type --format=list
```

### 1b. Via Drush

```bash
# List all block types
drush entity:list block_content_type --format=json
```

### 1c. Block Type Fields

Fields on block types follow the same storage/instance pattern as node fields (Skill 04). The config files use `block_content` as the entity type:

- **Field storage**: `field.storage.block_content.{field_name}.yml`
- **Field instance**: `field.field.block_content.{bundle}.{field_name}.yml`

```bash
# List all field instances for block_content
ls config/sync/field.field.block_content.*.yml

# Or via Drush
drush field:info --entity-type=block_content --format=json
```

Each block type also has display and form display config:

- `core.entity_view_display.block_content.{bundle}.{view_mode}.yml`
- `core.entity_form_display.block_content.{bundle}.default.yml`

Export these alongside the field definitions. The target platform needs both structure and presentation order.

---

## 2. Block Content Entities

Block content entities are the saved instances of each block type. A site might define one "Hero Banner" block type but create 15 hero banner blocks, each with different field values.

### 2a. Via Drush (D8+)

```bash
# Count all block_content entities
drush sql:query "SELECT type, COUNT(*) as count FROM block_content_field_data GROUP BY type"

# Export all block_content entities as JSON
drush php:eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('block_content');
  \$ids = \$storage->getQuery()->accessCheck(FALSE)->execute();
  \$blocks = \$storage->loadMultiple(\$ids);
  \$data = [];
  foreach (\$blocks as \$block) {
    \$data[] = [
      'id' => \$block->id(),
      'uuid' => \$block->uuid(),
      'type' => \$block->bundle(),
      'info' => \$block->label(),
      'langcode' => \$block->get('langcode')->value,
      'status' => \$block->isPublished(),
      'revision_id' => \$block->getRevisionId(),
      'fields' => [],
    ];
    foreach (\$block->getFieldDefinitions() as \$field_name => \$definition) {
      if (!\$definition->getFieldStorageDefinition()->isBaseField()) {
        \$data[count(\$data)-1]['fields'][\$field_name] = \$block->get(\$field_name)->getValue();
      }
    }
  }
  echo json_encode(\$data, JSON_PRETTY_PRINT);
"
```

### 2b. Via Database (D8+)

Block content uses two core tables:

| Table | Contents |
|---|---|
| `block_content` | Base table: `id`, `revision_id`, `type`, `uuid`, `langcode` |
| `block_content_field_data` | Data table: `id`, `revision_id`, `type`, `langcode`, `info` (admin label), `status`, `changed` |
| `block_content_revision` | Revision base: `id`, `revision_id`, `langcode`, `revision_default` |
| `block_content_field_revision` | Revision data: same columns as `block_content_field_data` plus `revision_translation_affected` |

Custom fields use dedicated tables named `block_content__{field_name}` with columns for `entity_id`, `revision_id`, `bundle`, `delta`, `langcode`, and field-type-specific value columns.

```sql
-- All block content with type and label
SELECT id, type, info, status, langcode, changed
FROM block_content_field_data
ORDER BY type, id;

-- Field values for a specific field
SELECT entity_id, delta, field_heading_value
FROM block_content__field_heading
ORDER BY entity_id, delta;
```

### 2c. D7 Custom Blocks

D7 stores custom blocks in the `block_custom` table:

```sql
SELECT bid, body, info, format
FROM block_custom;
```

| Column | Meaning |
|---|---|
| `bid` | Block ID (referenced as `delta` in the `block` table with `module = 'block'`) |
| `info` | Admin label |
| `body` | Block body content (HTML) |
| `format` | Text format machine name |

D7 custom blocks have no types and no custom fields. Each is a single blob of formatted text. The migration path is to map each D7 custom block to a `basic` block_content entity or a block type with a body field.

---

## 3. Block Placements

Block placements define which blocks appear in which theme regions, with what visibility rules. This is the "Block layout" page in the admin UI.

### 3a. Via Config YAML (D8+)

Each placement is a config entity in `block.block.{machine_name}.yml`:

```yaml
# block.block.olivero_site_branding.yml
uuid: 12345678-abcd-1234-efgh-567890abcdef
langcode: en
status: true
dependencies:
  module:
    - system
  theme:
    - olivero
id: olivero_site_branding
theme: olivero
region: header
weight: 0
provider: null
plugin: system_branding_block
settings:
  id: system_branding_block
  label: 'Site branding'
  label_display: '0'
  provider: system
  use_site_logo: true
  use_site_name: true
  use_site_slogan: false
visibility:
  request_path:
    id: request_path
    negate: false
    pages: "/admin\n/admin/*"
```

### Key Fields

| Field | Meaning |
|---|---|
| `id` | Machine name of the placement. Convention: `{theme}_{block_description}`. |
| `theme` | Which theme this placement belongs to. Each theme has its own set of placements. |
| `region` | Theme region where the block renders (`header`, `sidebar_first`, `content`, `footer`, etc.). |
| `weight` | Sort order within the region. Lower weight = higher in the region. |
| `plugin` | The block plugin ID. Identifies what kind of block this is (see below). |
| `provider` | Module that provides the block plugin. Often `null` for config-based blocks. |
| `status` | Whether the placement is active. |

### Block Plugin Types

The `plugin` field determines the block's source:

| Plugin pattern | What it is | Example |
|---|---|---|
| `system_branding_block` | Site logo, name, slogan | Core system block |
| `system_main_block` | Main page content | The primary content area |
| `system_breadcrumb_block` | Breadcrumb trail | Navigation breadcrumb |
| `system_messages_block` | Status messages | Drupal messages |
| `page_title_block` | Page title | H1 title |
| `local_tasks_block` | Tabs (primary/secondary) | View/Edit/Revisions tabs |
| `local_actions_block` | Action links | "Add content" button |
| `system_menu_block:{menu_id}` | Menu block | `system_menu_block:main`, `system_menu_block:footer` |
| `block_content:{uuid}` | Custom block (block_content entity) | `block_content:a1b2c3d4-...` |
| `views_block:{view_id}-{display_id}` | Views block display | `views_block:content_recent-block_1` |
| `field_block:node:{bundle}:{field}` | Field block (Layout Builder) | `field_block:node:article:body` |
| `extra_field_block:node:{bundle}:{field}` | Extra field (pseudo-field) | `extra_field_block:node:article:links` |
| `inline_block:{block_type}` | Inline block (Layout Builder) | `inline_block:hero_banner` |

### Visibility Conditions

The `visibility` map contains zero or more condition plugins. All conditions must pass for the block to show (AND logic). Each condition can be negated.

```yaml
visibility:
  # Show only on specific paths
  request_path:
    id: request_path
    negate: false
    pages: "/node/1\n/about\n/contact"
  # Show only for specific roles
  user_role:
    id: user_role
    roles:
      authenticated: authenticated
      content_editor: content_editor
    negate: false
    context_mapping:
      user: '@user.current_user_context:current_user'
  # Show only on specific content types
  entity_bundle:node:
    id: 'entity_bundle:node'
    bundles:
      article: article
      page: page
    negate: false
    context_mapping:
      node: '@node.node_route_context:node'
  # Show only for specific language
  language:
    id: language
    langcodes:
      en: en
    negate: false
    context_mapping:
      language: '@language.current_language_context:language_interface'
```

| Condition plugin | What it controls |
|---|---|
| `request_path` | URL path matching. One path per line. Supports `*` wildcard. `negate: true` hides on those paths. |
| `user_role` | Role-based visibility. Lists role machine names. |
| `entity_bundle:node` | Content type restriction. Block shows only on pages for the listed bundles. |
| `language` | Language restriction. Block shows only for listed language codes. |
| `node_type` | D8 legacy variant of `entity_bundle:node`. |

### 3b. Export All Placements

```bash
# List all block placement configs
ls config/sync/block.block.*.yml

# Via Drush, export as JSON
drush config:list --prefix=block.block --format=list | while read name; do
  echo "---"
  drush config:get "$name" --format=yaml
done

# Count placements per theme
grep -l "^theme:" config/sync/block.block.*.yml | xargs grep "^theme:" | \
  sed 's/.*theme: //' | sort | uniq -c | sort -rn
```

### 3c. D7 Block Placements

D7 stores all block placements in a single `block` table:

```sql
SELECT module, delta, theme, region, weight, status, visibility, pages, title, cache
FROM block
WHERE status = 1
ORDER BY theme, region, weight;
```

| Column | Meaning |
|---|---|
| `module` | Module providing the block (`block` for custom, `views` for Views blocks, `system` for system blocks, `menu` for menu blocks) |
| `delta` | Block identifier within the module. For `module = 'block'`, delta matches `block_custom.bid`. For `module = 'views'`, delta is `{view_name}-{display_id}`. For `module = 'menu'`, delta is the menu machine name. |
| `theme` | Theme machine name |
| `region` | Theme region (string like `sidebar_first`, `header`, `footer`, `-1` means disabled/hidden) |
| `weight` | Sort order within region |
| `status` | 1 = enabled, 0 = disabled |
| `visibility` | Path visibility mode: 0 = show on all except listed, 1 = show only on listed, 2 = PHP code |
| `pages` | Newline-separated page paths (or PHP code if `visibility = 2`) |
| `title` | Override title. Empty string = use default. `<none>` = hide title. |
| `cache` | Cache mode: -1 = no cache, 1 = per role, 2 = per page, 4 = global, 8 = per user |

D7 role-based visibility lives in a separate table:

```sql
SELECT module, delta, rid
FROM block_role;
```

If a block has rows in `block_role`, it shows only for those role IDs. No rows means visible to all roles.

D7 content-type visibility (contrib module `block_class` or core `block_node_type` in some versions):

```sql
-- If the block_node_type table exists
SELECT module, delta, type
FROM block_node_type;
```

---

## 4. Layout Builder

Layout Builder replaces the traditional block placement system for individual entities and content type defaults. Instead of placing blocks into theme regions, editors build layouts per page with configurable sections, columns, and blocks.

Layout Builder was added in Drupal 8.6 as experimental and became stable in 8.8.

### 4a. Check if Layout Builder Is Enabled

```bash
# Check module status
drush pm:list --filter=layout_builder --format=json

# Check which entity types/bundles use Layout Builder
grep -r "layout_builder" config/sync/core.entity_view_display.*.yml | grep "enabled: true"
```

Layout Builder is enabled per entity type, per bundle, per view mode. The setting lives in the `third_party_settings.layout_builder` section of entity view display config:

```yaml
# core.entity_view_display.node.article.default.yml
third_party_settings:
  layout_builder:
    enabled: true
    allow_custom: true
```

| Setting | Meaning |
|---|---|
| `enabled: true` | Layout Builder controls this display instead of the traditional field formatter list. |
| `allow_custom: true` | Editors can override the default layout on individual entities. Each node gets its own layout. |

### 4b. Default Layouts (Config YAML)

When Layout Builder is enabled for a view display, the layout is stored in the same entity view display config file under `third_party_settings.layout_builder.sections`:

```yaml
# core.entity_view_display.node.article.default.yml
third_party_settings:
  layout_builder:
    enabled: true
    allow_custom: true
    sections:
      - layout_id: layout_onecol
        layout_settings:
          label: 'Section 1'
        components:
          some-uuid-1111:
            uuid: some-uuid-1111
            region: content
            configuration:
              id: 'field_block:node:article:body'
              label: Body
              label_display: '0'
              provider: layout_builder
              context_mapping:
                entity: layout_builder.entity
            weight: 0
            additional: {}
          some-uuid-2222:
            uuid: some-uuid-2222
            region: content
            configuration:
              id: 'field_block:node:article:field_tags'
              label: Tags
              label_display: visible
              provider: layout_builder
              formatter:
                type: entity_reference_label
                settings:
                  link: true
                label: above
              context_mapping:
                entity: layout_builder.entity
            weight: 1
            additional: {}
      - layout_id: layout_twocol_section
        layout_settings:
          label: 'Section 2'
          column_widths: '67-33'
        components:
          some-uuid-3333:
            uuid: some-uuid-3333
            region: first
            configuration:
              id: 'inline_block:call_to_action'
              label: 'Call to Action'
              label_display: '0'
              provider: layout_builder
              block_serialized: null
              block_revision_id: '42'
            weight: 0
            additional: {}
```

### Section Structure

Each section in the `sections` array has:

| Field | Meaning |
|---|---|
| `layout_id` | The layout plugin. Core provides `layout_onecol`, `layout_twocol_section`, `layout_threecol_section`, `layout_fourcol_section`. Contrib adds more (Bootstrap layouts, custom layouts). |
| `layout_settings.label` | Admin label for the section. |
| `layout_settings.column_widths` | Column proportions for multi-column layouts: `50-50`, `67-33`, `33-67`, `25-50-25`, `25-25-25-25`, etc. |
| `components` | Map of block instances in this section, keyed by UUID. |

### Component Structure

Each component (block instance) within a section:

| Field | Meaning |
|---|---|
| `uuid` | Unique ID for this block instance. |
| `region` | Which column/region of the section layout: `content` (one-col), `first`/`second` (two-col), `first`/`second`/`third` (three-col). |
| `configuration.id` | Block plugin ID. Same patterns as block placements: `field_block:*`, `inline_block:*`, `views_block:*`, `system_branding_block`, etc. |
| `configuration.label` | Display label. |
| `configuration.label_display` | `'0'` to hide, `visible` to show. |
| `configuration.formatter` | For field blocks: formatter type, settings, and label position. |
| `configuration.block_revision_id` | For inline blocks: revision ID in `block_content` table. |
| `weight` | Sort order within the region. |

### 4c. Inline Blocks

Inline blocks are block_content entities created within Layout Builder. They are not reusable. They do not appear in the block library. They exist only in the context of the layout where they were placed.

Inline blocks use the `inline_block:{block_type}` plugin pattern. Their content is stored in the `block_content` table, but the `reusable` field is set to `0`:

```bash
# Find all non-reusable (inline) block_content entities
drush php:eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('block_content');
  \$ids = \$storage->getQuery()
    ->accessCheck(FALSE)
    ->condition('reusable', 0)
    ->execute();
  \$blocks = \$storage->loadMultiple(\$ids);
  foreach (\$blocks as \$block) {
    echo \$block->id() . ' | ' . \$block->bundle() . ' | ' . \$block->label() . PHP_EOL;
  }
"
```

```sql
-- Via database: inline blocks have reusable = 0
SELECT bc.id, bcd.type, bcd.info, bcd.status
FROM block_content AS bc
JOIN block_content_field_data AS bcd ON bc.id = bcd.id
WHERE bc.reusable = 0;
```

### 4d. Per-Entity Layout Overrides (Database)

When `allow_custom: true` is set, editors can override the default layout on individual nodes. These overrides are stored as a serialized PHP field on the entity.

The data lives in the `node__layout_builder__layout` table:

```sql
SELECT entity_id, revision_id, delta, langcode, layout_builder__layout_section
FROM node__layout_builder__layout
ORDER BY entity_id, delta;
```

| Column | Meaning |
|---|---|
| `entity_id` | Node ID |
| `revision_id` | Node revision ID |
| `delta` | Section index (0, 1, 2, ...) |
| `langcode` | Language code |
| `layout_builder__layout_section` | Serialized PHP object representing one section |

Each row holds one section. A node with three layout sections has three rows (delta 0, 1, 2).

The `layout_builder__layout_section` column contains a serialized `Drupal\layout_builder\Section` object. This object cannot be read with plain SQL. Extracting it requires PHP unserialization.

### Extracting Serialized Layout Data

**Option 1: Drush script (recommended)**

```bash
drush php:eval "
  \$nids = \Drupal::entityTypeManager()->getStorage('node')
    ->getQuery()
    ->accessCheck(FALSE)
    ->exists('layout_builder__layout')
    ->execute();
  \$nodes = \Drupal::entityTypeManager()->getStorage('node')->loadMultiple(\$nids);
  \$result = [];
  foreach (\$nodes as \$node) {
    \$sections = \$node->get('layout_builder__layout')->getSections();
    \$node_data = [
      'nid' => \$node->id(),
      'type' => \$node->bundle(),
      'title' => \$node->getTitle(),
      'sections' => [],
    ];
    foreach (\$sections as \$delta => \$section) {
      \$section_data = [
        'delta' => \$delta,
        'layout_id' => \$section->getLayoutId(),
        'layout_settings' => \$section->getLayoutSettings(),
        'components' => [],
      ];
      foreach (\$section->getComponents() as \$uuid => \$component) {
        \$section_data['components'][\$uuid] = [
          'region' => \$component->getRegion(),
          'plugin_id' => \$component->getPluginId(),
          'weight' => \$component->getWeight(),
          'configuration' => \$component->get('configuration'),
        ];
      }
      \$node_data['sections'][] = \$section_data;
    }
    \$result[] = \$node_data;
  }
  echo json_encode(\$result, JSON_PRETTY_PRINT);
"
```

**Option 2: Standalone PHP script (no Drush)**

If Drush is unavailable but you have database access and a Drupal bootstrap:

```php
<?php
// extract_layouts.php - run from Drupal root
use Drupal\Core\DrupalKernel;
use Symfony\Component\HttpFoundation\Request;

$autoloader = require_once 'autoload.php';
$request = Request::createFromGlobals();
$kernel = DrupalKernel::createFromRequest($request, $autoloader, 'prod');
$kernel->boot();
$kernel->preHandle($request);

$database = \Drupal::database();
$rows = $database->query("
  SELECT entity_id, delta, layout_builder__layout_section
  FROM {node__layout_builder__layout}
  ORDER BY entity_id, delta
")->fetchAll();

$result = [];
foreach ($rows as $row) {
  $section = unserialize($row->layout_builder__layout_section);
  $result[] = [
    'entity_id' => $row->entity_id,
    'delta' => $row->delta,
    'layout_id' => $section->getLayoutId(),
    'layout_settings' => $section->getLayoutSettings(),
    'components' => array_map(function ($component) {
      return [
        'region' => $component->getRegion(),
        'plugin_id' => $component->getPluginId(),
        'weight' => $component->getWeight(),
        'configuration' => $component->get('configuration'),
      ];
    }, $section->getComponents()),
  ];
}

echo json_encode($result, JSON_PRETTY_PRINT);
```

**Option 3: Raw database dump (no PHP)**

If you have no PHP runtime, dump the raw serialized data for post-processing:

```sql
SELECT entity_id, delta,
  CAST(layout_builder__layout_section AS CHAR) as section_serialized
FROM node__layout_builder__layout
ORDER BY entity_id, delta;
```

The serialized string follows PHP's serialize format. Parse it with any language that has a PHP serialization library (Python: `phpserialize`, Node: `php-serialize`, Ruby: `php_serialize`).

### 4e. Layout Builder on Other Entity Types

Layout Builder works on any fieldable entity type, not just nodes. Check for layout fields on:

- `block_content` (block types with Layout Builder)
- `taxonomy_term` (taxonomy terms with layouts)
- `media` (media entities with layouts)
- `commerce_product` (Commerce products)
- Custom entity types

```bash
# Find all entity types with Layout Builder enabled
grep -rl "layout_builder" config/sync/core.entity_view_display.*.yml | \
  xargs grep -l "enabled: true"

# Check for layout override tables
drush sql:query "SHOW TABLES LIKE '%layout_builder__layout%'"
```

The table naming pattern is `{entity_type}__layout_builder__layout`. For nodes: `node__layout_builder__layout`. For taxonomy terms: `taxonomy_term__layout_builder__layout`.

---

## 5. Layout Builder Contrib Modules

Several contrib modules extend Layout Builder. Check for these and export their config:

| Module | What it adds |
|---|---|
| `layout_builder_restrictions` | Restricts which blocks/layouts are available per content type. Config: `layout_builder_restrictions.restrictions.*.yml` |
| `layout_builder_styles` | Adds style selection per block/section (CSS classes). Config: `layout_builder_styles.style.*.yml` |
| `layout_builder_modal` | Changes the block selection UX to a modal dialog |
| `layout_builder_st` | Symmetric translations for Layout Builder |
| `layout_builder_component_attributes` | Adds HTML attributes (class, id) to individual components |
| `layout_library` | Reusable layout templates that can be applied to entities |
| `section_library` | Save and reuse sections across entities |
| `bootstrap_layout_builder` | Bootstrap grid layout plugins with responsive column options |

```bash
# Check which Layout Builder contrib modules are installed
drush pm:list --filter="layout_builder" --status=enabled --format=json
```

Export their configuration alongside the core Layout Builder data:

```bash
# Example: layout_builder_restrictions
ls config/sync/layout_builder_restrictions.*.yml

# Example: layout_builder_styles
ls config/sync/layout_builder_styles.style.*.yml
```

---

## 6. Single Directory Components (SDC)

SDC landed in Drupal 10.1 core. Each component is a self-contained directory inside a theme or module's `components/` folder. A `*.component.yml` file defines the component's name, props (typed inputs), and slots (named insertion points for child content).

SDC components are the building blocks for Layout Builder and Experience Builder. Exporting them documents the component contracts your target platform needs to replicate.

### 6a. Discovery

Find all component definitions in the codebase:

```bash
# All component.yml files across themes and modules
find web/themes web/modules -name '*.component.yml' -type f

# Or from Drupal root if paths differ
find . -path '*/components/*.component.yml' -type f
```

### 6b. Component YAML Structure

Each `*.component.yml` file defines one component:

```yaml
name: Card
status: stable
props:
  type: object
  properties:
    title:
      type: string
      title: Card Title
    image:
      type: string
      title: Image URL
    link:
      type: object
      properties:
        url: { type: string }
        text: { type: string }
slots:
  body:
    title: Card Body
```

| Field | Meaning |
|---|---|
| `name` | Human-readable component name |
| `status` | `stable`, `experimental`, or `deprecated` |
| `props` | JSON Schema object defining typed inputs. Supported types: `string`, `number`, `boolean`, `object`, `array`. Each prop can have validation rules (`enum`, `maxLength`, `required`). |
| `slots` | Named insertion points where child content or nested components go. Each slot has a `title` for the editor UI. |

The directory also contains the Twig template (`{component}.twig`), optional CSS (`{component}.css`), and optional JS (`{component}.js`).

### 6c. Export All SDC Definitions

```bash
# Dump every component.yml as a combined JSON array
drush php:eval "
  \$discovery = \Drupal::service('plugin.manager.sdc');
  \$definitions = \$discovery->getDefinitions();
  \$result = [];
  foreach (\$definitions as \$id => \$def) {
    \$result[\$id] = [
      'id' => \$id,
      'name' => \$def['name'] ?? \$id,
      'status' => \$def['status'] ?? 'stable',
      'props' => \$def['props'] ?? [],
      'slots' => \$def['slots'] ?? [],
      'provider' => \$def['provider'] ?? '',
      'path' => \$def['path'] ?? '',
    ];
  }
  echo json_encode(\$result, JSON_PRETTY_PRINT);
"
```

If Drush is unavailable, parse the YAML files directly. Each `*.component.yml` is standalone and needs no PHP to read.

### 6d. Migration Mapping

SDC definitions map directly to component interfaces on the target platform:

| SDC concept | Target platform equivalent |
|---|---|
| `props.properties` | Component prop types (React `PropTypes`/TypeScript interface, Vue `defineProps`, Svelte `export let`) |
| `props.properties.{name}.type` | Prop type annotation (`string`, `number`, `boolean`) |
| `props.properties.{name}.enum` | Union type or enum constraint |
| `slots` | Children/slot system (React `children`/named slots, Vue `<slot name="...">`, Svelte `<slot name="...">`) |
| `status: deprecated` | Mark component for removal in the target codebase |
| Component Twig template | Component render template. Rewrite Twig to JSX/Vue SFC/Svelte markup. |
| Component CSS file | Scoped styles. Map to CSS modules, styled-components, or framework scoping. |

The prop schema is the most valuable artifact. It tells you exactly what data each component accepts, with types and constraints, without reading the Twig template.

---

## 7. Complete Export Script

This script exports everything covered in this skill into a single JSON file:

```bash
drush php:eval "
  \$export = ['block_types' => [], 'block_content' => [], 'placements' => [], 'layout_builder' => []];

  // 1. Block types
  \$types = \Drupal::entityTypeManager()->getStorage('block_content_type')->loadMultiple();
  foreach (\$types as \$type) {
    \$export['block_types'][\$type->id()] = [
      'id' => \$type->id(),
      'label' => \$type->label(),
      'description' => \$type->getDescription(),
    ];
  }

  // 2. Block content entities (reusable and inline)
  \$storage = \Drupal::entityTypeManager()->getStorage('block_content');
  \$ids = \$storage->getQuery()->accessCheck(FALSE)->execute();
  \$blocks = \$storage->loadMultiple(\$ids);
  foreach (\$blocks as \$block) {
    \$fields = [];
    foreach (\$block->getFieldDefinitions() as \$fname => \$def) {
      if (!\$def->getFieldStorageDefinition()->isBaseField()) {
        \$fields[\$fname] = \$block->get(\$fname)->getValue();
      }
    }
    \$export['block_content'][] = [
      'id' => \$block->id(),
      'uuid' => \$block->uuid(),
      'type' => \$block->bundle(),
      'info' => \$block->label(),
      'reusable' => (bool) \$block->get('reusable')->value,
      'fields' => \$fields,
    ];
  }

  // 3. Block placements
  \$placements = \Drupal::entityTypeManager()->getStorage('block')->loadMultiple();
  foreach (\$placements as \$placement) {
    \$export['placements'][\$placement->id()] = [
      'id' => \$placement->id(),
      'theme' => \$placement->getTheme(),
      'region' => \$placement->getRegion(),
      'weight' => \$placement->getWeight(),
      'plugin' => \$placement->getPluginId(),
      'settings' => \$placement->get('settings'),
      'visibility' => \$placement->getVisibility(),
    ];
  }

  // 4. Layout Builder: per-entity overrides
  if (\Drupal::moduleHandler()->moduleExists('layout_builder')) {
    \$nids = \Drupal::entityTypeManager()->getStorage('node')
      ->getQuery()->accessCheck(FALSE)
      ->exists('layout_builder__layout')
      ->execute();
    \$nodes = \Drupal::entityTypeManager()->getStorage('node')->loadMultiple(\$nids);
    foreach (\$nodes as \$node) {
      \$sections = \$node->get('layout_builder__layout')->getSections();
      \$section_data = [];
      foreach (\$sections as \$section) {
        \$components = [];
        foreach (\$section->getComponents() as \$uuid => \$comp) {
          \$components[\$uuid] = [
            'region' => \$comp->getRegion(),
            'plugin_id' => \$comp->getPluginId(),
            'weight' => \$comp->getWeight(),
            'configuration' => \$comp->get('configuration'),
          ];
        }
        \$section_data[] = [
          'layout_id' => \$section->getLayoutId(),
          'layout_settings' => \$section->getLayoutSettings(),
          'components' => \$components,
        ];
      }
      \$export['layout_builder'][] = [
        'nid' => \$node->id(),
        'type' => \$node->bundle(),
        'title' => \$node->getTitle(),
        'sections' => \$section_data,
      ];
    }
  }

  echo json_encode(\$export, JSON_PRETTY_PRINT);
" > blocks_layouts_export.json
```

---

## 8. Migration Mapping

### What the Target Platform Needs

| Drupal concept | Target platform equivalent |
|---|---|
| Block type (bundle) | Component type or widget definition with typed fields |
| Block content entity | Component instance with populated field values |
| Block placement + region | Layout slot assignment, widget zone, or template region |
| Visibility conditions | Routing rules, conditional rendering logic, audience targeting |
| Layout Builder section | Page section or row in a page builder |
| Layout Builder component | Widget or component instance within a section |
| Inline block | Embedded component (not in a shared library) |
| Column widths (`67-33`) | Grid column spans (e.g., `col-8 col-4` in a 12-column grid) |
| Layout Builder default | Content type template or default page layout |
| Layout Builder override | Per-page custom layout |

### D7 to D8+ Mapping

| D7 concept | D8+ equivalent |
|---|---|
| `block` table placement | `block.block.*.yml` config entity |
| `block_custom` table | `block_content` entity with `basic` bundle |
| `module` + `delta` | `plugin` field on block config |
| `visibility` + `pages` columns | `visibility.request_path` condition |
| `block_role` table | `visibility.user_role` condition |
| `block_node_type` table | `visibility.entity_bundle:node` condition |
| No equivalent | Layout Builder (new in D8.6) |

### Common Pitfalls

1. **Theme-specific placements.** Each theme has independent block placements. Switching themes does not carry block assignments. Export placements for every active theme, not just the default.

2. **Disabled blocks.** D7 stores disabled blocks with `region = -1`. D8+ stores them with `region: -1` or removes them from config. Check for disabled placements that editors might re-enable.

3. **Serialized Layout Builder data.** The `layout_builder__layout_section` column is not human-readable. You must unserialize it through PHP or a compatible library. Do not attempt regex extraction.

4. **Inline blocks are orphans.** Inline blocks are not referenced by UUID in block placements. They exist only in Layout Builder section data. If you export block_content entities without checking the Layout Builder context, you will have inline blocks with no apparent owner.

5. **Revision-aware extraction.** Layout Builder overrides are revision-aware. The `node_revision__layout_builder__layout` table holds historical layouts. Export the current default revision unless the migration specifically needs revision history.

6. **Block placement config per environment.** Block placements are config entities. They may differ between environments if config is not fully synced. Export from the production database or production config directory.
