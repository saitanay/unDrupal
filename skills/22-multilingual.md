# Skill 22: Multilingual Content, Interface Translations, and Config Translations

Export every layer of Drupal's multilingual system: configured languages, language negotiation settings, content translations, interface string translations, config translations, language-specific path aliases, and language-specific menu links. Produces a complete multilingual map suitable for rebuilding the site in any language-aware target platform.

Run Skills 01 (Site Audit), 02 (Content Model Map), and 11 (Node Content Export) first. You need the Drupal version, access methods, content model, and base content export before extracting translations.

## Prerequisites

| Dependency | Why |
|---|---|
| **Skill 01 output** | Drupal version determines multilingual architecture (D7 i18n contrib vs D9+ core) |
| **Skill 02 output** | Field-level `translatable` flags determine which fields carry translated values |
| **Skill 11 output** | Base-language content must exist before layering translations on top |
| **Skill 15 output** | Menu link export. This skill adds language-specific menu link translations. |

| Access method | What it unlocks |
|---|---|
| **Drush** | Language list, locale export (PO files), config translation export, content queries |
| **Database** | Full translation tables, interface strings, config translations, language negotiation settings |
| **Config directory** (YAML) | Language definitions, negotiation config, field translatability flags |
| **JSON:API** | Translated content entities via `?filter[langcode]=xx` or content negotiation |
| **Admin UI** | Manual review of translation status. Last resort. |

---

## Background: Drupal's Four Translation Layers

Drupal multilingual is not one system. It is four independent systems that happen to share a language list.

### Layer 1: Language Configuration

The language list itself. Every language has a langcode (IETF), label, weight (sort order), and a direction (LTR/RTL). One language is marked default. The language list gates everything else: no language defined, no translations possible.

### Layer 2: Content Translation

Translatable entity fields. Each translatable entity (node, taxonomy term, menu link, block, paragraph, media) can have one row per language in its data table. The `langcode` column distinguishes translations. One translation is the "original" (source language). Others are translations of it.

D9+ stores this in core. D7 uses the `i18n` contrib module suite, which works differently.

### Layer 3: Interface Translation (Locale)

Translatable UI strings. Button labels, form labels, validation messages, module-provided text. Stored in `locales_source` (English source strings) and `locales_target` (translations keyed by langcode). This is Drupal's version of gettext. The `locale` module manages it.

Community translations ship as `.po` files from `localize.drupal.org`. Sites also store custom translations (strings manually overridden by site administrators). Both end up in the same tables, distinguished by a `customized` flag.

### Layer 4: Config Translation

Translated configuration values. Site name, site slogan, view labels, metatag defaults, field labels, vocabulary names, content type descriptions. Stored as config overrides in the `config` table (D8+) with a `language.config.{langcode}.{config_name}` naming pattern.

D7 has no config translation system. D7 translates some config-like strings through the `i18n_string` module, which stores them in `i18n_string` and `locales_target`.

---

## 1. Language Configuration

### 1a. Via Config YAML (D8+)

Language definitions live in `language.entity.{langcode}.yml`:

```yaml
# language.entity.fr.yml
uuid: a1b2c3d4-...
langcode: fr
status: true
dependencies: {}
id: fr
label: French
direction: ltr
weight: 1
locked: false
```

| Field | Meaning |
|---|---|
| `id` | IETF langcode. `en`, `fr`, `de`, `zh-hans`, `pt-br`. |
| `label` | Human-readable name. |
| `direction` | `ltr` or `rtl`. Affects CSS and markup direction. |
| `weight` | Sort order in language switchers and admin lists. Lower = first. |
| `locked` | Locked languages (`und` for "Not specified", `zxx` for "Not applicable") cannot be deleted. |

List all configured languages:

```bash
ls config/sync/language.entity.*.yml
```

The default language is set in `system.site.yml`:

```yaml
# system.site.yml (partial)
langcode: en
default_langcode: en
```

And in `language.negotiation.yml` the default language fallback is configured.

### 1b. Via Drush

```bash
# List all configured languages
drush language:list

# Same as JSON for parsing
drush language:list --format=json
```

Output includes langcode, label, default status, and weight.

### 1c. Via Database (D8+)

Languages are config entities:

```sql
SELECT name, data FROM config
WHERE name LIKE 'language.entity.%'
ORDER BY name;
```

The `data` column is PHP-serialized. Unserialize each row to get the same fields as the YAML.

Default language:

```sql
SELECT data FROM config WHERE name = 'system.site';
-- Unserialize, read 'default_langcode' key.
```

### 1d. Via Database (D7)

D7 stores languages in a dedicated `languages` table:

```sql
SELECT language, name, native, direction, enabled, weight, domain, prefix
FROM languages
WHERE enabled = 1
ORDER BY weight;
```

| Column | Meaning |
|---|---|
| `language` | Langcode (`en`, `fr`, `de`) |
| `name` | English name |
| `native` | Name in the language itself (e.g. "Français") |
| `direction` | `0` = LTR, `1` = RTL |
| `enabled` | `1` = active |
| `domain` | Language-specific domain if using domain negotiation |
| `prefix` | URL prefix (`fr`, `de`) if using path prefix negotiation |

Default language:

```sql
SELECT language FROM languages
WHERE enabled = 1
ORDER BY weight ASC
LIMIT 1;
```

Or check the `language_default` variable:

```sql
SELECT value FROM variable WHERE name = 'language_default';
-- PHP-serialized object with `language`, `name`, `direction`, etc.
```

---

## 2. Language Negotiation

Language negotiation determines which language Drupal uses for a given request. The negotiation stack processes a list of detection methods in priority order.

### 2a. Via Config YAML (D8+)

Two config files control negotiation:

`language.types.yml` defines the negotiation types:

```yaml
# language.types.yml
negotiation:
  language_interface: true
  language_content: true
  language_url: true
configurable:
  - language_interface
  - language_content
  - language_url
```

The three types:
- `language_interface` — UI language (which interface translation to use)
- `language_content` — content language (which translation of an entity to show)
- `language_url` — URL language (which language the URL implies)

`language.negotiation.yml` defines which detection methods are enabled for each type and their order:

```yaml
# language.negotiation.yml
url:
  source: path_prefix
  prefixes:
    en: ''
    fr: fr
    de: de
  domains:
    en: ''
    fr: ''
    de: ''
selected_langcode: site_default
```

Detection methods and their config keys:

| Method | Config key | How it works |
|---|---|---|
| URL path prefix | `language-url` | `/fr/about` means French. Prefix map in `language.negotiation.yml`. |
| URL domain | `language-url` | `fr.example.com` means French. Domain map in `language.negotiation.yml`. Source must be set to `domain`. |
| Browser | `language-browser` | Reads `Accept-Language` HTTP header. |
| Session | `language-session` | Stores language choice in the user's session. Set via query parameter. |
| User preference | `language-user` | Uses the `preferred_langcode` field on the user entity. |
| Admin language | `language-user-admin` | Separate language for admin pages. |
| Selected language | `language-selected` | Hardcoded fallback. Usually `site_default`. |

Per-type method configuration lives in individual config files:

```bash
ls config/sync/language.mappings.yml 2>/dev/null
ls config/sync/language.content_settings.*.yml 2>/dev/null
```

The method weights (priority order) are stored in:

```sql
-- D8+ database
SELECT name, data FROM config
WHERE name LIKE 'language.negotiation.%'
ORDER BY name;
```

### 2b. Via Database (D7)

D7 stores negotiation settings as variables:

```sql
SELECT name, value FROM variable
WHERE name LIKE 'language_negotiation_%'
ORDER BY name;
```

Key variables:

| Variable | Contains |
|---|---|
| `language_negotiation_language` | Serialized array of enabled providers with weights for the main language type |
| `language_negotiation_language_content` | Providers for content language |
| `language_negotiation_language_url` | Providers for URL language |

D7 provider names differ from D8+:
- `locale-url` (path prefix or domain)
- `locale-browser` (browser Accept-Language)
- `locale-session` (session parameter)
- `locale-user` (user account preference)

URL prefix settings:

```sql
SELECT language, prefix, domain FROM languages;
```

### 2c. Export Format

Export negotiation settings as:

```json
{
  "negotiation": {
    "url_method": "path_prefix",
    "prefixes": {
      "en": "",
      "fr": "fr",
      "de": "de"
    },
    "domains": {},
    "detection_order": [
      "url",
      "user",
      "browser",
      "selected"
    ],
    "default_language": "en"
  }
}
```

The target platform needs this to replicate the same URL structure. If the source uses path prefixes `/fr/about`, the target should too for SEO continuity.

---

## 3. Content Translation Status

### 3a. Which Entity Types and Bundles Are Translatable (D8+)

Content translation settings live in `language.content_settings.{entity_type}.{bundle}.yml`:

```yaml
# language.content_settings.node.article.yml
uuid: ...
langcode: en
status: true
dependencies:
  config:
    - node.type.article
id: node.article
target_entity_type_id: node
target_bundle: article
default_langcode: site_default
language_alterable: true
content_translation_enabled: true
third_party_settings:
  content_translation:
    enabled: true
```

| Field | Meaning |
|---|---|
| `content_translation_enabled` | `true` means this bundle accepts translations |
| `default_langcode` | How the default language is determined: `site_default`, `current_interface`, or a fixed langcode |
| `language_alterable` | Whether editors can change the language of an entity after creation |

List all translatable bundles:

```bash
grep -l "content_translation_enabled: true" config/sync/language.content_settings.*.yml
```

Or via Drush:

```bash
drush eval "
  \$manager = \Drupal::service('content_translation.manager');
  foreach (\Drupal::entityTypeManager()->getDefinitions() as \$id => \$type) {
    if (\$manager->isEnabled(\$id)) {
      echo \"\$id\n\";
    }
  }
"
```

### 3b. Which Fields Are Translatable

Check `field.field.{entity_type}.{bundle}.{field_name}.yml`:

```yaml
translatable: true
```

Some fields are always translatable per entity type (title, status, created, changed). Others follow the `translatable` flag in their field config.

List all translatable fields for a bundle:

```bash
grep -l "translatable: true" config/sync/field.field.node.article.*.yml
```

Base fields (title, status, uid, created) are controlled by the entity type's `translatable` annotation. If content translation is enabled for a bundle, base field translatability is set in:

```sql
-- D8+ database
SELECT name, data FROM config
WHERE name LIKE 'language.content_settings.%';
-- Each entry contains a 'third_party_settings.content_translation' key
-- with field-level override settings.
```

### 3c. D7 Content Translation

D7 has two translation models. Sites use one or the other, never both on the same content type.

**Model 1: Node translation (core `translation` module)**

Each translation is a separate node linked by `tnid` (translation node ID). The original node's `nid` becomes the `tnid` for the group.

```sql
SELECT n.nid, n.tnid, n.language, n.title, n.type
FROM node n
WHERE n.tnid > 0
ORDER BY n.tnid, n.language;
```

| Column | Meaning |
|---|---|
| `tnid` | Translation set ID. All nodes sharing a `tnid` are translations of each other. `tnid = 0` means untranslated. |
| `language` | Langcode of this node. `und` means language-neutral. |

This model duplicates the entire node. Each translation has its own `nid`, its own fields, its own revision history. They share nothing except the `tnid` link.

**Model 2: Entity Translation (contrib `entity_translation` module)**

Single node, multiple field translations stored in the same field tables. This is the predecessor to D9+ core content translation.

```sql
SELECT entity_type, entity_id, revision_id, language, source, status, created, changed
FROM entity_translation
ORDER BY entity_type, entity_id, language;
```

| Column | Meaning |
|---|---|
| `entity_type` | Usually `node` |
| `entity_id` | Node ID |
| `language` | Langcode of this translation |
| `source` | Source language this was translated from |
| `status` | `1` = published translation |

Field values are stored in per-field tables with the `language` column:

```sql
SELECT entity_id, language, field_body_value
FROM field_data_field_body
WHERE entity_id = 123
ORDER BY language;
```

Each row is a different language's value for the same field on the same entity.

Detect which model is in use:

```sql
-- If entity_translation table exists, Model 2 is installed
SHOW TABLES LIKE 'entity_translation';

-- If nodes have tnid values > 0, Model 1 is in use
SELECT COUNT(*) FROM node WHERE tnid > 0;
```

A D7 site may use Model 1 for some content types and Model 2 for others (via different module configuration). Check both.

---

## 4. Extracting Translated Content

### 4a. Via JSON:API (D9+)

JSON:API returns one language per request. Two ways to select the language:

**Path prefix method** (if language negotiation uses path prefixes):

```
GET /fr/jsonapi/node/article?page[limit]=50
```

Prepend the language prefix to the JSON:API base path. This returns French translations of all articles. Nodes without a French translation return their default language version.

**Filter method:**

```
GET /jsonapi/node/article?filter[langcode]=fr&page[limit]=50
```

This returns only nodes that have a French translation. Nodes without a French translation are excluded from results.

The filter method is better for migration because it tells you exactly which nodes have translations in each language.

**For each language, for each content type:**

```
GET /jsonapi/node/{bundle}?filter[langcode]={langcode}&page[limit]=50&page[offset]=0
```

Compare the node UUIDs returned for each language against the default-language export from Skill 11. Nodes present in a non-default language response have translations.

### 4b. Via Database (D8+)

D8+ stores content translations in the entity data table. `node_field_data` has one row per node per language:

```sql
-- All translations for all nodes
SELECT nid, langcode, title, status, default_langcode, revision_translation_affected
FROM node_field_data
ORDER BY nid, langcode;
```

| Column | Meaning |
|---|---|
| `langcode` | Language of this row |
| `default_langcode` | `1` if this row is the original language, `0` if it is a translation |
| `revision_translation_affected` | `1` if this translation was changed in the current revision |

Field values follow the same pattern. Each field table (`node__field_body`, `node__field_tags`, etc.) has a `langcode` column:

```sql
-- Body field in all languages for node 123
SELECT entity_id, langcode, body_value, body_summary, body_format
FROM node__field_body
WHERE entity_id = 123
ORDER BY langcode;
```

To get a full translated node, join the data table with each field table, filtering by the target langcode:

```sql
SELECT nfd.nid, nfd.title, nfd.langcode, nfd.status,
       fb.body_value, fb.body_format
FROM node_field_data nfd
LEFT JOIN node__field_body fb
  ON fb.entity_id = nfd.nid AND fb.langcode = nfd.langcode
WHERE nfd.langcode = 'fr'
ORDER BY nfd.nid;
```

**Translation overview query** (which nodes have which translations):

```sql
SELECT nfd.nid, nfd.type,
  GROUP_CONCAT(DISTINCT nfd2.langcode ORDER BY nfd2.langcode) AS available_languages,
  (SELECT langcode FROM node_field_data
   WHERE nid = nfd.nid AND default_langcode = 1 LIMIT 1) AS source_language
FROM node_field_data nfd
JOIN node_field_data nfd2 ON nfd2.nid = nfd.nid
WHERE nfd.default_langcode = 1
GROUP BY nfd.nid, nfd.type
HAVING COUNT(DISTINCT nfd2.langcode) > 1
ORDER BY nfd.type, nfd.nid;
```

This returns every node that has more than one language, with a comma-separated list of available languages and the source language.

### 4c. Other Translatable Entity Types

The same table pattern applies to every translatable entity type:

| Entity type | Data table | Field table pattern |
|---|---|---|
| Nodes | `node_field_data` | `node__field_{name}` |
| Taxonomy terms | `taxonomy_term_field_data` | `taxonomy_term__field_{name}` |
| Media | `media_field_data` | `media__field_{name}` |
| Block content | `block_content_field_data` | `block_content__field_{name}` |
| Menu link content | `menu_link_content_data` | `menu_link_content__field_{name}` |
| Paragraphs | `paragraphs_item_field_data` | `paragraph__field_{name}` |

Query each with the same pattern: join the data table (filtered by `langcode`) with field tables (matched on `entity_id` and `langcode`).

### 4d. Translation Metadata

For each translated entity, capture:

```json
{
  "entity_type": "node",
  "bundle": "article",
  "id": 123,
  "uuid": "a1b2c3d4-...",
  "source_language": "en",
  "translations": {
    "en": {"status": "published", "title": "Hello World", "changed": "2024-01-15T10:00:00"},
    "fr": {"status": "published", "title": "Bonjour le monde", "changed": "2024-02-01T14:30:00"},
    "de": {"status": "draft", "title": "Hallo Welt", "changed": "2024-02-10T09:15:00"}
  }
}
```

Note the per-translation status. Drupal allows translations to have independent publish states. A node can be published in English, published in French, but still in draft in German.

---

## 5. Interface Translations (Locale Module)

Interface translations are UI strings: button labels, form text, status messages, error messages, module-provided strings. Anything wrapped in `t()` or `@Translation()` in Drupal code.

### 5a. Storage (D8+)

Two tables:

**`locales_source`** — one row per unique English source string:

| Column | Meaning |
|---|---|
| `lid` | String ID (auto-increment) |
| `source` | The English string. This is the key. |
| `context` | Context disambiguator. Same English string with different meanings gets different contexts. Empty string is the default context. |
| `version` | Drupal version that introduced this string |

**`locales_target`** — one row per translation of a source string:

| Column | Meaning |
|---|---|
| `lid` | References `locales_source.lid` |
| `translation` | The translated string |
| `language` | Target langcode |
| `customized` | `0` = community translation (imported from .po file), `1` = custom translation (edited on-site) |

```sql
-- Count interface translations per language
SELECT lt.language, COUNT(*) AS string_count,
  SUM(CASE WHEN lt.customized = 1 THEN 1 ELSE 0 END) AS custom_count
FROM locales_target lt
GROUP BY lt.language
ORDER BY lt.language;
```

The `custom_count` matters. Community translations can be re-imported from drupal.org PO files. Custom translations are site-specific and must be migrated.

### 5b. Exporting Interface Translations

**Via Drush (preferred):**

```bash
# Export all translations for French as a PO file
drush locale:export fr --types=customized > fr_custom.po
drush locale:export fr --types=not-customized > fr_community.po
drush locale:export fr > fr_all.po

# Export for every configured language
for lang in $(drush language:list --format=list); do
  if [ "$lang" != "en" ]; then
    drush locale:export "$lang" --types=customized > "${lang}_custom.po"
  fi
done
```

The `--types=customized` flag exports only site-specific overrides. This is the critical set for migration. Community translations can be re-imported on the target platform if it supports PO files.

**Via Database:**

```sql
-- Export all custom translations (the ones you must migrate)
SELECT ls.source, ls.context, lt.language, lt.translation
FROM locales_source ls
JOIN locales_target lt ON lt.lid = ls.lid
WHERE lt.customized = 1
ORDER BY lt.language, ls.source;
```

```sql
-- Export ALL translations (custom + community) for a specific language
SELECT ls.source, ls.context, lt.translation, lt.customized
FROM locales_source ls
JOIN locales_target lt ON lt.lid = ls.lid
WHERE lt.language = 'fr'
ORDER BY ls.source;
```

### 5c. PO File Format

PO (Portable Object) files are the standard gettext format. Every translation tool and most CMS platforms understand them.

```
# French translation
msgctxt "Long month name"
msgid "March"
msgstr "Mars"

msgid "Save"
msgstr "Enregistrer"

msgid "Are you sure you want to delete this item?"
msgstr "Voulez-vous vraiment supprimer cet élément ?"
```

| Directive | Meaning |
|---|---|
| `msgctxt` | Context. Only present when the source string has a non-empty context. |
| `msgid` | English source string. The lookup key. |
| `msgstr` | Translated string. |

Plural forms use `msgid_plural` and indexed `msgstr[0]`, `msgstr[1]`, etc.

### 5d. D7 Interface Translations

Same table structure. `locales_source` and `locales_target` exist in D7 with the same columns. The export method differs:

```bash
# D7 Drush (if l10n_update module is installed)
drush l10n-update-export fr > fr.po
```

Without the `l10n_update` module, export via database query (same SQL as D8+) or via the admin UI at `/admin/config/regional/translate/export`.

### 5e. What to Do with Interface Translations

For most target platforms, interface translations are irrelevant. The target has its own UI and its own translation system. But check for:

1. **Custom UI strings used as content.** Some sites store user-facing text as interface translations rather than content fields. Labels, callout text, banner headlines stored in `t()` calls in custom templates.
2. **Webform labels and messages.** If forms were built with translatable labels, those translations live in interface translation tables.
3. **Custom module strings.** Any custom module that uses `t('...')` with translatable strings has those translations in locale tables.

Export custom translations for review. The migration team decides which ones map to content in the target system.

---

## 6. Config Translations

Config translations are translated versions of configuration values. Site name in French. A View's exposed filter label in German. A metatag default in Spanish.

### 6a. Storage (D8+)

Config translations are stored as config overrides. The naming convention:

```
language.config.{langcode}.{original_config_name}
```

Example: the French translation of `system.site` (which contains site name and slogan) is stored as `language.config.fr.system.site`.

**Via Config YAML:**

```bash
ls config/sync/language.config.*.yml | head -20
```

```yaml
# language.config.fr.system.site.yml
langcode: fr
label: 'Mon site'
slogan: 'Un site Drupal'
```

Only the translated keys appear. Untranslated keys inherit from the original config.

**Via Database:**

```sql
SELECT name, data FROM config
WHERE name LIKE 'language.config.%'
ORDER BY name;
```

**Via Drush:**

```bash
# List all config translations
drush config:list --prefix=language.config --format=list

# Export a specific translation
drush config:get language.config.fr.system.site --format=yaml
```

### 6b. Common Translated Config Items

| Config name | What gets translated |
|---|---|
| `system.site` | Site name, slogan, 403/404 page paths |
| `system.maintenance` | Maintenance mode message |
| `field.field.{entity_type}.{bundle}.{field}` | Field labels and descriptions |
| `node.type.{bundle}` | Content type names and descriptions |
| `taxonomy.vocabulary.{vid}` | Vocabulary names and descriptions |
| `views.view.{view_id}` | View titles, exposed filter labels, empty text, header/footer content |
| `block.block.{block_id}` | Block labels |
| `metatag.metatag_defaults.{id}` | Default metatag values per entity type |
| `webform.webform.{id}` | Form labels, descriptions, confirmation messages |

### 6c. Bulk Export

```bash
# Export all config translations for one language
for config in $(drush config:list --prefix=language.config.fr --format=list); do
  filename=$(echo "$config" | sed 's/\//-/g')
  drush config:get "$config" --format=yaml > "config_translations/${filename}.yml"
done
```

Or export the entire config sync directory (which includes all `language.config.*` files):

```bash
drush config:export --destination=/tmp/config_export
ls /tmp/config_export/language.config.* | wc -l
```

### 6d. D7 Config-like Translations (i18n_string)

D7 does not have a config system. The `i18n_string` module translates "string objects" from various sources: menu names, vocabulary names, block titles, taxonomy term names, field labels.

Storage uses the same `locales_source` and `locales_target` tables as interface translations, but with structured `context` values and a separate tracking table:

```sql
-- i18n_string table maps string objects to locale IDs
SELECT textgroup, context, objectid, type, property, objectindex, lid
FROM i18n_string
ORDER BY textgroup, type;
```

| Column | Meaning |
|---|---|
| `textgroup` | Module that owns the string: `menu`, `taxonomy`, `blocks`, `field`, `node` |
| `context` | Full context path: `menu:item:123:title`, `taxonomy:term:456:name` |
| `objectid` | ID of the source object |
| `type` | Object type within the textgroup |
| `property` | Which property of the object: `title`, `name`, `description` |
| `lid` | Foreign key to `locales_source.lid` |

To get translations:

```sql
SELECT i.textgroup, i.type, i.objectid, i.property,
       ls.source AS original,
       lt.language, lt.translation
FROM i18n_string i
JOIN locales_source ls ON ls.lid = i.lid
JOIN locales_target lt ON lt.lid = i.lid
ORDER BY i.textgroup, i.type, lt.language;
```

Textgroup breakdown:

| Textgroup | What it translates |
|---|---|
| `menu` | Menu link titles and descriptions |
| `taxonomy` | Vocabulary names, term names, term descriptions |
| `blocks` | Block titles and body content |
| `field` | Field labels, descriptions, allowed values (list fields) |
| `node` | Content type names and descriptions |

---

## 7. Language-Specific Path Aliases

Drupal supports per-language URL aliases. The same node can have `/about-us` in English and `/a-propos` in French.

### 7a. D8+ Path Aliases

Path aliases are `path_alias` entities (D9+) or entries in the `url_alias` table (D8):

**D9+ (path_alias entity):**

```sql
SELECT pa.id, pa.path, pa.alias, pa.langcode, pa.status
FROM path_alias pa
WHERE pa.langcode != 'und'
ORDER BY pa.path, pa.langcode;
```

**D8 (url_alias table):**

```sql
SELECT pid, source, alias, langcode
FROM url_alias
WHERE langcode != 'und'
ORDER BY source, langcode;
```

| Value of langcode | Meaning |
|---|---|
| `und` | Language-neutral. This alias applies to all languages. |
| `en`, `fr`, etc. | Language-specific alias. Active only when that language is negotiated. |

A node with `langcode = 'und'` aliases has the same URL path in all languages. A node with per-language aliases gets different paths per language.

**Export:**

```bash
# D9+ via Drush
drush sql:query "SELECT id, path, alias, langcode FROM path_alias ORDER BY path, langcode" > path_aliases_by_language.tsv
```

### 7b. D7 Path Aliases

D7 uses the `url_alias` table:

```sql
SELECT pid, source, alias, language
FROM url_alias
ORDER BY source, language;
```

Note the column is named `language` in D7, not `langcode`.

A `language` value of empty string or `und` means language-neutral.

### 7c. Migration Impact

For SEO, the target platform must reproduce the same language-specific URL structure. Map each source path (with its langcode) to the target URL. Feed this into the redirect map from Skill 20.

---

## 8. Language-Specific Menu Links

Menu link content entities are translatable in D8+. Each menu link can have translated titles and descriptions.

### 8a. D8+

```sql
SELECT mlcd.id, mlcd.langcode, mlcd.title, mlcd.description,
       mlcd.menu_name, mlcd.link__uri, mlcd.default_langcode
FROM menu_link_content_data mlcd
ORDER BY mlcd.menu_name, mlcd.id, mlcd.langcode;
```

Links with `default_langcode = 0` are translations. Group by `id` to see all translations of a single link.

**Via JSON:API:**

```
GET /fr/jsonapi/menu_link_content/menu_link_content?page[limit]=50
```

Returns French translations of all menu link content entities.

### 8b. D7 (i18n_menu)

D7 menu link translations are handled by the `i18n_menu` module. Two methods:

**Method 1: Localized menu links** (translate the link title via i18n_string)

```sql
SELECT i.objectid AS mlid, lt.language, lt.translation AS title
FROM i18n_string i
JOIN locales_target lt ON lt.lid = i.lid
WHERE i.textgroup = 'menu'
  AND i.type = 'item'
  AND i.property = 'title'
ORDER BY i.objectid, lt.language;
```

**Method 2: Translation sets** (each language gets a different menu link pointing to different content)

```sql
SELECT ml.mlid, ml.menu_name, ml.link_title, ml.link_path, ml.language,
       ml.i18n_tsid
FROM menu_links ml
WHERE ml.i18n_tsid > 0
ORDER BY ml.i18n_tsid, ml.language;
```

`i18n_tsid` groups links that are translations of each other. Same concept as `tnid` for nodes.

---

## 9. D7 i18n Module Suite Reference

D7 multilingual relies on the `i18n` (Internationalization) contrib module suite. Each sub-module handles a different translation domain:

| Module | Purpose | D9+ equivalent |
|---|---|---|
| `i18n` | Base module, API, string translation framework | Core `locale` + `config_translation` |
| `i18n_string` | Translatable string objects (bridge to locale) | `config_translation` |
| `i18n_node` | Content translation coordination | Core `content_translation` |
| `i18n_taxonomy` | Taxonomy term and vocabulary translation | Core content translation for taxonomy |
| `i18n_menu` | Menu link translation | Core content translation for menu links |
| `i18n_block` | Block title and body translation | Core content translation for block content |
| `i18n_field` | Field label and allowed value translation | `config_translation` for field config |
| `i18n_variable` | Variable translation (site name, slogan) | `config_translation` for `system.site` |
| `i18n_contact` | Contact form category translation | `config_translation` for contact forms |
| `i18n_select` | Language selection filtering in admin lists | No equivalent needed |
| `i18n_redirect` | Language-aware redirects | Core language negotiation handles this |

### D7 Taxonomy Translation Models

D7 i18n_taxonomy supports three vocabulary modes. Check the vocabulary's `i18n_mode` variable:

```sql
SELECT v.vid, v.name, v.machine_name,
  (SELECT value FROM variable WHERE name = CONCAT('i18n_taxonomy_vocabulary_', v.machine_name))
    AS i18n_mode
FROM taxonomy_vocabulary v
ORDER BY v.vid;
```

Or more reliably, check the `i18n_mode` column if it exists on `taxonomy_vocabulary`:

```sql
DESCRIBE taxonomy_vocabulary;
-- If i18n_mode column exists:
SELECT vid, name, machine_name, i18n_mode FROM taxonomy_vocabulary;
```

| i18n_mode | Behavior |
|---|---|
| `0` (None) | No translation. Language-neutral terms. |
| `1` (Localize) | Single term, name translated via `i18n_string`. Same term ID across languages. |
| `2` (Translate) | Separate terms per language, linked by `i18n_tsid` (translation set ID). Different term IDs. |
| `4` (Fixed language) | Each term locked to one language. No translations. |

For mode 1 (Localize):

```sql
SELECT td.tid, td.name AS original_name, lt.language, lt.translation AS translated_name
FROM taxonomy_term_data td
JOIN i18n_string i ON i.objectid = CAST(td.tid AS CHAR)
  AND i.textgroup = 'taxonomy' AND i.type = 'term' AND i.property = 'name'
JOIN locales_target lt ON lt.lid = i.lid
ORDER BY td.tid, lt.language;
```

For mode 2 (Translate):

```sql
SELECT td.tid, td.name, td.language, td.i18n_tsid
FROM taxonomy_term_data td
WHERE td.i18n_tsid > 0
ORDER BY td.i18n_tsid, td.language;
```

---

## 10. Full Multilingual Export Procedure

### Step 1: Export language configuration

```bash
# Languages
drush language:list --format=json > languages.json

# Negotiation settings
drush config:get language.negotiation --format=yaml > language_negotiation.yml
drush config:get language.types --format=yaml > language_types.yml
```

### Step 2: Export content translation inventory

```sql
-- Per bundle: how many entities, how many translated, into which languages
SELECT
  nfd.type AS bundle,
  COUNT(DISTINCT nfd.nid) AS total_nodes,
  COUNT(DISTINCT CASE WHEN nfd.default_langcode = 0 THEN nfd.nid END) AS translated_nodes,
  GROUP_CONCAT(DISTINCT CASE WHEN nfd.default_langcode = 0 THEN nfd.langcode END) AS translation_languages
FROM node_field_data nfd
GROUP BY nfd.type
ORDER BY nfd.type;
```

### Step 3: Export translated content per language

For each non-default language, export all translated entities using the method from Section 4. JSON:API with `?filter[langcode]={lang}` is fastest for bulk. Database queries give the most control.

### Step 4: Export interface translations

```bash
for lang in $(drush language:list --format=list); do
  if [ "$lang" != "en" ]; then
    drush locale:export "$lang" --types=customized > "locale_custom_${lang}.po"
    drush locale:export "$lang" > "locale_all_${lang}.po"
  fi
done
```

### Step 5: Export config translations

```bash
drush config:export --destination=/tmp/config_full
mkdir -p config_translations
cp /tmp/config_full/language.config.*.yml config_translations/
```

### Step 6: Export language-specific path aliases

```bash
drush sql:query "
  SELECT pa.path, pa.alias, pa.langcode
  FROM path_alias pa
  ORDER BY pa.path, pa.langcode
" > path_aliases_multilingual.tsv
```

### Step 7: Export language-specific menu links

```bash
drush sql:query "
  SELECT mlcd.id, mlcd.menu_name, mlcd.title, mlcd.link__uri, mlcd.langcode, mlcd.default_langcode
  FROM menu_link_content_data mlcd
  ORDER BY mlcd.menu_name, mlcd.id, mlcd.langcode
" > menu_links_multilingual.tsv
```

---

## 11. Output Schema

Combine all multilingual data into a single export structure:

```json
{
  "languages": [
    {
      "langcode": "en",
      "label": "English",
      "direction": "ltr",
      "weight": 0,
      "is_default": true
    },
    {
      "langcode": "fr",
      "label": "French",
      "direction": "ltr",
      "weight": 1,
      "is_default": false
    }
  ],
  "negotiation": {
    "url_method": "path_prefix",
    "prefixes": {"en": "", "fr": "fr"},
    "detection_order": ["url", "browser", "selected"],
    "default_language": "en"
  },
  "translatable_bundles": [
    {
      "entity_type": "node",
      "bundle": "article",
      "default_langcode_policy": "site_default",
      "language_alterable": true,
      "translatable_fields": ["title", "body", "field_summary", "field_tags"]
    }
  ],
  "content_translation_summary": {
    "node": {
      "article": {"total": 500, "with_translations": 320, "languages": ["en", "fr", "de"]},
      "page": {"total": 50, "with_translations": 45, "languages": ["en", "fr"]}
    },
    "taxonomy_term": {
      "tags": {"total": 200, "with_translations": 180, "languages": ["en", "fr", "de"]}
    }
  },
  "interface_translations": {
    "fr": {"total_strings": 12500, "custom_strings": 340},
    "de": {"total_strings": 11800, "custom_strings": 120}
  },
  "config_translations": {
    "fr": ["system.site", "views.view.frontpage", "node.type.article"],
    "de": ["system.site", "views.view.frontpage"]
  },
  "path_aliases": {
    "language_specific_count": 640,
    "language_neutral_count": 200
  },
  "menu_translations": {
    "main": {"links": 12, "translated_links": 10, "languages": ["en", "fr"]},
    "footer": {"links": 6, "translated_links": 6, "languages": ["en", "fr", "de"]}
  },
  "d7_specific": {
    "translation_model": "entity_translation",
    "i18n_modules": ["i18n", "i18n_node", "i18n_taxonomy", "i18n_menu", "i18n_string"],
    "taxonomy_modes": {
      "tags": "localize",
      "categories": "translate"
    }
  }
}
```

### Validation Checks

After export, verify:

1. **Every translated node has a source language.** Orphan translations (no source) indicate data corruption.
2. **Translation counts match expectations.** If a site claims 95% translation coverage but the export shows 60%, investigate missing translations.
3. **Custom interface translations are captured.** Run `SELECT COUNT(*) FROM locales_target WHERE customized = 1` and compare against exported PO file line count.
4. **Path aliases exist for all translated content.** Nodes with translations but no language-specific alias will share a URL path across languages. This may or may not be correct depending on the site's URL strategy.
5. **Config translations cover critical items.** At minimum: site name, content type labels, vocabulary names, menu titles. Missing config translations are often overlooked during migration.

### Common Pitfalls

- **`und` (undefined) language content.** D7 sites that enabled multilingual late may have thousands of nodes with `language = 'und'`. These are language-neutral and cannot receive translations until assigned a language. The migration must decide: assign them to the default language, or keep them neutral.
- **Paragraph translations.** Paragraphs inherit their host entity's translation model. A translated node with untranslatable paragraph fields means the paragraph content is identical across all languages. Check `field.field.paragraph.{type}.{field}.yml` for `translatable: true` on paragraph sub-fields.
- **Asymmetric translations.** Drupal allows translations to differ structurally from the source. A French article can have three paragraphs while the English source has five. This is valid but complicates migration to platforms that assume 1:1 structural parity between translations.
- **Revision + translation interaction.** Each revision can affect only one translation. The `revision_translation_affected` flag marks which translation changed in each revision. If migrating revision history (Skill 27), track this per-translation.
- **Media translations.** Media entities can be translatable, but many sites leave media untranslated. The alt text and title on image fields are typically the only translated media fields. Verify: `SELECT COUNT(*) FROM media_field_data WHERE default_langcode = 0`.
