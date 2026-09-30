# Target Mapping Guide: Drupal to Next.js + Contentful

**Target platform:** Next.js 14+ with Contentful as headless CMS
**Last updated:** 2024-01-15

---

## Platform Overview

Contentful is a headless CMS with a structured content model, REST and GraphQL APIs, and a web-based editorial interface. Content is organized into Spaces, Environments, Content Types, and Entries. Next.js fetches content at build time (SSG) or request time (SSR/ISR) via the Contentful SDK or GraphQL.

### Key Architectural Differences from Drupal

| Concept | Drupal | Contentful + Next.js |
|---|---|---|
| Content types | Entity bundles | Content Types |
| Fields | Field API | Content Type fields |
| Taxonomy | Vocabulary + terms | Content Type with references, or tags |
| Media | Media entity + file | Asset (image, file, video) |
| Paragraphs | Paragraph bundles | Rich Text embedded entries or linked entries |
| Rich text | CKEditor HTML | Rich Text (structured JSON) |
| URL aliases | Path alias | Slug field + Next.js routing |
| Views | Views module | API queries with filters |
| Revisions | Entity revisions | Entry versioning (draft/published) |
| Multilingual | Content translation | Locales (built-in) |

---

## Content Type Mapping

### Drupal Nodes → Contentful Content Types

Create one Contentful Content Type per Drupal content type. Use the Contentful web UI, CLI, or Migration API:

```js
// migrations/01-create-article.js (Contentful Migration script)
module.exports = function (migration) {
  const article = migration.createContentType('article')
    .name('Article')
    .displayField('title');

  article.createField('title').type('Symbol').name('Title').required(true);
  article.createField('slug').type('Symbol').name('Slug').required(true).validations([{ unique: true }]);
  article.createField('body').type('RichText').name('Body');
  article.createField('summary').type('Text').name('Summary');
  article.createField('featuredImage').type('Link').name('Featured Image').linkType('Asset');
  article.createField('author').type('Link').name('Author').linkType('Entry').validations([{ linkContentType: ['author'] }]);
  article.createField('categories').type('Array').name('Categories').items({ type: 'Link', linkType: 'Entry', validations: [{ linkContentType: ['category'] }] });
  article.createField('publishDate').type('Date').name('Publish Date');
};
```

### Field Type Mapping

| Drupal Field Type | Contentful Field Type | Notes |
|---|---|---|
| text / string | Symbol (short) | Max 256 chars |
| text_long | Text (long) | |
| text_with_summary | RichText + Text | Body → Rich Text, summary → Text |
| integer | Integer | |
| decimal / float | Number | |
| boolean | Boolean | |
| datetime | Date | ISO 8601 |
| timestamp | Date | Convert Unix → ISO 8601 |
| email | Symbol with regex validation | |
| link | Object (JSON) or Symbol | No native link field; use JSON or two fields |
| list_string | Symbol with in-list validation | |
| entity_reference (node) | Link (Entry) | Specify allowed content types |
| entity_reference (term) | Link (Entry) or tags | |
| image | Link (Asset) | Upload to Contentful |
| file | Link (Asset) | |
| entity_reference_revisions | RichText embedded entries or Array of Links | See Paragraphs section |

---

## Taxonomy Mapping

Contentful has no dedicated taxonomy feature. Options:

### Option A: Content Type + References

Create a `Category` content type and reference it from other content types:

```js
const category = migration.createContentType('category')
  .name('Category')
  .displayField('name');

category.createField('name').type('Symbol').name('Name').required(true);
category.createField('slug').type('Symbol').name('Slug');
category.createField('description').type('Text').name('Description');
category.createField('parent').type('Link').name('Parent').linkType('Entry')
  .validations([{ linkContentType: ['category'] }]);
```

### Option B: Contentful Tags

Use Contentful's built-in tagging (metadata tags) for flat vocabularies. Limited to simple labels — no descriptions, hierarchy, or custom fields.

---

## Paragraph / Component Mapping

### Rich Text Embedded Entries

Contentful Rich Text supports embedded entries (block and inline). Map Drupal paragraph types to content types that are embedded within Rich Text fields:

1. Create a content type per paragraph type (e.g., `heroBlock`, `callToAction`, `imageGallery`).
2. When converting content, insert `embedded-entry-block` nodes in the Rich Text JSON referencing those entries.
3. In Next.js, use `documentToReactComponents` with custom renderers for each embedded type.

### Array of Linked Entries

Alternatively, create a `components` field as an Array of Links:

```js
article.createField('components')
  .type('Array')
  .name('Components')
  .items({
    type: 'Link',
    linkType: 'Entry',
    validations: [{ linkContentType: ['heroBlock', 'textBlock', 'imageBlock'] }]
  });
```

Use `flatten-paragraphs.py` to prepare the component data, then create an Entry per component and link them in order.

---

## Media Mapping

| Drupal Media Type | Contentful | Notes |
|---|---|---|
| image | Asset (image) | Auto-optimized via Contentful Images API |
| document | Asset (file) | |
| remote_video | Entry with URL field | Or embed in Rich Text |
| audio | Asset (file) | |

### Upload Process

```bash
# Using Contentful CLI
contentful space import --content-file export.json --space-id $SPACE_ID

# Or via Management API
const asset = await environment.createAssetFromFiles({
  fields: { title: { 'en-US': 'Photo' }, file: { 'en-US': { fileName, contentType, file: stream } } }
});
await asset.processForAllLocales();
await asset.publish();
```

---

## URL and Redirect Mapping

1. Add a `slug` field to each content type.
2. Map Drupal path aliases to slug values.
3. Next.js dynamic routes: `app/[slug]/page.tsx` or `app/blog/[slug]/page.tsx`.
4. Use `generate-redirects.py --format nextjs` or `--format vercel` for redirect config.
5. Vercel: `vercel.json` redirects. Netlify: `_redirects` file.

---

## Querying Content (Views Replacement)

Replace Drupal Views with Contentful API queries:

```js
// Using Contentful JS SDK
const entries = await client.getEntries({
  content_type: 'article',
  order: '-fields.publishDate',
  'fields.categories.sys.id': categoryId,
  limit: 10,
  skip: offset,
  include: 2,  // resolve 2 levels of linked entries
});
```

Or use GraphQL:

```graphql
query {
  articleCollection(order: publishDate_DESC, limit: 10) {
    items {
      title
      slug
      publishDate
      categoriesCollection { items { name slug } }
      featuredImage { url width height }
    }
  }
}
```

---

## Multilingual Content

Contentful has built-in locale support. Each field value can be localized:

```json
{
  "fields": {
    "title": {
      "en-US": "Hello World",
      "fr": "Bonjour le monde"
    }
  }
}
```

1. Create locales in Contentful matching Drupal's language codes.
2. Mark fields as localized in the content type definition.
3. Import each translation as a locale-specific field value on the same entry.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML to Contentful Rich Text JSON using `@contentful/rich-text-html-parser`.
4. Shape data into Contentful import format (content types + entries + assets).
5. Run migrations to create content types first.
6. Upload assets, capture asset IDs.
7. Import entries: `contentful space import --content-file data.json`.
8. Run `validate-export.py` before import.
9. Verify with the validation checklist after import.

### Rate Limits

Contentful Management API: 10 requests/second (free), higher on paid plans. Use the `contentful-batch-libs` for throttled bulk import.

---

## Known Gotchas

- Contentful `Symbol` fields have a 256-character limit. Long Drupal text fields must use `Text` type.
- Rich Text JSON structure is not HTML. Converting complex Drupal HTML (tables, nested divs, embedded media) requires custom transformation.
- Reference fields require the target entry to exist before the referencing entry. Import order matters.
- Contentful has a 50 field limit per content type. Consolidate Drupal fields if needed.
- Entry payload max size is 500KB. Very large paragraph-heavy content may need restructuring.
- Contentful's free tier: 1 space, 5 users, 25K entries. Check limits before starting.
- Webhook-based revalidation (ISR) setup is needed for Next.js to reflect content changes.
