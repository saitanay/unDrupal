# Skill 25: Custom and Contrib Entity Types

Export entity types created by contrib modules (ECK, Profile, Group, Flag, Message, Advanced Queue) and bespoke custom modules. These entities sit outside the node/media/taxonomy/user/paragraph set covered by other skills. Every site of moderate complexity has at least one.

Run Skill 01 (Site Audit) and Skill 03 (Module Inventory) first. You need the Drupal version, enabled modules, and available access methods.

---

## Why These Get Missed

Migration plans focus on nodes, users, and media. Custom entity types hide in plain sight. They have their own base tables, field tables, and revision tables. They do not show up in node counts. A site audit that counts nodes and calls it done will miss every entity type in this skill.

The damage shows up late. You launch the new site and discover that user profiles lost their certification records, group memberships vanished, or a custom booking entity with 40,000 rows was never exported.

---

## Discovery: Find Every Entity Type on the Site

Before exporting anything, build a complete list of entity types. Drupal's entity type system registers every content entity and config entity in a central registry.

### Via Drush

```bash
# List all entity types with their class, provider module, and base table
drush php:eval "
  \$definitions = \Drupal::entityTypeManager()->getDefinitions();
  foreach (\$definitions as \$id => \$def) {
    if (\$def instanceof \Drupal\Core\Entity\ContentEntityTypeInterface) {
      printf(\"%-30s %-40s %-20s %s\n\",
        \$id,
        \$def->getBaseTable() ?: '(no base table)',
        \$def->getProvider(),
        \$def->getClass()
      );
    }
  }
"
```

Core content entity types you can ignore (covered by other skills): `node`, `user`, `file`, `media`, `taxonomy_term`, `comment`, `paragraph`, `block_content`, `menu_link_content`, `path_alias`, `redirect`, `shortcut`, `contact_message`.

Everything else in that list needs this skill.

### Via Database

Query the key_value store where Drupal persists installed entity type definitions:

```sql
-- All installed entity type definitions
SELECT name, SUBSTRING(CAST(value AS CHAR), 1, 200) AS definition_preview
FROM key_value
WHERE collection = 'entity.definitions.installed'
ORDER BY name;
```

The `name` column is the entity type ID. The `value` column is a PHP-serialized object. Look for names that are not in the core list above.

### Via Table Pattern Matching

Content entities follow a predictable table naming pattern. Scan for tables that look like entity base tables:

```sql
-- Find tables that follow the {entity_type}_field_data pattern
SELECT REPLACE(table_name, '_field_data', '') AS probable_entity_type
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE '%_field_data'
ORDER BY table_name;
```

Cross-reference with the core entity type list. Anything left is a custom or contrib entity type.

### Via Custom Module Code

Scan for `@ContentEntityType` annotations (D8/D9) or `#[ContentEntityType]` attributes (D10+) in custom module code:

```bash
# Annotation style (D8/D9/D10)
grep -rn '@ContentEntityType' modules/custom/ --include='*.php'

# Attribute style (D10+)
grep -rn '#\[ContentEntityType' modules/custom/ --include='*.php'
```

Each match points to a PHP class that defines a custom entity type. The annotation contains the entity type ID, base table, field table, data table, and revision tables.

### Via Config Export

```bash
# ECK entity types
ls config/sync/eck.eck_entity_type.*.yml 2>/dev/null

# Profile types
ls config/sync/profile.type.*.yml 2>/dev/null

# Group types (Group 1.x)
ls config/sync/group.type.*.yml 2>/dev/null

# Group types (Group 2.x/3.x)
ls config/sync/group_type.group_type.*.yml 2>/dev/null

# Flag types
ls config/sync/flag.flag.*.yml 2>/dev/null

# Message types
ls config/sync/message.template.*.yml 2>/dev/null
```

---

## 1. ECK Entities (Entity Construction Kit)

ECK lets site builders create custom entity types through the admin UI without writing code. Each ECK entity type gets its own base table, data table, and optional revision tables. Fields attach to ECK bundles the same way they attach to node bundles.

### Config Structure

Each ECK entity type is a config entity stored in `eck.eck_entity_type.{type}.yml`:

```yaml
# Example: eck.eck_entity_type.event_registration.yml
langcode: en
status: true
id: event_registration
label: Event Registration
created: true       # Entity has a 'created' base field
changed: true       # Entity has a 'changed' base field
uid: true           # Entity has an author (uid) base field
title: true         # Entity has a title base field
status: true        # Entity has a published/unpublished status field
```

Each boolean flag controls whether that base field exists on the entity type. ECK entities are modular: a site builder can create an entity type with just an ID and no other base fields.

Bundles for ECK entity types are stored as separate config:

```yaml
# eck.eck_entity_bundle.event_registration.workshop.yml
langcode: en
status: true
type: event_registration
name: workshop
description: 'Workshop registration'
```

### Database Tables

ECK creates tables following this pattern:

| Table | Purpose |
|---|---|
| `eck_{type}` | Base table. Contains `id`, `uuid`, `type` (bundle). Optionally: `title`, `uid`, `created`, `changed`, `status`, depending on config flags. |
| `eck_{type}_field_data` | Field data table. Stores translatable base field values. Only exists if the entity type is translatable. |
| `eck_{type}_field_revision` | Revision field data. Only exists if revisions are enabled. |
| `eck_{type}_revision` | Revision base table. Only exists if revisions are enabled. |
| `eck_{type}__{field_name}` | Per-field value tables. Same structure as node field tables. |

### Export: Entity Type Definitions

```bash
# List all ECK entity types
drush php:eval "
  \$types = \Drupal::entityTypeManager()->getStorage('eck_entity_type')->loadMultiple();
  foreach (\$types as \$type) {
    echo \$type->id() . ' | ' . \$type->label() . PHP_EOL;
  }
"
```

```sql
-- Config table approach
SELECT name, data FROM config
WHERE name LIKE 'eck.eck_entity_type.%'
ORDER BY name;

-- Bundle definitions
SELECT name, data FROM config
WHERE name LIKE 'eck.eck_entity_bundle.%'
ORDER BY name;
```

### Export: Entity Data

Replace `{eck_type}` with the actual ECK entity type machine name.

```sql
-- Base entity data
SELECT * FROM eck_{eck_type}
ORDER BY id;

-- If the entity type has field_data table
SELECT * FROM eck_{eck_type}_field_data
ORDER BY id;

-- Count per bundle
SELECT type, COUNT(*) AS total
FROM eck_{eck_type}
GROUP BY type
ORDER BY total DESC;
```

### Export: Field Values

ECK field tables follow the same pattern as node field tables:

```sql
-- List all field tables for an ECK entity type
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'eck_{eck_type}__%'
  AND table_name NOT LIKE '%_revision__%'
ORDER BY table_name;
```

Export each field table. The columns match the standard Drupal field table structure: `entity_id`, `revision_id`, `bundle`, `delta`, `langcode`, and the field-specific value columns.

### JSON:API

ECK entities are exposed through JSON:API if the `jsonapi` module is enabled. The resource type follows the pattern `{entity_type}--{bundle}`:

```bash
# List event_registration entities of bundle 'workshop'
curl -s 'https://example.com/jsonapi/event_registration/workshop' \
  -H 'Authorization: Bearer {token}' | python3 -m json.tool
```

Check `/jsonapi` for the full resource list. ECK types appear alongside core types.

---

## 2. Profile Entities (Profile Module)

The Profile module creates a `profile` entity type with one or more bundles (profile types). Each user can have one profile per type (or multiple, if the type allows). Profiles hold structured data that belongs to a user but does not fit in user fields: billing addresses, professional certifications, company details, preferences.

### Config Structure

```yaml
# profile.type.customer.yml
langcode: en
status: true
id: customer
label: 'Customer profile'
display_label: 'Customer information'
multiple: false        # true = user can have multiple profiles of this type
registration: false    # true = profile form shown during user registration
roles: {  }            # Restrict which roles can have this profile type
```

### Database Tables

| Table | Purpose |
|---|---|
| `profile` | Base table: `profile_id`, `uuid`, `revision_id`, `type` (bundle), `uid`, `status`, `is_default` |
| `profile_field_data` | Translatable fields: `profile_id`, `uid`, `type`, `status`, `is_default`, `created`, `changed`, `langcode` |
| `profile_revision` | Revision base table (if revisions enabled) |
| `profile_revision__field_{name}` | Revision field data |
| `profile__field_{name}` | Per-field value tables, same structure as node field tables |

### Export: Profile Type Definitions

```sql
SELECT name, data FROM config
WHERE name LIKE 'profile.type.%'
ORDER BY name;
```

```bash
drush php:eval "
  \$types = \Drupal::entityTypeManager()->getStorage('profile_type')->loadMultiple();
  foreach (\$types as \$type) {
    printf(\"%-20s %-30s multiple=%s registration=%s\n\",
      \$type->id(),
      \$type->label(),
      \$type->allowsMultiple() ? 'yes' : 'no',
      \$type->getRegistration() ? 'yes' : 'no'
    );
  }
"
```

### Export: Profile Data

```sql
-- All profiles with their user association
SELECT
  p.profile_id,
  p.uuid,
  pfd.type,
  pfd.uid,
  pfd.status,
  pfd.is_default,
  pfd.created,
  pfd.changed
FROM profile p
JOIN profile_field_data pfd ON p.profile_id = pfd.profile_id
WHERE pfd.default_langcode = 1
ORDER BY pfd.uid, pfd.type;

-- Count per profile type
SELECT type, COUNT(*) AS total
FROM profile_field_data
WHERE default_langcode = 1
GROUP BY type
ORDER BY total DESC;
```

### Export: Profile Fields

```sql
-- List all profile field tables
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'profile__%'
  AND table_name NOT LIKE 'profile_revision%'
  AND table_name NOT LIKE 'profile_field_data'
ORDER BY table_name;
```

### Linking Profiles to Users

Every profile row has a `uid` column. The join to the user table is direct:

```sql
SELECT
  pfd.profile_id,
  pfd.type AS profile_type,
  pfd.uid,
  ufd.name AS username,
  ufd.mail AS email
FROM profile_field_data pfd
JOIN users_field_data ufd ON pfd.uid = ufd.uid
WHERE pfd.default_langcode = 1 AND ufd.default_langcode = 1
ORDER BY ufd.name, pfd.type;
```

In the target platform, profiles typically become either user metadata fields or a related record linked by user ID.

---

## 3. Group Entities (Group Module)

The Group module adds `group` and `group_content` entity types. Groups are containers that own content and members. Group content entities represent the relationship between a group and its members or content. The permission model layers on top of Drupal's core roles.

The Group module went through a major architecture change between 1.x and 2.x/3.x. Check which version is installed before proceeding.

### Version Detection

```bash
# Check installed version
drush pm:list --filter=group --fields=name,version --format=table

# Or from composer
composer show drupal/group 2>/dev/null | grep versions
```

```sql
-- From database
SELECT name, value FROM key_value
WHERE collection = 'system.schema' AND name = 'group';
```

### Group 1.x Schema

Group 1.x uses `group` and `group_content` entity types.

**Group types** (config entities):

```yaml
# group.type.project_team.yml
langcode: en
status: true
id: project_team
label: 'Project team'
description: 'A team collaborating on a project'
creator_membership: true    # Auto-add creator as member
creator_wizard: true        # Show wizard when creating group
creator_roles:              # Roles auto-assigned to creator
  - project_team-admin
```

**Group roles** (config entities):

```yaml
# group.role.project_team-admin.yml
langcode: en
status: true
id: project_team-admin
label: Admin
group_type: project_team
scope: individual           # 'individual' = assigned per member, 'insider' = all members, 'outsider' = all non-members
weight: 0
permissions:
  - 'administer members'
  - 'edit group'
  - 'delete group'
```

**Database tables (Group 1.x):**

| Table | Purpose |
|---|---|
| `groups` | Base table: `id`, `uuid`, `type`, `langcode` |
| `groups_field_data` | `id`, `type`, `uid` (author), `label`, `status`, `created`, `changed`, `langcode` |
| `group_content` | Base table: `id`, `uuid`, `type`, `gid` (group ID), `entity_id` (referenced entity), `langcode` |
| `group_content_field_data` | `id`, `type`, `gid`, `entity_id`, `uid`, `label`, `created`, `changed`, `langcode` |

Group content types define what can go inside a group. Each is a plugin. Common plugins:

| Plugin ID pattern | What it does |
|---|---|
| `group_membership` | Links a user to a group as a member |
| `group_node:{bundle}` | Links a node of type `{bundle}` to a group |
| `group_media:{bundle}` | Links a media entity to a group |
| `subgroup:{group_type}` | Links a group to a parent group (subgroups) |

### Group 2.x / 3.x Schema

Group 2.x replaced `group_content` with `group_relationship` (renamed for clarity). The plugin system changed. Group types became `group_type` config entities.

**Database tables (Group 2.x+):**

| Table | Purpose |
|---|---|
| `groups` | Same as 1.x |
| `groups_field_data` | Same as 1.x |
| `group_relationship` | Replaces `group_content`. Same structure: `id`, `uuid`, `type`, `gid`, `entity_id`, `plugin_id` |
| `group_relationship_field_data` | Translatable fields for relationships |
| `group_relationship_type` | Relationship type definitions (was group_content_type) |

### Export: Group Types and Roles

```sql
-- Group type config (all versions)
SELECT name, data FROM config
WHERE name LIKE 'group.type.%'
   OR name LIKE 'group_type.group_type.%'
ORDER BY name;

-- Group roles (all versions)
SELECT name, data FROM config
WHERE name LIKE 'group.role.%'
ORDER BY name;
```

```bash
drush php:eval "
  \$types = \Drupal::entityTypeManager()->getStorage('group_type')->loadMultiple();
  foreach (\$types as \$type) {
    echo \$type->id() . ' | ' . \$type->label() . PHP_EOL;
  }
"
```

### Export: Groups

```sql
-- All groups
SELECT
  g.id,
  g.uuid,
  gfd.type,
  gfd.label,
  gfd.uid,
  gfd.status,
  gfd.created,
  gfd.changed
FROM groups g
JOIN groups_field_data gfd ON g.id = gfd.id
WHERE gfd.default_langcode = 1
ORDER BY gfd.type, g.id;

-- Count per group type
SELECT type, COUNT(*) AS total
FROM groups_field_data
WHERE default_langcode = 1
GROUP BY type
ORDER BY total DESC;
```

### Export: Group Memberships and Content Relationships

**Group 1.x:**

```sql
-- All group content (memberships + content assignments)
SELECT
  gc.id,
  gcfd.type AS group_content_type,
  gcfd.gid AS group_id,
  gcfd.entity_id,
  gcfd.uid AS author_uid,
  gcfd.label,
  gcfd.created,
  gcfd.changed
FROM group_content gc
JOIN group_content_field_data gcfd ON gc.id = gcfd.id
WHERE gcfd.default_langcode = 1
ORDER BY gcfd.gid, gcfd.type;

-- Memberships only (the type column contains 'membership')
SELECT
  gcfd.gid AS group_id,
  gcfd.entity_id AS member_uid,
  gcfd.created AS joined
FROM group_content_field_data gcfd
WHERE gcfd.type LIKE '%-group_membership'
  AND gcfd.default_langcode = 1
ORDER BY gcfd.gid, gcfd.entity_id;
```

**Group 2.x+:**

```sql
-- All group relationships
SELECT
  gr.id,
  grfd.type AS relationship_type,
  grfd.gid AS group_id,
  grfd.entity_id,
  grfd.plugin_id,
  grfd.uid AS author_uid,
  grfd.label,
  grfd.created,
  grfd.changed
FROM group_relationship gr
JOIN group_relationship_field_data grfd ON gr.id = grfd.id
WHERE grfd.default_langcode = 1
ORDER BY grfd.gid, grfd.type;
```

### Export: Group Role Assignments

Group roles are assigned per membership. In Group 1.x, the role assignment lives in a field on the group_content entity for the membership.

```sql
-- Group 1.x: role assignments stored in group_content__group_roles
SELECT
  entity_id AS group_content_id,
  group_roles_target_id AS role_id
FROM group_content__group_roles
ORDER BY entity_id;

-- Join to get group ID and user ID
SELECT
  gcfd.gid AS group_id,
  gcfd.entity_id AS user_uid,
  gcgr.group_roles_target_id AS group_role
FROM group_content__group_roles gcgr
JOIN group_content_field_data gcfd ON gcgr.entity_id = gcfd.id
WHERE gcfd.type LIKE '%-group_membership'
ORDER BY gcfd.gid, gcfd.entity_id;
```

### What to Capture for Target Platform

| Data | Maps to |
|---|---|
| Group types | Workspace types, team types, organization types, or channel categories |
| Groups | Workspaces, teams, organizations, channels, projects |
| Memberships | Team membership, workspace access, channel subscription |
| Group roles | Workspace-level roles or permission tiers |
| Group content | Content ownership, content-to-workspace assignment |
| Subgroups | Nested workspaces or organizational hierarchy |

---

## 4. Flag Entities (Flag Module)

The Flag module lets users mark content with boolean actions: bookmark, like, follow, report, approve. Each flag action creates a `flagging` entity. The flag type itself is a config entity.

### Config Structure

```yaml
# flag.flag.bookmarks.yml
langcode: en
status: true
id: bookmarks
label: Bookmarks
entity_type: node           # What entity type can be flagged
bundles:                    # Which bundles (empty = all)
  - article
  - page
flag_type: entity:node
global: false               # false = per-user, true = global (one flag state shared by all users)
flag_short: 'Bookmark this'
flag_long: 'Add this content to your bookmarks'
unflag_short: 'Remove bookmark'
unflag_long: 'Remove this content from your bookmarks'
flag_message: 'Bookmarked'
unflag_message: 'Bookmark removed'
```

Key fields in the config:

| Field | Meaning |
|---|---|
| `entity_type` | The entity type this flag targets (node, comment, user, media, or any entity type) |
| `bundles` | Restrict to specific bundles. Empty array means all bundles of that entity type. |
| `global` | `false` = each user has their own flag state. `true` = one shared state for all users. |
| `flag_type` | Plugin ID, usually `entity:{entity_type}` |

### Database Tables

| Table | Purpose |
|---|---|
| `flagging` | Base table: `id`, `uuid`, `flag_id` (machine name of the flag type), `entity_type`, `entity_id`, `uid`, `session_id`, `created` |
| `flagging_field_data` | Unused in most installs. Only present if flagging entities have extra fields attached. |
| `flag_counts` | Aggregate table: `flag_id`, `entity_type`, `entity_id`, `count`, `last_updated`. Stores total flag count per entity. |

### Export: Flag Types

```sql
SELECT name, data FROM config
WHERE name LIKE 'flag.flag.%'
ORDER BY name;
```

```bash
drush php:eval "
  \$flags = \Drupal::entityTypeManager()->getStorage('flagging')->getEntityType();
  \$flag_configs = \Drupal::entityTypeManager()->getStorage('flag')->loadMultiple();
  foreach (\$flag_configs as \$flag) {
    printf(\"%-20s %-15s bundles=[%s] global=%s\n\",
      \$flag->id(),
      \$flag->getFlaggableEntityTypeId(),
      implode(',', \$flag->getBundles()),
      \$flag->isGlobal() ? 'yes' : 'no'
    );
  }
"
```

### Export: Flagging Records

```sql
-- All flaggings
SELECT
  id,
  flag_id,
  entity_type,
  entity_id,
  uid,
  created
FROM flagging
ORDER BY flag_id, entity_id;

-- Count per flag type
SELECT flag_id, COUNT(*) AS total
FROM flagging
GROUP BY flag_id
ORDER BY total DESC;

-- Aggregate counts (pre-computed by the module)
SELECT flag_id, entity_type, entity_id, count, last_updated
FROM flag_counts
ORDER BY flag_id, count DESC;
```

### Export: Per-User Flaggings with Context

```sql
-- Bookmarks with node titles
SELECT
  f.id AS flagging_id,
  f.flag_id,
  f.entity_id AS nid,
  nfd.title AS node_title,
  f.uid,
  ufd.name AS username,
  FROM_UNIXTIME(f.created) AS flagged_at
FROM flagging f
JOIN node_field_data nfd ON f.entity_id = nfd.nid AND f.entity_type = 'node'
JOIN users_field_data ufd ON f.uid = ufd.uid
WHERE f.flag_id = 'bookmarks'
ORDER BY f.uid, f.created;
```

### What to Capture for Target Platform

| Flag type | Common target equivalents |
|---|---|
| Bookmark / Save | User favorites, saved items, reading list |
| Like / Heart | Reaction count, upvote |
| Follow | Subscription, watch, notification preference |
| Report / Flag for review | Content moderation queue entry |
| Approve | Workflow state transition trigger |

Export both the individual flagging records (who flagged what, when) and the aggregate counts. Most target platforms need both: the counts for display and the individual records for per-user features.

---

## 5. Message Entities (Message Module)

The Message module creates `message` entities for activity logs, notifications, and audit trails. Each message references a template that defines the text pattern. Messages are write-once records. They store what happened, who did it, and when.

### Config Structure

```yaml
# message.template.content_published.yml
langcode: en
status: true
id: content_published
label: 'Content published'
description: 'Logged when content is published'
text:
  -
    value: '<p>@user published <a href="@url">@title</a>.</p>'
    format: basic_html
settings:
  token options:
    clear: false
    token replace: true
```

Templates use token placeholders. The actual values come from the message entity's fields and referenced entities at render time.

### Database Tables

| Table | Purpose |
|---|---|
| `message` | Base table: `mid`, `uuid`, `template` (bundle/message type), `uid` (author), `created`, `langcode` |
| `message_field_data` | Translatable base fields. Rarely differs from `message` on monolingual sites. |
| `message__field_{name}` | Custom fields on message entities. Common: `field_node_reference`, `field_comment_reference`. |

### Export: Message Templates

```sql
SELECT name, data FROM config
WHERE name LIKE 'message.template.%'
ORDER BY name;
```

### Export: Messages

```sql
-- All messages
SELECT
  m.mid,
  m.uuid,
  mfd.template,
  mfd.uid,
  FROM_UNIXTIME(mfd.created) AS created_at,
  mfd.langcode
FROM message m
JOIN message_field_data mfd ON m.mid = mfd.mid
WHERE mfd.default_langcode = 1
ORDER BY mfd.created DESC;

-- Count per template
SELECT template, COUNT(*) AS total
FROM message_field_data
WHERE default_langcode = 1
GROUP BY template
ORDER BY total DESC;
```

### Export: Message Arguments and References

Messages often store references to the entities they describe. These live in field tables:

```sql
-- Find all field tables for messages
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'message__%'
  AND table_name NOT LIKE 'message_field_data'
  AND table_name NOT LIKE '%_revision%'
ORDER BY table_name;
```

### Migration Decision: Keep or Discard

Messages are activity logs. Ask these questions before exporting:

1. Does the target platform have an activity feed or audit log? If yes, export and transform.
2. Are messages used for notifications that users see in their UI? If yes, you need the per-user message data.
3. Are messages write-once audit records for compliance? If yes, export everything. Store as immutable records.
4. Are messages transient notifications (read/dismissed)? Probably safe to discard. Confirm with the site owner.

Count the rows before deciding. Some sites accumulate millions of messages. Export the templates and a sample set first. Only export the full dataset if the target platform will use it.

---

## 6. Queue Items (Advanced Queue, Queue UI)

The `advancedqueue` module stores queue jobs as entities. Standard Drupal queues use the `queue` table, which holds serialized blobs. Advanced Queue adds structure.

### Standard Drupal Queue Table

```sql
-- Core queue table (all Drupal versions)
SELECT name, COUNT(*) AS items, MIN(created) AS oldest, MAX(created) AS newest
FROM queue
GROUP BY name
ORDER BY items DESC;
```

The `data` column is PHP-serialized. Items are meant to be transient. In most migrations, queue data is discarded. Check with the site owner if any queues hold business-critical data that was never processed.

### Advanced Queue Tables

The `advancedqueue` module stores jobs in a dedicated table tied to queue config entities.

```yaml
# advancedqueue.advancedqueue_queue.order_sync.yml
langcode: en
status: true
id: order_sync
label: 'Order sync'
backend: database
backend_configuration:
  lease_time: 300
processor: cron
processing_time: 90
```

```sql
-- Advanced Queue jobs table
SELECT
  job_id,
  queue_id,
  type,
  state,          -- 'queued', 'processing', 'success', 'failure'
  payload,        -- JSON
  FROM_UNIXTIME(available) AS available_at,
  FROM_UNIXTIME(processed) AS processed_at,
  num_retries,
  message         -- Error message on failure
FROM advancedqueue
ORDER BY queue_id, job_id;

-- Count by queue and state
SELECT queue_id, state, COUNT(*) AS total
FROM advancedqueue
GROUP BY queue_id, state
ORDER BY queue_id, state;
```

The `payload` column is JSON. Its structure depends on the job type. Examine a sample before writing a parser:

```sql
SELECT type, SUBSTRING(payload, 1, 500) AS payload_preview
FROM advancedqueue
GROUP BY type
LIMIT 20;
```

### Migration Decision

Queue items are almost always transient. Export only if:

- Failed jobs contain data that needs manual review or reprocessing.
- The queue represents a backlog of unprocessed business operations (orders, sync tasks, imports).
- Compliance requires retaining job history.

---

## 7. Custom Entity Types from Bespoke Modules

Sites with custom modules often define their own entity types. These follow no standard pattern beyond Drupal's entity API. Discovery is the hard part. Once found, the export process matches the pattern used for every other content entity.

### Finding Custom Entity Types

Use the discovery queries from the top of this skill. Filter out all known core and contrib entity types. What remains is custom.

```bash
# List entity types provided by modules in modules/custom/
drush php:eval "
  \$definitions = \Drupal::entityTypeManager()->getDefinitions();
  foreach (\$definitions as \$id => \$def) {
    if (\$def instanceof \Drupal\Core\Entity\ContentEntityTypeInterface) {
      \$provider = \$def->getProvider();
      \$module_path = \Drupal::service('extension.list.module')->getPath(\$provider);
      if (strpos(\$module_path, 'modules/custom') !== false) {
        printf(\"%-25s %-25s %s\n\", \$id, \$provider, \$def->getBaseTable());
      }
    }
  }
"
```

### Reverse-Engineering an Unknown Entity Type

For each custom entity type found, extract its schema:

```bash
# Get full entity type definition
drush php:eval "
  \$def = \Drupal::entityTypeManager()->getDefinition('{entity_type_id}');
  echo 'Label: ' . \$def->getLabel() . PHP_EOL;
  echo 'Base table: ' . \$def->getBaseTable() . PHP_EOL;
  echo 'Data table: ' . \$def->getDataTable() . PHP_EOL;
  echo 'Revision table: ' . \$def->getRevisionTable() . PHP_EOL;
  echo 'Revision data table: ' . \$def->getRevisionDataTable() . PHP_EOL;
  echo 'Provider: ' . \$def->getProvider() . PHP_EOL;
  echo 'Has bundles: ' . (\$def->getBundleEntityType() ? 'yes (' . \$def->getBundleEntityType() . ')' : 'no') . PHP_EOL;
  echo 'Entity keys: ' . json_encode(\$def->getKeys()) . PHP_EOL;
"
```

```bash
# Get all fields for the entity type
drush php:eval "
  \$fields = \Drupal::service('entity_field.manager')
    ->getFieldStorageDefinitions('{entity_type_id}');
  foreach (\$fields as \$name => \$field) {
    printf(\"%-30s %-20s cardinality=%s\n\",
      \$name,
      \$field->getType(),
      \$field->getCardinality() == -1 ? 'unlimited' : \$field->getCardinality()
    );
  }
"
```

### Generic Export Pattern

Every content entity follows the same table structure. Once you know the base table and data table, the export query is predictable:

```sql
-- Replace {base_table} and {data_table} with actual table names

-- Row count
SELECT COUNT(*) FROM {base_table};

-- Schema inspection
DESCRIBE {base_table};
DESCRIBE {data_table};

-- Base data
SELECT * FROM {data_table}
WHERE default_langcode = 1
ORDER BY id
LIMIT 100;

-- Field tables
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE '{base_table}__%'
  AND table_name NOT LIKE '%_revision__%'
ORDER BY table_name;
```

### JSON:API for Custom Entities

Custom entity types appear in JSON:API if the module does not explicitly exclude them. Check the resource list:

```bash
curl -s 'https://example.com/jsonapi' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for key in sorted(data.get('links', {}).keys()):
    if key not in ('self',):
        print(key)
" | grep -v '^node--' | grep -v '^user--' | grep -v '^taxonomy_term--'
```

Anything in that filtered list that you do not recognize is a custom or contrib entity type worth investigating.

---

## 8. Export Checklist

Run through this for every non-core entity type discovered:

| Step | Action |
|---|---|
| 1 | Identify entity type ID, provider module, and base table |
| 2 | Count total entities and entities per bundle |
| 3 | Export entity type config (YAML or config table query) |
| 4 | Export bundle definitions if the entity type has bundles |
| 5 | Export field storage and field instance config for all bundles |
| 6 | Export base table and data table rows |
| 7 | Export each field value table |
| 8 | Export revision tables if the target platform needs revision history |
| 9 | Map entity references: which other entities point to this entity type, and which entities this type points to |
| 10 | Document the mapping to target platform structures |

### Entity Reference Mapping

Custom entities often reference or are referenced by nodes, users, or other entities. Find these cross-references:

```sql
-- Find fields that reference a custom entity type
SELECT fc.name, fc.data
FROM config fc
WHERE fc.name LIKE 'field.storage.%.field_%'
  AND fc.data LIKE '%{entity_type_id}%';
```

```bash
# More precise: find entity reference fields targeting a specific entity type
drush php:eval "
  \$fields = \Drupal::service('entity_field.manager')
    ->getFieldMapByFieldType('entity_reference');
  foreach (\$fields as \$entity_type => \$field_list) {
    foreach (\$field_list as \$field_name => \$info) {
      \$storage = \Drupal\field\Entity\FieldStorageConfig::loadByName(\$entity_type, \$field_name);
      if (\$storage && \$storage->getSetting('target_type') === '{entity_type_id}') {
        echo \$entity_type . '.' . \$field_name . ' -> {entity_type_id}' . PHP_EOL;
      }
    }
  }
"
```

---

## 9. Output Format

Store each entity type export in its own directory:

```
export/
  custom_entities/
    {entity_type_id}/
      type_definition.json         # Entity type config
      bundles.json                 # Bundle definitions (if applicable)
      field_definitions.json       # Field storage + instance configs
      entities.json                # All entity data with field values
      entity_references.json       # Cross-reference map (what points here, what this points to)
      summary.json                 # Counts, bundle breakdown, field list
```

### Summary File Structure

```json
{
  "entity_type": "event_registration",
  "provider_module": "eck",
  "base_table": "eck_event_registration",
  "total_entities": 4521,
  "bundles": {
    "workshop": 3200,
    "conference": 1321
  },
  "fields": [
    {
      "name": "field_attendee_name",
      "type": "string",
      "cardinality": 1
    },
    {
      "name": "field_event_reference",
      "type": "entity_reference",
      "target_type": "node",
      "target_bundles": ["event"],
      "cardinality": 1
    }
  ],
  "referenced_by": [
    {
      "entity_type": "node",
      "bundle": "event",
      "field_name": "field_registrations",
      "count": 3400
    }
  ],
  "exported_at": "2024-01-15T10:30:00Z"
}
```

---

## Common Pitfalls

**ECK table names vary.** Some versions of ECK prefix tables with `eck_`, others use just the entity type ID. Check `information_schema` before writing queries.

**Profile module vs. user fields.** Some sites use the Profile module. Others attach fields directly to the user entity. Skill 17 covers user fields. This skill covers the separate `profile` entity. A site can use both. Check for the `profile` base table to know which path applies.

**Group module version mismatch.** Group 1.x and 2.x have different table names and different config entity structures. Running 1.x queries against a 2.x site returns empty results. Always check the version first.

**Flag module anonymous flaggings.** When `global` is false and anonymous users can flag, the module stores a session ID instead of a uid. These flaggings have `uid = 0` and a non-empty `session_id`. They are ephemeral. Most migrations discard anonymous flaggings. Confirm with the site owner.

**Message volume.** Sites with the Message module enabled for years accumulate millions of rows. Export the templates and a representative sample before committing to a full export. A million-row JSON file is not useful. Consider exporting messages in batches by date range or template type.

**Custom entities without config.** Some custom modules define entity types entirely in code with no config entities for bundles. These entity types have a single implicit bundle matching the entity type ID. The field storage and field instance configs still exist in the config system. The entity type definition exists only in the PHP class annotation or attribute.

**Orphaned field tables.** After module updates or failed migrations, field tables can exist in the database without matching config entries. Compare `information_schema` table lists against config-defined fields. Orphaned tables may contain data that was never cleaned up. Decide with the site owner whether to include or discard.
