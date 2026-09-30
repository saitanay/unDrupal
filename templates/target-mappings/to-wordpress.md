# Target Mapping Guide: Drupal to WordPress

**Target platform:** WordPress 6.x
**Last updated:** 2024-01-15

---

## Platform Overview

WordPress is the most widely deployed CMS. It stores content in a MySQL/MariaDB database using a posts + postmeta pattern. Custom fields are typically managed through plugins like Advanced Custom Fields (ACF), Meta Box, or Pods. The block editor (Gutenberg) uses HTML comments to delimit blocks within `post_content`.

### Key Architectural Differences from Drupal

| Concept | Drupal | WordPress |
|---|---|---|
| Content types | Entity bundles with field configs | Post types (built-in + CPT) |
| Fields | Field API (typed, configurable) | postmeta key-value + ACF/Meta Box |
| Taxonomy | Vocabulary + terms | Taxonomy + terms (similar) |
| Media | Media entity + file entity | Attachment post type + media library |
| Paragraphs | Paragraph entity bundles | Gutenberg blocks or ACF Flexible Content |
| URL aliases | Path alias / Pathauto | Permalink structure + Yoast/Redirection |
| Views | Views module | WP_Query + custom templates or plugins |
| Users/roles | User entity + role permissions | wp_users + wp_usermeta + roles/capabilities |
| Revisions | Entity revisions | Post revisions (content only) |
| Multilingual | Content translation / i18n | WPML / Polylang |

---

## Content Type Mapping

### Nodes → Posts / Custom Post Types

| Drupal Content Type | WordPress Post Type | Notes |
|---|---|---|
| article | `post` | Default blog post type; map categories and tags |
| page | `page` | Default page type; set template if needed |
| [custom type] | Custom Post Type (CPT) | Register via `register_post_type()` or CPT UI plugin |

#### Required Setup

1. Register CPTs for each Drupal content type beyond article/page.
2. Install ACF Pro or Meta Box and create field groups matching Drupal field configs.
3. Map Drupal field cardinality: single-value → standard field; multi-value → repeater or group.

### Field Type Mapping

| Drupal Field Type | WordPress / ACF Field Type | Notes |
|---|---|---|
| text | text | |
| text_long | textarea | |
| text_with_summary | wysiwyg (ACF) | Summary → excerpt |
| string | text | |
| integer | number (integer) | |
| decimal / float | number | |
| boolean | true_false | |
| datetime | date_time_picker | |
| timestamp | number or date_time_picker | Convert from Unix timestamp |
| email | email | |
| link | link (url + title) | |
| list_string | select | Options must be recreated |
| list_integer | select | |
| entity_reference (node) | post_object or relationship | |
| entity_reference (term) | taxonomy | |
| entity_reference (user) | user | |
| image | image | Upload to media library |
| file | file | Upload to media library |
| entity_reference_revisions (paragraph) | flexible_content (ACF) | See Paragraphs section |

---

## Taxonomy Mapping

| Drupal Vocabulary | WordPress Taxonomy | Notes |
|---|---|---|
| tags | `post_tag` | Built-in |
| [vocabulary] | Custom taxonomy | Register via `register_taxonomy()` |

- Term hierarchy is supported natively (parent term ID).
- Term descriptions map directly.
- Term fields require ACF for Taxonomies.

---

## Paragraph / Component Mapping

Drupal paragraphs become either Gutenberg blocks or ACF Flexible Content layouts.

### Option A: Gutenberg Blocks

Map each paragraph type to a core or custom Gutenberg block. Use the flattened component output from `flatten-paragraphs.py`:

| Paragraph Type | Gutenberg Block | Notes |
|---|---|---|
| text | `core/paragraph` or `core/freeform` | |
| image | `core/image` | |
| video | `core/video` or `core/embed` | |
| accordion | Custom block or plugin | |
| columns | `core/columns` | Nested layout |
| call_to_action | Custom block | |

Generate block markup as HTML with block comment delimiters:
```html
<!-- wp:paragraph -->
<p>Content here</p>
<!-- /wp:paragraph -->
```

### Option B: ACF Flexible Content

Map each paragraph type to a Flexible Content layout. Preferred when content editors need structured editing rather than free-form blocks.

---

## Media Mapping

| Drupal Media Type | WordPress | Notes |
|---|---|---|
| image | Attachment (image) | Upload to `wp-content/uploads/` |
| document | Attachment (application) | |
| remote_video | oEmbed or custom field | Store URL, let WP handle embed |
| audio | Attachment (audio) | |

### File Migration Steps

1. Download all files from Drupal's `sites/default/files/` (or S3/CDN).
2. Upload to WordPress `wp-content/uploads/` with date-based directory structure.
3. Create attachment posts in `wp_posts` with `post_type = 'attachment'`.
4. Set `_wp_attached_file` and `_wp_attachment_metadata` in postmeta.
5. Update content references to use new attachment IDs.

---

## URL and Redirect Mapping

1. Set WordPress permalink structure to match Drupal alias patterns where possible.
2. Use `generate-redirects.py --format wordpress` or the Redirection plugin.
3. Import 301 redirects for any paths that changed.
4. Map Drupal path aliases to WordPress slugs on the corresponding post.

---

## User Mapping

| Drupal | WordPress | Notes |
|---|---|---|
| uid | ID | |
| name | user_login | |
| mail | user_email | |
| status (1/0) | user_status | WP uses 0 = active, opposite of Drupal |
| roles | wp_capabilities | Map custom roles to WP roles or create new ones |
| created | user_registered | Convert timestamp to datetime |
| user fields | wp_usermeta | Via ACF or direct meta |

**Password migration:** Drupal uses phpass (D7) or Argon2/bcrypt (D8+). WordPress uses phpass. For D7 sites, hashes may be directly compatible. For D8+, users will need to reset passwords or use a custom authentication plugin.

---

## Menu Mapping

| Drupal | WordPress | Notes |
|---|---|---|
| Menu link | `wp_nav_menu` item | |
| Menu tree | Nav menu with parent references | |
| External links | Custom link menu item | |
| Internal links | Post/page menu item | Re-map entity IDs |

---

## Views → WordPress Queries

Drupal Views don't have a direct WordPress equivalent. Options:

1. **WP_Query in templates** — translate View filters to `WP_Query` args.
2. **REST API** — if frontend is decoupled, query via `/wp-json/wp/v2/`.
3. **Plugin (FacetWP, SearchWP)** — for faceted or advanced search Views.
4. Use the `views-to-query.py` output as a starting point for WP_Query args.

---

## Multilingual Content

| Approach | Plugin | Notes |
|---|---|---|
| WPML | WPML Multilingual CMS | Most full-featured; paid |
| Polylang | Polylang / Polylang Pro | Lighter weight |

Map Drupal's language codes and translation relationships to the chosen plugin's schema. Both plugins use post meta or taxonomy to associate translations.

---

## Import Tools

| Tool | Use Case |
|---|---|
| WP-CLI `wp import` | WXR XML import |
| WP All Import Pro | CSV/XML import with field mapping |
| Custom script via WP REST API | JSON import with full control |
| Custom script via `wp_insert_post()` | Direct PHP import (fastest for bulk) |

### Recommended Approach

1. Export from Drupal using the toolkit's extraction skills.
2. Transform with `normalize-content.py` and `flatten-paragraphs.py`.
3. Generate a WP All Import-compatible CSV or write a custom REST/PHP importer.
4. Import media first, then content (to resolve attachment references).
5. Import taxonomy terms before posts.
6. Run `validate-export.py` on the source data before importing.
7. Run the validation checklist after import.

---

## Known Gotchas

- WordPress stores all content in `post_content` as serialized block HTML. Structured field data lives only in postmeta/ACF. If you need structured + rendered, store in both places.
- WordPress has no native revision support for custom fields. ACF Pro adds this.
- WordPress permalink changes require manual redirect setup. Drupal's redirect module exports help here.
- `wp_insert_post()` triggers hooks. For bulk import, use `wp_defer_term_counting(true)` and disable hooks where possible.
- Max `post_content` size is limited by `max_allowed_packet` in MySQL. Very large paragraph-heavy pages may need splitting.
