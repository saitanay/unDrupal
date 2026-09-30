# Common Contrib Modules: Data Patterns and Migration Impact

This reference covers 35+ major Drupal contrib modules, their data storage patterns, and how they affect migration.

## Migration Impact Classification

| Level | Meaning |
|-------|---------|
| **High** | Changes core data structures. Ignoring it loses content or breaks relationships. |
| **Medium** | Adds data that enriches content. Can be skipped but leaves gaps. |
| **Low** | Configuration or presentation. Can be rebuilt in the target platform. |

---

## Content Structure Modules

### Paragraphs

**Impact: High**

Component-based content. Nodes reference typed paragraph entities instead of storing content in a single body field.

| Table | Purpose |
|-------|---------|
| `paragraphs_item` | Base table |
| `paragraphs_item_field_data` | Translatable fields + parent tracking |
| `paragraphs_item_revision` | Revisions |
| `paragraph__field_{name}` | Per-paragraph-type field data |

See `drupal-paragraph-patterns.md` for full details.

### Paragraphs Library

**Impact: Medium**

Reusable paragraphs shared across nodes.

| Table | Purpose |
|-------|---------|
| `paragraphs_library_item` | Library item entity |
| `paragraphs_library_item_field_data` | Label and paragraph reference |

A library item references a paragraph. Multiple nodes reference the same library item.

### Layout Paragraphs

**Impact: Medium**

Extends Paragraphs with layout and grid capabilities. A behavior plugin adds layout metadata to paragraph entities. Paragraphs gain parent-child relationships and region placement without separate tables.

| Field | Purpose |
|-------|----------|
| `behavior_settings.layout_paragraphs.parent_uuid` | UUID of the parent paragraph that acts as a layout container |
| `behavior_settings.layout_paragraphs.region` | Region within the parent layout where this paragraph renders |
| `behavior_settings.layout_paragraphs.layout` | Layout plugin ID (e.g. `layout_twocol`, `layout_threecol_section`) on container paragraphs |
| `behavior_settings.layout_paragraphs.config` | Layout-specific configuration (column widths, classes) |

Behavior settings are serialized into the `behavior_settings` column on `paragraphs_item_field_data`. Query them by unserializing that column. Paragraphs without a `parent_uuid` sit at the root level. See skill 12 (Layout Paragraphs section).

### Field Collection (D7)

**Impact: High** (D7 only)

Predecessor to Paragraphs. Field collections are entities attached to a host entity through a field. Each collection item holds its own fields.

| Table | Purpose |
|-------|----------|
| `field_collection_item` | Base table: `item_id`, `revision_id`, `field_name`, `archived` |
| `field_collection_item_revision` | Revisions |
| `field_data_field_{name}` | Host entity's reference to field collection items |
| `field_data_field_{fc_field}` | Fields on the collection items themselves |

The host relationship is stored in the field that references the collection. The `field_name` column on `field_collection_item` identifies which field on the host entity owns the item. D7-to-modern migrations must reconstruct these as Paragraphs or equivalent nested structures. See skill 12 (Field Collections section).

### Entity Reference Revisions

**Impact: High**

Field type for revision-pinned references. Used by Paragraphs. See `drupal-field-types.md` for column details.

### Layout Builder

**Impact: High**

Stores per-entity layout overrides as serialized data in a field.

| Storage | Location |
|---------|----------|
| Default layouts | `core.entity_view_display.{entity_type}.{bundle}.{view_mode}` config |
| Per-entity overrides | `node__layout_builder__layout` field table |
| Column | `layout_builder__layout_section` (serialized PHP array of `Section` objects) |

Each section contains a layout plugin ID, layout settings, and an array of `SectionComponent` objects with block plugin IDs, configuration, and weight.

Parsing requires PHP unserialization. The serialized data references block plugin IDs like `inline_block:basic`, `field_block:node:article:body`, `views_block:view_name-display_id`.

### Experience Builder (Core, D11+)

**Impact: High**

Canvas-style page builder that replaces Layout Builder in Drupal 11. Stores component trees with typed props and slots.

| Storage | Location |
|---------|----------|
| Component tree | Serialized in a field on the entity, similar to Layout Builder |
| Component definitions | SDC-based YAML + Twig in the theme/module `components/` directory |
| Props | Typed values (string, entity reference, media) passed to components |
| Slots | Named regions that accept nested component trees |

The component tree is a nested structure of component instances. Each instance references a component ID (SDC machine name), prop values, and slot contents. Prop values can be static or field-mapped. Extraction requires PHP unserialization of the tree, then recursive traversal of slots to collect all referenced content. See skill 33.

### Site Studio (Cohesion)

**Impact: High**

Acquia's visual page builder. Stores layout and component configuration as JSON blobs in `cohesion_layout` fields.

| Storage | Location |
|---------|----------|
| Layout JSON | `node__cohesion_layout` field table, `cohesion_layout_value` column |
| Component config | `cohesion_component` config entities |
| Style config | `cohesion_custom_style`, `cohesion_style_guide` config entities |
| Templates | `cohesion_content_templates` config entities |

The JSON blob defines a tree of elements, each with a UUID, type, styles, and child elements. Component instances reference component config entities by UUID. Styles are stored as separate JSON objects with breakpoint-specific CSS properties. The module uses `sitestudio_*` table prefixes for some data.

Extracting content requires parsing the JSON tree, resolving component references, and separating content values from layout/style metadata. See skill 34.

### Gutenberg

**Impact: High**

WordPress block editor ported to Drupal. Stores block content as serialized HTML with comment delimiters in text fields.

| Storage | Location |
|---------|----------|
| Block content | Standard `node__body` or `node__field_{name}` text field |
| Block delimiters | `<!-- wp:block-name {"attr":"value"} -->` HTML comments |
| Reusable blocks | Stored as separate entities referenced by ID |

Block content looks like regular HTML but is structured by comment markers:

```html
<!-- wp:paragraph -->
<p>Text content here.</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":42,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large">
  <img src="/sites/default/files/photo.jpg" alt="" />
</figure>
<!-- /wp:image -->
```

Parsing requires splitting on the comment delimiters to extract block type, JSON attributes, and inner HTML. Nested blocks (columns, groups) contain child blocks between their opening and closing comments. See skill 35.

### Single Directory Components (SDC, Core D10.1+)

**Impact: Low**

Component definition system. Each component lives in a single directory with a YAML metadata file, Twig template, and optional CSS/JS.

No data storage. SDC defines component contracts: prop schemas (JSON Schema), slots, and library dependencies. Experience Builder and Layout Builder reference SDC components by machine name.

Useful during migration for mapping Drupal component structures to target platform equivalents. The prop schemas document expected data shapes. Slot definitions show where nested content goes. See skill 16 (SDC section).

### Field Group

**Impact: Low**

Groups fields in the edit/display form. Presentation only. No content tables.

Config: `field_group.group_{entity_type}.{bundle}.{form_mode}.{group_name}`

---

## Media and Files

### Media (Core, D8.5+)

**Impact: High**

Wraps files in typed media entities. See `drupal-entity-types.md`.

### Focal Point

**Impact: Medium**

Stores a focal point (crop center) per image.

| Table | Purpose |
|-------|---------|
| `crop` | `cid`, `type`, `entity_id`, `entity_type`, `uri`, `height`, `width`, `x`, `y` |
| `crop_field_data` | Same with langcode support |

The `x` and `y` values are pixel coordinates relative to the original image. Convert to percentage: `x_pct = x / width * 100`.

### Crop API

**Impact: Medium**

Manual crop regions per image per crop type.

Same `crop` table as Focal Point. When both are installed, focal point entries have `type = 'focal_point'` and manual crops have type matching the crop type machine name.

### File Entity (D7)

**Impact: High** (D7 only)

Turns files into fieldable entities in D7. Adds a `type` to file_managed:

```sql
-- D7 with file_entity
SELECT fid, type, filename, uri, filemime FROM file_managed;
-- type values: image, video, audio, document
```

---

## SEO and URL

### Pathauto

**Impact: Medium**

Auto-generates URL aliases from token patterns. The aliases themselves are stored in:
- D7: `url_alias`
- D9+: `path_alias` entity tables

The patterns are config: `pathauto.pattern.{id}`. Migration needs the aliases, not the patterns.

### Redirect

**Impact: High**

HTTP redirect records. Losing these breaks inbound links and SEO.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `redirect` | `rid` | `redirect_source__path`, `redirect_source__query`, `redirect_redirect__uri`, `redirect_redirect__title`, `status_code`, `language` |

### Metatag

**Impact: Medium**

Per-entity meta tags stored as a serialized field.

| Table | Column |
|-------|--------|
| `node__field_metatag` | `field_metatag_value` (serialized PHP array) |

```php
// Typical serialized value
a:3:{
  s:5:"title";s:21:"[node:title] | [site:name]";
  s:11:"description";s:16:"[node:summary]";
  s:8:"og_image";s:27:"[node:field_image:entity:url]";
}
```

D7 stores metatags in a dedicated table: `metatag` with `entity_type`, `entity_id`, `language`, `data` (serialized).

### XML Sitemap

**Impact: Low**

Generated sitemap. No content data. Rebuild in target platform.

### Simple XML Sitemap

**Impact: Low**

Same as XML Sitemap. Config only.

---

## Search

### Search API

**Impact: Medium**

Search index configuration. The index config defines which fields are indexed and how. Content data comes from the source entities.

Config entities:
- `search_api.server.{name}` (backend: Solr, Elasticsearch, database)
- `search_api.index.{name}` (fields, processors, datasources)

### Search API Solr

**Impact: Low**

Solr backend for Search API. Index is rebuilt from source data.

---

## Forms

### Webform

**Impact: High**

Form builder with submission storage.

| Table | Purpose |
|-------|---------|
| `webform_submission` | Submission metadata |
| `webform_submission_data` | EAV storage: `webform_id`, `sid`, `name`, `property`, `delta`, `value` |

Form definitions are config entities: `webform.webform.{id}` with `elements` as a YAML string defining form structure.

```yaml
# webform.webform.contact_us
elements: |
  name:
    '#type': textfield
    '#title': 'Your Name'
    '#required': true
  email:
    '#type': email
    '#title': 'Email'
  message:
    '#type': textarea
    '#title': 'Message'
```

### Entityform (D7)

**Impact: High**

D7 equivalent of Webform for structured form submissions. Submissions are fieldable entities.

| Table | Purpose |
|-------|---------|
| `entityform` | Base table |
| `entityform_type` | Form type definitions |
| `field_data_field_{name}` | Form field values (standard D7 field tables) |

---

## Commerce

### Drupal Commerce (2.x for D8+)

**Impact: High**

Full e-commerce platform. See `drupal-entity-types.md` for table details.

Key data relationships:

```
commerce_store
  └── commerce_product (references store)
       └── commerce_product_variation (references product)
            └── price, SKU, stock, attributes

commerce_order
  ├── commerce_order_item (references order + purchased entity)
  ├── field_billing_profile (address)
  ├── field_shipping_profile (address via commerce_shipping)
  └── commerce_payment (references order)
```

### Commerce License

**Impact: High**

Digital product access.

| Table | Purpose |
|-------|---------|
| `commerce_license` | `license_id`, `type`, `uid`, `state`, `product_variation`, `granted`, `expires`, `renewed` |

### Commerce Stock

**Impact: Medium**

Inventory tracking.

| Table | Purpose |
|-------|---------|
| `commerce_stock_transaction` | Stock movements per variation per location |
| `commerce_stock_location` | Warehouse/location entities |

### Ubercart (D7)

**Impact: High**

D7 commerce. Different schema from Commerce 2.x.

| Table | Purpose |
|-------|---------|
| `uc_orders` | Orders |
| `uc_order_products` | Line items |
| `uc_order_line_items` | Additional charges |
| `uc_products` | Product data (extends nodes) |

---

## Content Moderation and Workflow

### Content Moderation (Core)

**Impact: Medium**

Editorial workflow states per entity revision.

| Table | Purpose |
|-------|---------|
| `content_moderation_state` | Current moderation state per entity |
| `content_moderation_state_field_data` | `content_entity_type_id`, `content_entity_id`, `content_entity_revision_id`, `moderation_state`, `workflow` |

Workflow config: `workflows.workflow.{name}` defines states (`draft`, `review`, `published`) and transitions.

### Workbench Moderation (D7/D8 contrib, replaced by core)

**Impact: Medium**

Predecessor to core content moderation. D7 uses `workbench_moderation_node_history` table.

### Workspaces (Core, D9+)

**Impact: Medium**

Content staging system. Workspaces let editors prepare changes in parallel without affecting the live site. Each workspace tracks entity revisions that differ from the live version.

| Table | Purpose |
|-------|----------|
| `workspace` | Workspace entity: `id`, `label`, `uid`, `created`, `changed` |
| `workspace_association` | Links entities to workspaces: `workspace`, `target_entity_type_id`, `target_entity_id`, `target_entity_revision_id` |

The `workspace_association` table is the key migration artifact. It maps which entity revision belongs to which workspace. When a workspace is published, its tracked revisions become the live versions.

For migration, decide whether to export only the live (published) workspace content or preserve staging state. Most migrations take only the live content and ignore workspace associations. See skill 09 (Workspaces section).

### Scheduler

**Impact: Medium**

Scheduled publish/unpublish dates.

| Table | Key Columns |
|-------|-------------|
| `node__field_scheduler_publish_on` | `field_scheduler_publish_on_value` (timestamp) |
| `node__field_scheduler_unpublish_on` | `field_scheduler_unpublish_on_value` (timestamp) |

Older versions use a dedicated `scheduler` table.

---

## Translation and Multilingual

### Content Translation (Core)

**Impact: High**

Translations stored as additional rows in `node_field_data` and field tables, keyed by `langcode`.

No separate tables. Query with `WHERE default_langcode = 0` for translations.

### Interface Translation (Core)

**Impact: Low**

UI string translations. Stored in `locales_source` and `locales_target`. Not content data.

### Configuration Translation (Core)

**Impact: Medium**

Translated config labels and text. Stored in `config` table with collection = `language.{langcode}`.

### TMGMT (Translation Management)

**Impact: Low**

Translation workflow tool. Job data is operational, not content.

---

## Address and Location

### Address

**Impact: High**

Composite address field. See `drupal-field-types.md` for all columns.

### Geocoder

**Impact: Low**

Geocodes addresses to lat/lng on save. The geocoded values land in a geofield. No separate tables.

### Geofield

**Impact: Medium**

Geospatial data. See `drupal-field-types.md` for columns.

---

## Access Control

### Group

**Impact: Medium**

Organizes content and users into groups with group-level permissions.

| Table | Purpose |
|-------|---------|
| `groups` | Group entity base table |
| `groups_field_data` | Group label, type, uid |
| `group_content` | Membership and content relationships: `type`, `gid`, `entity_id`, `uid` |

### Domain / Domain Access

**Impact: Medium**

Multi-domain content assignment from a single Drupal database. The `domain` module creates domain entities. The `domain_access` module adds fields to content types for domain assignment.

| Table | Key Columns |
|-------|-------------|
| `config: domain.record.{name}` | Domain entity: `id`, `name`, `hostname`, `scheme`, `status`, `weight`, `is_default` |
| `node__field_domain_access` | `field_domain_access_target_id` (domain machine name) |
| `node__field_domain_all_affiliates` | Boolean: visible on all domains |
| `node__field_domain_source` | Primary domain for canonical URL |
| `user__field_domain_access` | Domain assignments for users |

Migration must map domain assignments to the target platform's multi-site or multi-tenant model. Content without domain assignments defaults to the primary domain. See skill 36.

### ACSF (Acquia Site Factory)

**Impact: Low-Medium**

Acquia Cloud Site Factory platform modules. ACSF manages multi-site deployments on Acquia infrastructure. The `acsf` module provides platform integration hooks. The `acsf_duplication` module handles site cloning.

| Storage | Purpose |
|---------|----------|
| `acsf_variables` table | Platform-specific variable storage |
| Config: `acsf.settings` | Site Factory connection settings |
| Theme: factory themes | Shared base themes distributed across factory sites |

ACSF data is platform configuration, not content. Migration impact is limited to understanding site grouping (which sites share content or config) and resolving factory theme dependencies. Content export works the same as standard Drupal. See skill 36.

### Organic Groups (D7)

**Impact: Medium**

D7 predecessor to Group module.

| Table | Purpose |
|-------|---------|
| `og_membership` | `id`, `type`, `etid` (entity ID), `entity_type`, `gid` (group nid), `state`, `created` |
| `og_role` | Roles within groups |
| `og_role_permission` | Permissions per group role |

---

## API

### GraphQL

**Impact: Medium**

Alternative API layer to core's JSON:API. Two major versions coexist.

| Version | Approach |
|---------|----------|
| v3 | Auto-generated schema from Drupal's entity/field system. Every entity type and field becomes a GraphQL type and field. |
| v4 | Composable schema. Developers define resolvers and schema extensions explicitly. More flexible but requires reading custom code to understand the schema. |

GraphQL does not store content. It changes how content is accessed during export. If the source site exposes content through GraphQL (and not JSON:API or direct DB access), the export pipeline must query the GraphQL endpoint instead.

Key considerations:
- Custom resolvers in v4 may reshape data in ways that differ from the underlying entity structure
- Authentication and permissions apply to GraphQL queries the same as REST
- Pagination uses cursor-based connections, not offset/limit

See `reference/graphql-patterns.md`.

---

## Views and Display

### Views (Core in D8+)

**Impact: Low**

Query builder / listing pages. Config only. No content data. Rebuild in target platform.

Config: `views.view.{name}`

### Display Suite

**Impact: Low**

Custom entity display layouts. Config only.

### Panels / Page Manager (D7)

**Impact: Medium** (D7)

Panel pages with custom layouts. Stores in `panels_pane`, `panels_display`, `page_manager_pages`.

---

## Misc Content

### Menu Link Attributes

**Impact: Low**

Extra attributes on menu links (class, target, rel). Stored in the `link__options` serialized column of `menu_link_content_data`.

### Entity Queue

**Impact: Medium**

Curated lists of entities.

| Table | Purpose |
|-------|---------|
| `entity_subqueue` | Queue instance |
| `entity_subqueue__items` | Queue items with `items_target_id` and `delta` for ordering |

### Flag

**Impact: Medium**

User flagging (bookmarks, favorites, spam reports).

| Table | Key Columns |
|-------|-------------|
| `flagging` | `id`, `flag_id`, `entity_type`, `entity_id`, `uid`, `created` |

### Votingapi

**Impact: Medium**

Rating/voting system.

| Table | Key Columns |
|-------|-------------|
| `votingapi_vote` | `id`, `type`, `entity_type`, `entity_id`, `value`, `value_type`, `user_id`, `timestamp`, `vote_source` |
| `votingapi_result` | Aggregated results per entity |

### Simple Sitemap

**Impact: Low**

Sitemap generation config. No content data.

### Smart Date

**Impact: Medium**

Enhanced date field with duration and recurring dates. See `drupal-field-types.md`.

### Inline Entity Form

**Impact: Low**

UX module for editing referenced entities inline. No data storage impact. References use standard entity_reference fields.

### Better Exposed Filters

**Impact: Low**

Views UI enhancement. No data storage.

### Admin Toolbar

**Impact: Low**

Admin UI. No data.

---

## Quick Discovery: Detecting Installed Modules

### D9+

```sql
SELECT data FROM config WHERE name = 'core.extension';
-- Deserialize to get module list

-- Or look for module-specific tables
SELECT table_name FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'paragraphs_item',           -- Paragraphs
    'redirect',                  -- Redirect
    'webform_submission',        -- Webform
    'commerce_order',            -- Commerce
    'crop',                      -- Crop / Focal Point
    'group_content',             -- Group
    'flagging',                  -- Flag
    'entity_subqueue',           -- Entity Queue
    'commerce_license',          -- Commerce License
    'workspace',                 -- Workspaces
    'workspace_association',     -- Workspaces
    'cohesion_layout',           -- Site Studio
    'acsf_variables'             -- ACSF
  );
```

### D7

```sql
SELECT name, status FROM system
WHERE type = 'module' AND status = 1
ORDER BY name;

-- Or detect by table presence
SELECT table_name FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'paragraphs_item',           -- Paragraphs (D7 version)
    'entityform',                -- Entityform
    'redirect',                  -- Redirect
    'uc_orders',                 -- Ubercart
    'og_membership',             -- Organic Groups
    'panels_pane',               -- Panels
    'workbench_moderation_node_history', -- Workbench Moderation
    'field_collection_item'      -- Field Collection
  );
```

## Migration Priority Matrix

Migrate these first (content and relationships):

| Priority | Modules | Reason |
|----------|---------|--------|
| 1 | Paragraphs, Entity Reference Revisions | Content structure |
| 2 | Media, File Entity, Focal Point | Assets |
| 3 | Redirect, Pathauto | URL preservation, SEO |
| 4 | Commerce (all) | Transaction history |
| 5 | Webform | Form submissions |
| 6 | Address, Geofield | Structured data |
| 7 | Metatag | SEO metadata |
| 8 | Content Moderation, Scheduler | Workflow state |
| 9 | Group, Domain Access, Flag | Access and personalization |
| 10 | Layout Builder, Experience Builder, Site Studio, Gutenberg | Per-entity layout and page builder overrides |
| 11 | GraphQL | API layer (affects export method) |
| 12 | Domain, ACSF | Multi-site and platform config |

Skip these (rebuild in target):

| Module | Reason |
|--------|--------|
| Views | Query definitions, not data |
| Search API | Index rebuilt from source data |
| Field Group | Form/display presentation |
| Display Suite | Display presentation |
| Admin Toolbar | Admin UI |
| Better Exposed Filters | Views UI |
| Simple Sitemap | Generated output |
| SDC | Component definitions, no stored data |
