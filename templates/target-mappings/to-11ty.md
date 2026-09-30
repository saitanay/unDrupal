# Target Mapping Guide: Drupal to Eleventy (11ty)

**Target platform:** Eleventy 3.x (or 2.x)
**Last updated:** 2024-01-15

---

## Platform Overview

Eleventy (11ty) is a lightweight, JavaScript-based static site generator. It supports multiple template languages (Nunjucks, Liquid, Markdown, JavaScript, WebC). Content comes from Markdown files, data files (JSON/YAML/JS), or CMS APIs. Eleventy is intentionally minimal — it generates HTML and stays out of the way.

### Key Architectural Differences from Drupal

| Concept | Drupal | Eleventy |
|---|---|---|
| Content types | Entity bundles | Collections (tag-based or directory-based) |
| Fields | Field API | Front matter + data cascade |
| Taxonomy | Vocabulary + terms | Collections or front matter tags |
| Media | Media entity | Static files in passthrough dirs |
| Paragraphs | Paragraph bundles | Shortcodes, includes, or data-driven partials |
| Rich text | CKEditor HTML | Markdown or HTML templates |
| URL aliases | Path alias | Permalink front matter |
| Views | Views module | Collections + Nunjucks/Liquid filters |
| Users | User entity | No user system |
| Revisions | Entity revisions | Git history |
| Multilingual | Content translation | i18n plugin (built-in in 2.x+) |

---

## Content Type Mapping

### Drupal Nodes → Eleventy Collections

Organize content by directory and tag as collections:

```
src/
  articles/
    articles.json          # Directory data file: {"layout": "article.njk", "tags": ["articles"]}
    hello-world.md
    another-post.md
  pages/
    pages.json             # {"layout": "page.njk", "tags": ["pages"]}
    about.md
    contact.md
```

Front matter defines metadata:

```yaml
---
title: "Hello World"
date: 2024-01-15
slug: "hello-world"
summary: "A brief introduction."
author: "Jane Doe"
categories: ["news"]
featuredImage: "/images/hero.jpg"
permalink: "/blog/{{ slug }}/"
---

Article body in Markdown here.
```

### Field Type Mapping

| Drupal Field Type | Eleventy Front Matter | Notes |
|---|---|---|
| text / string | String value | |
| text_long | Markdown body content | Below front matter |
| text_with_summary | `summary` field + body | Or use excerpt separator `---` |
| integer | Number | |
| decimal / float | Number | |
| boolean | Boolean | |
| datetime | Date string | YAML date or ISO 8601 |
| email | String | |
| link | `{ url, title }` | |
| list_string | String | |
| entity_reference (node) | Slug string | Resolve via collection lookup |
| entity_reference (term) | Array of strings | `categories: ["news"]` |
| image | File path string | |
| file | File path string | Copy to output dir |
| entity_reference_revisions | Front matter data array | See Paragraphs section |

---

## Taxonomy Mapping

### Option A: Front Matter Tags + Collection

Use front matter arrays and Eleventy's collection API:

```yaml
categories: ["news", "tutorials"]
tags: ["articles"]  # 11ty collection tag
```

Generate taxonomy pages using pagination:

```yaml
---
# src/categories.njk
pagination:
  data: collections
  size: 1
  alias: tag
  filter: ["all", "articles", "pages"]
permalink: "/categories/{{ tag }}/"
---
<h1>{{ tag }}</h1>
{% for post in collections[tag] %}
  <a href="{{ post.url }}">{{ post.data.title }}</a>
{% endfor %}
```

### Option B: Global Data File

For vocabularies with metadata:

```json
// src/_data/categories.json
[
  { "name": "News", "slug": "news", "description": "Latest updates" },
  { "name": "Tutorials", "slug": "tutorials", "description": "How-to guides" }
]
```

---

## Paragraph / Component Mapping

### Shortcodes

Register shortcodes in `.eleventy.js`:

```js
// .eleventy.js
module.exports = function(eleventyConfig) {
  eleventyConfig.addShortcode("hero", function(heading, image, ctaUrl, ctaLabel) {
    return `<section class="hero" style="background-image: url('${image}')">
      <h1>${heading}</h1>
      ${ctaUrl ? `<a href="${ctaUrl}">${ctaLabel}</a>` : ''}
    </section>`;
  });
};
```

Use in Markdown:

```markdown
{% hero "Welcome", "/images/hero.jpg", "/contact", "Get in touch" %}
```

### Data-Driven Components

Store component data in front matter and render in the layout:

```yaml
components:
  - type: hero
    heading: "Welcome"
    image: "/images/hero.jpg"
  - type: textBlock
    body: "Lorem ipsum..."
```

```njk
{# layouts/article.njk #}
{% for component in components %}
  {% include "components/" + component.type + ".njk" %}
{% endfor %}
```

Use `flatten-paragraphs.py` output to prepare the component data.

---

## Media Mapping

Configure passthrough copy in `.eleventy.js`:

```js
eleventyConfig.addPassthroughCopy("src/images");
eleventyConfig.addPassthroughCopy("src/files");
```

| Drupal Media Type | Eleventy | Notes |
|---|---|---|
| image | `src/images/` passthrough | Use `eleventy-img` plugin for optimization |
| document | `src/files/` passthrough | |
| remote_video | Embed shortcode | |
| audio | `src/audio/` passthrough | |

### Image Optimization

```js
const Image = require("@11ty/eleventy-img");

eleventyConfig.addShortcode("image", async function(src, alt) {
  let metadata = await Image(src, { widths: [300, 600, 900], formats: ["webp", "jpeg"] });
  return Image.generateHTML(metadata, { alt, loading: "lazy" });
});
```

---

## URL and Redirect Mapping

1. Set `permalink` in front matter to control output paths.
2. Map Drupal path aliases to permalink values.
3. Use directory data files to set permalink patterns for entire collections:

```json
// src/articles/articles.json
{ "permalink": "/blog/{{ page.fileSlug }}/" }
```

4. Use `generate-redirects.py` with the format matching your host (netlify, vercel, cloudflare).
5. Eleventy does not generate redirect pages natively. Use the `eleventy-plugin-redirects` community plugin or generate hosting-specific redirect files.

---

## Querying Content (Views Replacement)

Eleventy collections replace Drupal Views:

```js
// .eleventy.js
eleventyConfig.addCollection("recentArticles", function(collectionApi) {
  return collectionApi.getFilteredByTag("articles")
    .filter(item => !item.data.draft)
    .sort((a, b) => b.date - a.date)
    .slice(0, 10);
});
```

```njk
{# In a template #}
{% for post in collections.recentArticles %}
  <a href="{{ post.url }}">{{ post.data.title }}</a>
{% endfor %}
```

For paginated listing pages:

```yaml
---
pagination:
  data: collections.articles
  size: 10
  reverse: true
permalink: "/blog/{% if pagination.pageNumber > 0 %}page/{{ pagination.pageNumber + 1 }}/{% endif %}"
---
```

---

## Multilingual Content

Eleventy supports i18n via the `i18n` plugin (built-in since 2.0):

```js
const { EleventyI18nPlugin } = require("@11ty/eleventy");
eleventyConfig.addPlugin(EleventyI18nPlugin, { defaultLanguage: "en" });
```

Content structure:

```
src/
  en/
    articles/
      hello-world.md
  fr/
    articles/
      hello-world.md
```

Pages are linked by matching file paths across language directories.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML body fields to Markdown (using `turndown` or `pandoc`).
4. Generate one `.md` file per entity with YAML front matter.
5. Create directory data files (`articles.json`) to set shared defaults.
6. Download media to `src/images/` and `src/files/`.
7. Run `validate-export.py` on intermediate JSON before generating Markdown.
8. Build with `npx @11ty/eleventy` and verify output.
9. Run the validation checklist.

---

## Known Gotchas

- Eleventy has no built-in CMS admin. Editors need Decap CMS, Tina, or direct Markdown editing.
- Template language choice (Nunjucks, Liquid, etc.) affects shortcode syntax. Pick one and be consistent.
- Eleventy processes Markdown with `markdown-it`. Complex Drupal HTML may need custom `markdown-it` plugins or direct HTML passthrough.
- Collections are computed at build time from all content. Very complex cross-references (e.g., bidirectional entity references) need custom collection logic.
- Eleventy has no built-in image optimization. The `eleventy-img` plugin is recommended but must be set up separately.
- Global data files in `_data/` are available in all templates. Use this for shared data (site config, navigation, taxonomy metadata) rather than duplicating in front matter.
- Hot reload in dev mode (`--serve`) is fast, but full rebuilds on large sites (10K+ pages) can take minutes. Use computed data and pagination wisely.
