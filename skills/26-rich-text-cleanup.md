# Skill 26: Rich Text Cleanup — Drupal-Specific Markup Conversion

Strip or convert Drupal-specific tags, tokens, and attributes embedded in rich text HTML. The goal: portable HTML that renders without a Drupal runtime.

Run Skill 01 (Site Audit) first for the Drupal version. Run Skill 07 (Media and Files Export) first to build a file/media ID-to-URL lookup table. Run Skill 20 (URL Aliases) first to resolve internal paths.

---

## Why This Skill Exists

Drupal stores rich text as HTML, but that HTML contains tags and tokens that only render inside Drupal. Move the content to WordPress, a static site, or any non-Drupal system and you get broken images, dead links, and raw markup visible to readers. This skill finds every Drupal-specific pattern and converts it to standard HTML.

---

## Prerequisites

| Requirement | Why |
|---|---|
| **Media lookup table** | Maps `mid`, `fid`, `uuid` to public file URL. Built by Skill 07. |
| **Node lookup table** | Maps `nid`, `uuid` to final URL on the target platform. Built by Skill 20 + your URL mapping. |
| **Taxonomy term lookup** | Maps `tid`, `uuid` to target URL. Built by Skill 05. |
| **Drupal version** | D7 and D8+ use different embed formats. |
| **Text format config** | `filter.format.*.yml` (D8+) or `filter` / `filter_format` tables (D7). Tells you which filters are active per format. |

---

## Pattern Reference

### 1. `<drupal-media>` Tags (D8.6+, D9, D10, D11)

Core media embed introduced in Drupal 8.6. Replaces entity_embed for media.

**Stored markup:**

```html
<drupal-media
  data-entity-type="media"
  data-entity-uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  data-view-mode="full"
  data-align="center"
  data-caption="Photo of the old barn"
  alt="Old barn at sunset">
</drupal-media>
```

**Key attributes:**

| Attribute | Required | Meaning |
|---|---|---|
| `data-entity-type` | Yes | Always `media` |
| `data-entity-uuid` | Yes | UUID of the media entity |
| `data-view-mode` | No | Drupal view mode: `full`, `thumbnail`, `media_library`, custom |
| `data-align` | No | `left`, `center`, `right` |
| `data-caption` | No | Caption text (may contain HTML) |
| `alt` | No | Alt text override for the image |

**Detection regex:**

```regex
<drupal-media\b[^>]*>[\s\S]*?<\/drupal-media>
```

**Resolution strategy:**

1. Extract `data-entity-uuid` from the tag.
2. Look up the UUID in the media lookup table to get the file URL and media type (image, document, video, remote_video).
3. Branch on media type:

For **image** media:

```html
<!-- Input -->
<drupal-media data-entity-uuid="a1b2..." data-align="center" data-caption="Photo of the old barn" alt="Old barn at sunset"></drupal-media>

<!-- Output -->
<figure class="align-center">
  <img src="/sites/default/files/2024-03/barn.jpg" alt="Old barn at sunset" />
  <figcaption>Photo of the old barn</figcaption>
</figure>
```

For **document** media (file download):

```html
<a href="/sites/default/files/2024-03/report.pdf" class="media-document">report.pdf</a>
```

For **remote_video** media (YouTube, Vimeo stored via oembed):

```html
<figure class="align-center media-remote-video">
  <iframe src="https://www.youtube.com/embed/VIDEO_ID" allowfullscreen></iframe>
  <figcaption>Photo of the old barn</figcaption>
</figure>
```

For **video** media (local file):

```html
<figure class="align-center">
  <video src="/sites/default/files/2024-03/clip.mp4" controls></video>
  <figcaption>Photo of the old barn</figcaption>
</figure>
```

4. If `data-align` is present, set a class on the `<figure>`: `align-left`, `align-center`, `align-right`.
5. If `data-caption` is present, add a `<figcaption>`. If absent, output a bare `<img>` (no `<figure>` wrapper needed unless alignment is set).
6. If `alt` is present on the `<drupal-media>` tag, use it. Otherwise fall back to the alt text stored on the media entity's image field.

**Fallback if UUID not found:**

```html
<!-- MIGRATION-TODO: unresolved drupal-media uuid=a1b2c3d4-e5f6-7890-abcd-ef1234567890 -->
```

Log every unresolved UUID. Do not silently drop content.

---

### 2. `<drupal-entity>` Tags (entity_embed contrib module, D8+)

The entity_embed module provides a more general embed tag. Used for nodes, blocks, media, taxonomy terms, and custom entities.

**Stored markup:**

```html
<drupal-entity
  data-entity-type="node"
  data-entity-uuid="f9e8d7c6-b5a4-3210-fedc-ba9876543210"
  data-entity-embed-display="view_mode:node.teaser"
  data-align="right"
  data-caption="Related article">
</drupal-entity>
```

Can also embed media (before core drupal-media existed):

```html
<drupal-entity
  data-entity-type="media"
  data-entity-uuid="a1b2c3d4-..."
  data-entity-embed-display="view_mode:media.full">
</drupal-entity>
```

Or blocks:

```html
<drupal-entity
  data-entity-type="block_content"
  data-entity-uuid="..."
  data-entity-embed-display="view_mode:block_content.full">
</drupal-entity>
```

**Key attributes:**

| Attribute | Required | Meaning |
|---|---|---|
| `data-entity-type` | Yes | `node`, `media`, `block_content`, `taxonomy_term`, `user`, or any entity type |
| `data-entity-uuid` | Yes | UUID of the entity |
| `data-entity-embed-display` | No | Render plugin. Format: `view_mode:{entity_type}.{view_mode}` or `entity_reference:{formatter}` |
| `data-entity-embed-display-settings` | No | JSON-encoded settings for the display plugin |
| `data-align` | No | `left`, `center`, `right` |
| `data-caption` | No | Caption text |

**Detection regex:**

```regex
<drupal-entity\b[^>]*>[\s\S]*?<\/drupal-entity>
```

**Resolution strategy by entity type:**

| Entity type | Convert to |
|---|---|
| `media` | Same as `<drupal-media>` resolution above |
| `node` | Link to the node: `<a href="{target_url}">{node_title}</a>`. If the embed display was a teaser, consider inlining a card with title + summary. |
| `block_content` | Inline the block body HTML. If the block contains complex fields, flag for manual review. |
| `taxonomy_term` | Link: `<a href="{target_url}">{term_name}</a>` |
| `user` | Link: `<a href="{target_url}">{display_name}</a>` |

**Fallback:**

```html
<!-- MIGRATION-TODO: unresolved drupal-entity type={data-entity-type} uuid={data-entity-uuid} -->
```

---

### 3. D7 Media WYSIWYG Tokens

Drupal 7's media module (with media_wysiwyg) stores embedded media as a JSON token inside double square brackets. This is the most complex pattern.

**Stored markup:**

```
[[{"type":"media","view_mode":"default","fid":"123","attributes":{"alt":"Sunset photo","class":"media-image","height":"400","width":"600"}}]]
```

Sometimes multi-line or with extra whitespace. Some sites have additional keys: `fields`, `link_text`, `format`, `alignment`.

**Variant with fields override:**

```
[[{"type":"media","view_mode":"large","fid":"456","fields":{"field_file_image_alt_text[und][0][value]":"Overridden alt","field_file_image_title_text[und][0][value]":"Title text"}}]]
```

**Detection regex:**

```regex
\[\[\s*\{[^}]*"type"\s*:\s*"media"[^]]*\}\s*\]\]
```

A stricter version that handles nested braces:

```regex
\[\[\s*(\{(?:[^{}]|\{[^{}]*\})*\})\s*\]\]
```

**Resolution strategy:**

1. Extract the JSON string from between `[[` and `]]`.
2. Parse the JSON. Extract `fid`, `view_mode`, and `attributes`.
3. Look up `fid` in the file lookup table (D7 uses `file_managed.fid` mapped to a URI like `public://images/photo.jpg`).
4. Convert the URI to a public URL.
5. Use `attributes.alt` for alt text. If `fields.field_file_image_alt_text` is present, prefer that (it overrides the default).
6. Apply `view_mode` to determine image style. Map common view modes:

| D7 view_mode | Typical image style | Suggested output |
|---|---|---|
| `default` | Original size | `<img>` with original dimensions |
| `thumbnail` | `thumbnail` (100x100) | `<img>` with width/height from attributes or 100x100 |
| `preview` | `preview` (220x220) | `<img>` with constrained dimensions |
| `large` | `large` (480x480) | `<img>` with constrained dimensions |
| `full` | Original | `<img>` at full size |
| `media_original` | Original | `<img>` at full size |

7. Output:

```html
<img src="/sites/default/files/images/photo.jpg" alt="Sunset photo" width="600" height="400" />
```

**Fallback if FID not found:**

```html
<!-- MIGRATION-TODO: unresolved D7 media token fid=123 -->
```

**Common pitfalls:**
- JSON is sometimes malformed (single quotes instead of double, trailing commas). Use a lenient JSON parser or fix known issues before parsing.
- Some sites wrap these tokens in `<p>` tags. After replacing the token with an `<img>`, the `<img>` sits inside a `<p>`, which is invalid HTML when wrapped in `<figure>`. Strip the `<p>` wrapper if the replacement is a block-level element.
- The `fid` references `file_managed.fid`. If the file was deleted, the FID exists in content but not in the file table. Flag these.

---

### 4. Token Replacements: `[node:123]`, `[[nid:123]]`, `[token:name]`

Several Drupal modules allow tokens in body text that get replaced at render time.

#### 4a. Node Reference Tokens

**Formats seen across contrib modules:**

```
[node:123]
[[nid:123]]
[nid:123]
[entity:node/123]
```

**Detection regex (catches all common variants):**

```regex
\[{1,2}(?:node|nid|entity:node)[:/](\d+)\]{1,2}
```

**Resolution:**

1. Extract the node ID.
2. Look up the node in the node lookup table.
3. Replace with a link: `<a href="{target_url}">{node_title}</a>`.
4. If the token was inline (mid-sentence), a link is correct. If it was the sole content of a paragraph, consider inlining a card or teaser.

**Fallback:**

```html
<a href="#" class="migration-broken-link" data-original-nid="123">[[nid:123]]</a>
<!-- MIGRATION-TODO: unresolved node reference nid=123 -->
```

#### 4b. Drupal Token Module Patterns

The Token module provides `[site:name]`, `[current-user:name]`, `[node:title]`, and hundreds more. These are rarely stored in body text, but some sites use them in custom blocks, footer text, or automated content.

**Detection regex:**

```regex
\[([a-z_-]+):([a-z0-9_-]+(?::[a-z0-9_-]+)*)\]
```

This matches `[site:name]`, `[node:author:name]`, `[current-date:custom:Y]`.

**Common tokens and resolution:**

| Token | Replace with |
|---|---|
| `[site:name]` | Hardcode the site name string |
| `[site:url]` | Hardcode the target site URL |
| `[site:slogan]` | Hardcode or remove |
| `[current-date:*]` | Remove or hardcode the date at export time |
| `[current-user:*]` | Remove. These are session-dependent. |
| `[node:title]` | Replace with the actual node title if context is known |
| `[node:url]` | Replace with the target URL |
| `[node:field_*]` | Resolve from node data if possible |

**Strategy:**

1. Scan all body text for token patterns.
2. Build a frequency report of which tokens appear and how often.
3. For static tokens (`[site:name]`, `[site:url]`), do a global find-replace with the actual value.
4. For context-dependent tokens (`[node:title]` in that node's own body), resolve from the node's exported data.
5. For unresolvable tokens (`[current-user:name]`), strip them and log.

**Fallback:**

```html
<!-- MIGRATION-TODO: unresolved token [current-user:name] -->
```

---

### 5. Linkit Module References

Linkit replaces standard `<a href="/node/42">` links with data attributes that reference entities by UUID. This survives alias changes in Drupal. Outside Drupal, the data attributes are meaningless and the href may be stale.

**Stored markup:**

```html
<a href="/node/42"
   data-entity-substitution="canonical"
   data-entity-type="node"
   data-entity-uuid="f9e8d7c6-b5a4-3210-fedc-ba9876543210">
  Read more about our project
</a>
```

**Other substitution types:**

| `data-entity-substitution` | Meaning |
|---|---|
| `canonical` | Link to the entity's canonical URL |
| `media` | Direct link to the media file |
| `file` | Direct link to the file entity's file |

**Detection regex:**

```regex
<a\b[^>]*data-entity-type=[^>]*data-entity-uuid=[^>]*>
```

**Resolution strategy:**

1. Extract `data-entity-type` and `data-entity-uuid`.
2. Look up the UUID in the appropriate lookup table.
3. Replace the `href` value with the target URL.
4. Remove `data-entity-substitution`, `data-entity-type`, and `data-entity-uuid` attributes.
5. Keep the link text unchanged.

```html
<!-- Before -->
<a href="/node/42" data-entity-substitution="canonical" data-entity-type="node" data-entity-uuid="f9e8d7c6-...">Read more</a>

<!-- After -->
<a href="/blog/our-project">Read more</a>
```

If `data-entity-substitution="media"` or `"file"`, resolve to the direct file URL:

```html
<a href="/sites/default/files/report.pdf">Download the report</a>
```

**Fallback:**

Keep the existing `href` (it may still work as a path alias). Add a comment:

```html
<a href="/node/42">Read more</a>
<!-- MIGRATION-TODO: unresolved linkit uuid=f9e8d7c6-... type=node -->
```

---

### 6. Internal Path Links (`/node/42`, `/taxonomy/term/7`, `/user/1`)

Standard Drupal internal paths that were never aliased, or that editors linked to directly.

**Detection regex:**

```regex
<a\b[^>]*href=["']/(node|taxonomy/term|user)/(\d+)(?:[?#][^"']*)?\s*["'][^>]*>
```

Also catch absolute URLs to the same site:

```regex
<a\b[^>]*href=["']https?://(?:www\.)?example\.com/(node|taxonomy/term|user)/(\d+)[^"']*["'][^>]*>
```

Replace `example.com` with the actual source domain from the site audit.

**Resolution:**

1. Parse the entity type and ID from the path.
2. Look up the target URL.
3. Rewrite `href` to the target URL. Remove any Drupal-specific query parameters (`?destination=...`).

**Fallback:**

```html
<a href="/node/42">Link text</a>
<!-- MIGRATION-TODO: unresolved internal path /node/42 -->
```

---

### 7. `data-entity-type` and `data-entity-uuid` on Non-Linkit Elements

Some modules and themes add entity reference attributes to elements other than links: `<div>`, `<span>`, `<img>`.

**Detection regex:**

```regex
data-entity-type=["'][^"']+["']
```

```regex
data-entity-uuid=["'][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}["']
```

**Resolution:**

Strip these attributes. They serve no purpose outside Drupal. No content is lost.

```html
<!-- Before -->
<div data-entity-type="node" data-entity-uuid="...">Content</div>

<!-- After -->
<div>Content</div>
```

---

### 8. Media Alignment and Caption Wrappers

Drupal wraps aligned media and captions in specific div structures. CKEditor 4 and CKEditor 5 use different markup.

#### CKEditor 4 (D8, D9)

Alignment applied via `data-align` attribute on the `<drupal-media>` tag. At render time, Drupal wraps it:

```html
<div class="field__item">
  <div data-caption="A photo" data-align="center" class="caption caption-center">
    <div class="media media--type-image media--view-mode-full">
      <img src="..." alt="..." />
    </div>
    <figcaption>A photo</figcaption>
  </div>
</div>
```

#### CKEditor 5 (D10+)

```html
<figure class="image image-style-align-center">
  <drupal-media data-entity-type="media" data-entity-uuid="..."></drupal-media>
  <figcaption>A photo</figcaption>
</figure>
```

**Resolution:**

When processing `<drupal-media>` and `<drupal-entity>` tags, you already handle alignment and captions (patterns 1 and 2). This pattern catches the wrapper markup that Drupal's filter system adds around already-rendered content.

1. Detect wrapper divs with classes matching `caption`, `caption-*`, `media--type-*`, `media--view-mode-*`, `field__item`.
2. If the inner content has already been resolved (the `<drupal-media>` was converted to an `<img>`), simplify the wrapper to a `<figure>` with alignment class.
3. Strip Drupal-specific classes: `media--type-*`, `media--view-mode-*`, `field__item`, `contextual-region`.
4. Keep `align-left`, `align-center`, `align-right` classes or convert to standard HTML/CSS equivalents.

**Cleanup regex for wrapper classes:**

```regex
\bclass="[^"]*\b(media--type-\w+|media--view-mode-\w+|field__item|contextual-region|caption-\w+)\b[^"]*"
```

Do not strip classes blindly. Remove only known Drupal-specific class prefixes. Preserve any custom classes that the site's theme may have added.

---

### 9. CKEditor Widget Markup

CKEditor 4 wraps widgets (media embeds, tables, code blocks) in extra scaffolding that Drupal stores in the database.

**Common patterns:**

```html
<div class="cke_widget_wrapper cke_widget_block" data-cke-widget-wrapper="1" data-cke-widget-id="0">
  <div class="cke_widget_element" data-cke-widget-data="..." data-widget="drupalimage">
    <img src="..." />
  </div>
  <span class="cke_reset cke_widget_drag_handler_container">
    <img class="cke_reset cke_widget_drag_handler" />
  </span>
</div>
```

**Detection:**

```regex
(?:class|data-cke-)[^"]*cke_widget[^"]*
```

**Resolution:**

1. Unwrap: extract the inner content element (the actual `<img>`, `<table>`, etc.).
2. Remove all `cke_*` classes and `data-cke-*` attributes.
3. Remove drag handler spans (`cke_widget_drag_handler_container` and its children).
4. This is usually stored only when content was saved with CKEditor's source view or when the body was copied between editors. Check frequency. On most sites this pattern is rare.

---

### 10. PHP Code in Content (php_code filter)

Drupal 7 shipped a "PHP code" text format that executed `<?php ... ?>` stored in the database. Some D8 sites have the contributed `php` module. This is a security concern and must never be migrated as executable code.

**Detection regex:**

```regex
<\?php[\s\S]*?\?>
```

Also detect the text format configuration:

```bash
# D8+: check if any text format uses the php_code filter
grep -r "php_code" config/sync/filter.format.*.yml

# D7: check filter table
drush sql:query "SELECT format, name FROM filter WHERE module = 'php' AND status = 1"
```

**Resolution:**

1. Log every piece of content that contains `<?php`. Include entity type, entity ID, field name, and the PHP code snippet.
2. Do not execute the code.
3. Analyze what the code does. Common cases:

| PHP pattern | Migration approach |
|---|---|
| Prints a block or view | Replace with the rendered output, or a shortcode/component on the target platform |
| Redirects (`drupal_goto`) | Add a server-side redirect rule |
| Outputs a form | Replace with the target platform's form embed |
| Calls `node_load` / `entity_load` | Replace with the referenced content, resolved statically |
| Generates dynamic listings | Replace with a component or API call on the target platform |

4. Replace the `<?php ... ?>` block with a placeholder:

```html
<!-- MIGRATION-TODO: PHP code removed. Review required. Original: [first 200 chars of the code] -->
```

5. Generate a separate report of all PHP-in-content instances with full code for manual review.

---

### 11. Filter Tokens Stored Raw (Render-Time Processing)

Some Drupal text filters transform content at display time but store the raw token in the database. These break when you move the content out of Drupal.

**Common filter-based tokens:**

| Module | Token format | What it renders |
|---|---|---|
| `shortcode` | `[button url="/path"]Click[/button]` | HTML button |
| `video_filter` | `[video:https://youtube.com/watch?v=ID]` | Embedded video player |
| `insert_view` | `[view:view_name=display_id]` | Rendered Drupal view output |
| `insert_block` | `[block:module=delta]` or `[block:block_content:uuid]` | Rendered block |
| `footnotes` | `[fn]Footnote text[/fn]` | Footnote markup |
| `ckeditor_accordion` | `<dl class="styled-accordion">` with specific structure | Accordion UI |
| `oembed_filter` | Raw URLs on their own line | oEmbed-rendered media |
| `highlightjs_filter` | `<code data-lang="php">` | Syntax-highlighted code |

**Detection strategy:**

1. Export the text format configuration:

```bash
# D8+
drush config:get filter.format.full_html --format=yaml
drush config:get filter.format.basic_html --format=yaml

# D7
drush sql:query "SELECT name, module, settings FROM filter WHERE status = 1 ORDER BY format, weight"
```

2. For each active filter, check whether it uses a token/pattern that is stored raw. Build a list of patterns to search for in body text.
3. Count occurrences per pattern to prioritize conversion effort.

**Resolution per token type:**

- **`[view:*]`**: Run the view on the source site, capture the HTML output, and embed it statically. Or map to a dynamic component on the target platform.
- **`[block:*]`**: Same as views. Render on source, capture, embed.
- **`[video:URL]`**: Convert to an `<iframe>` or `<video>` tag.
- **`[fn]...[/fn]`**: Convert to `<sup>` with an anchor link and a `<footer>` footnotes section, or use the target platform's footnote mechanism.
- **Shortcode-style tags**: Map each shortcode to its HTML equivalent. Build a converter per shortcode type.

---

## Processing Order

Run these patterns in order. Later steps depend on earlier ones.

| Step | Pattern | Reason for order |
|---|---|---|
| 1 | PHP code (10) | Remove dangerous code first. |
| 2 | CKEditor widget unwrap (9) | Simplify wrapper markup before processing inner embeds. |
| 3 | D7 media tokens (3) | Convert `[[{json}]]` to `<img>` before the generic token pass catches the brackets. |
| 4 | `<drupal-media>` tags (1) | Convert core media embeds. |
| 5 | `<drupal-entity>` tags (2) | Convert entity_embed tags. |
| 6 | Linkit references (5) | Resolve link hrefs and strip data attributes. |
| 7 | Internal path links (6) | Rewrite `/node/42` style paths. |
| 8 | Node reference tokens (4a) | Resolve `[nid:123]` tokens. |
| 9 | Token module patterns (4b) | Resolve `[site:name]` and similar. |
| 10 | Filter tokens (11) | Handle `[view:*]`, `[video:*]`, shortcodes. |
| 11 | Orphan data attributes (7) | Strip leftover `data-entity-*` attributes. |
| 12 | Caption/alignment wrappers (8) | Clean up structural divs last. |

---

## Implementation

### Build the Lookup Tables First

Before processing any body text, build three lookup dictionaries:

```python
# Pseudocode — adapt to your migration tooling

media_lookup = {}   # {uuid: {url, alt, type, title}, fid: {url, alt, type, title}}
node_lookup = {}    # {uuid: {url, title}, nid: {url, title}}
term_lookup = {}    # {uuid: {url, name}, tid: {url, name}}
file_lookup = {}    # {fid: {url, filename, mime}}  (D7 file_managed)
```

Populate from:
- Skill 07 output (media/file export)
- Skill 20 output (path aliases)
- Skill 05 output (taxonomy terms)

### Processing Pipeline

```
for each entity with a rich text field:
    for each text field value:
        html = field_value
        html = remove_php_code(html)
        html = unwrap_ckeditor_widgets(html)
        html = convert_d7_media_tokens(html, file_lookup, media_lookup)
        html = convert_drupal_media_tags(html, media_lookup)
        html = convert_drupal_entity_tags(html, media_lookup, node_lookup, term_lookup)
        html = resolve_linkit_links(html, node_lookup, media_lookup, file_lookup)
        html = rewrite_internal_paths(html, node_lookup, term_lookup)
        html = resolve_node_reference_tokens(html, node_lookup)
        html = resolve_token_module_patterns(html, site_config)
        html = resolve_filter_tokens(html)
        html = strip_orphan_data_attributes(html)
        html = clean_caption_alignment_wrappers(html)
        field_value = html
```

### Validation

After processing, run these checks on every converted field:

| Check | How |
|---|---|
| No `<drupal-media>` tags remain | `grep -c '<drupal-media'` across all output |
| No `<drupal-entity>` tags remain | `grep -c '<drupal-entity'` across all output |
| No D7 media tokens remain | `grep -cP '\[\[\s*\{[^}]*"type"\s*:\s*"media"'` across all output |
| No `data-entity-uuid` attributes remain | `grep -c 'data-entity-uuid'` across all output |
| No `/node/\d+` hrefs remain | `grep -cP 'href="[^"]*\/node\/\d+'` across all output |
| No PHP code remains | `grep -c '<?php'` across all output |
| No MIGRATION-TODO exceeds threshold | Count all `MIGRATION-TODO` comments. Set an acceptable percentage (e.g., under 2% of total fields). |
| HTML is well-formed | Run through an HTML parser. Fix unclosed tags introduced by token replacement. |
| Images resolve | Spot-check 50 random `<img>` `src` values. Verify the file exists at that URL. |

### Reporting

Produce a cleanup report with:

```json
{
  "total_fields_processed": 12450,
  "patterns_found": {
    "drupal_media_tags": 342,
    "drupal_entity_tags": 87,
    "d7_media_tokens": 1203,
    "linkit_references": 567,
    "internal_path_links": 2341,
    "node_reference_tokens": 45,
    "token_module_patterns": 12,
    "php_code_blocks": 3,
    "ckeditor_widgets": 28,
    "filter_tokens": 156
  },
  "resolved": {
    "drupal_media_tags": 340,
    "drupal_entity_tags": 85,
    "d7_media_tokens": 1198,
    "linkit_references": 560,
    "internal_path_links": 2300,
    "node_reference_tokens": 42,
    "token_module_patterns": 10,
    "filter_tokens": 130
  },
  "unresolved": [
    {"type": "drupal_media", "uuid": "a1b2c3...", "count": 2, "entities": ["node/42", "node/99"]},
    {"type": "d7_media", "fid": 789, "count": 5, "entities": ["node/101", "node/102", "..."]}
  ],
  "php_code_removed": [
    {"entity": "node/55", "field": "body", "code_preview": "<?php print views_embed_view('related_co..."}
  ]
}
```

---

## Edge Cases

**Nested embeds.** A `<drupal-entity>` that embeds a node whose body contains another `<drupal-media>`. Process recursively, but set a depth limit (3 levels). Log anything deeper.

**Multilingual content.** The same entity may have different body text per language. Each translation needs independent processing. The media/node lookup must account for language-specific aliases.

**Revisions.** If migrating revision history, process every revision's body text. Old revisions may reference deleted media. Accept higher unresolved rates for non-current revisions.

**Encoded entities.** Some WYSIWYG editors double-encode HTML entities. A `<drupal-media>` tag may appear as `&lt;drupal-media&gt;` in the stored text. Decode HTML entities before pattern matching if you find zero matches but know the site uses media embeds.

**Mixed D7/D8 content.** Sites that migrated from D7 to D8 in-place may have both D7 media tokens (`[[{json}]]`) and D8 `<drupal-media>` tags in the same database. Handle both.

**Empty tags.** `<drupal-media></drupal-media>` with no attributes. Strip and log.

**Self-closing variants.** Some content may contain `<drupal-media ... />` instead of the paired open/close tags. Match both:

```regex
<drupal-media\b[^>]*(?:\/>|>[\s\S]*?<\/drupal-media>)
```
