# Target Mapping Guide: Drupal to Next.js + Sanity

**Target platform:** Next.js 14+ with Sanity.io as headless CMS
**Last updated:** 2024-01-15

---

## Platform Overview

Sanity is a headless CMS with a real-time content lake and customizable editing studio. Content is stored as structured JSON documents with a schema defined in JavaScript/TypeScript. Next.js consumes content via GROQ queries or the Sanity client SDK.

### Key Architectural Differences from Drupal

| Concept | Drupal | Sanity + Next.js |
|---|---|---|
| Content types | Entity bundles | Document types (schema.js) |
| Fields | Field API | Schema field definitions |
| Taxonomy | Vocabulary + terms | Document type or string tags |
| Media | Media entity | Image/file assets in CDN |
| Paragraphs | Paragraph bundles | Portable Text blocks or object arrays |
| Rich text | CKEditor filtered HTML | Portable Text (structured) |
| URL aliases | Path alias | Slug field + Next.js routing |
| Views | Views module | GROQ queries |
| Users | User entity | Sanity users (studio) or custom |
| Revisions | Entity revisions | Built-in document history |
| Multilingual | Content translation | i18n document pattern or field-level |

---

## Content Type Mapping

### Drupal Nodes → Sanity Document Types

Each Drupal content type maps to a Sanity document type definition:

```js
// schemas/article.js
export default {
  name: 'article',
  title: 'Article',
  type: 'document',
  fields: [
    { name: 'title', title: 'Title', type: 'string' },
    { name: 'slug', title: 'Slug', type: 'slug', options: { source: 'title' } },
    { name: 'body', title: 'Body', type: 'portableText' },
    { name: 'author', title: 'Author', type: 'reference', to: [{ type: 'author' }] },
    { name: 'categories', title: 'Categories', type: 'array', of: [{ type: 'reference', to: [{ type: 'category' }] }] },
    { name: 'publishedAt', title: 'Published At', type: 'datetime' },
    { name: 'image', title: 'Featured Image', type: 'image', options: { hotspot: true } },
  ],
}
```

### Field Type Mapping

| Drupal Field Type | Sanity Field Type | Notes |
|---|---|---|
| text / string | `string` | |
| text_long | `text` | Plain multiline text |
| text_with_summary | `portableText` (custom) | Convert HTML to Portable Text |
| integer | `number` | |
| decimal / float | `number` | |
| boolean | `boolean` | |
| datetime | `datetime` | |
| timestamp | `datetime` | Convert Unix → ISO 8601 |
| email | `string` with validation | |
| link | `object { url, title }` | Custom object type |
| list_string | `string` with options list | |
| entity_reference (node) | `reference` | `to: [{ type: 'docType' }]` |
| entity_reference (term) | `reference` | Or inline string for simple tags |
| image | `image` | Sanity handles CDN + transforms |
| file | `file` | |
| entity_reference_revisions | `array` of typed objects | See Paragraphs section |

---

## Taxonomy Mapping

Sanity has no built-in taxonomy system. Two approaches:

### Option A: Reference Documents

Create a `category` document type and use references:

```js
// schemas/category.js
export default {
  name: 'category',
  title: 'Category',
  type: 'document',
  fields: [
    { name: 'title', type: 'string' },
    { name: 'slug', type: 'slug', options: { source: 'title' } },
    { name: 'description', type: 'text' },
    { name: 'parent', type: 'reference', to: [{ type: 'category' }] },
  ],
}
```

### Option B: String Tags

For flat vocabularies (like Drupal tags), use a string array:

```js
{ name: 'tags', type: 'array', of: [{ type: 'string' }], options: { layout: 'tags' } }
```

---

## Paragraph / Component Mapping

### Portable Text

Drupal's rich text (filtered HTML) should be converted to Sanity's Portable Text format. Use a library like `@sanity/block-tools` or `html-to-portable-text` to convert.

### Structured Components (Paragraphs → Object Arrays)

Map Drupal paragraph types to Sanity block-level objects within a Portable Text field or a separate `components` array:

```js
// schemas/objects/heroBlock.js
export default {
  name: 'heroBlock',
  title: 'Hero',
  type: 'object',
  fields: [
    { name: 'heading', type: 'string' },
    { name: 'subheading', type: 'text' },
    { name: 'backgroundImage', type: 'image' },
    { name: 'cta', type: 'object', fields: [
      { name: 'label', type: 'string' },
      { name: 'url', type: 'url' },
    ]},
  ],
}
```

Use `flatten-paragraphs.py` output to produce the component array, then map each component type to a Sanity object type.

---

## Media Mapping

| Drupal Media Type | Sanity Type | Notes |
|---|---|---|
| image | `image` asset | Upload via Sanity client; auto-CDN |
| document | `file` asset | |
| remote_video | `object { url, provider }` | Or use MUX integration |
| audio | `file` asset | |

### Upload Process

```bash
# Using Sanity CLI
sanity dataset import media-export.ndjson production

# Or via API
sanity client.assets.upload('image', fs.createReadStream(filePath))
```

---

## URL and Redirect Mapping

1. Define a `slug` field on each document type.
2. Map Drupal path aliases to slug values (strip leading `/`).
3. Configure Next.js dynamic routes: `app/[slug]/page.tsx` or `app/blog/[slug]/page.tsx`.
4. Use `generate-redirects.py --format nextjs` to produce `next.config.js` redirects.
5. Deploy redirects in `next.config.js`:

```js
module.exports = {
  async redirects() {
    return [
      { source: '/node/:id', destination: '/:slug', permanent: true },
      // ...generated redirects
    ]
  },
}
```

---

## Querying Content (Views Replacement)

Replace Drupal Views with GROQ queries:

```groq
// All articles, sorted by date, with category references resolved
*[_type == "article"] | order(publishedAt desc) {
  title,
  slug,
  publishedAt,
  "categories": categories[]->{ title, slug },
  "imageUrl": image.asset->url
}
```

Use the `views-to-query.py` output as a reference for which fields and filters each View requires.

---

## Multilingual Content

Sanity supports two i18n patterns:

1. **Document-level:** Separate documents per language, linked by a `__i18n_base` reference. Use `@sanity/document-internationalization` plugin.
2. **Field-level:** Localized fields within one document. Use `sanity-plugin-intl-input`.

Map Drupal's translation relationships to whichever pattern you choose.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML body fields to Portable Text.
4. Shape data into Sanity NDJSON format (one JSON object per line, each with `_type` and `_id`).
5. Upload media assets first, capture asset references.
6. Import content documents: `sanity dataset import content.ndjson production`.
7. Run `validate-export.py` before import.
8. Verify with the validation checklist after import.

### NDJSON Format Example

```json
{"_type": "article", "_id": "article-123", "title": "Hello World", "slug": {"_type": "slug", "current": "hello-world"}, "body": [...portableText...]}
```

---

## Known Gotchas

- Sanity's free tier has usage limits (datasets, API calls, bandwidth). Check pricing for large migrations.
- Portable Text conversion from complex Drupal HTML (tables, embedded entities, inline media) requires careful custom serialization.
- Sanity references use `_ref` IDs. Plan your ID scheme before import (e.g., `drupal-node-{nid}`).
- GROQ has no JOIN — use references and dereference with `->`. Deeply nested queries can be slow.
- Image hotspot/crop metadata has no Drupal equivalent. Set defaults or skip.
- Sanity schema changes require redeployment of the studio. Plan the schema before bulk import.
