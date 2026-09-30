# Skill 30: Full Migration Plan

Synthesize outputs from all previous skills into a single migration plan document. This plan is the deliverable that stakeholders, developers, and project managers use to scope, schedule, and execute the migration off Drupal.

Run this skill last, after completing the discovery, configuration export, content export, and specialized export skills. The more skills you have run, the more complete the plan. The skill works with partial data but will flag gaps.

---

## Prerequisites

Outputs from earlier skills. Check for these files in the project directory:

| Skill | Expected Output File(s) | Required? |
|---|---|---|
| 01 Site Audit | `site-audit.json` or `site-audit.md` | Yes |
| 02 Content Model Map | `content-model.json` | Yes |
| 03 Module Inventory | `module-inventory.json` or `module-inventory.md` | Yes |
| 04 Content Types & Fields | `content-types.json` | Recommended |
| 05 Views Export | `views-export.json` | Recommended |
| 06 Display Modes | `display-modes.json` | Optional |
| 07 Text Formats | `text-formats.json` | Recommended |
| 08 Image Styles | `image-styles.json` | Optional |
| 09 Workflows | `workflows.json` | If workflows exist |
| 10 Roles & Permissions | `roles-permissions.json` | If users in scope |
| 11 Nodes | `nodes/` directory or `nodes-export.json` | Recommended |
| 12 Paragraphs | `paragraphs.json` or `paragraphs/` directory | If paragraphs exist |
| 13 Taxonomy | `taxonomy.json` | Recommended |
| 14 Media & Files | `media-manifest.json`, `files/` | Recommended |
| 15 Menus | `menus.json` | Optional |
| 16 Blocks & Layouts | `blocks.json`, `layouts.json` | If Layout Builder exists |
| 17 Users | `users.json` | If users in scope |
| 18 Comments | `comments.json` | If comments exist |
| 19 Webforms | `webforms.json` | If webforms exist |
| 20 URL Aliases & Redirects | `path-aliases.json`, `redirects.json` | Recommended |
| 21 Metatags & SEO | `metatags.json` | If SEO in scope |
| 22 Multilingual | `translations.json` | If multilingual |
| 23 Commerce | `commerce-export.json` | If commerce exists |
| 24 Search Indexes | `search-indexes.json` | If Search API exists |
| 25 Custom Entities | `custom-entities.json` | If custom entities exist |
| 26 Rich Text Cleanup | `rich-text-report.json` | Recommended |
| 27 Revision History | `revisions.json` | If revisions in scope |
| 28 Scheduled Content | `scheduled-content.json` | If Scheduler exists |
| 29 Flags & Bookmarks | `flagging-export.json` | If Flag module exists |

Search the project directory for these files. Also check for variant names (`.csv`, `.tsv`, different prefixes). Look in subdirectories. Some skills write to `exports/` or `output/` folders.

If a required file is missing, stop and tell the user which skills to run first.

If a recommended file is missing, continue but add it to the gaps section of the plan.

---

## Step 1: Gather Site Metrics

Pull these numbers from the skill outputs. These feed the executive summary and effort estimate.

### From Skill 01 (Site Audit)

| Metric | Where to Find It |
|---|---|
| Drupal version | `site-audit.json` → `drupal_version` |
| Total nodes | Sum of all content type counts |
| Total taxonomy terms | Sum of all vocabulary counts |
| Total media entities | Sum of all media bundle counts |
| Total users | User count |
| Total paragraphs | Paragraph entity count (0 if no Paragraphs module) |
| Database size | `database_size_mb` |
| Files directory size | `files_size_mb` or `files_size_gb` |
| Number of enabled modules | Count of enabled modules |
| Number of content types | Count of node bundles |

### From Skill 03 (Module Inventory)

| Metric | Where to Find It |
|---|---|
| Tier 1 modules (high impact) | Count of modules classified as high migration impact |
| Tier 2 modules (medium impact) | Count of modules classified as medium migration impact |
| Custom modules | Count of modules under `modules/custom` |
| Contrib modules | Count of contrib modules |

### Compute the Complexity Score

Score the site on a 1-10 scale. Add points for each factor present:

| Factor | Points | How to Detect |
|---|---|---|
| Paragraphs module enabled | +2 | Module inventory or `paragraphs_item_field_data` table exists |
| Max paragraph nesting depth > 2 | +1 | Skill 12 output, trace deepest entity_reference_revisions chain |
| Layout Builder in use | +2 | `layout_builder` module enabled and `node__layout_builder__layout` table has rows |
| Multilingual (2+ languages) | +2 | Skill 22 output or `language.entity.*.yml` config count > 1 |
| Commerce module enabled | +2 | `commerce` in module list |
| Custom entity types | +1 per type | Skill 25 output |
| More than 50,000 nodes | +1 | Node count from audit |
| More than 15 content types | +1 | Content type count from audit |
| Webforms with submissions | +1 | Skill 19 output, submission count > 0 |
| Content moderation workflows | +1 | Skill 09 output |
| More than 50 Views | +1 | Skill 05 output, count of View configs |
| Custom field types from contrib | +1 | Module inventory, modules that register FieldType plugins |
| Embedded media tokens in rich text | +1 | Skill 26 output, count of `<drupal-media>` or `[[nid:*]]` occurrences |
| 100+ redirects | +1 | Skill 20 output, redirect count |

**Score interpretation:**

| Score | Label | Meaning |
|---|---|---|
| 1-3 | Low | Brochure site. Flat content, few modules. One developer, 2-4 weeks. |
| 4-6 | Medium | Business site. Paragraphs or moderate customization. 2-3 developers, 1-3 months. |
| 7-9 | High | Enterprise site. Nested paragraphs, multilingual, commerce, or Layout Builder. 3-5 developers, 3-6 months. |
| 10+ | Very High | Complex enterprise. Multiple high-complexity factors stacked. Dedicated team, 6-12 months. Expect surprises. |

---

## Step 2: Build the Content Model Mapping Table

For every entity type and bundle in `content-model.json`, create a row mapping the Drupal source to the target platform.

### Node Content Types

For each content type in the source, determine the target equivalent based on the chosen platform.

**Generate a table with these columns:**

| Drupal Content Type | Node Count | Fields | Paragraphs? | Target Entity/Type | Migration Method | Notes |
|---|---|---|---|---|---|---|
| `article` | 2,340 | 12 | No | (target-specific) | (method) | (any special handling) |
| `landing_page` | 87 | 4 + paragraphs | Yes (3 levels deep) | (target-specific) | (method) | Paragraph flattening required |

Fill in the "Target Entity/Type" column based on the migration target:

| Target Platform | How Drupal Content Types Map |
|---|---|
| **WordPress** | Custom Post Types (one per Drupal content type). Simple types like `article` and `page` map to native WP posts and pages. |
| **Sanity** | Document types in the Sanity schema. Each content type becomes a document type. Paragraphs become array items or Portable Text blocks. |
| **Contentful** | Content Types. 1:1 mapping. Paragraphs become embedded entries or rich text. |
| **Strapi** | Collection Types. 1:1 mapping. Paragraphs map to Dynamic Zones or components. |
| **Payload CMS** | Collections. 1:1 mapping. Paragraphs become Blocks fields. |
| **Next.js (custom)** | Database tables or collections in your chosen data store. Define schemas per content type. |
| **Hugo / Astro / 11ty** | Markdown files in content directories. One directory per content type. Fields become front matter. Rich text becomes markdown body. |
| **Craft CMS** | Sections + Entry Types. Content types become entry types within sections. Paragraphs map to Matrix fields. |
| **Statamic** | Collections. Content types become collections. Paragraphs map to Replicator or Bard sets. |

Fill in "Migration Method" with one of:

| Method | When to Use |
|---|---|
| Direct field mapping | Fields have 1:1 equivalents in the target |
| Transform + map | Fields need type conversion (e.g., Drupal entity_reference to target relation) |
| Flatten paragraphs to HTML | Target has no structured component system. Render paragraphs to HTML and store as rich text. |
| Convert to components | Target supports structured components (Sanity blocks, Strapi dynamic zones, Payload blocks). Map each paragraph type to a component. |
| Manual rebuild | No automated path. Rebuild in the target by hand. |
| Skip | Content type is obsolete, empty, or out of scope |

### Taxonomy Vocabularies

| Drupal Vocabulary | Term Count | Hierarchical? | Target Equivalent |
|---|---|---|---|
| `tags` | 450 | No | (platform-specific taxonomy) |
| `categories` | 23 | Yes (3 levels) | (platform-specific taxonomy) |

### Media Types

| Drupal Media Bundle | Count | Target Equivalent |
|---|---|---|
| `image` | 5,200 | Target media library / asset manager |
| `document` | 340 | File storage in target |
| `remote_video` | 18 | Video embed field or URL field |

### Other Entity Types

Include paragraph types, block types, webform definitions, commerce product types, and any custom entity types from Skills 12, 16, 19, 23, 25.

---

## Step 3: Define the Data Migration Sequence

Order matters. Entities that are referenced by other entities must migrate first. If you migrate nodes before taxonomy terms, term references on nodes will point to nothing.

### Standard Migration Order

Execute in this sequence. Each phase completes before the next begins.

| Phase | What Migrates | Why This Order | Depends On |
|---|---|---|---|
| 1 | Taxonomy terms (all vocabularies) | Referenced by nodes, media, paragraphs, menus. Must exist first. | Nothing |
| 2 | Media entities and files | Referenced by nodes, paragraphs, blocks. File downloads can run in parallel with term migration. | Phase 1 (terms referenced in media alt text or metadata fields) |
| 3 | Users and roles | Nodes have author references. Comments have author references. Must exist before content. | Nothing (can run parallel with Phase 1-2) |
| 4 | Nodes by content type (simplest first) | Core content. Order by complexity: types without paragraphs first, types with paragraphs last. | Phases 1-3 |
| 5 | Paragraphs (if not inlined during Phase 4) | Attached to nodes. If paragraphs were resolved during node export (Skill 12), this phase is already done. Otherwise, resolve and attach now. | Phase 4 |
| 6 | Comments | Threaded, attached to nodes. Nodes must exist so comment parent references resolve. | Phase 4 |
| 7 | Menus and menu links | Menu links reference nodes, taxonomy terms, and external URLs. Nodes and terms must exist. | Phases 1, 4 |
| 8 | Block content and placements | Blocks may reference nodes, terms, media. Some blocks appear in Layout Builder layouts on nodes. | Phases 1-4 |
| 9 | Path aliases | Map internal paths to clean URLs. Nodes, terms, and users must exist so internal paths resolve. | Phases 1-4 |
| 10 | Redirects | Map old paths to new paths. Path aliases must be set first so redirect targets resolve. | Phase 9 |
| 11 | Webform definitions and submissions | Forms may reference nodes (via webform entity reference fields). Submissions are standalone but need the form definition. | Phase 4 (if forms attached to nodes) |
| 12 | Commerce (products, variations, orders) | Products reference media, taxonomy, and users. Orders reference users and products. | Phases 1-3 |

### Phase 4 Detail: Node Migration Sub-Order

Within Phase 4, migrate content types in this order:

1. Content types with no entity references to other node types (standalone types like `page`, `article`)
2. Content types that reference types from step 1 (e.g., `case_study` referencing `article`)
3. Content types with paragraphs but no inter-node references
4. Content types with both paragraphs and inter-node references
5. Content types with Layout Builder overrides (most complex)

Build this sub-order from the content model map. Trace `entity_reference` fields where `target_type` is `node` and the `target_bundles` setting limits to specific content types. That gives you the dependency graph.

---

## Step 4: Feature Parity Analysis

For each Drupal feature, document what it becomes in the target platform. This is the section stakeholders read to understand what changes.

### Views

For every View exported by Skill 05, determine the target equivalent.

| View ID | Display Type | What It Does | Target Equivalent | Notes |
|---|---|---|---|---|
| `content_recent` | Page | Lists 20 recent articles, filtered by published status, sorted by created date | (platform query) | |
| `frontpage` | Page | Homepage listing with promoted content | (platform homepage query or static build) | |
| `taxonomy_term` | Page | Lists content tagged with a term | (platform taxonomy page or filtered query) | |
| `media_library` | Page + Block | Admin media browser | Target CMS media library (built-in) | No migration needed |

**Target platform patterns:**

| Drupal View Feature | WordPress | Next.js + Headless | Hugo / Astro | Strapi / Payload |
|---|---|---|---|---|
| Page display with path | Custom page template + `WP_Query` | Route + API query | List template on section | Custom API endpoint or built-in list |
| Block display | Widget or shortcode | Component with data fetch | Partial template | Component with API call |
| Exposed filters | URL query parameters + form | Client-side filter UI + API params | Not native (JS required) | API filter parameters |
| Contextual filters | URL arguments in template | Route parameters | Taxonomy template variables | API path parameters |
| Pager | `paginate_links()` | Client or server pagination | Hugo pagination | API pagination (limit/offset) |
| Sort criteria | `orderby` in query | API sort parameter | Front matter sort in template | API sort parameter |
| Relationships | `JOIN` via `WP_Query` meta | Populate/expand in API | Data file references | Populate/relation in API |
| Aggregation | Custom SQL or plugin | Custom aggregation query | Not native | Custom controller or raw query |
| REST export | WP REST API endpoint | Already headless | JSON output template | Already an API |

### Paragraphs

For each paragraph type from Skill 12:

| Paragraph Type | Fields | Target Component | Conversion Method |
|---|---|---|---|
| `hero_banner` | title, subtitle, background_image, cta_link | (target component) | Field-by-field mapping |
| `card_group` | heading, cards (nested paragraph) | (target component with children) | Recursive conversion |
| `text_block` | body (formatted text) | Rich text field or markdown | HTML to target format |

### Workflows

| Drupal Workflow | States | Target Equivalent |
|---|---|---|
| Editorial | Draft, In Review, Published, Archived | (target draft/publish system) |

Map each state to the closest target equivalent. Note where the target has fewer states. Content in intermediate states (like "In Review") will need a decision: migrate as draft, or migrate as published.

### Search

| Drupal Search Config | Index | Target Equivalent |
|---|---|---|
| Search API + Solr | `default_solr_index` indexing nodes, terms | (target search: Algolia, Meilisearch, Typesense, Pagefind) |

### Webforms

| Webform ID | Fields | Submissions | Target Equivalent |
|---|---|---|---|
| `contact` | name, email, message | 1,200 | (target form solution) |

For each form: note whether submissions must migrate (historical data) or only the form definition.

---

## Step 5: URL Migration Strategy

This section prevents SEO damage. Every URL that received traffic on the Drupal site must either work on the new site or redirect to the correct new URL.

### Three-Part URL Plan

**Part 1: Alias Preservation**

From Skill 20 output, count total aliases. For each alias:

1. If the new site uses the same URL path, no action needed. Map it in the routing config.
2. If the new site changes the URL structure, generate a 301 redirect from the old alias to the new path.
3. If the content is removed in migration, generate a 301 redirect to the closest replacement page, or a 410 (Gone) if no replacement exists.

Generate a table:

| Old Alias | Entity | New URL | Action |
|---|---|---|---|
| `/blog/my-post` | node/42 (article) | `/blog/my-post` | Preserve (same path) |
| `/about/team` | node/15 (page) | `/about/our-team` | 301 redirect |
| `/old-promo` | node/99 (promo, deleted) | `/` | 301 to homepage or 410 |

**Part 2: Redirect Preservation**

Existing redirects from the `redirect` module (Skill 20 output) must carry forward. Export them as a redirect map in the format the target platform consumes:

| Target Platform | Redirect Format |
|---|---|
| WordPress | Redirection plugin import CSV, or `.htaccess` rules |
| Next.js | `next.config.js` `redirects` array, or `_redirects` file for Netlify/Vercel |
| Hugo | Netlify `_redirects` or server config |
| Astro | `_redirects` file or middleware |
| Nginx | `rewrite` or `return 301` directives |
| Apache | `.htaccess` `Redirect` or `RewriteRule` directives |
| Cloudflare | Bulk redirect rules or Page Rules |

**Part 3: SEO Impact Analysis**

Flag high-risk URL changes:

- Pages with the most inbound links (check analytics or backlink data if available)
- Pages ranking for target keywords
- Pages with structured data or rich snippets
- Sitemaps: the new site must generate a sitemap and submit it to Google Search Console

Recommend a crawl of the old site with a tool like Screaming Frog or `wget --spider` before migration to capture the full URL inventory. Compare against post-migration URLs to find gaps.

---

## Step 6: Risk Register

Rank risks by impact and likelihood. Pull risk factors from skill outputs.

### Risk Assessment Table

| Risk | Likelihood | Impact | Mitigation | Detected By |
|---|---|---|---|---|
| Nested paragraphs lose structure during flattening | High (if paragraphs > 2 levels) | High: content layout breaks | Build recursive converter. Test with deepest nesting examples first. | Skill 12 max depth |
| Embedded media tokens in rich text not converted | High (if `<drupal-media>` tags found) | High: broken images and embeds in migrated content | Skill 26 regex replacement pass before migration. Validate every `<drupal-media>` tag resolves. | Skill 26 token count |
| Layout Builder overrides not portable | Medium (if Layout Builder used) | High: per-page layouts revert to default | Export section/block data. Rebuild as target page builder components or flatten to HTML. | Skill 16 layout count |
| Multilingual content out of sync | Medium (if 2+ languages) | High: missing translations, wrong language associations | Migrate default language first. Validate translation counts match source. | Skill 22 translation coverage |
| Commerce order history references missing products | Medium (if commerce) | Medium: orphaned orders | Migrate products before orders. Validate referential integrity. | Skill 23 product/order counts |
| Custom entity types with no target equivalent | Low-Medium | High: data loss | Identify all custom entities in Skill 25. Design target schema before migration starts. | Skill 25 entity type list |
| File download incomplete (large files, timeouts) | Medium (if files > 10GB) | Medium: missing media on new site | Checksum verification after download. Retry failed downloads. Track manifest. | Skill 14 file manifest + checksums |
| Pathauto patterns produce different URLs on target | Medium | Medium: SEO impact from URL changes | Pre-compute all aliases before migration. Compare old vs new. Generate redirects for mismatches. | Skill 20 alias list |
| Webform submission data format incompatible | Low | Medium: submission history lost | Export submissions as CSV. Import into target form system or archive separately. | Skill 19 submission format |
| User passwords not transferable | High (always) | Low-Medium: users must reset passwords | Communicate password reset requirement. Import password hashes if target uses the same hashing algorithm (unlikely). | Always applies |
| Cron-triggered scheduled content breaks | Medium (if Scheduler used) | Low: content publishes late or not at all | Export schedule dates. Rebuild scheduled publishing in target. | Skill 28 scheduled dates |
| Revision history too large to migrate | Low | Low: edit history lost | Migrate only current revision. Archive revision history as a separate dataset if needed. | Skill 27 revision count |

### Custom Risks

Add project-specific risks based on findings from earlier skills. Common sources:

- Skill 03: Custom modules with business logic that lives in PHP. That logic must be rewritten, not migrated.
- Skill 07: Custom text filter plugins that transform content on render. The stored content may look different from the displayed content.
- Skill 10: Complex permission logic tied to Drupal's node access system. Target platforms handle access control differently.
- Skill 26: Linkit references (`<a data-entity-type="node" data-entity-uuid="...">`), entity embed tokens, and shortcodes.

---

## Step 7: What Will Not Migrate

State this clearly. Stakeholders must know what requires rebuilding from scratch.

| Category | What Is Lost | Why |
|---|---|---|
| Theme and CSS | All Drupal theme code, Twig templates, CSS/SCSS, theme settings | Drupal themes are tightly coupled to Drupal's render pipeline. They do not translate to other platforms. The target site needs a new frontend. |
| Custom module business logic | PHP code in `modules/custom/*` that implements hooks, plugins, services, event subscribers | This is application code specific to Drupal's architecture. Business rules must be reimplemented in the target platform's language and framework. |
| Cron jobs | Drupal `hook_cron` implementations and cron task scheduling | Cron runs inside Drupal's runtime. Equivalent scheduled tasks must be built on the target (cron, task queues, serverless functions). |
| External integrations | Drupal modules that connect to third-party APIs (payment gateways, CRMs, marketing platforms, analytics) | Integration code is Drupal-specific. The target platform needs its own connectors. |
| Admin UI customizations | Custom admin pages, Views used only in admin, admin toolbar customizations, custom field widgets | The target platform provides its own admin interface. |
| Drupal-specific access control | `node_access` grants, custom access handlers, entity-level permissions tied to Drupal's access system | Security models differ across platforms. Rebuild access control using the target's permission system. |
| Cache configuration | Drupal's internal page cache, dynamic page cache, render cache, BigPipe, cache tags | Every platform has its own caching layer. |
| Update hooks and database migrations | Custom `hook_update_N()` functions | These are Drupal upgrade scripts. Irrelevant outside Drupal. |

List this section in the plan without hedging. If something does not migrate, say so.

---

## Step 8: Timeline Estimate

Use T-shirt sizing by phase. Base estimates on the complexity score from Step 1 and the content type count.

### Phase Duration Reference

| Phase | Low Complexity (1-3) | Medium (4-6) | High (7-9) | Very High (10+) |
|---|---|---|---|---|
| Discovery + audit (Skills 01-03) | 1-2 days | 2-3 days | 3-5 days | 5-10 days |
| Content model design on target | 2-3 days | 1-2 weeks | 2-4 weeks | 4-8 weeks |
| Migration script development | 1-2 weeks | 3-6 weeks | 6-12 weeks | 12-24 weeks |
| Content migration execution | 1 day | 1-3 days | 3-5 days | 1-2 weeks |
| Frontend development | 2-4 weeks | 4-8 weeks | 8-16 weeks | 16-32 weeks |
| URL redirects + SEO verification | 1-2 days | 3-5 days | 1-2 weeks | 2-4 weeks |
| QA + validation | 3-5 days | 1-2 weeks | 2-4 weeks | 4-8 weeks |
| Parallel run + cutover | 1-2 days | 3-5 days | 1-2 weeks | 2-4 weeks |

### Total Estimate by Complexity

| Complexity | Calendar Time | Developer-Weeks |
|---|---|---|
| Low (1-3) | 6-10 weeks | 8-15 |
| Medium (4-6) | 3-5 months | 20-40 |
| High (7-9) | 5-9 months | 40-80 |
| Very High (10+) | 9-18 months | 80-160+ |

These estimates assume the migration team knows the target platform. Add 2-4 weeks for platform learning if the team is new to the target.

### Timeline Adjustments

Increase the estimate for:

- Multilingual: multiply content migration and QA phases by the number of languages
- Commerce: add 30-50% to migration script development for order/payment data
- Custom entities: add 1-2 weeks per custom entity type for schema design and migration scripting
- Layout Builder: add 2-4 weeks for layout conversion logic

Decrease the estimate for:

- Content-only migration (no structure rebuild): cut content model design and frontend phases
- Target platform has import tools (e.g., WordPress WP All Import): cut migration script development by 30-50%
- Small site (< 500 nodes, < 5 content types): use the low end of the Low range

---

## Step 9: Validation Plan

Define how to verify the migration is complete and correct. This feeds into Skill 31 (Validation Checklist) but provides the strategy here.

### Count Validation

Compare entity counts between source and target:

| Entity Type | Source Count | Target Count | Match? |
|---|---|---|---|
| Nodes (by type) | From Skill 01 | Query target | Yes/No + delta |
| Taxonomy terms (by vocab) | From Skill 13 | Query target | |
| Media entities (by bundle) | From Skill 14 | Query target | |
| Users | From Skill 17 | Query target | |
| Comments | From Skill 18 | Query target | |
| Redirects | From Skill 20 | Query target | |
| Paragraphs (by type) | From Skill 12 | Query target | |

A count mismatch means either the migration script filtered records or an error occurred. Investigate every mismatch.

### Content Spot-Check

Select a sample of content for manual comparison:

1. Pick 5-10 nodes from each content type. Include the newest, the oldest, and 3-8 random selections.
2. Compare field values between source and target. Every field on every sampled node.
3. For paragraphs: verify the tree structure matches. Child order, nesting depth, all field values.
4. For media: verify the file exists on the target, the file size matches, and the media metadata (alt text, title) carried over.
5. For rich text: render the content in the target and visually compare to the source. Check for broken images, missing embeds, mangled formatting.

### URL Validation

1. Crawl the old site to produce a list of all URLs.
2. For each old URL, verify it either resolves on the new site (same content) or redirects (301) to the correct new URL.
3. Check for redirect chains (A redirects to B which redirects to C). Collapse to a single hop.
4. Check for redirect loops.
5. Verify the sitemap on the new site contains all public content URLs.

### Referential Integrity

1. For every entity reference field on migrated content, verify the target entity exists.
2. For menu links, verify the linked content exists.
3. For inline links in rich text (`<a href="/node/42">`), verify the link resolves on the target.
4. For embedded media in rich text, verify the media entity and file exist.

### Functional Validation

1. Search: if the target has search, verify results match expectations for 10-20 test queries.
2. Forms: submit each migrated webform and verify submissions are captured.
3. User login: verify users can authenticate (or receive password reset emails).
4. Permissions: verify role-based access restrictions match the source.
5. Workflows: if editorial workflows were migrated, verify state transitions work.

---

## Output: The Migration Plan Document

Generate a markdown file named `migration-plan.md` with the following structure. Fill every section from the data gathered above.

```markdown
# Migration Plan: [Site Name]

Generated: [date]
Source: Drupal [version] at [site URL or identifier]
Target: [target platform]
Scope: [content only | content + structure | full migration]

## Executive Summary

- **Site size**: [X] nodes across [Y] content types, [Z] taxonomy terms,
  [A] media entities, [B] users, [C] files totaling [D] GB
- **Complexity score**: [N]/10 — [Low/Medium/High/Very High]
- **Estimated effort**: [T-shirt size] — [calendar range], [developer-week range]
- **Key risks**: [top 3 risks in one line each]
- **Skills run**: [list of completed skill numbers]
- **Gaps**: [list of recommended but unrun skills]

## Content Model Mapping

### Node Content Types

| Source Type | Count | Fields | Has Paragraphs | Target Type | Method |
|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... |

### Taxonomy Vocabularies

| Source Vocabulary | Terms | Hierarchical | Target Equivalent |
|---|---|---|---|
| ... | ... | ... | ... |

### Media Types

| Source Bundle | Count | Target Equivalent |
|---|---|---|
| ... | ... | ... |

### Paragraph Types

| Source Type | Used By | Nesting Depth | Target Component |
|---|---|---|---|
| ... | ... | ... | ... |

### Other Entities

[Block types, webforms, commerce types, custom entities]

## Data Migration Sequence

| Phase | Entities | Estimated Records | Depends On |
|---|---|---|---|
| 1 | Taxonomy terms | [count] | — |
| 2 | Media + files | [count] + [file size] | Phase 1 |
| 3 | Users + roles | [count] | — |
| 4 | Nodes (by type) | [count] | Phases 1-3 |
| 5 | Paragraphs | [count] | Phase 4 |
| 6 | Comments | [count] | Phase 4 |
| 7 | Menus | [count] links | Phases 1, 4 |
| 8 | Blocks | [count] | Phases 1-4 |
| 9 | Path aliases | [count] | Phases 1-4 |
| 10 | Redirects | [count] | Phase 9 |
| 11 | Webforms | [count] forms, [count] submissions | Phase 4 |
| 12 | Commerce | [count] products, [count] orders | Phases 1-3 |

## Feature Parity

### Views → Target Queries

| View | Purpose | Target Implementation |
|---|---|---|
| ... | ... | ... |

### Paragraphs → Target Components

| Paragraph Type | Target Component | Conversion Notes |
|---|---|---|
| ... | ... | ... |

### Workflows → Target States

| Source State | Target State |
|---|---|
| ... | ... |

### Search

[Source search config → target search solution]

### Webforms

[Source forms → target form solution]

## URL Migration Strategy

### Alias Preservation

- Total aliases: [count]
- Preserved (same path): [count]
- Redirected (path changed): [count]
- Removed (content deleted): [count]

### Redirect Map

- Existing redirects carried forward: [count]
- New redirects generated by path changes: [count]
- Format: [target platform redirect format]

### SEO Considerations

[High-traffic pages, ranking pages, structured data, sitemap plan]

## Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | ... | ... | ... | ... |

## What Will Not Migrate

| Category | Details |
|---|---|
| Theme / CSS | [specifics from the site] |
| Custom module logic | [list custom modules and what they do] |
| Cron jobs | [list scheduled tasks] |
| External integrations | [list third-party connections] |
| Admin customizations | [list admin-only features] |

## Timeline

| Phase | Duration | Team |
|---|---|---|
| Discovery + audit | [range] | [who] |
| Content model design | [range] | [who] |
| Migration scripts | [range] | [who] |
| Content migration | [range] | [who] |
| Frontend build | [range] | [who] |
| URL + SEO work | [range] | [who] |
| QA + validation | [range] | [who] |
| Cutover | [range] | [who] |
| **Total** | **[range]** | |

## Validation Plan

### Count Checks

| Entity | Source | Target | Status |
|---|---|---|---|
| ... | ... | ... | Pending |

### Spot-Check Sample

[List of specific content items to compare manually]

### URL Audit

[Crawl plan, redirect verification, sitemap check]

### Functional Tests

[Search, forms, auth, permissions, workflows]
```

---

## Target-Specific Recommendations

After generating the main plan, add a section with recommendations specific to the chosen target platform.

### WordPress

- Use WP-CLI for bulk import. Avoid the admin UI for large datasets.
- Install Advanced Custom Fields (ACF) or Meta Box before importing to define custom fields per post type.
- Map Drupal image styles to WordPress image sizes in `functions.php` or a plugin.
- Drupal's body field with summary maps to WP's `post_content` and `post_excerpt`.
- Drupal's taxonomy vocabularies beyond tags and categories require `register_taxonomy()` calls.
- Consider WP All Import for CSV-based import if the migration script approach is too complex.

### Sanity

- Define the Sanity schema first. Use `content-model.json` to generate `schema.ts` files.
- Paragraphs map well to Sanity's block content (Portable Text) or to array fields of typed objects.
- Use the Sanity Migration tool (`@sanity/migrate`) or write a custom script with `@sanity/client`.
- Batch writes with `client.transaction()` for performance.
- Sanity has no built-in redirects. Use a Vercel/Netlify redirect file or a custom redirect document type.

### Contentful

- Contentful has a 50,000 record limit per space on some plans. Check plan limits before starting.
- Use the Contentful Migration CLI to create content types programmatically.
- Rich text fields use Contentful's rich text JSON format. Convert Drupal HTML to this format.
- Paragraphs map to embedded entries within rich text or to linked entries in a multi-reference field.
- Media assets upload via the Contentful Asset API. Download files from Drupal first, then upload.

### Strapi

- Define collection types in Strapi before importing.
- Paragraphs map to Dynamic Zones (multiple component types in one field) or Components (single type).
- Use the Strapi REST or GraphQL API for bulk import. Write a script that POSTs entities in dependency order.
- Strapi v5 changed the API response format. Verify the target version before writing import scripts.

### Payload CMS

- Define collections from `content-model.json`. Each Drupal content type becomes a Payload collection.
- Paragraphs map to Payload's Blocks field type.
- Payload stores data in MongoDB or PostgreSQL. Use the local API (`payload.create()`) for fast bulk import.
- Payload has built-in draft/publish and access control. Map Drupal workflows and permissions directly.

### Hugo / Astro / 11ty (Static Site Generators)

- Each content type becomes a content directory. Nodes become markdown files with front matter.
- Rich text HTML must convert to markdown. Use a library like Turndown (JS) or html2text (Python).
- Paragraphs lose their structured nature in markdown. Flatten to HTML sections, or use shortcodes/MDX components.
- Taxonomy terms become taxonomy pages automatically (Hugo) or require explicit collection config (Astro, 11ty).
- Media files copy to the static/public directory. Update all internal references to new paths.
- No user system, comments, or forms in static sites. Use external services (Disqus, Formspree, Auth0) or skip.

### Craft CMS

- Content types map to Sections (Channel, Structure, or Single) with Entry Types.
- Paragraphs map to Matrix fields (Craft 4) or the new entry-based Matrix (Craft 5).
- Use the Craft Feed Me plugin for CSV/JSON import.
- Craft has built-in image transforms that map to Drupal image styles.
- URL aliases map to Craft's URI Format setting on each section.

### Statamic

- Content types become Collections. Taxonomies map directly.
- Paragraphs map to Replicator fields (ordered sets of fieldsets) or Bard blocks (rich text with sets).
- Content stores as flat files (YAML + markdown) by default. Good fit if coming from a Git-based workflow.
- Use the Statamic CLI or write a script that generates flat files in the expected directory structure.

---

## Handling Gaps

If skills have not been run, flag them in the plan. For each gap:

1. Name the missing skill and what data it would provide.
2. State what section of the plan is incomplete without it.
3. Recommend whether to run the skill before finalizing the plan or proceed with assumptions.

Example gap entries:

| Missing Skill | Impact on Plan | Recommendation |
|---|---|---|
| Skill 05 (Views) | Feature parity section has no View-to-query mapping | Run before finalizing. Views encode business logic that affects target architecture. |
| Skill 12 (Paragraphs) | Content model mapping lacks paragraph nesting depth. Risk register may underestimate paragraph complexity. | Run before finalizing if Paragraphs module is enabled. |
| Skill 20 (URL Aliases) | URL migration strategy section is empty. SEO risk is unquantified. | Run before finalizing if SEO matters. |
| Skill 22 (Multilingual) | No translation coverage data. Timeline may be underestimated. | Run if site has more than one language. |
| Skill 26 (Rich Text Cleanup) | Cannot assess embedded media token risk. Content may break after migration. | Run before content migration begins. |

---

## Final Checklist Before Delivering the Plan

Before presenting the migration plan to the user:

- [ ] Every table has data from skill outputs, not placeholder text
- [ ] Complexity score calculated with the formula above, not estimated by feel
- [ ] Content model mapping covers every content type, vocabulary, media bundle, and paragraph type
- [ ] Migration sequence accounts for all entity reference dependencies
- [ ] Risk register includes at least 5 risks ranked by likelihood and impact
- [ ] "What will not migrate" section lists concrete items from this site, not generic warnings
- [ ] Timeline references the complexity score and adjustments for site-specific factors
- [ ] Gaps section lists every recommended skill that was not run
- [ ] Target-specific recommendations match the chosen platform
- [ ] URL migration strategy includes actual alias and redirect counts
