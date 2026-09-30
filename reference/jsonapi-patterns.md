# Drupal JSON:API Patterns

Drupal core ships with a JSON:API module (stable since D8.7). It exposes all content entities as RESTful resources following the {json:api} specification.

## Base URL Pattern

```
/jsonapi/{entity_type}/{bundle}
```

Examples:

```
/jsonapi/node/article
/jsonapi/node/page
/jsonapi/taxonomy_term/tags
/jsonapi/media/image
/jsonapi/user/user
/jsonapi/paragraph/hero
/jsonapi/block_content/basic
/jsonapi/menu_link_content/menu_link_content
/jsonapi/comment/comment
/jsonapi/file/file
```

The bundle name uses the machine name. For entity types where the bundle matches the entity type (users, files), the bundle repeats: `/jsonapi/user/user`.

### Single Resource

```
/jsonapi/node/article/{uuid}
```

JSON:API uses UUIDs, not entity IDs.

### Resource Discovery

```
GET /jsonapi
```

Returns a list of all available resource types with their URLs.

## Pagination

```
?page[limit]=50              -- Items per page (max varies, default 50)
?page[offset]=100            -- Skip this many items
```

Response includes pagination links:

```json
{
  "links": {
    "self": "/jsonapi/node/article?page[limit]=50&page[offset]=0",
    "next": "/jsonapi/node/article?page[limit]=50&page[offset]=50",
    "last": "/jsonapi/node/article?page[limit]=50&page[offset]=950"
  },
  "meta": {
    "count": 1000
  }
}
```

The default maximum page size is 50. The `jsonapi_page_limit` module or custom configuration can change this. Some sites cap it lower.

To iterate all resources:

```python
url = "/jsonapi/node/article?page[limit]=50"
while url:
    response = requests.get(base + url, headers=headers)
    data = response.json()
    for item in data['data']:
        process(item)
    url = data.get('links', {}).get('next', {})
    if isinstance(url, dict):
        url = url.get('href')
```

## Filtering

### Simple Filter

```
?filter[status]=1
?filter[field_category.id]={uuid}
```

### Condition Filter (explicit operator)

```
?filter[title-filter][condition][path]=title
&filter[title-filter][condition][operator]=CONTAINS
&filter[title-filter][condition][value]=migration
```

### Available Operators

| Operator | SQL Equivalent | Notes |
|----------|---------------|-------|
| `=` | `=` | Default if omitted |
| `<>` | `!=` | Not equal |
| `>` | `>` | Greater than |
| `>=` | `>=` | Greater than or equal |
| `<` | `<` | Less than |
| `<=` | `<=` | Less than or equal |
| `STARTS_WITH` | `LIKE 'x%'` | |
| `CONTAINS` | `LIKE '%x%'` | |
| `ENDS_WITH` | `LIKE '%x'` | |
| `IN` | `IN (...)` | Value must be array |
| `NOT IN` | `NOT IN (...)` | Value must be array |
| `BETWEEN` | `BETWEEN x AND y` | Value must be two-element array |
| `IS NULL` | `IS NULL` | No value needed |
| `IS NOT NULL` | `IS NOT NULL` | No value needed |

### IN Operator Example

```
?filter[type-filter][condition][path]=field_type
&filter[type-filter][condition][operator]=IN
&filter[type-filter][condition][value][0]=article
&filter[type-filter][condition][value][1]=page
```

### Filter Groups (AND/OR)

```
?filter[and-group][group][conjunction]=AND
&filter[published][condition][path]=status
&filter[published][condition][value]=1
&filter[published][condition][memberOf]=and-group
&filter[recent][condition][path]=created
&filter[recent][condition][operator]=>=
&filter[recent][condition][value]=1704067200
&filter[recent][condition][memberOf]=and-group
```

### Filtering on Related Entities

Dot notation traverses relationships:

```
# Nodes where the referenced taxonomy term name is "News"
?filter[field_category.name]=News

# Nodes where the author's email contains "example.com"
?filter[uid.mail][condition][operator]=CONTAINS
&filter[uid.mail][condition][value]=example.com
```

## Includes (Relationship Loading)

```
?include=field_image,field_category,uid
```

Included resources appear in the `included` array of the response. This avoids N+1 requests.

### Nested Includes

```
?include=field_content_blocks,field_content_blocks.field_image
```

Dot notation walks through references. For paragraphs, this loads the paragraph entities and their referenced media in one request.

### Deep Nesting

```
?include=field_content_blocks,field_content_blocks.field_cards,field_content_blocks.field_cards.field_image
```

Default include depth limit is 5 levels. The `jsonapi_include_limit` setting controls this.

## Sparse Fieldsets

Reduce response size by requesting only specific fields:

```
?fields[node--article]=title,created,field_image,field_category
&fields[taxonomy_term--tags]=name
&fields[file--file]=uri,filename
```

Format: `fields[{entity_type}--{bundle}]=field1,field2`

Note the double-dash separator between entity type and bundle.

## Sorting

```
?sort=created                  -- Ascending
?sort=-created                 -- Descending (prefix with -)
?sort=-sticky,created          -- Multiple sort criteria
```

### Sort with explicit direction

```
?sort[sort-created][path]=created
&sort[sort-created][direction]=DESC
```

## Authentication

### Cookie Authentication

Use session cookie from a Drupal login. Include CSRF token for write operations.

```
# Get session cookie
POST /user/login?_format=json
Content-Type: application/json
{"name": "admin", "pass": "password"}

# Get CSRF token
GET /session/token
```

### Basic Auth

```
Authorization: Basic base64(username:password)
```

Requires the `basic_auth` module.

### OAuth 2.0

Requires the `simple_oauth` contrib module.

```
# Get access token
POST /oauth/token
Content-Type: application/x-www-form-urlencoded
grant_type=password&client_id=...&client_secret=...&username=...&password=...

# Use token
Authorization: Bearer {access_token}
```

### API Key

Some sites use the `key_auth` or `api_key` module:

```
?api-key={key}
# or
X-API-Key: {key}
```

## Write Operations

### Create

```
POST /jsonapi/node/article
Content-Type: application/vnd.api+json

{
  "data": {
    "type": "node--article",
    "attributes": {
      "title": "New Article",
      "body": {
        "value": "<p>Content here</p>",
        "format": "full_html"
      }
    },
    "relationships": {
      "field_category": {
        "data": {
          "type": "taxonomy_term--tags",
          "id": "uuid-of-term"
        }
      }
    }
  }
}
```

### Update (PATCH)

```
PATCH /jsonapi/node/article/{uuid}
Content-Type: application/vnd.api+json

{
  "data": {
    "type": "node--article",
    "id": "{uuid}",
    "attributes": {
      "title": "Updated Title"
    }
  }
}
```

### Delete

```
DELETE /jsonapi/node/article/{uuid}
```

## File and Image Uploads

JSON:API supports binary file uploads:

```
POST /jsonapi/node/article/{uuid}/field_image
Content-Type: application/octet-stream
Content-Disposition: file; filename="photo.jpg"

{binary file content}
```

## Common Gotchas

### 1. Include Depth Limits

Deep paragraph structures hit the default 5-level include limit. You get the reference but not the included data. Increase via settings or make separate requests for deeply nested content.

### 2. Permission Restrictions

JSON:API respects Drupal's entity access system. Anonymous users see only published content. Fields with restricted view permissions are omitted from responses. The `jsonapi_include_existing_access` permission controls whether 403 responses include the entity data.

### 3. Max Page Size

The default max is 50. Requesting `page[limit]=999` silently caps at 50 (or whatever the configured max is). Watch the response `meta.count` and paginate.

### 4. Disabled Resources

Site admins can disable specific resource types. If you get 404 on a resource type that should exist, check `/jsonapi` for the available list.

### 5. Read-Only Mode

By default since D9, JSON:API runs in read-only mode. Write operations return 405 unless the site explicitly sets:

```php
// settings.php
$settings['jsonapi_read_only'] = FALSE;
```

Or the `jsonapi_extras` module is configured to allow writes.

### 6. Decoupled Menus

Menu links require the `jsonapi_menu_items` contrib module. Core JSON:API exposes `menu_link_content` entities but not the computed menu tree.

### 7. Revision Access

JSON:API does not expose revisions by default. The `jsonapi_resources` contrib module adds custom revision endpoints.

### 8. JSON:API Extras

The `jsonapi_extras` module allows:
- Renaming resource types (e.g., `node--article` to `articles`)
- Disabling specific resources or fields
- Overriding resource paths
- Custom aliasing

If resource types don't match expected names, check for `jsonapi_extras` configuration.

### 9. Subrequests

The `subrequests` module (core experimental) allows batching multiple JSON:API requests into one HTTP request. Useful for reducing round trips.

```
POST /subrequests?_format=json
Content-Type: application/json

[
  {"uri": "/jsonapi/node/article?page[limit]=50", "requestId": "articles", "action": "view"},
  {"uri": "/jsonapi/taxonomy_term/tags", "requestId": "tags", "action": "view"}
]
```

## Useful Extraction Patterns

### Dump All Content of a Type

```bash
#!/bin/bash
BASE="https://example.com"
TYPE="node/article"
URL="/jsonapi/${TYPE}?page[limit]=50&include=field_image,field_category"
while [ -n "$URL" ]; do
  RESPONSE=$(curl -s "${BASE}${URL}")
  echo "$RESPONSE" >> output.jsonl
  URL=$(echo "$RESPONSE" | jq -r '.links.next.href // empty')
  # Strip base URL if absolute
  URL="${URL#$BASE}"
done
```

### Get All Taxonomy Terms with Hierarchy

```
GET /jsonapi/taxonomy_term/tags?include=parent&fields[taxonomy_term--tags]=name,parent,weight&page[limit]=50
```

### Get Full Node with Paragraphs

```
GET /jsonapi/node/article/{uuid}?include=field_content_blocks,field_content_blocks.field_image,field_content_blocks.field_cards,field_content_blocks.field_cards.field_image
```
