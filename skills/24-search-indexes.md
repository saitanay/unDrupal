# Skill 24: Search Indexes, Facets, and Search API Configuration

Export Search API servers, indexes, processors, facet configuration, and autocomplete settings. This captures the full search architecture: what backend powers search, which fields are indexed, how content is processed before indexing, and how users interact with search results.

Run Skill 01 (Site Audit) first. You need the Drupal version and the module inventory. Search API is contrib in all Drupal versions. Some sites use core Search instead (or both).

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Config directory** (YAML) | Server definitions, index config, facet settings, processor chains |
| **Drush** | Index status, item counts, server connectivity, reindex triggers |
| **Database** | D7 search_api entities, core search index tables, tracker state |
| **Admin UI** | `/admin/config/search/search-api` for visual review |

---

## 1. Search API Servers

A server defines the search backend: Solr, Elasticsearch, database, or Typesense. Each index connects to one server.

### 1a. Via Config YAML (D8+)

Server definitions live in `search_api.server.{machine_name}.yml`:

```yaml
# search_api.server.solr_main.yml
uuid: a1b2c3d4-...
langcode: en
status: true
dependencies:
  module:
    - search_api_solr
id: solr_main
name: 'Main Solr Server'
description: 'Production Solr 8 cluster'
backend: search_api_solr
backend_config:
  connector: standard
  connector_config:
    scheme: https
    host: solr.example.com
    port: 8983
    path: /
    core: drupal
    timeout: 5
    index_timeout: 10
    optimize_timeout: 20
    commit_within: 1000
    solr_version: ''
    http_method: AUTO
    jmx: false
    jts: false
    solr_install_dir: ''
  retrieve_data: false
  highlight_data: false
  skip_schema_check: false
  server_prefix: ''
  domain: ''
  environment: default
```

| Key | What it means |
|---|---|
| `id` | Machine name |
| `name` | Admin label |
| `backend` | Plugin ID: `search_api_solr`, `elasticsearch_connector`, `search_api_db`, `search_api_typesense` |
| `backend_config` | Backend-specific settings. Structure varies by plugin. |
| `status` | Whether the server is enabled |

**Backend config varies by type:**

**Solr** (`search_api_solr`):
- `connector`: `standard` (single core), `solr_cloud` (SolrCloud with ZooKeeper), `solr_cloud_basic_auth`
- `connector_config`: `scheme`, `host`, `port`, `path`, `core` (standard) or `collection` (SolrCloud)
- `commit_within`: milliseconds before a soft commit (affects near-real-time search)
- `retrieve_data`, `highlight_data`: whether to pull stored fields and highlight snippets from Solr

**Elasticsearch** (`elasticsearch_connector`):
- `connector_config`: `url` (e.g. `http://localhost:9200`), `index_prefix`
- Authentication settings: `use_authentication`, `authentication_type`, `user`, `password`

**Database** (`search_api_db`):
- `min_chars`: minimum word length to index
- `partial_matches`: enable LIKE-based partial matching (slow on large datasets)
- `autocomplete`: configuration for autocomplete suggestions
- Database backend stores everything in Drupal's own database. No external service.

**Typesense** (`search_api_typesense`):
- `connector_config`: `nodes` array (host, port, protocol), `api_key`

### 1b. Via Drush

```bash
# List all servers with status
drush search-api:server-list --format=json

# Check server connectivity
drush search-api:server-info solr_main --format=json

# Export server config
drush config:get search_api.server.solr_main --format=yaml
```

### 1c. Via Database (D8+)

```sql
-- All search server configs
SELECT name, data FROM config WHERE name LIKE 'search_api.server.%';
```

Data is PHP-serialized. Unserialize to get the full config array.

### 1d. Via Database (D7)

D7 search_api stores servers as entities in the database, not config YAML:

```sql
-- D7 search_api servers
SELECT id, name, machine_name, description, class, options, enabled
FROM search_api_server;
```

The `class` column identifies the backend:
- `SearchApiSolrService` or `SearchApiSolrConnection`: Solr
- `SearchApiDbService`: Database
- `SearchApiElasticsearchBackend`: Elasticsearch

The `options` column holds a PHP-serialized array with connection details (host, port, path, etc.).

**D7 apachesolr module** (alternative to search_api):

```sql
-- apachesolr environments (each = one server connection)
SELECT env_id, name, url, service_class
FROM apachesolr_environment;

-- apachesolr environment variables (additional settings)
SELECT env_id, name, value
FROM apachesolr_environment_variable;
```

---

## 2. Search API Indexes

An index defines what content to index, which fields to include, and how to process them. This is the core of search configuration.

### 2a. Via Config YAML (D8+)

Index definitions live in `search_api.index.{machine_name}.yml`:

```yaml
# search_api.index.content.yml
uuid: b2c3d4e5-...
langcode: en
status: true
dependencies:
  config:
    - field.storage.node.body
    - field.storage.node.field_tags
    - search_api.server.solr_main
  module:
    - node
    - search_api
    - taxonomy
    - user
id: content
name: 'Content Index'
description: 'Indexes published nodes for site search'
read_only: false
field_settings:
  title:
    label: Title
    datasource_id: 'entity:node'
    property_path: title
    type: text
    boost: 5.0
  body:
    label: Body
    datasource_id: 'entity:node'
    property_path: body
    type: text
    boost: 1.0
  field_tags:
    label: Tags
    datasource_id: 'entity:node'
    property_path: field_tags
    type: integer
  rendered_item:
    label: 'Rendered HTML output'
    property_path: rendered_item
    type: text
    configuration:
      roles:
        - anonymous
      view_mode:
        'entity:node':
          article: search_index
          page: search_index
  status:
    label: 'Publishing status'
    datasource_id: 'entity:node'
    property_path: status
    type: boolean
  uid:
    label: 'Author'
    datasource_id: 'entity:node'
    property_path: uid
    type: integer
  created:
    label: 'Created date'
    datasource_id: 'entity:node'
    property_path: created
    type: date
  changed:
    label: 'Changed date'
    datasource_id: 'entity:node'
    property_path: changed
    type: date
datasource_settings:
  'entity:node':
    bundles:
      default: true
      selected: []
    languages:
      default: true
      selected: []
server: solr_main
options:
  index_directly: true
  cron_limit: 50
tracker_settings:
  default:
    indexing_order: fifo
processor_settings:
  add_url:
    weights:
      preprocess_index: -30
  aggregated_field:
    weights:
      add_properties: 20
  content_access:
    weights:
      preprocess_index: -6
      preprocess_query: -4
  entity_status: {}
  highlight:
    weights:
      postprocess_query: 0
    prefix: '<strong>'
    suffix: '</strong>'
    excerpt: true
    excerpt_length: 256
    highlight: always
    highlight_partial: false
    exclude_fields: []
  html_filter:
    weights:
      preprocess_index: -3
      preprocess_query: -6
    all_fields: false
    fields:
      - body
      - rendered_item
    title: true
    alt: true
    tags:
      h1: 5
      h2: 3
      h3: 2
      strong: 2
      em: 1
      b: 2
  ignorecase:
    weights:
      preprocess_index: -5
      preprocess_query: -8
    all_fields: true
    fields: []
  language_with_fallback: {}
  rendered_item: {}
  stemmer:
    weights:
      preprocess_index: 0
      preprocess_query: 0
    all_fields: true
    fields: []
    exceptions: {}
  stopwords:
    weights:
      preprocess_index: -2
      preprocess_query: -7
    all_fields: true
    fields: []
    stopwords:
      - a
      - an
      - the
      - is
      - are
  tokenizer:
    weights:
      preprocess_index: -2
      preprocess_query: -5
    all_fields: true
    fields: []
    spaces: ''
    overlap_cjk: 1
    minimum_word_size: 3
  transliteration:
    weights:
      preprocess_index: -4
      preprocess_query: -7
    all_fields: true
    fields: []
  type_boost:
    weights:
      preprocess_index: 0
    boosts:
      'entity:node':
        datasource_boost: 1.0
        bundle_boosts:
          article: 1.0
          page: 0.8
          landing_page: 1.5
```

### Key Sections

**`field_settings`** defines every indexed field:

| Property | Meaning |
|---|---|
| `label` | Human-readable name |
| `datasource_id` | Source entity type (e.g. `entity:node`, `entity:taxonomy_term`). Omit for computed fields. |
| `property_path` | Entity property or field name. Nested paths use `:` separator (e.g. `field_tags:entity:name`). |
| `type` | Index data type (see field type table below) |
| `boost` | Relevance boost. Default `1.0`. Higher values weight this field more in search ranking. |
| `configuration` | Extra settings for computed fields like `rendered_item` |

**Search API field types:**

| Type | Use |
|---|---|
| `text` | Full-text searchable. Processed through tokenizer, stemmer, etc. |
| `string` | Exact match. Not tokenized. Used for facets and filters. |
| `integer` | Numeric, whole numbers. Entity reference target IDs. |
| `decimal` | Numeric with fractional part. |
| `date` | Timestamp. Stored as Unix epoch or ISO format depending on backend. |
| `boolean` | True/false. Publishing status, sticky flag, etc. |
| `fulltext` | Alias for `text` in some contexts. |

**`datasource_settings`** controls which entities and bundles to index:

```yaml
datasource_settings:
  'entity:node':
    bundles:
      default: true    # true = all bundles except 'selected'; false = only 'selected'
      selected:
        - article
        - page
    languages:
      default: true    # true = all languages except 'selected'
      selected: []
```

Multiple datasources in one index (nodes + taxonomy terms) are valid but uncommon.

**`tracker_settings`** controls how Drupal tracks which items need (re)indexing:

| Setting | Meaning |
|---|---|
| `default` | Standard tracker. Tracks items via a database queue. |
| `indexing_order` | `fifo` (first in, first out) or `lifo` (newest first) |

**`options`**:

| Key | Meaning |
|---|---|
| `index_directly` | Index items on entity save (not just on cron). Adds write latency but keeps index fresh. |
| `cron_limit` | Max items to index per cron run. 0 = unlimited. |

### 2b. Processor Reference

Processors transform content before indexing and modify queries at search time. They run in weight order (lower = earlier).

| Processor | Purpose | Key settings |
|---|---|---|
| `add_url` | Adds the entity URL to the index | None |
| `aggregated_field` | Combines multiple fields into one searchable field | Field list, aggregation type (`union`, `concat`, `first`, `last`, `max`, `min`, `sum`, `count`) |
| `content_access` | Filters results by node access grants | None (enable/disable only) |
| `entity_status` | Excludes unpublished entities | None |
| `highlight` | Highlights search terms in results | `prefix`, `suffix` (HTML tags), `excerpt` (boolean), `excerpt_length` |
| `html_filter` | Strips HTML, optionally boosts tag content | `tags` map (tag name to boost weight), `title`/`alt` (index those attributes) |
| `ignorecase` | Lowercases all text | `all_fields` or specific `fields` list |
| `language_with_fallback` | Indexes content with language fallback chain | None |
| `rendered_item` | Indexes fully rendered entity HTML | `roles` (render as which user), `view_mode` per bundle |
| `stemmer` | Reduces words to root form (English by default) | `exceptions` map for overrides |
| `stopwords` | Removes common words | `stopwords` list |
| `tokenizer` | Splits text into words | `minimum_word_size`, `overlap_cjk` (CJK bigram tokenization), `spaces` (extra split chars) |
| `transliteration` | Converts accented characters to ASCII | `all_fields` or `fields` |
| `type_boost` | Boosts results by entity type or bundle | `boosts` map per datasource and bundle |
| `number_field_boost` | Boosts by a numeric field value (e.g. view count) | `boost_factor`, `aggregation` |
| `role_filter` | Indexes content visible to specific roles | `roles` list, `default` flag |
| `hierarchy` | Indexes taxonomy term ancestors | `fields` map with hierarchy types |

### 2c. Via Drush

```bash
# List all indexes with server, indexing status, item counts
drush search-api:list --format=json

# Detailed status for one index
drush search-api:status content --format=json

# Export index config
drush config:get search_api.index.content --format=yaml

# List all search_api configs at once
drush config:list --prefix=search_api --format=list
```

Output from `search-api:list` shows:
- Index ID and name
- Server it connects to
- Datasource types
- Total items, indexed items, remaining items

### 2d. Via Database (D7)

```sql
-- D7 search_api indexes (stored as entities, not config)
SELECT id, name, machine_name, description, server, item_type, options, enabled, read_only
FROM search_api_index;
```

The `options` column is PHP-serialized. It contains:
- `fields`: map of field machine names to type and boost
- `processors`: keyed by processor name, each with `status`, `weight`, `settings`
- `datasource`: settings for the datasource plugin
- `cron_limit`: items per cron run
- `index_directly`: boolean

The `item_type` column indicates the entity type (e.g. `node`, `taxonomy_term`, `user`).

**D7 apachesolr alternative:**

apachesolr does not use discrete index entities. Configuration is per-environment:

```sql
-- Which entity types and bundles are indexed
SELECT env_id, entity_type, bundle
FROM apachesolr_index_bundles;

-- Custom field bias (boost) settings
SELECT env_id, field_name, boost
FROM apachesolr_index_field_weights
WHERE env_id = 'solr';

-- Type-level bias
SELECT env_id, bundle, boost
FROM apachesolr_index_type_weights
WHERE env_id = 'solr';
```

---

## 3. Facets

Facets let users filter search results by field values (category, date range, content type, author). The `facets` module (D8+) provides this. In D7, `facetapi` handles it.

### 3a. Via Config YAML (D8+)

Facet definitions live in `facets.facet.{machine_name}.yml`:

```yaml
# facets.facet.content_type.yml
uuid: c3d4e5f6-...
langcode: en
status: true
dependencies:
  config:
    - search_api.index.content
  module:
    - facets
    - search_api
id: content_type
name: 'Content Type'
url_alias: type
weight: 0
show_only_one_result: false
field_identifier: type
query_type: search_api_string
facet_source_id: 'search_api:views_page__search__page_1'
widget:
  type: links
  config:
    show_numbers: true
    soft_limit: 0
    soft_limit_settings:
      show_less_label: 'Show less'
      show_more_label: 'Show more'
    exclude_when_empty: true
empty_behavior:
  behavior: none
processor_configs:
  active_widget_order:
    processor_id: active_widget_order
    weights:
      sort: 20
    settings:
      sort: ASC
  count_widget_order:
    processor_id: count_widget_order
    weights:
      sort: 30
    settings:
      sort: DESC
  display_value_widget_order:
    processor_id: display_value_widget_order
    weights:
      sort: 40
    settings:
      sort: ASC
  url_processor_handler:
    processor_id: url_processor_handler
    weights:
      pre_query: 50
      build: 15
    settings:
      filter_key: f
      separator: ':'
      active_separator: '||'
  exclude_specified_items:
    processor_id: exclude_specified_items
    weights:
      build: 50
    settings:
      exclude: ''
      regex: false
  count_limit:
    processor_id: count_limit
    weights:
      build: 60
    settings:
      minimum_items: 1
      maximum_items: 0
  translate_entity:
    processor_id: translate_entity
    weights:
      build: 5
    settings: {}
  hide_non_narrowing_result_processor:
    processor_id: hide_non_narrowing_result_processor
    weights:
      build: 40
    settings: {}
show_title: true
use_admin_theme: false
keep_hierarchy_parents_active: false
expand_hierarchy: false
enable_parent_when_child_gets_disabled: true
hard_limit: 0
min_count: 1
missing: false
missing_label: ''
```

| Key | Meaning |
|---|---|
| `id` | Machine name of this facet |
| `name` | Display label |
| `url_alias` | URL query parameter name (e.g. `?f[0]=type:article`) |
| `field_identifier` | The indexed field this facet filters on |
| `query_type` | How to query: `search_api_string`, `search_api_range`, `search_api_date` |
| `facet_source_id` | Which search display powers this facet. Format: `search_api:views_{display_type}__{view_id}__{display_id}` |
| `widget.type` | UI widget: `links`, `checkbox`, `dropdown`, `array` (raw values), `range_slider` |
| `widget.config` | Widget settings: `show_numbers`, `soft_limit`, etc. |
| `empty_behavior` | What to show when no results: `none`, `text` (custom message) |
| `hard_limit` | Max facet items to show. 0 = unlimited. |
| `min_count` | Hide facet values with fewer than this many results |
| `missing` | Show a "missing" option for items without a value |
| `show_title` | Render the facet label above the widget |
| `processor_configs` | Sorting and filtering rules (see below) |

**Facet processors** (sorting and filtering, not to be confused with Search API processors):

| Processor | Purpose |
|---|---|
| `active_widget_order` | Sort active (selected) items |
| `count_widget_order` | Sort by result count |
| `display_value_widget_order` | Sort alphabetically by display value |
| `url_processor_handler` | Controls URL format. `filter_key` is the query param (default `f`). `separator` splits field name from value. |
| `exclude_specified_items` | Hide specific facet values. Supports regex. |
| `count_limit` | Hide items below `minimum_items` count or above `maximum_items` |
| `translate_entity` | Translate entity reference labels to current language |
| `hide_non_narrowing_result_processor` | Hide items that would not reduce the result set |

**Facet summary** (combined facet block):

```yaml
# facets_summary.facets_summary.search_summary.yml
id: search_summary
name: 'Search Summary'
facets:
  content_type:
    checked: true
    label: 'Content Type'
    separator: ', '
    show_count: true
  tags:
    checked: true
    label: Tags
    separator: ', '
    show_count: false
facet_source:
  id: 'search_api:views_page__search__page_1'
```

### 3b. Via Drush

```bash
# List all facet configs
drush config:list --prefix=facets.facet --format=list

# Export a specific facet
drush config:get facets.facet.content_type --format=yaml

# Facet summaries
drush config:list --prefix=facets_summary --format=list
```

### 3c. Via Database (D7 facetapi)

D7 uses the `facetapi` module. Facet configuration lives in the database or in Features exports:

```sql
-- facetapi settings (stored as ctools exportables)
SELECT name, value FROM variable WHERE name LIKE 'facetapi:%';

-- If using ctools export, check the facetapi table
SELECT * FROM facetapi;
```

D7 facetapi config keys encode the searcher, realm, and facet name in a colon-separated string. The `value` is PHP-serialized and contains:
- `widget`: display type (`facetapi_links`, `facetapi_checkbox_links`, `facetapi_select`)
- `soft_limit`: number of items before "Show more"
- `sort_weight`, `sort_order`: sorting per algorithm
- `filters`: count minimum, exclude items, rewrite values

---

## 4. Search Pages and Views

Most search interfaces are built as Views with exposed filters. The search_api module also provides a standalone search page plugin.

### 4a. Search API Pages Module

If `search_api_page` is installed:

```yaml
# search_api_page.search_api_page.site_search.yml
id: site_search
label: 'Site Search'
index: content
path: search
limit: 10
show_search_form: true
show_all_when_no_query: false
clean_url: true
style: default
```

| Key | Meaning |
|---|---|
| `index` | Which Search API index to query |
| `path` | URL path for the search page |
| `limit` | Results per page |
| `show_search_form` | Display search input on results page |
| `clean_url` | Use `/search/query` instead of `/search?keys=query` |
| `style` | Display format |

```bash
drush config:list --prefix=search_api_page --format=list
```

### 4b. Views-Based Search

The more common pattern. A View uses a Search API index as its base table.

In `views.view.{view_name}.yml`, look for:
- `base_table` starting with `search_api_index_` (e.g. `search_api_index_content`)
- Exposed filter for `search_api_fulltext` (the search keywords input)
- Contextual filters, sorts, and relationships

Export these using Skill 05 (Views Export). When the base table starts with `search_api_index_`, the View queries the search index instead of the database.

Search-specific View features to capture:
- `search_api_fulltext` filter: `parse_mode` (`terms` = AND, `direct` = raw query syntax, `phrase` = exact match)
- `search_api_fulltext` filter: `fields` (which indexed fields to search, empty = all fulltext fields)
- `search_api_more_like_this` contextual filter (related content)
- `search_api_rendered_item` row plugin

### 4c. Facet-to-View Binding

Facets bind to a specific View display through the `facet_source_id`. The format is:

```
search_api:views_{display_plugin}__{view_id}__{display_id}
```

Examples:
- `search_api:views_page__search__page_1` = page display `page_1` of the `search` View
- `search_api:views_block__search__block_1` = block display `block_1`

Extract all unique `facet_source_id` values to map which facets belong to which search display.

---

## 5. Autocomplete

The `search_api_autocomplete` module adds suggestions to search inputs.

### 5a. Via Config YAML

```yaml
# search_api_autocomplete.search.content_search.yml
id: content_search
label: 'Content search'
index_id: content
search_id: 'views:search'
suggestion_limit: 10
status: true
type_settings:
  custom:
    status: false
  live_results:
    status: true
    display:
      view_mode:
        'entity:node': teaser
    limit: 5
  server:
    status: true
    limit: 10
```

| Key | Meaning |
|---|---|
| `index_id` | Which Search API index |
| `search_id` | Which search plugin (usually `views:{view_id}`) |
| `suggestion_limit` | Max total suggestions |
| `type_settings.server` | Use the backend's native suggest (Solr Suggester, etc.) |
| `type_settings.live_results` | Show actual results as suggestions. `view_mode` controls rendering. |
| `type_settings.custom` | Custom suggestion callback |

```bash
drush config:list --prefix=search_api_autocomplete --format=list
```

---

## 6. Core Search Module

Some sites use Drupal's core Search module instead of (or alongside) Search API. It has no external backend. Indexing runs on cron and stores results in dedicated database tables.

### 6a. Via Config YAML (D8+)

```yaml
# search.page.node_search.yml
id: node_search
label: 'Content'
path: node
weight: -10
plugin: node_search
configuration: {}
status: true

# search.page.user_search.yml
id: user_search
label: Users
path: user
weight: 0
plugin: user_search
configuration: {}
status: true

# search.settings.yml
active_plugins:
  - node_search
  - user_search
default_page: node_search
index:
  cron_limit: 100
  minimum_word_size: 3
  overlap_cjk: true
logging: false
```

| Setting | Meaning |
|---|---|
| `active_plugins` | Which search page plugins are enabled |
| `default_page` | Default search tab |
| `index.cron_limit` | Items indexed per cron run |
| `index.minimum_word_size` | Words shorter than this are ignored |
| `index.overlap_cjk` | CJK character bigram tokenization |

### 6b. Via Database (D7)

```sql
-- Core search settings
SELECT name, value FROM variable WHERE name LIKE 'search_%';

-- Key variables:
-- search_active_modules: serialized array of enabled search modules
-- search_cron_limit: items per cron
-- search_minimum_word_size: minimum word length (default 3)
-- search_overlap_cjk: boolean

-- Core search index state
SELECT word, sid, type, score
FROM search_index
LIMIT 100;

-- Total indexed items
SELECT type, COUNT(DISTINCT sid) as indexed_count
FROM search_index
GROUP BY type;
```

### 6c. Via Drush

```bash
# D8+ core search status
drush search:status --format=json

# Reindex (planning reference only, not needed for export)
drush search:index
```

---

## 7. Full Export Procedure

### Step 1: Identify the search stack

```bash
# Check which search modules are installed
drush pm:list --status=enabled --format=json | python3 -c "
import json, sys
mods = json.load(sys.stdin)
search_mods = {k: v for k, v in mods.items()
               if any(s in k.lower() for s in ['search', 'solr', 'elastic', 'facet', 'algolia', 'typesense', 'meilisearch'])}
for name, info in search_mods.items():
    print(f\"{name}: {info.get('status', 'unknown')} ({info.get('version', 'n/a')})\")"
```

Common module combinations:
- `search_api` + `search_api_solr` + `facets` = Solr-backed faceted search
- `search_api` + `search_api_db` + `facets` = Database-backed faceted search (simpler sites)
- `search_api` + `elasticsearch_connector` = Elasticsearch-backed search
- `search` (core) only = basic built-in search
- D7: `apachesolr` + `facetapi` = older Solr integration
- D7: `search_api` + `search_api_solr` + `facetapi` = newer D7 Solr integration

### Step 2: Export server config

```bash
# All search_api server configs
for cfg in $(drush config:list --prefix=search_api.server --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done
```

### Step 3: Export index config

```bash
# All search_api index configs
for cfg in $(drush config:list --prefix=search_api.index --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done

# Index status (item counts, remaining)
drush search-api:list --format=json > export/search_api_index_status.json
```

### Step 4: Export facet config

```bash
# All facets
for cfg in $(drush config:list --prefix=facets.facet --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done

# Facet summaries
for cfg in $(drush config:list --prefix=facets_summary --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done
```

### Step 5: Export search pages and autocomplete

```bash
# Search API pages
for cfg in $(drush config:list --prefix=search_api_page --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done

# Autocomplete
for cfg in $(drush config:list --prefix=search_api_autocomplete --format=list); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done

# Core search settings
drush config:get search.settings --format=yaml > export/search.settings.yml 2>/dev/null
for cfg in $(drush config:list --prefix=search.page --format=list 2>/dev/null); do
  drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
done
```

### Step 6: Export search Views

```bash
# Find Views that use search_api indexes as base table
for cfg in $(drush config:list --prefix=views.view --format=list); do
  base=$(drush config:get "$cfg" base_table --format=string 2>/dev/null)
  if echo "$base" | grep -q "search_api_index"; then
    echo "Search View: $cfg (base: $base)"
    drush config:get "$cfg" --format=yaml > "export/${cfg}.yml"
  fi
done
```

### Step 7: Config sync directory alternative

If you have the config sync directory but no Drush:

```bash
CONFIG_DIR="config/sync"  # adjust path

# Servers
cp "$CONFIG_DIR"/search_api.server.*.yml export/ 2>/dev/null

# Indexes
cp "$CONFIG_DIR"/search_api.index.*.yml export/ 2>/dev/null

# Facets
cp "$CONFIG_DIR"/facets.facet.*.yml export/ 2>/dev/null
cp "$CONFIG_DIR"/facets_summary.*.yml export/ 2>/dev/null

# Search pages + autocomplete
cp "$CONFIG_DIR"/search_api_page.*.yml export/ 2>/dev/null
cp "$CONFIG_DIR"/search_api_autocomplete.*.yml export/ 2>/dev/null

# Core search
cp "$CONFIG_DIR"/search.settings.yml export/ 2>/dev/null
cp "$CONFIG_DIR"/search.page.*.yml export/ 2>/dev/null

# Views that use search indexes
grep -l "search_api_index" "$CONFIG_DIR"/views.view.*.yml 2>/dev/null | while read f; do
  cp "$f" export/
done
```

---

## 8. Migration Target Mapping

Drupal search concepts map to other platforms with varying fidelity. Use this table to guide the translation.

### Search Backend Mapping

| Drupal backend | Direct equivalent | Notes |
|---|---|---|
| Solr (search_api_solr) | Solr, Elasticsearch, Meilisearch, Typesense | Solr schema translates to any full-text engine. Field types and analyzers need per-engine translation. |
| Elasticsearch (elasticsearch_connector) | Elasticsearch, OpenSearch | Index mappings transfer with minor syntax changes. |
| Database (search_api_db) | Algolia, Meilisearch, Typesense, PostgreSQL full-text | Database backend is the simplest to migrate. No external service config to replicate. |
| Core Search | Any | Minimal config. Rebuild from scratch on the target. |

### Field Type Mapping

| Search API type | Algolia | Meilisearch | Typesense | Elasticsearch |
|---|---|---|---|---|
| `text` | searchableAttributes | searchableAttributes | `string` (index: true) | `text` with analyzer |
| `string` | attributesForFaceting | filterableAttributes | `string` (facet: true) | `keyword` |
| `integer` | attributesForFaceting | filterableAttributes | `int32` or `int64` | `integer` or `long` |
| `decimal` | attributesForFaceting | filterableAttributes | `float` | `float` or `double` |
| `date` | attributesForFaceting | filterableAttributes + sortableAttributes | `int64` (Unix timestamp) | `date` |
| `boolean` | attributesForFaceting | filterableAttributes | `bool` | `boolean` |

### Processor Mapping

| Drupal processor | Target platform handling |
|---|---|
| `html_filter` | Strip HTML before indexing. All platforms expect plain text. |
| `tokenizer` | Built into every search engine. Configure via analyzer/tokenizer settings. |
| `stemmer` | Algolia: use `queryLanguages`. Meilisearch: built-in per language. Elasticsearch: `stemmer` token filter. Typesense: built-in per language. |
| `stopwords` | Algolia: `removeStopWords`. Meilisearch: `stopWords` setting. Elasticsearch: `stop` token filter. Typesense: built-in. |
| `ignorecase` | All platforms lowercase by default during indexing. |
| `transliteration` | Algolia: built-in. Meilisearch: built-in. Elasticsearch: `asciifolding` filter. Typesense: built-in. |
| `content_access` | No direct equivalent. Implement as a filter on query time using user roles/permissions. |
| `highlight` | Algolia: `attributesToHighlight`. Meilisearch: built-in. Elasticsearch: `highlight` query param. Typesense: `highlight_fields`. |
| `type_boost` | Algolia: `optionalFilters` with boost. Elasticsearch: `function_score`. Meilisearch: `rankingRules`. Typesense: no direct equivalent (use `pinned_hits` or query-time boost). |
| `aggregated_field` | Concatenate fields at index time in your data pipeline. |

### Facet Mapping

| Drupal facet concept | Algolia | Meilisearch | Typesense | Elasticsearch |
|---|---|---|---|---|
| Facet field | `attributesForFaceting` | `filterableAttributes` | `facet_by` query param | `aggs` in query body |
| Facet widget (links/checkbox) | Frontend concern (InstantSearch.js widgets) | Frontend (InstantSearch.js) | Frontend (InstantSearch adapter) | Frontend or custom UI |
| URL alias | Frontend routing | Frontend routing | Frontend routing | Frontend routing |
| Count limit / min_count | `maxValuesPerFacet` | `maxValuesPerFacet` (default 100) | `max_facet_values` | `size` in aggs |
| Hierarchical facets | `hierarchicalFacets` in InstantSearch.js | `filterableAttributes` + frontend logic | Not built-in | `terms` agg with `path_hierarchy` tokenizer |
| Facet summary | Frontend component | Frontend component | Frontend component | Frontend component |

### Autocomplete Mapping

| Drupal autocomplete type | Target |
|---|---|
| Server suggestions (Solr Suggester) | Algolia: Query Suggestions. Meilisearch: built-in search-as-you-type. Typesense: built-in. Elasticsearch: Completion Suggester. |
| Live results | All platforms: query on keystroke with `limit` param. Render results in dropdown. |

---

## 9. Output Format

Produce one JSON file per index:

```json
{
  "index_id": "content",
  "index_name": "Content Index",
  "server": {
    "id": "solr_main",
    "name": "Main Solr Server",
    "backend": "search_api_solr",
    "connector": "standard",
    "host": "solr.example.com",
    "port": 8983,
    "core": "drupal"
  },
  "datasources": [
    {
      "id": "entity:node",
      "bundles": {
        "mode": "all",
        "selected": []
      }
    }
  ],
  "fields": [
    {
      "id": "title",
      "label": "Title",
      "datasource": "entity:node",
      "property_path": "title",
      "type": "text",
      "boost": 5.0
    },
    {
      "id": "body",
      "label": "Body",
      "datasource": "entity:node",
      "property_path": "body",
      "type": "text",
      "boost": 1.0
    }
  ],
  "processors": [
    {
      "id": "html_filter",
      "settings": {
        "fields": ["body", "rendered_item"],
        "tags": {"h1": 5, "h2": 3, "h3": 2, "strong": 2}
      }
    },
    {
      "id": "stemmer",
      "settings": {
        "all_fields": true,
        "exceptions": {}
      }
    }
  ],
  "tracker": {
    "type": "default",
    "indexing_order": "fifo"
  },
  "options": {
    "index_directly": true,
    "cron_limit": 50
  },
  "facets": [
    {
      "id": "content_type",
      "name": "Content Type",
      "field": "type",
      "url_alias": "type",
      "widget": "links",
      "source_view": "search:page_1",
      "show_counts": true,
      "hard_limit": 0,
      "min_count": 1,
      "sort": "count_desc"
    }
  ],
  "autocomplete": {
    "enabled": true,
    "suggestion_limit": 10,
    "live_results": true,
    "server_suggestions": true
  },
  "status": {
    "total_items": 15420,
    "indexed_items": 15420,
    "remaining": 0
  }
}
```

Produce a separate summary file listing all search infrastructure:

```json
{
  "search_stack": {
    "modules": ["search_api", "search_api_solr", "facets", "search_api_autocomplete"],
    "backend": "solr",
    "core_search_enabled": false
  },
  "servers": [
    {"id": "solr_main", "backend": "search_api_solr", "status": "enabled"}
  ],
  "indexes": [
    {"id": "content", "server": "solr_main", "items": 15420, "indexed": 15420}
  ],
  "facets_count": 8,
  "search_views": ["search"],
  "search_pages": [],
  "autocomplete_enabled": true
}
```
