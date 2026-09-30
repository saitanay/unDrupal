# Skill 15: Menus, Menu Links, and Navigation

Export menu definitions, menu link trees, menu block placements, and breadcrumb configuration from a Drupal site. Produces a complete navigation map suitable for rebuilding site menus on any target platform.

Run Skill 01 (Site Audit) first. You need the Drupal version and available access methods before starting.

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Drush** | Menu list, menu link tree export, config export |
| **Database** | Full menu trees with all metadata, menu block placements, breadcrumb settings |
| **Config directory** (YAML) | Menu definitions (D8+). No link content. |
| **JSON:API** | Menu link content entities with pagination (D8+) |
| **Admin UI** | Manual review. Last resort. |

---

## Background: How Drupal Stores Menus

Drupal splits menu data into three layers:

1. **Menu definitions** — the menu itself (main, footer, account, custom menus). Machine name, label, description, locked status.
2. **Menu links** — individual entries in a menu. Title, URI, weight, parent, enabled/disabled, expanded. These form a tree.
3. **Menu block placements** — which menus render in which theme regions, with what depth and starting level.

D7 and D8+ store these differently.

### D7 Storage

Two tables:

- `menu_custom` — one row per menu. Columns: `menu_name`, `title`, `description`.
- `menu_links` — one row per link. Tree structure uses `plid` (parent link ID) and materialized depth columns (`p1` through `p9`). Mixes content menu links, system-generated links (from `hook_menu`), and Views-generated links in one table.

### D8+ Storage

Menu definitions are config entities: `system.menu.{machine_name}.yml`.

Menu links come from two sources:

- **Static links** — defined in `{module}.links.menu.yml` files. Modules declare menu items that point to routes. These live in code, not the database.
- **Content links** — `menu_link_content` entities stored in the database. These are the links site builders create through the admin UI. They are fieldable and translatable.

Both types merge into the `menu_tree` table at runtime. This table holds the computed tree structure for all menus, combining static and content links into one sorted hierarchy.

---

## 1. Menu Definitions

### 1a. Via Config YAML (D8+)

Menu definitions live in `system.menu.{machine_name}.yml`:

```yaml
uuid: 12345678-1234-1234-1234-123456789abc
langcode: en
status: true
dependencies: {  }
id: main
label: 'Main navigation'
description: 'Site section links'
locked: true
```

| Field | Meaning |
|---|---|
| `id` | Machine name. Used in code, templates, and block config. |
| `label` | Human-readable name shown in the admin UI. |
| `description` | Purpose of this menu. |
| `locked` | If `true`, the menu cannot be deleted through the admin UI. Core menus are locked. |

Standard menus shipped with core:

| Machine name | Label | Purpose |
|---|---|---|
| `main` | Main navigation | Primary site navigation. Typically placed in the header. |
| `footer` | Footer | Links shown in the site footer. |
| `account` | User account menu | Login, logout, my account links. |
| `admin` | Administration | Admin toolbar menu tree. |
| `tools` | Tools | Miscellaneous utility links (e.g. "Add content"). |

Export all menu definitions:

```bash
# From config sync directory
ls config/sync/system.menu.*.yml

# Via Drush
drush config:list --prefix=system.menu --format=list
```

To export each menu's YAML:

```bash
for menu in $(drush config:list --prefix=system.menu --format=list); do
  drush config:get "$menu" --format=yaml > "${menu}.yml"
done
```

### 1b. Via Database (D8+)

Menu definitions are config entities stored in the `config` table:

```sql
SELECT name, data FROM config
WHERE name LIKE 'system.menu.%'
ORDER BY name;
```

The `data` column is PHP-serialized. Unserialize each row to get the same structure as the YAML files.

### 1c. Via Database (D7)

```sql
SELECT menu_name, title, description
FROM menu_custom
ORDER BY menu_name;
```

D7 default menus:

| menu_name | title |
|---|---|
| `main-menu` | Main menu |
| `management` | Management |
| `navigation` | Navigation |
| `user-menu` | User menu |

Note the naming difference: D7 uses `main-menu`, D8+ uses `main`. D7 uses `user-menu`, D8+ uses `account`. Map these during migration.

---

## 2. Menu Links

### 2a. Via Config Export + Database (D8+)

Menu links in D8+ come from two sources. Both must be exported.

**Static links** (code-defined):

Modules declare static menu links in `{module}.links.menu.yml`:

```yaml
entity.node.canonical:
  title: 'View'
  route_name: entity.node.canonical
  menu_name: tools
  weight: 0
```

These do not live in the database. They are discovered from module files. To find them:

```bash
# Find all static menu link definitions
find /path/to/drupal -name "*.links.menu.yml" -exec echo "=== {} ===" \; -exec cat {} \;
```

Or via Drush:

```bash
drush eval "print_r(\Drupal::service('plugin.manager.menu.link')->getDefinitions());" > static_menu_links.txt
```

**Content links** (admin-created):

These are `menu_link_content` entities. They store in two main tables:

`menu_link_content_data` — the primary data table:

| Column | Meaning |
|---|---|
| `id` | Entity ID |
| `revision_id` | Revision ID |
| `bundle` | Always `menu_link_content` |
| `langcode` | Language code |
| `title` | Link text displayed in the menu |
| `description` | Tooltip/title attribute text |
| `menu_name` | Which menu this link belongs to |
| `link__uri` | Target URI. Internal routes use `internal:/path` or `entity:node/123`. External URLs stored as-is. `route:<nolink>` for non-linking parents. `route:<front>` for the front page. |
| `link__title` | Link title attribute (often empty, overlaps with `description`) |
| `link__options` | Serialized PHP array. Contains `query` (query parameters), `fragment` (URL hash), `attributes` (HTML attributes like class, target). |
| `external` | `1` if external URL, `0` if internal route |
| `rediscover` | Internal flag. Ignore for migration. |
| `weight` | Sort order within the same parent. Lower weight = higher position. |
| `expanded` | `1` = always show children in menus. `0` = children shown only when active trail. |
| `enabled` | `1` = visible in menu. `0` = hidden but still exists. |
| `parent` | Parent link plugin ID. Format: `menu_link_content:{uuid}` for content links, or `{module}:{link_id}` for static links. Empty string for top-level items. |
| `changed` | Last modified timestamp |
| `default_langcode` | `1` if this is the default translation |

```sql
-- All content menu links with full metadata
SELECT
  mlcd.id,
  mlcd.uuid,
  mlcd.title,
  mlcd.description,
  mlcd.menu_name,
  mlcd.link__uri,
  mlcd.link__options,
  mlcd.external,
  mlcd.weight,
  mlcd.expanded,
  mlcd.enabled,
  mlcd.parent,
  mlcd.langcode,
  mlcd.changed
FROM menu_link_content_data mlcd
WHERE mlcd.default_langcode = 1
ORDER BY mlcd.menu_name, mlcd.weight;
```

To get translations:

```sql
SELECT
  mlcd.id,
  mlcd.title,
  mlcd.description,
  mlcd.langcode,
  mlcd.link__uri
FROM menu_link_content_data mlcd
WHERE mlcd.default_langcode = 0
ORDER BY mlcd.id, mlcd.langcode;
```

**Resolving internal URIs to paths:**

The `link__uri` column stores route references, not URL paths. To get the actual path a visitor sees:

| URI format | Example | Resolved path |
|---|---|---|
| `entity:node/42` | Entity reference | `/about-us` (whatever the node's alias is) |
| `internal:/admin/reports` | Internal path | `/admin/reports` |
| `route:<front>` | Front page | `/` |
| `route:<nolink>` | No link (parent placeholder) | (none) |
| `https://example.com` | External URL | `https://example.com` |

For `entity:` URIs, resolve the path alias:

```sql
-- Resolve entity:node/{nid} URIs to path aliases
SELECT
  mlcd.id AS menu_link_id,
  mlcd.title,
  mlcd.link__uri,
  COALESCE(ua.alias, CONCAT('/node/', SUBSTRING_INDEX(mlcd.link__uri, '/', -1))) AS resolved_path
FROM menu_link_content_data mlcd
LEFT JOIN path_alias pa ON pa.path = CONCAT('/node/', SUBSTRING_INDEX(mlcd.link__uri, '/', -1))
  AND pa.langcode = mlcd.langcode
LEFT JOIN path_alias ua ON ua.id = pa.id
WHERE mlcd.link__uri LIKE 'entity:node/%'
  AND mlcd.default_langcode = 1;
```

For D9.2+ (path_alias is an entity):

```sql
SELECT
  mlcd.id AS menu_link_id,
  mlcd.title,
  mlcd.link__uri,
  COALESCE(
    pad.alias,
    CONCAT('/node/', SUBSTRING_INDEX(mlcd.link__uri, '/', -1))
  ) AS resolved_path
FROM menu_link_content_data mlcd
LEFT JOIN path_alias_field_data pad
  ON pad.path = CONCAT('/node/', SUBSTRING_INDEX(mlcd.link__uri, '/', -1))
  AND pad.langcode = mlcd.langcode
WHERE mlcd.link__uri LIKE 'entity:node/%'
  AND mlcd.default_langcode = 1;
```

**Link options:**

The `link__options` column is a PHP-serialized array. Unserialize it to extract:

```php
// Example unserialized link__options:
[
  'query' => ['page' => '1', 'sort' => 'date'],
  'fragment' => 'section-2',
  'attributes' => [
    'class' => ['btn', 'btn-primary'],
    'target' => '_blank',
    'rel' => 'noopener',
  ],
]
```

Export with options decoded:

```bash
drush eval "
  \$links = \Drupal::entityTypeManager()->getStorage('menu_link_content')->loadMultiple();
  foreach (\$links as \$link) {
    \$url = \$link->getUrlObject();
    \$options = \$url->getOptions();
    echo json_encode([
      'id' => \$link->id(),
      'uuid' => \$link->uuid(),
      'title' => \$link->getTitle(),
      'menu_name' => \$link->getMenuName(),
      'uri' => \$link->get('link')->uri,
      'url' => \$url->toString(),
      'options' => \$options,
      'weight' => \$link->getWeight(),
      'expanded' => \$link->isExpanded(),
      'enabled' => \$link->isEnabled(),
      'parent' => \$link->getParentId(),
      'description' => \$link->getDescription(),
    ]) . PHP_EOL;
  }
"
```

### 2b. Via the menu_tree Table (D8+)

The `menu_tree` table merges static and content links into one computed tree. It contains the resolved hierarchy for every menu.

| Column | Meaning |
|---|---|
| `menu_name` | Menu this link belongs to |
| `mlid` | Unique row ID in this table |
| `id` | Plugin ID. `menu_link_content:{uuid}` for content links. `{module}.{link_id}` for static links. |
| `parent` | Parent plugin ID. Empty string for root items. |
| `route_name` | Drupal route name (e.g. `entity.node.canonical`, `view.frontpage.page_1`) |
| `route_param_key` | Serialized route parameters (e.g. `node=42`) |
| `url` | External URL if not a route. Empty for internal links. |
| `title` | Serialized title (may be a TranslatableMarkup object) |
| `description` | Serialized description |
| `class` | PHP class implementing the link plugin |
| `options` | Serialized link options |
| `provider` | Module that provides this link |
| `enabled` | 1/0 |
| `discovered` | 1 if auto-discovered from module code |
| `expanded` | 1/0 |
| `weight` | Sort weight |
| `metadata` | Serialized metadata |
| `has_children` | 1 if child links exist |
| `depth` | Tree depth (1 = root) |
| `p1` through `p9` | Materialized path columns. `p1` = top-level ancestor mlid, `p2` = second level, etc. Used for fast tree queries. |

Export the full tree for a specific menu:

```sql
SELECT
  id,
  parent,
  title,
  description,
  route_name,
  route_param_key,
  url,
  options,
  enabled,
  expanded,
  weight,
  has_children,
  depth,
  p1, p2, p3, p4, p5, p6, p7, p8, p9
FROM menu_tree
WHERE menu_name = 'main'
ORDER BY p1, p2, p3, p4, p5, p6, p7, p8, p9;
```

The ORDER BY on materialized path columns returns links in correct tree order: parent before children, siblings sorted by weight.

Note: `title` and `description` in this table are PHP-serialized. They may contain `TranslatableMarkup` objects. Unserialize them to extract the plain string.

To export all menus:

```sql
SELECT DISTINCT menu_name FROM menu_tree ORDER BY menu_name;
```

Then run the per-menu query for each.

### 2c. Via JSON:API (D8+)

Menu link content entities are exposed at:

```
GET /jsonapi/menu_link_content/menu_link_content
```

Filter by menu:

```
GET /jsonapi/menu_link_content/menu_link_content?filter[menu_name]=main
```

Response includes `title`, `description`, `menu_name`, `link` (with `uri` and `options`), `weight`, `expanded`, `enabled`, `parent`, and `langcode`.

Paginate with `page[offset]` and `page[limit]`:

```
GET /jsonapi/menu_link_content/menu_link_content?filter[menu_name]=main&page[limit]=50&page[offset]=0
```

Follow the `next` link in the response until it stops appearing.

JSON:API does not return static menu links. It only returns content links. For a complete export, combine JSON:API results with static links from module files.

JSON:API does not return links in tree order. Reconstruct the tree client-side using the `parent` field.

### 2d. Via Drush (D8+)

No built-in Drush command exports menu links as structured data. Use Drush to run PHP:

```bash
# Export all menus with their link trees
drush eval "
  \$menu_tree_service = \Drupal::menuTree();
  \$menus = \Drupal::entityTypeManager()->getStorage('menu')->loadMultiple();
  foreach (\$menus as \$menu_name => \$menu) {
    \$parameters = new \Drupal\Core\Menu\MenuTreeParameters();
    \$tree = \$menu_tree_service->load(\$menu_name, \$parameters);
    \$manipulators = [
      ['callable' => 'menu.default_tree_manipulators:generateIndexAndSort'],
    ];
    \$tree = \$menu_tree_service->transform(\$tree, \$manipulators);

    echo json_encode([
      'menu_name' => \$menu_name,
      'label' => \$menu->label(),
      'description' => \$menu->getDescription(),
      'locked' => \$menu->isLocked(),
      'links' => build_tree(\$tree),
    ]) . PHP_EOL;
  }

  function build_tree(array \$tree) {
    \$items = [];
    foreach (\$tree as \$element) {
      \$link = \$element->link;
      \$url = \$link->getUrlObject();
      \$item = [
        'plugin_id' => \$link->getPluginId(),
        'title' => \$link->getTitle(),
        'description' => \$link->getDescription(),
        'url' => \$url->isRouted() ? \$url->toString() : \$url->getUri(),
        'route_name' => \$url->isRouted() ? \$url->getRouteName() : null,
        'external' => !\\$url->isRouted(),
        'weight' => \$link->getWeight(),
        'enabled' => \$link->isEnabled(),
        'expanded' => \$link->isExpanded(),
        'options' => \$url->getOptions(),
        'provider' => \$link->getProvider(),
        'children' => build_tree(\$element->subtree),
      ];
      \$items[] = \$item;
    }
    return \$items;
  }
"
```

This produces a nested JSON tree per menu, with children inline. It includes both static and content links in correct tree order.

### 2e. Via Database (D7)

D7 stores all menu links in one table. No separate entity storage.

```sql
SELECT
  mlid,
  menu_name,
  plid,
  link_path,
  link_title,
  options,
  module,
  hidden,
  external,
  has_children,
  expanded,
  weight,
  depth,
  customized,
  p1, p2, p3, p4, p5, p6, p7, p8, p9
FROM menu_links
ORDER BY menu_name, p1, p2, p3, p4, p5, p6, p7, p8, p9;
```

Key columns:

| Column | Meaning |
|---|---|
| `mlid` | Menu link ID (primary key) |
| `plid` | Parent link ID. `0` for top-level items. |
| `link_path` | Drupal internal path (`node/42`, `admin/structure`, `http://example.com`). Not a URI scheme like D8+. |
| `link_title` | Display text |
| `options` | PHP-serialized array. Contains `attributes` (title, class), `query`, `fragment`. Same concept as D8+ link options. |
| `module` | Module that created this link. `menu` = admin-created. `system` = hook_menu. `views` = Views-generated. |
| `hidden` | `0` = visible, `1` = hidden (disabled), `-1` = hidden by module (system link, not toggleable) |
| `external` | `1` if external URL |
| `expanded` | `1` = show children in menu |
| `customized` | `1` = admin has modified this link. `0` = module defaults. |
| `depth` | Tree depth (1 = root) |
| `p1`-`p9` | Materialized path. Same concept as D8+ menu_tree. |

Filter by menu:

```sql
SELECT mlid, plid, link_path, link_title, options, hidden, weight, depth,
  p1, p2, p3, p4, p5, p6, p7, p8, p9
FROM menu_links
WHERE menu_name = 'main-menu'
  AND hidden = 0
ORDER BY p1, p2, p3, p4, p5, p6, p7, p8, p9;
```

Resolve `link_path` to aliases:

```sql
SELECT
  ml.mlid,
  ml.link_title,
  ml.link_path,
  COALESCE(ua.alias, CONCAT('/', ml.link_path)) AS resolved_path
FROM menu_links ml
LEFT JOIN url_alias ua ON ua.source = ml.link_path
WHERE ml.menu_name = 'main-menu'
  AND ml.hidden = 0
ORDER BY ml.p1, ml.p2, ml.p3, ml.p4, ml.p5, ml.p6, ml.p7, ml.p8, ml.p9;
```

D7 `url_alias` uses `source` (internal path like `node/42`) and `alias` (path alias like `/about-us`). No leading slash on `source`.

---

## 3. Menu Block Placements

Menus render on the page through block placements. Each placement specifies which menu, which theme region, and display settings (depth, starting level, visibility conditions).

### 3a. Via Config YAML (D8+)

Block placements live in `block.block.{block_id}.yml`:

```yaml
uuid: 12345678-1234-1234-1234-123456789abc
langcode: en
status: true
dependencies:
  config:
    - system.menu.main
  theme:
    - olivero
id: olivero_main_menu
theme: olivero
region: primary_menu
weight: 0
provider: null
plugin: 'system_menu_block:main'
settings:
  id: 'system_menu_block:main'
  label: 'Main navigation'
  label_display: '0'
  provider: system
  level: 1
  depth: 0
  expand_all_items: false
visibility: {  }
```

Key fields:

| Field | Meaning |
|---|---|
| `plugin` | `system_menu_block:{menu_name}` identifies this as a menu block and which menu it renders |
| `theme` | Which theme this placement belongs to |
| `region` | Theme region where the block appears (`primary_menu`, `footer`, `sidebar_first`, etc.) |
| `weight` | Sort order within the region |
| `settings.level` | Starting level of the menu tree to display. `1` = show from root. `2` = show from second level only. |
| `settings.depth` | How many levels deep to render. `0` = unlimited. `1` = starting level only. |
| `settings.expand_all_items` | If `true`, render all items regardless of active trail. If `false`, expand only active trail. |
| `settings.label_display` | `'0'` = hide block title. `visible` = show it. |
| `visibility` | Conditions that control when this block appears. Can restrict by page path, role, content type, language. |

Export all menu block placements:

```bash
# Find all menu block configs
grep -l "system_menu_block" config/sync/block.block.*.yml
```

```bash
# Export each one
for f in $(grep -l "system_menu_block" config/sync/block.block.*.yml); do
  echo "=== $f ==="
  cat "$f"
done
```

### 3b. Via Database (D8+)

```sql
SELECT name, data FROM config
WHERE name LIKE 'block.block.%'
AND data LIKE '%system_menu_block%'
ORDER BY name;
```

Unserialize the `data` column. Filter for entries where `plugin` starts with `system_menu_block:`.

### 3c. Via Database (D7)

D7 stores block placements in the `block` table:

```sql
SELECT
  b.module,
  b.delta,
  b.theme,
  b.region,
  b.status,
  b.weight,
  b.title
FROM block b
WHERE b.module = 'menu'
  AND b.status = 1
ORDER BY b.theme, b.region, b.weight;
```

The `delta` column holds the menu machine name. `module = 'menu'` identifies menu blocks. For the special system menus (Navigation, Management), the module is `system` and delta identifies the menu.

```sql
-- System menu blocks (D7)
SELECT module, delta, theme, region, status, weight, title
FROM block
WHERE module = 'system'
  AND delta IN ('main-menu', 'management', 'navigation', 'user-menu')
  AND status = 1
ORDER BY theme, region, weight;
```

D7 also has the `menu_block` contrib module for advanced menu rendering. If installed:

```sql
SELECT module, delta, theme, region, status, weight, title
FROM block
WHERE module = 'menu_block'
  AND status = 1
ORDER BY theme, region, weight;
```

Menu Block settings are stored in the `variable` table as `menu_block_{delta}_*` entries. Extract them:

```sql
SELECT name, value FROM variable
WHERE name LIKE 'menu_block_%'
ORDER BY name;
```

Values are PHP-serialized. Key settings: `menu_name`, `level`, `depth`, `follow`, `expanded`, `sort`.

---

## 4. Breadcrumb Configuration

Drupal breadcrumbs are not stored as content. They are computed at runtime from the menu tree active trail and route hierarchy. The migration concern is capturing any customization that overrides the default behavior.

### 4a. Default Behavior

Core builds breadcrumbs from the active menu trail. If a page is a menu link in the "Main navigation" menu, the breadcrumb shows ancestors of that link in the tree. If the page has no menu link, core falls back to the URL path segments.

### 4b. Easy Breadcrumb Module (D8+)

The most common breadcrumb customization module. Config lives in `easy_breadcrumb.settings.yml`:

```yaml
include_invalid_paths: false
excluded_paths: "/node\r\n"
replaced_titles: {  }
custom_paths: {  }
include_home_segment: true
home_segment_title: Home
home_segment_keep: false
include_title_segment: true
title_from_page_when_available: true
title_segment_as_link: false
language_path_prefix_as_segment: false
use_menu_title_as_fallback: true
add_structured_data_json_ld: true
```

Export:

```bash
drush config:get easy_breadcrumb.settings --format=yaml
```

Or from the database:

```sql
SELECT data FROM config WHERE name = 'easy_breadcrumb.settings';
```

Key settings to capture:

| Setting | Meaning |
|---|---|
| `include_home_segment` | Prepend "Home" link to breadcrumbs |
| `home_segment_title` | Label for the home link |
| `include_title_segment` | Append current page title to breadcrumbs |
| `title_segment_as_link` | Make the current page title a link |
| `use_menu_title_as_fallback` | Use menu link title instead of page title |
| `excluded_paths` | Paths that get no breadcrumb |
| `replaced_titles` | Override specific breadcrumb segment titles |
| `custom_paths` | Override breadcrumb trails for specific paths |
| `add_structured_data_json_ld` | Output JSON-LD BreadcrumbList schema |

### 4c. Menu Breadcrumb Module (D8+)

Another common module. Uses menu hierarchy for breadcrumbs. Config in `menu_breadcrumb.settings.yml`:

```yaml
determine_menu: true
disable_admin_page: true
append_current_page: true
current_page_as_link: false
stop_on_first_match: true
append_member_page: true
member_page_as_link: true
menu_order:
  main: main
  footer: ''
  account: ''
  admin: ''
  tools: ''
```

The `menu_order` map controls which menus are consulted and in what priority. Non-empty values mean that menu participates in breadcrumb generation.

### 4d. Breadcrumbs in D7

D7 breadcrumbs depend on the menu trail or custom module overrides. There is no standardized config. Check for these contrib modules:

- **Custom Breadcrumbs**: stores patterns in a `custom_breadcrumb` table.
- **Path Breadcrumbs**: stores breadcrumb definitions as config in the `path_breadcrumbs` table.
- **Crumbs**: configuration via its admin UI, stored in variables.

```sql
-- Check which breadcrumb modules are enabled (D7)
SELECT name FROM system
WHERE status = 1
  AND type = 'module'
  AND name IN ('custom_breadcrumbs', 'path_breadcrumbs', 'crumbs', 'hansel');
```

If none are enabled, breadcrumbs use the default menu trail and need no special export.

---

## 5. Export Format

Combine all data into a single JSON output per menu:

```json
{
  "menus": [
    {
      "machine_name": "main",
      "label": "Main navigation",
      "description": "Site section links",
      "locked": true,
      "links": [
        {
          "id": "menu_link_content:550e8400-e29b-41d4-a716-446655440000",
          "title": "About",
          "description": "About our company",
          "uri": "entity:node/42",
          "resolved_path": "/about-us",
          "external": false,
          "weight": 0,
          "enabled": true,
          "expanded": true,
          "options": {
            "attributes": {"class": ["about-link"]}
          },
          "langcode": "en",
          "children": [
            {
              "id": "menu_link_content:550e8400-e29b-41d4-a716-446655440001",
              "title": "Our Team",
              "description": null,
              "uri": "entity:node/55",
              "resolved_path": "/about-us/team",
              "external": false,
              "weight": 0,
              "enabled": true,
              "expanded": false,
              "options": {},
              "langcode": "en",
              "children": []
            }
          ]
        },
        {
          "id": "menu_link_content:550e8400-e29b-41d4-a716-446655440002",
          "title": "Blog",
          "description": null,
          "uri": "internal:/blog",
          "resolved_path": "/blog",
          "external": false,
          "weight": 1,
          "enabled": true,
          "expanded": false,
          "options": {},
          "langcode": "en",
          "children": []
        },
        {
          "id": "menu_link_content:550e8400-e29b-41d4-a716-446655440003",
          "title": "Partner Site",
          "description": "External partner link",
          "uri": "https://partner.example.com",
          "resolved_path": "https://partner.example.com",
          "external": true,
          "weight": 10,
          "enabled": true,
          "expanded": false,
          "options": {
            "attributes": {"target": "_blank", "rel": "noopener"}
          },
          "langcode": "en",
          "children": []
        }
      ],
      "placements": [
        {
          "block_id": "olivero_main_menu",
          "theme": "olivero",
          "region": "primary_menu",
          "weight": 0,
          "level": 1,
          "depth": 0,
          "expand_all_items": false,
          "visibility": {}
        }
      ]
    }
  ],
  "breadcrumb": {
    "module": "easy_breadcrumb",
    "settings": {
      "include_home_segment": true,
      "home_segment_title": "Home",
      "include_title_segment": true,
      "title_segment_as_link": false,
      "use_menu_title_as_fallback": true,
      "add_structured_data_json_ld": true
    }
  },
  "drupal_version": 10,
  "total_menus": 6,
  "total_links": 47
}
```

---

## 6. Migration Notes

### URI Translation

The target platform will not understand Drupal URI schemes. Convert them during migration:

| Drupal URI | Target equivalent |
|---|---|
| `entity:node/{nid}` | Look up the migrated content by original node ID. Use the new platform's internal reference or the path alias. |
| `internal:/path` | Use the path directly. Verify it exists on the target. |
| `route:<front>` | Map to the target's home page URL (`/`). |
| `route:<nolink>` | Non-linking parent. Render as plain text or a `#` href depending on the target. |
| `base:path` | Relative to Drupal base. Rarely used. Convert to absolute path. |

### Tree Reconstruction

If you exported flat data (database rows or JSON:API responses), reconstruct the tree before passing to the target platform.

From `menu_tree` or D7 `menu_links` rows:

1. Sort by `p1, p2, p3, ..., p9`.
2. `depth = 1` items are root nodes.
3. For `depth > 1`, the parent is the row where `mlid = p{depth-1}` value of the current row.

From `menu_link_content_data` rows (D8+):

1. The `parent` column holds a plugin ID string like `menu_link_content:{uuid}`.
2. Parse the UUID from `parent`. Find the row whose UUID matches. That is the parent.
3. Items with empty `parent` are root nodes.
4. Sort siblings by `weight`.

### D7 to D8+ Name Mapping

| D7 name | D8+ name |
|---|---|
| `main-menu` | `main` |
| `user-menu` | `account` |
| `management` | `admin` |
| `navigation` | `tools` |

### Static vs Content Links

Static links (from module code) may not exist on the target platform. Review each static link to determine if it maps to a feature that will be rebuilt. Admin menu links (`admin.*` routes) are typically irrelevant for frontend migrations. Content links created by site builders carry the actual navigation structure.

### Translations

Multilingual sites store translated menu link content in `menu_link_content_data` rows with `default_langcode = 0`. Each translation has the same `id` but different `langcode`, `title`, `description`, and potentially `link__uri` (if the target page differs by language).

Export all translations per link. The target platform needs to recreate the same per-language navigation structure.
