# Skill 31: Post-Migration Validation Checklist

Run a full comparison between the Drupal source and the migration target. Count every entity type, spot-check content, verify URLs, scan for broken markup, and produce a pass/fail report. This skill catches what automated migration pipelines miss.

Run this skill after migration is complete. You need the source Drupal site (or its export files) and the live target platform.

---

## Prerequisites

1. **Drupal source access** (at least one):
   - Drush or database access to run count queries
   - JSON:API access for entity enumeration
   - Export JSON files from Skills 11-21 (counts derivable from file contents)

2. **Target platform access** (at least one):
   - API access to the target CMS (REST, GraphQL, SDK)
   - Database access to the target
   - Public URL access for crawl-based checks

3. **Export manifests** from prior skills:
   - Content export (Skill 11) for node counts and field data
   - Taxonomy export (Skill 13) for vocabulary/term counts
   - Media export (Skill 14) for file manifests and download URLs
   - URL aliases and redirects (Skill 20) for redirect verification
   - Metatags/SEO (Skill 21) for meta tag comparison

4. **Tools** (install if missing):
   - `curl` or `wget` for HTTP checks
   - `jq` for JSON processing
   - A link checker: `linkchecker`, `broken-link-checker`, `muffet`, or `lychee`

---

## Validation Report Format

Generate a JSON report. Every check produces one entry:

```json
{
  "validation_run": {
    "timestamp": "2025-01-15T14:30:00Z",
    "source": "drupal-site.example.com",
    "target": "new-site.example.com",
    "drupal_version": "10.3.1"
  },
  "checks": [
    {
      "id": "content_count_article",
      "category": "content_counts",
      "label": "Node count: article",
      "status": "PASS",
      "source_count": 1247,
      "target_count": 1247,
      "delta": 0,
      "details": null
    },
    {
      "id": "content_count_page",
      "category": "content_counts",
      "label": "Node count: page",
      "status": "FAIL",
      "source_count": 89,
      "target_count": 85,
      "delta": -4,
      "details": "Missing node IDs: [42, 108, 233, 501]"
    },
    {
      "id": "taxonomy_count_tags",
      "category": "taxonomy_counts",
      "label": "Taxonomy count: tags",
      "status": "PASS",
      "source_count": 340,
      "target_count": 340,
      "delta": 0,
      "details": null
    },
    {
      "id": "spot_check_article",
      "category": "spot_check",
      "label": "Spot check: article (10 random)",
      "status": "FAIL",
      "checked": 10,
      "passed": 8,
      "failed": 2,
      "failures": [
        {
          "source_id": "node/456",
          "field": "field_hero_image",
          "issue": "Image missing on target"
        },
        {
          "source_id": "node/789",
          "field": "body",
          "issue": "Drupal token [media:image:123] not resolved"
        }
      ]
    }
  ],
  "summary": {
    "total": 42,
    "pass": 36,
    "fail": 4,
    "skip": 2,
    "pass_rate": "85.7%"
  }
}
```

Status values: `PASS`, `FAIL`, `SKIP` (check not applicable or access unavailable).

---

## 1. Content Count Comparison

Count published nodes per content type on both source and target. Every node that was published on Drupal must exist on the target.

### 1a. Source Counts

#### Via Drush

```bash
# Count published nodes per content type
drush sql:query "
  SELECT type, COUNT(*) as count
  FROM node_field_data
  WHERE status = 1
    AND default_langcode = 1
  GROUP BY type
  ORDER BY type
" --format=json
```

#### Via Database (D9/D10/D11)

```sql
SELECT type, COUNT(*) as count
FROM node_field_data
WHERE status = 1
  AND default_langcode = 1
GROUP BY type
ORDER BY type;
```

#### Via Database (D7)

```sql
SELECT n.type, COUNT(*) as count
FROM node n
WHERE n.status = 1
GROUP BY n.type
ORDER BY n.type;
```

#### Via JSON:API

```bash
# For each content type, get the total count from pagination metadata
for BUNDLE in article page event product; do
  TOTAL=$(curl -s "https://drupal-site.example.com/jsonapi/node/$BUNDLE?page[limit]=1" \
    | jq '.meta.count // 0')
  echo "$BUNDLE: $TOTAL"
done
```

JSON:API returns all nodes (published and unpublished) unless filtered. Add a status filter:

```
/jsonapi/node/{bundle}?filter[status]=1&page[limit]=1
```

The `.meta.count` field in the response gives the total without downloading all records.

#### Via Export Files

```bash
# Count records per content type from Skill 11 export files
for FILE in exports/nodes_*.json; do
  BUNDLE=$(echo "$FILE" | sed 's/.*nodes_\(.*\)\.json/\1/')
  COUNT=$(jq 'length' "$FILE")
  echo "$BUNDLE: $COUNT"
done
```

### 1b. Target Counts

The target query depends on your platform. Examples for common targets:

#### WordPress (via WP-CLI)

```bash
wp post list --post_type=post --post_status=publish --format=count
wp post list --post_type=page --post_status=publish --format=count
# Repeat for each custom post type that maps to a Drupal content type
```

#### Headless CMS (via API)

```bash
# Contentful
curl -s "https://cdn.contentful.com/spaces/$SPACE_ID/entries?content_type=article&limit=0" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq '.total'

# Strapi
curl -s "https://your-strapi.com/api/articles?pagination[pageSize]=1" | jq '.meta.pagination.total'

# Sanity
curl -s "https://$PROJECT_ID.api.sanity.io/v2024-01-01/data/query/production" \
  --data-urlencode 'query=count(*[_type == "article"])'
```

#### Static Site (file-based)

```bash
# Count markdown files per content directory
for DIR in content/blog content/pages content/events; do
  TYPE=$(basename "$DIR")
  COUNT=$(find "$DIR" -name "*.md" -o -name "*.mdx" | wc -l)
  echo "$TYPE: $COUNT"
done
```

#### Database (generic SQL target)

```sql
-- Adjust table/column names to your schema
SELECT content_type, COUNT(*) as count
FROM content
WHERE published = true
GROUP BY content_type
ORDER BY content_type;
```

### 1c. Compare and Report

Build one check entry per content type:

```bash
#!/bin/bash
# compare_counts.sh — reads source_counts.json and target_counts.json
# Each file: [{"type": "article", "count": 1247}, ...]

jq -n --slurpfile src source_counts.json --slurpfile tgt target_counts.json '
  [$src[0][] | {type, source: .count}] as $s |
  [$tgt[0][] | {type, target: .count}] as $t |
  [
    $s[] | . as $row |
    ($t | map(select(.type == $row.type)) | .[0].target // 0) as $tc |
    {
      id: ("content_count_" + $row.type),
      category: "content_counts",
      label: ("Node count: " + $row.type),
      status: (if $row.source == $tc then "PASS" else "FAIL" end),
      source_count: $row.source,
      target_count: $tc,
      delta: ($tc - $row.source)
    }
  ]
'
```

Flag any content type where delta is not zero. A negative delta means content was lost. A positive delta means duplicates or extra records were created.

### 1d. Find Missing Content

When counts do not match, identify the specific missing records:

```sql
-- Source: get all published node IDs for a content type
SELECT nid FROM node_field_data
WHERE type = 'article' AND status = 1 AND default_langcode = 1
ORDER BY nid;
```

Export both source and target ID lists, then diff:

```bash
comm -23 <(sort source_article_ids.txt) <(sort target_article_ids.txt) > missing_articles.txt
```

Each line in `missing_articles.txt` is a node ID that exists on Drupal but not on the target. Include these IDs in the `details` field of the check entry.

---

## 2. Taxonomy Term Count Comparison

Count terms per vocabulary on both sides.

### 2a. Source Counts

#### Database (D9/D10/D11)

```sql
SELECT vid AS vocabulary, COUNT(*) as count
FROM taxonomy_term_field_data
WHERE default_langcode = 1
GROUP BY vid
ORDER BY vid;
```

#### Database (D7)

```sql
SELECT v.machine_name AS vocabulary, COUNT(*) as count
FROM taxonomy_term_data t
JOIN taxonomy_vocabulary v ON t.vid = v.vid
GROUP BY v.machine_name
ORDER BY v.machine_name;
```

#### Via JSON:API

```bash
# List vocabularies first
VOCABS=$(curl -s "https://drupal-site.example.com/jsonapi/taxonomy_vocabulary/taxonomy_vocabulary" \
  | jq -r '.data[].attributes.drupal_internal__vid')

for VOCAB in $VOCABS; do
  COUNT=$(curl -s "https://drupal-site.example.com/jsonapi/taxonomy_term/$VOCAB?page[limit]=1" \
    | jq '.meta.count // 0')
  echo "$VOCAB: $COUNT"
done
```

### 2b. Target Counts

Adapt to your platform. WordPress example:

```bash
# WordPress taxonomies
for TAX in category post_tag custom_taxonomy; do
  wp term list "$TAX" --format=count
done
```

### 2c. Compare

Same comparison logic as Section 1c. One check entry per vocabulary. Include missing term names in the `details` field when counts differ.

Also verify hierarchy depth. If Drupal had three-level nested terms and the target flattened them, flag this:

```sql
-- Source: find maximum hierarchy depth per vocabulary
WITH RECURSIVE term_tree AS (
  SELECT entity_id AS tid, parent_target_id AS parent, vid, 1 AS depth
  FROM taxonomy_term__parent tp
  JOIN taxonomy_term_field_data td ON tp.entity_id = td.tid AND td.default_langcode = 1
  WHERE parent_target_id = 0

  UNION ALL

  SELECT tp.entity_id, tp.parent_target_id, td.vid, tt.depth + 1
  FROM taxonomy_term__parent tp
  JOIN taxonomy_term_field_data td ON tp.entity_id = td.tid AND td.default_langcode = 1
  JOIN term_tree tt ON tp.parent_target_id = tt.tid
)
SELECT vid, MAX(depth) AS max_depth
FROM term_tree
GROUP BY vid;
```

---

## 3. Media and File Count Comparison

### 3a. Source Counts

#### Media Entities by Type (D8+)

```sql
SELECT bundle, COUNT(*) as count
FROM media_field_data
WHERE default_langcode = 1
GROUP BY bundle
ORDER BY bundle;
```

#### Files by MIME Category

```sql
SELECT
  CASE
    WHEN filemime LIKE 'image/%' THEN 'image'
    WHEN filemime LIKE 'application/pdf' THEN 'pdf'
    WHEN filemime LIKE 'video/%' THEN 'video'
    WHEN filemime LIKE 'audio/%' THEN 'audio'
    ELSE 'other'
  END AS file_type,
  COUNT(*) as count
FROM file_managed
WHERE status = 1
GROUP BY file_type
ORDER BY file_type;
```

#### D7 Files

```sql
SELECT
  CASE
    WHEN filemime LIKE 'image/%' THEN 'image'
    WHEN filemime LIKE 'application/pdf' THEN 'pdf'
    WHEN filemime LIKE 'video/%' THEN 'video'
    WHEN filemime LIKE 'audio/%' THEN 'audio'
    ELSE 'other'
  END AS file_type,
  COUNT(*) as count
FROM file_managed
WHERE status = 1
GROUP BY file_type
ORDER BY file_type;
```

### 3b. Target Counts

Count files on the target by type. For file-system targets:

```bash
# Count files by extension in the target media directory
find /path/to/target/media -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

For CMS targets, use their API to enumerate media assets.

### 3c. File Accessibility Check

Every file in the Skill 14 download manifest must be reachable on the target. Sample 100 files (or all, if under 500) and verify HTTP 200:

```bash
#!/bin/bash
# check_files.sh — verify migrated files are accessible
# Input: file_manifest.json from Skill 14 with download_url and target_url fields

TOTAL=0
OK=0
FAIL=0
FAILURES=""

# Sample 100 random files
jq -r '.[].target_url' file_manifest.json | shuf -n 100 | while read -r URL; do
  TOTAL=$((TOTAL + 1))
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
  if [ "$STATUS" = "200" ]; then
    OK=$((OK + 1))
  else
    FAIL=$((FAIL + 1))
    FAILURES="$FAILURES\n$URL ($STATUS)"
  fi
done

echo "Checked: $TOTAL, OK: $OK, Failed: $FAIL"
if [ -n "$FAILURES" ]; then
  echo -e "Failures:$FAILURES"
fi
```

For images, verify the response `Content-Type` header matches the expected MIME type. A 200 that returns HTML instead of an image means a broken redirect or missing file served by a fallback page.

```bash
# Verify Content-Type matches expected MIME
EXPECTED_MIME="image/jpeg"
ACTUAL_MIME=$(curl -s -o /dev/null -w "%{content_type}" "$URL" | cut -d';' -f1)
if [ "$ACTUAL_MIME" != "$EXPECTED_MIME" ]; then
  echo "MIME mismatch: expected $EXPECTED_MIME, got $ACTUAL_MIME for $URL"
fi
```

---

## 4. User Count Comparison

### 4a. Source Counts

```sql
-- D9/D10/D11: active and blocked users
SELECT
  CASE WHEN status = 1 THEN 'active' ELSE 'blocked' END AS user_status,
  COUNT(*) as count
FROM users_field_data
WHERE uid > 0
  AND default_langcode = 1
GROUP BY status;
```

```sql
-- D7: active and blocked users
SELECT
  CASE WHEN status = 1 THEN 'active' ELSE 'blocked' END AS user_status,
  COUNT(*) as count
FROM users
WHERE uid > 0
GROUP BY status;
```

### 4b. Target Counts

Adapt to the target platform. Most CMS platforms distinguish active from inactive/suspended users.

### 4c. Compare

One check entry per user status (active, blocked). If the target platform does not support blocked users, report the blocked count as `SKIP` and note it.

Also verify user role mapping:

```sql
-- Source: users per role (D9+)
SELECT roles_target_id AS role, COUNT(DISTINCT entity_id) AS count
FROM user__roles
GROUP BY roles_target_id
ORDER BY roles_target_id;
```

---

## 5. Menu Link Count and Structure Comparison

### 5a. Source Counts

```sql
-- D9/D10/D11: menu links per menu
SELECT menu_name, COUNT(*) as count
FROM menu_link_content_data
WHERE enabled = 1
GROUP BY menu_name
ORDER BY menu_name;
```

```sql
-- D7: menu links per menu
SELECT menu_name, COUNT(*) as count
FROM menu_links
WHERE hidden = 0
GROUP BY menu_name
ORDER BY menu_name;
```

### 5b. Structure Comparison

Count nesting depth per menu:

```sql
-- D9+: max depth per menu
SELECT menu_name, MAX(depth) as max_depth
FROM menu_tree
GROUP BY menu_name;
```

```sql
-- D7: max depth per menu
SELECT menu_name, MAX(depth) as max_depth
FROM menu_links
WHERE hidden = 0
GROUP BY menu_name;
```

Compare item counts and max depth for each menu. Flag menus where depth was flattened or items were lost.

### 5c. Target Counts

Query the target's navigation/menu system. WordPress example:

```bash
# WordPress: count menu items per menu location
wp menu list --format=json | jq '.[] | {name: .name, count: .count}'
```

---

## 6. Redirect Count Comparison

### 6a. Source Count

```sql
-- D8+: redirects from the redirect module
SELECT
  status_code,
  COUNT(*) as count
FROM redirect
GROUP BY status_code;

-- Total
SELECT COUNT(*) as total FROM redirect;
```

```sql
-- D7
SELECT
  status_code,
  COUNT(*) as count
FROM redirect
GROUP BY status_code;
```

### 6b. Target Count

Count redirect rules in the target's redirect system. Check:
- `.htaccess` or `nginx.conf` rules
- Platform redirect manager (WordPress Redirection plugin, Netlify `_redirects`, Vercel `vercel.json`, etc.)
- CDN-level redirects (Cloudflare Page Rules, etc.)

```bash
# Count redirects in a _redirects file (Netlify/Cloudflare Pages)
wc -l < _redirects

# Count redirects in vercel.json
jq '.redirects | length' vercel.json

# Count redirects in .htaccess
grep -c "^RewriteRule\|^Redirect " .htaccess
```

### 6c. Compare

One check entry with total redirect counts and a breakdown by status code (301, 302, 307). Missing redirects cause SEO damage. Every redirect from Drupal must have a corresponding rule on the target.

---

## 7. Sample Content Spot Check

Automated count comparison catches missing records. Spot checks catch field-level data loss, broken references, and formatting corruption.

### 7a. Select Samples

Pick 10 random published nodes per content type from the source:

```sql
-- D9+: 10 random articles
SELECT nid, title
FROM node_field_data
WHERE type = 'article'
  AND status = 1
  AND default_langcode = 1
ORDER BY RAND()
LIMIT 10;
```

For D7, replace `node_field_data` with `node` and drop `default_langcode`.

For MySQL, `ORDER BY RAND()` works. For PostgreSQL, use `ORDER BY RANDOM()`.

### 7b. Field-by-Field Comparison

For each sampled node, compare every field value between source and target.

Fields to check per node:

| Field Type | What to Compare |
|---|---|
| Title | Exact string match |
| Body / rich text | Normalized HTML comparison (strip whitespace differences, compare DOM structure) |
| Plain text | Exact string match |
| Date | Same date value (allow format differences) |
| Boolean | Same value |
| Number | Same value |
| Entity reference (taxonomy) | Referenced term name matches |
| Entity reference (media) | Media asset exists and file is accessible |
| Entity reference (node) | Referenced content exists on target |
| Link | URL and title match |
| File | File exists and downloads correctly |
| Image | File exists, alt text matches, dimensions preserved |
| Address | All components match (street, city, postal code, country) |
| Geolocation | Coordinates match within rounding tolerance |

Normalize rich text before comparison. Strip:
- Extra whitespace and newlines
- HTML comments
- data-* attributes added by Drupal editors
- Drupal-specific CSS classes (`align-left`, `drupal-media`, etc.)

Compare the remaining DOM structure and text content.

```python
# normalize_html.py — strip Drupal artifacts, compare structure
from bs4 import BeautifulSoup
import re

def normalize(html):
    soup = BeautifulSoup(html, 'html.parser')
    # Remove HTML comments
    for comment in soup.find_all(string=lambda t: isinstance(t, Comment)):
        comment.extract()
    # Remove data-* attributes
    for tag in soup.find_all(True):
        attrs = dict(tag.attrs)
        for attr in attrs:
            if attr.startswith('data-'):
                del tag[attr]
    # Remove Drupal-specific classes
    drupal_classes = {'drupal-media', 'align-left', 'align-right', 'align-center',
                      'media-library-item', 'contextual-region'}
    for tag in soup.find_all(class_=True):
        tag['class'] = [c for c in tag['class'] if c not in drupal_classes]
        if not tag['class']:
            del tag['class']
    # Normalize whitespace
    text = soup.prettify()
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def compare(source_html, target_html):
    return normalize(source_html) == normalize(target_html)
```

### 7c. Report Failures

Each spot-check entry in the report lists the node ID, the field name, and a description of the mismatch. Group failures by type (missing field, value mismatch, broken reference) to identify patterns.

---

## 8. Paragraph Structure Spot Check

Paragraphs are the highest-risk data in a Drupal migration. Nested paragraph structures break in subtle ways: wrong order, missing nested items, lost field values on deeply nested components.

### 8a. Identify Complex Pages

Find the pages with the most paragraph nesting and the most paragraph items:

```sql
-- D9+: nodes with the most paragraph references
SELECT nfd.nid, nfd.title, nfd.type, COUNT(pi.field_paragraphs_target_id) AS para_count
FROM node_field_data nfd
JOIN node__field_paragraphs pi ON pi.entity_id = nfd.nid
WHERE nfd.status = 1 AND nfd.default_langcode = 1
GROUP BY nfd.nid, nfd.title, nfd.type
ORDER BY para_count DESC
LIMIT 20;
```

Replace `field_paragraphs` with the actual paragraph reference field name for each content type. Check Skill 2 output for field names.

### 8b. Verify Structure

For each complex page, compare the full paragraph tree:
1. Count of top-level paragraph items. Must match.
2. Order of paragraph types. The sequence of paragraph bundles (hero, text, gallery, cta) must match.
3. Nested items within each paragraph. A "cards" paragraph with 4 card children must have 4 on the target.
4. Field values on each paragraph item. Text, images, links, embedded media.

Walk the tree depth-first. Report the first divergence point:

```
FAIL: node/234 "About Us" — paragraph index 3 (type: card_group)
  Expected 4 child cards, found 3.
  Missing: card at position 2 with title "Our Team"
```

### 8c. Verify Paragraph Field Values

For each paragraph item, check the same field types listed in Section 7b. Pay attention to:
- Nested entity references inside paragraphs (media, taxonomy)
- WYSIWYG fields within paragraphs (same rich text issues as node body fields)
- Link fields that may contain internal Drupal paths (`internal:/node/42`) needing conversion

---

## 9. Rich Text Rendering Check

Drupal rich text fields often contain tokens, embed codes, and filter syntax that only Drupal's rendering pipeline understands. If the migration did not transform these, they appear as raw markup in the target.

### 9a. Drupal Tokens and Filter Patterns to Detect

Scan all migrated rich text for these patterns:

| Pattern | Regex | What It Means |
|---|---|---|
| Drupal media embed (D8+) | `<drupal-media\b[^>]*>` | Embedded media entity. Must be converted to an `<img>` or platform-specific embed. |
| Drupal media embed (entity_embed) | `<drupal-entity\b[^>]*>` | Entity embed module. Same treatment as drupal-media. |
| Media embed data attribute | `data-entity-uuid="[^"]*"` | Reference to a Drupal entity by UUID. Meaningless outside Drupal. |
| Linkit reference | `data-entity-type="[^"]*"` | Linkit module internal reference. Must be resolved to a URL. |
| Token syntax | `\[node:\w+[:\w+]*\]` | Drupal token. Example: `[node:title]`, `[site:name]`. Must be resolved or removed. |
| Token syntax (general) | `\[\w+:\w+[:\w+]*\]` | Broader token match. Catches `[current-user:name]`, `[view:name]`, etc. |
| D7 media tag (JSON) | `\[\[{"fid":"\d+"` | D7 media module JSON embed. Must be converted to `<img>`. |
| PHP filter | `<\?php` | PHP code in body fields (D7 PHP filter module). Must be removed or executed and captured. |
| Inline shortcodes | `\[embed\].*?\[/embed\]` | Various contrib shortcode syntaxes. |
| Entity embed (CKEditor) | `data-embed-button="[^"]*"` | CKEditor embed button metadata. |
| View embed | `\[view:[\w_]+` | Embedded view display. Must be replaced with target-platform equivalent. |
| Webform embed | `<drupal-webform\b` | Embedded webform. Replace with target form solution. |

### 9b. Scan Migrated Content

Run the regex patterns against all rich text fields on the target:

```bash
#!/bin/bash
# scan_broken_tokens.sh — find Drupal artifacts in migrated HTML

PATTERNS=(
  '<drupal-media\b'
  '<drupal-entity\b'
  'data-entity-uuid='
  'data-entity-type='
  '\[node:[a-zA-Z_]+\]'
  '\[[a-zA-Z_]+:[a-zA-Z_]+[:\w]*\]'
  '\[\[{"fid":"[0-9]+'
  '<\?php'
  'data-embed-button='
  '\[view:[a-zA-Z_]+'
  '<drupal-webform\b'
)

echo "Scanning target content for broken Drupal tokens..."
FOUND=0

for PATTERN in "${PATTERNS[@]}"; do
  MATCHES=$(grep -rlP "$PATTERN" /path/to/exported/target/content/ 2>/dev/null | wc -l)
  if [ "$MATCHES" -gt 0 ]; then
    echo "FAIL: $PATTERN found in $MATCHES files"
    FOUND=$((FOUND + MATCHES))
    # Show first 5 occurrences
    grep -rlP "$PATTERN" /path/to/exported/target/content/ | head -5
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "PASS: No broken Drupal tokens found"
fi
```

For database-stored content on the target:

```sql
-- Generic SQL: scan body fields for drupal-media tags
SELECT id, title
FROM content
WHERE body LIKE '%<drupal-media%'
   OR body LIKE '%data-entity-uuid%'
   OR body LIKE '%[node:%'
   OR body LIKE '%[[{"fid"%'
   OR body LIKE '%<?php%';
```

### 9c. Report

One check entry per pattern type. List the content IDs where each pattern was found. Any match is a `FAIL`.

---

## 10. URL Alias Verification

Every URL that worked on the Drupal site must work on the target. This means either the same path exists, or a redirect sends visitors (and search engines) to the correct page.

### 10a. Export All Source Aliases

Pull the alias list from Skill 20 output, or query directly:

```sql
-- D9+
SELECT alias FROM path_alias WHERE status = 1 ORDER BY alias;
```

### 10b. Check Each Alias on Target

```bash
#!/bin/bash
# check_aliases.sh — verify URL aliases resolve on target

TOTAL=0
OK=0
REDIRECT=0
FAIL=0

while IFS= read -r ALIAS; do
  TOTAL=$((TOTAL + 1))
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://new-site.example.com${ALIAS}")

  case $STATUS in
    200) OK=$((OK + 1)) ;;
    301|302|307|308) REDIRECT=$((REDIRECT + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      echo "FAIL ($STATUS): $ALIAS"
      ;;
  esac
done < source_aliases.txt

echo "Total: $TOTAL, OK(200): $OK, Redirected: $REDIRECT, Failed: $FAIL"
```

Acceptable outcomes:
- **200**: Path exists on target. Best case.
- **301/308**: Permanent redirect to new location. Acceptable if the destination is correct.
- **302/307**: Temporary redirect. Flag for review. Temporary redirects do not pass full SEO value.
- **404/410/5xx**: Broken. Content is missing or the server is misconfigured.

### 10c. Validate Redirect Destinations

For redirected aliases, follow the redirect chain and verify the final destination returns 200 and displays the correct content:

```bash
# Follow redirects, show the chain
curl -sL -o /dev/null -w "%{url_effective}\n%{http_code}\n" "https://new-site.example.com/old-path"
```

Flag redirect chains longer than 2 hops. Search engines penalize long chains.

---

## 11. Redirect Verification

Separate from alias verification. This checks the explicit redirect rules migrated from Drupal's redirect module.

### 11a. Source Redirect List

From Skill 20 output or direct query:

```sql
SELECT redirect_source__path AS source_path,
       redirect_redirect__uri AS target_uri,
       status_code
FROM redirect
ORDER BY redirect_source__path;
```

### 11b. Test Each Redirect

```bash
#!/bin/bash
# test_redirects.sh — verify Drupal redirects work on target

TOTAL=0
PASS=0
FAIL=0

while IFS=$'\t' read -r SOURCE TARGET CODE; do
  TOTAL=$((TOTAL + 1))

  ACTUAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://new-site.example.com/$SOURCE")
  ACTUAL_DEST=$(curl -s -o /dev/null -w "%{redirect_url}" "https://new-site.example.com/$SOURCE")

  if [ "$ACTUAL_CODE" = "$CODE" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: /$SOURCE → expected $CODE, got $ACTUAL_CODE (dest: $ACTUAL_DEST)"
  fi
done < redirects.tsv

echo "Total: $TOTAL, Pass: $PASS, Fail: $FAIL"
```

Check both the status code and the destination URL. A 301 that points to the wrong page is worse than a 404 because it silently sends users to the wrong content.

---

## 12. Multilingual Content Check

Skip this section if the source site has no translations.

### 12a. Translation Count Comparison

```sql
-- D9+: count translations per content type and language
SELECT nfd.type, nfd.langcode, COUNT(*) as count
FROM node_field_data nfd
WHERE nfd.status = 1
  AND nfd.default_langcode = 0
GROUP BY nfd.type, nfd.langcode
ORDER BY nfd.type, nfd.langcode;
```

```sql
-- D7 with entity_translation
SELECT et.entity_type, et.language, COUNT(*) as count
FROM entity_translation et
JOIN node n ON et.entity_id = n.nid AND et.entity_type = 'node'
WHERE n.status = 1
  AND et.source <> ''
GROUP BY et.entity_type, et.language
ORDER BY et.entity_type, et.language;
```

Compare translation counts per content type and language on source vs target.

### 12b. Translation Linking

Verify that translations are linked to their source content on the target. For each translated node:

1. The source language version exists.
2. The translated version exists.
3. The target platform's translation system links them (e.g., `hreflang` tags in HTML, translation group in the CMS).

```bash
# Check hreflang tags on a page
curl -s "https://new-site.example.com/about" | grep -i 'hreflang'
# Expected: <link rel="alternate" hreflang="es" href="https://new-site.example.com/es/acerca-de" />
```

### 12c. Translated Taxonomy and Menu

Do not forget translated taxonomy terms and menu links. Count translated terms per vocabulary per language. Verify translated menu labels appear in the target's navigation.

---

## 13. Commerce Data Check

Skip if the source site has no Drupal Commerce installation.

### 13a. Product Counts

```sql
-- D8+ Commerce: products by type
SELECT type, COUNT(*) as count
FROM commerce_product_field_data
WHERE status = 1 AND default_langcode = 1
GROUP BY type;

-- Variations by type
SELECT type, COUNT(*) as count
FROM commerce_product_variation_field_data
WHERE status = 1 AND default_langcode = 1
GROUP BY type;
```

### 13b. Order Counts

```sql
-- Orders by state
SELECT state, COUNT(*) as count
FROM commerce_order
GROUP BY state;
```

### 13c. Price Verification

Sample 10 random products. Compare price, currency code, and variation count between source and target. A price migration error is a business-critical failure.

```sql
-- Sample products with prices
SELECT p.product_id, p.title, v.sku,
       v.price__number, v.price__currency_code
FROM commerce_product_field_data p
JOIN commerce_product_variation_field_data v
  ON v.product_id = p.product_id
WHERE p.status = 1 AND p.default_langcode = 1
ORDER BY RAND()
LIMIT 10;
```

### 13d. Compare

One check entry each for product count, variation count, and order count. Separate check for price spot-check results.

---

## 14. SEO Verification

### 14a. Meta Tag Comparison

Sample 20 pages across content types. Compare these meta tags between source and target:

| Meta Tag | HTML Element |
|---|---|
| Title | `<title>` |
| Description | `<meta name="description">` |
| Canonical | `<link rel="canonical">` |
| OG title | `<meta property="og:title">` |
| OG description | `<meta property="og:description">` |
| OG image | `<meta property="og:image">` |
| Twitter card | `<meta name="twitter:card">` |
| Robots | `<meta name="robots">` |

```bash
#!/bin/bash
# compare_meta.sh — compare meta tags between source and target

compare_meta() {
  local URL_PATH=$1
  local SOURCE_URL="https://drupal-site.example.com${URL_PATH}"
  local TARGET_URL="https://new-site.example.com${URL_PATH}"

  SOURCE_TITLE=$(curl -s "$SOURCE_URL" | grep -oP '(?<=<title>)[^<]+')
  TARGET_TITLE=$(curl -s "$TARGET_URL" | grep -oP '(?<=<title>)[^<]+')

  SOURCE_DESC=$(curl -s "$SOURCE_URL" | grep -oP '<meta name="description" content="\K[^"]+')
  TARGET_DESC=$(curl -s "$TARGET_URL" | grep -oP '<meta name="description" content="\K[^"]+')

  SOURCE_CANON=$(curl -s "$SOURCE_URL" | grep -oP '<link rel="canonical" href="\K[^"]+')
  TARGET_CANON=$(curl -s "$TARGET_URL" | grep -oP '<link rel="canonical" href="\K[^"]+')

  echo "Path: $URL_PATH"
  [ "$SOURCE_TITLE" = "$TARGET_TITLE" ] && echo "  title: PASS" || echo "  title: FAIL (source='$SOURCE_TITLE' target='$TARGET_TITLE')"
  [ "$SOURCE_DESC" = "$TARGET_DESC" ] && echo "  description: PASS" || echo "  description: FAIL"
  [ -n "$TARGET_CANON" ] && echo "  canonical: PASS" || echo "  canonical: FAIL (missing)"
}

# Run on sampled URLs
while IFS= read -r PATH; do
  compare_meta "$PATH"
done < sampled_urls.txt
```

### 14b. Canonical URL Check

Every page on the target must have a canonical URL tag. Self-referencing canonicals prevent duplicate content issues.

```bash
# Check all pages in sitemap for canonical tags
curl -s "https://new-site.example.com/sitemap.xml" \
  | grep -oP '<loc>\K[^<]+' \
  | while read -r URL; do
      HAS_CANON=$(curl -s "$URL" | grep -c 'rel="canonical"')
      if [ "$HAS_CANON" -eq 0 ]; then
        echo "MISSING CANONICAL: $URL"
      fi
    done
```

### 14c. Robots.txt Comparison

```bash
# Fetch and compare robots.txt
diff <(curl -s "https://drupal-site.example.com/robots.txt") \
     <(curl -s "https://new-site.example.com/robots.txt")
```

Verify:
- Sitemap URL points to the target domain.
- No new `Disallow` rules that block content previously accessible.
- User-agent rules are preserved.

### 14d. XML Sitemap Check

```bash
# Fetch sitemap, count URLs
TARGET_SITEMAP_COUNT=$(curl -s "https://new-site.example.com/sitemap.xml" \
  | grep -c '<loc>')

SOURCE_SITEMAP_COUNT=$(curl -s "https://drupal-site.example.com/sitemap.xml" \
  | grep -c '<loc>')

echo "Source sitemap URLs: $SOURCE_SITEMAP_COUNT"
echo "Target sitemap URLs: $TARGET_SITEMAP_COUNT"
```

The target sitemap should contain at least as many URLs as the source. Fewer URLs means content is missing from the sitemap or pages are not being indexed.

For sitemap indexes (multiple sitemap files), fetch and count across all child sitemaps:

```bash
# Handle sitemap index
curl -s "https://new-site.example.com/sitemap.xml" \
  | grep -oP '<loc>\K[^<]+' \
  | while read -r SITEMAP_URL; do
      if echo "$SITEMAP_URL" | grep -q "sitemap.*\.xml"; then
        COUNT=$(curl -s "$SITEMAP_URL" | grep -c '<loc>')
        echo "$SITEMAP_URL: $COUNT URLs"
      fi
    done
```

### 14e. Structured Data Check

Sample 10 pages. Verify JSON-LD or microdata is present on the target:

```bash
# Check for JSON-LD structured data
curl -s "https://new-site.example.com/sample-page" \
  | grep -oP '<script type="application/ld\+json">[^<]+' \
  | python3 -m json.tool
```

If the source had structured data (Article, Product, Organization, BreadcrumbList), the target should too. Compare schema types between source and target pages.

---

## 15. Performance Baseline Comparison

Migration should not degrade page load performance. Compare key metrics between source and target.

### 15a. Page Load Time Comparison

Sample 10 pages of different types (homepage, listing page, content page, search results). Measure time-to-first-byte (TTFB) and total load time:

```bash
#!/bin/bash
# perf_compare.sh — compare TTFB between source and target

URLS=(
  "/"
  "/blog"
  "/blog/sample-article"
  "/about"
  "/contact"
)

for PATH in "${URLS[@]}"; do
  SOURCE_TTFB=$(curl -s -o /dev/null -w "%{time_starttransfer}" "https://drupal-site.example.com${PATH}")
  TARGET_TTFB=$(curl -s -o /dev/null -w "%{time_starttransfer}" "https://new-site.example.com${PATH}")

  echo "$PATH: source=${SOURCE_TTFB}s target=${TARGET_TTFB}s"
done
```

### 15b. Page Size Comparison

```bash
# Compare page sizes (bytes)
SOURCE_SIZE=$(curl -s "https://drupal-site.example.com/" | wc -c)
TARGET_SIZE=$(curl -s "https://new-site.example.com/" | wc -c)
echo "Homepage: source=${SOURCE_SIZE}B target=${TARGET_SIZE}B"
```

### 15c. Report

One check entry per sampled page. Flag any page where target TTFB exceeds source TTFB by more than 50%. This is a warning, not a hard failure. Document the baseline for ongoing monitoring.

---

## 16. Link Checker / Broken Link Scan

Crawl the entire target site for broken links. This catches internal links to missing content, broken external links, and misconfigured asset paths.

### 16a. Run a Link Checker

Use one of these tools. All produce machine-readable output.

#### lychee (Rust, fast)

```bash
lychee --format json --output broken_links.json "https://new-site.example.com"
```

#### muffet (Go, fast)

```bash
muffet --json "https://new-site.example.com" > broken_links.json
```

#### linkchecker (Python)

```bash
linkchecker --check-extern --output=json "https://new-site.example.com" > broken_links.json
```

#### wget-based crawl

```bash
wget --spider --recursive --no-directories --output-file=wget_crawl.log \
  "https://new-site.example.com" 2>&1

# Extract broken links
grep -B2 "broken link" wget_crawl.log
```

### 16b. Categorize Results

Group broken links by type:

| Type | Meaning | Action |
|---|---|---|
| Internal 404 | Link to a page on your own site that returns 404 | Fix: content missing or URL wrong |
| Internal 5xx | Server error on your own site | Fix: server misconfiguration |
| External 404 | Link to another site that returns 404 | Review: external site changed |
| Image 404 | `<img src>` returns 404 | Fix: file missing or path wrong |
| Asset 404 | CSS/JS/font returns 404 | Fix: build or deploy issue |
| Timeout | Link did not respond within timeout | Recheck: transient or permanent |

### 16c. Report

One check entry for the full broken link scan. Report total links checked, total broken, and the top 20 broken URLs with their status codes and the pages that link to them.

---

## 17. 404 Monitoring Setup Recommendation

After migration goes live, 404 errors will surface problems the pre-launch checks missed. Recommend a 404 monitoring setup:

### Server-Level Logging

```nginx
# Nginx: log 404s to a separate file
error_log /var/log/nginx/404.log;

# Or use a custom log format
log_format fourohfour '$time_iso8601 $status $request_uri $http_referer';
access_log /var/log/nginx/404.log fourohfour if=$is_404;

# where $is_404 is set:
map $status $is_404 {
  404 1;
  default 0;
}
```

### Analytics-Based Monitoring

- **Google Search Console**: Monitor the "Pages" report under Indexing for "Not found (404)" errors. Check weekly for the first 3 months after migration.
- **Google Analytics 4**: Create an exploration filtered to page_title containing "404" or "Page not found". Track the page_location dimension to see which URLs are generating 404s.
- **Server-side 404 page logging**: Have the 404 page template send the requested URL and referrer to your analytics platform.

### Automated Alerts

```bash
# Simple cron job: alert on 404 spikes
# Run every hour
FOUROHFOUR_COUNT=$(grep "$(date +%Y-%m-%d)" /var/log/nginx/404.log | wc -l)
THRESHOLD=100
if [ "$FOUROHFOUR_COUNT" -gt "$THRESHOLD" ]; then
  echo "Alert: $FOUROHFOUR_COUNT 404s today" | mail -s "404 Spike Alert" admin@example.com
fi
```

Include this as a `SKIP` check in the report with a `details` field containing the recommended monitoring setup.

---

## 18. Generate the Final Report

Assemble all check entries into the JSON structure defined at the top of this skill.

### 18a. Summary Calculation

```python
import json

def generate_summary(checks):
    total = len(checks)
    pass_count = sum(1 for c in checks if c['status'] == 'PASS')
    fail_count = sum(1 for c in checks if c['status'] == 'FAIL')
    skip_count = sum(1 for c in checks if c['status'] == 'SKIP')
    pass_rate = f"{(pass_count / total * 100):.1f}%" if total > 0 else "0%"

    return {
        "total": total,
        "pass": pass_count,
        "fail": fail_count,
        "skip": skip_count,
        "pass_rate": pass_rate
    }
```

### 18b. Category Breakdown

Group checks by category in the report:

| Category | Checks Included |
|---|---|
| `content_counts` | Node counts per content type |
| `taxonomy_counts` | Term counts per vocabulary |
| `media_counts` | Media entity and file counts |
| `user_counts` | Active and blocked user counts |
| `menu_counts` | Menu link counts per menu |
| `redirect_counts` | Redirect totals by status code |
| `spot_check` | Random content field comparisons |
| `paragraph_check` | Complex page paragraph structure |
| `rich_text_scan` | Broken Drupal token detection |
| `url_verification` | Alias resolution checks |
| `redirect_verification` | Redirect rule testing |
| `multilingual` | Translation counts and linking |
| `commerce` | Product, variation, order counts |
| `seo` | Meta tags, canonical, robots, sitemap, structured data |
| `performance` | TTFB and page size comparison |
| `broken_links` | Full-site link checker results |
| `monitoring` | 404 monitoring setup recommendation |

### 18c. Output Format

Write the report to `validation_report.json`. Also generate a human-readable summary:

```bash
#!/bin/bash
# print_report.sh — human-readable validation summary

jq -r '
  "MIGRATION VALIDATION REPORT",
  "Source: \(.validation_run.source)",
  "Target: \(.validation_run.target)",
  "Date: \(.validation_run.timestamp)",
  "",
  "SUMMARY: \(.summary.pass)/\(.summary.total) passed (\(.summary.pass_rate))",
  "  Pass: \(.summary.pass)  Fail: \(.summary.fail)  Skip: \(.summary.skip)",
  "",
  "FAILURES:",
  (.checks[] | select(.status == "FAIL") |
    "  [\(.category)] \(.label)" +
    (if .source_count then " (source: \(.source_count), target: \(.target_count), delta: \(.delta))" else "" end) +
    (if .details then "\n    \(.details)" else "" end)
  ),
  "",
  "SKIPPED:",
  (.checks[] | select(.status == "SKIP") |
    "  [\(.category)] \(.label)" +
    (if .details then " — \(.details)" else "" end)
  )
' validation_report.json
```

### 18d. Decision Gate

Use this matrix to decide whether the migration is ready to go live:

| Pass Rate | Failures | Decision |
|---|---|---|
| 100% | None | Go live. |
| 95-99% | Cosmetic only (whitespace, minor formatting) | Go live. Fix post-launch. |
| 90-94% | No content loss, only SEO or redirect gaps | Fix redirects and SEO first. Then go live. |
| 80-89% | Some content loss or broken references | Do not go live. Fix and re-run validation. |
| Below 80% | Significant data loss | Do not go live. Investigate migration pipeline. |

Content loss (missing nodes, missing media) always blocks launch regardless of pass rate. A site at 95% with 50 missing pages is not ready. A site at 90% with only redirect gaps is closer.

---

## Execution Notes

- Run all count queries against the same snapshot. If the source site is live and content changes between queries, counts will drift.
- For large sites (50k+ nodes), batch the spot checks and file accessibility tests. Do not send 50,000 concurrent HTTP requests.
- Cache the source data. Run source queries once, save to JSON, compare repeatedly as you fix issues on the target.
- Re-run this skill after fixing failures. The report should reach 100% before go-live (excluding intentional skips).
- Keep the validation report in version control alongside the migration code. It documents what was checked and when.
