# Target Mapping Guide: Drupal to Payload CMS

**Target platform:** Payload CMS 3.x (Next.js native)
**Last updated:** 2024-01-15

---

## Platform Overview

Payload CMS is an open-source, TypeScript-first headless CMS that runs as a Next.js application. Content is defined through code-based collection configs. It supports MongoDB or PostgreSQL, has built-in auth, file uploads, rich text (Lexical or Slate), versioning, and access control. You self-host it.

### Key Architectural Differences from Drupal

| Concept | Drupal | Payload CMS |
|---|---|---|
| Content types | Entity bundles | Collections |
| Fields | Field API | Collection field configs (TypeScript) |
| Taxonomy | Vocabulary + terms | Collection with relationship fields |
| Media | Media entity | Upload collection |
| Paragraphs | Paragraph bundles | Blocks field or array field |
| Rich text | CKEditor HTML | Lexical editor (structured JSON) |
| URL aliases | Path alias | Slug field + Next.js routing |
| Views | Views module | `find()` queries with where clauses |
| Users | User entity | Auth-enabled collection |
| Revisions | Entity revisions | Built-in versioning with drafts |
| Multilingual | Content translation | Built-in localization |
| Access control | Permissions + roles | Field and collection-level access functions |

---

## Content Type Mapping

### Drupal Nodes → Payload Collections

Each Drupal content type becomes a Payload collection:

```ts
// src/collections/Articles.ts
import { CollectionConfig } from 'payload';

export const Articles: CollectionConfig = {
  slug: 'articles',
  admin: { useAsTitle: 'title' },
  versions: { drafts: true },
  fields: [
    { name: 'title', type: 'text', required: true },
    { name: 'slug', type: 'text', unique: true, required: true },
    { name: 'body', type: 'richText' },
    { name: 'summary', type: 'textarea' },
    { name: 'featuredImage', type: 'upload', relationTo: 'media' },
    { name: 'author', type: 'relationship', relationTo: 'authors' },
    { name: 'categories', type: 'relationship', relationTo: 'categories', hasMany: true },
    { name: 'publishedAt', type: 'date' },
  ],
};
```

### Field Type Mapping

| Drupal Field Type | Payload Field Type | Notes |
|---|---|---|
| text / string | `text` | |
| text_long | `textarea` | |
| text_with_summary | `richText` + `textarea` | Body → richText, summary → textarea |
| integer | `number` (integer) | |
| decimal / float | `number` | |
| boolean | `checkbox` | |
| datetime | `date` | |
| timestamp | `date` | Convert Unix → ISO 8601 |
| email | `email` | |
| link | `group { url: text, label: text }` | Or use `link` block type |
| list_string | `select` | Define options in config |
| entity_reference (node) | `relationship` | `relationTo: 'collection'` |
| entity_reference (term) | `relationship` | |
| image | `upload` | `relationTo: 'media'` |
| file | `upload` | `relationTo: 'media'` |
| entity_reference_revisions | `blocks` | See Paragraphs section |

---

## Taxonomy Mapping

Create a collection per Drupal vocabulary:

```ts
export const Categories: CollectionConfig = {
  slug: 'categories',
  admin: { useAsTitle: 'name' },
  fields: [
    { name: 'name', type: 'text', required: true },
    { name: 'slug', type: 'text', unique: true },
    { name: 'description', type: 'textarea' },
    { name: 'parent', type: 'relationship', relationTo: 'categories' },
  ],
};
```

Hierarchical terms are supported via self-referencing relationships.

---

## Paragraph / Component Mapping

Payload's `blocks` field is the direct equivalent of Drupal paragraphs:

```ts
{
  name: 'content',
  type: 'blocks',
  blocks: [
    {
      slug: 'heroBlock',
      fields: [
        { name: 'heading', type: 'text' },
        { name: 'subheading', type: 'textarea' },
        { name: 'backgroundImage', type: 'upload', relationTo: 'media' },
        { name: 'ctaLabel', type: 'text' },
        { name: 'ctaUrl', type: 'text' },
      ],
    },
    {
      slug: 'textBlock',
      fields: [
        { name: 'body', type: 'richText' },
      ],
    },
    {
      slug: 'imageGallery',
      fields: [
        { name: 'images', type: 'array', fields: [
          { name: 'image', type: 'upload', relationTo: 'media' },
          { name: 'caption', type: 'text' },
        ]},
      ],
    },
  ],
}
```

Use `flatten-paragraphs.py` output and map each component type to a Payload block slug. The `blockType` field in Payload corresponds to the paragraph bundle machine name.

---

## Media Mapping

Create a media upload collection:

```ts
export const Media: CollectionConfig = {
  slug: 'media',
  upload: {
    staticDir: 'media',
    imageSizes: [
      { name: 'thumbnail', width: 400, height: 300, position: 'centre' },
      { name: 'card', width: 768, height: 1024, position: 'centre' },
    ],
    mimeTypes: ['image/*', 'application/pdf', 'audio/*', 'video/*'],
  },
  fields: [
    { name: 'alt', type: 'text' },
    { name: 'caption', type: 'text' },
  ],
};
```

| Drupal Media Type | Payload | Notes |
|---|---|---|
| image | Upload (image) | Auto-resized per imageSizes |
| document | Upload (file) | |
| remote_video | Collection with URL field | Custom collection |
| audio | Upload (audio) | |

---

## URL and Redirect Mapping

1. Add a `slug` field to each collection.
2. Map Drupal path aliases to slug values.
3. Payload runs inside Next.js, so use Next.js routing: `app/(frontend)/[slug]/page.tsx`.
4. Use `generate-redirects.py --format nextjs` for `next.config.js` redirects.
5. Or implement redirects in a Payload global/collection for runtime management.

---

## Querying Content (Views Replacement)

Payload's Local API replaces Drupal Views:

```ts
// Server-side (same process)
const articles = await payload.find({
  collection: 'articles',
  where: {
    categories: { equals: categoryId },
    _status: { equals: 'published' },
  },
  sort: '-publishedAt',
  limit: 10,
  page: 1,
  depth: 2,  // resolve relationships 2 levels deep
});
```

REST API: `GET /api/articles?where[categories][equals]=id&sort=-publishedAt&limit=10`

---

## Multilingual Content

Payload has built-in localization:

```ts
// payload.config.ts
export default buildConfig({
  localization: {
    locales: ['en', 'fr', 'es'],
    defaultLocale: 'en',
    fallback: true,
  },
  // ...
});
```

Mark fields as localized: `{ name: 'title', type: 'text', localized: true }`. Each locale's value is stored in the same document.

Map Drupal translation sets to localized field values during import.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML to Lexical JSON (or use Payload's HTML-to-Lexical utility).
4. Write a seed script using Payload's Local API:

```ts
// seed.ts
import { getPayload } from 'payload';
import config from './payload.config';

const payload = await getPayload({ config });

// Upload media first
const mediaDoc = await payload.create({
  collection: 'media',
  data: { alt: 'Photo' },
  filePath: './exports/files/photo.jpg',
});

// Then create content
await payload.create({
  collection: 'articles',
  data: {
    title: 'Hello World',
    slug: 'hello-world',
    featuredImage: mediaDoc.id,
    body: lexicalContent,
  },
});
```

5. Run `validate-export.py` before import.
6. Verify with the validation checklist after import.

---

## Known Gotchas

- Payload's Lexical editor stores content as a JSON tree, not HTML. Converting complex Drupal markup requires a custom serializer.
- Payload 3.x requires Next.js 15+ (canary/RC). Check compatibility with your Next.js version.
- `blocks` field data is stored inline in the parent document (not as separate entities like Drupal paragraphs). Very large documents may have performance implications with MongoDB.
- Relationship fields store IDs. Import referenced documents before referencing documents.
- Payload's access control is function-based. Drupal's role-permission model needs to be translated to access functions.
- Self-hosting means you manage the database, file storage (local or S3), and deployment.
- No built-in CDN for media. Configure S3 + CloudFront or similar for production.
