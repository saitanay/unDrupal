# Drupal GraphQL Patterns

The `drupal/graphql` module exposes Drupal content through a GraphQL API. Two major version lines exist with fundamentally different architectures. A third line (5.x) ships the same architecture as 4.x with minor PHP API changes.

## Module Versions

| Version | Architecture | Schema Generation | Status |
|---------|-------------|-------------------|--------|
| 3.x | Auto-generated schema from entity system | Automatic. Every content entity exposed by default. | Maintenance mode. Works with D9/D10/D11. Uses older `webonyx/graphql-php`. |
| 4.x | Composable/SDL schema. Developers define types, queries, resolvers. | Manual. Only what you wire up appears in the schema. | Stable. Works with D10.2+/D11. |
| 5.x | Same as 4.x with small PHP type API breaks. | Manual. Same as 4.x. | Stable. Released June 2025. Works with D10.4+/D11. |

v3 exposes everything. The schema contains Drupalisms: `entityLabel`, `entityBundle`, `fieldTags`, `taxonomyTermQuery`. Frontend developers unfamiliar with Drupal find this confusing.

v4/v5 expose nothing by default. The developer writes `.graphqls` schema files and PHP resolver code. The schema is clean and domain-specific. The tradeoff: more setup work.

There is no upgrade path from v3 to v4. They are separate architectures.

### Community Schema Generators for v4/v5

These contributed modules auto-generate schemas on top of v4/v5, reducing manual work:

| Module | Approach |
|--------|----------|
| `graphql_compose` | GUI-driven. Enable fields per entity type through admin UI. Clean schema, cursor pagination. Recommended by Octahedroid. |
| `graphql_core_schema` | Exposes schema similar to v3 but on the v4/v5 base. Configurable field exposure. Supports Paragraphs and Views. |
| `graphql_directives` | Declarative. Schema annotations like `@resolveProperty(path: "title.value")` replace PHP resolver code. |

## Detection

Check if GraphQL is available:

```bash
# Via Drush
drush pm:list --filter=graphql --format=table

# Via Composer (check version)
composer show drupal/graphql 2>/dev/null

# Check for community schema generators
composer show drupal/graphql_compose 2>/dev/null
composer show drupal/graphql_core_schema 2>/dev/null
```

The GraphQL endpoint is typically at `/graphql`. Some sites configure a different path at `/admin/config/graphql`.

The GraphiQL explorer lives at `/graphql/explorer` when the module is enabled.

## Schema Discovery

### Introspection Query

Run this against the endpoint to discover all types, fields, and relationships:

```graphql
{
  __schema {
    queryType { name }
    types {
      name
      kind
      fields {
        name
        type {
          name
          kind
          ofType { name kind }
        }
      }
    }
  }
}
```

Minimal introspection to list just the query root fields:

```graphql
{
  __type(name: "Query") {
    fields {
      name
      description
      args { name type { name kind } }
      type { name kind ofType { name kind } }
    }
  }
}
```

### Schema Export

```bash
# v4/v5: Export schema via contributed module graphql_export
drush config:export

# v5: Native drush command (if available)
drush graphql:dump <server_id>

# v3: Introspection utility in module code
# Drupal\graphql\GraphQL\Utility\Introspection::introspect($schema)
```

### Visual Exploration

- GraphiQL explorer: `/graphql/explorer` (ships with the module)
- GraphQL Voyager: third-party tool, paste introspection JSON to visualize relationships

## Common Query Patterns

### v3: Entity Queries (Auto-Schema)

v3 provides `nodeQuery`, `taxonomyTermQuery`, `mediaQuery`, `userQuery`, and `{entityType}ById` queries out of the box.

#### List Nodes by Type

```graphql
query {
  nodeQuery(
    filter: {
      conditions: [
        { field: "type", value: ["article"], operator: EQUAL }
        { field: "status", value: ["1"], operator: EQUAL }
      ]
    }
    limit: 50
    offset: 0
    sort: [
      { field: "created", direction: DESC }
    ]
  ) {
    count
    entities {
      ... on NodeArticle {
        nid
        uuid
        title
        body {
          value
          format
          summary
          processed
        }
        fieldImage {
          entity {
            ... on MediaImage {
              fieldMediaImage {
                url
                alt
                width
                height
              }
            }
          }
        }
        fieldTags {
          entity {
            ... on TaxonomyTermTags {
              tid
              name
            }
          }
        }
        entityCreated
        entityChanged
        entityPublished
        entityOwner { name }
        path { alias }
      }
    }
  }
}
```

#### Single Node by ID

```graphql
query {
  nodeById(id: "42") {
    entityLabel
    entityBundle
    entityUrl { path }
    ... on NodeArticle {
      title
      nid
      body { value processed }
      fieldTags {
        targetId
        entity {
          entityId
          entityBundle
          ... on TaxonomyTermTags {
            name
          }
        }
      }
    }
  }
}
```

#### Taxonomy Terms

```graphql
query {
  taxonomyTermQuery(
    filter: {
      conditions: [
        { field: "vid", value: ["tags"], operator: EQUAL }
      ]
    }
    limit: 100
  ) {
    count
    entities {
      ... on TaxonomyTermTags {
        tid
        name
        description { value }
        path { alias }
      }
    }
  }
}
```

#### Media

```graphql
query {
  mediaQuery(
    filter: {
      conditions: [
        { field: "bundle", value: ["image"], operator: EQUAL }
      ]
    }
    limit: 50
  ) {
    entities {
      ... on MediaImage {
        mid
        name
        fieldMediaImage {
          url
          alt
          width
          height
        }
      }
    }
  }
}
```

v3 also exposes image derivatives:

```graphql
fieldImage {
  small: derivative(style: THUMBNAIL) { url width height }
  medium: derivative(style: MEDIUM) { url width height }
  large: derivative(style: LARGE) { url width height }
}
```

#### Menu by Name

```graphql
query {
  menuByName(name: "main") {
    name
    description
    links {
      label
      description
      expanded
      url { path }
      links {
        label
        url { path }
        links {
          label
          url { path }
        }
      }
    }
  }
}
```

The `links` field nests recursively. Query as many levels deep as the menu requires.

#### Users

```graphql
query {
  userQuery(
    filter: {
      conditions: [
        { field: "status", value: ["1"], operator: EQUAL }
      ]
    }
    limit: 50
  ) {
    entities {
      ... on User {
        uid
        name
        mail
        created
      }
    }
  }
}
```

User fields are permission-restricted. Anonymous access returns limited data. `mail` requires `administer users` permission or the user viewing their own account.

### v4/v5: Composable Schema Queries

The schema depends on what developers exposed. Field names are clean and domain-specific. No Drupalisms.

#### Typical Article Query

```graphql
query Articles($offset: Int = 0, $limit: Int = 10) {
  articles(offset: $offset, limit: $limit) {
    total
    items {
      id
      title
      body
      image { url alt }
      tags { name }
      author { name }
      created
      path
    }
  }
}
```

#### Single Article

```graphql
query Article($id: Int!) {
  article(id: $id) {
    id
    title
    body
    image { url alt width height }
    tags { name }
    author { name }
    created
    path
  }
}
```

#### GraphQL Compose Patterns

Sites using `graphql_compose` follow a specific naming convention:

```graphql
# Single entity by ID
query {
  nodeArticle(id: "42") {
    ... on NodeArticle {
      id
      title
      image { url width height }
    }
  }
}

# Multiple entities with cursor pagination
query {
  nodeArticles(first: 10, after: "cursor_string") {
    nodes {
      ... on NodeArticle {
        id
        title
      }
    }
    edges {
      cursor
      node {
        ... on NodeArticle { id title }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

#### GraphQL Core Schema Patterns

Sites using `graphql_core_schema` use a unified `entityQuery`:

```graphql
query {
  entityQuery(
    entityType: NODE
    filter: { conditions: [{ field: "type", value: "article" }] }
  ) {
    items {
      id
      label
      ... on NodeArticle {
        body
        fieldTags { label }
      }
    }
  }
}
```

Menu queries:

```graphql
query {
  menuByName(name: MAIN) {
    links {
      link { label url { path } }
      subtree {
        link { label url { path } }
      }
    }
  }
}
```

## Pagination

### v3: Offset-Based

```graphql
nodeQuery(limit: 50, offset: 0) {
  count      # Total matching entities
  entities { ... }
}
```

Parameters:
- `limit`: Number of results per page (check site's max; default varies)
- `offset`: Number of items to skip

Always fetch `count` first to know total pages.

Pagination loop pseudocode:

```python
offset = 0
limit = 50
total = None

while total is None or offset < total:
    result = graphql_query(node_query, variables={"limit": limit, "offset": offset})
    total = result["data"]["nodeQuery"]["count"]
    entities = result["data"]["nodeQuery"]["entities"]
    for entity in entities:
        process(entity)
    offset += limit
```

### v4/v5: Depends on Implementation

**Offset-based** (common in custom schemas):

```graphql
articles(offset: 0, limit: 50) {
  total
  items { ... }
}
```

**Cursor-based** (common in `graphql_compose`):

```graphql
nodeArticles(first: 50, after: "cursor_value") {
  pageInfo {
    hasNextPage
    endCursor
  }
  edges {
    cursor
    node { ... }
  }
}
```

Cursor pagination loop:

```python
cursor = None
has_next = True

while has_next:
    variables = {"first": 50}
    if cursor:
        variables["after"] = cursor
    result = graphql_query(query, variables=variables)
    connection = result["data"]["nodeArticles"]
    for edge in connection["edges"]:
        process(edge["node"])
    has_next = connection["pageInfo"]["hasNextPage"]
    cursor = connection["pageInfo"]["endCursor"]
```

## Filtering and Sorting

### v3 Filter Syntax

Filters mirror Drupal's EntityQuery API.

#### Conditions

```graphql
filter: {
  conditions: [
    { field: "type", value: ["article"], operator: EQUAL }
    { field: "status", value: ["1"], operator: EQUAL }
  ]
}
```

Without a conjunction, multiple conditions combine with AND.

#### Available Operators

| Operator | Description |
|----------|-------------|
| `EQUAL` | Exact match (default) |
| `NOT_EQUAL` | Not equal |
| `SMALLER_THAN` | Less than |
| `SMALLER_THAN_OR_EQUAL` | Less than or equal |
| `GREATER_THAN` | Greater than |
| `GREATER_THAN_OR_EQUAL` | Greater than or equal |
| `IN` | Value in list |
| `NOT_IN` | Value not in list |
| `LIKE` | Pattern match (use `%` wildcard) |
| `NOT_LIKE` | Negative pattern match |
| `BETWEEN` | Range (two-element value) |
| `NOT_BETWEEN` | Outside range |
| `IS_NULL` | Field is null |
| `IS_NOT_NULL` | Field is not null |

#### Conjunctions (OR Logic)

```graphql
filter: {
  conjunction: OR
  conditions: [
    { field: "type", value: ["article"], operator: EQUAL }
    { field: "type", value: ["page"], operator: EQUAL }
  ]
}
```

#### Groups (Complex Logic)

Combine AND and OR:

```graphql
filter: {
  conjunction: AND
  groups: [
    {
      conjunction: OR
      conditions: [
        { field: "type", value: ["article"], operator: EQUAL }
        { field: "type", value: ["page"], operator: EQUAL }
      ]
    }
    {
      conditions: [
        { field: "status", value: ["1"], operator: EQUAL }
      ]
    }
  ]
}
```

This returns: (type = article OR type = page) AND (status = 1).

#### Filtering on Entity Reference Fields

Use dot notation to traverse references:

```graphql
filter: {
  conditions: [
    { field: "type", value: ["article"], operator: EQUAL }
    { field: "field_author.entity.uid", value: ["5"], operator: EQUAL }
    { field: "field_tags.entity.name", value: ["migration"], operator: EQUAL }
  ]
}
```

For taxonomy term references use `.entity.tid`. For node references use `.entity.nid`.

#### Sorting

```graphql
nodeQuery(
  sort: [
    { field: "sticky", direction: DESC }
    { field: "created", direction: DESC }
  ]
  ...
)
```

### v4/v5 Filtering

Depends on the schema design. Common patterns:

```graphql
# Custom filter arguments
articles(type: "tutorial", status: PUBLISHED, limit: 10) { ... }

# Input object filters
articles(filter: { category: "news", dateFrom: "2024-01-01" }) { ... }

# Enum-based filters
articles(sortBy: CREATED_DESC, status: PUBLISHED) { ... }
```

Introspect the schema to discover what filters are available. There is no universal pattern for v4/v5 filters.

## Resolving Related Entities

GraphQL resolves relationships in a single request. This is the primary advantage over JSON:API for deeply nested data. No include depth limits. Query as deep as the schema allows.

### v3: Inline Fragment Resolution

Entity reference fields return the referenced entity via `entity`:

```graphql
... on NodeArticle {
  title
  fieldAuthor {
    entity {
      ... on User {
        name
        mail
      }
    }
  }
  fieldCategory {
    entity {
      ... on TaxonomyTermCategory {
        name
        parent {
          entity {
            ... on TaxonomyTermCategory { name }
          }
        }
      }
    }
  }
}
```

### Paragraph Resolution

Paragraphs are accessed through their parent entity's reference field, not queried directly. Each paragraph type gets a typed fragment.

#### v3: Paragraphs

```graphql
... on NodeLandingPage {
  fieldContent {
    entity {
      ... on ParagraphHeroBanner {
        fieldTitle
        fieldSubtitle
        fieldBackground {
          entity {
            ... on MediaImage {
              fieldMediaImage { url alt width height }
            }
          }
        }
      }
      ... on ParagraphTextBlock {
        fieldBody { value processed }
      }
      ... on ParagraphCardGroup {
        fieldCards {
          entity {
            ... on ParagraphCard {
              fieldTitle
              fieldBody { value }
              fieldLink { url title }
              fieldImage {
                entity {
                  ... on MediaImage {
                    fieldMediaImage { url alt }
                  }
                }
              }
            }
          }
        }
      }
      ... on ParagraphAccordion {
        fieldItems {
          entity {
            ... on ParagraphAccordionItem {
              fieldTitle
              fieldBody { value processed }
            }
          }
        }
      }
    }
  }
}
```

#### v4/v5: Paragraphs

The schema defines paragraph types as interfaces or unions. The query is cleaner but the structure depends on how the developer built the resolvers.

```graphql
# With interface-based paragraph types
query {
  landingPage(id: 1) {
    components {
      ... on HeroBanner {
        title
        subtitle
        backgroundImage { url alt }
      }
      ... on TextBlock {
        body
      }
      ... on CardGroup {
        cards {
          ... on Card {
            title
            body
            link { url label }
            image { url alt }
          }
        }
      }
    }
  }
}
```

#### GraphQL Compose: Paragraphs

```graphql
query {
  nodeArticle(id: "1") {
    ... on NodeArticle {
      components {
        ... on ParagraphRichText {
          __typename
          name
          description { value }
        }
        ... on ParagraphImage {
          __typename
          image { url alt width height }
        }
      }
    }
  }
}
```

Use `__typename` to identify paragraph types in the response for frontend component mapping.

## Authentication

GraphQL requests respect Drupal's access control. The endpoint returns only data the authenticated user can access.

| Method | Setup | Header/Mechanism |
|--------|-------|-----------------|
| Cookie session | Default. Same session as browser login. | `Cookie: SESS...=...` |
| Basic auth | Enable `basic_auth` module. | `Authorization: Basic base64(user:pass)` |
| OAuth 2.0 | Install `simple_oauth` module. | `Authorization: Bearer <token>` |
| API key | Custom module or `key_auth`. | Custom header, e.g. `api-key: <key>` |

For migration scripts, OAuth 2.0 with a service account is the cleanest approach. Basic auth works for quick extraction. Cookie auth works if you can maintain a session.

### Authentication Example

```python
import requests

# Basic auth
response = requests.post(
    f"{base_url}/graphql",
    json={"query": query},
    auth=("username", "password"),
    headers={"Content-Type": "application/json"}
)

# OAuth bearer token
response = requests.post(
    f"{base_url}/graphql",
    json={"query": query},
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}"
    }
)
```

## GraphQL vs JSON:API: When to Use Which

### Prefer GraphQL When

- The site already has a GraphQL schema built for a decoupled frontend. The data shape is already optimized. Use it.
- Content uses deep paragraph nesting. A single GraphQL query resolves the full tree. JSON:API requires multiple requests or deep include chains that hit depth limits.
- Custom resolvers compute or transform data server-side. This captures business logic that raw entity export misses.
- Virtual fields or computed properties are exposed only through GraphQL.
- You need specific fields from many related entities. GraphQL returns only the fields you ask for.

### Prefer JSON:API When

- v4/v5 schema may not expose all entity types or fields. The developer chose what to include. If your target content is missing from the GraphQL schema, JSON:API exposes everything.
- JSON:API is core (D9+). It works with zero configuration on any Drupal 9/10/11 site.
- JSON:API filters are predictable. They map to the entity query API directly. v4/v5 GraphQL filters depend on whatever the developer implemented.
- You need bulk export of all content types. JSON:API resource discovery (`GET /jsonapi`) lists every entity type. GraphQL v4/v5 may only expose a subset.
- The GraphQL module is not installed.

### Use Both

Nothing prevents using both. Run the audit (skill 01), check what each API exposes, and pick the access method per content type based on coverage and depth.

## Rate Limits and Performance

GraphQL has no built-in rate limiting in Drupal. Limits come from the web server or hosting platform.

Considerations:
- Large queries with deep nesting can be expensive. The server resolves every field for every entity in a single request.
- Some sites limit query complexity or depth via the `graphql` module's server configuration.
- Persisted queries (if configured) restrict which queries the endpoint accepts. You may not be able to run arbitrary introspection or custom queries.
- Batch multiple queries in a single HTTP request if the server supports it.

## Querying Different Entity Types: Quick Reference

### v3 Query Map

| Entity Type | List Query | Single Query | Notes |
|-------------|-----------|--------------|-------|
| Node | `nodeQuery(filter, limit, offset, sort)` | `nodeById(id)` | Filter by `type` for specific bundles |
| Taxonomy term | `taxonomyTermQuery(filter, limit, offset)` | `taxonomyTermById(id)` | Filter by `vid` for specific vocabularies |
| Media | `mediaQuery(filter, limit, offset)` | `mediaById(id)` | Resolve through to file URL via `fieldMediaImage`, `fieldMediaFile`, etc. |
| User | `userQuery(filter, limit, offset)` | `userById(id)` | Permission-restricted. Anonymous gets limited fields. |
| File | `fileQuery(filter, limit, offset)` | `fileById(id)` | Raw file entities. Usually accessed through media. |
| Menu | `menuByName(name)` | N/A | Returns nested link tree |
| Paragraph | N/A | N/A | Not queried directly. Accessed through parent entity's paragraph reference field. |
| Block content | `blockContentQuery(filter, limit, offset)` | `blockContentById(id)` | Custom block entities |

### v4/v5 Query Map

No standard queries. Everything depends on the schema. Run introspection to discover available queries:

```graphql
{
  __type(name: "Query") {
    fields { name args { name type { name } } }
  }
}
```

## Integration with Migration Skills

When auditing a Drupal site (skill 01):

1. Check if `drupal/graphql` is installed: `composer show drupal/graphql` or `drush pm:list --filter=graphql`.
2. Check the version to determine v3 vs v4/v5 behavior.
3. Check for community generators: `composer show drupal/graphql_compose`, `composer show drupal/graphql_core_schema`.
4. Hit the GraphQL endpoint with an introspection query to map the full schema.
5. Compare available types/fields against JSON:API resource discovery to find gaps in either direction.
6. For each content type, pick the access method that provides the most complete data with the least complexity.

If both APIs expose the same content, prefer whichever gives you:
- All fields you need (check for computed/virtual fields only in one API)
- Paragraph resolution depth you require
- Cleaner data shape for the target format
