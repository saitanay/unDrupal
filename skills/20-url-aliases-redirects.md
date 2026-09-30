# Skill 20: URL Aliases, Redirects, and Redirect Rule Generation

Export path aliases, redirect mappings, and Pathauto patterns from a Drupal site. Generate platform-specific redirect rules for the migration target so no URL breaks and no SEO value is lost.

Run Skill 01 (Site Audit) first. You need the Drupal version and available access methods before starting.

---

## What You Are Extracting

| Component | Where It Lives | What It Contains |
|---|---|---|
| **Path aliases** | `path_alias` entity (D9+), `url_alias` table (D7/D8) | Internal path → clean URL mapping, per language |
| **Pathauto patterns** | `pathauto.pattern.*.yml` config (D8+), `pathauto_patterns` variable (D7) | Token-based rules that auto-generate aliases per entity type and bundle |
| **Redirects** | `redirect` table (redirect module) | Source path → destination, HTTP status code, language |
| **Base URL** | `system.site.yml` config, `$base_url` in settings.php | Needed to resolve absolute redirect targets |

---

## Prerequisites

| Access method | What it unlocks |
|---|---|
| **Drush** | SQL queries against alias and redirect tables, config export |
| **Database** | Direct access to `path_alias` / `url_alias` / `redirect` tables |
| **Config YAML** | Pathauto pattern definitions, site settings |
| **JSON:API** | Path alias entities (D9+): `/jsonapi/path_alias/path_alias` |
| **Admin UI** | Manual review at `/admin/config/search/path`, `/admin/config/search/redirect` |

---

## 1. Export Path Aliases

Path aliases map internal Drupal paths (like `/node/42`) to clean URLs (like `/blog/my-post`). Every alias must be captured. If a URL worked on the old site, it must either work on the new site or redirect.

### 1a. Database — Drupal 9 / 10 / 11

D9+ stores aliases in the `path_alias` entity table. The table name is `path_alias`.

```sql
SELECT id,
       path AS internal_path,
       alias,
       langcode,
       status
FROM path_alias
ORDER BY alias;
```

| Column | Meaning |
|---|---|
| `id` | Primary key |
| `path` | Internal system path: `/node/42`, `/taxonomy/term/7`, `/user/1` |
| `alias` | The clean URL visitors see: `/blog/my-post` |
| `langcode` | Language code (`en`, `es`, `und` for language-neutral) |
| `status` | `1` = active, `0` = disabled |

Via Drush:

```bash
drush sql:query "SELECT id, path, alias, langcode, status FROM path_alias ORDER BY alias" --result-file=path_aliases_d9.tsv
```

Export as JSON:

```php
// Run with: drush php:eval 'include "export_aliases.php";'
$storage = \Drupal::entityTypeManager()->getStorage('path_alias');
$ids = $storage->getQuery()->accessCheck(FALSE)->execute();
$aliases = [];
foreach ($storage->loadMultiple($ids) as $entity) {
  $aliases[] = [
    'id' => $entity->id(),
    'internal_path' => $entity->getPath(),
    'alias' => $entity->getAlias(),
    'langcode' => $entity->language()->getId(),
    'status' => (bool) $entity->isPublished(),
  ];
}
file_put_contents('path_aliases.json', json_encode($aliases, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo count($aliases) . " aliases exported.\n";
```

### 1b. Database — Drupal 7 / 8

D7 and D8 store aliases in the `url_alias` table. The schema differs slightly between versions.

**Drupal 8:**

```sql
SELECT pid,
       source AS internal_path,
       alias,
       langcode
FROM url_alias
ORDER BY alias;
```

**Drupal 7:**

```sql
SELECT pid,
       source AS internal_path,
       alias,
       language AS langcode
FROM url_alias
ORDER BY alias;
```

D7 uses `language` instead of `langcode`. The value `und` means no language assigned.

Via Drush (D7):

```bash
drush sql-query "SELECT pid, source, alias, language FROM url_alias ORDER BY alias" > path_aliases_d7.tsv
```

### 1c. JSON:API — Drupal 9+

Path aliases are exposed as entities:

```bash
# Fetch first page of aliases
curl -s 'https://example.com/jsonapi/path_alias/path_alias?page[limit]=50' \
  -H 'Accept: application/vnd.api+json' | python3 -m json.tool

# Paginate through all aliases
curl -s 'https://example.com/jsonapi/path_alias/path_alias?page[limit]=50&page[offset]=0'
```

Each resource object contains:

```json
{
  "type": "path_alias--path_alias",
  "id": "uuid-here",
  "attributes": {
    "path": "/node/42",
    "alias": "/blog/my-post",
    "langcode": "en",
    "status": true
  }
}
```

Paginate until `links.next` is absent. For large sites (10,000+ aliases), the database method is faster.

### 1d. Drush Config Export — Drupal 8+

Path aliases are content entities, not config. They will not appear in `drush config:export`. Use the database or JSON:API methods above.

---

## 2. Export Pathauto Patterns

Pathauto generates aliases automatically based on token patterns. Capturing these patterns tells you the URL structure logic, not just the individual URLs.

### 2a. Config YAML — Drupal 8+

Pattern configs are stored as `pathauto.pattern.{machine_name}.yml`:

```yaml
uuid: 12345678-abcd-...
langcode: en
status: true
dependencies:
  module:
    - node
    - pathauto
id: article_alias
label: 'Article URL pattern'
type: 'canonical_entities:node'
pattern: 'blog/[node:title]'
selection_criteria:
  abc12345-...:
    id: node_type
    negate: false
    context_mapping:
      node: '@node.node_route_context:node'
    bundles:
      article: article
selection_logic: and
weight: 0
```

Key fields:

| Field | Meaning |
|---|---|
| `id` | Machine name |
| `type` | Entity type this pattern applies to. Format: `canonical_entities:{entity_type}` |
| `pattern` | Token string. Drupal replaces tokens at alias creation time. |
| `selection_criteria` | Conditions that scope this pattern to specific bundles, languages, or other context. |
| `weight` | Priority when multiple patterns match. Lower weight wins. |

Common `type` values:

| Type value | Applies to |
|---|---|
| `canonical_entities:node` | Content (nodes) |
| `canonical_entities:taxonomy_term` | Taxonomy terms |
| `canonical_entities:user` | User profiles |
| `canonical_entities:media` | Media entities |
| `canonical_entities:commerce_product` | Commerce products |

Export all patterns:

```bash
# From config sync directory
ls config/sync/pathauto.pattern.*.yml

# Via Drush
for p in $(drush config:list | grep '^pathauto\.pattern\.'); do
  drush config:get "$p" --format=json
done > pathauto_patterns.json
```

### 2b. Common Token Patterns

These are the tokens you will see most often in Pathauto patterns. You need to map each to its equivalent in the target platform's URL generation logic.

| Token | Resolves To | Example Output |
|---|---|---|
| `[node:title]` | Node title, lowercased and transliterated | `my-great-post` |
| `[node:content-type]` | Content type machine name | `article` |
| `[node:content-type:name]` | Content type label | `Article` |
| `[node:created:custom:Y]` | Year from created date | `2024` |
| `[node:created:custom:m]` | Month from created date | `03` |
| `[node:field_category:entity:name]` | Referenced taxonomy term name | `technology` |
| `[node:menu-link:parents:join-path]` | Menu trail as path segments | `products/widgets` |
| `[term:vocabulary]` | Vocabulary machine name | `tags` |
| `[term:name]` | Term name | `javascript` |
| `[term:parents:join-path]` | Parent term chain | `languages/scripting` |
| `[user:name]` | Username | `jdoe` |

### 2c. Database — Drupal 7

D7 stores Pathauto patterns as variables in the `variable` table:

```sql
SELECT name, value
FROM variable
WHERE name LIKE 'pathauto_%_pattern'
ORDER BY name;
```

The `value` column is a serialized PHP string. Common variable names:

| Variable name | Controls |
|---|---|
| `pathauto_node_pattern` | Default pattern for all nodes |
| `pathauto_node_article_pattern` | Pattern for article nodes |
| `pathauto_node_page_pattern` | Pattern for basic page nodes |
| `pathauto_taxonomy_term_pattern` | Default pattern for all terms |
| `pathauto_taxonomy_term_tags_pattern` | Pattern for the "tags" vocabulary |
| `pathauto_user_pattern` | Pattern for user profiles |

Deserialize all patterns:

```bash
drush vget pathauto --format=json 2>/dev/null || \
drush sql-query "SELECT name, value FROM variable WHERE name LIKE 'pathauto_%'" > pathauto_d7.tsv
```

---

## 3. Export Redirects

The redirect module stores explicit redirects. These are different from aliases. A redirect sends users (and search engines) from one URL to another with a 301/302/307 status code.

### 3a. Database — Drupal 8 / 9 / 10 / 11

The `redirect` table stores redirect entities. The source and destination are serialized as blobs, but the key columns are readable.

```sql
SELECT rid,
       redirect_source__path AS source_path,
       redirect_source__query AS source_query,
       redirect_redirect__uri AS redirect_target,
       status_code,
       language,
       count,
       uid
FROM redirect
ORDER BY redirect_source__path;
```

| Column | Meaning |
|---|---|
| `rid` | Primary key |
| `redirect_source__path` | Source path without leading slash: `old-page` |
| `redirect_source__query` | Serialized query parameters (nullable). If set, the redirect only fires when these query params match. |
| `redirect_redirect__uri` | Target. Formats: `internal:/node/42`, `entity:node/42`, `https://example.com/new-page`, or `base:new-path` |
| `status_code` | HTTP status: `301` (permanent), `302` (temporary), `307` (temporary, preserves method) |
| `language` | Language code or `und` for all languages |
| `count` | Number of times this redirect has been followed (usage tracking) |

Export as JSON via Drush:

```php
// Run with: drush php:eval 'include "export_redirects.php";'
$storage = \Drupal::entityTypeManager()->getStorage('redirect');
$ids = $storage->getQuery()->accessCheck(FALSE)->execute();
$redirects = [];
foreach ($storage->loadMultiple($ids) as $redirect) {
  $source = $redirect->getSource();
  $redir = $redirect->getRedirect();
  $redirects[] = [
    'rid' => $redirect->id(),
    'source_path' => '/' . $source['path'],
    'source_query' => $source['query'] ?? null,
    'redirect_target' => $redir['uri'],
    'status_code' => (int) $redirect->getStatusCode(),
    'language' => $redirect->language()->getId(),
  ];
}
file_put_contents('redirects.json', json_encode($redirects, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo count($redirects) . " redirects exported.\n";
```

### 3b. Database — Drupal 7

D7's redirect module uses a different schema:

```sql
SELECT rid,
       source AS source_path,
       source_options,
       redirect AS redirect_target,
       redirect_options,
       status_code,
       language,
       count
FROM redirect
ORDER BY source;
```

`source_options` and `redirect_options` are serialized PHP arrays. They may contain query strings and fragments.

Deserialize:

```php
// D7 drush script
$result = db_query("SELECT * FROM {redirect}");
$redirects = [];
foreach ($result as $row) {
  $redirects[] = [
    'rid' => $row->rid,
    'source_path' => '/' . $row->source,
    'source_options' => unserialize($row->source_options),
    'redirect_target' => $row->redirect,
    'redirect_options' => unserialize($row->redirect_options),
    'status_code' => (int) $row->status_code,
    'language' => $row->language,
  ];
}
$json = json_encode($redirects, JSON_PRETTY_PRINT);
file_put_contents('redirects_d7.json', $json);
drush_print(count($redirects) . " redirects exported.");
```

### 3c. Detecting the Redirect Module

The redirect module is contrib, not core. Confirm it exists before querying:

```bash
# D8+
drush pm:list --status=enabled --format=list | grep '^redirect$'

# D7
drush pm-list --status=enabled | grep -w redirect

# Or check the database directly
# D8+
SELECT name FROM config WHERE name = 'redirect.settings';
# D7
SELECT name FROM system WHERE name = 'redirect' AND status = 1;
```

If the redirect module is not installed, skip Section 3. Some sites use `.htaccess` rules or nginx config for redirects instead. Ask the user if they have server-level redirect rules outside Drupal.

---

## 4. Resolve Redirect Targets

The `redirect_redirect__uri` (D8+) and `redirect` (D7) columns store targets in Drupal-internal formats. You must resolve these to final URLs before generating platform rules.

| Stored format | Meaning | Resolution |
|---|---|---|
| `internal:/node/42` | Internal path | Look up the alias for `/node/42` in the alias table |
| `entity:node/42` | Entity reference | Same as above. Resolve entity path, then look up alias. |
| `base:new-path` | Relative to site root | Use `/new-path` directly |
| `https://example.com/page` | Absolute external URL | Use as-is |
| `<front>` | The site front page | Resolve to `/` |

Resolution script for D8+:

```php
// Run with: drush php:eval 'include "resolve_redirects.php";'
$alias_manager = \Drupal::service('path_alias.manager');
$redirects = json_decode(file_get_contents('redirects.json'), true);

foreach ($redirects as &$r) {
  $uri = $r['redirect_target'];

  if (str_starts_with($uri, 'internal:/')) {
    $internal = substr($uri, strlen('internal:'));
    $r['resolved_target'] = $alias_manager->getAliasByPath($internal) ?: $internal;
  } elseif (str_starts_with($uri, 'entity:')) {
    $path = '/' . str_replace('entity:', '', $uri);
    // entity:node/42 → /node/42
    $r['resolved_target'] = $alias_manager->getAliasByPath($path) ?: $path;
  } elseif (str_starts_with($uri, 'base:')) {
    $r['resolved_target'] = '/' . substr($uri, strlen('base:'));
  } elseif ($uri === 'internal:/<front>') {
    $r['resolved_target'] = '/';
  } else {
    // External URL or already resolved
    $r['resolved_target'] = $uri;
  }
}

file_put_contents('redirects_resolved.json', json_encode($redirects, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "Redirects resolved.\n";
```

---

## 5. Build the Combined URL Map

Before generating redirect rules, merge aliases and redirects into a single map. This map answers: for every URL that existed on the old site, where should it go on the new site?

```python
#!/usr/bin/env python3
"""Merge path aliases and redirects into a unified URL map."""
import json
import sys

aliases = json.load(open('path_aliases.json'))
redirects = json.load(open('redirects_resolved.json'))

url_map = []

# 1. Path aliases: old internal path → alias
# Both the internal path and the alias existed on the old site.
# If the new site preserves the alias as a real page, no redirect needed.
# If the new site changes the URL, both the alias and the internal path need redirects.
for a in aliases:
    url_map.append({
        'old_url': a['internal_path'],
        'new_url': a['alias'],
        'type': 'alias',
        'langcode': a['langcode'],
        'status_code': 301,
    })

# 2. Explicit redirects
for r in redirects:
    url_map.append({
        'old_url': r['source_path'],
        'new_url': r.get('resolved_target', r['redirect_target']),
        'type': 'redirect',
        'langcode': r['language'],
        'status_code': r['status_code'],
    })

# 3. Deduplicate: if a redirect and an alias both claim the same old_url,
#    the explicit redirect wins.
seen = {}
for entry in url_map:
    key = entry['old_url']
    if key in seen:
        if entry['type'] == 'redirect':
            seen[key] = entry  # redirect overrides alias
    else:
        seen[key] = entry

final = sorted(seen.values(), key=lambda x: x['old_url'])

json.dump(final, open('url_map.json', 'w'), indent=2, ensure_ascii=False)
print(f"{len(final)} URL mappings written to url_map.json")
```

---

## 6. Generate Redirect Rules for Target Platforms

Feed `url_map.json` into one of the generators below. Each produces output ready to drop into the target platform.

### 6a. Nginx Rewrite Rules

Output goes in the nginx server block or an included file.

```python
#!/usr/bin/env python3
"""Generate nginx rewrite map from url_map.json."""
import json

url_map = json.load(open('url_map.json'))

print("# nginx redirect map")
print("# Include this file in your server block:")
print("#   include /etc/nginx/conf.d/drupal_redirects.conf;")
print()

for entry in url_map:
    old = entry['old_url']
    new = entry['new_url']
    code = entry['status_code']

    # Skip external URLs in rewrite (handle with proxy_pass or return)
    if new.startswith('http://') or new.startswith('https://'):
        print(f"rewrite ^{old}$ {new} {'permanent' if code == 301 else 'redirect'};")
    else:
        flag = 'permanent' if code == 301 else 'redirect'
        print(f"rewrite ^{old}$ {new} {flag};")
```

For large redirect sets (1,000+), use an nginx `map` block instead of individual `rewrite` directives. This is more efficient:

```python
#!/usr/bin/env python3
"""Generate nginx map block for large redirect sets."""
import json

url_map = json.load(open('url_map.json'))

# Separate by status code
permanent = [e for e in url_map if e['status_code'] == 301]
temporary = [e for e in url_map if e['status_code'] != 301]

if permanent:
    print("map $request_uri $redirect_301 {")
    print("    default \"\";")
    for entry in permanent:
        print(f"    {entry['old_url']} {entry['new_url']};")
    print("}")
    print()
    print("# In the server block:")
    print("# if ($redirect_301) {")
    print("#     return 301 $redirect_301;")
    print("# }")

if temporary:
    print()
    print("map $request_uri $redirect_302 {")
    print("    default \"\";")
    for entry in temporary:
        print(f"    {entry['old_url']} {entry['new_url']};")
    print("}")
    print()
    print("# if ($redirect_302) {")
    print("#     return 302 $redirect_302;")
    print("# }")
```

### 6b. Apache .htaccess

```python
#!/usr/bin/env python3
"""Generate Apache .htaccess RewriteRule directives from url_map.json."""
import json
import re

url_map = json.load(open('url_map.json'))

print("# Apache redirect rules from Drupal migration")
print("# Add to .htaccess or VirtualHost config")
print()
print("RewriteEngine On")
print()

for entry in url_map:
    old = entry['old_url']
    new = entry['new_url']
    code = entry['status_code']

    # Escape regex special chars in the old path
    old_escaped = re.escape(old.lstrip('/'))
    # RewriteRule pattern does not include leading slash
    flag = f"R={code},L"

    if new.startswith('http://') or new.startswith('https://'):
        print(f"RewriteRule ^{old_escaped}$ {new} [{flag}]")
    else:
        print(f"RewriteRule ^{old_escaped}$ {new} [{flag}]")
```

### 6c. Netlify `_redirects`

Netlify reads a `_redirects` file in the publish directory. One rule per line.

```python
#!/usr/bin/env python3
"""Generate Netlify _redirects file from url_map.json."""
import json

url_map = json.load(open('url_map.json'))

print("# Netlify _redirects")
print("# Place in your publish directory root")
print()

for entry in url_map:
    old = entry['old_url']
    new = entry['new_url']
    code = entry['status_code']
    # Netlify uses "301!" for forced redirects (ignore asset pipeline)
    print(f"{old}  {new}  {code}")
```

Format: `from  to  status_code`. Use `301!` to force the redirect even if a file exists at the `from` path.

### 6d. Vercel `vercel.json`

```python
#!/usr/bin/env python3
"""Generate Vercel redirects config from url_map.json."""
import json

url_map = json.load(open('url_map.json'))

redirects = []
for entry in url_map:
    redirects.append({
        "source": entry['old_url'],
        "destination": entry['new_url'],
        "statusCode": entry['status_code'],
    })

config = {"redirects": redirects}

with open('vercel_redirects.json', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f"{len(redirects)} redirects written to vercel_redirects.json")
print("Merge into your vercel.json under the 'redirects' key.")
```

Output structure:

```json
{
  "redirects": [
    {
      "source": "/old-path",
      "destination": "/new-path",
      "statusCode": 301
    }
  ]
}
```

Vercel limits: 1,024 redirects in `vercel.json`. For larger sets, use middleware.

### 6e. Cloudflare Pages `_redirects`

Cloudflare Pages uses the same `_redirects` format as Netlify:

```
/old-path  /new-path  301
```

Limits: 2,000 static redirects max, 100 dynamic (with splats/placeholders). For larger sets, use Cloudflare Workers or bulk redirects via the dashboard API.

The generator from Section 6c works for Cloudflare Pages. The file goes in the build output directory.

### 6f. Next.js `next.config.js`

```python
#!/usr/bin/env python3
"""Generate Next.js redirects array from url_map.json."""
import json

url_map = json.load(open('url_map.json'))

redirects = []
for entry in url_map:
    redirects.append({
        "source": entry['old_url'],
        "destination": entry['new_url'],
        "permanent": entry['status_code'] == 301,
    })

# Output as a JS module snippet
print("// Add to next.config.js (or next.config.mjs)")
print("// module.exports = { async redirects() { return [...] } }")
print()
print("const drupalRedirects = " + json.dumps(redirects, indent=2) + ";")
print()
print("module.exports = {")
print("  async redirects() {")
print("    return drupalRedirects;")
print("  },")
print("};")
```

Output structure per entry:

```javascript
{
  source: "/old-path",
  destination: "/new-path",
  permanent: true  // true = 308 (permanent), false = 307 (temporary)
}
```

Next.js note: `permanent: true` returns 308 (not 301). To force 301, use `statusCode: 301` instead of `permanent`:

```javascript
{
  source: "/old-path",
  destination: "/new-path",
  statusCode: 301,
}
```

Next.js limits: 1,024 redirects at the config level. For larger sets, use middleware with a lookup map.

### 6g. Hugo (Static Aliases)

Hugo handles aliases differently. Each content page declares its old URLs in front matter:

```yaml
aliases:
  - /old-path
  - /another-old-path
```

Hugo generates an HTML meta-refresh redirect at each alias path pointing to the canonical page. No server config needed.

```python
#!/usr/bin/env python3
"""Generate Hugo alias front matter snippets from url_map.json."""
import json
from collections import defaultdict

url_map = json.load(open('url_map.json'))

# Group by destination (new_url → list of old_urls)
by_dest = defaultdict(list)
for entry in url_map:
    by_dest[entry['new_url']].append(entry['old_url'])

for dest, sources in sorted(by_dest.items()):
    print(f"# Page: {dest}")
    print("aliases:")
    for src in sources:
        print(f"  - {src}")
    print()
```

Hugo aliases are client-side redirects (meta refresh + JS). They work for SEO but add a small delay. For 301 redirects at the server level, combine Hugo with Netlify/Cloudflare `_redirects`.

---

## 7. Handle Edge Cases

### Query String Redirects

Some Drupal redirects match on query parameters. The `redirect_source__query` column (D8+) or `source_options` (D7) contains the query conditions.

```sql
-- D8+: Find redirects with query string conditions
SELECT redirect_source__path, redirect_source__query, redirect_redirect__uri
FROM redirect
WHERE redirect_source__query IS NOT NULL
  AND redirect_source__query != 'N;'
  AND redirect_source__query != '';
```

These require platform-specific handling:

- **Nginx:** Use `if ($arg_param = "value")` inside a location block
- **Apache:** Add `RewriteCond %{QUERY_STRING}` before the `RewriteRule`
- **Netlify/Vercel/Cloudflare Pages:** Cannot match query strings in static redirect files. Use edge functions or middleware.
- **Next.js:** Use `has` conditions in the redirect config:

```javascript
{
  source: "/old-page",
  has: [{ type: "query", key: "id", value: "42" }],
  destination: "/new-page/42",
  statusCode: 301,
}
```

### Language-Prefixed URLs

Multilingual sites often prefix aliases with the language code: `/es/blog/mi-post`. The alias table stores the alias without the prefix. The language prefix comes from the URL language negotiation config.

Check the prefix settings:

```bash
# D8+
drush config:get language.negotiation --format=json
```

Or from config YAML:

```yaml
# language.types.yml, language.negotiation.yml
# Look for the url method and its prefix configuration
```

```sql
-- Get language prefixes (D8+)
SELECT name, data FROM config WHERE name = 'language.negotiation';
```

When generating redirect rules, prepend the language prefix to both source and destination if the site used prefixed URLs:

```
/es/old-path  /es/new-path  301
/fr/old-path  /fr/new-path  301
```

### Internal Path Redirects

Drupal's alias system makes both `/node/42` and `/blog/my-post` resolve to the same content (with a redirect from internal to alias). After migration, the internal paths no longer exist, but search engines or old links may still reference them.

Generate redirects for all internal paths:

```python
# From path_aliases.json
for alias in aliases:
    if alias['internal_path'] != alias['alias']:
        print(f"{alias['internal_path']}  {alias['alias']}  301")
```

### Trailing Slash Normalization

Drupal typically serves pages without trailing slashes. If the target platform uses a different convention, add normalization rules:

```
# Nginx: strip trailing slash
rewrite ^/(.*)/$ /$1 permanent;

# Nginx: add trailing slash
rewrite ^(.*[^/])$ $1/ permanent;
```

---

## 8. Validation

After generating redirect rules, verify them before deploying.

### Count Check

```bash
# Compare counts
echo "Aliases in Drupal: $(cat path_aliases.json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
echo "Redirects in Drupal: $(cat redirects.json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
echo "Rules in URL map: $(cat url_map.json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
```

### Circular Redirect Detection

```python
#!/usr/bin/env python3
"""Detect circular redirects in url_map.json."""
import json

url_map = json.load(open('url_map.json'))
by_source = {e['old_url']: e['new_url'] for e in url_map}

for start, target in by_source.items():
    visited = {start}
    current = target
    while current in by_source:
        if current in visited:
            print(f"CIRCULAR: {start} -> ... -> {current}")
            break
        visited.add(current)
        current = by_source[current]
```

### Chain Detection

Redirect chains (A→B→C) slow down crawlers and waste crawl budget. Flatten them:

```python
#!/usr/bin/env python3
"""Flatten redirect chains in url_map.json."""
import json

url_map = json.load(open('url_map.json'))
by_source = {e['old_url']: e for e in url_map}

for entry in url_map:
    target = entry['new_url']
    hops = 0
    while target in by_source and hops < 10:
        target = by_source[target]['new_url']
        hops += 1
    if hops > 0:
        original_target = entry['new_url']
        entry['new_url'] = target
        print(f"FLATTENED: {entry['old_url']} -> {original_target} -> ... -> {target} ({hops + 1} hops)")

json.dump(url_map, open('url_map_flat.json', 'w'), indent=2, ensure_ascii=False)
```

### Smoke Test with curl

After deploying redirect rules, test a sample:

```bash
# Test a batch of redirects
head -20 url_map.json | python3 -c "
import json, sys
for entry in json.load(sys.stdin)[:20]:
    old = entry['old_url']
    new = entry['new_url']
    code = entry['status_code']
    print(f'curl -s -o /dev/null -w \"%{{http_code}} %{{redirect_url}}\" https://newsite.example{old}')
" | sh
```

---

## Output Checklist

At the end of this skill, the user should have:

| File | Contents |
|---|---|
| `path_aliases.json` | Every path alias: internal path, alias, language, status |
| `pathauto_patterns.json` | Every Pathauto pattern: entity type, bundle, token pattern, weight |
| `redirects.json` | Every redirect: source, target (raw), status code, language |
| `redirects_resolved.json` | Same as above with resolved targets (aliases looked up) |
| `url_map.json` | Merged, deduplicated map of old URL → new URL |
| Platform-specific file | One of: nginx conf, `.htaccess`, `_redirects`, `vercel.json`, `next.config.js`, Hugo aliases |

Report the counts for each file. Flag any circular redirects, redirect chains longer than 2 hops, or query-string redirects that need manual handling.
