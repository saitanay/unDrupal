# Target Mapping Guide: Drupal to Astro

**Target platform:** Astro 4.x+
**Last updated:** 2024-01-15

---

## Platform Overview

Astro is a static-first web framework that renders HTML at build time by default. It supports multiple UI frameworks (React, Vue, Svelte, Solid) via islands architecture — interactive components hydrate only where needed. Content can come from local Markdown/MDX files, a headless CMS, or any API. Astro has no built-in CMS; it is a presentation layer.

### Key Architectural Differences from Drupal

| Concept | Drupal | Astro |
|---|---|---|
| Content types | Entity bundles | Content collections (schema-validated) |
| Fields | Field API | Frontmatter schema (Zod) |
| Taxonomy | Vocabulary + terms | Collection or frontmatter tags |
| Media | Media entity | Static assets or remote images |
| Paragraphs | Paragraph bundles | MDX components or JSON data |
| Rich text | CKEditor HTML | Markdown / MDX / HTML |
| URL aliases | Path alias | File-based routing or dynamic routes |
| Views | Views module | `getCollection()` queries + filtering |
| Users | User entity | No built-in auth (add external) |
| Revisions | Entity revisions | Git history |
| Multilingual | Content translation | i18n routing (`src/pages/[lang]/`) |

---

## Content Type Mapping

### Drupal Nodes → Astro Content Collections

Define collections in `src/content/config.ts`:

```ts
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const articles = defineCollection({
  type: 'content',  // Markdown/MDX
  schema: ({ image }) => z.object({
    title: z.string(),
    summary: z.string().optional(),
    author: z.string(),
    categories: z.array(z.string()).default([]),
    featuredImage: image().optional(),
    publishedAt: z.coerce.date(),
    draft: z.boolean().default(false),
  }),
});

const pages = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    layout: z.string().optional(),
  }),
});

export const collections = { articles, pages };
```

Content files live under `src/content/articles/` as Markdown with frontmatter:

```markdown
---
title: "Hello World"
author: "Jane Doe"
categories: ["news", "announcements"]
featuredImage: "./images/hero.jpg"
publishedAt: 2024-01-15
---

Article body in Markdown here.
```

### Field Type Mapping

| Drupal Field Type | Astro / Zod Type | Notes |
|---|---|---|
| text / string | `z.string()` | |
| text_long | `z.string()` | Body is the Markdown content itself |
| text_with_summary | Markdown body + `z.string()` (summary) | Summary in frontmatter, body in content |
| integer | `z.number().int()` | |
| decimal / float | `z.number()` | |
| boolean | `z.boolean()` | |
| datetime | `z.coerce.date()` | |
| email | `z.string().email()` | |
| link | `z.object({ url, label })` | |
| list_string | `z.enum([...])` | |
| entity_reference (node) | `z.string()` (slug reference) | Resolve at build time |
| entity_reference (term) | `z.array(z.string())` | Tag strings or collection references |
| image | `image()` (content collection) | Local images optimized at build |
| file | Static asset path | Copy to `public/` |
| entity_reference_revisions | JSON data or MDX components | See Paragraphs section |

---

## Taxonomy Mapping

### Option A: Frontmatter Tags

For simple flat vocabularies, use string arrays in frontmatter:

```yaml
categories: ["news", "tutorials"]
tags: ["drupal", "migration"]
```

Generate tag index pages with `getCollection()`:

```astro
---
// src/pages/tags/[tag].astro
export async function getStaticPaths() {
  const posts = await getCollection('articles');
  const tags = [...new Set(posts.flatMap(p => p.data.tags))];
  return tags.map(tag => ({ params: { tag }, props: { posts: posts.filter(p => p.data.tags.includes(tag)) } }));
}
---
```

### Option B: Separate Collection

For vocabularies with descriptions, hierarchy, or custom fields, create a data collection:

```ts
const categories = defineCollection({
  type: 'data',  // JSON/YAML
  schema: z.object({
    name: z.string(),
    slug: z.string(),
    description: z.string().optional(),
    parent: z.string().optional(),
  }),
});
```

---

## Paragraph / Component Mapping

### MDX Components

Convert Drupal paragraphs to MDX component usage:

```mdx
---
title: "About Us"
---

<Hero heading="Welcome" backgroundImage="./hero.jpg" />

Our story begins...

<ImageGallery images={["./img1.jpg", "./img2.jpg"]} />

<CallToAction label="Contact Us" url="/contact" />
```

### JSON Data + Astro Components

Alternatively, store component data in frontmatter or a JSON data collection and render with Astro components:

```yaml
# frontmatter
components:
  - type: hero
    heading: "Welcome"
    backgroundImage: "./hero.jpg"
  - type: textBlock
    body: "Our story begins..."
```

```astro
---
// Dynamic component rendering
import Hero from '../components/Hero.astro';
import TextBlock from '../components/TextBlock.astro';
const componentMap = { hero: Hero, textBlock: TextBlock };
---
{entry.data.components.map(c => {
  const Component = componentMap[c.type];
  return Component ? <Component {...c} /> : null;
})}
```

Use `flatten-paragraphs.py` to prepare the component data.

---

## Media Mapping

| Drupal Media Type | Astro | Notes |
|---|---|---|
| image | `src/content/` co-located or `src/assets/` | Optimized via `<Image />` component |
| document | `public/files/` | Served as-is |
| remote_video | Embed URL in frontmatter | Render with iframe or component |
| audio | `public/audio/` | |

### Image Optimization

```astro
---
import { Image } from 'astro:assets';
---
<Image src={entry.data.featuredImage} alt={entry.data.title} width={800} />
```

Remote images need explicit `domains` in `astro.config.mjs`.

---

## URL and Redirect Mapping

1. File-based routing: `src/pages/blog/[slug].astro` generates `/blog/hello-world`.
2. Map Drupal path aliases to content file names or slug frontmatter fields.
3. Use `generate-redirects.py --format netlify` or `--format vercel` depending on hosting.
4. Or use Astro's built-in redirects in `astro.config.mjs`:

```js
export default defineConfig({
  redirects: {
    '/node/123': '/blog/hello-world',
    '/old-path': '/new-path',
  },
});
```

---

## Querying Content (Views Replacement)

Use `getCollection()` and JavaScript filtering:

```astro
---
import { getCollection } from 'astro:content';

const allArticles = await getCollection('articles', ({ data }) => !data.draft);
const sorted = allArticles.sort((a, b) => b.data.publishedAt.valueOf() - a.data.publishedAt.valueOf());
const paginated = sorted.slice(0, 10);
---
```

For paginated listing pages, use Astro's `paginate()` in `getStaticPaths()`.

---

## Multilingual Content

Astro supports i18n routing:

```js
// astro.config.mjs
export default defineConfig({
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'fr', 'es'],
    routing: { prefixDefaultLocale: false },
  },
});
```

Organize translated content in locale subdirectories:
```
src/content/articles/en/hello-world.md
src/content/articles/fr/hello-world.md
```

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML body fields to Markdown (using a library like `turndown`).
4. Generate one `.md` or `.mdx` file per entity with frontmatter matching the collection schema.
5. Download media files to `src/content/` (co-located) or `src/assets/`.
6. Run `validate-export.py` on the intermediate JSON before generating Markdown.
7. Build with `astro build` and verify output.
8. Run the validation checklist.

### Conversion Script Pattern

```js
import TurndownService from 'turndown';
import fs from 'fs';
const td = new TurndownService();

for (const entity of exportData) {
  const frontmatter = `---\ntitle: "${entity.title}"\npublishedAt: ${entity.created}\n---\n`;
  const body = td.turndown(entity.body_value);
  fs.writeFileSync(`src/content/articles/${entity.slug}.md`, frontmatter + body);
}
```

---

## Known Gotchas

- Astro is static by default. Dynamic features (search, comments, auth) need client-side JS islands or external services.
- Content collection schema validation runs at build time. Import data must match the Zod schema or the build fails.
- MDX components must be imported in each file. For bulk migration, the JSON-in-frontmatter approach is easier to automate.
- Astro's `<Image />` component requires local images in `src/`. Images in `public/` are not optimized.
- Large sites (10K+ pages) may have long build times. Consider incremental builds or SSR mode for very large migrations.
- No built-in CMS admin. Editors need a separate tool (Tina, Decap CMS, or a headless CMS API).
