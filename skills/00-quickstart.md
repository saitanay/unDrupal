# Skill 0: Quickstart Decision Tree

You are guiding a user through a migration OFF Drupal. Your job: figure out their situation, then tell them which skills to run and in what order.

Do not assume anything. Ask. The answers determine everything downstream.

---

## Step 1: Gather the Facts

Walk the user through these seven questions. Ask them one group at a time. Wait for answers before moving on.

### Q1: What access do you have to the Drupal site?

Present these options. The user may have more than one.

| Access Level | What It Means | How to Confirm |
|---|---|---|
| **Drush (shell)** | SSH or local terminal access to the Drupal codebase with Drush installed | Run `drush status` and get output |
| **Database** | Direct connection to the MySQL/MariaDB/PostgreSQL database | Can run `SELECT * FROM node LIMIT 1` or equivalent |
| **JSON:API** | HTTP access to `/jsonapi` endpoints (D8.7+ with JSON:API module enabled) | Visit `https://site.example/jsonapi` and get a response |
| **Config files** | Access to exported YAML config (from `drush config:export` or a repo) | Have a `/config/sync` directory with `.yml` files |
| **Admin UI** | Can log into `/admin` but have no shell, DB, or API access | Can see content types at `/admin/structure/types` |
| **Public URL only** | No backend access at all. Can only visit the public site | This is the worst case. Some data is still recoverable. |

Record their access level. This determines which scripts and extraction methods each skill will use.

### Q2: What Drupal version is the source site?

| Version | Key Differences for Migration |
|---|---|
| **Drupal 7** | No config management system. Entity/field data stored in per-field tables (`field_data_field_*`, `field_revision_field_*`). Modules tracked in `system` table. No JSON:API without contrib. No paragraphs core support (uses `field_collection` or `paragraphs` contrib). No media entities without contrib. |
| **Drupal 8** | Config management via YAML. Entity/field storage in `node__field_*` tables. JSON:API available as contrib (core in 8.7+). Paragraphs via contrib. Media entities via contrib then core. |
| **Drupal 9** | Same architecture as D8. JSON:API in core. Media in core. Paragraphs still contrib. Deprecated code removed from D8. |
| **Drupal 10** | Same architecture as D9. CKEditor 5 replaces CKEditor 4. Symfony 6. Olivero default theme. Claro admin theme. |
| **Drupal 11** | Same architecture as D10. PHP 8.3+. Symfony 7. Further deprecation cleanup. |

How to detect the version:
- Drush: `drush status` shows `Drupal version`
- Database (D7): `SELECT info FROM system WHERE name = 'system'` then parse the version from the serialized blob
- Database (D8+): `SELECT value FROM key_value WHERE collection = 'system.schema' AND name = 'system'`
- Admin UI: Check `/admin/reports/status`
- Public URL: Look for `<meta name="generator" content="Drupal 7">` or similar in page source. Check `/CHANGELOG.txt` or `/core/CHANGELOG.txt`.
- Config files: Look at `core.extension.yml` for the `core` compatibility key

### Q3: What is the migration target?

Get the specific platform. Common targets:

| Target Category | Examples |
|---|---|
| **Headless CMS + Frontend** | Sanity + Next.js, Contentful + Next.js, Strapi + Next.js, Payload CMS + Next.js, Directus + Nuxt, Storyblok + any framework |
| **Traditional CMS** | WordPress, Craft CMS, Statamic, Umbraco, Sitecore |
| **Static Site Generator** | Astro, Hugo, Eleventy (11ty), Gatsby, Jekyll |
| **Custom Application** | Next.js + own DB, Rails app, Laravel, Django, SvelteKit |
| **Another Drupal** | D7 to D10/D11 (this toolkit still helps with the audit and content export phases) |

If they don't know the target yet, that's fine. Run the discovery and audit skills first. The content model map (Skill 2) and module inventory (Skill 3) will inform the target decision.

### Q4: What is in scope?

| Scope | What It Includes |
|---|---|
| **Content only** | Nodes, taxonomy terms, media files, menu structures. No structural config recreation. |
| **Content + structure** | Everything above, plus: content type definitions, field schemas, Views query logic, text format config, image style definitions, roles/permissions, editorial workflows. The target platform gets rebuilt to match the source structure. |
| **Full migration** | Everything above, plus: URL aliases, redirects, SEO metadata, users with profiles, comments, webform definitions and submissions, revision history, commerce data, multilingual content and config translations. |

### Q5: Special concerns?

Check each that applies:

- [ ] **Multilingual**: Site has content translations, interface translations, or both
- [ ] **Commerce**: Drupal Commerce with products, orders, customer data, payment history
- [ ] **Large site**: More than 50,000 nodes, or more than 100GB of files
- [ ] **SEO critical**: Organic search is a primary traffic source. URL preservation and redirect mapping are high priority.
- [ ] **Paragraphs-heavy**: Content built with nested Paragraph entities (common in D8+). Adds extraction complexity.
- [ ] **Layout Builder**: Per-entity layout overrides (D8.6+). Layout data is stored differently from field data.
- [ ] **Custom entities**: Custom entity types from contrib or custom modules beyond nodes, terms, media, users
- [ ] **Webforms**: Webform module with form definitions and stored submissions
- [ ] **Revision history**: Need to preserve edit history, not only the current published version
- [ ] **Tight deadline**: Migration must happen before a specific date (D7 EOL was Jan 2025, security risk grows daily)

### Q6: What page builder does the site use?

Most Drupal 8+ sites use some form of structured page building beyond plain fields. The page builder determines how content is stored and how much work extraction requires.

| Page Builder | How to Detect | Migration Skill |
|---|---|---|
| **Paragraphs** (most common) | `paragraphs` module enabled. Content types have entity reference revision fields pointing to `paragraph` entities. Tables: `paragraphs_item`, `paragraphs_item_field_data` (D8+) or `paragraphs_item` (D7 contrib). | Skill 12: `12-paragraphs-deep.md` |
| **Layout Builder** | `layout_builder` core module enabled. Per-entity layout overrides stored in `inline_block_content` entities and `layout_builder__layout` field storage. | Skill 16: `16-blocks-layouts.md` |
| **Experience Builder (XB)** | Drupal 11+ only. `experience_builder` module enabled. Component-based page building with a different storage model than Layout Builder. | Skill 33: `33-experience-builder.md` |
| **Site Studio / Cohesion** (Acquia) | `cohesion` module enabled. Content stored as JSON layout canvases in custom tables. Acquia-specific. | Skill 34: `34-site-studio.md` |
| **Gutenberg** | `gutenberg` module enabled. Content stored as Gutenberg block markup in body fields, similar to WordPress block format. | Skill 35: `35-gutenberg-drupal.md` |
| **None / basic fields only** | No page builder module. Content types use plain field widgets (text, image, link, reference). | Skip page builder skills. |

Some sites combine page builders. A site might use Paragraphs for structured landing pages and Layout Builder for per-page layout overrides. Check for both.

### Q7: Is this a multisite or platform setup?

Multisite and platform setups affect discovery, export, and planning. A single-site migration is one run through the skills. A multisite migration is N runs with shared config analysis.

| Setup | How to Detect | Migration Skill |
|---|---|---|
| **Standard single site** | One codebase, one database, one domain. | No extra skill needed. |
| **Drupal multisite** | `sites/` directory contains multiple site directories (e.g., `sites/site-a`, `sites/site-b`). Each site has its own `settings.php` and database. Shared codebase. | Skill 36: `36-multisite-platform.md` |
| **Acquia Site Factory** | Acquia Cloud hosting with Site Factory. Sites managed through the ACSF admin UI. Each site has its own database but shares the codebase and a common "factory" config. | Skill 36: `36-multisite-platform.md` |
| **Domain Access** | Single database, single codebase. `domain` module enabled. Multiple domains served from one Drupal install with content assigned per domain. | Skill 36: `36-multisite-platform.md` |
| **Hosted platform** (Pantheon, Platform.sh, Lagoon) | Platform-specific config files in the repo root: `pantheon.yml`, `.platform.app.yaml`, `.lagoon.yml`. Deployment, cron, and environment config managed by the platform. | Skill 36: `36-multisite-platform.md` |

For multisite setups, run Skill 36 right after Skill 01 (Site Audit). It maps the sites, identifies shared vs. per-site config, and produces a per-site run plan for the remaining skills.

---

## Step 2: Determine the Access Method Priority

Each skill supports multiple access methods. Use the best one available.

### Access Method Capabilities by Drupal Version

| Access Method | D7 | D8 | D9 | D10 | D11 |
|---|---|---|---|---|---|
| **Drush** | Full (if Drush 8 installed) | Full | Full | Full | Full |
| **Database** | Full (different schema) | Full | Full | Full | Full |
| **JSON:API** | Only with `restws` or `services` contrib | Contrib, then core (8.7+) | Core | Core | Core |
| **Config files** | Not applicable (no CMI) | Full structure, no content | Full structure, no content | Full structure, no content | Full structure, no content |
| **Admin UI** | Manual, slow, error-prone | Manual, slow | Manual, slow | Manual, slow | Manual, slow |
| **Public URL** | Partial (scraping) | Partial | Partial | Partial | Partial |

### Priority Order

Use the highest available method. Fall back as needed.

1. **Drush** gives you everything: config export, database queries, entity dumps, file access. Prefer this when available.
2. **Database** gives you raw data and full schema discovery. Requires knowledge of Drupal's table structure (different between D7 and D8+). Second best for completeness.
3. **JSON:API** gives you structured content over HTTP. Good for content and media export. Cannot export config, Views, workflows, or permissions. Third choice.
4. **Config files** give you structure but no content. Useful when combined with another content source. Covers content types, fields, Views, text formats, image styles, workflows.
5. **Admin UI** works as a last resort for structure. Copy field definitions manually. Export Views via the UI. Slow, but possible for small sites.
6. **Public URL** is for when you have nothing else. Crawl the site. Identify content types from URL patterns and page structure. Extract visible content with a scraper. You lose all backend structure.

---

## Step 3: Select the Skill Execution Order

Use the answers from Steps 1 and 2 to build the run list.

### Core Skills (run these for every migration)

Run in this order. Each skill depends on the output of the ones before it.

| Order | Skill | File | Purpose |
|---|---|---|---|
| 1 | Site Audit | `01-site-audit.md` | Baseline: what exists, how much, what version |
| 1b | Multisite / Platform | `36-multisite-platform.md` | Map sites, shared config, per-site run plan. Run only if Q7 identified a multisite or platform setup. |
| 2 | Content Model Map | `02-content-model-map.md` | Every entity type, bundle, field, and relationship |
| 3 | Module Inventory | `03-module-inventory.md` | Classify every module's migration impact |

These three (plus 36 when applicable) produce the information needed to plan the rest.

### Structure Skills (run when scope includes structure)

| Order | Skill | File | When to Include |
|---|---|---|---|
| 4 | Content Types & Fields | `04-content-types-fields.md` | Always (if structure in scope) |
| 5 | Views Export | `05-views-export.md` | Site uses Views (almost every site does) |
| 6 | Display Modes | `06-display-modes.md` | Target needs to replicate display variants |
| 7 | Text Formats & Editors | `07-text-formats-editors.md` | Always (affects rich text migration) |
| 8 | Image Styles | `08-image-styles.md` | Site uses image styles or responsive images |
| 9 | Workflows & Moderation | `09-workflows-moderation.md` | Site uses Content Moderation or Workflows |
| 10 | Roles & Permissions | `10-roles-permissions.md` | Target needs user access control |

### Content Export Skills (run when scope includes content)

Run these after the structure skills. Order matters: export referenced entities before the entities that reference them.

| Order | Skill | File | When to Include |
|---|---|---|---|
| 11 | Taxonomy Export | `13-taxonomy-export.md` | Site uses taxonomy (almost always) |
| 12 | Media & Files | `14-media-files.md` | Site has images, documents, video |
| 13 | Users & Profiles | `17-users-profiles.md` | Users are in scope |
| 14 | Nodes / Content | `11-nodes-content.md` | Always |
| 15 | Paragraphs | `12-paragraphs-deep.md` | Site uses Paragraphs module |
| 15b | Experience Builder | `33-experience-builder.md` | Site uses Experience Builder (Drupal 11+ only) |
| 15c | Site Studio / Cohesion | `34-site-studio.md` | Site uses Site Studio (Acquia) |
| 15d | Gutenberg | `35-gutenberg-drupal.md` | Site uses Gutenberg module |
| 16 | Menus & Navigation | `15-menu-navigation.md` | Always |
| 17 | Blocks & Layouts | `16-blocks-layouts.md` | Site uses custom blocks or Layout Builder |
| 18 | Comments | `18-comments.md` | Site has comments enabled |
| 19 | Webforms | `19-webforms.md` | Site uses Webform module |

Note the ordering: Taxonomy and Media export before Nodes because nodes reference terms and media entities. Users export before Nodes because nodes have an author reference. Paragraphs export after Nodes because paragraph extraction often works as a post-processing step on node data.

Page builder skills (15, 15b, 15c, 15d) are mutually exclusive in most cases. Run the one that matches Q6. If a site uses multiple page builders, run each applicable skill in sequence.

### Specialized Skills (run based on Q5 answers)

| Skill | File | Trigger |
|---|---|---|
| URL Aliases & Redirects | `20-url-aliases-redirects.md` | SEO critical, or full migration scope |
| Metatags & SEO | `21-metatags-seo.md` | SEO critical |
| Multilingual | `22-multilingual.md` | Multilingual concern checked |
| Commerce | `23-commerce.md` | Commerce concern checked |
| Search Indexes | `24-search-indexes.md` | Site uses Search API / Solr |
| Custom Entities | `25-custom-entities.md` | Custom entities concern checked |
| Rich Text Cleanup | `26-rich-text-cleanup.md` | Always recommended. Drupal rich text contains embedded media tokens, linkit references, and entity embeds that need conversion. |
| Revision History | `27-revision-history.md` | Revision history concern checked |
| Scheduled Content | `28-scheduled-content.md` | Site uses Scheduler module |
| Flags & Bookmarks | `29-flags-bookmarks.md` | Site uses Flag module |

### Synthesis Skills (run last)

| Order | Skill | File | Purpose |
|---|---|---|---|
| Last - 2 | Content Inventory | `32-content-inventory.md` | Generate the full inventory spreadsheet |
| Last - 1 | Migration Plan | `30-migration-plan.md` | Produce the migration plan document |
| Last | Validation Checklist | `31-validation-checklist.md` | Post-migration verification steps |

---

## Step 4: Quick-Start Paths

These are pre-built run lists for common scenarios. Use them as starting points. Adjust based on the user's actual answers.

### Path A: "D7 site, want to go to Next.js + Sanity, have Drush access"

Drupal 7 has a different database schema and no config management. Drush access makes this straightforward.

```
Run order:
1. 01-site-audit.md          (Drush + DB mode, D7 schema)
2. 02-content-model-map.md   (D7 field tables: field_data_field_*, field_revision_field_*)
3. 03-module-inventory.md    (check for paragraphs, field_collection, media/file handling)
4. 04-content-types-fields.md (no YAML config in D7; extract from DB or drush)
5. 07-text-formats-editors.md (D7 text formats stored differently)
6. 13-taxonomy-export.md
7. 14-media-files.md          (D7 uses file_managed, no media entities unless contrib)
8. 11-nodes-content.md        (D7 node export via drush or DB)
9. 15-menu-navigation.md
10. 20-url-aliases-redirects.md
11. 26-rich-text-cleanup.md   (D7 rich text may have inline file references, not entity embeds)
12. 30-migration-plan.md      (include Sanity schema generation from content model)
13. 31-validation-checklist.md
```

D7-specific watch items:
- No UUID on entities unless the `uuid` contrib module was enabled. Plan for ID remapping.
- File fields store file references directly. No media entity layer.
- `field_collection` items (if used) are the D7 precursor to Paragraphs. Different storage tables.
- Rich text embeds use `[[nid:123]]` tokens or `<img>` tags with direct file paths, not `<drupal-media>` tags.
- No revision moderation without `workbench_moderation` contrib.

### Path B: "D10 site, want to go to WordPress, have database access only"

D10 uses the modern entity/field storage schema. Database access covers both structure and content.

```
Run order:
1. 01-site-audit.md          (DB mode)
2. 02-content-model-map.md   (node__field_* tables, config tables)
3. 03-module-inventory.md    (query key_value for enabled modules)
4. 04-content-types-fields.md
5. 05-views-export.md        (export Views config from config table)
6. 07-text-formats-editors.md
7. 08-image-styles.md
8. 10-roles-permissions.md
9. 13-taxonomy-export.md
10. 14-media-files.md
11. 17-users-profiles.md
12. 11-nodes-content.md
13. 12-paragraphs-deep.md    (if Paragraphs module is present)
14. 15-menu-navigation.md
15. 16-blocks-layouts.md
16. 18-comments.md           (if comments exist)
17. 20-url-aliases-redirects.md
18. 21-metatags-seo.md
19. 26-rich-text-cleanup.md
20. 32-content-inventory.md
21. 30-migration-plan.md     (include WP import mapping)
22. 31-validation-checklist.md
```

WordPress-specific considerations:
- WordPress has a flat content model (posts and pages). Drupal content types map to WP post types or custom post types via a plugin like ACF or Pods.
- Drupal Paragraphs have no native WP equivalent. Options: flatten to HTML, convert to Gutenberg blocks, or use ACF Flexible Content fields.
- Drupal taxonomy vocabularies map to WP taxonomies, but WP has only two built-in (categories and tags). Register custom taxonomies for the rest.
- Drupal media entities need conversion to WP media library entries. File paths change.
- Drupal roles/permissions are more granular than WP. Expect lossy mapping.

### Path C: "D9 site, going headless with Astro + Markdown files, have JSON:API"

JSON:API gives structured content over HTTP. Good for content export. Config must be inferred or obtained separately.

```
Run order:
1. 01-site-audit.md          (JSON:API mode: discover resource types, count entities)
2. 02-content-model-map.md   (infer from JSON:API resource schemas and relationships)
3. 03-module-inventory.md    (limited: can detect entity types but not all modules)
4. 13-taxonomy-export.md     (JSON:API: /jsonapi/taxonomy_term/{vocabulary})
5. 14-media-files.md         (JSON:API: /jsonapi/media/{bundle}, download file URLs)
6. 11-nodes-content.md       (JSON:API: /jsonapi/node/{type}, paginate with page[offset])
7. 12-paragraphs-deep.md     (JSON:API: include nested paragraphs with ?include= param)
8. 15-menu-navigation.md     (JSON:API: /jsonapi/menu_link_content/{menu})
9. 26-rich-text-cleanup.md   (process extracted body HTML)
10. 30-migration-plan.md     (Astro: convert to Markdown + frontmatter content collections)
11. 31-validation-checklist.md
```

Astro/Markdown-specific considerations:
- Each node becomes a Markdown (or MDX) file with YAML frontmatter for fields.
- Paragraphs need to be flattened into the Markdown body or converted to MDX components.
- Taxonomy terms become frontmatter arrays or collection references.
- Media files download to a local `/public/` or `/src/assets/` directory. Update references.
- URL aliases become file paths or route overrides in `astro.config.mjs`.
- No dynamic content. Views-based listings become static collection queries in Astro templates.

### Path D: "D10, going to Contentful, have Drush, multilingual site"

Full access, multilingual. This is a complex migration.

```
Run order:
1. 01-site-audit.md
2. 02-content-model-map.md
3. 03-module-inventory.md
4. 04-content-types-fields.md  (Contentful content model must be designed from this)
5. 07-text-formats-editors.md
6. 08-image-styles.md
7. 09-workflows-moderation.md  (map to Contentful workflows if on Enterprise plan)
8. 10-roles-permissions.md
9. 22-multilingual.md          (run early: affects every content export skill)
10. 13-taxonomy-export.md      (with translations)
11. 14-media-files.md          (with translations, upload to Contentful asset API)
12. 17-users-profiles.md
13. 11-nodes-content.md        (with translations per locale)
14. 12-paragraphs-deep.md      (map to Contentful linked entries or rich text embeds)
15. 15-menu-navigation.md
16. 20-url-aliases-redirects.md
17. 21-metatags-seo.md
18. 26-rich-text-cleanup.md    (convert to Contentful Rich Text JSON format)
19. 32-content-inventory.md
20. 30-migration-plan.md
21. 31-validation-checklist.md
```

Contentful-specific considerations:
- Contentful has a 50,000-entry limit on the free/Team plans. Count total entities (nodes + terms + media + paragraphs) before starting.
- Paragraphs can map to linked entries (referenced content types) or embedded entries within Rich Text fields. Decide per paragraph type.
- Contentful Rich Text is a JSON AST, not HTML. The `26-rich-text-cleanup.md` output needs further conversion.
- Contentful locales must be created before importing translations. Map Drupal language codes to Contentful locale codes.
- Contentful has no built-in URL alias system. Store aliases as a field on each entry and handle routing in the frontend.
- Contentful media (Assets) are separate from entries. Upload files first, get asset IDs, then link from entries.

### Path E: "Have nothing but a URL. Site might go down soon."

Emergency extraction. Grab what you can.

```
Run order:
1. 01-site-audit.md          (Public URL mode: crawl, detect version from page source)
2. Crawl the entire site with wget, httrack, or a custom scraper
3. 02-content-model-map.md   (infer content types from URL patterns and page structure)
4. 14-media-files.md         (download all linked images, PDFs, files from crawl)
5. 11-nodes-content.md       (extract content from crawled HTML pages)
6. 15-menu-navigation.md     (extract nav structure from crawled HTML)
7. 20-url-aliases-redirects.md (the crawled URLs become the redirect source list)
8. 26-rich-text-cleanup.md   (clean scraped HTML)
9. 30-migration-plan.md
```

You will lose:
- Unpublished content and drafts
- Revision history
- Backend field structure (everything becomes scraped HTML)
- Taxonomy structure (unless visible in the frontend)
- User data
- File metadata
- Paragraph structure (flattened into page HTML)
- Webform definitions and submissions
- Comments (unless rendered on the page)
- Any content behind login walls

Prioritize getting better access. Ask the user: Can you contact the hosting provider? Can you get a database dump? Can you get someone with admin access to install JSON:API and expose endpoints? Even partial backend access changes the outcome.

### Path F: "Acquia-hosted D10, Site Studio for page building, multiple sites on Site Factory"

Acquia sites often use Site Studio (Cohesion) for visual page building and Site Factory for multisite management. Both add extraction complexity.

```
Run order:
1. 01-site-audit.md
2. 36-multisite-platform.md   (map all Site Factory sites, identify shared vs. per-site config)
3. 02-content-model-map.md    (run per site if schemas differ)
4. 03-module-inventory.md
5. 04-content-types-fields.md
6. 05-views-export.md
7. 07-text-formats-editors.md
8. 08-image-styles.md
9. 10-roles-permissions.md
10. 13-taxonomy-export.md
11. 14-media-files.md
12. 17-users-profiles.md
13. 11-nodes-content.md
14. 34-site-studio.md          (extract Site Studio layout canvases and component configs)
15. 15-menu-navigation.md
16. 16-blocks-layouts.md
17. 20-url-aliases-redirects.md
18. 21-metatags-seo.md
19. 26-rich-text-cleanup.md
20. 32-content-inventory.md
21. 30-migration-plan.md
22. 31-validation-checklist.md
```

Acquia / Site Studio considerations:
- Site Studio stores layouts as JSON canvas data, not as Drupal fields or Layout Builder sections. The `34-site-studio.md` skill parses these canvases and maps components to target-platform equivalents.
- Site Factory sites share a codebase but can have per-site config overrides. Skill 36 identifies which config is shared and which diverges.
- Acquia Cloud environments (dev/stage/prod) may have different content. Export from production.
- Site Studio component templates are config entities. Export them alongside content for full reconstruction.
- If the target is not Acquia, every Site Studio component needs a mapping to the target's content model. Budget time for this.

---

## Pitfalls That Should Change Your Skill Order

These conditions, discovered during the audit phase, affect how you run later skills.

### Entity Reference Integrity

Drupal sites accumulate broken entity references over time: fields pointing to deleted nodes, orphaned paragraph entities, taxonomy terms that changed meaning. Run `02-content-model-map.md` with reference validation enabled. Broken references cause failures during import into the target platform if not caught during export.

### Paragraph Nesting Depth

Sites built with Paragraphs often have 3-5 levels of nesting. A "Page" node contains a "Section" paragraph, which contains a "Columns" paragraph, which contains a "Card" paragraph, which contains an "Image + Text" paragraph. Each level is a separate entity with its own fields. The `12-paragraphs-deep.md` skill handles recursive resolution. If the audit reveals deep nesting, budget extra time for this skill and for designing the target content model.

### Rich Text Embedded Media

Drupal 8+ uses `<drupal-media>` tags in rich text to embed media entities. Drupal 7 uses a mix of `[[nid:123]]` tokens, `[inline:filename.jpg]` tags, or raw `<img src="/sites/default/files/...">` paths. The `26-rich-text-cleanup.md` skill must run after media export (`14-media-files.md`) because it needs the media ID-to-URL mapping to rewrite references.

### URL Aliases and SEO Dependency

If the site depends on organic search traffic, treat `20-url-aliases-redirects.md` and `21-metatags-seo.md` as required skills, not optional. Generate a complete redirect map from old Drupal paths to new target URLs. Missing redirects after a migration cause traffic drops that can take months to recover.

### Commerce Data Sensitivity

Commerce migrations involve customer PII, payment records, and order history. Handle `23-commerce.md` output with appropriate data protection. Decide early whether to migrate order history or start fresh on the target platform. Most targets (Shopify, WooCommerce, custom) have their own order management and may not need historical orders.

### Multilingual Ordering

When the multilingual concern applies, the `22-multilingual.md` skill must run before any content export skill. It determines: which languages exist, which content types have translations, whether translations are stored as separate nodes (D7 pattern) or as entity translations (D8+ pattern), and whether config translations exist. Every subsequent content export skill changes behavior based on this information.
