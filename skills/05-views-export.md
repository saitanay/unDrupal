# Skill 05 — Export Drupal Views

Extract every View from a Drupal site. Translate each into a portable, abstract query definition that any target platform can consume.

---

## Why Views Matter for Migration

Views are the primary query builder in Drupal. They define listing pages, blocks, feeds, REST endpoints, and entity reference lookups. A site with 40 content types might have 200+ Views. Each View encodes business logic: which entities to show, how to filter them, how to sort, how to paginate, how to format output.

Losing that logic during migration means rebuilding it by hand. This skill prevents that.

---

## What to Extract Per View

### Top-Level Properties

From the root of each `views.view.*.yml`:

| Key | What It Is |
|-----|-----------|
| `id` | Machine name (max 128 chars) |
| `label` | Admin title |
| `description` | Admin description |
| `status` | Enabled (`true`) or disabled (`false`) |
| `module` | Module that owns this View |
| `tag` | Grouping tag |
| `base_table` | Source table — determines entity type (`node_field_data`, `taxonomy_term_field_data`, `users_field_data`, `media_field_data`, `commerce_product_field_data`, etc.) |
| `base_field` | Primary key field (`nid`, `tid`, `uid`, etc.) |

### Per Display

Each View contains a `display` map. The `default` display holds shared settings. Other displays override or inherit from it.

**Display types** (the `display_plugin` value):

| Plugin | Purpose |
|--------|---------|
| `default` | Master display. Holds fallback settings for all others. |
| `page` | Full page at a URL path. Has menu integration. |
| `block` | Rendered as a Drupal block. |
| `feed` | RSS/Atom feed at a URL path. |
| `attachment` | Attaches to another display (before/after). |
| `embed` | Embedded programmatically. |
| `rest_export` | REST API endpoint returning JSON/XML/HAL. |
| `entity_reference` | Powers entity reference autocomplete widgets. |

**For each display, extract these from `display_options`:**

#### Path and Menu (page, feed, rest_export)

```yaml
path: admin/content/node
menu:
  type: 'default tab'    # normal, tab, default tab, none
  title: Content
  weight: -10
  menu_name: admin
tab_options:
  type: normal
  title: Content
```

#### Title, Header, Footer, Empty Text

```yaml
title: 'My Listing'
header:
  area_text_custom:
    plugin_id: text_custom
    content: '<p>Header markup</p>'
footer: {}
empty:
  area_text_custom:
    plugin_id: text_custom
    empty: true
    content: 'No results found.'
```

#### Access Control

```yaml
access:
  type: perm              # perm, role, none
  options:
    perm: 'access content overview'
```

#### Caching

```yaml
cache:
  type: tag               # tag, time, none
```

#### Fields

Each field lives under `display_options.fields.<field_id>`:

```yaml
title:
  id: title
  table: node_field_data
  field: title
  entity_type: node
  entity_field: title
  plugin_id: field
  label: Title
  exclude: false            # hidden from output but available for rewriting
  alter:
    alter_text: true        # rewriting enabled
    text: '<a href="/node/{{ nid }}">{{ title }}</a>'
  type: string              # formatter plugin
  settings:
    link_to_entity: true
  click_sort_column: value  # column used for table click-sorting
  hide_empty: false
  empty_zero: false
```

Key field properties to capture:
- `field`, `table`, `entity_field` — identify the source data
- `plugin_id` — handler type (`field`, `node_bulk_form`, `entity_operations`, `custom`, `counter`, `rendered_entity`, `entity_link`)
- `label` — display label
- `exclude` — field computed but hidden (used in rewriting tokens)
- `alter.alter_text` + `alter.text` — rewriting with replacement tokens (`{{ field_name }}`)
- `type` — formatter (`string`, `entity_reference_label`, `boolean`, `timestamp`, `number_integer`, `text_default`, `image`, `user_name`, `language`)
- `settings` — formatter-specific config
- `click_sort_column` — which DB column gets sorted on click
- `relationship` — which relationship provides this field's data

#### Filters

Each filter under `display_options.filters.<filter_id>`:

```yaml
status:
  id: status
  table: node_field_data
  field: status
  entity_type: node
  plugin_id: boolean
  operator: '='
  value: '1'
  group: 1
  exposed: true
  expose:
    label: Status
    identifier: status       # query string parameter name
    operator: status_op
    required: false
    remember: false
    multiple: false
  is_grouped: true
  group_info:
    label: 'Published status'
    identifier: status
    widget: select
    group_items:
      1:
        title: Published
        operator: '='
        value: '1'
      2:
        title: Unpublished
        operator: '='
        value: '0'
```

Key filter properties:
- `operator` — `=`, `!=`, `contains`, `in`, `not in`, `>`, `<`, `between`, `IS NULL`, `IS NOT NULL`
- `value` — static value or empty when exposed
- `exposed` — user-facing filter
- `expose.identifier` — the URL query parameter
- `is_grouped` — grouped filter with predefined choices
- `group` — filter group number (for AND/OR logic)
- `filter_groups` — defines group operator logic:
  ```yaml
  filter_groups:
    operator: AND
    groups:
      1: AND
      2: OR
  ```

#### Sort Criteria

```yaml
sorts:
  created:
    id: created
    table: node_field_data
    field: created
    entity_type: node
    plugin_id: date
    order: DESC
    exposed: false
    granularity: second
```

#### Relationships

```yaml
relationships:
  uid:
    id: uid
    table: node_field_data
    field: uid
    admin_label: author
    plugin_id: standard
    required: true          # INNER JOIN when true, LEFT JOIN when false
```

Relationships are joins. They connect the base entity to related entities. Fields, filters, and sorts reference relationships by the relationship `id`.

#### Contextual Filters (Arguments)

```yaml
arguments:
  nid:
    id: nid
    table: node_field_data
    field: nid
    plugin_id: node_nid
    default_action: 'not found'     # not found, ignore, empty, default, summary, access denied
    default_argument_type: fixed    # fixed, raw, query_parameter, node, user, php
    default_argument_options:
      argument: ''
    validate:
      type: 'entity:node'
    validate_options:
      bundles: {article: article}
    exception:
      value: all
      title_enable: true
      title: All
```

#### Pager

```yaml
pager:
  type: full              # full, mini, some, none
  options:
    items_per_page: 50
    offset: 0
    tags:
      next: 'Next ›'
      previous: '‹ Previous'
      first: '« First'
      last: 'Last »'
```

Pager types:
- `full` — numbered pages with first/last/prev/next
- `mini` — prev/next only
- `some` — fixed number of items, no pager controls
- `none` — show all results

#### Query Settings

```yaml
query:
  type: views_query
  options:
    distinct: true
    query_comment: ''
```

Aggregation lives at the display level:
```yaml
group_by: true    # enables GROUP BY / aggregation
```

#### Style and Row Plugins

```yaml
style:
  type: table             # default (unformatted), table, grid, list, serializer
  options:
    columns:
      title: title
      type: type
    default: changed      # default sort column
    info:
      title:
        sortable: true
        default_sort_order: asc
    sticky: true
    empty_table: true
row:
  type: fields            # fields, entity, data_entity, data_field, search_api
```

Style plugins:
| Plugin | Output |
|--------|--------|
| `default` | Unformatted list of rows |
| `table` | HTML table with optional sortable columns |
| `grid` | CSS grid layout |
| `list` | HTML `<ul>` or `<ol>` |
| `serializer` | JSON/XML/HAL (REST export) |

Row plugins:
| Plugin | Output |
|--------|--------|
| `fields` | Renders selected fields |
| `entity:node` (etc.) | Full entity render in a view mode |
| `data_entity` | Serialized entity (REST) |
| `data_field` | Serialized fields (REST) with alias + raw output options |
| `search_api` | Search API rendered row |

#### AJAX

```yaml
use_ajax: true
```

#### Exposed Form Settings

```yaml
exposed_form:
  type: basic             # basic, input_required, bef (contrib)
  options:
    submit_button: Filter
    reset_button: true
    reset_button_label: Reset
exposed_block: false      # render exposed form as a separate block
```

#### REST Export Specifics

REST export displays add:

```yaml
auth:
  - cookie
  - basic_auth
style:
  type: serializer
  options:
    formats:
      json: json
      xml: xml
row:
  type: data_field
  options:
    field_options:
      title:
        alias: 'name'
        raw_output: false
      nid:
        alias: 'id'
        raw_output: true
```

---

## Access Patterns

Use these methods in order of preference.

### 1. Config YAML Files (Best)

Drupal 8/9/10/11 store Views as config entities. Each View is one YAML file.

**Location:** `sites/default/files/config_*/sync/views.view.*.yml` (if config sync is enabled) or export via Drush.

```bash
# Export all config to a directory
drush config:export --destination=/tmp/drupal-config

# List the exported View files
ls /tmp/drupal-config/views.view.*.yml

# Export a single View
drush config:get views.view.content --format=yaml > views.view.content.yml
```

### 2. Drush Commands

```bash
# List all Views with machine name, label, status
drush views:list
drush views:list --status=enabled
drush views:list --format=json

# Export specific View config
drush config:get views.view.frontpage --format=yaml

# Bulk export all View configs
for view in $(drush config:list | grep '^views\.view\.'); do
  drush config:get "$view" --format=yaml > "${view}.yml"
done
```

### 3. Database Direct Query

When Drush is unavailable and no config export exists:

```sql
-- Drupal stores active config in the config table
SELECT name, data
FROM config
WHERE name LIKE 'views.view.%';
```

The `data` column contains PHP-serialized config. Deserialize it, then convert to YAML:

```python
import phpserialize
import yaml

# After fetching rows from the config table
data = phpserialize.loads(raw_data)
yaml_str = yaml.dump(data, default_flow_style=False)
```

### 4. Admin UI Export

Navigate to `/admin/config/development/configuration/single/export`, select **View** from the Configuration type dropdown, pick the View name, and copy the YAML from the textarea.

### 5. Drupal 7 Views (Legacy)

D7 Views use a PHP export format, not YAML. They are stored in the `views_view` and `views_display` database tables.

```sql
-- D7: Get all views
SELECT vid, name, description, tag, base_table, human_name, core
FROM views_view;

-- D7: Get displays for a view
SELECT vid, id, display_title, display_plugin, position, display_options
FROM views_display
WHERE vid = ?;
```

The `display_options` column in D7 is a PHP serialized blob. Structure is similar to D8+ but key names differ:

| D7 Key | D8+ Key |
|--------|---------|
| `handler` | `plugin_id` |
| `views_handler_field` | `standard` or `field` |
| `views_handler_filter_string` | `string` |
| `views_handler_sort` | `standard` |
| `views_handler_relationship` | `standard` |
| `views_handler_argument_string` | `string` |

---

## Translation Script: `views-to-query.py`

Convert Views YAML files into abstract query definitions. This decouples the business logic from Drupal.

```python
#!/usr/bin/env python3
"""
views-to-query.py

Reads Drupal Views YAML files (views.view.*.yml) and produces
abstract query definitions in JSON.

Usage:
    python views-to-query.py /path/to/config/dir --output /path/to/output/dir
    python views-to-query.py /path/to/views.view.blog.yml
"""

import argparse
import json
import sys
from pathlib import Path

import yaml


# Map Drupal base_table to entity type
TABLE_TO_ENTITY = {
    "node_field_data": "node",
    "node": "node",
    "taxonomy_term_field_data": "taxonomy_term",
    "users_field_data": "user",
    "media_field_data": "media",
    "file_managed": "file",
    "comment_field_data": "comment",
    "commerce_product_field_data": "commerce_product",
    "commerce_product_variation_field_data": "commerce_product_variation",
    "commerce_order": "commerce_order",
    "block_content_field_data": "block_content",
    "paragraphs_item_field_data": "paragraph",
    "redirect": "redirect",
    "webform_submission": "webform_submission",
    "flagging": "flagging",
    "search_api_index_*": "search_api",
}


def resolve_entity_type(base_table: str) -> str:
    """Map a Drupal base_table to a portable entity type name."""
    if base_table.startswith("search_api_index_"):
        return "search_api"
    return TABLE_TO_ENTITY.get(base_table, base_table)


def extract_bundle_filter(filters: dict) -> str | None:
    """Pull bundle/type restriction from filters if present."""
    for fid, f in filters.items():
        if f.get("entity_field") == "type" and f.get("plugin_id") == "bundle":
            val = f.get("value", {})
            if isinstance(val, dict):
                bundles = list(val.keys())
                if bundles:
                    return bundles if len(bundles) > 1 else bundles[0]
    return None


def merge_display_options(default_opts: dict, display_opts: dict) -> dict:
    """Merge a display's options with the default, respecting 'defaults' flags."""
    merged = dict(default_opts)
    defaults_flags = display_opts.get("defaults", {})

    for key, value in display_opts.items():
        if key == "defaults":
            continue
        # If defaults[key] is False, this display overrides the default
        # If defaults[key] is True or missing, inherit from default
        if not defaults_flags.get(key, True):
            merged[key] = value
        elif key not in merged:
            merged[key] = value

    # Also apply overrides for keys where defaults flag is explicitly False
    for key, uses_default in defaults_flags.items():
        if not uses_default and key in display_opts:
            merged[key] = display_opts[key]

    return merged


def extract_fields(fields: dict) -> list[dict]:
    """Convert Views fields map to portable field definitions."""
    result = []
    for fid, f in fields.items():
        field_def = {
            "id": fid,
            "source_field": f.get("entity_field") or f.get("field", fid),
            "source_table": f.get("table", ""),
            "plugin": f.get("plugin_id", ""),
            "label": f.get("label", ""),
            "formatter": f.get("type", ""),
            "exclude_from_display": f.get("exclude", False),
        }

        # Formatter settings
        if f.get("settings"):
            field_def["formatter_settings"] = f["settings"]

        # Rewriting
        alter = f.get("alter", {})
        if alter.get("alter_text"):
            field_def["rewrite"] = alter.get("text", "")

        # Relationship
        if f.get("relationship") and f["relationship"] != "none":
            field_def["relationship"] = f["relationship"]

        # Click sort
        if f.get("click_sort_column"):
            field_def["click_sort_column"] = f["click_sort_column"]

        result.append(field_def)
    return result


def extract_conditions(filters: dict, filter_groups: dict | None) -> dict:
    """Convert Views filters to portable conditions."""
    conditions = []
    for fid, f in filters.items():
        # Skip the node_status special filter
        if f.get("plugin_id") == "node_status":
            continue

        cond = {
            "field": f.get("entity_field") or f.get("field", fid),
            "operator": f.get("operator", "="),
            "value": f.get("value", ""),
            "group": f.get("group", 1),
        }

        if f.get("exposed"):
            cond["exposed"] = True
            expose = f.get("expose", {})
            cond["expose"] = {
                "label": expose.get("label", ""),
                "identifier": expose.get("identifier", fid),
                "required": expose.get("required", False),
            }

        if f.get("is_grouped"):
            gi = f.get("group_info", {})
            cond["grouped"] = True
            cond["group_items"] = []
            for item_id, item in (gi.get("group_items") or {}).items():
                cond["group_items"].append({
                    "label": item.get("title", ""),
                    "operator": item.get("operator", "="),
                    "value": item.get("value", ""),
                })

        conditions.append(cond)

    result = {"conditions": conditions}

    if filter_groups:
        result["logic"] = {
            "operator": filter_groups.get("operator", "AND"),
            "groups": filter_groups.get("groups", {}),
        }

    return result


def extract_sort(sorts: dict) -> list[dict]:
    """Convert Views sort criteria to portable sort definitions."""
    result = []
    for sid, s in sorts.items():
        sort_def = {
            "field": s.get("entity_field") or s.get("field", sid),
            "direction": s.get("order", "ASC"),
        }
        if s.get("exposed"):
            sort_def["exposed"] = True
            if s.get("expose", {}).get("label"):
                sort_def["expose_label"] = s["expose"]["label"]
        result.append(sort_def)
    return result


def extract_relationships(rels: dict) -> list[dict]:
    """Convert Views relationships to portable join definitions."""
    result = []
    for rid, r in rels.items():
        rel_def = {
            "id": rid,
            "entity_type": r.get("entity_type", ""),
            "field": r.get("field", rid),
            "table": r.get("table", ""),
            "required": r.get("required", False),
            "admin_label": r.get("admin_label", ""),
        }
        result.append(rel_def)
    return result


def extract_arguments(args: dict) -> list[dict]:
    """Convert Views contextual filters to portable argument definitions."""
    result = []
    for aid, a in args.items():
        arg_def = {
            "field": a.get("entity_field") or a.get("field", aid),
            "default_action": a.get("default_action", "ignore"),
        }
        if a.get("default_argument_type"):
            arg_def["default_value_plugin"] = a["default_argument_type"]
        if a.get("default_argument_options"):
            arg_def["default_value_options"] = a["default_argument_options"]
        if a.get("validate", {}).get("type"):
            arg_def["validator"] = a["validate"]["type"]
        if a.get("validate_options"):
            arg_def["validator_options"] = a["validate_options"]
        if a.get("exception"):
            arg_def["exception"] = a["exception"]
        result.append(arg_def)
    return result


def extract_pager(pager: dict) -> dict:
    """Convert Views pager config to portable pager definition."""
    result = {
        "type": pager.get("type", "none"),
    }
    opts = pager.get("options", {})
    if "items_per_page" in opts:
        result["items_per_page"] = opts["items_per_page"]
    if opts.get("offset"):
        result["offset"] = opts["offset"]
    return result


def convert_display(view_id: str, view_label: str, entity_type: str,
                    display_id: str, display: dict,
                    merged_opts: dict) -> dict:
    """Convert one display into an abstract query definition."""
    query_def = {
        "view_id": view_id,
        "view_label": view_label,
        "display_id": display_id,
        "display_title": display.get("display_title", ""),
        "display_type": display.get("display_plugin", "default"),
        "entity_type": entity_type,
    }

    # Path
    if merged_opts.get("path"):
        query_def["path"] = merged_opts["path"]

    # Title
    if merged_opts.get("title"):
        query_def["title"] = merged_opts["title"]

    # Bundle filter
    filters = merged_opts.get("filters", {})
    filter_groups = merged_opts.get("filter_groups")
    bundle = extract_bundle_filter(filters)
    if bundle:
        query_def["bundle_filter"] = bundle

    # Fields
    fields = merged_opts.get("fields", {})
    if fields:
        query_def["fields"] = extract_fields(fields)

    # Conditions
    if filters:
        query_def.update(extract_conditions(filters, filter_groups))

    # Sort
    sorts = merged_opts.get("sorts", {})
    if sorts:
        query_def["sort"] = extract_sort(sorts)

    # Relationships
    rels = merged_opts.get("relationships", {})
    if rels:
        query_def["relationships"] = extract_relationships(rels)

    # Contextual filters
    arguments = merged_opts.get("arguments", {})
    if arguments:
        query_def["contextual_filters"] = extract_arguments(arguments)

    # Pager
    pager = merged_opts.get("pager", {})
    if pager:
        query_def["pager"] = extract_pager(pager)

    # Style and row
    style = merged_opts.get("style", {})
    if style:
        query_def["style"] = {
            "plugin": style.get("type", "default"),
        }
        style_opts = style.get("options", {})
        if style_opts:
            query_def["style"]["options"] = style_opts

    row = merged_opts.get("row", {})
    if row:
        query_def["row_plugin"] = row.get("type", "fields")
        row_opts = row.get("options", {})
        if row_opts:
            query_def["row_options"] = row_opts

    # Access
    access = merged_opts.get("access", {})
    if access:
        query_def["access"] = {
            "type": access.get("type", "none"),
        }
        if access.get("options"):
            query_def["access"]["options"] = access["options"]

    # AJAX
    if merged_opts.get("use_ajax"):
        query_def["ajax"] = True

    # Exposed form
    ef = merged_opts.get("exposed_form", {})
    if ef:
        query_def["exposed_form"] = {
            "type": ef.get("type", "basic"),
        }

    # REST auth (rest_export only)
    if merged_opts.get("auth"):
        query_def["auth"] = merged_opts["auth"]

    # Query settings
    query_settings = merged_opts.get("query", {})
    if query_settings.get("options", {}).get("distinct"):
        query_def["distinct"] = True
    if merged_opts.get("group_by"):
        query_def["aggregation"] = True

    # Header / footer / empty areas
    for area in ("header", "footer", "empty"):
        area_data = merged_opts.get(area, {})
        if area_data:
            query_def[area] = []
            for area_id, area_conf in area_data.items():
                query_def[area].append({
                    "plugin": area_conf.get("plugin_id", ""),
                    "content": area_conf.get("content", ""),
                })

    # Menu (page displays)
    if merged_opts.get("menu"):
        query_def["menu"] = merged_opts["menu"]

    return query_def


def convert_view(view_data: dict) -> list[dict]:
    """Convert a full View config into abstract query definitions (one per display)."""
    view_id = view_data.get("id", "unknown")
    view_label = view_data.get("label", "")
    base_table = view_data.get("base_table", "")
    entity_type = resolve_entity_type(base_table)

    displays = view_data.get("display", {})
    default_opts = displays.get("default", {}).get("display_options", {})

    results = []
    for display_id, display in displays.items():
        display_opts = display.get("display_options", {})
        merged = merge_display_options(default_opts, display_opts)
        query_def = convert_display(
            view_id, view_label, entity_type,
            display_id, display, merged
        )
        results.append(query_def)

    return results


def process_file(filepath: Path) -> list[dict]:
    """Load one YAML file and return abstract query definitions."""
    with open(filepath) as f:
        data = yaml.safe_load(f)
    if not data or "display" not in data:
        print(f"  Skipping {filepath.name}: not a valid View config", file=sys.stderr)
        return []
    return convert_view(data)


def main():
    parser = argparse.ArgumentParser(
        description="Convert Drupal Views YAML to abstract query definitions"
    )
    parser.add_argument(
        "source",
        help="Path to a single views.view.*.yml file or a directory of config files"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output directory (writes one JSON per View). Prints to stdout if omitted."
    )
    parser.add_argument(
        "--combined", "-c",
        action="store_true",
        help="Write all queries into a single combined JSON file"
    )
    args = parser.parse_args()

    source = Path(args.source)
    if source.is_file():
        files = [source]
    elif source.is_dir():
        files = sorted(source.glob("views.view.*.yml"))
        if not files:
            print(f"No views.view.*.yml files found in {source}", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"Source not found: {source}", file=sys.stderr)
        sys.exit(1)

    all_queries = []
    for filepath in files:
        queries = process_file(filepath)
        if not queries:
            continue

        if args.output and not args.combined:
            out_dir = Path(args.output)
            out_dir.mkdir(parents=True, exist_ok=True)
            view_id = queries[0].get("view_id", filepath.stem)
            out_path = out_dir / f"{view_id}.json"
            with open(out_path, "w") as f:
                json.dump(queries, f, indent=2, default=str)
            print(f"  Wrote {out_path}")
        else:
            all_queries.extend(queries)

    if args.combined and args.output:
        out_dir = Path(args.output)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / "all-views-queries.json"
        with open(out_path, "w") as f:
            json.dump(all_queries, f, indent=2, default=str)
        print(f"  Wrote {out_path}")
    elif not args.output:
        print(json.dumps(all_queries, indent=2, default=str))


if __name__ == "__main__":
    main()
```

### Dependencies

```
pip install pyyaml
```

### Usage

```bash
# Single file
python views-to-query.py views.view.blog.yml

# All views in an exported config directory
python views-to-query.py /tmp/drupal-config/ --output ./query-defs/

# Combined output
python views-to-query.py /tmp/drupal-config/ --output ./query-defs/ --combined
```

### Example Output

For a View named `blog` with a page display at `/blog`:

```json
[
  {
    "view_id": "blog",
    "view_label": "Blog",
    "display_id": "page_1",
    "display_title": "Page",
    "display_type": "page",
    "entity_type": "node",
    "path": "blog",
    "title": "Blog",
    "bundle_filter": "article",
    "fields": [
      {
        "id": "title",
        "source_field": "title",
        "source_table": "node_field_data",
        "plugin": "field",
        "label": "",
        "formatter": "string",
        "exclude_from_display": false,
        "formatter_settings": {"link_to_entity": true}
      },
      {
        "id": "created",
        "source_field": "created",
        "source_table": "node_field_data",
        "plugin": "field",
        "label": "Posted",
        "formatter": "timestamp",
        "exclude_from_display": false,
        "formatter_settings": {"date_format": "medium"}
      }
    ],
    "conditions": [
      {
        "field": "status",
        "operator": "=",
        "value": "1",
        "group": 1
      },
      {
        "field": "type",
        "operator": "in",
        "value": {"article": "article"},
        "group": 1
      }
    ],
    "logic": {
      "operator": "AND",
      "groups": {"1": "AND"}
    },
    "sort": [
      {"field": "created", "direction": "DESC"}
    ],
    "pager": {
      "type": "full",
      "items_per_page": 10
    },
    "style": {"plugin": "default"},
    "row_plugin": "fields",
    "access": {"type": "none"},
    "exposed_form": {"type": "basic"}
  }
]
```

---

## Step-by-Step Extraction Procedure

### Step 1: Inventory All Views

```bash
drush views:list --format=json > views-inventory.json
```

Or from config files:

```bash
ls /path/to/config/views.view.*.yml | wc -l
```

Record total count. Flag disabled Views (they still contain logic worth preserving).

### Step 2: Export Config YAML

```bash
# Method A: Full config export
drush config:export --destination=/tmp/drupal-config

# Method B: Per-view export
mkdir -p ./views-yaml
for view in $(drush config:list | grep '^views\.view\.'); do
  drush config:get "$view" --format=yaml > "./views-yaml/${view}.yml"
done
```

### Step 3: Validate Exported Files

Check that each file parses and contains a `display` key:

```python
for f in Path("./views-yaml").glob("views.view.*.yml"):
    data = yaml.safe_load(open(f))
    assert "display" in data, f"Invalid: {f.name}"
    print(f"{f.name}: {len(data['display'])} displays")
```

### Step 4: Run the Converter

```bash
python views-to-query.py ./views-yaml/ --output ./query-defs/ --combined
```

### Step 5: Review and Annotate

Open `all-views-queries.json`. For each query definition:

1. Confirm the `entity_type` and `bundle_filter` are correct.
2. Check that exposed filters have meaningful `identifier` values — these become URL parameters on the target platform.
3. Verify relationships resolved to real entity types.
4. Flag any `plugin_id` values you do not recognize — they may come from contrib modules (`search_api`, `better_exposed_filters`, `views_bulk_operations`, `views_conditional`, `geolocation`).
5. Note REST export displays: capture the `path`, `auth`, and serialization `formats` for API migration.
6. Note contextual filters with `default_argument_type: raw` — these depend on Drupal's URL structure and need path mapping on the target platform.

### Step 6: Map to Target Platform

The abstract query definitions are platform-agnostic. Map them to your target:

| Drupal Concept | WordPress | Next.js/Headless | Laravel | Static Site |
|----------------|-----------|------------------|---------|-------------|
| Page display | WP_Query + template | API route + component | Eloquent query + Blade | Build-time query |
| Block display | Widget/Shortcode | Component | Livewire component | Partial |
| REST export | REST API endpoint | API route | API resource | JSON file |
| Feed display | RSS feed | RSS route | Feed controller | RSS build |
| Exposed filter | Query params | URL search params | Request params | Client-side filter |
| Contextual filter | URL param/rewrite | Dynamic route param | Route parameter | Path param |
| Pager | `posts_per_page` | `limit`/`offset` | `paginate()` | Pagination build |
| Relationship | `meta_query` join | `include`/`populate` | `with()` eager load | Resolved at build |

---

## Gotchas

**Display inheritance.** Non-default displays inherit from `default` unless they override. The `defaults` map inside each display controls this. A display with `defaults.fields: true` uses the default display's fields. With `defaults.fields: false`, it defines its own. The converter script handles this via `merge_display_options`.

**Contrib plugins.** Views ecosystem has hundreds of contrib handler and style plugins. The converter captures their config as-is. Unrecognized `plugin_id` values appear in the output for manual review. Common ones: `search_api_*`, `better_exposed_filters`, `views_bulk_operations`, `geofield_proximity`, `entity_browser`, `flag_*`.

**Token rewriting.** Fields with `alter.alter_text: true` use Twig-style tokens (`{{ field_name }}`). These reference other fields in the same View by their field ID. The converter preserves the rewrite template string. Map these to template expressions on the target platform.

**Grouped filters.** When `is_grouped: true`, the filter presents predefined choices to the user instead of a free-form input. Each group item has its own operator and value. These are dropdown selects on the front end.

**Search API Views.** Views built on Search API use `search_api_index_*` as the base table. Their fields, filters, and sorts reference indexed fields, not entity fields directly. The converter maps these to entity type `search_api`. You need the Search API index config (`search_api.index.*.yml`) to resolve indexed field names back to entity fields.

**Drupal 7 migration.** D7 Views use PHP serialized arrays, not YAML. The schema is similar but handler names differ (see the D7 table above). Use `phpserialize` to decode, then normalize to the D8+ key names before running through the converter.
