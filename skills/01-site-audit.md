# Skill: Drupal Site Audit

Analyze a Drupal site before migration. Collect version info, module inventory, content statistics, and structural metadata. Produce a machine-readable audit report that downstream migration skills consume.

Run this skill first. Every other UnDrupal skill depends on its output.

## Prerequisites

Ask the user which access methods they have. Accept one or more:

| Access method | What it unlocks |
|---|---|
| **Drush** (SSH or local) | Full audit: versions, modules, content counts, database stats |
| **Database** (direct connection or tunnel) | Full audit without Drush overhead |
| **JSON:API** (HTTP, authenticated or anonymous) | Entity type discovery + content counts via pagination metadata |
| **Config directory** (exported YAML, e.g. `config/sync`) | Module list, field definitions, content type structure. No content counts. |
| **Public site URL only** | Crawl-based detection. Limited to visible content types and page structure. |

Prefer access methods in that order. If the user has Drush, skip JSON:API and crawl steps. Combine methods when partial access exists (e.g. config YAML for structure + JSON:API for counts).

---

## 1. Core Site Info

### 1a. Via Drush

```bash
# Drupal version, PHP version, database type/version, Drupal root, site URI
drush core:status --format=json

# All installed extensions with status, version, type (module/theme)
drush pm:list --format=json

# Active theme
drush config:get system.theme default --format=json
drush config:get system.theme admin --format=json
```

Parse the `core:status` JSON for these fields:
- `drupal-version` (major.minor.patch)
- `php-version`
- `db-driver` (mysql, pgsql, sqlite)
- `db-version`
- `drupal-settings-file`
- `uri`

Parse `pm:list` JSON. Classify each extension:
- **core**: package starts with `Core` or `Drupal core`
- **contrib**: has a version string matching `\d+\.\d+\.\d+` or `8.x-\d+`
- **custom**: no version, or located under `modules/custom`

### 1b. Via Database (D9/D10/D11)

```sql
-- Drupal version
SELECT value FROM key_value
WHERE collection = 'system.schema' AND name = 'system';

-- Better: read from core.extension config
SELECT data FROM config WHERE name = 'core.extension';
-- The result is a PHP-serialized array. Unserialize it to get module => weight pairs.

-- Enabled modules and their schema versions
SELECT name, CAST(value AS CHAR) as schema_version
FROM key_value
WHERE collection = 'system.schema'
ORDER BY name;

-- PHP version: not stored in DB. If unavailable, note it as "requires Drush or phpinfo".

-- Database version
SELECT VERSION();

-- Database size (MySQL/MariaDB)
SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.TABLES
WHERE table_schema = DATABASE();

-- Database size (PostgreSQL)
SELECT pg_size_pretty(pg_database_size(current_database()));
```

### 1c. Via Database (D7)

D7 stores everything in the `system` table, not `key_value`.

```sql
-- Enabled modules
SELECT name, type, status, schema_version, info
FROM system
WHERE status = 1 AND type = 'module'
ORDER BY name;
-- The `info` column is a PHP-serialized array containing version, package, dependencies.

-- Enabled themes
SELECT name, status, info
FROM system
WHERE type = 'theme'
ORDER BY status DESC, name;

-- Drupal version
SELECT info FROM system WHERE name = 'system' AND type = 'module';
-- Unserialize `info`, read the `version` key.
```

### 1d. Via Config Directory (YAML)

```bash
# Module list from core.extension.yml
cat config/sync/core.extension.yml
# Contains: module: {module_name: weight, ...} and theme: {theme_name: weight, ...}

# Active themes
cat config/sync/system.theme.yml
# Contains: default: theme_name, admin: theme_name
```

No version info is available from config YAML alone. Note this gap in the report.

### 1e. Via JSON:API

```
GET /jsonapi
```

The root endpoint returns a `links` object. Each key is a resource type in `entity_type--bundle` format (e.g. `node--article`, `taxonomy_term--tags`). This reveals all non-internal entity types and bundles.

No module list or version info is available via JSON:API. Note this gap.

---

## 2. Content Statistics

### 2a. Nodes per Content Type (D9/D10/D11 via Drush)

```bash
drush sql:query "
  SELECT type,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS published,
    SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS unpublished,
    COUNT(*) AS total
  FROM node_field_data
  GROUP BY type
  ORDER BY total DESC;
"
```

### 2b. Nodes per Content Type (D7)

```sql
SELECT n.type,
  SUM(CASE WHEN n.status = 1 THEN 1 ELSE 0 END) AS published,
  SUM(CASE WHEN n.status = 0 THEN 1 ELSE 0 END) AS unpublished,
  COUNT(*) AS total
FROM node n
GROUP BY n.type
ORDER BY total DESC;
```

### 2c. Taxonomy Terms per Vocabulary

```sql
-- D9/D10/D11
SELECT td.vid, COUNT(*) AS term_count
FROM taxonomy_term_field_data td
GROUP BY td.vid
ORDER BY term_count DESC;

-- D7
SELECT v.name AS vocabulary, COUNT(t.tid) AS term_count
FROM taxonomy_term_data t
JOIN taxonomy_vocabulary v ON t.vid = v.vid
GROUP BY v.name
ORDER BY term_count DESC;
```

### 2d. Media Entities per Bundle (D9/D10/D11 only)

```sql
SELECT bundle, COUNT(*) AS total
FROM media_field_data
GROUP BY bundle
ORDER BY total DESC;
```

Media entities do not exist in D7. D7 uses `file_managed` and may have the `media` contrib module with a different schema.

### 2e. Paragraphs per Type

```sql
-- Only if paragraphs module is installed (check pm:list first)
SELECT type, COUNT(*) AS total
FROM paragraphs_item_field_data
GROUP BY type
ORDER BY total DESC;

-- D7 paragraphs (paragraphs_item table)
SELECT bundle, COUNT(*) AS total
FROM paragraphs_item
GROUP BY bundle
ORDER BY total DESC;
```

### 2f. Users

```sql
-- D9/D10/D11
SELECT
  SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS active,
  SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS blocked,
  COUNT(*) AS total
FROM users_field_data
WHERE uid > 0;

-- D7
SELECT
  SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS active,
  SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS blocked,
  COUNT(*) AS total
FROM users
WHERE uid > 0;
```

### 2g. Comments per Node Type

```sql
-- D9/D10/D11 (comment module stores entity_type and field_name)
SELECT
  n.type AS node_type,
  COUNT(c.cid) AS comment_count
FROM comment_field_data c
JOIN node_field_data n ON c.entity_id = n.nid AND c.entity_type = 'node'
GROUP BY n.type
ORDER BY comment_count DESC;

-- D7
SELECT n.type AS node_type, COUNT(c.cid) AS comment_count
FROM comment c
JOIN node n ON c.nid = n.nid
GROUP BY n.type
ORDER BY comment_count DESC;
```

### 2h. Menu Links per Menu

```sql
-- D9/D10/D11
SELECT menu_name, COUNT(*) AS link_count
FROM menu_link_content_data
GROUP BY menu_name
ORDER BY link_count DESC;

-- D7
SELECT menu_name, COUNT(*) AS link_count
FROM menu_links
GROUP BY menu_name
ORDER BY link_count DESC;
```

### 2i. Redirects

```sql
-- redirect module (D7 and D9+)
SELECT COUNT(*) AS redirect_count FROM redirect;
```

### 2j. Webform Submissions

```sql
-- D9/D10/D11 (webform module)
SELECT webform_id, COUNT(*) AS submission_count
FROM webform_submission
GROUP BY webform_id
ORDER BY submission_count DESC;

-- D7 (webform module)
SELECT w.nid, n.title, COUNT(ws.sid) AS submission_count
FROM webform_submissions ws
JOIN webform w ON ws.nid = w.nid
JOIN node n ON w.nid = n.nid
GROUP BY w.nid, n.title
ORDER BY submission_count DESC;
```

### 2k. Files by Scheme

```sql
-- D9/D10/D11 and D7 both use file_managed
SELECT
  SUBSTRING_INDEX(uri, '://', 1) AS scheme,
  COUNT(*) AS file_count,
  ROUND(SUM(filesize) / 1024 / 1024, 2) AS total_size_mb
FROM file_managed
GROUP BY scheme
ORDER BY file_count DESC;
```

### 2l. Files by MIME Type

```sql
SELECT filemime, COUNT(*) AS file_count,
  ROUND(SUM(filesize) / 1024 / 1024, 2) AS total_size_mb
FROM file_managed
GROUP BY filemime
ORDER BY file_count DESC;
```

### 2m. Path Aliases

```sql
-- D9/D10/D11
SELECT COUNT(*) AS alias_count FROM path_alias;

-- D7
SELECT COUNT(*) AS alias_count FROM url_alias;
```

### 2n. Revision Counts per Content Type

```sql
-- D9/D10/D11
SELECT nfd.type,
  COUNT(nr.vid) AS revision_count,
  ROUND(AVG(rev_per_node.rev_count), 1) AS avg_revisions_per_node
FROM node_revision nr
JOIN node_field_data nfd ON nr.nid = nfd.nid
JOIN (
  SELECT nid, COUNT(*) AS rev_count
  FROM node_revision
  GROUP BY nid
) rev_per_node ON nr.nid = rev_per_node.nid
GROUP BY nfd.type
ORDER BY revision_count DESC;

-- D7
SELECT n.type,
  COUNT(nr.vid) AS revision_count
FROM node_revision nr
JOIN node n ON nr.nid = n.nid
GROUP BY n.type
ORDER BY revision_count DESC;
```

### 2o. Total Database Size

See Section 1b above (`information_schema` query).

Also collect per-table sizes for the top 20 largest tables:

```sql
-- MySQL/MariaDB
SELECT table_name,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb,
  table_rows
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC
LIMIT 20;
```

### 2p. Via JSON:API (no database access)

For each resource type discovered at `/jsonapi`:

```
GET /jsonapi/node/article?page[limit]=1
```

Read the `meta.count` field from the response (available when the JSON:API module includes count metadata). If `meta.count` is absent, paginate using `links.next` and count pages. This is slow for large collections; warn the user.

To split published/unpublished via JSON:API, add a filter:

```
GET /jsonapi/node/article?filter[status]=1&page[limit]=1
GET /jsonapi/node/article?filter[status]=0&page[limit]=1
```

Note: anonymous users cannot see unpublished content. An authenticated session with admin permissions is required for accurate counts.

### 2q. Via Site Crawl (last resort)

If no other access method is available:

1. Fetch the sitemap (`/sitemap.xml`) if it exists. Parse URLs to identify content type patterns (e.g. `/blog/`, `/news/`, `/products/`).
2. Crawl the homepage and follow internal links (limit depth to 3 levels, limit total pages to 500).
3. Look for Drupal-specific HTML signatures:
   - `<meta name="Generator" content="Drupal X">` for version detection
   - CSS class patterns: `node--type-{type}`, `page-node-type-{type}` for content types
   - Body classes: `page-taxonomy-term`, `node-type-{type}` (D7)
4. Check `/user/login` to confirm Drupal.
5. Check `/jsonapi` for JSON:API availability (it may be publicly accessible).

Crawl-based audits cannot produce exact counts. Report estimates with a confidence qualifier.

---

## 3. Advanced Detection

Run these checks after core info and content stats are collected.

### 3a. Multilingual Status

```bash
# Drush
drush pm:list --filter="name=language,content_translation,locale,config_translation" --format=json

# Or via SQL (D9+)
drush sql:query "
  SELECT name FROM key_value
  WHERE collection = 'system.schema'
  AND name IN ('language','content_translation','locale','config_translation');
"
```

If `language` or `content_translation` modules are enabled:

```sql
-- Count configured languages
SELECT COUNT(*) FROM config WHERE name LIKE 'language.entity.%';

-- Count translated nodes
SELECT langcode, COUNT(*) AS node_count
FROM node_field_data
GROUP BY langcode
ORDER BY node_count DESC;
```

D7 multilingual detection:

```sql
-- Check if locale or i18n modules are enabled
SELECT name FROM system WHERE status = 1 AND name IN ('locale','i18n','i18n_node','entity_translation');

-- Count languages
SELECT COUNT(*) FROM languages WHERE enabled = 1;

-- Count translated content
SELECT language, COUNT(*) FROM node GROUP BY language;
```

### 3b. Content Moderation

```bash
drush pm:list --filter="name=content_moderation,workflows" --format=json
```

If enabled:

```sql
-- List workflows (D9+)
SELECT name FROM config WHERE name LIKE 'workflows.workflow.%';

-- Count moderated entities
SELECT moderation_state, COUNT(*) AS total
FROM content_moderation_state_field_data
GROUP BY moderation_state;
```

D7: Check for `workbench_moderation` module in `system` table.

### 3c. Commerce

```bash
drush pm:list --filter="package=Commerce" --format=json
```

If Commerce modules are found:

```sql
-- D9+ Commerce
SELECT type, COUNT(*) AS total FROM commerce_product_field_data GROUP BY type;
SELECT type, COUNT(*) AS total FROM commerce_order GROUP BY type;
SELECT COUNT(*) AS total FROM commerce_payment;
```

D7: Check for `commerce_product`, `commerce_order` tables.

### 3d. Custom Entity Types

```sql
-- D9/D10/D11: Find entity types not from core or well-known contrib
-- List all entity type tables by checking for *_field_data pattern
SELECT DISTINCT REPLACE(table_name, '_field_data', '') AS possible_entity_type
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
AND table_name LIKE '%_field_data'
AND table_name NOT IN (
  'node_field_data','users_field_data','taxonomy_term_field_data',
  'comment_field_data','media_field_data','block_content_field_data',
  'menu_link_content_data','file_managed','path_alias',
  'aggregator_feed','aggregator_item','contact_message_field_data',
  'content_moderation_state_field_data','shortcut_field_data',
  'commerce_product_field_data','commerce_order_field_data',
  'paragraphs_item_field_data','webform_submission'
);
```

For each custom entity type found, count rows in its `_field_data` table.

### 3e. Cron Configuration

```bash
drush config:get system.cron --format=json
# Returns threshold.autorun (in seconds), threshold.requirements_warning, threshold.requirements_error

drush sql:query "SELECT value FROM key_value WHERE collection = 'state' AND name = 'system.cron_last';"
# Returns serialized timestamp of last cron run
```

### 3f. External Integrations

Check the module list for these patterns:

| Integration | Modules to look for |
|---|---|
| SMTP / Mail | `smtp`, `swiftmailer`, `symfony_mailer`, `mailsystem`, `mimemail` |
| LDAP | `ldap`, `ldap_authentication`, `ldap_servers`, `externalauth` |
| SSO / SAML | `samlauth`, `simplesamlphp_auth`, `openid_connect`, `cas` |
| Search backends | `search_api_solr`, `search_api_elasticsearch`, `elasticsearch_connector` |
| CDN / Storage | `s3fs`, `cdn`, `cloudfront`, `flysystem` |
| API consumers | `jsonapi`, `graphql`, `restui`, `consumers`, `simple_oauth` |
| Analytics | `google_analytics`, `matomo`, `google_tag` |
| Caching | `redis`, `memcache`, `varnish_purge`, `purge` |

Flag any found integrations. The migration plan needs to account for each one.

### 3g. Page Builder Detection

Page builders store content in non-standard structures. Identify which one is in use before planning content extraction.

```bash
# Check for page builder modules
drush pm:list --filter="name=experience_builder,cohesion,gutenberg,layout_paragraphs" --format=json
```

Or via SQL (D9+):

```sql
SELECT name FROM key_value
WHERE collection = 'system.schema'
AND name IN ('experience_builder','cohesion','gutenberg','layout_paragraphs');
```

**Experience Builder** (`experience_builder` module): Drupal's core page builder starting in D11. If present, check for experience builder components:

```sql
SELECT type, COUNT(*) AS total
FROM experience_builder_field_data
GROUP BY type
ORDER BY total DESC;
```

**Site Studio** (`cohesion` module): Check for entities that use `cohesion_layout` fields.

```sql
-- Count Site Studio layout entities
SELECT COUNT(*) AS cohesion_layout_count
FROM cohesion_layout;

-- Count Site Studio components
SELECT COUNT(*) AS component_count
FROM cohesion_custom_style;

-- Identify content types with cohesion layout fields
SELECT DISTINCT bundle
FROM config
WHERE name LIKE 'field.field.node.%.layout_canvas';
```

**Gutenberg** (`gutenberg` module): Identify which content types use it.

```bash
# Check which content types have Gutenberg enabled
drush config:get node.type.article third_party_settings.gutenberg --format=json
```

```sql
-- List all content types with Gutenberg third-party settings
SELECT name FROM config
WHERE name LIKE 'node.type.%'
AND data LIKE '%gutenberg%';
```

Or from config YAML:

```bash
# Scan all node type configs for Gutenberg settings
grep -rl 'gutenberg' config/sync/node.type.*.yml
```

**Layout Paragraphs** (`layout_paragraphs` module): Works on top of the Paragraphs module. If detected, paragraph counts from Section 2e already cover its content. Note its presence in the report so the migration plan accounts for layout structure stored in paragraph behavior settings.

### 3h. Multisite Detection

Multisite setups multiply the migration scope. Each sub-site may have its own database, content, and configuration.

**Directory-based multisite:**

```bash
# Check for sites.php
if [ -f sites/sites.php ]; then
  echo "sites.php found"
  grep -cE '^\s*\$sites\[' sites/sites.php
fi

# Count site directories (exclude default, all, simpletest)
ls -d sites/*/ 2>/dev/null | grep -vE '/(default|all|simpletest)/$' | wc -l
```

**Domain Access** (`domain` module): Manages multiple domains within a single Drupal install.

```bash
drush pm:list --filter="name=domain" --format=json
```

```sql
-- Count domain records (D9+)
SELECT COUNT(*) AS domain_count FROM config WHERE name LIKE 'domain.record.%';

-- Or via Drush
-- drush domain:list --format=json
```

**Workspaces** (`workspaces` module): Content staging and preview environments within Drupal.

```bash
drush pm:list --filter="name=workspaces" --format=json
```

```sql
-- Count workspaces
SELECT COUNT(*) FROM workspaces;

-- Count workspace-tracked entity associations
SELECT COUNT(*) FROM workspace_association;
```

If workspaces exist, each workspace may contain unpublished content variants. The migration must decide which workspace state to export.

### 3i. Hosting Platform Detection

The hosting platform affects how you access the site, run commands, and extract files. Detect it early.

**Acquia:**

```bash
# Environment variable (available on Acquia servers)
echo $AH_SITE_ENVIRONMENT

# Check for Acquia modules
drush pm:list --filter="name=acquia_connector,acsf,acsf_duplication" --format=json
```

```sql
SELECT name FROM key_value
WHERE collection = 'system.schema'
AND name IN ('acquia_connector','acsf','acsf_duplication');
```

If `acsf` is present, this is an Acquia Site Factory install. Each factory site is a separate Drupal instance; treat it like a multisite.

**Pantheon:**

```bash
# Environment variable
echo $PANTHEON_ENVIRONMENT

# Check for Pantheon module
drush pm:list --filter="name=pantheon_advanced_page_cache" --format=json
```

```sql
SELECT name FROM key_value
WHERE collection = 'system.schema'
AND name = 'pantheon_advanced_page_cache';
```

**Platform.sh:**

```bash
# Environment variable
echo $PLATFORM_APPLICATION

# Check for config file in the project root
test -f .platform.app.yaml && echo "Platform.sh detected"
```

**Lagoon:**

```bash
# Check for Lagoon config file
test -f .lagoon.yml && echo "Lagoon detected"
```

For config-directory-only audits, check for platform-specific modules in `core.extension.yml`.

### 3j. Workspaces Content Staging

If the `workspaces` module is enabled (detected in 3h), collect details on staged content:

```sql
-- List all workspaces with their owners
SELECT id, label, uid FROM workspaces;

-- Count entity associations per workspace
SELECT workspace, COUNT(*) AS tracked_entities
FROM workspace_association
GROUP BY workspace
ORDER BY tracked_entities DESC;

-- Identify which entity types are tracked
SELECT target_entity_type_id, COUNT(*) AS count
FROM workspace_association
GROUP BY target_entity_type_id
ORDER BY count DESC;
```

During migration, decide whether to flatten all workspace content into a single state or preserve workspace boundaries in the target platform.

---

## 4. Output Format

Produce the audit as a JSON object matching this schema. Store it at `audit-report.json` in the project root.

```json
{
  "audit_version": "1.0",
  "generated_at": "2024-01-15T10:30:00Z",
  "access_methods_used": ["drush", "database"],

  "site": {
    "drupal_version": "10.2.3",
    "drupal_major": 10,
    "php_version": "8.2.14",
    "database_driver": "mysql",
    "database_version": "8.0.35",
    "database_size_mb": 1245.67,
    "site_uri": "https://example.com"
  },

  "extensions": {
    "modules": {
      "core": [
        {"name": "node", "version": "10.2.3", "status": "enabled"},
        "..."
      ],
      "contrib": [
        {"name": "pathauto", "version": "1.12", "status": "enabled"},
        "..."
      ],
      "custom": [
        {"name": "mysite_utils", "version": null, "status": "enabled"},
        "..."
      ]
    },
    "themes": {
      "default": "olivero",
      "admin": "claro",
      "all": [
        {"name": "olivero", "version": "10.2.3", "status": "enabled"},
        "..."
      ]
    }
  },

  "content": {
    "nodes": [
      {
        "type": "article",
        "published": 1523,
        "unpublished": 47,
        "total": 1570,
        "revisions": 4890,
        "avg_revisions_per_node": 3.1
      }
    ],
    "taxonomy_terms": [
      {"vocabulary": "tags", "count": 342}
    ],
    "media": [
      {"bundle": "image", "count": 2841}
    ],
    "paragraphs": [
      {"type": "text", "count": 5102}
    ],
    "users": {
      "active": 1205,
      "blocked": 89,
      "total": 1294
    },
    "comments": [
      {"node_type": "article", "count": 892}
    ],
    "menu_links": [
      {"menu": "main", "count": 45}
    ],
    "redirects": 1203,
    "webform_submissions": [
      {"webform_id": "contact", "count": 567}
    ],
    "files": {
      "by_scheme": [
        {"scheme": "public", "count": 8923, "size_mb": 4521.3}
      ],
      "by_mime": [
        {"mime": "image/jpeg", "count": 5012, "size_mb": 3200.1}
      ]
    },
    "path_aliases": 3201,
    "total_database_size_mb": 1245.67,
    "largest_tables": [
      {"table": "node_revision__body", "size_mb": 320.5, "rows": 48000}
    ]
  },

  "multilingual": {
    "enabled": true,
    "modules": ["language", "content_translation"],
    "languages": ["en", "es", "fr"],
    "translated_node_counts": {
      "en": 1523,
      "es": 980,
      "fr": 412
    }
  },

  "content_moderation": {
    "enabled": true,
    "workflows": ["editorial"],
    "state_counts": {
      "published": 1400,
      "draft": 120,
      "archived": 50
    }
  },

  "commerce": {
    "enabled": false
  },

  "custom_entity_types": [
    {"type": "event", "count": 234}
  ],

  "integrations": {
    "smtp": {"detected": true, "module": "symfony_mailer"},
    "ldap": {"detected": false},
    "sso": {"detected": true, "module": "samlauth"},
    "search": {"detected": true, "module": "search_api_solr"},
    "cdn": {"detected": false},
    "api_consumers": {"detected": true, "modules": ["jsonapi", "simple_oauth"]},
    "analytics": {"detected": true, "module": "google_tag"},
    "caching": {"detected": true, "module": "redis"}
  },

  "cron": {
    "autorun_seconds": 10800,
    "last_run": "2024-01-15T09:00:00Z"
  },

  "page_builder": {
    "detected": true,
    "type": "gutenberg",
    "module": "gutenberg",
    "content_types_using": ["article", "landing_page"],
    "entity_count": null
  },

  "multisite": {
    "sites_php": false,
    "site_directories": 0,
    "domain_access": {
      "enabled": false,
      "domain_count": 0
    },
    "workspaces": {
      "enabled": true,
      "workspace_count": 3,
      "association_count": 487
    }
  },

  "hosting_platform": {
    "detected": true,
    "platform": "acquia",
    "indicators": ["AH_SITE_ENVIRONMENT", "acquia_connector module"],
    "is_site_factory": false
  },

  "red_flags": []
}
```

Omit sections where data is unavailable due to access limitations. Add a top-level `"gaps"` array listing what could not be collected and why.

---

## 5. Red Flags

After collecting all data, scan for these conditions. Add each match to the `red_flags` array with a severity (`critical`, `warning`, `info`) and a description.

### Critical

- **Drupal 7 end-of-life**: D7 reached EOL on January 5, 2025. No security patches.
- **Drupal 8 end-of-life**: D8 reached EOL on November 2, 2021.
- **PHP < 8.1**: End-of-life. Security risk.
- **Known insecure modules**: `php` (PHP Filter), `coder` on production, `devel` on production, `views_php`.
- **SA-flagged modules**: If `drush pm:security` is available, run it and include results.

### Warning

- **Revision table bloat**: Any content type averaging more than 20 revisions per node, or revision tables exceeding 500MB.
- **Orphaned files**: `file_managed` entries with no references in `file_usage` (run `SELECT COUNT(*) FROM file_managed fm LEFT JOIN file_usage fu ON fm.fid = fu.fid WHERE fu.fid IS NULL;`).
- **Disabled but present modules**: Modules in the codebase but not enabled may contain vulnerabilities.
- **100+ contrib modules**: Migration complexity rises sharply. Each module needs a target-platform equivalent or replacement strategy.
- **Large file store**: Public files exceeding 10GB require a file migration strategy (CDN, object storage, progressive sync).
- **Custom modules**: Each one needs manual review. No automated migration path exists.
- **Deprecated modules**: `color`, `aggregator`, `hal`, `rdf` (removed or deprecated in D10+).
- **Database > 5GB**: Large databases slow down migration testing cycles.
- **High redirect count (> 5000)**: Redirect mapping needs its own migration step.

### Info

- **Multilingual site**: Adds a translation migration phase.
- **Content moderation enabled**: Moderation states and workflows need mapping to the target platform.
- **Commerce enabled**: Commerce data migration is a separate workstream.
- **Webform submissions present**: Decide whether to migrate submission data or archive it.
- **Paragraphs detected**: Paragraph-to-component mapping is one of the most time-consuming migration tasks.
- **Page builder detected**: Content stored in page builder formats (Site Studio, Gutenberg, Experience Builder, Layout Paragraphs) requires custom extraction logic.
- **Multisite detected**: Each sub-site or domain needs its own migration plan and timeline.
- **Workspaces enabled**: Staged content in workspaces must be resolved or exported per-workspace.
- **Acquia Site Factory detected**: Each factory site is a separate migration target.

---

## 6. Execution Procedure

Follow this sequence:

1. Ask the user which access methods are available.
2. Detect Drupal version (D7 vs D9+). This determines which SQL queries and Drush commands to use.
3. Collect core site info (Section 1).
4. Collect content statistics (Section 2). Run all applicable SQL queries. For Drush access, wrap each query in `drush sql:query`.
5. Run advanced detection checks (Section 3).
6. Scan for red flags (Section 5).
7. Assemble the JSON report.
8. Present a human-readable summary to the user: total content items, module count, detected integrations, and all red flags.

If a query fails (missing table, permission denied), log the error in a `"query_errors"` array in the report and move on. Do not halt the audit over a single failed query.

For D7 sites: use the D7-specific queries throughout. D7 has no `_field_data` tables, no `key_value` table, no media entity type, and different table structures for users, comments, and menu links.

For JSON:API-only audits: walk the `/jsonapi` resource list, fetch counts for each entity type, and note that module/version/integration data is unavailable.

For config-directory-only audits: parse `core.extension.yml` for the module list, read `node.type.*.yml` for content type definitions, read `field.storage.*.yml` for field types. Content counts are unavailable.
