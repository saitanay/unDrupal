# Target Mapping Guide: Drupal to Custom Application

**Target platform:** Custom web application (any language/framework)
**Last updated:** 2024-01-15

---

## Platform Overview

This guide covers migrating Drupal content to a bespoke application where you control the database schema, API, and rendering layer. This applies to custom apps built with:

- **Backend frameworks:** Django, Rails, Laravel, Express, FastAPI, Spring Boot, ASP.NET, Phoenix, etc.
- **Frontend frameworks:** React, Vue, Svelte, Angular, etc. (consuming an API)
- **Databases:** PostgreSQL, MySQL, MongoDB, SQLite, etc.
- **Full-stack:** Next.js with custom data layer, SvelteKit, Remix, Nuxt, etc.

Because you own every layer, you have maximum flexibility in how to model, store, and present the migrated content.

---

## Content Model Design

### Principles

1. **Do not replicate Drupal's schema.** Drupal's `node`, `field_data_*`, and EAV pattern are optimized for its runtime, not yours. Design a schema that fits your application's query patterns and UI.
2. **Flatten where possible.** Drupal stores fields across many tables. Consolidate into single tables per content type.
3. **Normalize where appropriate.** Use proper relational tables for taxonomies, tags, and many-to-many relationships.
4. **Plan your ID strategy.** Decide whether to keep Drupal's node IDs (for URL compatibility) or generate new IDs and maintain a mapping table for redirects.

### Entity Type → Table/Collection Mapping

| Drupal Entity | Custom App | Notes |
|---|---|---|
| Node (per bundle) | One table per content type | `articles`, `pages`, `events`, etc. |
| Taxonomy term | Lookup/reference table | `categories`, `tags`, `topics` |
| Media entity | `media` table + file storage | Or inline on content table |
| Paragraph | Inline JSON or child table | See Components section |
| User | `users` table | |
| File | File storage + metadata table | S3/local + `files` table |
| Redirect | `redirects` table | |
| Menu link | `menus` / `menu_items` table | |
| URL alias | `slug` column on content table | |

---

## Schema Design Example

### Relational (PostgreSQL/MySQL)

```sql
-- Content types
CREATE TABLE articles (
    id BIGSERIAL PRIMARY KEY,
    drupal_nid INTEGER,                  -- Original Drupal node ID for mapping
    title VARCHAR(512) NOT NULL,
    slug VARCHAR(512) UNIQUE NOT NULL,
    body TEXT,                           -- HTML or Markdown
    summary TEXT,
    author_id BIGINT REFERENCES authors(id),
    featured_image_id BIGINT REFERENCES media(id),
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'published',
    meta JSONB DEFAULT '{}'             -- Catch-all for misc fields
);

-- Taxonomy
CREATE TABLE categories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    parent_id BIGINT REFERENCES categories(id)
);

CREATE TABLE article_categories (
    article_id BIGINT REFERENCES articles(id) ON DELETE CASCADE,
    category_id BIGINT REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (article_id, category_id)
);

-- Media
CREATE TABLE media (
    id BIGSERIAL PRIMARY KEY,
    filename VARCHAR(512) NOT NULL,
    mime_type VARCHAR(128),
    file_size BIGINT,
    storage_path VARCHAR(1024),          -- S3 key or local path
    alt_text VARCHAR(512),
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Components (paragraph replacement)
CREATE TABLE article_components (
    id BIGSERIAL PRIMARY KEY,
    article_id BIGINT REFERENCES articles(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL,
    component_type VARCHAR(100) NOT NULL, -- 'hero', 'text_block', 'image_gallery'
    data JSONB NOT NULL                   -- Typed component data
);

-- Redirects
CREATE TABLE redirects (
    id BIGSERIAL PRIMARY KEY,
    from_path VARCHAR(2048) UNIQUE NOT NULL,
    to_path VARCHAR(2048) NOT NULL,
    status_code SMALLINT DEFAULT 301
);
```

### Document Store (MongoDB)

```js
// articles collection
{
  _id: ObjectId,
  drupalNid: 123,
  title: "Hello World",
  slug: "hello-world",
  body: "<p>HTML content...</p>",
  summary: "Brief summary",
  author: { name: "Jane Doe", slug: "jane-doe" },  // Embedded or reference
  categories: [
    { name: "News", slug: "news" },
  ],
  featuredImage: {
    url: "/media/hero.jpg",
    alt: "Hero image",
    width: 1200,
    height: 800,
  },
  components: [
    { type: "hero", heading: "Welcome", image: "/media/bg.jpg" },
    { type: "textBlock", body: "<p>...</p>" },
  ],
  publishedAt: ISODate("2024-01-15T10:00:00Z"),
  status: "published",
}
```

---

## Field Type Mapping

| Drupal Field Type | Relational DB | Document DB | Notes |
|---|---|---|---|
| text / string | `VARCHAR` | `String` | |
| text_long | `TEXT` | `String` | |
| text_with_summary | `TEXT` + `TEXT` | `body` + `summary` | |
| integer | `INTEGER` | `Number` | |
| decimal / float | `NUMERIC` / `FLOAT` | `Number` | |
| boolean | `BOOLEAN` | `Boolean` | |
| datetime | `TIMESTAMPTZ` | `Date` | |
| timestamp | `BIGINT` or `TIMESTAMPTZ` | `Date` | Convert Unix → datetime |
| email | `VARCHAR` with check | `String` | |
| link | `VARCHAR` + `VARCHAR` or `JSONB` | `{ url, title }` | |
| list_string | `VARCHAR` with check or enum | `String` with enum validation | |
| entity_reference | Foreign key | ObjectId reference or embedded | |
| image | FK to `media` table | Embedded or `$ref` | |
| file | FK to `media` table | Embedded or `$ref` | |
| entity_reference_revisions | Child table or `JSONB` | Embedded array | See Components |

---

## Paragraph / Component Mapping

### Option A: JSON Column (Recommended for Moderate Complexity)

Store flattened components as a JSON array on the parent content record:

```json
{
  "components": [
    {
      "type": "hero",
      "heading": "Welcome",
      "backgroundImage": "/media/hero.jpg",
      "ctaLabel": "Learn More",
      "ctaUrl": "/about"
    },
    {
      "type": "textBlock",
      "body": "<p>Our mission is...</p>"
    }
  ]
}
```

Render in your frontend by mapping `type` to a component/template.

### Option B: Child Table (Better for Querying Across Components)

See `article_components` table in the schema example above. Each component is a row with a `component_type` discriminator and `data` JSON payload.

### Option C: Fully Typed Tables

One table per component type. Most normalized, but creates many tables. Only worthwhile if you need to query component data independently.

Use `flatten-paragraphs.py` output as the source for component data in any option.

---

## Media Migration

1. Export file metadata and download files from Drupal.
2. Upload files to your storage backend (local filesystem, S3, GCS, Azure Blob).
3. Create media records in your database with storage paths.
4. Update content references to use new media IDs/paths.

### File Storage Patterns

| Pattern | When to Use |
|---|---|
| Local filesystem | Development, small sites |
| S3 + CloudFront | Production, any scale |
| Database BLOBs | Avoid (poor performance for media) |
| CDN proxy (Cloudflare, Imgix) | When you need on-the-fly image transforms |

---

## URL and Redirect Strategy

1. Store `slug` on every content record.
2. If preserving Drupal URLs: keep the Drupal `nid` and generate redirects from `/node/{nid}` to the new slug-based URL.
3. Import all Drupal path aliases and redirect entries.
4. Implement a redirect middleware/handler in your app:

```python
# Django example
from django.shortcuts import redirect
from myapp.models import Redirect

class RedirectMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        try:
            r = Redirect.objects.get(from_path=request.path)
            return redirect(r.to_path, permanent=(r.status_code == 301))
        except Redirect.DoesNotExist:
            return self.get_response(request)
```

Or use `generate-redirects.py` to produce redirect configs for nginx/Apache in front of your app.

---

## Querying Content (Views Replacement)

You control the query layer. Map each Drupal View to:

1. A database query (ORM or raw SQL).
2. An API endpoint (REST or GraphQL).
3. A search index query (Elasticsearch, Meilisearch, Typesense) for full-text or faceted views.

Use `views-to-query.py` to catalog what each Drupal View did (filters, sorts, paging, relationships). Implement the equivalent query in your framework.

---

## User Migration

| Drupal | Custom App | Notes |
|---|---|---|
| uid | id | |
| name | username | |
| mail | email | |
| status | is_active | Invert: Drupal 1=active, 0=blocked |
| roles | roles (RBAC table or array) | Map Drupal roles to your permission model |
| created | created_at | Convert timestamp |
| user fields | Profile columns or related table | |

**Passwords:** Drupal uses phpass (D7) or Argon2i/bcrypt (D8+). Options:
- Import hashes and implement Drupal's hash verification in your app.
- Force password resets for all users on first login.
- Use a migration-period dual-hash strategy (try new hash, fall back to Drupal hash, then rehash).

---

## Multilingual Content

Design based on your needs:

### Row-per-Translation Pattern (Relational)

```sql
CREATE TABLE article_translations (
    article_id BIGINT REFERENCES articles(id),
    language VARCHAR(5) NOT NULL,
    title VARCHAR(512) NOT NULL,
    body TEXT,
    summary TEXT,
    slug VARCHAR(512),
    PRIMARY KEY (article_id, language)
);
```

### Locale Object Pattern (Document)

```json
{
  "title": { "en": "Hello World", "fr": "Bonjour le monde" },
  "body": { "en": "<p>English...</p>", "fr": "<p>Français...</p>" }
}
```

### Separate Document per Language

Each translation is its own document, linked by a `translation_group` ID. Simpler queries, more documents.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Run `validate-export.py` on the transformed data.
4. Write a migration script in your application's language:
   - Read the transformed JSON.
   - Upload media files to your storage.
   - Insert records in dependency order: media → taxonomies → users → content → components → redirects.
   - Maintain an ID mapping (Drupal ID → new ID) for resolving references.
5. Run the validation checklist after import.

### Import Script Pattern

```python
# Generic Python pattern
import json

# Load transformed export
with open('export.json') as f:
    data = json.load(f)

# Phase 1: Media
media_map = {}  # drupal_fid -> new_id
for media in data['media']:
    new_id = upload_and_create_media(media)
    media_map[media['drupal_id']] = new_id

# Phase 2: Taxonomies
term_map = {}
for term in data['taxonomy_terms']:
    new_id = create_term(term)
    term_map[term['drupal_id']] = new_id

# Phase 3: Content
for entity in data['entities']:
    entity['featured_image_id'] = media_map.get(entity.get('featured_image_drupal_id'))
    entity['category_ids'] = [term_map[tid] for tid in entity.get('category_drupal_ids', [])]
    create_content(entity)

# Phase 4: Redirects
for redirect in data['redirects']:
    create_redirect(redirect['from_path'], redirect['to_path'])
```

---

## Known Gotchas

- **No CMS admin for free.** You need to build or integrate an admin UI (Django Admin, Laravel Nova, custom React admin, etc.).
- **Schema migrations are your responsibility.** Plan for evolving the content model after initial import.
- **Drupal's EAV pattern hides complexity.** When you flatten to typed tables, you may discover field conflicts, inconsistent data, or content that relied on Drupal's loose typing.
- **HTML cleanup is critical.** Drupal's filtered HTML may contain Drupal-specific markup (media embed tokens, linkit references, view embeds). Run `clean-rich-text.py` and inspect the output.
- **Performance testing with real data.** Test your queries with the full imported dataset, not a subset. Drupal sites often have more content and relationships than expected.
- **Revision history is lost** unless you explicitly import it. Decide whether you need historical revisions or just the current published version.
- **Search indexing.** If Drupal used Search API + Solr/Elasticsearch, plan your search infrastructure separately. The content migration and search index are independent concerns.
