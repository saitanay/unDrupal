# Skill 8: Image Styles and Responsive Image Export

You are extracting every image processing pipeline from a Drupal site: image styles, responsive image mappings, and focal point configuration. The output feeds directly into your target platform's image handling.

---

## What You Are Extracting

| Component | Where It Lives | What It Controls |
|---|---|---|
| **Image styles** | `image.style.*.yml` config, `config` DB table | Named pipelines of effects: resize, crop, scale, convert, desaturate, rotate |
| **Responsive image styles** | `responsive_image.responsive_image_style.*.yml` | Breakpoint-to-image-style mappings for `<picture>` / `srcset` output |
| **Focal point config** | `focal_point.settings.yml`, per-entity crop data | Crop anchor coordinates stored per image, used by `focal_point_scale_and_crop` and `focal_point_crop` effects |
| **Image field settings** | Field config YAML or DB | Default image style applied to a field formatter, responsive image style selection |

---

## Step 1: Export Image Styles

### Method A: Config YAML (Best)

Image styles live in files named `image.style.{machine_name}.yml`.

```bash
# Find all image style configs
find config/sync -name "image.style.*.yml" | sort
```

Each file follows this structure:

```yaml
uuid: a1b2c3d4-...
langcode: en
status: true
dependencies:
  module:
    - focal_point
name: hero_banner
label: 'Hero Banner'
effects:
  a1b2c3d4-effect-uuid:
    uuid: a1b2c3d4-effect-uuid
    id: image_scale_and_crop
    weight: 1
    data:
      width: 1920
      height: 600
      anchor: center-center
  b2c3d4e5-effect-uuid:
    uuid: b2c3d4e5-effect-uuid
    id: image_convert
    weight: 2
    data:
      extension: webp
```

Extract all styles into a single JSON manifest:

```bash
# Parse all image styles to JSON (requires yq)
for f in config/sync/image.style.*.yml; do
  machine_name=$(basename "$f" .yml | sed 's/^image\.style\.//')
  echo "--- $machine_name ---"
  yq -o=json '.' "$f"
done > image_styles_dump.json
```

### Method B: Drush

```bash
# List all image style machine names
drush config:list | grep '^image.style\.'

# Export a single style
drush config:get image.style.hero_banner --format=json

# Export all image styles at once
for style in $(drush config:list | grep '^image\.style\.' ); do
  drush config:get "$style" --format=json
done > image_styles_all.json
```

### Method C: Database (D8+)

```sql
SELECT name, data
FROM config
WHERE name LIKE 'image.style.%'
ORDER BY name;
```

The `data` column holds serialized PHP. Deserialize it:

```php
// Run with: drush php:eval 'include "extract_styles.php";'
$rows = \Drupal::database()->select('config', 'c')
  ->fields('c', ['name', 'data'])
  ->condition('name', 'image.style.%', 'LIKE')
  ->execute();
$styles = [];
foreach ($rows as $row) {
  $styles[$row->name] = unserialize($row->data);
}
file_put_contents('image_styles_db.json', json_encode($styles, JSON_PRETTY_PRINT));
```

### Method D: Database (D7)

D7 stores image styles in dedicated tables, not the config system.

```sql
-- Get all styles
SELECT isid, name, label
FROM image_styles
ORDER BY name;

-- Get all effects per style
SELECT s.name AS style_name,
       e.ieid,
       e.module,
       e.name AS effect_name,
       e.data,
       e.weight
FROM image_effects e
JOIN image_styles s ON s.isid = e.isid
ORDER BY s.name, e.weight;
```

The `data` column in `image_effects` is serialized PHP. Parse it:

```php
// D7 extraction script (run with drush scr)
$styles = image_styles();
$output = [];
foreach ($styles as $name => $style) {
  $output[$name] = [
    'label' => $style['label'],
    'effects' => [],
  ];
  foreach ($style['effects'] as $effect) {
    $output[$name]['effects'][] = [
      'name' => $effect['name'],
      'module' => $effect['module'],
      'data' => $effect['data'],
      'weight' => $effect['weight'],
    ];
  }
}
print json_encode($output, JSON_PRETTY_PRINT);
```

---

## Step 2: Catalog Every Effect Type

Each effect in a pipeline has an `id` (D8+) or `name` (D7) that identifies the operation.

### Core Effects (D8+)

| Effect Plugin ID | What It Does | Key Settings |
|---|---|---|
| `image_resize` | Force exact dimensions. Stretches or squashes if aspect ratio differs. | `width`, `height` |
| `image_scale` | Scale to fit within dimensions. Preserves aspect ratio. | `width`, `height`, `upscale` (bool) |
| `image_scale_and_crop` | Scale then crop to exact dimensions. | `width`, `height`, `anchor` |
| `image_crop` | Crop to exact dimensions from anchor point. No scaling. | `width`, `height`, `anchor` |
| `image_convert` | Change format (JPEG, PNG, WebP, AVIF in D10.1+). | `extension` |
| `image_rotate` | Rotate by degrees. | `degrees`, `bgcolor`, `random` (bool) |
| `image_desaturate` | Convert to grayscale. | (none) |

### Contrib Effects (Common)

| Effect Plugin ID | Module | What It Does | Key Settings |
|---|---|---|---|
| `focal_point_scale_and_crop` | `focal_point` | Scale and crop using per-image focal point coordinates. | `width`, `height`, `crop_type` |
| `focal_point_crop` | `focal_point` | Crop only (no scale) around focal point. | `width`, `height`, `crop_type` |
| `image_effects_color_shift` | `image_effects` | Apply color overlay. | `color` |
| `image_effects_brightness` | `image_effects` | Adjust brightness. | `level` |
| `image_effects_watermark` | `image_effects` | Overlay a watermark image. | `path`, `position`, `opacity` |
| `image_effects_text_overlay` | `image_effects` | Render text on image. | `text`, `font`, `size`, `color`, `position` |
| `image_style_quality` | `image_style_quality` | Set per-style compression quality. | `quality` (1-100) |

### Anchor Values

Anchor settings use a `{vertical}-{horizontal}` format:

`top-left`, `top-center`, `top-right`, `center-left`, `center-center`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right`

### D7 Effect Names

D7 uses slightly different names: `image_resize`, `image_scale`, `image_scale_and_crop`, `image_crop`, `image_rotate`, `image_desaturate`. Same concepts, same settings. No `image_convert` in D7 core.

---

## Step 3: Export Responsive Image Styles

Responsive image styles map breakpoints to image styles. They generate `<picture>` elements or `srcset` attributes.

### Config File Structure

Files: `responsive_image.responsive_image_style.{machine_name}.yml`

```yaml
uuid: f1e2d3c4-...
langcode: en
status: true
dependencies:
  config:
    - image.style.hero_mobile
    - image.style.hero_tablet
    - image.style.hero_desktop
  module:
    - responsive_image
id: hero_responsive
label: 'Hero Responsive'
image_style_mappings:
  - image_style_mapping_type: image_style
    breakpoint_id: mymodule.mobile
    multiplier: '1x'
    image_mapping: hero_mobile
  - image_style_mapping_type: image_style
    breakpoint_id: mymodule.mobile
    multiplier: '2x'
    image_mapping: hero_mobile_2x
  - image_style_mapping_type: sizes
    breakpoint_id: mymodule.wide
    multiplier: '1x'
    image_mapping:
      sizes: '(min-width: 1200px) 1140px, 100vw'
      sizes_image_styles:
        - hero_desktop
        - hero_desktop_lg
fallback_image_style: hero_mobile
breakpoint_group: mymodule
```

Two mapping types exist:

| Type | Behavior |
|---|---|
| `image_style` | One image style per breakpoint/multiplier combo. Generates `<source>` in `<picture>`. |
| `sizes` | Multiple image styles with a `sizes` attribute. Generates `srcset` with width descriptors. |

### Extract All Responsive Image Styles

```bash
# Config files
find config/sync -name "responsive_image.responsive_image_style.*.yml" | sort

# Drush
drush config:list | grep '^responsive_image.responsive_image_style\.'
for style in $(drush config:list | grep '^responsive_image\.responsive_image_style\.'); do
  drush config:get "$style" --format=json
done > responsive_image_styles.json
```

### Extract the Breakpoint Definitions

Responsive image styles reference breakpoints. These come from `*.breakpoints.yml` files in themes or modules.

```bash
# Find breakpoint files
find . -name "*.breakpoints.yml" -not -path "*/node_modules/*"
```

A breakpoint file looks like:

```yaml
mytheme.mobile:
  label: Mobile
  mediaQuery: '(max-width: 767px)'
  weight: 0
  multipliers:
    - 1x
    - 2x
mytheme.tablet:
  label: Tablet
  mediaQuery: '(min-width: 768px) and (max-width: 1199px)'
  weight: 1
  multipliers:
    - 1x
    - 2x
mytheme.wide:
  label: Wide
  mediaQuery: '(min-width: 1200px)'
  weight: 2
  multipliers:
    - 1x
    - 2x
```

Record these breakpoints. You need them to reconstruct media queries on the target.

---

## Step 4: Export Focal Point Data

The `focal_point` module stores a crop anchor coordinate per image entity. This tells `focal_point_scale_and_crop` where to center the crop.

### Check if Focal Point is Installed

```bash
# Drush
drush pm:list --filter=focal_point --format=json

# Config YAML
cat config/sync/core.extension.yml | grep focal_point

# Database
SELECT * FROM key_value WHERE collection = 'system.schema' AND name = 'focal_point';
```

### Module-Level Configuration

```bash
drush config:get focal_point.settings --format=json
```

```yaml
# focal_point.settings.yml
preview_image_style: thumbnail
```

### Per-Image Focal Point Data

Focal point coordinates are stored as crop entities. Each image file entity gets a crop entity with x,y percentages.

```sql
-- D8+: crop entities store the focal point
SELECT c.entity_id,
       c.entity_type,
       c.type,
       c.x,
       c.y,
       c.width,
       c.height,
       f.uri
FROM crop_field_data c
JOIN file_managed f ON c.entity_id = f.fid
WHERE c.type = 'focal_point'
ORDER BY c.entity_id;
```

The `x` and `y` values are pixel coordinates from the top-left of the original image. The focal point percentage is calculated as:

```
focal_x_percent = (x / original_width) * 100
focal_y_percent = (y / original_height) * 100
```

Export with Drush:

```php
// drush php:eval or drush scr
$crops = \Drupal::entityTypeManager()
  ->getStorage('crop')
  ->loadByProperties(['type' => 'focal_point']);
$output = [];
foreach ($crops as $crop) {
  $output[] = [
    'file_id' => $crop->get('entity_id')->value,
    'x' => $crop->get('x')->value,
    'y' => $crop->get('y')->value,
    'width' => $crop->get('width')->value,
    'height' => $crop->get('height')->value,
  ];
}
print json_encode($output, JSON_PRETTY_PRINT);
```

---

## Step 5: Map Image Field Formatters

Fields that render images use a formatter that specifies which image style or responsive image style to apply.

### Extract Field Formatter Settings

```bash
# Find all entity view display configs that reference image styles
grep -rl "image_style\|responsive_image_style\|image_formatter\|responsive_image_formatter" config/sync/core.entity_view_display.*.yml
```

Inside a view display config, an image field formatter looks like:

```yaml
field_hero_image:
  type: image
  label: hidden
  settings:
    image_style: hero_banner
    image_link: ''
  third_party_settings: {}
  weight: 0
  region: content
```

Or with responsive images:

```yaml
field_hero_image:
  type: responsive_image
  label: hidden
  settings:
    responsive_image_style: hero_responsive
    image_link: ''
  third_party_settings: {}
  weight: 0
  region: content
```

Record which content types and view modes use which image styles. This tells you which styles are active and which are orphaned.

---

## Step 6: Build the Migration Manifest

Combine everything into a structured manifest. One JSON document that captures the full picture.

```json
{
  "image_styles": {
    "hero_banner": {
      "label": "Hero Banner",
      "effects": [
        {
          "id": "focal_point_scale_and_crop",
          "weight": 1,
          "settings": {
            "width": 1920,
            "height": 600,
            "crop_type": "focal_point"
          }
        },
        {
          "id": "image_convert",
          "weight": 2,
          "settings": {
            "extension": "webp"
          }
        }
      ]
    },
    "thumbnail": {
      "label": "Thumbnail",
      "effects": [
        {
          "id": "image_scale_and_crop",
          "weight": 1,
          "settings": {
            "width": 150,
            "height": 150,
            "anchor": "center-center"
          }
        }
      ]
    }
  },
  "responsive_image_styles": {
    "hero_responsive": {
      "label": "Hero Responsive",
      "fallback_style": "hero_mobile",
      "breakpoint_group": "mytheme",
      "mappings": [
        {
          "breakpoint": "mytheme.mobile",
          "multiplier": "1x",
          "type": "image_style",
          "style": "hero_mobile"
        },
        {
          "breakpoint": "mytheme.wide",
          "multiplier": "1x",
          "type": "sizes",
          "sizes": "(min-width: 1200px) 1140px, 100vw",
          "styles": ["hero_desktop", "hero_desktop_lg"]
        }
      ]
    }
  },
  "breakpoints": {
    "mytheme.mobile": "(max-width: 767px)",
    "mytheme.tablet": "(min-width: 768px) and (max-width: 1199px)",
    "mytheme.wide": "(min-width: 1200px)"
  },
  "focal_points": {
    "42": { "x_percent": 65, "y_percent": 30 },
    "87": { "x_percent": 50, "y_percent": 50 }
  },
  "usage_map": {
    "hero_banner": ["node.article.full.field_hero_image"],
    "thumbnail": ["node.article.teaser.field_hero_image", "node.page.teaser.field_image"]
  }
}
```

---

## Step 7: Target Platform Mapping

### CSS Object-Fit + Aspect-Ratio

Every image style with fixed dimensions maps to CSS properties. No server-side processing needed if the original image is served at sufficient resolution.

| Drupal Effect | CSS Equivalent |
|---|---|
| `image_scale_and_crop` (w: 1920, h: 600) | `object-fit: cover; aspect-ratio: 1920/600;` (simplify to `16/5`) |
| `image_scale` (w: 800, h: null) | `max-width: 800px; width: 100%; height: auto;` |
| `image_resize` (w: 400, h: 300) | `width: 400px; height: 300px; object-fit: fill;` |
| `image_crop` (w: 500, h: 500, anchor: center-center) | `object-fit: none; object-position: center center; width: 500px; height: 500px;` |
| `image_desaturate` | `filter: grayscale(100%);` |
| `image_rotate` (degrees: 90) | `transform: rotate(90deg);` |
| Focal point crop (65%, 30%) | `object-fit: cover; object-position: 65% 30%;` |

For responsive image styles, the breakpoint media queries translate directly:

```css
.hero-image {
  object-fit: cover;
  width: 100%;
}

/* Mobile: hero_mobile style (750x400) */
@media (max-width: 767px) {
  .hero-image {
    aspect-ratio: 750/400;
  }
}

/* Wide: hero_desktop style (1920x600) */
@media (min-width: 1200px) {
  .hero-image {
    aspect-ratio: 1920/600;
  }
}
```

### Cloudinary

Map each effect to a Cloudinary URL transformation parameter.

| Drupal Effect | Cloudinary Transform | Example |
|---|---|---|
| `image_scale_and_crop` (1920x600) | `c_fill,w_1920,h_600` | `/c_fill,w_1920,h_600/image.jpg` |
| `image_scale` (800, upscale: false) | `c_limit,w_800` | `/c_limit,w_800/image.jpg` |
| `image_scale` (800, upscale: true) | `c_fit,w_800` | `/c_fit,w_800/image.jpg` |
| `image_resize` (400x300) | `c_scale,w_400,h_300` | `/c_scale,w_400,h_300/image.jpg` |
| `image_crop` (500x500, top-left) | `c_crop,w_500,h_500,g_north_west` | `/c_crop,w_500,h_500,g_north_west/image.jpg` |
| `image_convert` (webp) | `f_webp` | `/f_webp/image.jpg` |
| `image_desaturate` | `e_grayscale` | `/e_grayscale/image.jpg` |
| `image_rotate` (90) | `a_90` | `/a_90/image.jpg` |
| Focal point (65%, 30%) | `c_fill,g_xy_center,x_0.65,y_0.30` | `/c_fill,w_800,h_600,g_xy_center,x_0.65,y_0.30/image.jpg` |
| Quality 80 | `q_80` | `/q_80/image.jpg` |

Cloudinary anchor mapping from Drupal anchor values:

| Drupal Anchor | Cloudinary Gravity |
|---|---|
| `top-left` | `g_north_west` |
| `top-center` | `g_north` |
| `top-right` | `g_north_east` |
| `center-left` | `g_west` |
| `center-center` | `g_center` |
| `center-right` | `g_east` |
| `bottom-left` | `g_south_west` |
| `bottom-center` | `g_south` |
| `bottom-right` | `g_south_east` |

Chain multiple effects by concatenating transforms with `/`:

```
/c_fill,w_1920,h_600,g_center/f_webp/q_80/image.jpg
```

### imgix

| Drupal Effect | imgix Parameters | Example |
|---|---|---|
| `image_scale_and_crop` (1920x600) | `w=1920&h=600&fit=crop` | `?w=1920&h=600&fit=crop` |
| `image_scale` (800, no upscale) | `w=800&fit=max` | `?w=800&fit=max` |
| `image_scale` (800, upscale) | `w=800&fit=clip` | `?w=800&fit=clip` |
| `image_resize` (400x300) | `w=400&h=300&fit=scale` | `?w=400&h=300&fit=scale` |
| `image_crop` (500x500, top-left) | `w=500&h=500&fit=crop&crop=top,left` | `?w=500&h=500&fit=crop&crop=top,left` |
| `image_convert` (webp) | `fm=webp` | `?fm=webp` |
| `image_desaturate` | `sat=-100` | `?sat=-100` |
| `image_rotate` (90) | `rot=90` | `?rot=90` |
| Focal point (65%, 30%) | `fit=crop&crop=focalpoint&fp-x=0.65&fp-y=0.30` | `?fit=crop&crop=focalpoint&fp-x=0.65&fp-y=0.30` |
| Quality 80 | `q=80` | `?q=80` |

imgix anchor mapping:

| Drupal Anchor | imgix `crop` Value |
|---|---|
| `top-left` | `crop=top,left` |
| `top-center` | `crop=top` |
| `top-right` | `crop=top,right` |
| `center-left` | `crop=left` |
| `center-center` | `crop=center` |
| `center-right` | `crop=right` |
| `bottom-left` | `crop=bottom,left` |
| `bottom-center` | `crop=bottom` |
| `bottom-right` | `crop=bottom,right` |

### Vercel Image Optimization (Next.js)

Vercel's image optimizer is simpler. It handles width and quality. Cropping and effects are not supported at the URL level. Use CSS for crop behavior and the Next.js `<Image>` component for optimization.

```jsx
// Drupal: image_scale_and_crop 1920x600
<Image
  src="/uploads/hero.jpg"
  width={1920}
  height={600}
  style={{ objectFit: 'cover' }}
  sizes="(max-width: 767px) 100vw, (max-width: 1199px) 100vw, 1140px"
  alt="Hero image"
/>
```

```jsx
// Drupal: image_scale width=800
<Image
  src="/uploads/photo.jpg"
  width={800}
  height={0}  // calculate from source aspect ratio
  style={{ width: '100%', height: 'auto' }}
  alt="Photo"
/>
```

For focal point with Next.js:

```jsx
// Drupal: focal_point_scale_and_crop, focal point at 65% 30%
<div style={{ position: 'relative', aspectRatio: '1920/600', overflow: 'hidden' }}>
  <Image
    src="/uploads/hero.jpg"
    fill
    style={{ objectFit: 'cover', objectPosition: '65% 30%' }}
    sizes="100vw"
    alt="Hero image"
  />
</div>
```

Configure allowed sizes in `next.config.js`:

```js
// Map your Drupal image style widths to Next.js deviceSizes and imageSizes
module.exports = {
  images: {
    // Breakpoint widths from responsive image styles
    deviceSizes: [640, 750, 828, 1080, 1200, 1920, 2048],
    // Smaller fixed-width styles (thumbnails, avatars, icons)
    imageSizes: [16, 32, 48, 64, 96, 128, 150, 256, 384],
    formats: ['image/avif', 'image/webp'],
  },
};
```

### WordPress

WordPress uses named image sizes. Register one per Drupal image style.

```php
// functions.php or plugin
// Map from Drupal image styles
add_action('after_setup_theme', function () {
    // image_scale_and_crop → hard crop (true)
    add_image_size('hero_banner', 1920, 600, true);
    // With anchor: add_image_size('hero_banner', 1920, 600, ['center', 'center']);

    // image_scale → soft crop (false)
    add_image_size('content_image', 800, 600, false);

    // image_scale width-only → height 9999, soft crop
    add_image_size('sidebar_image', 400, 9999, false);

    // image_resize (exact) → hard crop
    add_image_size('thumbnail_square', 150, 150, true);
});
```

WordPress anchor mapping (third parameter of `add_image_size` when using array):

| Drupal Anchor | WordPress Crop Position |
|---|---|
| `top-left` | `['left', 'top']` |
| `top-center` | `['center', 'top']` |
| `top-right` | `['right', 'top']` |
| `center-left` | `['left', 'center']` |
| `center-center` | `['center', 'center']` |
| `center-right` | `['right', 'center']` |
| `bottom-left` | `['left', 'bottom']` |
| `bottom-center` | `['center', 'bottom']` |
| `bottom-right` | `['right', 'bottom']` |

WordPress has no per-image focal point in core. For focal point behavior, use a plugin like [Jeremie Starter Starter Images](https://developer.wordpress.org/plugins/) or handle cropping in the media library manually.

WordPress does not chain effects like Drupal. No desaturate, rotate, or format conversion at the image-size level. Handle those with:
- CSS filters for desaturate: `filter: grayscale(100%)`
- WebP/AVIF: WordPress 5.8+ generates WebP variants automatically. Use the `image_editor_output_format` filter for per-size format control.

---

## Step 8: Generate a Conversion Script

This script reads the migration manifest from Step 6 and outputs target platform configuration.

```python
#!/usr/bin/env python3
"""
Convert Drupal image style manifest to target platform config.
Usage: python3 convert_image_styles.py manifest.json --target cloudinary|imgix|nextjs|wordpress|css
"""

import json
import sys
import argparse
import math


def simplify_ratio(w, h):
    """Simplify aspect ratio."""
    g = math.gcd(w, h)
    return f"{w // g}/{h // g}"


DRUPAL_ANCHOR_TO_CLOUDINARY = {
    "top-left": "north_west", "top-center": "north", "top-right": "north_east",
    "center-left": "west", "center-center": "center", "center-right": "east",
    "bottom-left": "south_west", "bottom-center": "south", "bottom-right": "south_east",
}

DRUPAL_ANCHOR_TO_IMGIX = {
    "top-left": "top,left", "top-center": "top", "top-right": "top,right",
    "center-left": "left", "center-center": "center", "center-right": "right",
    "bottom-left": "bottom,left", "bottom-center": "bottom", "bottom-right": "bottom,right",
}

DRUPAL_ANCHOR_TO_WP = {
    "top-left": "['left', 'top']", "top-center": "['center', 'top']",
    "top-right": "['right', 'top']", "center-left": "['left', 'center']",
    "center-center": "['center', 'center']", "center-right": "['right', 'center']",
    "bottom-left": "['left', 'bottom']", "bottom-center": "['center', 'bottom']",
    "bottom-right": "['right', 'bottom']",
}


def effects_to_cloudinary(effects):
    """Convert Drupal effects pipeline to Cloudinary URL transforms."""
    transforms = []
    for effect in sorted(effects, key=lambda e: e.get("weight", 0)):
        eid = effect["id"]
        s = effect.get("settings", {})
        if eid == "image_scale_and_crop":
            anchor = DRUPAL_ANCHOR_TO_CLOUDINARY.get(s.get("anchor", "center-center"), "center")
            transforms.append(f"c_fill,w_{s['width']},h_{s['height']},g_{anchor}")
        elif eid in ("focal_point_scale_and_crop", "focal_point_crop"):
            transforms.append(f"c_fill,w_{s['width']},h_{s['height']},g_auto:subject")
        elif eid == "image_scale":
            mode = "c_fit" if s.get("upscale", False) else "c_limit"
            parts = [mode]
            if s.get("width"): parts.append(f"w_{s['width']}")
            if s.get("height"): parts.append(f"h_{s['height']}")
            transforms.append(",".join(parts))
        elif eid == "image_resize":
            transforms.append(f"c_scale,w_{s['width']},h_{s['height']}")
        elif eid == "image_crop":
            anchor = DRUPAL_ANCHOR_TO_CLOUDINARY.get(s.get("anchor", "center-center"), "center")
            transforms.append(f"c_crop,w_{s['width']},h_{s['height']},g_{anchor}")
        elif eid == "image_convert":
            transforms.append(f"f_{s['extension']}")
        elif eid == "image_desaturate":
            transforms.append("e_grayscale")
        elif eid == "image_rotate":
            transforms.append(f"a_{s['degrees']}")
    return "/".join(transforms)


def effects_to_imgix(effects):
    """Convert Drupal effects pipeline to imgix query params."""
    params = []
    for effect in sorted(effects, key=lambda e: e.get("weight", 0)):
        eid = effect["id"]
        s = effect.get("settings", {})
        if eid == "image_scale_and_crop":
            anchor = DRUPAL_ANCHOR_TO_IMGIX.get(s.get("anchor", "center-center"), "center")
            params.extend([f"w={s['width']}", f"h={s['height']}", "fit=crop", f"crop={anchor}"])
        elif eid in ("focal_point_scale_and_crop", "focal_point_crop"):
            params.extend([f"w={s['width']}", f"h={s['height']}", "fit=crop", "crop=focalpoint"])
        elif eid == "image_scale":
            mode = "clip" if s.get("upscale", False) else "max"
            if s.get("width"): params.append(f"w={s['width']}")
            if s.get("height"): params.append(f"h={s['height']}")
            params.append(f"fit={mode}")
        elif eid == "image_resize":
            params.extend([f"w={s['width']}", f"h={s['height']}", "fit=scale"])
        elif eid == "image_crop":
            anchor = DRUPAL_ANCHOR_TO_IMGIX.get(s.get("anchor", "center-center"), "center")
            params.extend([f"w={s['width']}", f"h={s['height']}", "fit=crop", f"crop={anchor}"])
        elif eid == "image_convert":
            params.append(f"fm={s['extension']}")
        elif eid == "image_desaturate":
            params.append("sat=-100")
        elif eid == "image_rotate":
            params.append(f"rot={s['degrees']}")
    return "&".join(params)


def effects_to_css(effects, focal_point=None):
    """Convert Drupal effects pipeline to CSS properties."""
    rules = []
    for effect in sorted(effects, key=lambda e: e.get("weight", 0)):
        eid = effect["id"]
        s = effect.get("settings", {})
        if eid == "image_scale_and_crop":
            ratio = simplify_ratio(s["width"], s["height"])
            rules.append(f"object-fit: cover; aspect-ratio: {ratio};")
        elif eid in ("focal_point_scale_and_crop", "focal_point_crop"):
            ratio = simplify_ratio(s["width"], s["height"])
            pos = "50% 50%"
            if focal_point:
                pos = f"{focal_point['x_percent']}% {focal_point['y_percent']}%"
            rules.append(f"object-fit: cover; aspect-ratio: {ratio}; object-position: {pos};")
        elif eid == "image_scale":
            if s.get("width"):
                rules.append(f"max-width: {s['width']}px; width: 100%; height: auto;")
        elif eid == "image_resize":
            rules.append(f"width: {s['width']}px; height: {s['height']}px; object-fit: fill;")
        elif eid == "image_crop":
            rules.append(f"width: {s['width']}px; height: {s['height']}px; object-fit: none;")
        elif eid == "image_desaturate":
            rules.append("filter: grayscale(100%);")
        elif eid == "image_rotate":
            rules.append(f"transform: rotate({s['degrees']}deg);")
    return " ".join(rules)


def effects_to_wordpress(style_name, effects):
    """Convert Drupal effects pipeline to WordPress add_image_size call."""
    for effect in sorted(effects, key=lambda e: e.get("weight", 0)):
        eid = effect["id"]
        s = effect.get("settings", {})
        if eid in ("image_scale_and_crop", "focal_point_scale_and_crop"):
            anchor = s.get("anchor", "center-center")
            wp_crop = DRUPAL_ANCHOR_TO_WP.get(anchor, "true")
            return f"add_image_size('{style_name}', {s['width']}, {s['height']}, {wp_crop});"
        elif eid == "image_scale":
            w = s.get("width", 0)
            h = s.get("height", 9999)
            return f"add_image_size('{style_name}', {w}, {h}, false);"
        elif eid == "image_resize":
            return f"add_image_size('{style_name}', {s['width']}, {s['height']}, true);"
        elif eid == "image_crop":
            anchor = s.get("anchor", "center-center")
            wp_crop = DRUPAL_ANCHOR_TO_WP.get(anchor, "true")
            return f"add_image_size('{style_name}', {s['width']}, {s['height']}, {wp_crop});"
    return f"// No dimensional effect found for '{style_name}'"


def main():
    parser = argparse.ArgumentParser(description="Convert Drupal image styles to target platform config")
    parser.add_argument("manifest", help="Path to image style manifest JSON")
    parser.add_argument("--target", required=True,
                        choices=["cloudinary", "imgix", "nextjs", "wordpress", "css"],
                        help="Target platform")
    args = parser.parse_args()

    with open(args.manifest) as f:
        manifest = json.load(f)

    styles = manifest.get("image_styles", {})
    focal_points = manifest.get("focal_points", {})

    if args.target == "cloudinary":
        print("# Cloudinary URL transforms per Drupal image style\n")
        for name, style in styles.items():
            transform = effects_to_cloudinary(style["effects"])
            print(f"{name}: /{transform}/{{image}}")

    elif args.target == "imgix":
        print("# imgix query parameters per Drupal image style\n")
        for name, style in styles.items():
            params = effects_to_imgix(style["effects"])
            print(f"{name}: ?{params}")

    elif args.target == "css":
        print("/* CSS equivalents for Drupal image styles */\n")
        for name, style in styles.items():
            css = effects_to_css(style["effects"])
            print(f".img-{name} {{ {css} }}")

    elif args.target == "wordpress":
        print("<?php\n// WordPress image sizes from Drupal image styles\n")
        print("add_action('after_setup_theme', function () {")
        for name, style in styles.items():
            line = effects_to_wordpress(name, style["effects"])
            print(f"    {line}")
        print("});\n")

    elif args.target == "nextjs":
        widths = set()
        for style in styles.values():
            for effect in style["effects"]:
                w = effect.get("settings", {}).get("width")
                if w:
                    widths.add(int(w))
        sorted_widths = sorted(widths)
        device = [w for w in sorted_widths if w > 384]
        image = [w for w in sorted_widths if w <= 384]
        print("// next.config.js image configuration\n")
        print("module.exports = {")
        print("  images: {")
        print(f"    deviceSizes: {device},")
        print(f"    imageSizes: {image or [16, 32, 48, 64, 96, 128, 256, 384]},")
        print("    formats: ['image/avif', 'image/webp'],")
        print("  },")
        print("};")


if __name__ == "__main__":
    main()
```

Save this script alongside your manifest. Run it:

```bash
python3 convert_image_styles.py manifest.json --target cloudinary
python3 convert_image_styles.py manifest.json --target imgix
python3 convert_image_styles.py manifest.json --target css
python3 convert_image_styles.py manifest.json --target wordpress
python3 convert_image_styles.py manifest.json --target nextjs
```

---

## Checklist

Before marking this skill complete:

- [ ] Exported all `image.style.*.yml` configs with full effects pipelines
- [ ] Recorded every effect's plugin ID and settings (width, height, anchor, upscale, extension, degrees)
- [ ] Exported all `responsive_image.responsive_image_style.*.yml` configs
- [ ] Extracted breakpoint group definitions (media queries, multipliers)
- [ ] Checked for `focal_point` module and exported per-image crop coordinates
- [ ] Mapped which image styles are used by which fields and view modes
- [ ] Identified orphaned styles (defined but not referenced by any field formatter)
- [ ] Built the JSON migration manifest
- [ ] Generated target platform configuration using the conversion script
- [ ] Verified focal point data carries over (CSS `object-position` or CDN focal point params)
