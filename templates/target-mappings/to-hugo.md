# Target Mapping Guide: Drupal to Hugo

**Target platform:** Hugo 0.120+
**Last updated:** 2024-01-15

---

## Platform Overview

Hugo is a fast static site generator written in Go. Content is authored as Markdown files with YAML/TOML/JSON front matter. Hugo uses Go's `html/template` and `text/template` for layouts. It has no runtime server — the output is static HTML, CSS, and JS served from any CDN or file host.

### Key Architectural Differences from Drupal

| Concept | Drupal | Hugo |
|---|---|---|
| Content types | Entity bundles | Content types (directory-based sections + archetypes) |
| Fields | Field API | Front matter key-value pairs |
| Taxonomy | Vocabulary + terms | Taxonomies (built-in, configurable) |
| Media | Media entity | Static files in `static/` or page bundles |
| Paragraphs | Paragraph bundles | Shortcodes or data-driven partials |
| Rich text | CKEditor HTML | Markdown + shortcodes |
| URL aliases | Path alias | Slug / url front matter + permalink config |
| Views | Views module | List templates + taxonomy pages |
| Users | User entity | No user system (add external auth) |
| Revisions | Entity revisions | Git history |
| Multilingual | Content translation | Built-in i18n (content dirs per language) |

---

## Content Type Mapping

### Drupal Nodes → Hugo Sections

Each Drupal content type maps to a Hugo content section (a directory under `content/`):

```
content/
  articles/
    hello-world.md
    another-post.md
  pages/
    about.md
    contact.md
  events/
    _index.md
    event-one.md
```

Front matter defines metadata:

```yaml
---
title: "Hello World"
date: 2024-01-15T10:00:00Z
draft: false
slug: "hello-world"
summary: "A brief introduction."
author: "Jane Doe"
categories: ["news"]
tags: ["drupal", "migration"]
featured_image: "/images/hero.jpg"
---

Article body in Markdown here.
```

### Field Type Mapping

| Drupal Field Type | Hugo Front Matter | Notes |
|---|---|---|
| text / string | String value | |
| text_long | Markdown body | Content below front matter |
| text_with_summary | `summary` + body | Summary in front matter or `<!--more-->` |
| integer | Number | |
| decimal / float | Number | |
| boolean | Boolean | |
| datetime | ISO 8601 date string | Hugo parses dates natively |
| email | String | |
| link | `{ url, title }` object | Or separate fields |
| list_string | String | |
| entity_reference (node) | Slug string or related content | Use `.GetPage` in templates |
| entity_reference (term) | Taxonomy values | `categories: ["news"]` |
| image | File path | Page bundle or `static/` path |
| file | File path | |
| entity_reference_revisions | Shortcodes or front matter data | See Paragraphs section |

---

## Taxonomy Mapping

Hugo has first-class taxonomy support. Configure in `hugo.toml`:

```toml
[taxonomies]
  category = "categories"
  tag = "tags"
  author = "authors"
```

- Assign terms in front matter: `categories: ["news", "tutorials"]`
- Hugo auto-generates list pages at `/categories/`, `/categories/news/`, etc.
- Term pages can have their own content at `content/categories/news/_index.md`.
- Hierarchical terms: Hugo supports nested sections but not native parent-child term relationships. Flatten or simulate with front matter `parent` field + custom template logic.

---

## Paragraph / Component Mapping

Hugo has no paragraph/component system. Options:

### Option A: Shortcodes

Create shortcodes for each paragraph type:

```html
<!-- layouts/shortcodes/hero.html -->
<section class="hero" style="background-image: url('{{ .Get "image" }}')">
  <h1>{{ .Get "heading" }}</h1>
  <p>{{ .Get "subheading" }}</p>
  {{ if .Get "cta_url" }}
    <a href="{{ .Get "cta_url" }}">{{ .Get "cta_label" }}</a>
  {{ end }}
</section>
```

Use in Markdown:

```markdown
{{</* hero heading="Welcome" subheading="Our story" image="/images/hero.jpg" cta_url="/contact" cta_label="Get in touch" */>}}
```

### Option B: Data-Driven Partials

Store component data in front matter and render with partials:

```yaml
components:
  - type: hero
    heading: "Welcome"
    image: "/images/hero.jpg"
  - type: text_block
    body: "Lorem ipsum..."
  - type: image_gallery
    images: ["/img1.jpg", "/img2.jpg"]
```

```html
<!-- layouts/_default/single.html -->
{{ range .Params.components }}
  {{ partial (printf "components/%s.html" .type) . }}
{{ end }}
```

Use `flatten-paragraphs.py` to prepare the component data for front matter.

---

## Media Mapping

### Page Bundles (Recommended)

Co-locate media with content:

```
content/articles/hello-world/
  index.md
  hero.jpg
  document.pdf
```

Reference in Markdown: `![Hero](hero.jpg)` or in front matter: `featured_image: "hero.jpg"`.

### Static Directory

Global media in `static/images/`, `static/files/`, etc. Referenced as `/images/photo.jpg`.

| Drupal Media Type | Hugo | Notes |
|---|---|---|
| image | Page bundle resource or `static/` | Use Hugo image processing for resize/crop |
| document | `static/files/` | |
| remote_video | Shortcode with embed URL | |
| audio | `static/audio/` or page bundle | |

---

## URL and Redirect Mapping

Configure permalink patterns in `hugo.toml`:

```toml
[permalinks]
  articles = "/blog/:slug/"
  pages = "/:slug/"
```

For individual overrides, set `url` in front matter: `url: "/custom-path/"`.

### Redirects

Hugo supports aliases (client-side redirect pages):

```yaml
aliases:
  - /node/123
  - /old-path/article-name
```

For server-side redirects, use `generate-redirects.py` with the format matching your hosting (nginx, netlify, vercel, cloudflare).

---

## Querying Content (Views Replacement)

Hugo replaces Views with list templates and `where`/`sort` functions:

```html
<!-- List all articles sorted by date -->
{{ range where .Site.RegularPages "Type" "articles" | sort ".Date" "desc" }}
  <article>
    <h2><a href="{{ .Permalink }}">{{ .Title }}</a></h2>
    <time>{{ .Date.Format "January 2, 2006" }}</time>
    <p>{{ .Summary }}</p>
  </article>
{{ end }}
```

```html
<!-- Filter by taxonomy -->
{{ range where .Site.RegularPages "Params.categories" "intersect" (slice "news") }}
  ...
{{ end }}
```

For more complex queries, use Hugo's `resources.GetRemote` or pre-build data files.

---

## Multilingual Content

Hugo has built-in multilingual support:

```toml
defaultContentLanguage = "en"

[languages]
  [languages.en]
    title = "My Site"
    weight = 1
  [languages.fr]
    title = "Mon Site"
    weight = 2
```

Content structure:
```
content/
  articles/
    hello-world.en.md
    hello-world.fr.md
```

Or separate content directories:
```
content/en/articles/hello-world.md
content/fr/articles/hello-world.md
```

Map Drupal translations to the corresponding language-suffixed files.

---

## Import Process

### Recommended Approach

1. Export Drupal content using the toolkit's extraction skills.
2. Transform with `normalize-content.py`, `flatten-paragraphs.py`, and `clean-rich-text.py`.
3. Convert HTML body fields to Markdown (using `turndown`, `pandoc`, or similar).
4. Generate one `.md` file per entity with YAML front matter.
5. Download media to page bundle directories or `static/`.
6. Run `validate-export.py` on the intermediate JSON before generating Markdown.
7. Build with `hugo` and verify output.
8. Run the validation checklist.

### Drupal-to-Hugo Conversion Pattern

```python
import yaml, os
from pathlib import Path

for entity in export_data:
    front_matter = {
        'title': entity['title'],
        'date': entity['created'],
        'slug': entity['slug'],
        'categories': entity.get('categories', []),
        'tags': entity.get('tags', []),
        'draft': not entity.get('published', True),
    }
    body = html_to_markdown(entity['body_value'])
    
    output_dir = Path(f"content/articles/{entity['slug']}")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    with open(output_dir / 'index.md', 'w') as f:
        f.write('---\n')
        f.write(yaml.dump(front_matter, default_flow_style=False))
        f.write('---\n\n')
        f.write(body)
```

---

## Known Gotchas

- Hugo is purely static. Dynamic features (search, comments, forms) need external services (Algolia, Disqus, Formspree) or client-side JS.
- Hugo's templating language (Go templates) has a learning curve. Complex View-like queries may require creative use of `where`, `sort`, and `range`.
- Hugo has no database. All content is in Markdown files. Very large sites (50K+ pages) still build fast but Git repos get large.
- Shortcode syntax in Markdown can be fragile. Validate generated shortcode calls carefully.
- Hugo processes Markdown with Goldmark. Some Drupal HTML constructs (tables with colspan, complex nested divs) may not survive HTML→Markdown→HTML roundtrip.
- No built-in admin UI. Editors need a git-based CMS (Decap CMS, Forestry/Tina, Cloudcannon) or edit files directly.
- Hugo's image processing requires images in page bundles or `assets/`, not `static/`. Plan your media structure accordingly.
