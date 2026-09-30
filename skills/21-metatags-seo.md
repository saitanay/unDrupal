# Skill 21: Metatags, SEO, and Structured Data Export

Export metatag configuration, Open Graph tags, Twitter Cards, JSON-LD structured data, XML sitemaps, robots.txt rules, and analytics tracking IDs from a Drupal site. The output gives your target platform everything it needs to preserve search engine rankings and social sharing behavior.

Run Skill 01 (Site Audit) first. You need the Drupal version, module list, and available access methods.

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Drush** | Config export, per-entity metatag values via SQL, module detection |
| **Database** | Full per-entity metatag overrides, sitemap entries, analytics config |
| **Config directory** (YAML) | Global and per-entity-type metatag defaults, sitemap config, analytics IDs |
| **JSON:API** | Entity metatag field values (if field exposed) |
| **Public site URL** | Crawl robots.txt, sitemap XML, inspect rendered meta tags in HTML |

---

## Background: How Drupal Stores Metatags

### D8+ (including D9, D10, D11)

The `metatag` module stores data at two levels:

1. **Defaults** — config entities in `metatag.metatag_defaults.{scope}.yml`. One per scope: `global`, `node`, `node__article`, `taxonomy_term`, `user`, etc. Each file holds a `tags` map of tag name to value (which may contain tokens like `[node:title]`).

2. **Per-entity overrides** — a `field_metatag` field (or `metatag` computed field) on the entity. Stored in the entity's field data table (e.g. `node__field_metatag`). The value is a serialized PHP array mapping tag names to override values.

Resolution order: per-entity override wins over entity-type+bundle default, which wins over entity-type default, which wins over global default. Tokens in defaults resolve at render time.

### D7

The `metatag` module stores everything in a single `metatag` table:

| Column | Type | Purpose |
|---|---|---|
| `entity_type` | varchar | `node`, `taxonomy_term`, `user`, `global`, `global:frontpage`, etc. |
| `entity_id` | int | Entity ID. 0 for global/config-level defaults. |
| `revision_id` | int | Entity revision ID. 0 for globals. |
| `language` | varchar | Language code (`und`, `en`, `es`, etc.) |
| `data` | longblob | Serialized PHP array of tag values |

The `data` column contains output like:

```php
a:3:{
  s:5:"title";a:1:{s:5:"value";s:40:"[node:title] | [site:name]";}
  s:11:"description";a:1:{s:5:"value";s:25:"[node:summary]";}
  s:8:"keywords";a:1:{s:5:"value";s:0:"";}
}
```

Each tag maps to an array with a `value` key. Some tags carry additional keys like `default` for fallback values.

Global defaults use `entity_type = 'global'` and `entity_id = 0`. Content type defaults use `entity_type = 'global:node'` or type-specific rows like `entity_type = 'node'` with `entity_id = 0`.

---

## 1. Global and Entity-Type Metatag Defaults

### 1a. Via Config YAML (D8+)

Defaults live in files named `metatag.metatag_defaults.{scope}.yml`.

```bash
# Find all metatag default configs
find config/sync -name "metatag.metatag_defaults.*.yml" | sort
```

Each file follows this structure:

```yaml
uuid: a1b2c3d4-...
langcode: en
status: true
dependencies:
  module:
    - metatag
id: global
label: Global
tags:
  title: '[current-page:title] | [site:name]'
  description: ''
  canonical_url: '[current-page:url]'
  robots: 'index, follow'
  og_title: '[current-page:title]'
  og_description: '[current-page:title]'
  og_url: '[current-page:url]'
  og_site_name: '[site:name]'
  twitter_cards_type: summary
  twitter_cards_title: '[current-page:title]'
  twitter_cards_description: ''
```

Bundle-specific defaults use a double-underscore separator in the ID:

```
metatag.metatag_defaults.global.yml         # site-wide fallback
metatag.metatag_defaults.node.yml           # all nodes
metatag.metatag_defaults.node__article.yml  # article content type
metatag.metatag_defaults.node__page.yml     # basic page content type
metatag.metatag_defaults.taxonomy_term.yml  # all taxonomy terms
metatag.metatag_defaults.user.yml           # user profiles
metatag.metatag_defaults.front.yml          # front page
metatag.metatag_defaults.403.yml            # access denied page
metatag.metatag_defaults.404.yml            # not found page
```

Parse all defaults into a single manifest:

```bash
# Requires yq
for file in config/sync/metatag.metatag_defaults.*.yml; do
  scope=$(yq '.id' "$file")
  echo "--- Scope: $scope ---"
  yq '.tags' "$file"
done
```

### 1b. Via Drush (D8+)

```bash
# List all metatag default scopes
drush config:list | grep metatag.metatag_defaults

# Export a specific scope
drush config:get metatag.metatag_defaults.global --format=json
drush config:get metatag.metatag_defaults.node__article --format=json

# Export all at once
for name in $(drush config:list --format=list | grep metatag.metatag_defaults); do
  echo "=== $name ==="
  drush config:get "$name" tags --format=json
done
```

### 1c. Via Database (D8+)

```sql
-- All metatag default configs from the config table
SELECT name, data FROM config WHERE name LIKE 'metatag.metatag_defaults.%';
```

The `data` column is PHP-serialized. Unserialize each row to extract the `tags` array.

### 1d. Via Database (D7)

```sql
-- Global defaults
SELECT entity_type, language, data
FROM metatag
WHERE entity_id = 0
ORDER BY entity_type, language;

-- This returns rows like:
-- entity_type='global', language='und'           -> site-wide
-- entity_type='global:frontpage', language='und'  -> front page
-- entity_type='node', language='und'              -> all nodes (if set)
```

Unserialize the `data` column with PHP or a serialization parser. Map D7 tag names to their target platform equivalents.

---

## 2. Per-Entity Metatag Overrides

These are the values editors set on individual nodes, terms, or users. They override the defaults from Step 1.

### 2a. Via Database (D8+)

The metatag module attaches a field to entities. The field table name depends on how the field was added. Common patterns:

```sql
-- Check which tables store metatag field data
SELECT TABLE_NAME FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME LIKE '%metatag%'
ORDER BY TABLE_NAME;

-- Typical results:
-- node__field_metatag
-- node_revision__field_metatag
-- taxonomy_term__field_metatag
-- user__field_metatag
```

Query the current values:

```sql
-- Per-node metatag overrides
SELECT
  n.entity_id,
  n.bundle,
  n.langcode,
  n.field_metatag_value
FROM node__field_metatag n
ORDER BY n.bundle, n.entity_id;
```

The `field_metatag_value` column holds a serialized PHP array:

```php
a:3:{
  s:5:"title";s:28:"Custom Title | My Site";
  s:11:"description";s:55:"A hand-written description for this specific article.";
  s:12:"og_image_url";s:45:"https://example.com/images/custom-og-image.jpg";
}
```

Only tags that differ from defaults appear in the override. An empty string means "clear this tag" (don't inherit). A missing key means "inherit from defaults."

Export all per-entity overrides to JSON:

```bash
# Via Drush SQL
drush sql:query "
  SELECT
    entity_id,
    bundle,
    langcode,
    field_metatag_value
  FROM node__field_metatag
  ORDER BY bundle, entity_id
" --extra=--batch > /tmp/node_metatag_overrides.tsv
```

Parse each row's serialized value into JSON. Pair each `entity_id` with its bundle for context.

### 2b. Via Database (D7)

```sql
-- All per-entity metatag overrides
SELECT
  m.entity_type,
  m.entity_id,
  m.revision_id,
  m.language,
  m.data
FROM metatag m
WHERE m.entity_id > 0
ORDER BY m.entity_type, m.entity_id, m.language;
```

For large sites, export per entity type:

```sql
-- Nodes only
SELECT entity_id, revision_id, language, data
FROM metatag
WHERE entity_type = 'node' AND entity_id > 0
ORDER BY entity_id;

-- Taxonomy terms
SELECT entity_id, revision_id, language, data
FROM metatag
WHERE entity_type = 'taxonomy_term' AND entity_id > 0
ORDER BY entity_id;

-- Users
SELECT entity_id, language, data
FROM metatag
WHERE entity_type = 'user' AND entity_id > 0
ORDER BY entity_id;
```

### 2c. Via Drush (D8+)

```bash
# Count entities with metatag overrides, per bundle
drush sql:query "
  SELECT bundle, COUNT(*) as cnt
  FROM node__field_metatag
  GROUP BY bundle
  ORDER BY cnt DESC
"
```

### 2d. Via JSON:API (D8+)

If `field_metatag` is exposed via JSON:API (it often is not by default), query it per entity:

```
GET /jsonapi/node/article?fields[node--article]=title,field_metatag&page[limit]=50
```

The field value appears as a serialized string. You still need to unserialize it client-side.

---

## 3. Tag Types Reference

Map these Drupal metatag names to your target platform's equivalents.

### 3a. Basic Tags

| Drupal metatag key | HTML output | Notes |
|---|---|---|
| `title` | `<title>` and `<meta name="title">` | Often token-based: `[node:title] \| [site:name]` |
| `description` | `<meta name="description">` | Primary SEO description |
| `keywords` | `<meta name="keywords">` | Rarely used by search engines now |
| `robots` | `<meta name="robots">` | Values: `index`, `noindex`, `follow`, `nofollow`, `noarchive`, `nosnippet` |
| `canonical_url` | `<link rel="canonical">` | Defaults to `[current-page:url]` |
| `shortlink` | `<link rel="shortlink">` | Short URL if configured |
| `abstract` | `<meta name="abstract">` | Rarely used |
| `generator` | `<meta name="generator">` | Usually `Drupal N (https://www.drupal.org)` |

### 3b. Open Graph Tags

| Drupal metatag key | HTML output | Notes |
|---|---|---|
| `og_title` | `<meta property="og:title">` | Falls back to page title |
| `og_description` | `<meta property="og:description">` | Falls back to description |
| `og_image` | `<meta property="og:image">` | Absolute URL to image |
| `og_image_url` | `<meta property="og:image:url">` | Alternate image URL tag |
| `og_image_width` | `<meta property="og:image:width">` | Pixel width |
| `og_image_height` | `<meta property="og:image:height">` | Pixel height |
| `og_image_type` | `<meta property="og:image:type">` | MIME type (image/jpeg, etc.) |
| `og_image_alt` | `<meta property="og:image:alt">` | Alt text for the image |
| `og_type` | `<meta property="og:type">` | `article`, `website`, `product`, etc. |
| `og_url` | `<meta property="og:url">` | Canonical URL for sharing |
| `og_site_name` | `<meta property="og:site_name">` | Site name |
| `og_locale` | `<meta property="og:locale">` | Language/locale code |
| `og_locale_alternative` | `<meta property="og:locale:alternate">` | Alternative locales |
| `article_author` | `<meta property="article:author">` | Author URL or name |
| `article_published_time` | `<meta property="article:published_time">` | ISO 8601 datetime |
| `article_modified_time` | `<meta property="article:modified_time">` | ISO 8601 datetime |

### 3c. Twitter Card Tags

| Drupal metatag key | HTML output | Notes |
|---|---|---|
| `twitter_cards_type` | `<meta name="twitter:card">` | `summary`, `summary_large_image`, `app`, `player` |
| `twitter_cards_site` | `<meta name="twitter:site">` | `@username` of the site account |
| `twitter_cards_site_id` | `<meta name="twitter:site:id">` | Numeric Twitter ID |
| `twitter_cards_creator` | `<meta name="twitter:creator">` | `@username` of the content author |
| `twitter_cards_creator_id` | `<meta name="twitter:creator:id">` | Numeric Twitter ID of author |
| `twitter_cards_title` | `<meta name="twitter:title">` | Title for card |
| `twitter_cards_description` | `<meta name="twitter:description">` | Description for card |
| `twitter_cards_image` | `<meta name="twitter:image">` | Image URL for card |
| `twitter_cards_image_alt` | `<meta name="twitter:image:alt">` | Alt text for card image |

### 3d. Canonical URLs and Hreflang

Canonical URLs come from the `canonical_url` metatag key or Drupal's built-in canonical link generation.

For multilingual sites, hreflang tags are generated by the metatag module's `metatag_hreflang` submodule or by Drupal core itself (D8+).

```bash
# Check if hreflang submodule is enabled
drush pm:list --filter=metatag_hreflang --format=json
```

Export hreflang configuration:

```bash
# Via config YAML
cat config/sync/metatag.settings.yml
# Look for hreflang-related settings
```

Check rendered hreflang on a multilingual page:

```bash
# Crawl a page and extract hreflang links
curl -s https://example.com/node/1 | grep -i hreflang
# Expected output:
# <link rel="alternate" hreflang="en" href="https://example.com/en/my-page" />
# <link rel="alternate" hreflang="es" href="https://example.com/es/mi-pagina" />
# <link rel="alternate" hreflang="x-default" href="https://example.com/my-page" />
```

---

## 4. Schema.org / JSON-LD Structured Data

The `schema_metatag` module adds JSON-LD structured data output controlled through the metatag interface.

### 4a. Detect the Module

```bash
# Check for schema_metatag
drush pm:list --filter=schema_metatag --format=json

# Or in config
grep -r "schema_metatag" config/sync/core.extension.yml
```

### 4b. Via Config YAML (D8+)

Schema.org tags appear in the same `metatag.metatag_defaults.*.yml` files alongside regular metatags. They use a `schema_` prefix:

```yaml
tags:
  title: '[node:title] | [site:name]'
  description: '[node:summary]'
  schema_article_type: Article
  schema_article_name: '[node:title]'
  schema_article_description: '[node:summary]'
  schema_article_author: '[node:author:display-name]'
  schema_article_date_published: '[node:created:html_datetime]'
  schema_article_date_modified: '[node:changed:html_datetime]'
  schema_article_image: '[node:field_image:entity:url]'
  schema_article_publisher: '@type: Organization|name: [site:name]|url: [site:url]'
  schema_web_page_type: WebPage
  schema_web_page_name: '[current-page:title]'
```

The module renders these into a `<script type="application/ld+json">` block in the page head.

Extract schema metatag configuration:

```bash
# Find all schema_ tags across all default configs
for file in config/sync/metatag.metatag_defaults.*.yml; do
  scope=$(yq '.id' "$file")
  schema_tags=$(yq '.tags | to_entries | map(select(.key | test("^schema_"))) | from_entries' "$file")
  if [ "$schema_tags" != "{}" ] && [ -n "$schema_tags" ]; then
    echo "--- $scope ---"
    echo "$schema_tags"
  fi
done
```

### 4c. Schema Types Reference

Common `schema_metatag` types and their Drupal config keys:

| Schema type | Config key prefix | Typical entity |
|---|---|---|
| Article | `schema_article_*` | Blog posts, news articles |
| WebPage | `schema_web_page_*` | Basic pages |
| Organization | `schema_organization_*` | Usually global default |
| Person | `schema_person_*` | User profiles, author pages |
| Product | `schema_product_*` | Commerce products |
| Event | `schema_event_*` | Event content types |
| BreadcrumbList | `schema_breadcrumb_*` | Auto-generated from menu trail |
| FAQPage | `schema_faq_page_*` | FAQ content types |
| HowTo | `schema_how_to_*` | Tutorial/guide content |
| LocalBusiness | `schema_local_business_*` | Business listing pages |

### 4d. Rendered JSON-LD Verification

Crawl a page to capture the actual JSON-LD output:

```bash
# Extract JSON-LD from rendered page
curl -s https://example.com/node/1 | \
  grep -oP '<script type="application/ld\+json">\K.*?(?=</script>)' | \
  python3 -m json.tool
```

Compare rendered output against config to verify token resolution and data accuracy.

### 4e. D7 Schema.org

D7 sites may use `schemaorg` module instead of `schema_metatag`. Check:

```sql
-- D7: check for schemaorg module
SELECT name, status FROM system
WHERE name LIKE '%schema%' AND type = 'module';
```

The `schemaorg` module in D7 uses RDFa attributes rather than JSON-LD. Export its mappings:

```sql
SELECT * FROM rdf_mapping;
```

---

## 5. XML Sitemap

Two modules dominate: `xmlsitemap` (older, more common on D7) and `simple_sitemap` (common on D8+). Check which is installed.

```bash
drush pm:list --filter=xmlsitemap --format=json
drush pm:list --filter=simple_sitemap --format=json
```

### 5a. simple_sitemap Module (D8+)

This is the more common sitemap module on D8+ sites.

#### Config YAML

```bash
# Find all simple_sitemap config
find config/sync -name "simple_sitemap.*" | sort
```

Key config files:

```
simple_sitemap.settings.yml              # Global settings
simple_sitemap.type.default_hreflang.yml # Sitemap type definitions
simple_sitemap.type.index.yml
simple_sitemap.bundle_settings.*.yml     # Per-bundle inclusion settings (older versions)
simple_sitemap.custom_links.yml          # Manually added URLs (older versions)
```

Global settings:

```yaml
# simple_sitemap.settings.yml
max_links: 2000
cron_generate: true
cron_generate_interval: 0
remove_duplicates: true
skip_untranslated: false
base_url: ''
default_variant: default
```

#### Sitemap types (simple_sitemap 4.x)

In version 4.x, simple_sitemap uses "sitemap types" and "sitemap variants":

```bash
# List sitemap types
find config/sync -name "simple_sitemap.type.*.yml" | sort

# Example content of simple_sitemap.type.default_hreflang.yml:
# id: default_hreflang
# label: 'Default hreflang'
# sitemap_generator: default
# url_generators:
#   - custom
#   - entity
#   - entity_menu_link_content
#   - arbitrary
```

#### Bundle settings via Drush

```bash
# All simple_sitemap config
for name in $(drush config:list --format=list | grep simple_sitemap); do
  echo "=== $name ==="
  drush config:get "$name" --format=json
done
```

#### Bundle settings via Database

```sql
-- simple_sitemap stores entity inclusion settings in key_value
SELECT name, data FROM config WHERE name LIKE 'simple_sitemap%';
```

In newer versions of simple_sitemap, bundle settings are stored in the entity itself via third-party settings or in dedicated database tables:

```sql
-- Check for simple_sitemap tables
SELECT TABLE_NAME FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME LIKE 'simple_sitemap%'
ORDER BY TABLE_NAME;

-- Common tables:
-- simple_sitemap
-- simple_sitemap_entity_overrides
```

```sql
-- Entity-level sitemap overrides
SELECT type, entity_type, entity_id, inclusion_settings
FROM simple_sitemap_entity_overrides
ORDER BY entity_type, entity_id;
```

The `inclusion_settings` column is serialized PHP:

```php
a:3:{
  s:5:"index";b:1;
  s:8:"priority";s:3:"0.5";
  s:10:"changefreq";s:0:"";
}
```

#### Custom Links

```sql
SELECT data FROM config WHERE name = 'simple_sitemap.custom_links';
```

Or from YAML:

```yaml
# simple_sitemap.custom_links.yml (older versions)
links:
  -
    path: /
    priority: '1.0'
    changefreq: daily
  -
    path: /contact
    priority: '0.5'
    changefreq: monthly
```

### 5b. xmlsitemap Module

More common on D7 sites, also available on D8+.

#### D8+ Config

```bash
find config/sync -name "xmlsitemap.*" | sort
```

Key config files:

```
xmlsitemap.settings.yml                     # Global settings
xmlsitemap.settings.node.article.yml        # Per-bundle settings
xmlsitemap.settings.node.page.yml
xmlsitemap.settings.taxonomy_term.tags.yml
xmlsitemap.settings.user.user.yml
```

Per-bundle config structure:

```yaml
# xmlsitemap.settings.node.article.yml
status: 1          # 0 = excluded, 1 = included
priority: 0.5      # 0.0 to 1.0
changefreq: 0      # 0 = none, or seconds between changes
```

Global settings:

```yaml
# xmlsitemap.settings.yml
minimum_lifetime: 0
xsl: true
prefetch_aliases: true
chunk_size: auto
batch_limit: 100
path: xmlsitemap
frontpage_priority: '1.0'
frontpage_changefreq: 86400
lastmod_format: 'Y-m-d\TH:i:sP'
```

#### D7 Database

```sql
-- xmlsitemap table: one row per URL in the sitemap
SELECT type, subtype, id, loc, priority, changefreq,
       language, status, access, lastmod
FROM xmlsitemap
ORDER BY type, subtype, id
LIMIT 100;

-- xmlsitemap_sitemap: sitemap instances
SELECT * FROM xmlsitemap_sitemap;

-- Per-type/bundle settings are stored in the variable table
SELECT name, value FROM variable
WHERE name LIKE 'xmlsitemap_settings_%'
ORDER BY name;
```

The `variable` table values are serialized PHP. Unserialize to get:

```php
// Example: xmlsitemap_settings_node_article
a:3:{
  s:6:"status";s:1:"1";
  s:8:"priority";s:3:"0.5";
  s:10:"changefreq";i:0;
}
```

### 5c. Download the Live Sitemap

Regardless of module, grab the rendered sitemap:

```bash
# Standard location
curl -sL https://example.com/sitemap.xml -o /tmp/sitemap.xml

# Check for sitemap index (multiple sitemaps)
curl -sL https://example.com/sitemap.xml | head -20

# If it's a sitemap index, download each child sitemap
grep -oP '<loc>\K[^<]+' /tmp/sitemap.xml | while read url; do
  filename=$(echo "$url" | sed 's|.*/||')
  curl -sL "$url" -o "/tmp/$filename"
  echo "Downloaded: $filename ($(wc -l < /tmp/$filename) lines)"
done

# Count URLs per sitemap
for f in /tmp/sitemap*.xml; do
  count=$(grep -c '<loc>' "$f")
  echo "$f: $count URLs"
done
```

---

## 6. robots.txt

### 6a. Static File

Drupal ships a default `robots.txt` in the webroot. Sites may modify it or replace it entirely.

```bash
# Read the file from the codebase
cat web/robots.txt
# or
cat robots.txt
```

### 6b. robotstxt Module

Some sites use the `robotstxt` module to manage robots.txt content through the admin UI.

```bash
# Check if the module is installed
drush pm:list --filter=robotstxt --format=json
```

If installed, the content lives in config:

```bash
drush config:get robotstxt.settings content
```

Or in YAML:

```yaml
# robotstxt.settings.yml
content: |
  User-agent: *
  Crawl-delay: 10
  Disallow: /admin/
  Disallow: /user/
  Disallow: /search/
  Sitemap: https://example.com/sitemap.xml
```

Or in the database:

```sql
SELECT data FROM config WHERE name = 'robotstxt.settings';
```

### 6c. Live Fetch

```bash
curl -s https://example.com/robots.txt
```

Compare the live version against the codebase file. They may differ if the `robotstxt` module or a CDN modifies the output.

---

## 7. Google Analytics and Tag Manager

### 7a. Google Analytics (google_analytics module)

```bash
# D8+ config
drush config:get google_analytics.settings account --format=json
```

Config YAML:

```yaml
# google_analytics.settings.yml
account: 'UA-12345678-1'     # or 'G-XXXXXXXXXX' for GA4
visibility:
  request_path_mode: 0
  request_path_pages: "/admin\n/admin/*\n/batch\n/node/add*\n/node/*/edit\n/node/*/delete"
  user_role_mode: 0
  user_role_roles: {  }
  user_account: false
privacy:
  anonymizeip: true
track:
  outbound: true
  mailto: true
  files: true
  files_extensions: '7z|aac|arc|arj|asf|asx|avi|bin|csv|doc(x)?|exe|flv|gif|gz|gzip|...'
codesnippet:
  before: ''
  after: ''
```

D7 stores this in the `variable` table:

```sql
SELECT value FROM variable WHERE name = 'googleanalytics_account';
-- Result is serialized: s:14:"UA-12345678-1";
```

### 7b. Google Tag Manager (google_tag module)

```bash
# D8+ config
drush config:get google_tag.settings --format=json
```

Config YAML:

```yaml
# google_tag.settings.yml or google_tag.container.primary.yml
container_id: GTM-XXXXXXX
data_layer: dataLayer
include_classes: false
whitelist_classes: ''
blacklist_classes: ''
include_environment: false
environment_id: ''
environment_token: ''
```

In D8+ with google_tag 2.x, containers are config entities:

```bash
find config/sync -name "google_tag.container.*.yml" | sort
```

D7:

```sql
SELECT value FROM variable WHERE name = 'google_tag_container_id';
```

### 7c. Other Analytics Modules

Check for other tracking modules:

```bash
# Matomo (formerly Piwik)
drush config:get matomo.settings site_id --format=json 2>/dev/null
drush config:get matomo.settings url_http --format=json 2>/dev/null

# Facebook Pixel
grep -r "facebook_pixel\|fb_pixel" config/sync/ 2>/dev/null

# Any tracking code in page templates or blocks
drush sql:query "
  SELECT info, body__value
  FROM block_content_field_data
  WHERE body__value LIKE '%analytics%'
     OR body__value LIKE '%gtag%'
     OR body__value LIKE '%GTM-%'
     OR body__value LIKE '%UA-%'
     OR body__value LIKE '%G-%'
"
```

---

## 8. Metatag Module Submodules

The metatag module ships with submodules that add tag groups. Check which are enabled:

```bash
drush pm:list --filter=metatag --format=json
```

Common submodules and their tag groups:

| Submodule | Tag group | Tags added |
|---|---|---|
| `metatag_open_graph` | Open Graph | All `og_*` tags |
| `metatag_twitter_cards` | Twitter Cards | All `twitter_cards_*` tags |
| `metatag_verification` | Site verification | `google`, `bing`, `pinterest`, `yandex`, `baidu` site verification codes |
| `metatag_google_cse` | Google CSE | `google_cse_*` tags for Custom Search Engine |
| `metatag_hreflang` | Hreflang | Automated hreflang link generation for multilingual content |
| `metatag_app_links` | App Links | `al_*` tags for deep linking to mobile apps |
| `metatag_mobile` | Mobile & UI | `theme-color`, `apple-mobile-web-app-*`, viewport settings |
| `metatag_favicons` | Favicons | `icon_*`, `mask-icon`, `apple-touch-icon` |
| `metatag_dc` | Dublin Core | `dcterms.*` metadata |
| `metatag_pinterest` | Pinterest | `pinterest` no-pin settings |

Export verification codes (these are needed for the target platform):

```bash
drush config:get metatag.metatag_defaults.global tags --format=json | \
  python3 -c "
import sys, json
tags = json.load(sys.stdin)
verification = {k: v for k, v in tags.items()
                if any(s in k for s in ['google', 'bing', 'pinterest', 'yandex', 'baidu'])}
print(json.dumps(verification, indent=2))
"
```

---

## 9. Full Export Script

Combine all the above into one export run.

### D8+ with Drush

```bash
#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/tmp/metatag_export"
mkdir -p "$OUTPUT_DIR"

echo "=== Metatag Defaults ==="
for name in $(drush config:list --format=list | grep metatag.metatag_defaults); do
  scope=$(echo "$name" | sed 's/metatag.metatag_defaults.//')
  drush config:get "$name" --format=json > "$OUTPUT_DIR/defaults_${scope}.json"
  echo "Exported: $scope"
done

echo "=== Per-Entity Overrides ==="
# Find metatag field tables
TABLES=$(drush sql:query "
  SELECT TABLE_NAME FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME LIKE '%field_metatag%'
    AND TABLE_NAME NOT LIKE '%revision%'
")

for table in $TABLES; do
  entity_type=$(echo "$table" | sed 's/__field_metatag//')
  drush sql:query "
    SELECT entity_id, bundle, langcode, field_metatag_value
    FROM $table
    ORDER BY bundle, entity_id
  " --extra=--batch > "$OUTPUT_DIR/overrides_${entity_type}.tsv"
  count=$(wc -l < "$OUTPUT_DIR/overrides_${entity_type}.tsv")
  echo "Exported: $entity_type ($count rows)"
done

echo "=== XML Sitemap Config ==="
for name in $(drush config:list --format=list | grep -E "^(simple_sitemap|xmlsitemap)"); do
  safe=$(echo "$name" | tr '.' '_')
  drush config:get "$name" --format=json > "$OUTPUT_DIR/${safe}.json"
  echo "Exported: $name"
done

echo "=== robots.txt ==="
curl -s "$(drush core:status --field=uri)/robots.txt" > "$OUTPUT_DIR/robots.txt" 2>/dev/null || echo "Could not fetch robots.txt"

echo "=== Analytics ==="
drush config:get google_analytics.settings --format=json > "$OUTPUT_DIR/google_analytics.json" 2>/dev/null || true
for container in $(drush config:list --format=list | grep google_tag.container 2>/dev/null); do
  safe=$(echo "$container" | tr '.' '_')
  drush config:get "$container" --format=json > "$OUTPUT_DIR/${safe}.json"
done
drush config:get google_tag.settings --format=json > "$OUTPUT_DIR/google_tag_settings.json" 2>/dev/null || true

echo "=== Sitemap XML Download ==="
SITE_URI=$(drush core:status --field=uri)
curl -sL "${SITE_URI}/sitemap.xml" -o "$OUTPUT_DIR/sitemap.xml" 2>/dev/null || true

echo ""
echo "Export complete: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
```

### D7 Full Export

```bash
#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/tmp/metatag_export_d7"
mkdir -p "$OUTPUT_DIR"

echo "=== Metatag Defaults ==="
drush sql:query "
  SELECT entity_type, language, data
  FROM metatag
  WHERE entity_id = 0
  ORDER BY entity_type
" --extra=--batch > "$OUTPUT_DIR/defaults.tsv"

echo "=== Per-Entity Overrides ==="
for type in node taxonomy_term user; do
  drush sql:query "
    SELECT entity_id, revision_id, language, data
    FROM metatag
    WHERE entity_type = '$type' AND entity_id > 0
    ORDER BY entity_id
  " --extra=--batch > "$OUTPUT_DIR/overrides_${type}.tsv"
  count=$(wc -l < "$OUTPUT_DIR/overrides_${type}.tsv")
  echo "Exported: $type ($count rows)"
done

echo "=== XML Sitemap ==="
drush sql:query "
  SELECT type, subtype, COUNT(*) as cnt,
         AVG(priority) as avg_priority
  FROM xmlsitemap
  GROUP BY type, subtype
  ORDER BY type, subtype
" > "$OUTPUT_DIR/xmlsitemap_summary.tsv"

drush sql:query "
  SELECT name, value FROM variable
  WHERE name LIKE 'xmlsitemap_settings_%'
  ORDER BY name
" --extra=--batch > "$OUTPUT_DIR/xmlsitemap_settings.tsv"

echo "=== Analytics ==="
drush sql:query "
  SELECT name, value FROM variable
  WHERE name IN (
    'googleanalytics_account',
    'google_tag_container_id',
    'piwik_site_id',
    'piwik_url_http'
  )
" > "$OUTPUT_DIR/analytics.tsv"

echo "=== robots.txt ==="
drush sql:query "
  SELECT value FROM variable WHERE name = 'robotstxt_content'
" > "$OUTPUT_DIR/robotstxt_content.tsv" 2>/dev/null || true

echo ""
echo "Export complete: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
```

---

## 10. Migration Mapping Notes

### Token Translation

Metatag defaults use Drupal tokens. Map them to your target platform's equivalent:

| Drupal token | Meaning | Target platform equivalent |
|---|---|---|
| `[node:title]` | Node title | Page/post title variable |
| `[node:summary]` | Body summary or trimmed body | Excerpt/summary field |
| `[node:url]` | Node canonical URL | Page URL |
| `[node:field_image:entity:url]` | Image field URL | Featured image URL |
| `[node:author:display-name]` | Author display name | Author name |
| `[node:created:html_datetime]` | Created date in ISO 8601 | Published date |
| `[node:changed:html_datetime]` | Modified date in ISO 8601 | Modified date |
| `[site:name]` | Site name from config | Site title constant |
| `[site:url]` | Site base URL | Base URL |
| `[site:slogan]` | Site slogan | Site tagline/description |
| `[current-page:title]` | Current page title | Page title |
| `[current-page:url]` | Current page URL | Canonical URL |

### Priority of Data

When building metatags for each migrated page:

1. Use per-entity override values where they exist. These are hand-written by editors.
2. Fall back to entity-type+bundle defaults, resolving tokens against the entity's field data.
3. Fall back to entity-type defaults.
4. Fall back to global defaults.

### Common Pitfalls

- Serialized PHP in the database requires a proper unserializer. Python's `phpserialize` package handles this. Do not regex-parse serialized data.
- Empty string in an override means "clear this tag," not "use default." Respect this distinction.
- Token values in defaults need your target platform's template variable system. A static export of defaults is incomplete without token mapping.
- D7 metatag data may contain nested arrays (`value` key inside each tag). D8+ per-entity overrides are flat (tag name maps directly to string value).
- `og:image` must be an absolute URL. Relative paths break social sharing. Verify during migration.
- XML sitemap priority and changefreq values are suggestions to search engines, not guarantees. Some target platforms handle sitemaps differently. Preserve the values but document that behavior may vary.
- Schema.org JSON-LD from `schema_metatag` uses a pipe-delimited format for nested objects in config (e.g. `@type: Organization|name: Site`). Parse this format when converting to your target platform's structured data system.
