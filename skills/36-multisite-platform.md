# Skill 36: Multi-site Setups and Hosting Platform Architectures

Discover how many Drupal sites exist, how they share code and data, and where they run. This determines whether you migrate one site or fifty, sequentially or in parallel, from one database or many.

---

## Why This Matters

A single Drupal codebase can serve dozens of sites. Some share a database. Some share users. Some share nothing but PHP files. The migration plan for a standalone Drupal install looks nothing like the plan for an Acquia Site Factory deployment with 200 sites on a shared codebase.

Get the topology wrong and you will either duplicate content across targets or lose content that lived on a site you did not know existed.

---

## Drupal Native Multisite

Drupal ships with built-in multisite support. One codebase, multiple `sites/` directories, separate databases per site.

### How It Works

Drupal resolves the active site directory from the incoming HTTP host. The lookup chain:

1. Check `sites/sites.php` for an explicit mapping
2. Strip the hostname left to right, path right to left, scanning for matching directories
3. Fall back to `sites/default/`

For `https://www.example.com:8080/mysite/test/`, Drupal checks directories in this order:

```
sites/8080.www.example.com.mysite.test
sites/www.example.com.mysite.test
sites/example.com.mysite.test
sites/8080.www.example.com.mysite
sites/www.example.com.mysite
sites/example.com.mysite
sites/8080.www.example.com
sites/www.example.com
sites/example.com
sites/default
```

### sites.php

The `sites/sites.php` file maps hostnames to site directories. It overrides the directory resolution chain above.

```php
// sites/sites.php
$sites['example.com'] = 'site_a';
$sites['another.com'] = 'site_b';
$sites['dev.example.com'] = 'site_a';  // dev alias for site_a
$sites['8080.localhost.sitea'] = 'site_a';  // local dev
```

The array key format is `<port>.<domain>.<path>`, with port and path omitted when standard.

### Per-site Directory Structure

```
sites/
  default/              # fallback site
    settings.php
    services.yml
    files/              # public file uploads
  example.com/          # site A
    settings.php        # database connection, config sync dir
    services.yml        # service overrides
    files/
    modules/            # site-specific modules (not managed by Composer)
    themes/             # site-specific themes
  another.com/          # site B
    settings.php
    files/
```

Each site has its own `settings.php` with its own `$databases` array pointing to a separate database. Modules and themes in the root `modules/` and `themes/` directories are shared across all sites. Modules in `sites/example.com/modules/` are visible only to that site.

### Discovery Commands

```bash
# List all site directories (quick scan)
ls -d sites/*/settings.php 2>/dev/null

# Parse sites.php for explicit mappings
php -r "include 'sites/sites.php'; print_r(\$sites);"

# List all configured sites via Drush
drush sa

# Run drush against a specific site
drush --uri=example.com status
drush --uri=another.com status

# Check each site's database connection
for dir in sites/*/; do
  site=$(basename "$dir")
  [ "$site" = "default" ] && continue
  echo "=== $site ==="
  drush --uri="$site" sql:connect 2>/dev/null || echo "no db config"
done
```

### Database Isolation Check

Each site should have its own database. Verify:

```bash
# Extract database names from each site's settings.php
for dir in sites/*/settings.php; do
  site=$(dirname "$dir" | xargs basename)
  db=$(php -r "
    include '$dir';
    echo \$databases['default']['default']['database'] ?? 'NOT SET';
  " 2>/dev/null)
  echo "$site -> $db"
done
```

If two sites point to the same database name, they share data. This is rare but possible with table prefixes (deprecated in D9+).

### Migration Scoping

Questions to answer for each multisite:

- How many sites exist? List every `sites/*/settings.php`.
- Do any share a database? Compare `$databases` across settings files.
- Which modules differ per site? Compare `core.extension.yml` across config directories.
- Which sites share users? Separate databases means separate user tables.
- What is the domain mapping? Document old domain to new domain for each site.
- Migrate together or independently? Sites with shared content need coordination. Independent sites can migrate on separate timelines.

---

## Domain Access Module

Domain Access takes a different approach: one database, one Drupal install, multiple domains. Content is tagged with which domains can access it.

### Architecture

- Single database for all domains
- `domain` config entities define each domain (machine name, hostname, scheme, weight, is_default)
- Entity reference fields on content control per-domain visibility
- Single user base shared across all domains

### Key Fields

Two fields are added to every content type and user entity:

| Field | Machine Name | Purpose |
|---|---|---|
| Domain Access | `field_domain_access` | Entity reference to `domain` entities. Which domains can see this content. |
| Domain All Affiliates | `field_domain_all_field` | Boolean. If true, content appears on every domain. |
| Domain Source | `field_domain_source` | Entity reference. The canonical domain for this content. Controls which domain owns the URL. |

### Discovery

```bash
# List all domain records
drush config:list | grep domain.record

# Export domain configuration
drush config:get domain.record.example_com --format=yaml

# Count content per domain via database
drush sqlq "
  SELECT daf.field_domain_access_target_id AS domain_id,
         COUNT(*) AS node_count
  FROM node__field_domain_access daf
  GROUP BY daf.field_domain_access_target_id
  ORDER BY node_count DESC;
"

# List all domains with their hostnames
drush eval "
  \$storage = \Drupal::entityTypeManager()->getStorage('domain');
  foreach (\$storage->loadMultiple() as \$domain) {
    echo \$domain->id() . ' | ' . \$domain->getHostname() . ' | '
      . (\$domain->isDefault() ? 'DEFAULT' : '') . PHP_EOL;
  }
"

# Check which content types have domain access fields
drush config:list | grep field.field | grep domain_access
```

### Config Files

Domain records live in config:

```yaml
# config/sync/domain.record.example_com.yml
id: example_com
domain_id: example_com
hostname: example.com
name: 'Example Site'
scheme: https
status: true
weight: 0
is_default: true
```

Field storage:

```yaml
# field.storage.node.field_domain_access.yml
id: node.field_domain_access
field_name: field_domain_access
entity_type: node
type: entity_reference
settings:
  target_type: domain
cardinality: -1
```

### Database Tables

```sql
-- Content domain assignments
SELECT * FROM node__field_domain_access LIMIT 10;
-- Columns: bundle, entity_id, field_domain_access_target_id

-- Content canonical domain
SELECT * FROM node__field_domain_source LIMIT 10;
-- Columns: bundle, entity_id, field_domain_source_target_id

-- User domain assignments
SELECT * FROM user__field_domain_access LIMIT 10;

-- "All affiliates" flag
SELECT * FROM node__field_domain_all_field WHERE field_domain_all_field_value = 1;
```

### Sub-modules

- `domain_access`: Core access control. Adds fields and node grants.
- `domain_alias`: Map multiple hostnames to one domain record.
- `domain_config`: Override config per domain (site name, theme, etc.).
- `domain_content`: Admin UI for managing content per domain.
- `domain_source`: Controls canonical URL assignment.

### Migration Approach

Domain Access sites are one database. The migration path depends on the target:

- **Single target site**: Export all content. Map domain assignments to categories, tags, or site references in the target. Ignore domain fields if the target has one domain.
- **Multiple target sites**: Split content by domain assignment. Content tagged to multiple domains gets duplicated or linked. Content tagged "all affiliates" goes everywhere.
- **Deduplication**: Content shared across domains exists once in Drupal. If migrating to separate systems, decide whether to copy it to each or pick a canonical home.

```bash
# Export content grouped by domain
drush sqlq "
  SELECT d.hostname,
         n.type AS content_type,
         COUNT(*) AS count
  FROM node__field_domain_access daf
  JOIN node_field_data n ON n.nid = daf.entity_id
  JOIN config c ON 1=1
  LEFT JOIN (
    SELECT REPLACE(name, 'domain.record.', '') AS domain_id,
           data
    FROM config
    WHERE name LIKE 'domain.record.%'
  ) dr ON dr.domain_id = daf.field_domain_access_target_id
  GROUP BY d.hostname, n.type
  ORDER BY d.hostname, count DESC;
"

# Simpler: count per domain ID
drush sqlq "
  SELECT field_domain_access_target_id AS domain,
         COUNT(DISTINCT entity_id) AS nodes
  FROM node__field_domain_access
  GROUP BY field_domain_access_target_id;
"
```

---

## Acquia Site Factory (ACSF)

Acquia Site Factory manages large-scale Drupal multisite deployments. One codebase deployed centrally. Each site gets its own database. A web UI and API handle site creation, theming, and deployment.

### Architecture

- Factory: the management layer. Creates sites, manages deployments, provides the admin UI.
- Sites: individual Drupal installs, each with its own database, created from factory templates.
- Stacks: server groups. Sites are distributed across stacks.
- Centralized Git deployment. Code changes deploy to all sites simultaneously.
- Per-site databases. No shared content tables.
- Per-site theme overrides via a theme selection UI.
- Config splits handle per-site configuration differences.

### ACSF API

The factory exposes REST endpoints for site management:

```bash
# List all sites
curl -s -u "$USERNAME:$API_KEY" \
  "https://www.FACTORY_ID.acsitefactory.com/api/v1/sites?limit=100&page=1"

# Response includes: id, site, stack_id, domain, groups, db_name, created

# Get site details
curl -s -u "$USERNAME:$API_KEY" \
  "https://www.FACTORY_ID.acsitefactory.com/api/v1/sites/SITE_ID"

# List domains for a site
curl -s -u "$USERNAME:$API_KEY" \
  "https://www.FACTORY_ID.acsitefactory.com/api/v1/domains/SITE_ID"

# Using Acquia CLI
acli acsf:sites:find --limit=1000
acli acsf:sites:find --domain_contains=example.com
```

### ACSF Drush Tools

The `acquia/acsf-tools` package adds Drush commands for factory management:

```bash
# Install
composer require acquia/acsf-tools

# List all sites in the factory (run on the server)
drush @factory.env acsf-tools-list
# Aliases: sfl

# Get detailed site info (ID, name, DB name, domain)
drush @factory.env acsf-tools-info
# Aliases: sfi

# Run a drush command against ALL sites
drush @factory.env acsf-tools-ml status
# Aliases: sfml

# Dump all site databases
drush @factory.env acsf-tools-dump --result-folder=/backups/20240101
# Aliases: sfdu

# Restore databases
drush @factory.env acsf-tools-restore --source-folder=/backups/20240101
# Aliases: sfre
```

### Configuration

The `acsf-tools` config file maps factory credentials:

```yaml
# acsf_tools_config.yml (DO NOT commit this)
site_id: 'my_factory'
rest_api_user: 'admin.user'
rest_api_key: 'your-api-key-here'
rest_factories:
  prod: 'https://www.my_factory.acsitefactory.com'
  test: 'https://www.my_factory.01test.acsitefactory.com'
  dev:  'https://www.my_factory.01dev.acsitefactory.com'
root_domain: 'acsitefactory.com'
subdomain_pattern: '{subdomain}-{env}'
prod_web: 'web-1234'
dev_web: 'web-5678'
```

### Site Data File

On ACSF servers, site information lives in a JSON map file loaded by `gardens_site_data_load_file()`. It contains every site's domain, database name, and configuration.

```php
// Reading the site map on ACSF
$map = gardens_site_data_load_file();
foreach ($map['sites'] as $domain => $details) {
  $db_name = $details['conf']['gardens_db_name'];
  $site_id = $details['conf']['gardens_site_id'];
  echo "$domain -> $db_name (ID: $site_id)\n";
}
```

### Migration Approach

1. Use the ACSF API to enumerate all sites: IDs, domains, database names.
2. Iterate per site. Each site has its own database, so each is an independent migration unit.
3. Use `acsf-tools-dump` to create database dumps for all sites in one pass.
4. Export config per site: `drush @factory.env sfml config:export`.
5. Export files per site from the shared filesystem.
6. Decide on phasing: migrate high-traffic sites first, long-tail sites later.
7. Per-site theme overrides map to per-site config in the target.

```bash
# Iterate all sites and export
drush @factory.prod sfl --fields=name,domains | while read site; do
  prefix=$(echo "$site" | cut -d' ' -f1)
  echo "Exporting $prefix..."
  drush @factory.prod --uri="$prefix.acsitefactory.com" sql:dump \
    --result-file="/tmp/exports/$prefix.sql" --gzip
done
```

---

## Pantheon

Pantheon provides managed Drupal hosting with a fixed environment model and its own workflow tooling.

### Environment Model

Three permanent environments:

- **Dev**: receives Git pushes. Connection mode is Git or SFTP.
- **Test**: receives code deployments from Dev. Database/files pulled from Live.
- **Live**: production.

Plus **Multidev** environments: feature-branch environments branched from Dev. Each gets its own database and file mount. Limited by plan tier (usually 5-10 multidevs).

### Detection

```php
// In settings.php or custom code
if (defined('PANTHEON_ENVIRONMENT')) {
  // Running on Pantheon
  $env = $_ENV['PANTHEON_ENVIRONMENT'];  // 'dev', 'test', 'live', or multidev name
}

// Other environment variables
$_ENV['PANTHEON_SITE'];           // site UUID
$_ENV['PANTHEON_SITE_NAME'];      // machine name
$_ENV['PANTHEON_ENVIRONMENT'];    // environment name
$_ENV['PANTHEON_INFRASTRUCTURE_PROVIDER']; // hosting detail
$_ENV['DB_HOST'];                 // database host
$_ENV['DB_PORT'];                 // database port
$_ENV['DB_USER'];                 // database user
$_ENV['DB_PASSWORD'];             // database password
$_ENV['DB_NAME'];                 // database name
```

### Terminus CLI

Terminus is the command-line interface for Pantheon:

```bash
# Authenticate
terminus auth:login --machine-token=TOKEN

# List sites
terminus site:list

# Site info
terminus site:info my-site

# Environment info
terminus env:info my-site.live

# Connection info (DB, Redis, SFTP)
terminus connection:info my-site.live

# Run Drush remotely
terminus drush my-site.live -- status
terminus drush my-site.live -- sql-dump --result-file=/tmp/dump.sql

# Create database backup
terminus backup:create my-site.live --element=db

# Download latest backup
terminus backup:get my-site.live --element=db --to=./live-db.sql.gz

# Clone content from Live to Dev
terminus env:clone-content my-site.live dev --db-only

# List multidev environments
terminus multidev:list my-site
```

### Drush Aliases

Pantheon generates Drush aliases via Terminus:

```bash
# Generate Drush aliases for all sites you can access
terminus aliases

# Generates: ~/.drush/pantheon.aliases.drushrc.php (Drush 8)
# Or: ~/.drush/sites/*.site.yml (Drush 9+)

# Use aliases
drush @pantheon.my-site.live status
drush @pantheon.my-site.dev sql-dump
```

### Multisite on Pantheon

Pantheon has limited multisite support. It is not a standard offering. Most Pantheon sites are single-site installs. If you encounter a Pantheon multisite, treat each site independently using `terminus drush` with the appropriate `--uri` flag.

### Migration Approach

1. Use `terminus site:list` to identify all Drupal sites on the account.
2. For each site, pull database and files using `terminus backup:create` and `terminus backup:get`.
3. Or use `terminus drush` to run remote exports.
4. Pantheon stores config in Git. Clone the repository to get the config sync directory.
5. Connection mode matters: if SFTP mode has uncommitted changes, commit them first or they will be lost.

```bash
# Bulk export from Pantheon
for site in $(terminus site:list --format=list --field=name); do
  echo "=== $site ==="
  terminus backup:create "$site.live" --element=db
  terminus backup:get "$site.live" --element=db --to="./exports/${site}-db.sql.gz"
  terminus backup:create "$site.live" --element=files
  terminus backup:get "$site.live" --element=files --to="./exports/${site}-files.tar.gz"
done
```

---

## Platform.sh / Upsun

Platform.sh (and its rebranded Upsun offering) uses a Git-driven, environment-branching model. Each Git branch becomes a full environment with its own services.

### Configuration Files

Three YAML files control the topology. They live in the repository:

```
.platform/
  routes.yaml        # Incoming routes and redirects
  services.yaml      # Backend services (MySQL, Redis, Solr, etc.)
.platform.app.yaml   # Application configuration (at repo root)
```

Example `.platform.app.yaml` for Drupal:

```yaml
name: 'drupal'
type: 'php:8.1'

relationships:
  database: 'db:mysql'
  redis: 'cache:redis'

disk: 2048

mounts:
  '/web/sites/default/files':
    source: local
    source_path: 'files'
  '/tmp':
    source: local
    source_path: 'tmp'
  '/private':
    source: local
    source_path: 'private'

build:
  flavor: composer

hooks:
  deploy: |
    set -e
    cd web
    drush updatedb -y
    drush cache:rebuild -y
    drush config:import -y

crons:
  drupal:
    spec: '*/19 * * * *'
    commands:
      start: 'cd web ; drush core-cron'
```

### Detection

```php
// In settings.php
if (getenv('PLATFORM_APPLICATION')) {
  // Running on Platform.sh
  $env = getenv('PLATFORM_ENVIRONMENT');  // branch name
  $project = getenv('PLATFORM_PROJECT'); // project ID
}
```

Key environment variables:

| Variable | Content |
|---|---|
| `PLATFORM_APPLICATION` | Base64-encoded JSON of `.platform.app.yaml` |
| `PLATFORM_ENVIRONMENT` | Branch/environment name |
| `PLATFORM_PROJECT` | Project ID |
| `PLATFORM_RELATIONSHIPS` | Base64-encoded JSON with service connection details |
| `PLATFORM_ROUTES` | Base64-encoded JSON of resolved routes |
| `PLATFORM_APP_DIR` | Absolute path to the app directory |
| `PLATFORM_TREE_ID` | Git tree SHA |

### Drush Aliases

Platform.sh uses a settings file (`settings.platformsh.php`) that auto-configures database connections from `PLATFORM_RELATIONSHIPS`. Drush aliases are generated by a helper script included in Platform.sh templates:

```bash
# On the server, inside the cli container
drush sa

# Typical aliases match environment names
drush @project.main status
drush @project.feature-branch status
```

### CLI

```bash
# Install Platform.sh CLI
curl -sS https://platform.sh/cli/installer | php

# List projects
platform project:list

# SSH into an environment
platform ssh -e main

# Get database connection info
platform relationships -e main

# Create database dump
platform db:dump -e main

# Download files
platform mount:download --mount web/sites/default/files -e main --target ./files
```

### Migration Approach

1. Use `platform project:list` to identify projects.
2. Each project is one Drupal site (unless using multi-app, which is uncommon).
3. Use `platform db:dump` to pull databases.
4. Use `platform mount:download` to pull uploaded files.
5. Clone the Git repo to get config and code.

---

## Lagoon (amazee.io)

Lagoon is a Docker-based hosting platform. Environments are defined by Docker Compose and a `.lagoon.yml` file.

### Configuration

```yaml
# .lagoon.yml (at repository root)
docker-compose-yaml: docker-compose.yml

tasks:
  post-rollout:
    - run:
        name: drush cim
        command: drush -y cim
        service: cli
    - run:
        name: drush updb
        command: drush -y updb
        service: cli
    - run:
        name: drush cr
        command: drush -y cr
        service: cli

environments:
  main:
    routes:
      - nginx:
        - example.com
        - "www.example.com":
            tls-acme: true
            insecure: Redirect
    cronjobs:
      - name: drush cron
        schedule: "*/15 * * * *"
        command: drush cron
        service: cli
```

The `docker-compose.yml` defines services (nginx, php, cli, mariadb, redis, solr). Lagoon reads `lagoon.type` labels on each service to determine deployment topology.

### Detection

```php
// In settings.php
if (getenv('LAGOON')) {
  // Running on Lagoon
  $env = getenv('LAGOON_ENVIRONMENT');       // environment name
  $env_type = getenv('LAGOON_ENVIRONMENT_TYPE'); // 'production' or 'development'
  $project = getenv('LAGOON_PROJECT');        // project name
  $branch = getenv('LAGOON_GIT_BRANCH');     // Git branch name
}
```

### Drush Aliases

Lagoon generates Drush aliases via a GraphQL API. For Drush 9+:

```bash
# Generate aliases inside the cli container
docker compose exec cli drush site:alias-convert /app/drush/sites --yes

# List aliases
drush sa --format=list

# Use aliases (prefixed with 'lagoon')
drush @lagoon.main ssh
drush @lagoon.main status

# Sync from remote
drush sql-sync @lagoon.main @self
drush rsync @lagoon.main:%files @self:%files -- --omit-dir-times --no-perms --no-group --no-owner --chmod=ugo=rwX
```

### Polysite

Lagoon supports "polysite": the same Git repository attached to multiple Lagoon projects. Each project gets isolated databases and file mounts but shares the codebase. Configure per-project routes in `.lagoon.yml`:

```yaml
# Polysite configuration
poly-project1:
  environments:
    main:
      routes:
        - nginx:
          - project1.com
poly-project2:
  environments:
    main:
      routes:
        - nginx:
          - project2.com
```

### Migration Approach

1. Check `.lagoon.yml` and `docker-compose.yml` for service topology.
2. SSH into the cli container: `drush @lagoon.main ssh`.
3. Run `drush sql-dump` from inside the container.
4. Use `drush rsync` to pull files.
5. Or sync locally: `drush sql-sync @lagoon.main @self`.
6. For polysite setups, treat each Lagoon project as a separate migration unit.

---

## Migration Scope Decisions for Multi-site

Regardless of the platform, multi-site migrations require answering these questions before writing a single export script.

### Content Sharing

| Situation | Action |
|---|---|
| Content exists once, visible on all sites (Domain Access "all affiliates") | Migrate once. Map to a shared content pool or pick one target. |
| Content tagged to specific domains | Split by domain. Each target gets its domain's content. |
| Content duplicated across separate databases (multisite/ACSF) | Each is independent. No deduplication needed. |
| Shared media library across sites | Migrate media once. Map references from all sites. |

### User Sharing

| Situation | Action |
|---|---|
| Single user table (Domain Access) | Migrate users once. Map domain assignments to roles or site memberships in the target. |
| Separate databases per site (multisite/ACSF) | Users exist per-site. Decide if the target needs a unified user base. Merge by email if so. |
| SSO in front of Drupal | Users may not need migration. The identity provider is the source of truth. |

### Domain Mapping

Document every old domain and its target:

```
old-domain.com         -> new-domain.com
sub.old-domain.com     -> sub.new-domain.com
factory-site.acsitefactory.com -> client-brand.com
```

Set up redirects from old domains to new domains after cutover.

### Phased Migration

For large deployments (50+ sites), migrate in waves:

1. Start with a low-traffic, low-complexity site as a pilot.
2. Validate the migration pipeline end-to-end on that site.
3. Migrate high-value sites next while lessons from the pilot are fresh.
4. Batch-migrate the remaining sites with automation.
5. Keep the old platform running in read-only mode during transition.

### Per-site Config Audit

Sites on the same codebase often differ in subtle ways:

```bash
# Compare enabled modules across multisite installs
for site in site_a site_b site_c; do
  drush --uri="$site" pm:list --status=enabled --field=name --format=list \
    | sort > "/tmp/modules_${site}.txt"
done
diff /tmp/modules_site_a.txt /tmp/modules_site_b.txt

# Compare config across ACSF sites
drush @factory.prod sfml config:export --destination=/tmp/config_export
# Then diff the config directories
```

Differences in enabled modules, content types, field definitions, and views will affect whether you can use a single migration template or need per-site variants.

---

## Platform Detection Cheat Sheet

Quick checks to identify the hosting platform from a codebase or running site:

| Check | Platform |
|---|---|
| `sites/sites.php` exists with `$sites` array | Drupal native multisite |
| `domain.record.*.yml` in config | Domain Access module |
| `acsf.settings.php` or `gardens_site_data_load_file()` | Acquia Site Factory |
| `$_ENV['PANTHEON_ENVIRONMENT']` in settings.php | Pantheon |
| `$_ENV['PLATFORM_APPLICATION']` in settings.php | Platform.sh / Upsun |
| `.lagoon.yml` at repo root | Lagoon (amazee.io) |
| `.platform.app.yaml` at repo root | Platform.sh |
| `pantheon.yml` at repo root | Pantheon |
| `$_ENV['AH_SITE_GROUP']` in settings.php | Acquia Cloud / ACSF |

```bash
# Automated detection from a codebase
detect_platform() {
  [ -f ".lagoon.yml" ] && echo "lagoon" && return
  [ -f ".platform.app.yaml" ] && echo "platformsh" && return
  [ -f "pantheon.yml" ] && echo "pantheon" && return
  grep -rql "gardens_site_data\|acsf" sites/default/settings.php 2>/dev/null && echo "acsf" && return
  grep -rql "PANTHEON_ENVIRONMENT" sites/default/settings.php 2>/dev/null && echo "pantheon" && return
  grep -rql "PLATFORM_APPLICATION" sites/default/settings.php 2>/dev/null && echo "platformsh" && return
  grep -rql "LAGOON" sites/default/settings.php 2>/dev/null && echo "lagoon" && return
  [ -f "sites/sites.php" ] && echo "multisite" && return
  ls sites/*/settings.php 2>/dev/null | wc -l | grep -q "[2-9]" && echo "multisite" && return
  drush pm:list --status=enabled --field=name 2>/dev/null | grep -q "^domain$" && echo "domain_access" && return
  echo "standalone"
}
detect_platform
```

---

## Common Pitfalls

- **Missing sites in inventory.** Always check `sites/sites.php` AND scan for `sites/*/settings.php`. Some sites may not be in the mapping file.
- **Shared vs. separate users.** Domain Access shares users. Multisite and ACSF do not. Plan user migration differently for each.
- **Config drift across sites.** Two ACSF sites on the same codebase can have different enabled modules via config splits. Export and diff per-site config.
- **File paths.** Each site has its own files directory. Public file URLs include the site path. Update file references during migration.
- **ACSF API pagination.** The sites endpoint returns max 100 results per page. Paginate until the response is empty.
- **Drush URI requirement.** In multisite setups, every Drush command needs `--uri=` or a site alias. Without it, Drush defaults to `sites/default`.
- **Lagoon polysite confusion.** Same Git repo, different Lagoon projects. They look identical in code but have separate databases. Track by project name, not repo URL.
