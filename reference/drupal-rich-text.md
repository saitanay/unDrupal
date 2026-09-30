# Drupal Rich Text: Formats, Filters, and Embedded Media

## Text Formats

Drupal processes rich text through text formats. Each format defines a pipeline of filters applied in order. Content authors select a format when editing text fields.

### Common Text Formats

| Machine Name | Typical Use | Common Filters |
|-------------|-------------|----------------|
| `plain_text` | Comments, short inputs | HTML escape, line break converter |
| `basic_html` | Standard content editing | HTML filter (allowlist), line break converter, URL to link |
| `restricted_html` | Untrusted users | Strict HTML allowlist |
| `full_html` | Trusted editors | Minimal filtering, CKEditor embed support |
| `markdown` | Developer content (contrib) | Markdown to HTML conversion |

### Storage

The format machine name is stored alongside the text value:

```sql
-- D9+ field table
SELECT body_value, body_format FROM node__body WHERE entity_id = 42;
-- body_format = 'full_html'
```

Format configuration lives in `filter.format.{name}` config entities.

### Filter Pipeline

Filters process text in weight order. Each filter has a `status` (enabled/disabled), `weight` (execution order), and `settings`.

```yaml
# filter.format.full_html
filters:
  filter_html_escape:
    status: false
  filter_autop:
    status: true
    weight: 0
  filter_url:
    status: true
    weight: 0
  filter_htmlcorrector:
    status: true
    weight: 10
  media_embed:
    status: true
    weight: 100
  filter_align:
    status: true
    weight: 200
  filter_caption:
    status: true
    weight: 300
```

## Embedded Media (D9+ Core Media)

Since Drupal 8.8, core provides a media embed filter. CKEditor inserts `<drupal-media>` tags into the HTML. The `media_embed` filter converts them to rendered output.

### Token Format

```html
<drupal-media
  data-entity-type="media"
  data-entity-uuid="12345678-1234-1234-1234-123456789abc"
  data-view-mode="full"
  data-align="center"
  data-caption="Photo by Jane Doe"
  alt="Override alt text">
</drupal-media>
```

### Attributes

| Attribute | Required | Values |
|-----------|----------|--------|
| `data-entity-type` | Yes | Always `media` |
| `data-entity-uuid` | Yes | UUID of the media entity |
| `data-view-mode` | No | View mode: `full`, `thumbnail`, `teaser`, `media_library`. Default depends on config. |
| `data-align` | No | `left`, `right`, `center` |
| `data-caption` | No | Caption text (may contain HTML) |
| `alt` | No | Alt text override (for images) |

### Detection Regex

```python
import re

# Find all embedded media in a text field
DRUPAL_MEDIA_RE = re.compile(
    r'<drupal-media\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\'][^>]*/?>',
    re.IGNORECASE
)

uuids = DRUPAL_MEDIA_RE.findall(body_value)
```

```python
# Full attribute extraction
DRUPAL_MEDIA_FULL_RE = re.compile(
    r'<drupal-media\s+'
    r'(?P<attrs>[^>]*)'
    r'/?>',
    re.IGNORECASE | re.DOTALL
)

ATTR_RE = re.compile(r'([\w-]+)=["\']([^"\']*)["\']')

for match in DRUPAL_MEDIA_FULL_RE.finditer(body_value):
    attrs = dict(ATTR_RE.findall(match.group('attrs')))
    uuid = attrs.get('data-entity-uuid')
    view_mode = attrs.get('data-view-mode', 'full')
    align = attrs.get('data-align')
    caption = attrs.get('data-caption')
```

## D7 Embedded Media (Media Module 1.x/2.x)

D7 with the `media` module uses a JSON-based token in the text body.

### Token Format

```
[[{"type":"media","view_mode":"media_large","fid":"123","attributes":{"alt":"Alt text","class":"media-image","height":"400","width":"600"}}]]
```

Single line, double-bracket wrapped JSON array with one object.

### Detection Regex

```python
D7_MEDIA_TOKEN_RE = re.compile(
    r'\[\[({[^]]*"type"\s*:\s*"media"[^]]*})\]\]'
)

import json
for match in D7_MEDIA_TOKEN_RE.finditer(body_value):
    try:
        token = json.loads(match.group(1))
        fid = token.get('fid')
        view_mode = token.get('view_mode')
        alt = token.get('attributes', {}).get('alt')
    except json.JSONDecodeError:
        pass  # Malformed token
```

### Variant: Media WYSIWYG

Some D7 sites use the `media_wysiwyg` module which uses a slightly different format:

```
[[{"fid":"123","view_mode":"media_large","type":"media","link_text":"","attributes":{"class":"file media-element file-media-large"}}]]
```

## D7 Embedded Images (IMCE / CKEditor direct)

D7 sites without the media module often have images inserted as raw `<img>` tags pointing to the files directory:

```html
<img src="/sites/default/files/field/image/photo.jpg" width="600" height="400" alt="Photo" />
```

### Detection Regex

```python
# Find images referencing Drupal file paths
DRUPAL_IMG_RE = re.compile(
    r'<img\s[^>]*src=["\']'
    r'(/sites/default/files/[^"\']+)'
    r'["\'][^>]*>',
    re.IGNORECASE
)

for match in DRUPAL_IMG_RE.finditer(body_value):
    file_path = match.group(1)
```

## Entity Embed Module (D8+ Contrib)

The `entity_embed` module provides a more general embed system that can embed any entity type.

### Token Format

```html
<drupal-entity
  data-entity-type="node"
  data-entity-uuid="12345678-1234-1234-1234-123456789abc"
  data-entity-embed-display="view_mode:full"
  data-align="center"
  data-caption="Related article">
</drupal-entity>
```

### Detection Regex

```python
ENTITY_EMBED_RE = re.compile(
    r'<drupal-entity\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\'][^>]*/?>',
    re.IGNORECASE
)
```

## URL Embed Module (D8+ Contrib)

```html
<drupal-url
  data-embed-url="https://www.youtube.com/watch?v=abc123"
  data-url-provider="YouTube">
</drupal-url>
```

## Linkit Module

The `linkit` module stores internal links with a `data-entity-*` attribute pattern:

```html
<a href="/node/123"
   data-entity-type="node"
   data-entity-uuid="uuid-here"
   data-entity-substitution="canonical">
  Link text
</a>
```

### Detection Regex

```python
LINKIT_RE = re.compile(
    r'<a\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\'][^>]*>',
    re.IGNORECASE
)
```

## CKEditor 5 HTML (D10+)

D10 defaults to CKEditor 5. Its output uses standard HTML5 with `<figure>` and `<figcaption>` for captioned media:

```html
<figure class="image image-style-align-left">
  <drupal-media data-entity-type="media" data-entity-uuid="..." data-view-mode="full"></drupal-media>
  <figcaption>Caption text</figcaption>
</figure>
```

## Token Module (D7)

The `token` module (and D7 core tokens) inserts replacement patterns:

```
[node:title]
[node:url]
[site:name]
[current-user:name]
[node:field_image:medium:url]
```

### Detection Regex

```python
TOKEN_RE = re.compile(r'\[([a-z_-]+(?::[a-z_-]+)+)\]', re.IGNORECASE)
tokens = TOKEN_RE.findall(body_value)
```

## PHP Filter (D7 Legacy)

Some D7 sites have the `php` filter enabled, embedding executable PHP in text fields:

```php
<?php
  print views_embed_view('recent_articles', 'block_1');
?>
```

### Detection Regex

```python
PHP_RE = re.compile(r'<\?php\s.*?\?>', re.DOTALL)
if PHP_RE.search(body_value):
    # Flag for manual review - cannot auto-migrate
    pass
```

## Shortcodes (D7/D8 Contrib)

Some sites use WordPress-style shortcodes via the `shortcode` module:

```
[button url="/contact" color="blue"]Contact Us[/button]
[gallery ids="1,2,3,4" columns="3"]
[accordion][tab title="FAQ 1"]Answer[/tab][/accordion]
```

### Detection Regex

```python
SHORTCODE_RE = re.compile(
    r'\[([a-z_]+)(?:\s[^\]]*?)?\]'
    r'(?:(.*?)\[/\1\])?',
    re.IGNORECASE | re.DOTALL
)
```

## Migration Strategy: Processing Rich Text

1. Identify the text format from the `_format` column.
2. Parse the raw HTML for all embed patterns (media, entity, linkit, tokens, PHP, shortcodes).
3. Resolve UUIDs to file paths or content references.
4. Convert embeds to target platform format (standard HTML `<img>`, `<a>`, `<video>`, etc.).
5. Run HTML cleanup: fix relative URLs, strip Drupal-specific classes, normalize attributes.
6. Preserve `data-align` and `data-caption` as CSS classes or `<figure>`/`<figcaption>`.

### Combined Detection

```python
def find_all_embeds(html):
    """Find all Drupal-specific embeds in a rich text field."""
    embeds = []

    # D9+ core media
    for m in re.finditer(r'<drupal-media\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\']', html):
        embeds.append(('drupal-media', m.group(1), m.start()))

    # Entity embed
    for m in re.finditer(r'<drupal-entity\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\']', html):
        embeds.append(('entity-embed', m.group(1), m.start()))

    # D7 media tokens
    for m in re.finditer(r'\[\[({[^]]*"type"\s*:\s*"media"[^]]*})\]\]', html):
        try:
            data = json.loads(m.group(1))
            embeds.append(('d7-media', data.get('fid'), m.start()))
        except json.JSONDecodeError:
            pass

    # Linkit references
    for m in re.finditer(r'<a\s[^>]*data-entity-uuid=["\']([0-9a-f-]{36})["\']', html):
        embeds.append(('linkit', m.group(1), m.start()))

    # Inline file images
    for m in re.finditer(r'<img\s[^>]*src=["\'](/sites/default/files/[^"\']+)["\']', html, re.I):
        embeds.append(('inline-image', m.group(1), m.start()))

    # PHP code
    for m in re.finditer(r'<\?php\s.*?\?>', html, re.DOTALL):
        embeds.append(('php', m.group(0)[:100], m.start()))

    return embeds
```
