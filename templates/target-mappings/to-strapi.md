# Target Mapping Guide: Drupal to Strapi

**Target platform:** Strapi 5.x (or 4.x)
**Last updated:** 2024-01-15

---

## Platform Overview

Strapi is an open-source, Node.js-based headless CMS. Content types are defined through the admin panel or code (JSON schema files). It supports SQLite, PostgreSQL, MySQL, and MariaDB. Strapi provides REST and GraphQL APIs out of the box. You self-host it.

### Key Architectural Differences from Drupal

| Concept | Drupal | Strapi |
|---|---|---|
| Content types | Entity bundles | Collection types / Single types |
| Fields | Field API | Component and field definitions |
| Taxonomy | Vocabulary + terms | Collection type with relations |
| Media | Media entity | Media Library (built-in) |
| Paragraphs | Paragraph bundles | Dynamic Zones or Components |
| Rich text | CKEditor HTML | Rich text (Markdown or Blocks) |
| URL aliases | Path alias | Slug field + frontend routing |
| Views | Views module | API queries with filters/sort/pagination |
| Users | User entity | Users & Permissions plugin |
| Revisions | Entity revisions | Draft/Publish (v4) / History (v5) |
| Multilingual | Content translation | i18n plugin (built-in) |

---

## Content Type Mapping

### Drupal Nodes → Strapi Collection Types

Create a Strapi collection type per Drupal content type. Via Admin UI or schema files:

```json
// src/api/article/content-types/article/schema.json
{
  "kind": "collectionType",
  "collectionName": "articles",
  "info": { "singularName": "article", "pluralName": "articles", "displayName": "Article" },
  "options": { "draftAndPublish": true },
  "attributes": {
    "title": { "type": "string", "required": true },
    "slug": { "type": "uid", "targetField": "title", "required": true },
    "body": { "type": "blocks" },
    "summary": { "type": "text" },
    "featuredImage": { "type": "media", "allowedTypes": ["images"], "multiple": false },
    "author": { "type": "relation", "relation": "manyToOne", "target": "api::author.author" },
    "categories": { "type": "relation", "relation": "manyToMany", "target": "api::category.category" },
    "publishedAt": { "type": "datetime" }
  }
}
```

### Field Type Mapping

| Drupal Field Type | Strapi Field Type | Notes |
|---|---|---|
| text / string | `string` | Max 255 chars by default |
| text_long | `text` (long text) | |
| text_with_summary | `blocks` or `richtext` + `text` | Body → blocks, summary → text |
| integer | `integer` | |
| decimal / float | `float` or `decimal` | |
| boolean | `boolean` | |
| datetime | `datetime` | |
| timestamp | `datetime` | Convert Unix → ISO 8601 |
| email | `email` | |
| link | `component` (url + label) | Create a reusable Link component |
| list_string | `enumeration` | |
| entity_reference (node) | `relation` | Specify relation type and target |
| entity_reference (term) | `relation` | |
| image | `media` (images) | |
| file | `media` (files) | |
| entity_reference_revisions | `dynamiczone` | See Paragraphs section |

---

## Taxonomy Mapping

Create a collection type per vocabulary:

```json
// src/api/category/content-types/category/schema.json
{
  "kind": "collectionType",
  "collectionName": "categories",
  "info": { "singularName": "category", "pluralName": "categories", "displayName": "Category" },
  "attributes": {
    "name": { "type": "string", "required": true },
    "slug": { "type": "uid", "targetField": "name" },
    "description": { "type": "text" },
    "parent": { "type": "relation", "relation": "manyToOne", "target": "api::category.category" }
  }
}
```

---

## Paragraph / Component Mapping

### Dynamic Zones

Strapi's Dynamic Zones are the closest match to Drupal paragraphs. Each paragraph type becomes a Strapi component added to a Dynamic Zone:

```json
// Create components under src/components/blocks/
// hero.json
{
  "collectionName": "components_blocks_heroes",
  "info": { "displayName": "Hero", "icon": "picture" },
  "attributes": {
    "heading": { "type": "string" },
    "subheading": { "type": "text" },
    "backgroundImage": { "type": "media", "allowedTypes": ["images"] },
    "ctaLabel": { "type": "string" },
    "ctaUrl": { "type": "string" }
  }
}
```

Add the Dynamic Zone to the content type:

```json
"content": {
  "type": "dynamiczone",
  "components": [
    "blocks.hero",
    "blocks.text-block",
    "blocks.image-gallery",
    "blocks.call-to-action"
  ]
}
```

Use `flatten-paragraphs.py` output and map `component_type` to the Strapi component name, prefixed with `__component`:

```json
{
  "content": [
    { "__component": "blocks.hero", "heading": "Welcome", "subheading": "..." },
    { "__component": "blocks.text-block", "body": "..." }
  ]
}
```

---

## Media Mapping

| Drupal Media Type | Strapi | Notes |
|---|---|---|
| image | Media Library (image) | Auto-generates thumbnails |
| document | Media Library (file) | |
| remote_video | Component with URL field | Or use Media Library video type |
| audio | Media Library (file) | |

### Upload via API

```bash
# Upload a file
curl -X POST http://localhost:1337/api/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "files=@photo.jpg" \
  -F "ref=api::article.article" \
  -F "refId=1" \
  -F "field=featuredImage"
```

---

## URL and Redirect Mapping

1. Use `uid` field type for slugs (auto-generated from title).
2. Map Drupal path aliases to Strapi slug values.
3. Frontend (Next.js, Nuxt, Astro, etc.) handles routing.
4. Use `generate-redirects.py` with the appropriate format for your hosting platform.

---

## Querying Content (Views Replacement)

Strapi REST API replaces Drupal Views:

```
GET /api/articles?filters[categories][slug][$eq]=news&sort=publishedAt:desc&pagination[pageSize]=10&populate=*
```

GraphQL (with plugin):

```graphql
query {
  articles(
    filters: { categories: { slug: { eq: "news" } } }
    sort: "publishedAt:desc"
    pagination: { pageSize: 10 }
  ) {
    data {
      attributes {
        title
        slug
        publishedAt
        categories { data { attributes { name slug } } }
        featuredImage { data { attributes { url width height } } }
      }
    }
  }
}
```

---

## Multilingual Content

Enable the i18n plugin in Strapi:

```js
// config/plugins.js
module.exports = {
  i18n: { enabled: true },
};
```

Add locales in Admin > Settings > Internationalization. Mark content types as localized. Each locale creates a separate entry linked by a localization group.

Map Drupal translations to Strapi localized entries. Create the default locale entry first, then create localizations for other languages.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML to Strapi Blocks JSON or Markdown (depending on field type).
4. Upload media files via `/api/upload`, capture returned IDs.
5. Create taxonomy/reference entries first via REST API.
6. Create content entries with resolved media and relation IDs.
7. Run `validate-export.py` before import.
8. Verify with the validation checklist after import.

### Bulk Import Script Example

```js
const fetch = require('node-fetch');
const API = 'http://localhost:1337/api';
const TOKEN = process.env.STRAPI_TOKEN;

async function createEntry(collection, data) {
  const res = await fetch(`${API}/${collection}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` },
    body: JSON.stringify({ data }),
  });
  return res.json();
}
```

---

## Known Gotchas

- Strapi's Dynamic Zones have a max component limit configurable in `config/server.js` (default is reasonable but may need increasing for paragraph-heavy content).
- Strapi v4 REST responses are wrapped in `{ data: { id, attributes } }` format. V5 simplifies this.
- Relations require the target entry's ID. Import in dependency order.
- Strapi's media upload is separate from content creation. Upload files first, then reference by ID.
- Rich text in Strapi v4 is Markdown by default. The Blocks editor (v5) or CKEditor plugin offer structured rich text. Choose before import.
- Rate limiting and request size limits may need configuration for bulk imports. Set `config/middlewares.js` body parser limit higher.
- Custom components and dynamic zones cannot be created via the API in Strapi v4 — define them in code before importing content.
