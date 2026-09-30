# Skill 03: Module Inventory and Migration Impact

Catalog every enabled module. Classify each by category, data footprint, and migration impact. Map equivalents in target platforms.

---

## Why This Matters

Modules define what Drupal does beyond storing nodes. Some add entity types, field types, and database tables. Others alter rendering or add admin UI sugar. The difference determines migration scope. A module that stores data requires export work. A module that only themes output can be dropped without data loss.

Skip this inventory and you will discover missing data three weeks into the migration.

---

## Access Patterns

### 1. Drush (fastest, requires shell)

```bash
# All enabled modules with package and version
drush pm:list --status=enabled --format=json > modules_enabled.json

# Just machine names
drush pm:list --status=enabled --field=name --format=list

# Show module type (core, contrib, custom)
drush pm:list --status=enabled --fields=name,package,version,path --format=json

# Count by type
drush pm:list --status=enabled --type=module --format=json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); \
  paths=[v.get('path','') for v in d.values()]; \
  print(f'core: {sum(1 for p in paths if \"/core/\" in p)}'); \
  print(f'contrib: {sum(1 for p in paths if \"/contrib/\" in p)}'); \
  print(f'custom: {sum(1 for p in paths if \"/custom/\" in p)}')"
```

### 2. Config Export (no shell needed if you have config sync)

```yaml
# core.extension.yml lists every enabled module and its weight
# Location: sites/default/files/config_*/core.extension.yml
# Or: drush config:get core.extension module --format=json
```

Parse `core.extension.yml`. Every key under `module:` is an enabled module. The value is its install weight.

### 3. Composer (version and source info)

```bash
# List all drupal/* packages
composer show --format=json 'drupal/*' 2>/dev/null | \
  python3 -c "import json,sys; d=json.load(sys.stdin); \
  [print(p['name'], p['version']) for p in d.get('installed',[])]"

# Or parse composer.lock directly
cat composer.lock | python3 -c "
import json, sys
lock = json.load(sys.stdin)
for pkg in lock.get('packages', []):
    if pkg['name'].startswith('drupal/'):
        print(pkg['name'], pkg['version'])
"
```

### 4. Database (Drupal 7 only)

```sql
-- D7: system table tracks all modules
SELECT name, status, type, schema_version, info
FROM system
WHERE status = 1 AND type = 'module'
ORDER BY name;
```

Drupal 8+ stores this in the `key_value` table under `core.extension`. Use config export instead.

### 5. JSON:API (remote, no shell)

JSON:API does not expose the module list directly. Use it only for content, not for this inventory.

---

## Classification Algorithm

For each enabled module, determine:

| Question | How to check | Migration impact |
|---|---|---|
| Does it create entity types? | Check for `*.entity_type.yml` in module's config/install | High: new tables, new data to export |
| Does it add field types? | Check for `FieldType` plugin annotations | High: field data may need conversion |
| Does it add database tables? | Check for `hook_schema()` in `.install` file | High: custom data to extract |
| Does it store config only? | Module dir has config/install but no schema | Medium: config may need translation |
| Does it affect display only? | Field formatters, Views plugins, theme hooks | Low: no data to migrate |
| Is it admin UI only? | Toolbar, dashboard, admin theme helpers | None: drop it |

### Automated Classification Script

```bash
# For each contrib module, check what it registers
for module_path in $(find web/modules/contrib -maxdepth 1 -type d); do
  module=$(basename "$module_path")

  has_schema=$(grep -l "hook_schema\|function ${module}_schema" "$module_path"/*.install 2>/dev/null)
  has_entity=$(find "$module_path" -name "*.entity_type.yml" 2>/dev/null | head -1)
  has_field_type=$(grep -rl "FieldType" "$module_path/src/Plugin/Field/FieldType" 2>/dev/null | head -1)
  has_formatter=$(grep -rl "FieldFormatter" "$module_path/src/Plugin/Field/FieldFormatter" 2>/dev/null | head -1)

  echo "$module|schema:${has_schema:+yes}|entity:${has_entity:+yes}|field_type:${has_field_type:+yes}|formatter:${has_formatter:+yes}"
done
```

---

## Module Classification Reference

### Tier 1: High Migration Impact (stores data, adds entity types or field types)

These modules create database tables, entity types, or field storage. You must export their data or lose it.

| Module | Category | What it stores | What breaks if ignored | WordPress | Next.js + Headless CMS | Strapi | Payload | Hugo | Astro |
|---|---|---|---|---|---|---|---|---|---|
| **paragraphs** | Contrib | Paragraph entities in dedicated tables. Each paragraph type gets field tables. Nested paragraphs create entity reference chains. | All structured content below the node level vanishes. Pages render empty or broken. | ACF Flexible Content, Gutenberg blocks | Sanity Portable Text, Contentful Rich Text, components in any headless CMS | Dynamic Zones + Components | Blocks field type (array of typed objects) | Shortcodes + data files (limited) | MDX components, content collections |
| **entity_reference_revisions** | Contrib | Revision-aware entity references. Used by Paragraphs for parent-child binding. | Paragraph references break. Content structure collapses. | Core post relationships | Relation fields in target CMS | Relation fields | Relationship field | Front matter refs | Content references |
| **webform** | Contrib | Form definitions (YAML config) and submissions (database tables: `webform_submission`, `webform_submission_data`). | All form definitions and collected submission data lost. | Gravity Forms, WPForms, Contact Form 7 | Formspree, Typeform, custom form handler | Custom collection type + form builder plugin | Form builder block, or external (Tally, Typeform) | Formspree, Netlify Forms | Formspree, Netlify Forms, Astro + React form |
| **commerce** | Contrib | Products, variations, orders, payments, stores, promotions, carts. Full e-commerce entity graph across 30+ tables. | Entire store data: products, order history, customer records. | WooCommerce | Saleor, Medusa, Shopify Storefront API | Strapi + Medusa or custom commerce plugin | Payload + custom commerce collections | Not suited for commerce | Not suited for commerce |
| **search_api** | Contrib | Index configuration, server config, tracked items in `search_api_item` table. Solr/Elasticsearch index state. | Search stops working. Index config must be rebuilt. | SearchWP, Relevanssi, ElasticPress | Algolia, Meilisearch, Typesense | Meilisearch plugin, Algolia | Payload built-in search or Meilisearch | Pagefind, Lunr.js | Pagefind, Fuse.js |
| **flag** | Contrib | Flag types (config) and flagging records (`flagging` entity table). Tracks which users flagged which content. | User bookmarks, favorites, follow lists lost. | User favorites via custom meta or plugin | Custom collection/table in target CMS | Custom flagging collection type | Custom collection | Not applicable | Not applicable |
| **commerce_product** | Contrib (sub) | Product entities with variations, attribute fields, prices. | Product catalog gone. | WooCommerce products | Headless commerce platform | Strapi product collection | Payload product collection | Data files (catalog only) | Content collection (catalog only) |
| **media** | Core (D8.5+) | Media entities wrapping files, images, videos, remote video, documents. References in `media__*` field tables. | Media references break across all content. Files may survive but entity metadata lost. | Core media library | Target CMS media library | Strapi Media Library | Payload upload collections | Static files in /static | Static files in /public |
| **layout_builder** | Core | Per-entity layout overrides stored in `node__layout_builder__layout` table. Section and block placement data. | Custom page layouts revert to default. Per-page design lost. | Gutenberg, Elementor, Beaver Builder | Page builder in target CMS or component-based layouts | Dynamic Zones approximate this | Payload blocks field | Not applicable (template-driven) | Astro layouts + islands |
| **content_moderation** | Core | Moderation state per entity revision in `content_moderation_state` tables. Workflow definitions in config. | Draft/review/published states lost. All content treated as published. | PublishPress, Editorial workflow plugins | Draft/publish in target CMS | Strapi Draft/Publish + Review Workflows | Payload draft system + access control | No equivalent (static) | No equivalent (static) |
| **redirect** | Contrib | Redirect records in `redirect` table: source path, redirect target, status code (301/302), language. | Existing 301/302 redirects lost. SEO damage from broken incoming links. | Redirection plugin, Yoast redirects | Middleware redirects (next.config.js, _redirects file) | Custom redirect middleware | Custom middleware or Payload hooks | `_redirects` file (Netlify) or aliases in config | `_redirects` file or Astro middleware |
| **scheduler** | Contrib | Scheduled publish/unpublish dates stored as fields on nodes. Cron triggers state changes. | Scheduled content goes live immediately or stays unpublished forever. | PublishPress Future, WP Cron scheduling | Cron job + CMS API, or CMS built-in scheduling | Strapi cron + lifecycle hooks | Payload access control with date checks | Not applicable | Not applicable |
| **inline_entity_form** | Contrib | No own tables. But enables creation of referenced entities inline. Paragraphs and media often depend on it. | Editing workflow breaks. No data loss directly. | ACF relationship fields | Inline editing in target CMS | Inline component editing | Payload relationship fields with inline creation | Not applicable | Not applicable |
| **experience_builder** | Core (D11) | Component-based page layouts in `xb_page` entities. Stores component trees as structured data, not serialized blobs. Replaces Layout Builder's section/block model with a prop-driven component graph. See Skill 33. | Every page built with XB loses its layout and component data. Content fields survive but page assembly is gone. | Gutenberg, Elementor | Component-based page builder in target CMS, or custom React page-assembly layer | Dynamic Zones + Components (approximate) | Payload blocks field with nested component config | Not applicable (template-driven) | Astro islands + MDX component composition |
| **cohesion** / **sitestudio_*** | Contrib (Acquia) | JSON layout blobs in `cohesion_layout` field on nodes and custom block entities. Component configs in `cohesion_*` config entities. Style definitions, templates, and component forms stored as large JSON objects in the database. | All Site Studio page layouts, components, and styles vanish. Content fields survive but pages render as raw markup or nothing. | Elementor, Beaver Builder (closest analogs for visual page building) | Component-based layouts in target CMS. JSON blobs require deep parsing. | Dynamic Zones (partial match) | Payload blocks field (partial match) | Not applicable | Not applicable |
| **gutenberg** | Contrib | Serialized HTML blocks in existing text fields (typically `body`). Block markup uses `<!-- wp:block-name -->` comment delimiters. Own media handling bypasses core Media entities. | Block markup renders as raw HTML comments in any non-Gutenberg context. Media references may point to files not tracked by core Media. | Gutenberg (native, zero conversion) | Parse block HTML into structured components or use as raw HTML | Rich Text field with HTML (lose block structure) | Rich Text field with HTML | Raw HTML in content files | Raw HTML or parse into MDX components |
| **field_collection** | Contrib (D7) | `field_collection_item` entities with per-bundle field tables. Same nested-entity pattern as Paragraphs but D7-era. Host entity stores reference IDs in a field table. | All structured sub-content within field collections disappears. Pages using them show empty regions. | ACF Flexible Content, ACF Repeater | Structured content models in target CMS | Components within Dynamic Zones | Payload array fields or blocks | Data files with nested YAML | Content collections with nested data |

### Tier 2: Medium Migration Impact (stores configuration, affects content model)

These modules store configuration that shapes how content is modeled, displayed, or accessed. No content data tables of their own, but their config must be translated to the target platform.

| Module | Category | What it stores | What breaks if ignored | WordPress | Next.js + Headless CMS | Strapi | Payload | Hugo | Astro |
|---|---|---|---|---|---|---|---|---|---|
| **metatag** | Contrib | Default metatag patterns (config) and per-entity overrides (field data in `node__field_metatag`). | SEO metadata vanishes. Open Graph, Twitter Cards, descriptions gone. | Yoast SEO, Rank Math, All in One SEO | next-seo, custom head tags from CMS fields | SEO plugin or custom SEO component type | Custom SEO fields on collections | Front matter + templates | Astro SEO component, front matter |
| **pathauto** | Contrib | URL alias patterns (config). Generated aliases stored in `path_alias` table (core). | Auto-generated URL patterns lost. Must rebuild alias logic in target. | Permalink settings (built-in) | URL structure in routing config | Custom slug generation | Payload slug field with hooks | Permalink config in Hugo config | File-based routing or `getStaticPaths` |
| **token** | Contrib | No data. Provides placeholder tokens used by Pathauto, Metatag, and others. | Modules depending on tokens lose their pattern replacement engine. | Not needed (WP has rewrite tags) | Not needed (template literals in code) | Not needed | Not needed | Not needed (Go templates) | Not needed |
| **field_group** | Contrib | Field group config (tabs, accordions, fieldsets) stored in config entities. No content data. | Admin editing UI loses organized field grouping. Content itself is fine. | ACF field groups, Meta Box groups | UI organization in target CMS | Component groups in content type builder | Payload field groups (tabs, rows, collapsibles) | Not applicable | Not applicable |
| **metatag_open_graph** | Contrib (sub) | Open Graph tag config. Part of metatag ecosystem. | Facebook/LinkedIn share previews break. | Yoast/Rank Math OG settings | og meta tags in head component | Strapi SEO plugin | Custom OG fields | OG in front matter | Astro SEO component |
| **simple_sitemap** / **xmlsitemap** | Contrib | Sitemap generation config. Cached sitemap in database or files. | Sitemap stops generating. Search engines lose crawl guidance. | Yoast sitemap, XML Sitemaps plugin | next-sitemap package | Strapi sitemap plugin | Custom sitemap generation | Hugo built-in sitemap | @astrojs/sitemap |
| **google_analytics** / **google_tag** | Contrib | Tracking ID and config. No content data. | Analytics tracking stops. | Site Kit, GA plugin, GTM plugin | GTM script in `_document` or layout | Env var in template head | Env var in template head | Partial template | Astro integration or head script |
| **views** | Core | View config entities (YAML). Defines listings, blocks, feeds, REST exports. Each view is a query + display config. | All dynamic listings, feeds, and content displays vanish. | WP_Query, custom queries, or page builders | GraphQL/REST queries from CMS | Strapi find/filter API, custom controllers | Payload find queries with filters | List templates, taxonomy pages | `getCollection()`, content queries |
| **taxonomy** | Core | Vocabulary definitions (config) and term entities (data tables). | All categorization, tagging, hierarchical classification gone. | Categories + Tags (built-in), custom taxonomies | Taxonomy/tag collection types in target CMS | Taxonomy collection type with relations | Payload taxonomy collections | Taxonomies in Hugo config | Content collections for tags |
| **text** / **options** / **link** / **telephone** | Core | Field type definitions. Data in per-field tables. | Field data for these types needs format conversion. | Core fields, ACF fields | Target CMS field types | Strapi field types (string, richtext, etc.) | Payload field types | Front matter fields | Content collection schema |
| **image** | Core | Image field data, alt text, dimensions. Image styles (config) define derivative generation. | Image references and responsive derivative config lost. | Core media + image sizes | Target CMS image transforms or CDN (Cloudinary, Imgix) | Strapi media library + responsive formats | Payload upload with image sizes | Hugo image processing | Astro `<Image>` component, Sharp |
| **layout_paragraphs** | Contrib | Layout metadata (region assignments, parent-child nesting) stored as behavior plugin data on paragraph entity reference fields. Adds `layout` and `config` keys to each paragraph reference. | Paragraph content survives but loses all grid/column/region placement. Pages render as a flat paragraph stack with no layout. | ACF Flexible Content with layout groups | Component-based layouts in target CMS | Dynamic Zones with layout components | Payload blocks with layout metadata | Shortcodes for columns (limited) | MDX layout components |
| **workspaces** | Core | `workspace` entities and `workspace_association` tracking table that maps each content entity revision to a workspace. Parallel content versions across workspaces. | Workspace-specific content revisions become invisible. Risk of publishing wrong revision if workspace state is ignored during export. | No direct equivalent (staging plugins approximate it) | Branch-based content in target CMS (Sanity, Contentful environments) | Strapi Draft/Publish (limited, no parallel workspaces) | Payload draft system (no workspace parallel) | Not applicable | Not applicable |
| **domain** / **domain_access** | Contrib | `domain` config entities defining each domain. `domain_access` field on nodes controlling which domains see which content. `domain_source` field sets canonical domain. | Multi-domain content assignments lost. All content becomes visible on all domains or no domains depending on target setup. See Skill 21. | WordPress Multisite or domain mapping plugins | Multi-tenant routing in Next.js middleware | Custom multi-domain logic in Strapi middleware | Payload tenant/access control | Not applicable (single site) | Not applicable (single site) |
| **acsf** / **acsf_duplication** | Contrib (Acquia) | Acquia Site Factory platform config. Site duplication records, ACSF-specific hooks, and platform database tables. No content data of its own. | Safe to drop in most cases. Only relevant if migrating the multi-site orchestration layer itself, not individual site content. | Not applicable (platform-level) | Not applicable | Not applicable | Not applicable | Not applicable | Not applicable |
| **graphql** | Contrib | Schema definitions and query config stored as config entities. Persisted queries in database. No content data. Provides an alternative API to JSON:API for content export. | If your export pipeline uses GraphQL queries, those queries stop working. Content itself is unaffected. Decide early: export via JSON:API, GraphQL, or direct DB. See Skill 04. | WPGraphQL | Native GraphQL in headless CMS (Hygraph, Contentful) | Strapi GraphQL plugin | Payload built-in GraphQL API | Not applicable | Not applicable |

### Tier 3: Low Migration Impact (display, theming, admin UX)

These modules affect how content renders or how admins interact with the site. No data to export. Drop them and content survives intact.

| Module | Category | Purpose | WordPress | Next.js + Headless CMS | Strapi | Payload |
|---|---|---|---|---|---|---|
| **admin_toolbar** | Contrib | Dropdown admin menus | Admin Menu plugin (or built-in) | Target CMS admin UI | Built-in Strapi admin | Built-in Payload admin |
| **ctools** | Contrib | Developer API utilities, plugins, dialogs | Not needed | Not needed | Not needed | Not needed |
| **libraries** | Contrib | External library management | wp_enqueue_script, npm | npm/yarn | npm | npm |
| **entity_api** (contrib) | Contrib | Extended entity CRUD API | Not needed | Not needed | Not needed | Not needed |
| **jquery_update** | Contrib (D7) | jQuery version override | Not needed | Not needed | Not needed | Not needed |
| **module_filter** | Contrib | Admin UI for filtering module list | Not needed | Not needed | Not needed | Not needed |
| **devel** | Contrib | Debug toolbar, generate content, kint | Query Monitor, Debug Bar | Dev tools | Strapi dev mode | Payload dev mode |
| **coffee** | Contrib | Admin search launcher | Admin search | Cmd+K pattern | Strapi search | Payload search |
| **views_bulk_operations** | Contrib | Bulk actions on Views listings | Bulk actions (built-in) | Custom admin actions | Strapi bulk actions | Payload bulk operations |
| **better_exposed_filters** | Contrib | Improved Views filter widgets | FacetWP, custom filters | Filter UI components | Custom filter UI | Custom filter UI |
| **colorbox** / **slick** / **blazy** | Contrib | Lightbox, carousel, lazy-load | Lightbox plugins, Swiper | Swiper, lightbox.js, native lazy | Frontend components | Frontend components |
| **twig_tweak** | Contrib | Twig template helpers | Theme functions | Not needed (React/JSX) | Not needed | Not needed |
| **easy_breadcrumb** | Contrib | Auto breadcrumbs from URL | Breadcrumb NavXT, Yoast | Custom breadcrumb component | Custom component | Custom component |
| **captcha** / **recaptcha** | Contrib | Form spam protection config | reCAPTCHA plugins | reCAPTCHA, hCaptcha, Turnstile | Middleware or frontend | Middleware or frontend |
| **honeypot** | Contrib | Hidden form field spam trap | WP Honeypot | Custom hidden field | Custom middleware | Custom middleware |
| **layout_discovery** | Core | Layout plugin definitions used by Layout Builder and Experience Builder. Config only: layout names, regions, template paths. No content data. | No data loss. Target platform defines its own layout system. | Not needed | Not needed | Not needed | Not needed |
| **sdc** | Core (D10.1+) | Single Directory Components. Defines component contracts (props, slots) used by Experience Builder. No stored content data. Component definitions live in module/theme directories. See Skill 33. | No data loss. Component definitions inform XB migration but carry no database state. | Not needed (theme components) | React/Vue components | Strapi components | Payload field schemas | Hugo partials | Astro components |
| **shield** | Contrib | HTTP basic auth for staging | .htpasswd | Middleware auth | Middleware auth | Middleware auth |
| **seckit** | Contrib | Security headers config | Security headers plugin | Middleware headers | Middleware headers | Middleware headers |
| **smtp** / **mailsystem** | Contrib | SMTP transport config | WP Mail SMTP | Nodemailer, SendGrid, SES | Strapi email plugin | Nodemailer config |
| **diff** | Contrib | Revision comparison UI | Revision comparison (built-in) | CMS revision diff | Not built-in | Not built-in |
| **linkit** | Contrib | Autocomplete link picker for CKEditor | Link insertion (built-in) | CMS link picker | Strapi link field | Payload relationship field |

### Tier 4: No Migration Impact (dev tools, CI, testing)

Drop these. They serve the Drupal development environment only.

| Module | Purpose |
|---|---|
| **config_split** | Environment-specific config management |
| **config_ignore** | Ignore certain config on import |
| **stage_file_proxy** | Proxy production files to dev |
| **environment_indicator** | Color-coded admin bar per environment |
| **dblog** / **syslog** | Logging backends |
| **update** | Module update checker |
| **automated_cron** | Cron trigger on page loads |
| **ban** | IP banning |
| **big_pipe** | Streaming page delivery optimization |
| **dynamic_page_cache** / **page_cache** | Drupal internal caching layers |

---

## Extended Module Analysis: 50+ Common Contrib Modules

Beyond the tables above, here is a flat reference for additional modules you will encounter.

### Content Structure Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **field_collection** (D7) | High | Yes, entity tables | D7 predecessor to Paragraphs. Same nested-entity extraction problem. |
| **entity_reference** | High | Yes, field tables | Core in D8+. Reference data must be mapped to target relations. |
| **block_content** | High | Yes, custom block entities | Reusable blocks with fields. Export like nodes. |
| **menu_link_content** | High | Yes, menu link entities | Custom menu links with fields. Export with menus. |
| **path_alias** | High | Yes, path_alias table | Core in D9+. Export all aliases for URL mapping. |
| **shortcut** | Low | Yes, shortcut entities | Admin shortcuts. Not worth migrating. |

### SEO and Analytics Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **schema_metatag** | Medium | Config + field data | JSON-LD structured data. Rebuild in target as JSON-LD templates. |
| **google_analytics** | Low | Config only | Just a tracking ID. Paste it into the new platform. |
| **google_tag** | Low | Config only | GTM container ID. Same story. |
| **matomo** | Low | Config only | Self-hosted analytics. Point it at the new site. |
| **simple_sitemap** | Medium | Config + cached data | Rebuild sitemap generation in target platform. |
| **xmlsitemap** | Medium | Config + tables | Same as above but older approach. |
| **hreflang** | Medium | Config | Multilingual URL mapping. Rebuild in target routing. |

### Media and File Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **media_library** | High | Core media UI | The media browser. Media entities themselves carry the data. |
| **file** | High | Yes, file_managed table | Core file tracking. Every file reference runs through this. |
| **image** | High | Yes, field tables + derivatives | Image fields + image style config. Export field data + regenerate derivatives. |
| **crop** / **focal_point** | Medium | Yes, crop entity data | Crop coordinates per image. Export if target supports focal point cropping. |
| **video_embed_field** | Medium | Yes, field data | Stores video URLs (YouTube, Vimeo). Extract URLs, embed in target. |
| **entity_embed** / **embed** | Medium | Config + CKEditor plugin | Embeds entities in rich text via `<drupal-entity>` tags. Must parse and convert during rich text cleanup. |
| **media_entity_download** | Low | No | Adds download links for media. Pure display. |

### Form and Interaction Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **webform** | High | Yes, submissions + config | Full form builder. Export definitions as YAML, submissions as CSV. |
| **contact** | Medium | Yes, submissions (if stored) | Core contact forms. Simpler than Webform. |
| **captcha** | Low | Config only | Spam protection config. Reconfigure on target. |
| **honeypot** | Low | Config only | Hidden field spam trap. Reimplement trivially. |

### User and Access Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **user** | High | Yes, users_field_data + roles | Core. Export users, roles, field data. Do NOT export password hashes unless target accepts same hash format. |
| **content_access** | Medium | Config | Per-node access grants. Rebuild as access control in target. |
| **group** | High | Yes, group entities + memberships | Organic Groups successor. Full entity graph to export. |
| **domain** / **domain_access** | High | Yes, domain assignment data | Multi-site content sharing. Export domain assignments if target has multi-site. |
| **permissions_by_term** | Medium | Yes, term-based access records | Taxonomy-driven access. Rebuild in target access layer. |
| **role_delegation** | Low | Config only | Allows non-admins to assign roles. Admin UX only. |

### Multilingual Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **content_translation** | High | Yes, translated field data | Core. Translations stored as additional rows in field tables. |
| **config_translation** | Medium | Config overrides per language | Core. Export translated config (views, metatags, etc.) |
| **language** | Medium | Config | Core. Language negotiation settings. |
| **locale** | Medium | Yes, locales_source + locales_target tables | Core. UI string translations. Export if target needs translated UI. |
| **i18n** (D7) | High | Yes, multiple tables | D7 i18n suite. Complex extraction. Use D7-specific migration scripts. |
| **tmgmt** | Medium | Yes, translation job records | Translation Management. Job history optional to migrate. |

### Commerce Modules

| Module | Impact | Stores data? | Notes |
|---|---|---|---|
| **commerce_product** | High | Yes, product + variation entities | Product catalog. |
| **commerce_order** | High | Yes, order + order item entities | Order history. |
| **commerce_payment** | High | Yes, payment entities | Payment records. Sensitive data, handle carefully. |
| **commerce_promotion** | High | Yes, promotion + coupon entities | Discount rules. Rebuild in target commerce platform. |
| **commerce_shipping** | High | Yes, shipment entities | Shipping records. |
| **commerce_cart** | Medium | Session/DB | Active carts. Usually not migrated (ephemeral). |
| **commerce_checkout** | Low | Config only | Checkout flow config. Rebuild in target. |

---

## Inventory Output Format

Generate the inventory as a JSON file the AI agent and migration scripts can consume:

```json
{
  "drupal_version": "10.2.4",
  "scan_date": "2025-01-15",
  "modules": [
    {
      "machine_name": "paragraphs",
      "human_name": "Paragraphs",
      "category": "contrib",
      "version": "1.17",
      "package": "Paragraphs",
      "migration_impact": "high",
      "stores_data": true,
      "affects_content_model": true,
      "affects_display_only": false,
      "entity_types_added": ["paragraph"],
      "field_types_added": [],
      "database_tables": ["paragraphs_item", "paragraphs_item_field_data", "paragraphs_item_revision", "paragraphs_item_revision_field_data"],
      "depends_on": ["entity_reference_revisions", "file", "user"],
      "required_by": [],
      "target_equivalents": {
        "wordpress": "ACF Flexible Content or Gutenberg reusable blocks",
        "strapi": "Dynamic Zones with Components",
        "payload": "Blocks field (array of typed block objects)",
        "nextjs_contentful": "Contentful Rich Text or structured content models",
        "hugo": "Shortcodes with data files (limited nesting)",
        "astro": "MDX components in content collections"
      },
      "migration_notes": "Export paragraph entities with full field data. Resolve parent-child chains. See Skill 12 for deep paragraph extraction."
    }
  ],
  "summary": {
    "total_enabled": 87,
    "core": 42,
    "contrib": 38,
    "custom": 7,
    "high_impact": 12,
    "medium_impact": 15,
    "low_impact": 18,
    "no_impact": 42
  }
}
```

### Drush Script to Generate Inventory JSON

```bash
#!/bin/bash
# Generate module inventory JSON
# Requires: drush, jq, php

OUTPUT_FILE="${1:-module_inventory.json}"
DRUPAL_VERSION=$(drush status --field=drupal-version 2>/dev/null)
SCAN_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get all enabled modules
drush pm:list --status=enabled --format=json > /tmp/drupal_modules_raw.json

# Classify each module
php -r '
$modules = json_decode(file_get_contents("/tmp/drupal_modules_raw.json"), true);
$result = [
    "drupal_version" => $argv[1] ?? "unknown",
    "scan_date" => $argv[2] ?? date("c"),
    "modules" => [],
    "summary" => ["total_enabled" => 0, "core" => 0, "contrib" => 0, "custom" => 0,
                   "high_impact" => 0, "medium_impact" => 0, "low_impact" => 0, "no_impact" => 0]
];

// Known high-impact modules
$high = ["paragraphs","entity_reference_revisions","webform","commerce","commerce_product",
         "commerce_order","commerce_payment","search_api","flag","media","layout_builder",
         "content_moderation","redirect","scheduler","group","domain","domain_access",
         "content_translation","block_content","menu_link_content","path_alias","field_collection",
         "commerce_promotion","commerce_shipping","locale","inline_entity_form",
         "experience_builder","cohesion","gutenberg"];

$medium = ["metatag","pathauto","field_group","simple_sitemap","xmlsitemap","google_tag",
           "schema_metatag","crop","focal_point","video_embed_field","entity_embed","embed",
           "contact","config_translation","language","tmgmt","hreflang","content_access",
           "permissions_by_term","token","views","taxonomy","text","options","link","image",
           "telephone","layout_paragraphs","workspaces","graphql","acsf"];

$none = ["config_split","config_ignore","stage_file_proxy","environment_indicator","dblog",
         "syslog","update","automated_cron","ban","big_pipe","dynamic_page_cache","page_cache",
         "devel","coffee","module_filter","shield","layout_discovery","sdc"];

foreach ($modules as $name => $info) {
    $path = $info["path"] ?? "";
    if (strpos($path, "/core/") !== false) $cat = "core";
    elseif (strpos($path, "/contrib/") !== false) $cat = "contrib";
    elseif (strpos($path, "/custom/") !== false) $cat = "custom";
    else $cat = "unknown";

    if (in_array($name, $high)) $impact = "high";
    elseif (in_array($name, $medium)) $impact = "medium";
    elseif (in_array($name, $none)) $impact = "none";
    else $impact = "low";

    $result["modules"][] = [
        "machine_name" => $name,
        "human_name" => $info["display_name"] ?? $name,
        "category" => $cat,
        "version" => $info["version"] ?? "unknown",
        "package" => $info["package"] ?? "unknown",
        "migration_impact" => $impact,
    ];

    $result["summary"]["total_enabled"]++;
    $result["summary"][$cat] = ($result["summary"][$cat] ?? 0) + 1;
    $result["summary"][$impact . "_impact"] = ($result["summary"][$impact . "_impact"] ?? 0) + 1;
}

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
' "$DRUPAL_VERSION" "$SCAN_DATE" > "$OUTPUT_FILE"

echo "Module inventory written to $OUTPUT_FILE"
```

---

## Custom Module Analysis

Custom modules require individual inspection. They have no public documentation and no known equivalents.

### What to Check for Each Custom Module

```bash
# List all custom modules
find web/modules/custom -maxdepth 1 -type d -exec basename {} \; | sort

# For each custom module, determine its footprint:
MODULE="my_custom_module"
MODULE_PATH="web/modules/custom/$MODULE"

# 1. Does it define entity types?
grep -r "EntityType\|entity_type" "$MODULE_PATH/src/Entity/" 2>/dev/null

# 2. Does it define field types?
find "$MODULE_PATH" -path "*/Plugin/Field/FieldType/*" -name "*.php"

# 3. Does it create database tables?
grep -l "hook_schema\|function ${MODULE}_schema" "$MODULE_PATH/$MODULE.install" 2>/dev/null

# 4. Does it store data in key_value or state?
grep -r "key_value\|state()->set\|state()->get" "$MODULE_PATH" 2>/dev/null

# 5. Does it alter existing entities?
grep -r "hook_entity_base_field_info\|hook_entity_bundle_field_info" "$MODULE_PATH" 2>/dev/null

# 6. What does it depend on?
grep "dependencies:" "$MODULE_PATH/$MODULE.info.yml"
```

For each custom module that stores data or alters the content model, document:

1. What data it stores and where (entity tables, custom tables, key_value, state)
2. What entities or fields it adds
3. What the data represents in business terms
4. Whether the target platform needs equivalent functionality or can drop it

---

## Agent Workflow

1. Run `drush pm:list --status=enabled --format=json` or parse `core.extension.yml`
2. Classify each module using the reference tables above
3. For unknown modules, run the automated classification script
4. For custom modules, inspect each one individually
5. Generate the inventory JSON
6. Flag all high-impact modules for the user
7. For each high-impact module, confirm: do we need to export its data? Do we need equivalent functionality in the target?
8. Feed the inventory into Skill 30 (migration plan) as a dependency map

---

## Common Pitfalls

**Paragraphs masquerading as simple fields.** A content type with 3 visible fields might have 15 paragraph types underneath. Check `entity_reference_revisions` fields on every content type.

**Webform submissions vs definitions.** The form YAML exports easily. The 50,000 submissions in the database are the hard part. Ask the client: do submissions need to migrate, or just the form definitions?

**Commerce order history.** Migrating active products is straightforward. Migrating 5 years of order history with payment references, tax calculations, and shipping records is a different project. Scope it separately.

**Search API index vs search API config.** Config exports define how search works. The index itself does not migrate. Rebuild the index on the target platform after content lands.

**Token module confusion.** Token stores no data. But 6 other modules depend on it for pattern generation. Understand the dependency, not the module itself.

**Layout Builder overrides.** A content type using Layout Builder may have per-node layout overrides. These are stored as serialized data on the node. They do not export cleanly to any other platform. Treat each override as a custom page layout to rebuild.

**Experience Builder vs Layout Builder.** Drupal 11 introduces Experience Builder (XB) as the successor to Layout Builder. They store data in incompatible formats. If the site runs D11 with XB, check for `xb_page` entities. If it still uses Layout Builder, check `layout_builder__layout` fields. Some sites may have both during the transition period. See Skill 33.

**Cohesion/Site Studio JSON blobs.** The `cohesion_layout` field stores the entire page structure as a single JSON blob. This is not a field-per-component model. Parsing these blobs requires understanding Cohesion's internal component schema. The JSON references component machine names, style GUIDs, and layout canvas coordinates. Export the raw JSON first, then map components to target equivalents.

**Gutenberg block markup in body fields.** The Drupal Gutenberg module stores block-delimited HTML directly in the body field. The content looks like standard HTML but contains `<!-- wp:paragraph -->` style comment markers. If you strip the comments, you get usable HTML. If you need structured data, parse the block comments into a component tree.

**Multilingual double-counting.** Content Translation does not double the number of entities. It adds translated field rows. But Paragraphs referenced by translated nodes may or may not have their own translations. Check both layers.
