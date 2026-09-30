# Skill 35: Gutenberg Block Editor Content Export

Extract content stored by the Drupal Gutenberg module. The module replaces the standard WYSIWYG editor with WordPress's Gutenberg block editor, storing serialized block HTML inside standard Drupal text fields. The content looks like HTML but contains structured block metadata embedded in HTML comments.

Run Skill 01 (Site Audit) and Skill 04 (Content Types & Fields) first. You need to know which content types use Gutenberg and which text field holds the block content.

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Config directory** (YAML) | `gutenberg.settings.yml`, content type third_party_settings, text format config |
| **Drush** | Entity queries, field value export, config inspection |
| **Database** | Direct access to body/text field tables containing serialized block HTML |
| **JSON:API** | Field values via REST; body.value contains the raw block HTML |

---

## 1. Detection: Is Gutenberg Enabled?

### 1a. Module Check

```bash
# Drush
drush pm:list --status=enabled --filter=gutenberg --format=list

# Database
SELECT name, status FROM system WHERE name = 'gutenberg' AND status = 1;
# D8+ uses key_value instead:
# Check config table for gutenberg entries
SELECT name FROM config WHERE name LIKE 'gutenberg.%';
```

### 1b. Which Content Types Use Gutenberg

Gutenberg stores its per-content-type settings in `gutenberg.settings` config (versions 2.x and 3.x) or in the content type's `third_party_settings` (version 4.x+).

**Version 2.x/3.x** (most common in production):

```yaml
# gutenberg.settings.yml
# Pattern: {content_type}_enable_full: true
article_enable_full: true
article_template: '[["core/heading",{}],["core/paragraph",{"placeholder":"Write here"}]]'
article_template_lock: none
article_allowed_blocks:
  core/paragraph: core/paragraph
  core/heading: core/heading
  core/image: core/image
  core/list: core/list
landing_page_enable_full: true
```

The keys follow this pattern:

| Config key | Purpose |
|---|---|
| `{type}_enable_full` | Boolean. Gutenberg is active for this content type. |
| `{type}_template` | JSON array defining the default block structure. |
| `{type}_template_lock` | `none`, `insert`, or `all`. Controls editor freedom. |
| `{type}_allowed_blocks` | Which Gutenberg blocks editors can use. |
| `{type}_allowed_drupal_blocks` | Which native Drupal blocks are exposed in the editor. |

```bash
# Drush: dump entire Gutenberg config
drush config:get gutenberg.settings --format=yaml

# Find all content types with Gutenberg enabled
drush config:get gutenberg.settings --format=yaml | grep '_enable_full: true'
```

```sql
-- Database: find Gutenberg-enabled content types
SELECT name, data FROM config WHERE name = 'gutenberg.settings';
-- Deserialize the blob and look for keys ending in _enable_full with truthy values.
```

**Version 4.x+** (uses third_party_settings on the content type entity):

```yaml
# node.type.article.yml (excerpt)
third_party_settings:
  gutenberg:
    enable: true
    template: '...'
    template_lock: none
```

```bash
# Drush: check a specific content type
drush config:get node.type.article third_party_settings.gutenberg

# Find all content types with Gutenberg in third_party_settings
for type in $(drush config:list --prefix=node.type --format=list); do
  enabled=$(drush config:get "$type" third_party_settings.gutenberg.enable 2>/dev/null)
  if [ "$enabled" = "true" ]; then
    echo "$type"
  fi
done
```

### 1c. Identify the Target Text Field

Gutenberg writes its block HTML into the first `text_long` (or `text_with_summary`) field on the content type. This is almost always `body`, but the module picks the first text field it finds. In version 4.x, admins can configure which field receives the block content.

```bash
# Check which field holds Gutenberg content for a content type
drush field:info --entity-type=node --bundle=article --format=table
# Look for the first field with type text_long or text_with_summary
```

The field's text format will be set to `gutenberg`. Check:

```bash
drush config:get filter.format.gutenberg --format=yaml
```

---

## 2. Storage Format

Gutenberg stores content as serialized HTML with block delimiters inside HTML comments. The field value is a single string containing the full page content. This is the same format WordPress uses.

### 2a. Block Serialization Format

A block consists of:
1. An opening comment: `<!-- wp:block-name {"attr":"value"} -->`
2. The block's HTML content (innerHTML)
3. A closing comment: `<!-- /wp:block-name -->`

Self-closing blocks (no inner content) use: `<!-- wp:block-name {"attr":"value"} /-->`

Example of a real field value from Drupal Gutenberg:

```html
<!-- wp:heading {"level":2} -->
<h2>About Our Company</h2>
<!-- /wp:heading -->

<!-- wp:paragraph -->
<p>We build software that matters.</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":42,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large">
  <img src="/sites/default/files/2024-01/team-photo.jpg" alt="Team photo" class="wp-image-42"/>
  <figcaption>The team at our annual retreat</figcaption>
</figure>
<!-- /wp:image -->

<!-- wp:columns -->
<div class="wp-block-columns">
  <!-- wp:column -->
  <div class="wp-block-column">
    <!-- wp:paragraph -->
    <p>Left column content.</p>
    <!-- /wp:paragraph -->
  </div>
  <!-- /wp:column -->

  <!-- wp:column -->
  <div class="wp-block-column">
    <!-- wp:paragraph -->
    <p>Right column content.</p>
    <!-- /wp:paragraph -->
  </div>
  <!-- /wp:column -->
</div>
<!-- /wp:columns -->

<!-- wp:latest-posts {"postsToShow":4,"displayPostDate":true} /-->
```

### 2b. Formal Block Structure

Each parsed block produces this structure:

| Property | Type | Description |
|---|---|---|
| `blockName` | string or null | Namespace/name, e.g. `core/paragraph`. Null for free-form HTML between blocks. |
| `attrs` | dict | JSON attributes from the opening comment. |
| `innerHTML` | string | The HTML between the opening and closing comment delimiters. |
| `innerBlocks` | list | Nested child blocks (recursive). |
| `innerContent` | list | Mix of HTML string fragments and null markers where inner blocks appear. |

Blocks with `blockName: null` represent loose HTML between defined blocks. These are called "freeform" blocks.

### 2c. Attribute Storage

Block attributes are JSON-encoded inside the opening comment. The JSON object sits between the block name and the closing `-->`:

```
<!-- wp:image {"id":42,"sizeSlug":"large","linkDestination":"none"} -->
```

Some attributes are also encoded as HTML attributes or CSS classes in the innerHTML. The `id` in the comment might reference a Drupal file ID. The `className` attribute adds CSS classes. The `align` attribute adds alignment classes.

---

## 3. Block Type Catalog

### 3a. Core Blocks

These ship with Gutenberg and work in both WordPress and Drupal:

| Block name | HTML output | Notes |
|---|---|---|
| `core/paragraph` | `<p>` | Default block. Content in innerHTML. |
| `core/heading` | `<h1>`..`<h6>` | `level` attribute (1-6, default 2). |
| `core/image` | `<figure><img></figure>` | `id` references file/media entity. `sizeSlug` maps to image style. |
| `core/list` | `<ul>` or `<ol>` | `ordered` attribute (boolean). List items in innerHTML. |
| `core/list-item` | `<li>` | Child of `core/list`. |
| `core/quote` | `<blockquote>` | Inner paragraphs as innerBlocks. `citation` in innerHTML. |
| `core/table` | `<figure><table>` | `head`, `body`, `foot` arrays in attrs. |
| `core/columns` | `<div>` wrapper | Contains `core/column` innerBlocks. |
| `core/column` | `<div>` | `width` attribute (percentage). |
| `core/group` | `<div>` wrapper | Generic container. `layout` attribute. |
| `core/cover` | `<div>` with background | `url`, `id`, `dimRatio`, `overlayColor` in attrs. |
| `core/gallery` | `<figure>` wrapper | Contains `core/image` innerBlocks. |
| `core/separator` | `<hr>` | Self-closing or minimal. |
| `core/spacer` | `<div>` | `height` attribute in pixels. |
| `core/buttons` | `<div>` wrapper | Contains `core/button` innerBlocks. |
| `core/button` | `<div><a>` | `url`, `text`, `linkTarget` in attrs. |
| `core/html` | raw HTML | Custom HTML block. Content in innerHTML. |
| `core/code` | `<pre><code>` | Preformatted code. |
| `core/preformatted` | `<pre>` | Preformatted text. |
| `core/pullquote` | `<figure><blockquote>` | Styled quote variant. |
| `core/verse` | `<pre>` | Poetry/verse formatting. |
| `core/embed` | `<figure>` with iframe | `url`, `providerNameSlug` in attrs. Covers YouTube, Twitter, etc. |

### 3b. Drupal-Specific Blocks

The Gutenberg module exposes native Drupal blocks in the editor. These use the `drupalblock/` prefix:

```html
<!-- wp:drupalblock/views_block__latest_news-block_1 /-->
<!-- wp:drupalblock/system_branding_block /-->
```

These are always self-closing. Drupal renders them server-side at display time. The block content is not stored in the field value. During export, you need to resolve what these blocks reference separately.

### 3c. Custom Blocks

Themes and modules register custom blocks via `*.gutenberg.yml` files and JavaScript:

```yaml
# mytheme.gutenberg.yml
custom-blocks:
  categories:
    - reference: layout
      name: Layout
      blocks:
        - id: layout/hero-section
          name: Hero Section
        - id: layout/card-grid
          name: Card Grid
    - reference: content
      name: Content
      blocks:
        - id: content/testimonial
          name: Testimonial
```

Custom block JavaScript lives in the module or theme's JS directory. The block registration uses the WordPress `registerBlockType` API:

```javascript
wp.blocks.registerBlockType('mytheme/hero-section', {
  title: 'Hero Section',
  category: 'layout',
  attributes: {
    heading: { type: 'string' },
    backgroundUrl: { type: 'string' },
    ctaText: { type: 'string' },
    ctaUrl: { type: 'string' },
  },
  // edit and save functions define the editor UI and serialized output
});
```

To catalog all custom blocks on a site:

```bash
# Find all gutenberg.yml files
find . -name '*.gutenberg.yml' -not -path '*/node_modules/*'

# Search theme/module JS for registerBlockType calls
grep -r 'registerBlockType' --include='*.js' --include='*.jsx' \
  themes/ modules/custom/
```

---

## 4. Reusable Blocks

Gutenberg reusable blocks are stored as `block_content` entities with the bundle `reusable_block`. The body field of each reusable block entity contains serialized block HTML in the same format as node body fields.

### 4a. How They Appear in Content

A reusable block reference in serialized content looks like:

```html
<!-- wp:block {"ref":17} /-->
```

The `ref` attribute is the `block_content` entity ID. The block is self-closing because its content lives in the referenced entity, not inline.

### 4b. Export Reusable Blocks

```bash
# Drush: list all reusable blocks
drush entity:list block_content --bundle=reusable_block --format=json

# Drush: export a specific reusable block
drush entity:load block_content 17 --format=json
```

```sql
-- Database: all reusable block entities
SELECT bc.id, bcfd.info, bcfd.status
FROM block_content bc
JOIN block_content_field_data bcfd ON bc.id = bcfd.id
WHERE bc.type = 'reusable_block';

-- Get the body (block HTML) for each
SELECT entity_id, body_value, body_format
FROM block_content__body
WHERE bundle = 'reusable_block';
```

```
GET /jsonapi/block_content/reusable_block?fields[block_content--reusable_block]=info,body
```

### 4c. Resolution During Export

When parsing node content and you hit `<!-- wp:block {"ref":17} /-->`, you must:

1. Load `block_content` entity 17
2. Extract its `body.value`
3. Parse that body value through the same block parser
4. Inline the result or keep the reference, depending on your target platform

Track reusable block usage across all content to build a dependency map:

```sql
-- Find all nodes that reference reusable blocks
SELECT nid, body_value
FROM node__body
WHERE body_value LIKE '%<!-- wp:block {%ref%/-->%';
```

---

## 5. Media Handling

Gutenberg in Drupal handles media differently from standard Drupal media_embed. The module has its own upload pipeline and reference system.

### 5a. Image Blocks

Image blocks store a Drupal file entity ID in the `id` attribute and the file URL in the innerHTML:

```html
<!-- wp:image {"id":42,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large">
  <img src="/sites/default/files/2024-01/photo.jpg" alt="Description" class="wp-image-42"/>
</figure>
<!-- /wp:image -->
```

The `id` attribute (42) corresponds to the file entity ID (`file_managed.fid`) when the `media` module is not installed. When the `media` module is installed, Gutenberg creates both a file entity and a media entity. The `id` may reference either depending on the module version.

The `sizeSlug` maps to Drupal image styles. `full` means the original. Other values match image style machine names.

### 5b. The file_managed_data Table

The Gutenberg module creates a `file_managed_data` table to store extra metadata about uploaded files:

```sql
-- Schema
CREATE TABLE file_managed_data (
  fid INT UNSIGNED NOT NULL DEFAULT 0,
  data LONGBLOB
);

-- Query
SELECT fid, data FROM file_managed_data;
-- data column contains serialized PHP or JSON with Gutenberg-specific file metadata
```

### 5c. Media Upload Pipeline

When a user uploads a file through the Gutenberg editor:

1. The file hits `MediaController::upload`
2. The `MediaService` saves a `file_managed` entity
3. If the `media` module is enabled, a `media` entity is also created
4. The response returns the file URL and entity IDs
5. The block stores the file ID in its attributes and the URL in the HTML

### 5d. Gallery Blocks

Gallery blocks contain multiple image blocks as inner blocks:

```html
<!-- wp:gallery {"linkTo":"none"} -->
<figure class="wp-block-gallery has-nested-images columns-default is-cropped">
  <!-- wp:image {"id":42,"sizeSlug":"large"} -->
  <figure class="wp-block-image size-large">
    <img src="/sites/default/files/photo1.jpg" alt="" class="wp-image-42"/>
  </figure>
  <!-- /wp:image -->

  <!-- wp:image {"id":43,"sizeSlug":"large"} -->
  <figure class="wp-block-image size-large">
    <img src="/sites/default/files/photo2.jpg" alt="" class="wp-image-43"/>
  </figure>
  <!-- /wp:image -->
</figure>
<!-- /wp:gallery -->
```

### 5e. Cover Blocks

Cover blocks use a background image:

```html
<!-- wp:cover {"url":"/sites/default/files/banner.jpg","id":55,"dimRatio":50} -->
<div class="wp-block-cover"><span class="wp-block-cover__background has-background-dim"></span>
  <img class="wp-block-cover__image-background wp-image-55" src="/sites/default/files/banner.jpg" alt=""/>
  <div class="wp-block-cover__inner-container">
    <!-- wp:heading {"level":1} -->
    <h1>Welcome</h1>
    <!-- /wp:heading -->
  </div>
</div>
<!-- /wp:cover -->
```

### 5f. Extract All Media References

To find every file referenced by Gutenberg content:

```sql
-- Images: extract file IDs from block comments
SELECT nid, body_value
FROM node__body
WHERE body_value LIKE '%<!-- wp:image%'
   OR body_value LIKE '%<!-- wp:cover%'
   OR body_value LIKE '%<!-- wp:gallery%'
   OR body_value LIKE '%<!-- wp:media-text%';
```

Then parse the `id` attributes from the block comments and resolve them against `file_managed`:

```sql
SELECT fm.fid, fm.uri, fm.filename, fm.filemime, fm.filesize
FROM file_managed fm
WHERE fm.fid IN (/* extracted IDs */);
```

---

## 6. Block Parser Implementation

The block serialization format is defined by a PEG grammar in the WordPress `@wordpress/block-serialization-spec-parser` package. For migration, you need a parser that converts the serialized HTML string into a structured block tree.

### 6a. Python Block Parser

This parser handles the core serialization format: opening comments, closing comments, self-closing blocks, nested blocks, and freeform HTML between blocks.

```python
"""
Gutenberg block parser for Drupal/WordPress serialized content.

Parses <!-- wp:name {"attrs"} -->innerHTML<!-- /wp:name --> delimiters
into a structured block tree.
"""

import re
import json
from typing import Optional


# Matches opening block comment: <!-- wp:namespace/name {"json":true} -->
BLOCK_OPEN = re.compile(
    r'<!--\s+wp:([a-z][a-z0-9-]*/)?([a-z][a-z0-9-]*)\s*'
    r'(\{[^}]*\})?\s*'
    r'(/?)\s*-->'
)


def parse_blocks(content: str) -> list[dict]:
    """
    Parse serialized Gutenberg HTML into a list of block dicts.

    Each block dict has:
        blockName: str or None (None for freeform HTML)
        attrs: dict
        innerHTML: str
        innerBlocks: list[dict]
        innerContent: list[str | None]

    Freeform HTML between blocks gets blockName=None.
    """
    blocks = []
    pos = 0
    length = len(content)

    while pos < length:
        match = BLOCK_OPEN.search(content, pos)

        if match is None:
            # Remaining content is freeform HTML
            remainder = content[pos:]
            if remainder.strip():
                blocks.append(_freeform_block(remainder))
            break

        # Freeform HTML before this block
        if match.start() > pos:
            freeform = content[pos:match.start()]
            if freeform.strip():
                blocks.append(_freeform_block(freeform))

        namespace = match.group(1) or 'core/'
        name = match.group(2)
        block_name = namespace.rstrip('/') + '/' + name
        attrs_json = match.group(3)
        self_closing = match.group(4) == '/'

        attrs = {}
        if attrs_json:
            try:
                attrs = json.loads(attrs_json)
            except json.JSONDecodeError:
                attrs = {"_raw_attrs": attrs_json}

        if self_closing:
            blocks.append({
                'blockName': block_name,
                'attrs': attrs,
                'innerHTML': '',
                'innerBlocks': [],
                'innerContent': [],
            })
            pos = match.end()
            continue

        # Find the matching closing tag
        inner_html, inner_blocks, inner_content, end_pos = _parse_block_body(
            content, match.end(), block_name
        )

        blocks.append({
            'blockName': block_name,
            'attrs': attrs,
            'innerHTML': inner_html,
            'innerBlocks': inner_blocks,
            'innerContent': inner_content,
        })
        pos = end_pos

    return blocks


def _parse_block_body(
    content: str, start: int, parent_name: str
) -> tuple[str, list[dict], list, int]:
    """
    Parse the body of a block from start until the matching closing tag.

    Returns (innerHTML, innerBlocks, innerContent, end_position).
    innerHTML has inner block regions replaced with empty strings.
    innerContent has None markers where inner blocks appeared.
    """
    closing_tag = re.compile(
        r'<!--\s+/wp:' + re.escape(parent_name) + r'\s*-->'
    )

    inner_blocks = []
    inner_content = []
    inner_html = ''
    pos = start

    while True:
        # Look for either a nested block opening or our closing tag
        close_match = closing_tag.search(content, pos)
        if close_match is None:
            # Malformed: no closing tag found. Take everything remaining.
            inner_html += content[pos:]
            inner_content.append(content[pos:])
            return inner_html, inner_blocks, inner_content, len(content)

        # Check for nested block openings before the closing tag
        nested_match = BLOCK_OPEN.search(content, pos)

        if nested_match is None or nested_match.start() >= close_match.start():
            # No nested blocks before closing tag
            html_fragment = content[pos:close_match.start()]
            if html_fragment:
                inner_html += html_fragment
                inner_content.append(html_fragment)
            end_pos = close_match.end()
            return inner_html, inner_blocks, inner_content, end_pos

        # There is a nested block before the closing tag
        # Capture HTML before the nested block
        html_before = content[pos:nested_match.start()]
        if html_before:
            inner_html += html_before
            inner_content.append(html_before)

        # Parse the nested block
        namespace = nested_match.group(1) or 'core/'
        name = nested_match.group(2)
        nested_name = namespace.rstrip('/') + '/' + name
        attrs_json = nested_match.group(3)
        self_closing = nested_match.group(4) == '/'

        nested_attrs = {}
        if attrs_json:
            try:
                nested_attrs = json.loads(attrs_json)
            except json.JSONDecodeError:
                nested_attrs = {"_raw_attrs": attrs_json}

        if self_closing:
            nested_block = {
                'blockName': nested_name,
                'attrs': nested_attrs,
                'innerHTML': '',
                'innerBlocks': [],
                'innerContent': [],
            }
            inner_blocks.append(nested_block)
            inner_content.append(None)  # Marker for inner block position
            pos = nested_match.end()
        else:
            nested_html, nested_inner, nested_ic, nested_end = _parse_block_body(
                content, nested_match.end(), nested_name
            )
            nested_block = {
                'blockName': nested_name,
                'attrs': nested_attrs,
                'innerHTML': nested_html,
                'innerBlocks': nested_inner,
                'innerContent': nested_ic,
            }
            inner_blocks.append(nested_block)
            inner_content.append(None)
            pos = nested_end


def _freeform_block(html: str) -> dict:
    """Create a freeform (non-block) content entry."""
    return {
        'blockName': None,
        'attrs': {},
        'innerHTML': html,
        'innerBlocks': [],
        'innerContent': [html],
    }


# --- Convenience functions ---

def flatten_blocks(blocks: list[dict]) -> list[dict]:
    """
    Flatten a nested block tree into a flat list.
    Each block gets a 'depth' key indicating nesting level.
    """
    result = []
    _flatten_recursive(blocks, 0, result)
    return result


def _flatten_recursive(blocks: list[dict], depth: int, result: list[dict]):
    for block in blocks:
        flat = {**block, 'depth': depth}
        flat.pop('innerBlocks', None)
        result.append(flat)
        if block.get('innerBlocks'):
            _flatten_recursive(block['innerBlocks'], depth + 1, result)


def extract_media_ids(blocks: list[dict]) -> list[dict]:
    """
    Walk the block tree and extract all media file references.
    Returns list of dicts with blockName, file_id, and url (if found in HTML).
    """
    results = []
    _extract_media_recursive(blocks, results)
    return results


def _extract_media_recursive(blocks: list[dict], results: list[dict]):
    for block in blocks:
        name = block.get('blockName') or ''
        attrs = block.get('attrs') or {}

        if name in ('core/image', 'core/cover', 'core/media-text', 'core/video'):
            entry = {
                'blockName': name,
                'file_id': attrs.get('id'),
                'sizeSlug': attrs.get('sizeSlug'),
            }
            # Try to extract URL from innerHTML
            src_match = re.search(r'src="([^"]+)"', block.get('innerHTML', ''))
            if src_match:
                entry['url'] = src_match.group(1)
            results.append(entry)

        if block.get('innerBlocks'):
            _extract_media_recursive(block['innerBlocks'], results)


def extract_reusable_refs(blocks: list[dict]) -> list[int]:
    """
    Walk the block tree and return all reusable block entity IDs.
    """
    refs = []
    for block in blocks:
        if block.get('blockName') == 'core/block':
            ref = (block.get('attrs') or {}).get('ref')
            if ref is not None:
                refs.append(int(ref))
        if block.get('innerBlocks'):
            refs.extend(extract_reusable_refs(block['innerBlocks']))
    return refs
```

### 6b. Usage

```python
import json

# From database query or Drush export
raw_body = """<!-- wp:heading {"level":2} -->
<h2>Hello World</h2>
<!-- /wp:heading -->

<!-- wp:paragraph -->
<p>Some text here.</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":42,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large">
  <img src="/sites/default/files/photo.jpg" alt="Photo" class="wp-image-42"/>
</figure>
<!-- /wp:image -->

<!-- wp:block {"ref":17} /-->"""

blocks = parse_blocks(raw_body)
print(json.dumps(blocks, indent=2))

# Extract media references
media = extract_media_ids(blocks)
# [{'blockName': 'core/image', 'file_id': 42, 'sizeSlug': 'large', 'url': '/sites/default/files/photo.jpg'}]

# Find reusable block dependencies
refs = extract_reusable_refs(blocks)
# [17]

# Flatten the tree
flat = flatten_blocks(blocks)
for b in flat:
    print(f"{'  ' * b['depth']}{b['blockName']}: {list(b['attrs'].keys())}")
```

### 6c. Edge Cases

| Case | Behavior |
|---|---|
| No namespace prefix | Parser defaults to `core/`. `<!-- wp:paragraph -->` becomes `core/paragraph`. |
| Malformed JSON in attrs | Store as `_raw_attrs` string. Do not discard the block. |
| Missing closing tag | Consume to end of content. Log a warning. |
| `blockName: null` | Freeform HTML between blocks. Preserve as-is. |
| Nested blocks inside `core/columns` | `innerBlocks` contains `core/column` children, each with their own `innerBlocks`. |
| Empty block | Self-closing block with no attrs, e.g. `<!-- wp:separator /-->`. |
| Classic editor content | A single freeform block (blockName=null) covering the entire body. |

---

## 7. Field Mapping

The Gutenberg module supports mapping block content back to Drupal fields on save. When a content type has a template with `mappingField` or `mappingFields` attributes, the module's `hook_entity_presave` extracts values from blocks and writes them into separate Drupal fields.

This means the same content may exist in two places:
1. Inside the serialized block HTML in the body field
2. In dedicated Drupal fields (populated by field mapping on save)

Check whether field mapping is active:

```bash
# Look for mappingField or mappingFields in templates
drush config:get gutenberg.settings --format=yaml | grep -i mapping

# Or search the template JSON
drush config:get gutenberg.settings article_template
# Look for "mappingField" or "mappingFields" in the JSON string
```

When field mapping is active, the dedicated fields contain the authoritative extracted values. The body field contains the full block HTML including those mapped sections. During export, prefer the dedicated fields for mapped data and the body field for everything else.

---

## 8. Access Patterns

### 8a. Database Direct

```sql
-- All Gutenberg content: nodes where the body contains wp: block delimiters
SELECT n.nid, n.type, nb.body_value, nb.body_format
FROM node n
JOIN node__body nb ON n.nid = nb.entity_id
WHERE nb.body_value LIKE '%<!-- wp:%'
ORDER BY n.type, n.nid;

-- Count of Gutenberg nodes per content type
SELECT n.type, COUNT(*) as count
FROM node n
JOIN node__body nb ON n.nid = nb.entity_id
WHERE nb.body_value LIKE '%<!-- wp:%'
GROUP BY n.type;

-- If the text field is not body but a custom field (e.g., field_content):
SELECT entity_id, field_content_value
FROM node__field_content
WHERE field_content_value LIKE '%<!-- wp:%';
```

### 8b. Drush

```bash
# Export all nodes of a Gutenberg-enabled type
drush sql:query "SELECT nid, body_value FROM node__body WHERE bundle='article' AND body_value LIKE '%<!-- wp:%'" \
  --result-file=/tmp/gutenberg_articles.csv

# Export as JSON using entity:load
for nid in $(drush entity:list node --bundle=article --format=list); do
  drush entity:load node "$nid" --format=json >> /tmp/articles.jsonl
done
```

### 8c. JSON:API

```
# Get body field with block HTML
GET /jsonapi/node/article?fields[node--article]=title,body,created,changed

# Response structure:
# data[].attributes.body.value  -> serialized block HTML
# data[].attributes.body.format -> "gutenberg"
```

The body.value field in the JSON:API response contains the raw serialized block HTML. Parse it with the block parser.

---

## 9. Target Platform Mapping

### 9a. WordPress

Gutenberg blocks transfer with zero or minimal conversion. The serialization format is identical. The differences:

| Drupal-specific | WordPress equivalent | Action required |
|---|---|---|
| File entity IDs | WordPress attachment IDs | Re-map `id` attributes after importing media |
| `/sites/default/files/...` URLs | `/wp-content/uploads/...` URLs | Search-replace file paths in innerHTML |
| `drupalblock/*` blocks | No equivalent | Convert to WordPress shortcodes, widgets, or custom blocks |
| Image style slugs | WordPress image size slugs | Map `sizeSlug` values (e.g., `large` maps directly, custom styles need registration) |
| Reusable block entity IDs | `wp_block` post IDs | Re-map `ref` attributes after importing reusable blocks |
| Drupal media entities | WordPress attachments | Flatten to file references |

Migration steps:
1. Export all media files and create WordPress attachments. Build an ID mapping table (old Drupal fid -> new WP attachment ID).
2. Export reusable blocks as `wp_block` posts. Build an ID mapping table.
3. For each node's body value, do a search-replace on file paths, file IDs (in block attrs), and reusable block refs.
4. Strip or convert `drupalblock/*` references.
5. Import the modified HTML as `post_content`.

### 9b. Headless CMS (Contentful, Sanity, Strapi, etc.)

Decompose blocks into structured component data:

```python
def blocks_to_components(blocks: list[dict]) -> list[dict]:
    """Convert parsed blocks into portable component structures."""
    components = []
    for block in blocks:
        name = block.get('blockName')
        attrs = block.get('attrs') or {}

        if name == 'core/paragraph':
            components.append({
                'type': 'paragraph',
                'content': _strip_tags_preserve_inline(block['innerHTML']),
                'html': block['innerHTML'].strip(),
            })
        elif name == 'core/heading':
            components.append({
                'type': 'heading',
                'level': attrs.get('level', 2),
                'content': _strip_outer_tag(block['innerHTML']),
            })
        elif name == 'core/image':
            components.append({
                'type': 'image',
                'src': _extract_src(block['innerHTML']),
                'alt': _extract_alt(block['innerHTML']),
                'caption': _extract_figcaption(block['innerHTML']),
                'fileId': attrs.get('id'),
                'size': attrs.get('sizeSlug', 'full'),
            })
        elif name == 'core/columns':
            columns = []
            for col_block in block.get('innerBlocks', []):
                columns.append({
                    'width': (col_block.get('attrs') or {}).get('width'),
                    'components': blocks_to_components(
                        col_block.get('innerBlocks', [])
                    ),
                })
            components.append({
                'type': 'columns',
                'columns': columns,
            })
        elif name == 'core/list':
            components.append({
                'type': 'list',
                'ordered': attrs.get('ordered', False),
                'html': block['innerHTML'].strip(),
            })
        elif name == 'core/quote':
            components.append({
                'type': 'quote',
                'components': blocks_to_components(
                    block.get('innerBlocks', [])
                ),
                'citation': _extract_tag_content(block['innerHTML'], 'cite'),
            })
        elif name == 'core/block':
            components.append({
                'type': 'reusable_block_ref',
                'refId': attrs.get('ref'),
            })
        elif name is None:
            # Freeform HTML
            html = block['innerHTML'].strip()
            if html:
                components.append({
                    'type': 'raw_html',
                    'html': html,
                })
        else:
            # Unknown or custom block: preserve as generic
            components.append({
                'type': 'block',
                'blockName': name,
                'attrs': attrs,
                'html': block['innerHTML'].strip(),
                'children': blocks_to_components(
                    block.get('innerBlocks', [])
                ),
            })

    return components
```

### 9c. Static Sites (Hugo, Astro, Gatsby, Next.js)

Convert blocks to MDX components or plain HTML:

```python
def blocks_to_mdx(blocks: list[dict]) -> str:
    """Convert parsed blocks to MDX-compatible content."""
    parts = []
    for block in blocks:
        name = block.get('blockName')
        attrs = block.get('attrs') or {}
        html = block.get('innerHTML', '').strip()

        if name == 'core/paragraph':
            # Strip <p> tags for markdown
            text = _strip_outer_tag(html)
            parts.append(text + '\n')

        elif name == 'core/heading':
            level = attrs.get('level', 2)
            text = _strip_outer_tag(html)
            parts.append('#' * level + ' ' + text + '\n')

        elif name == 'core/image':
            src = _extract_src(html)
            alt = _extract_alt(html)
            caption = _extract_figcaption(html)
            if caption:
                parts.append(f'<Figure src="{src}" alt="{alt}" caption="{caption}" />\n')
            else:
                parts.append(f'![{alt}]({src})\n')

        elif name == 'core/list':
            parts.append(html + '\n')

        elif name == 'core/code':
            code_content = _strip_outer_tag(_strip_outer_tag(html))  # strip <pre><code>
            parts.append(f'```\n{code_content}\n```\n')

        elif name == 'core/quote':
            inner_text = _strip_outer_tag(html)
            for line in inner_text.split('\n'):
                parts.append(f'> {line}\n')

        elif name == 'core/separator':
            parts.append('---\n')

        elif name == 'core/columns':
            # MDX component for columns
            parts.append('<Columns>\n')
            for col in block.get('innerBlocks', []):
                parts.append('<Column>\n')
                parts.append(blocks_to_mdx(col.get('innerBlocks', [])))
                parts.append('</Column>\n')
            parts.append('</Columns>\n')

        elif name is None:
            if html:
                parts.append(html + '\n')

        else:
            # Fallback: render as HTML block in MDX
            parts.append(f'<!-- block: {name} -->\n')
            parts.append(html + '\n')
            if block.get('innerBlocks'):
                parts.append(blocks_to_mdx(block['innerBlocks']))

    return '\n'.join(parts)
```

---

## 10. Full Export Pipeline

### Step 1: Identify Gutenberg content types

```bash
drush config:get gutenberg.settings --format=yaml | grep '_enable_full: true'
```

### Step 2: Export reusable blocks

```sql
SELECT bc.id, bcfd.info, b.body_value
FROM block_content bc
JOIN block_content_field_data bcfd ON bc.id = bcfd.id
JOIN block_content__body b ON bc.id = b.entity_id
WHERE bc.type = 'reusable_block';
```

### Step 3: Export node content

```sql
SELECT n.nid, n.type, nfd.title, nb.body_value, nb.body_format,
       nfd.created, nfd.changed, nfd.status
FROM node n
JOIN node_field_data nfd ON n.nid = nfd.nid
JOIN node__body nb ON n.nid = nb.entity_id
WHERE nb.body_value LIKE '%<!-- wp:%'
ORDER BY n.type, n.nid;
```

### Step 4: Export media files

```sql
SELECT fm.fid, fm.uri, fm.filename, fm.filemime, fm.filesize, fm.created
FROM file_managed fm
WHERE fm.fid IN (
  -- IDs extracted from parsed block attrs
  SELECT DISTINCT fid FROM file_managed_data
);
```

### Step 5: Parse and transform

```python
import json

# Load exported data
nodes = load_exported_nodes()         # from step 3
reusable = load_reusable_blocks()     # from step 2
media_map = load_media_files()        # from step 4

for node in nodes:
    # Parse block HTML
    blocks = parse_blocks(node['body_value'])

    # Resolve reusable block references
    blocks = resolve_reusable_blocks(blocks, reusable)

    # Extract and remap media references
    media_refs = extract_media_ids(blocks)

    # Transform for target platform
    if target == 'wordpress':
        output = remap_ids_and_paths(node['body_value'], id_map, path_map)
    elif target == 'headless':
        output = blocks_to_components(blocks)
    elif target == 'static':
        output = blocks_to_mdx(blocks)

    write_output(node['nid'], output)
```

### Step 6: Validate

For each exported node, confirm:
- All blocks parsed without errors (no `_raw_attrs` entries)
- All reusable block references resolved
- All media file IDs map to actual files
- No `drupalblock/*` references remain unhandled
- Block count matches between source and target

---

## 11. What Can Go Wrong

| Problem | Cause | Fix |
|---|---|---|
| Body field is empty but node has content | Gutenberg may store in a custom field, not `body` | Check all `text_long` fields on the content type |
| Block comments stripped | Text format filter ran before export, stripping comments | Export raw `body_value` from database, not rendered output |
| `id` attributes don't match `file_managed` | Media module creates media entities; `id` may be media entity ID | Check both `file_managed.fid` and `media.mid` |
| Custom blocks with no HTML output | Dynamic/server-rendered blocks store attrs only | Find the rendering code in the module/theme to understand the output |
| Reusable block body is empty | The reusable block was deleted but references remain | Log missing refs and skip or remove the block reference |
| Mixed content: some blocks, some raw HTML | Editor switched between Gutenberg and CKEditor | Parse tolerantly; freeform blocks capture the non-Gutenberg content |
| `gutenberg.settings` missing | Module enabled but never configured per content type | Check theme's `*.gutenberg.yml` and third_party_settings |
| Nested block depth exceeds parser recursion | Python default recursion limit (1000) | Set `sys.setrecursionlimit()` or convert parser to iterative |

---

## 12. Post-Uninstall Cleanup

After migrating content off Drupal, if you uninstall the Gutenberg module:

1. The `gutenberg` text format is deleted. Fields using it lose their format assignment. Set a replacement format (e.g., `basic_html`) on all affected fields before uninstalling.
2. The `file_managed_data` table is dropped.
3. The block content in body fields remains as-is. The `<!-- wp:* -->` comments stay in the HTML. Without the Gutenberg text format filter, they render as invisible HTML comments in the browser.
4. The `reusable_block` block_content bundle and its entities remain (they are standard Drupal entities).
5. Gutenberg-specific config (`gutenberg.settings`) is deleted.

The content degrades gracefully: the HTML between block comments is valid HTML and renders without Gutenberg. Layout-dependent blocks (columns, cover) lose their styling but the text content survives.
