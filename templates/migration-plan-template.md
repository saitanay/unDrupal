# Migration Plan: [Site Name]

**Source:** Drupal [version] at [URL or environment]
**Target:** [Target platform/framework]
**Date:** [YYYY-MM-DD]
**Author:** [Name]
**Status:** Draft | In Review | Approved

---

## Executive Summary

One paragraph. State what is being migrated, to what, and why. Include the estimated content volume (node count, media count, user count) and the target launch date.

---

## Source Site Profile

### Drupal Version and Stack

| Property | Value |
|---|---|
| Drupal version | |
| PHP version | |
| Database | MySQL / MariaDB / PostgreSQL [version] |
| Web server | Apache / Nginx [version] |
| Hosting | |
| Caching layer | Varnish / Redis / Memcached / none |
| CDN | Cloudflare / CloudFront / none |
| Search | Core search / Search API + Solr / Elasticsearch / Algolia |

### Content Volume

| Entity Type | Count |
|---|---|
| Nodes (total) | |
| — [content type 1] | |
| — [content type 2] | |
| Taxonomy terms | |
| Media entities | |
| Files | |
| Paragraphs | |
| Users | |
| Comments | |
| Redirects | |
| URL aliases | |
| Webform submissions | |
| Commerce products | |

### Installed Modules

List contrib modules that affect data structure or behavior. Group by category:

**Content modeling:** Paragraphs, Entity Reference Revisions, Field Group, ...
**Media:** Media, Focal Point, Crop API, ...
**SEO:** Pathauto, Redirect, Metatag, XML Sitemap, ...
**Search:** Search API, Facets, ...
**Multilingual:** Content Translation, Config Translation, Interface Translation, ...
**Commerce:** Commerce core, Commerce Product, ...
**Other:** [list]

---

## Content Model Mapping

For each source content type, map to the target structure.

### [Source Content Type: machine_name]

**Target:** [target content type or collection name]

| Drupal Field | Type | Cardinality | Target Field | Target Type | Notes |
|---|---|---|---|---|---|
| title | string | 1 | | | |
| body | text_with_summary | 1 | | | |
| field_image | image | 1 | | | |
| field_tags | entity_reference (taxonomy) | unlimited | | | |
| field_paragraphs | entity_reference_revisions | unlimited | | | See paragraph mapping below |

### Paragraph Type Mapping

| Drupal Paragraph Type | Target Component | Notes |
|---|---|---|
| text | | |
| image | | |
| image_text | | |
| accordion | | |
| [type] | | |

### Taxonomy Mapping

| Drupal Vocabulary | Target | Notes |
|---|---|---|
| tags | | |
| categories | | |
| [vocabulary] | | |

---

## Data Migration Sequence

Order matters. Dependencies must be migrated before the entities that reference them.

1. **Taxonomy terms** — no dependencies, referenced by nodes and paragraphs.
2. **Media entities and files** — download files, create media records. Referenced by nodes and paragraphs.
3. **Users** — create user accounts (without passwords). Referenced as node authors.
4. **Paragraph entities** — resolve nested paragraph trees bottom-up. Referenced by nodes.
5. **Nodes** — migrate with references to taxonomy, media, paragraphs, and users.
6. **Menus and navigation** — depends on nodes existing at their target URLs.
7. **URL aliases and redirects** — map old paths to new paths.
8. **Comments** — depends on nodes existing.
9. **Webform definitions and submissions** — if applicable.
10. **Commerce data** — if applicable. Products, variations, orders.

Adjust this order based on the site's reference graph. Run Skill 02 to generate the full dependency map.

---

## Feature Parity Analysis

For each Drupal feature, document whether the target platform handles it natively, needs a plugin/integration, needs custom code, or gets dropped.

| Drupal Feature | Target Equivalent | Status | Notes |
|---|---|---|---|
| Content preview | | Native / Plugin / Custom / Drop | |
| Editorial workflow (Draft/Review/Published) | | | |
| Scheduled publishing | | | |
| Revision history | | | |
| Content moderation | | | |
| Search | | | |
| Faceted search | | | |
| Multilingual content | | | |
| Multilingual UI | | | |
| Webforms | | | |
| Commerce | | | |
| User registration and profiles | | | |
| Comments | | | |
| RSS feeds | | | |
| XML sitemap | | | |
| Metatags (Open Graph, Twitter, etc.) | | | |
| Custom access control / permissions | | | |
| Layout Builder / block placement | | | |

Status values: Native, Plugin, Custom, Out of Scope, Drop

---

## URL Strategy

### Path Structure

| Drupal Pattern | Example | Target Pattern | Example |
|---|---|---|---|
| /node/[nid] | /node/42 | | |
| /[alias] | /about-us | | |
| /[type]/[alias] | /blog/my-post | | |
| /taxonomy/term/[tid] | /taxonomy/term/5 | | |

### Redirect Plan

- **Source:** Export all path aliases and redirect module entries using Skills 20.
- **Old canonical paths** (/node/NID): redirect to new URLs via 301.
- **Old aliases**: if the new URL differs, add a 301 redirect.
- **Existing redirects**: chain-resolve so no redirect points to another redirect.
- **Format:** Generate redirect rules for [nginx / Apache / Vercel / Netlify / Cloudflare].

### Domain Strategy

| Concern | Plan |
|---|---|
| Domain change? | Same domain / new domain / subdomain |
| HTTPS | |
| www vs non-www | |
| Trailing slashes | |
| DNS cutover plan | |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Data loss during migration | Low | High | Run validation counts after every batch. Keep source site read-only during final migration. |
| Broken internal links in rich text | Medium | Medium | Run Skill 26 to rewrite embedded references before migration. |
| SEO ranking drop | Medium | High | 301 redirects for all changed URLs. Submit updated sitemap to Google Search Console. |
| Paragraph nesting too deep for target | Low | Medium | Flatten to max 2 levels during export. See Skill 12. |
| Missing media files | Low | High | Verify file existence during download. Report missing files before content migration. |
| Custom module data not exported | Medium | Medium | Audit custom entity types with Skill 25 before planning. |
| Timeline slip | Medium | Medium | Migrate incrementally. Run content types in parallel. |

Add project-specific risks here.

---

## Out of Scope

List what is explicitly not being migrated and why.

- [ ] Revision history beyond current published version
- [ ] Webform submissions (archive separately)
- [ ] User passwords (users will reset passwords on new site)
- [ ] Commerce order history (export to CSV for archival)
- [ ] [Item] — [reason]

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|---|---|---|
| Discovery and audit (Skills 01-10) | [X days] | Site access |
| Content model mapping | [X days] | Discovery complete |
| Target platform setup | [X days] | Model mapping approved |
| Migration script development | [X days] | Target platform ready |
| Test migration (full) | [X days] | Scripts complete |
| Content freeze on source | [X days] | Stakeholder agreement |
| Final migration | [X days] | Content freeze active |
| Validation (Skill 31) | [X days] | Final migration complete |
| DNS cutover and go-live | [X days] | Validation passed |
| Post-launch monitoring | [X days] | Go-live |

**Total estimated duration:** [X weeks]

---

## Validation Plan

Use the validation checklist (Skill 31 / `templates/validation-checklist.md`) to verify the migration. At minimum:

### Content Counts
Compare entity counts between source and target for every content type, vocabulary, media type, and user role.

### Structural Verification
Spot-check 5-10 nodes per content type. Verify all fields transferred, paragraph nesting is correct, entity references resolve, and media displays.

### URL Verification
Crawl the target site. Compare against the source URL list. Verify 301 redirects return correct status codes and destinations.

### SEO Verification
Check meta tags, canonical URLs, Open Graph tags, structured data, and XML sitemap on the target.

### Performance Baseline
Run Lighthouse or WebPageTest on 5 representative pages. Compare against source site scores.

### Stakeholder Sign-off
Identify who approves the migration as complete. Define the rollback plan if critical issues surface after go-live.
