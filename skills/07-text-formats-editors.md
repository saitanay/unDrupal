# Skill 7: Text Formats, Filters, and Editor Configuration

You are extracting every text format definition, its filter pipeline, and its editor (CKEditor) configuration from a Drupal site. This data tells you exactly how rich text gets processed on its way from the editor to the database to the rendered page. Without it, migrated HTML will contain Drupal-specific markup that breaks in any other system.

---

## What You Are Extracting

| Component | What It Contains | Why It Matters |
|---|---|---|
| **Text formats** | Machine name, label, weight (priority), roles allowed | Determines which users can create which kinds of HTML |
| **Filter pipeline** | Ordered list of filter plugins per format, each with status/weight/settings | Filters transform stored HTML at render time. Some add markup. Some strip it. Order matters. |
| **Editor config** | CKEditor toolbar layout, plugin settings, allowed/disallowed HTML tags | Controls what authors can enter. Defines the contract between stored HTML and the filter pipeline. |
| **Linkit profiles** | Autocomplete link configurations that inject `data-entity-type` and `data-entity-uuid` attributes | These attributes are Drupal-specific. Every link using Linkit needs cleanup during migration. |

---

## Access Patterns

Use the best method available. Priority order:

### 1. Config YAML (D8/D9/D10/D11)

Text format config lives in two file families:

```
config/sync/filter.format.*.yml        # Format definition + filter pipeline
config/sync/editor.editor.*.yml        # CKEditor config tied to a format
config/sync/linkit.linkit_profile.*.yml # Linkit autocomplete profiles
```

Export config if you have Drush:

```bash
drush config:export --destination=/tmp/config-export
ls /tmp/config-export/filter.format.*.yml
ls /tmp/config-export/editor.editor.*.yml
ls /tmp/config-export/linkit.linkit_profile.*.yml
```

Or pull individual formats:

```bash
# List all text formats
drush config:list | grep filter.format

# Get one format's full config
drush config:get filter.format.full_html
drush config:get editor.editor.full_html
```

### 2. Drush Commands

```bash
# List text formats with status
drush php:eval "foreach(\Drupal\filter\Entity\FilterFormat::loadMultiple() as \$f) { echo \$f->id() . ' | ' . \$f->label() . ' | weight:' . \$f->get('weight') . ' | status:' . (\$f->status() ? 'enabled' : 'disabled') . PHP_EOL; }"

# List filters for a specific format
drush php:eval "\$f = \Drupal\filter\Entity\FilterFormat::load('full_html'); foreach(\$f->filters()->getAll() as \$id => \$filter) { echo \$id . ' | status:' . \$filter->status . ' | weight:' . \$filter->weight . PHP_EOL; }"

# Dump all format + filter config as JSON
drush php:eval "echo json_encode(array_map(function(\$f) { return \$f->toArray(); }, \Drupal\filter\Entity\FilterFormat::loadMultiple()), JSON_PRETTY_PRINT);"
```

### 3. Database (D8/D9/D10/D11)

Config is stored serialized in the `config` table:

```sql
-- All text format configs
SELECT name, data FROM config WHERE name LIKE 'filter.format.%';

-- All editor configs
SELECT name, data FROM config WHERE name LIKE 'editor.editor.%';

-- All linkit profiles
SELECT name, data FROM config WHERE name LIKE 'linkit.linkit_profile.%';
```

The `data` column contains PHP-serialized YAML. Unserialize with PHP or export via Drush.

### 4. Database (Drupal 7)

D7 stores text formats in dedicated tables, not config YAML:

```sql
-- All text formats
SELECT format, name, status, weight FROM filter_format ORDER BY weight;

-- All filters per format
SELECT format, name, module, status, weight, settings
FROM filter
ORDER BY format, weight;

-- CKEditor profiles (if ckeditor module is installed)
SELECT name, settings FROM ckeditor_settings;

-- WYSIWYG module profiles (alternative to ckeditor module in D7)
SELECT format, editor, settings FROM wysiwyg;
```

D7 filter `settings` column is a PHP serialized array. Unserialize it.

### 5. Admin UI

Visit these paths and record what you see:

- `/admin/config/content/formats` lists all text formats
- `/admin/config/content/formats/manage/{format_name}` shows filters and editor config for each format
- `/admin/config/content/linkit` lists Linkit profiles (if module installed)

---

## Config YAML Structure

### filter.format.*.yml

This is the complete structure. Every text format follows this pattern.

```yaml
uuid: 12345678-1234-1234-1234-123456789abc
langcode: en
status: true
dependencies:
  module:
    - editor
    - media
    - filter
  config:
    - editor.editor.full_html
name: Full HTML
format: full_html
weight: 0
roles:
  - authenticated
  - administrator
filters:
  filter_html:
    id: filter_html
    provider: filter
    status: true
    weight: -10
    settings:
      allowed_html: '<br> <p> <a href hreflang> <em> <strong> <ul> <ol> <li> <blockquote cite> <h2 id> <h3 id> <h4 id> <h5 id> <img src alt data-entity-type data-entity-uuid data-align data-caption> <table> <tr> <td> <th> <thead> <tbody> <caption> <drupal-media data-entity-type data-entity-uuid data-view-mode data-align data-caption alt>'
      filter_html_help: true
      filter_html_nofollow: false
  filter_autop:
    id: filter_autop
    provider: filter
    status: true
    weight: 0
    settings: {  }
  filter_url:
    id: filter_url
    provider: filter
    status: true
    weight: 0
    settings:
      filter_url_length: 72
  filter_htmlcorrector:
    id: filter_htmlcorrector
    provider: filter
    status: true
    weight: 10
    settings: {  }
  media_embed:
    id: media_embed
    provider: media
    status: true
    weight: 100
    settings:
      default_view_mode: default
      allowed_view_modes:
        full: full
        media_library: media_library
      allowed_media_types: {  }
  filter_align:
    id: filter_align
    provider: filter
    status: true
    weight: 200
    settings: {  }
  filter_caption:
    id: filter_caption
    provider: filter
    status: true
    weight: 300
    settings: {  }
```

Key fields:

- **`format`**: Machine name. This is the value stored in every text field's `format` column in the database.
- **`roles`**: Which roles can select this format when editing content. Empty means no restrictions (or fallback format).
- **`weight`**: Lower weight = higher priority. When a user has access to multiple formats, the lowest-weight format is the default.
- **`filters`**: Keyed by filter plugin ID. Each filter has `status` (enabled/disabled), `weight` (execution order), and `settings` (plugin-specific).

### editor.editor.*.yml

The editor config file pairs with a text format by machine name.

#### CKEditor 4 (Drupal 8, 9, early 10)

```yaml
uuid: abcdef12-3456-7890-abcd-ef1234567890
langcode: en
status: true
dependencies:
  config:
    - filter.format.full_html
  module:
    - ckeditor
format: full_html
editor: ckeditor
settings:
  toolbar:
    rows:
      -
        -
          name: Formatting
          items:
            - Bold
            - Italic
            - Underline
            - Strike
            - Superscript
            - Subscript
            - RemoveFormat
        -
          name: Lists
          items:
            - BulletedList
            - NumberedList
            - Outdent
            - Indent
            - Blockquote
        -
          name: Links
          items:
            - DrupalLink
            - DrupalUnlink
            - Linkit
        -
          name: Media
          items:
            - DrupalImage
            - DrupalMediaLibrary
        -
          name: Tools
          items:
            - Source
            - PasteFromWord
            - ShowBlocks
            - Maximize
        -
          name: Styles
          items:
            - Format
            - Styles
            - Table
  plugins:
    stylescombo:
      styles: "h2.title|Title\r\np.callout|Callout\r\nspan.highlight|Highlight"
    language:
      language_list: 'un'
image_upload:
  status: true
  scheme: public
  directory: inline-images
  max_size: '2 MB'
  max_dimensions:
    width: 1920
    height: 1080
```

CKEditor 4 structure:

- **`toolbar.rows`**: Array of rows. Each row has groups. Each group has a `name` and `items` array.
- **`plugins`**: Plugin-specific settings. `stylescombo.styles` defines the Styles dropdown. Format is `element.class|Label` separated by `\r\n`.
- **`image_upload`**: Controls inline image upload behavior. The `scheme`, `directory`, `max_size`, and `max_dimensions` settings determine where uploaded images land.

#### CKEditor 5 (Drupal 10.1+, required in Drupal 11)

CKEditor 5 config is structurally different. Drupal rewrote the integration.

```yaml
uuid: abcdef12-3456-7890-abcd-ef1234567890
langcode: en
status: true
dependencies:
  config:
    - filter.format.full_html
  module:
    - ckeditor5
    - media
    - media_library
format: full_html
editor: ckeditor5
settings:
  toolbar:
    items:
      - bold
      - italic
      - underline
      - strikethrough
      - superscript
      - subscript
      - removeFormat
      - '|'
      - bulletedList
      - numberedList
      - outdent
      - indent
      - blockQuote
      - '|'
      - link
      - drupalMedia
      - drupalInsertImage
      - '|'
      - insertTable
      - '|'
      - heading
      - style
      - codeBlock
      - horizontalLine
      - '|'
      - sourceEditing
  plugins:
    ckeditor5_heading:
      enabled_headings:
        - heading2
        - heading3
        - heading4
        - heading5
    ckeditor5_style:
      styles:
        -
          label: Callout
          element: '<p class="callout">'
        -
          label: Highlight
          element: '<span class="highlight">'
    ckeditor5_sourceEditing:
      allowed_tags:
        - '<div>'
        - '<span>'
        - '<cite>'
        - '<dl>'
        - '<dt>'
        - '<dd>'
    ckeditor5_list:
      properties:
        reversed: false
        startIndex: true
      multiBlock: true
    ckeditor5_alignment:
      enabled_alignments:
        - left
        - center
        - right
        - justify
    ckeditor5_imageResize:
      allow_resize: true
    ckeditor5_language:
      language_list: un
    media_media:
      allow_view_mode_override: true
    media_library:
      library_image_style: ''
    linkit_extension:
      linkit_enabled: true
      linkit_profile: default
image_upload:
  status: true
  scheme: public
  directory: inline-images
  max_size: '2 MB'
  max_dimensions:
    width: 1920
    height: 1080
```

CKEditor 5 differences from CKEditor 4:

| Aspect | CKEditor 4 | CKEditor 5 |
|---|---|---|
| Toolbar | Nested: `rows > groups > items`, items are PascalCase (`BulletedList`) | Flat array with `\|` pipe separators, items are camelCase (`bulletedList`) |
| Plugin config key | `plugins.stylescombo.styles` (newline-delimited string) | `plugins.ckeditor5_style.styles` (array of objects with `label` and `element`) |
| Editor module | `ckeditor` | `ckeditor5` |
| Source editing | Plugin button `Source` | Plugin `ckeditor5_sourceEditing` with explicit `allowed_tags` |
| Headings | Controlled by `Format` dropdown | `ckeditor5_heading.enabled_headings` array |
| Allowed HTML | Inferred from toolbar or set in `filter_html` | Strict: CKEditor 5 enforces its own allowed tags that must align with `filter_html` settings. Drupal shows a warning if they diverge. |
| Media | `DrupalMediaLibrary` button + `media_embed` filter | `drupalMedia` button + `media_media` plugin config + `media_embed` filter |

---

## Filter Plugin Reference

These are the filters you will encounter. Each one transforms HTML at render time. Understanding what each does tells you what processing you need to replicate or strip during migration.

### Core Filters (filter module)

| Filter ID | What It Does | Migration Impact |
|---|---|---|
| `filter_html` | Strips tags and attributes not in the allowed list | The `allowed_html` setting is your contract. Anything not listed gets removed on render. During migration, check if stored HTML contains tags that the filter would strip. |
| `filter_autop` | Converts line breaks to `<p>` and `<br>` tags | Stored HTML may contain raw line breaks instead of `<p>` tags. If you export rendered HTML, this is already applied. If you export raw stored HTML, you need to apply this conversion yourself. |
| `filter_url` | Converts plain-text URLs to clickable `<a>` links | Stored text may contain bare URLs like `https://example.com` without link markup. Rendered output wraps them in `<a>` tags. |
| `filter_htmlcorrector` | Fixes broken HTML (unclosed tags, bad nesting) | No migration impact unless stored HTML is intentionally malformed. |
| `filter_html_escape` | Escapes all HTML (plain text format) | The "Plain text" format uses this. All HTML is entity-encoded. No rich text. |

### Media and Entity Embedding Filters

These are the ones that cause the most migration pain.

| Filter ID | Provider Module | What It Does |
|---|---|---|
| `media_embed` | media | Converts `<drupal-media>` tags to rendered media entities |
| `entity_embed` | entity_embed (contrib) | Converts `<drupal-entity>` tags to rendered entities of any type |
| `filter_align` | filter | Processes `data-align` attributes into CSS alignment classes |
| `filter_caption` | filter | Wraps elements that have `data-caption` attributes in a `<figure>/<figcaption>` structure |

#### The `<drupal-media>` tag (media_embed filter)

This is what gets stored in the database when an author inserts media via CKEditor:

```html
<drupal-media data-entity-type="media" data-entity-uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890" data-view-mode="full" data-align="center" data-caption="Photo credit: Jane Doe" alt="A sunset over mountains"></drupal-media>
```

At render time, the `media_embed` filter:
1. Loads the media entity by UUID
2. Renders it using the specified `data-view-mode`
3. Applies alignment from `data-align`
4. Wraps it in `<figure>/<figcaption>` if `data-caption` exists (via `filter_caption`)

**Migration action**: Replace every `<drupal-media>` tag with the actual media output. You need the media entity's file URL, alt text, and any caption. Skill 14 (Media & Files) exports the media entities. Skill 26 (Rich Text Cleanup) handles the token replacement.

#### The `<drupal-entity>` tag (entity_embed filter)

Contrib module `entity_embed` uses a similar pattern:

```html
<drupal-entity data-entity-type="node" data-entity-uuid="f1e2d3c4-b5a6-7890-abcd-ef1234567890" data-entity-embed-display="view_mode:teaser" data-align="right"></drupal-entity>
```

This can embed any entity type: nodes, blocks, taxonomy terms, media. The `data-entity-embed-display` attribute controls how the entity renders. Values include:
- `view_mode:teaser`, `view_mode:full` (render as a view mode)
- `entity_reference:entity_reference_label` (render as a label link)
- `entity_reference:entity_reference_entity_id` (render as raw ID)

**Migration action**: Same as media_embed, but for any entity type. Map each embedded entity to its migrated equivalent.

#### Linkit-enhanced links

The Linkit module replaces the standard link dialog. Links created with Linkit store entity reference data:

```html
<a href="/node/42" data-entity-type="node" data-entity-uuid="a1b2c3d4-..." data-entity-substitution="canonical">Read more</a>
```

The `data-entity-type`, `data-entity-uuid`, and `data-entity-substitution` attributes are Drupal-specific. Standard HTML parsers ignore them, but they break the assumption that a link's `href` is the full story. During migration, you must:
1. Resolve the UUID to the migrated URL on the target platform
2. Update the `href`
3. Strip the `data-entity-*` attributes

### Token and Shortcode Filters

| Filter ID | Provider Module | What It Does |
|---|---|---|
| `token_filter` | token_filter (contrib) | Replaces `[token:name]` patterns with dynamic values (e.g., `[site:name]`, `[node:title]`, `[current-date:html_date]`) |
| `shortcode` | shortcode (contrib) | WordPress-style shortcodes like `[button url="/path"]Click[/button]` |
| `filter_markdown` | markdown (contrib) | Converts Markdown to HTML |
| `php_code` | php (contrib, D7 core) | Executes PHP code in content. **Security flag: any content using this format contains executable code. Review it manually.** |

**Migration action for tokens**: Resolve every `[token:*]` pattern to its static value at export time. Tokens are dynamic, so the exported value is a snapshot. Document which tokens were in use so the target platform can implement equivalents if needed.

**Migration action for php_code**: This filter executes arbitrary PHP stored in content fields. Flag every piece of content using a format with this filter. The PHP code must be manually reviewed, extracted, and reimplemented in the target platform's logic layer. Never migrate it as content.

### Additional Contrib Filters

| Filter ID | Provider Module | What It Does |
|---|---|---|
| `editor_file_reference` | editor | Tracks file usage for inline-uploaded images. Adds `data-entity-type="file"` and `data-entity-uuid` attributes to `<img>` tags created via the editor upload button. |
| `filter_lazy_load` | lazy (contrib) or core (D10.1+) | Adds `loading="lazy"` to images. No migration impact. |
| `pathologic` | pathologic (contrib) | Rewrites internal paths. Converts relative URLs to absolute or vice versa. Check settings for base URL behavior. |
| `transliteration` | transliteration (contrib) | Converts non-ASCII characters. Rare in text formats. |
| `typogrify` | typogrify (contrib) | Applies typographic improvements: smart quotes, widont, etc. |

---

## Drupal 7 Text Format Differences

D7 text formats work on the same concept but the storage is different.

### Schema

```
filter_format table:
  format    VARCHAR(255)  -- machine name
  name      VARCHAR(255)  -- human label
  cache     TINYINT       -- whether to cache filtered output
  status    TINYINT       -- enabled/disabled
  weight    INT           -- sort order

filter table:
  format    VARCHAR(255)  -- references filter_format.format
  module    VARCHAR(64)   -- providing module
  name      VARCHAR(32)   -- filter plugin name
  weight    INT           -- execution order within the format
  status    INT           -- enabled/disabled
  settings  LONGBLOB      -- PHP serialized array
```

### D7 filter names vs D8+ filter IDs

| D7 Name | D8+ Equivalent | Notes |
|---|---|---|
| `filter_html` | `filter_html` | Same concept, different settings structure |
| `filter_autop` | `filter_autop` | Same |
| `filter_url` | `filter_url` | Same |
| `filter_htmlcorrector` | `filter_htmlcorrector` | Same |
| `filter_html_escape` | `filter_html_escape` | Same |
| `php_code` | `php_code` | Was in core in D7. Moved to contrib `php` module in D8. |
| `media_filter` | `media_embed` | D7 media module used `[[{"fid":"123",...}]]` JSON tokens. Completely different from D8+ `<drupal-media>` tags. |

### D7 Media Tokens

D7's media module stores embedded media as JSON wrapped in double brackets:

```
[[{"fid":"123","view_mode":"full","type":"media","attributes":{"class":"media-image","height":"400","width":"600"}}]]
```

This is the single most painful text format artifact to migrate from D7. The token embeds a file ID (`fid`), not a UUID. You must:
1. Map every `fid` to the actual file path via the `file_managed` table
2. Replace the entire JSON token with an `<img>` tag (or equivalent)
3. Preserve the `view_mode` if it controls image size

### D7 CKEditor / WYSIWYG Module

D7 had two competing approaches:
- **WYSIWYG module**: Generic wrapper that supports multiple editors (TinyMCE, CKEditor, etc.). Config stored in the `wysiwyg` table.
- **CKEditor module**: Standalone CKEditor integration. Config stored in the `ckeditor_settings` table.

For migration, you care about what toolbar buttons were available (to understand what HTML structures authors could create) and any custom plugin configurations.

---

## Linkit Profiles

Linkit profiles control the autocomplete behavior for the link dialog in CKEditor.

### Config structure: linkit.linkit_profile.*.yml

```yaml
uuid: 11111111-2222-3333-4444-555555555566
langcode: en
status: true
id: default
label: Default
matchers:
  1234-5678-abcd:
    uuid: 1234-5678-abcd
    id: entity:node
    label: 'Content'
    weight: 0
    settings:
      metadata: '[node:content-type:name]'
      bundles:
        article: article
        page: page
      group_by_bundle: true
      substitution_type: canonical
      limit: 100
  5678-abcd-1234:
    uuid: 5678-abcd-1234
    id: entity:taxonomy_term
    label: 'Taxonomy term'
    weight: 1
    settings:
      metadata: '[term:vocabulary:name]'
      bundles: {  }
      group_by_bundle: false
      substitution_type: canonical
      limit: 100
  abcd-1234-5678:
    uuid: abcd-1234-5678
    id: entity:media
    label: 'Media'
    weight: 2
    settings:
      metadata: ''
      bundles: {  }
      group_by_bundle: false
      substitution_type: media
      limit: 100
```

Key fields:
- **`matchers`**: Each matcher searches one entity type. The `bundles` setting restricts which bundles appear in autocomplete results.
- **`substitution_type`**: How the link URL is generated. `canonical` uses the entity's canonical URL. `media` uses the media file's direct URL.

**Migration action**: Document which entity types and bundles are linkable. Links created with Linkit carry `data-entity-uuid` attributes that must be resolved to target platform URLs.

---

## Extraction Script

Run this to dump all text format, editor, and linkit config to structured JSON.

### Drush (D8/D9/D10/D11)

```bash
drush php:eval '
$output = [];

// Text formats + filters
$formats = \Drupal\filter\Entity\FilterFormat::loadMultiple();
foreach ($formats as $format) {
  $f = $format->toArray();
  $f["_filters_ordered"] = [];
  foreach ($format->filters()->getAll() as $id => $filter) {
    if ($filter->status) {
      $f["_filters_ordered"][] = [
        "id" => $id,
        "provider" => $filter->provider,
        "weight" => $filter->weight,
        "settings" => $filter->settings,
      ];
    }
  }
  usort($f["_filters_ordered"], function($a, $b) { return $a["weight"] <=> $b["weight"]; });
  $output["formats"][$format->id()] = $f;
}

// Editor config
$editors = \Drupal::entityTypeManager()->getStorage("editor")->loadMultiple();
foreach ($editors as $editor) {
  $output["editors"][$editor->id()] = $editor->toArray();
}

// Linkit profiles
if (\Drupal::moduleHandler()->moduleExists("linkit")) {
  $profiles = \Drupal::entityTypeManager()->getStorage("linkit_profile")->loadMultiple();
  foreach ($profiles as $profile) {
    $output["linkit_profiles"][$profile->id()] = $profile->toArray();
  }
}

echo json_encode($output, JSON_PRETTY_PRINT);
' > text-formats-export.json
```

### Database (D7)

```sql
-- Export text formats
SELECT format, name, status, weight FROM filter_format WHERE status = 1 ORDER BY weight;

-- Export filters with settings
SELECT f.format, ff.name AS format_name, f.name AS filter_name, f.module, f.status, f.weight, f.settings
FROM filter f
JOIN filter_format ff ON f.format = ff.format
WHERE ff.status = 1 AND f.status = 1
ORDER BY f.format, f.weight;

-- Export roles per format (D7 stores this in the role_permission table)
SELECT r.name AS role_name, p.permission
FROM role_permission p
JOIN role r ON p.rid = r.rid
WHERE p.permission LIKE 'use text format %';
```

### Database (D8+)

```sql
-- Raw config extraction (values are PHP-serialized)
SELECT name, data FROM config
WHERE name LIKE 'filter.format.%'
   OR name LIKE 'editor.editor.%'
   OR name LIKE 'linkit.linkit_profile.%'
ORDER BY name;
```

Deserialize the `data` column with PHP:

```php
$rows = $pdo->query("SELECT name, data FROM config WHERE name LIKE 'filter.format.%'");
foreach ($rows as $row) {
    $config = unserialize($row['data']);
    file_put_contents($row['name'] . '.json', json_encode($config, JSON_PRETTY_PRINT));
}
```

---

## Output Format

Save the export as `exports/text-formats.json`. Structure:

```json
{
  "drupal_version": "10.3.1",
  "formats": {
    "full_html": {
      "label": "Full HTML",
      "weight": 0,
      "status": true,
      "roles": ["authenticated", "administrator"],
      "filters_ordered": [
        {
          "id": "filter_html",
          "provider": "filter",
          "weight": -10,
          "settings": {
            "allowed_html": "<br> <p> <a href hreflang> <em> <strong> ..."
          }
        },
        {
          "id": "filter_autop",
          "provider": "filter",
          "weight": 0,
          "settings": {}
        },
        {
          "id": "media_embed",
          "provider": "media",
          "weight": 100,
          "settings": {
            "default_view_mode": "default",
            "allowed_view_modes": {"full": "full"}
          }
        },
        {
          "id": "filter_align",
          "provider": "filter",
          "weight": 200,
          "settings": {}
        },
        {
          "id": "filter_caption",
          "provider": "filter",
          "weight": 300,
          "settings": {}
        }
      ]
    },
    "basic_html": { "..." : "..." },
    "restricted_html": { "..." : "..." },
    "plain_text": { "..." : "..." }
  },
  "editors": {
    "full_html": {
      "editor_type": "ckeditor5",
      "toolbar_items": ["bold", "italic", "link", "drupalMedia", "sourceEditing"],
      "plugin_config": {
        "ckeditor5_heading": {
          "enabled_headings": ["heading2", "heading3", "heading4"]
        },
        "ckeditor5_sourceEditing": {
          "allowed_tags": ["<div>", "<span>"]
        },
        "media_media": {
          "allow_view_mode_override": true
        }
      },
      "image_upload": {
        "status": true,
        "scheme": "public",
        "directory": "inline-images",
        "max_size": "2 MB"
      }
    }
  },
  "linkit_profiles": {
    "default": {
      "label": "Default",
      "matchers": {
        "entity:node": {
          "bundles": ["article", "page"],
          "substitution_type": "canonical"
        },
        "entity:taxonomy_term": {
          "bundles": [],
          "substitution_type": "canonical"
        }
      }
    }
  },
  "migration_flags": {
    "has_media_embed": true,
    "has_entity_embed": false,
    "has_linkit": true,
    "has_token_filter": false,
    "has_php_code": false,
    "has_d7_media_tokens": false,
    "formats_with_media_embed": ["full_html"],
    "formats_with_entity_embed": [],
    "formats_with_php_code": []
  }
}
```

The `migration_flags` section is the fast-path for downstream skills. Skill 26 (Rich Text Cleanup) reads these flags to know which token types to scan for.

---

## Common Default Formats

Most Drupal sites ship with these. Knowing them helps you spot customizations.

| Format | Typical Filters | Notes |
|---|---|---|
| `plain_text` | `filter_html_escape`, `filter_url`, `filter_autop` | Escapes all HTML. Safe for any context. |
| `restricted_html` | `filter_html` (strict allowed list), `filter_autop`, `filter_url`, `filter_htmlcorrector` | Limited tags. Default for authenticated users in fresh installs. |
| `basic_html` | `filter_html` (moderate allowed list), `filter_autop`, `filter_url`, `filter_htmlcorrector`, `filter_align`, `filter_caption`, `editor_file_reference` | Standard editing format. Has CKEditor with a basic toolbar. |
| `full_html` | `filter_autop`, `filter_htmlcorrector`, `filter_align`, `filter_caption` | No `filter_html` restriction. Allows any HTML. Usually restricted to administrators. |

Custom formats are where the action is. Sites add formats like `email_html`, `teaser_text`, `code_block`, or `wysiwyg_full` with specific filter configurations.

---

## Checklist

Before marking this skill complete, verify you have:

- [ ] Every text format: machine name, label, status, weight, roles
- [ ] Every enabled filter per format: ID, provider, weight, full settings
- [ ] Filter execution order per format (sorted by weight)
- [ ] Editor config per format: toolbar items, plugin settings, image upload config
- [ ] CKEditor version in use (4 or 5) per format
- [ ] Linkit profiles (if module installed): matchers, bundles, substitution types
- [ ] Migration flags: which formats use media_embed, entity_embed, token_filter, php_code
- [ ] D7 media token format documented (if D7 source): `[[{"fid":"123",...}]]`
- [ ] `allowed_html` from `filter_html` captured exactly (this is the tag whitelist)
- [ ] `ckeditor5_sourceEditing.allowed_tags` captured (these are the extra tags authors can manually enter)
- [ ] Security review: any format with `php_code` filter flagged for manual review
- [ ] Output saved to `exports/text-formats.json`
