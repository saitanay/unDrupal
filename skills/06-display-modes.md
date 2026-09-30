# Skill 6: Display Modes, Form Modes & Field Groups

Export view modes, form modes, entity view display config, entity form display config, and field group definitions. This is the layout blueprint for every entity type.

---

## Why This Matters

Display config tells the target platform how content is organized, prioritized, and presented. A "teaser" view mode defines which fields appear in listing pages. A "full" view mode defines the detail page. Form modes control editorial interfaces. Field groups define visual containers (tabs, accordions, fieldsets) that organize fields into logical sections.

Without this data, the target platform gets a flat list of fields with no hierarchy, no ordering, and no presentation context.

---

## What to Export

### View Modes

A view mode is a named display variant for an entity type. Core ships several. Contrib and custom modules add more.

Common view modes for nodes:
- `full` — detail page
- `teaser` — listing excerpt
- `search_result` — search results page
- `rss` — RSS feed output
- `search_index` — indexed text for search
- `token` — token replacement context

Custom view modes appear in `core.entity_view_mode.{entity_type}.{mode_name}.yml`.

**Config YAML**: `core.entity_view_mode.*.yml`

```yaml
# core.entity_view_mode.node.card.yml
langcode: en
status: true
dependencies:
  module:
    - node
id: node.card
label: Card
targetEntityType: node
cache: true
```

Key fields:
- `id` — `{entity_type}.{mode_name}`
- `label` — human-readable name
- `targetEntityType` — which entity type this mode applies to
- `status` — whether the mode is enabled

### Form Modes

Form modes work the same way but control entity edit forms instead of rendered output.

**Config YAML**: `core.entity_form_mode.*.yml`

```yaml
# core.entity_form_mode.node.quick_edit.yml
langcode: en
status: true
dependencies:
  module:
    - node
id: node.quick_edit
label: Quick edit
targetEntityType: node
cache: true
```

Most sites use only the `default` form mode. Sites with complex editorial workflows define additional form modes for simplified or role-specific editing interfaces.

### Entity View Display

This is the core export. One config object per entity type + bundle + view mode combination. It defines which fields are visible, their order, and their formatter settings.

**Config YAML**: `core.entity_view_display.{entity_type}.{bundle}.{view_mode}.yml`

```yaml
# core.entity_view_display.node.article.teaser.yml
langcode: en
status: true
dependencies:
  config:
    - field.field.node.article.body
    - field.field.node.article.field_image
    - field.field.node.article.field_tags
    - node.type.article
  module:
    - image
    - text
    - user
id: node.article.teaser
targetEntityType: node
bundle: article
mode: teaser
content:
  body:
    type: text_summary_or_trimmed
    label: hidden
    settings:
      trim_length: 200
    third_party_settings: {}
    weight: 1
    region: content
  field_image:
    type: image
    label: hidden
    settings:
      image_style: medium
      image_link: content
      image_loading:
        attribute: lazy
    third_party_settings: {}
    weight: 0
    region: content
hidden:
  field_tags: true
  links: true
```

Key fields per entry in `content`:
- `type` — formatter plugin ID (`text_summary_or_trimmed`, `image`, `entity_reference_label`, `entity_reference_entity_view`, etc.)
- `label` — `above`, `inline`, `hidden`, or `visually_hidden`
- `settings` — formatter-specific settings (trim length, image style, link behavior, view mode for referenced entities)
- `weight` — sort order (lower = higher on page)
- `region` — layout region (usually `content`; Layout Builder adds custom regions)
- `third_party_settings` — settings from contrib modules (field_group stores data here)

The `hidden` key lists fields excluded from this display.

### Entity Form Display

Same structure, but for edit forms. Controls which widget renders each field and in what order.

**Config YAML**: `core.entity_form_display.{entity_type}.{bundle}.{form_mode}.yml`

```yaml
# core.entity_form_display.node.article.default.yml
langcode: en
status: true
dependencies:
  config:
    - field.field.node.article.body
    - field.field.node.article.field_image
    - field.field.node.article.field_tags
    - node.type.article
  module:
    - image
    - text
id: node.article.default
targetEntityType: node
bundle: article
mode: default
content:
  title:
    type: string_textfield
    weight: -5
    region: content
    settings:
      size: 60
      placeholder: ''
    third_party_settings: {}
  body:
    type: text_textarea_with_summary
    weight: 1
    region: content
    settings:
      rows: 9
      summary_rows: 3
      placeholder: ''
      show_summary: false
    third_party_settings: {}
  field_image:
    type: image_image
    weight: 2
    region: content
    settings:
      progress_indicator: throbber
      preview_image_style: thumbnail
    third_party_settings: {}
  field_tags:
    type: entity_reference_autocomplete
    weight: 3
    region: content
    settings:
      match_operator: CONTAINS
      match_limit: 10
      size: 60
      placeholder: ''
    third_party_settings: {}
hidden:
  created: true
  promote: true
  status: true
  sticky: true
  uid: true
```

Key fields per entry in `content`:
- `type` — widget plugin ID (`string_textfield`, `text_textarea_with_summary`, `image_image`, `entity_reference_autocomplete`, `paragraphs`, `inline_entity_form_complex`, etc.)
- `weight` — field order in the form
- `region` — form region
- `settings` — widget-specific settings

### Field Groups (field_group module)

Field groups organize fields into visual containers. They exist as third-party settings on entity display config objects. The `field_group` module also stores standalone config entities.

**Config YAML**: `field_group.field_group.{context}.{entity_type}.{bundle}.{view_or_form_mode}.{group_name}.yml`

Where `{context}` is `group_` prefix applied to the group name in the config ID.

Actual file naming pattern:

```
field_group.field_group.group_main_content.node.article.default.yml
field_group.field_group.group_sidebar.node.article.default.yml
field_group.field_group.group_tabs.node.article.form.default.yml
```

```yaml
# field_group.field_group.group_main.node.article.default.yml
langcode: en
status: true
dependencies:
  config:
    - core.entity_view_display.node.article.default
  module:
    - field_group
    - node
id: group_main.node.article.default
label: 'Main content'
group_name: group_main
entity_type: node
bundle: article
mode: default
context: view
children:
  - body
  - field_image
  - field_tags
parent_name: group_tabs
weight: 0
format_type: tab
format_settings:
  classes: ''
  show_empty_fields: false
  id: ''
  formatter: open
  description: ''
  required_fields: true
region: content
```

Key fields:
- `group_name` — machine name (always starts with `group_`)
- `entity_type` + `bundle` + `mode` — which display this group belongs to
- `context` — `view` or `form`
- `children` — ordered list of field machine names or child group names contained in this group
- `parent_name` — parent group name for nested groups (empty string if top-level)
- `format_type` — the visual container type:
  - `fieldset` — bordered box with legend
  - `details` — collapsible HTML details element
  - `details_sidebar` — details element placed in sidebar region
  - `tabs` — horizontal or vertical tab container (must contain `tab` children)
  - `tab` — individual tab (must be child of `tabs`)
  - `accordion` — accordion container (must contain `accordion_item` children)
  - `accordion_item` — individual accordion panel
  - `html_element` — arbitrary HTML wrapper (div, section, article)
- `format_settings` — type-specific settings:
  - `formatter` — `open` or `closed` (for details/accordion items)
  - `direction` — `horizontal` or `vertical` (for tabs)
  - `classes` — CSS classes
  - `id` — HTML id attribute
  - `show_empty_fields` — render group when all children are empty
  - `required_fields` — mark group as required when it contains required fields
  - `description` — group description text
  - `label_element` — HTML element for label (h2, h3, span, etc., for html_element type)
  - `effect` — animation effect (for accordion)
- `weight` — sort order among siblings
- `region` — display region

Field groups also appear inside entity display configs as third-party settings:

```yaml
# Inside core.entity_form_display.node.article.default.yml
third_party_settings:
  field_group:
    group_tabs:
      children:
        - group_main
        - group_sidebar
      label: Tabs
      parent_name: ''
      region: content
      weight: 0
      format_type: tabs
      format_settings:
        direction: horizontal
        classes: ''
        id: ''
    group_main:
      children:
        - title
        - body
        - field_image
      label: 'Main content'
      parent_name: group_tabs
      region: content
      weight: 0
      format_type: tab
      format_settings:
        classes: ''
        formatter: open
        description: ''
        required_fields: true
```

---

## Access Patterns

### Pattern A: Config YAML Export (Best)

Requires Drush or file system access to the config sync directory.

```bash
# Export all config
drush config:export --destination=/tmp/drupal-config

# View modes
ls /tmp/drupal-config/core.entity_view_mode.*.yml

# Form modes
ls /tmp/drupal-config/core.entity_form_mode.*.yml

# Entity view displays
ls /tmp/drupal-config/core.entity_view_display.*.yml

# Entity form displays
ls /tmp/drupal-config/core.entity_form_display.*.yml

# Field groups
ls /tmp/drupal-config/field_group.field_group.*.yml
```

Count displays per entity type:

```bash
ls /tmp/drupal-config/core.entity_view_display.node.*.yml | \
  sed 's/.*display\.\(node\.[^.]*\)\..*/\1/' | sort | uniq -c | sort -rn
```

### Pattern B: Drush Config Get

Pull individual config objects when you know the names.

```bash
# List all view modes
drush config:list | grep core.entity_view_mode

# Get a specific view display
drush config:get core.entity_view_display.node.article.teaser

# Get a specific form display
drush config:get core.entity_form_display.node.article.default

# List all field groups
drush config:list | grep field_group.field_group

# Get a specific field group
drush config:get field_group.field_group.group_tabs.node.article.default
```

### Pattern C: Database Config Table

Query the `config` table for active config.

```sql
-- All view modes
SELECT name, CONVERT(data USING utf8) AS data
FROM config
WHERE name LIKE 'core.entity_view_mode.%';

-- All entity view displays
SELECT name, CONVERT(data USING utf8) AS data
FROM config
WHERE name LIKE 'core.entity_view_display.%';

-- All entity form displays
SELECT name, CONVERT(data USING utf8) AS data
FROM config
WHERE name LIKE 'core.entity_form_display.%';

-- All field groups
SELECT name, CONVERT(data USING utf8) AS data
FROM config
WHERE name LIKE 'field_group.field_group.%';

-- Form modes
SELECT name, CONVERT(data USING utf8) AS data
FROM config
WHERE name LIKE 'core.entity_form_mode.%';
```

The `data` column stores serialized PHP. Use `drush php:eval` to unserialize if you need readable output:

```bash
drush php:eval "
  \$rows = \Drupal::database()->select('config', 'c')
    ->fields('c', ['name', 'data'])
    ->condition('name', 'core.entity_view_display.%', 'LIKE')
    ->execute();
  foreach (\$rows as \$row) {
    echo \$row->name . \":\n\";
    print_r(unserialize(\$row->data));
    echo \"\n\";
  }
"
```

### Pattern D: Drush PHP Eval (Programmatic)

When you need structured output or cross-referencing.

```bash
# List all view modes per entity type
drush php:eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('entity_view_mode');
  \$modes = \$storage->loadMultiple();
  \$by_type = [];
  foreach (\$modes as \$mode) {
    \$by_type[\$mode->getTargetType()][] = [
      'id' => \$mode->id(),
      'label' => \$mode->label(),
      'status' => \$mode->status(),
    ];
  }
  echo json_encode(\$by_type, JSON_PRETTY_PRINT);
"

# List all form modes per entity type
drush php:eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('entity_form_mode');
  \$modes = \$storage->loadMultiple();
  \$by_type = [];
  foreach (\$modes as \$mode) {
    \$by_type[\$mode->getTargetType()][] = [
      'id' => \$mode->id(),
      'label' => \$mode->label(),
      'status' => \$mode->status(),
    ];
  }
  echo json_encode(\$by_type, JSON_PRETTY_PRINT);
"

# Full display config for a content type across all view modes
drush php:eval "
  \$displays = \Drupal::entityTypeManager()
    ->getStorage('entity_view_display')
    ->loadByProperties(['targetEntityType' => 'node', 'bundle' => 'article']);
  foreach (\$displays as \$display) {
    \$mode = \$display->getMode();
    \$components = \$display->getComponents();
    echo \"=== \$mode ===\n\";
    foreach (\$components as \$name => \$component) {
      echo \"  \$name: type=\" . (\$component['type'] ?? 'n/a')
        . \" weight=\" . \$component['weight']
        . \" label=\" . (\$component['label'] ?? 'n/a') . \"\n\";
    }
    echo \"\n\";
  }
"

# Export all display configs as JSON
drush php:eval "
  \$types = ['entity_view_display', 'entity_form_display'];
  \$result = [];
  foreach (\$types as \$type) {
    \$storage = \Drupal::entityTypeManager()->getStorage(\$type);
    foreach (\$storage->loadMultiple() as \$display) {
      \$result[\$type][\$display->id()] = [
        'entity_type' => \$display->getTargetEntityTypeId(),
        'bundle' => \$display->getTargetBundle(),
        'mode' => \$display->getMode(),
        'components' => \$display->getComponents(),
        'hidden' => array_keys(array_filter(\$display->toArray()['hidden'] ?? [])),
        'third_party' => \$display->getThirdPartySettings('field_group'),
      ];
    }
  }
  echo json_encode(\$result, JSON_PRETTY_PRINT);
" > /tmp/display-modes-export.json
```

### Pattern E: Drupal 7

D7 stores display config differently. Field display settings live inside field instance config, not separate display entities.

```sql
-- D7: Field instances contain display settings per view mode
SELECT fc.field_name, fci.bundle, fci.data
FROM field_config_instance fci
JOIN field_config fc ON fc.id = fci.field_id
WHERE fci.entity_type = 'node';
```

The `data` column is serialized PHP. The `display` key inside each instance contains per-view-mode formatter settings:

```php
// Inside unserialized field instance data
'display' => [
  'default' => [
    'label' => 'above',
    'type' => 'text_default',
    'weight' => 0,
    'settings' => [],
    'module' => 'text',
  ],
  'teaser' => [
    'label' => 'hidden',
    'type' => 'text_summary_or_trimmed',
    'weight' => 1,
    'settings' => ['trim_length' => 200],
    'module' => 'text',
  ],
],
```

D7 field_group stores config in the `field_group` table:

```sql
SELECT identifier, group_name, entity_type, bundle, mode, parent_name, data
FROM field_group
ORDER BY entity_type, bundle, mode, group_name;
```

---

## Export Procedure

### Step 1: Inventory View Modes and Form Modes

List all defined modes. Note which are enabled and which entity types use them.

```bash
drush config:list | grep -E 'core\.entity_(view|form)_mode\.' | sort
```

### Step 2: Map Displays to Bundles

For each entity type and bundle, list which view modes and form modes have display config.

```bash
# View displays per bundle
drush config:list | grep core.entity_view_display | \
  sed 's/core\.entity_view_display\.\([^.]*\)\.\([^.]*\)\.\(.*\)/\1.\2 → \3/' | sort

# Form displays per bundle
drush config:list | grep core.entity_form_display | \
  sed 's/core\.entity_form_display\.\([^.]*\)\.\([^.]*\)\.\(.*\)/\1.\2 → \3/' | sort
```

### Step 3: Export All Display Config

```bash
# Create output directory
mkdir -p /tmp/drupal-displays

# Export view modes
for f in $(drush config:list | grep core.entity_view_mode); do
  drush config:get "$f" --format=yaml > "/tmp/drupal-displays/${f}.yml"
done

# Export form modes
for f in $(drush config:list | grep core.entity_form_mode); do
  drush config:get "$f" --format=yaml > "/tmp/drupal-displays/${f}.yml"
done

# Export view displays
for f in $(drush config:list | grep core.entity_view_display); do
  drush config:get "$f" --format=yaml > "/tmp/drupal-displays/${f}.yml"
done

# Export form displays
for f in $(drush config:list | grep core.entity_form_display); do
  drush config:get "$f" --format=yaml > "/tmp/drupal-displays/${f}.yml"
done
```

### Step 4: Export Field Groups

```bash
# Check if field_group module is enabled
drush pm:list --status=enabled | grep field_group

# If enabled, export all field group configs
for f in $(drush config:list | grep field_group.field_group); do
  drush config:get "$f" --format=yaml > "/tmp/drupal-displays/${f}.yml"
done
```

### Step 5: Build Summary

Generate a summary of all display configurations per content type:

```bash
drush php:eval "
  \$entity_types = ['node', 'media', 'taxonomy_term', 'block_content', 'paragraph'];
  \$summary = [];

  foreach (\$entity_types as \$et) {
    // View displays
    \$displays = \Drupal::entityTypeManager()
      ->getStorage('entity_view_display')
      ->loadByProperties(['targetEntityType' => \$et]);
    foreach (\$displays as \$d) {
      \$bundle = \$d->getTargetBundle();
      \$mode = \$d->getMode();
      \$components = \$d->getComponents();
      \$hidden = array_keys(array_filter(\$d->toArray()['hidden'] ?? []));
      \$summary[\$et][\$bundle]['view'][\$mode] = [
        'visible_fields' => count(\$components),
        'hidden_fields' => count(\$hidden),
        'fields' => array_keys(\$components),
      ];
    }

    // Form displays
    \$forms = \Drupal::entityTypeManager()
      ->getStorage('entity_form_display')
      ->loadByProperties(['targetEntityType' => \$et]);
    foreach (\$forms as \$f) {
      \$bundle = \$f->getTargetBundle();
      \$mode = \$f->getMode();
      \$components = \$f->getComponents();
      \$hidden = array_keys(array_filter(\$f->toArray()['hidden'] ?? []));
      \$summary[\$et][\$bundle]['form'][\$mode] = [
        'visible_fields' => count(\$components),
        'hidden_fields' => count(\$hidden),
        'fields' => array_keys(\$components),
      ];
    }
  }

  echo json_encode(\$summary, JSON_PRETTY_PRINT);
" > /tmp/drupal-displays/summary.json
```

---

## Output Schema

Structure the export as JSON for the target platform:

```json
{
  "view_modes": {
    "node": [
      {"id": "node.full", "label": "Full content", "status": true},
      {"id": "node.teaser", "label": "Teaser", "status": true},
      {"id": "node.card", "label": "Card", "status": true}
    ],
    "media": [
      {"id": "media.full", "label": "Full", "status": true},
      {"id": "media.thumbnail", "label": "Thumbnail", "status": true}
    ]
  },
  "form_modes": {
    "node": [
      {"id": "node.default", "label": "Default", "status": true}
    ]
  },
  "view_displays": {
    "node.article.teaser": {
      "entity_type": "node",
      "bundle": "article",
      "mode": "teaser",
      "fields": {
        "field_image": {
          "formatter": "image",
          "label": "hidden",
          "weight": 0,
          "settings": {
            "image_style": "medium",
            "image_link": "content"
          }
        },
        "body": {
          "formatter": "text_summary_or_trimmed",
          "label": "hidden",
          "weight": 1,
          "settings": {"trim_length": 200}
        }
      },
      "hidden_fields": ["field_tags", "links"]
    }
  },
  "form_displays": {
    "node.article.default": {
      "entity_type": "node",
      "bundle": "article",
      "mode": "default",
      "fields": {
        "title": {
          "widget": "string_textfield",
          "weight": -5,
          "settings": {"size": 60}
        },
        "body": {
          "widget": "text_textarea_with_summary",
          "weight": 1,
          "settings": {"rows": 9, "summary_rows": 3}
        }
      },
      "hidden_fields": ["created", "promote", "status", "sticky", "uid"]
    }
  },
  "field_groups": {
    "node.article.form.default": [
      {
        "group_name": "group_tabs",
        "label": "Tabs",
        "format_type": "tabs",
        "parent": null,
        "children": ["group_main", "group_sidebar"],
        "weight": 0,
        "format_settings": {"direction": "horizontal"}
      },
      {
        "group_name": "group_main",
        "label": "Main content",
        "format_type": "tab",
        "parent": "group_tabs",
        "children": ["title", "body", "field_image"],
        "weight": 0,
        "format_settings": {"formatter": "open"}
      }
    ]
  }
}
```

---

## Migration Mapping

### View Modes to Target Concepts

| Drupal View Mode | Target Platform Equivalent |
|------------------|---------------------------|
| `full` | Detail page template / single post component |
| `teaser` | Card component / listing item / excerpt |
| `search_result` | Search result component |
| `rss` | RSS feed template / serializer |
| Custom modes (`card`, `hero`, `sidebar`) | Named component variants |

### Field Formatters to Target Rendering

| Drupal Formatter | What It Tells You |
|------------------|-------------------|
| `text_summary_or_trimmed` | Needs truncation logic with configurable length |
| `image` with `image_style` | Needs specific image dimensions/crop |
| `entity_reference_label` | Render as text link |
| `entity_reference_entity_view` with `view_mode` | Render referenced entity inline using specified mode |
| `daterange_default` | Date range display with format string |
| `link_default` | Render as anchor tag |
| `address_default` | Structured address display |

### Field Group Types to Target Layouts

| Drupal Group Type | Target Equivalent |
|-------------------|-------------------|
| `tabs` / `tab` | Tab component (React tabs, details+summary, etc.) |
| `accordion` / `accordion_item` | Accordion / collapsible sections |
| `fieldset` | Grouped section with heading |
| `details` | Collapsible section (HTML `<details>`) |
| `html_element` | Generic wrapper (div, section) |
| `details_sidebar` | Sidebar panel in edit form |

### Form Widget to Target Input

| Drupal Widget | Target Input Type |
|---------------|-------------------|
| `string_textfield` | `<input type="text">` |
| `text_textarea_with_summary` | Rich text editor with optional summary |
| `image_image` | File upload with image preview |
| `entity_reference_autocomplete` | Autocomplete / typeahead select |
| `options_select` | `<select>` dropdown |
| `options_buttons` | Radio buttons or checkboxes |
| `boolean_checkbox` | `<input type="checkbox">` |
| `datetime_default` | Date/time picker |
| `paragraphs` | Nested component builder |
| `inline_entity_form_complex` | Inline entity editor |
| `media_library_widget` | Media browser/picker |

---

## Edge Cases

**Layout Builder overrides**: Sites using Layout Builder store per-entity layout overrides in `node__layout_builder__layout` (or equivalent). These override the default view display entirely. Check for `layout_builder` in the `dependencies.module` list of view display configs. If present, Skill 16 (Blocks & Layouts) covers the detailed export.

**Hidden vs absent**: A field listed under `hidden` in a display config exists on the entity but is deliberately excluded from that view mode. A field not mentioned at all inherits default behavior (usually hidden). Both mean "not shown," but the distinction matters for understanding editorial intent.

**Multiple form modes**: Rare but important. Some sites use form modes to show different field sets to different roles. The form mode config alone does not tell you which roles see which form. That lives in permissions: `use {entity_type}.{form_mode} form mode`.

**Paragraph display modes**: Paragraphs have their own view displays. A paragraph referenced in a node's `full` view mode might render using a `preview` view mode for the paragraph entity. Check the `view_mode` setting in the `entity_reference_revisions_entity_view` formatter.

**Third-party settings beyond field_group**: Other modules store data in `third_party_settings` on display configs. Check for `ds` (Display Suite), `layout_builder`, `field_formatter_class`, and other display-altering modules.

**D7 differences**: D7 has no standalone display config entities. View mode settings are embedded in field instance config. D7 field_group stores data in a dedicated `field_group` database table, not in YAML config. The export approach changes, but the conceptual output stays the same.
