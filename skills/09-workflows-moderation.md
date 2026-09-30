# Skill 9: Workflows & Moderation

Extract editorial workflow definitions and per-entity moderation state from a Drupal site. Output: a complete map of states, transitions, permissions, entity assignments, and the current moderation state of every piece of content.

---

## When to Use This Skill

The site uses the Content Moderation module (D8.5+ core) or the Workflows module (D8.4+ core). In Drupal 7, the equivalent is the `workbench_moderation` contrib module.

Signs the site uses editorial workflows:

- `content_moderation` appears in `core.extension.yml` or `drush pm:list --status=enabled`
- `workflows` appears in the same place (Content Moderation depends on Workflows)
- The database has `content_moderation_state_field_data` and `content_moderation_state_field_revision` tables
- Config files matching `workflows.workflow.*.yml` exist

If none of these are present, skip this skill. The site uses direct publish/unpublish without moderation.

---

## Background: D7 vs D8+ Moderation

### Drupal 7: workbench_moderation

Drupal 7 has no core workflow system. The `workbench_moderation` contrib module adds moderation states to nodes. Key differences:

| Aspect | D7 workbench_moderation | D8+ content_moderation |
|---|---|---|
| Storage | `workbench_moderation_node_history` table | `content_moderation_state_field_data` / `_field_revision` tables |
| Config | Database variables, no YAML | `workflows.workflow.*.yml` config entities |
| States | Hardcoded default: Draft, Needs Review, Published | Fully configurable states per workflow |
| Entity support | Nodes only | Nodes, block_content, media, taxonomy_term, any revisionable entity type |
| Transitions | States define allowed next-states | Transitions are named objects with from/to mappings |
| Permissions | Per-state-transition permissions via `workbench_moderation` | Per-transition permissions via `workflows` |
| Multiple workflows | One global workflow | Multiple named workflows, each assigned to specific bundles |

### Drupal 8+: content_moderation + workflows

Two modules work together:

- **Workflows** (`workflows` core module): Defines workflow entities with states and transitions. Generic system. Not tied to content.
- **Content Moderation** (`content_moderation` core module): Connects workflows to entity types. Adds the moderation state field. Enforces transition rules on save. Depends on Workflows.

A workflow is a config entity stored as `workflows.workflow.{machine_name}.yml`. Each workflow has:

- **States**: machine name, label, whether the state counts as "published", whether it creates a default revision
- **Transitions**: machine name, label, list of allowed "from" states, single "to" state
- **Type settings**: which entity types and bundles use this workflow

---

## Access Methods

### Method 1: Config YAML (D8+)

Best source for workflow definitions. Requires exported config files.

**File location**: `config/sync/workflows.workflow.*.yml` or wherever the site stores config exports.

Find all workflow config files:

```bash
find /path/to/config -name 'workflows.workflow.*.yml'
```

Each file has this structure:

```yaml
uuid: 12345678-abcd-1234-abcd-123456789012
langcode: en
status: true
dependencies:
  config:
    - node.type.article
    - node.type.page
  module:
    - content_moderation
id: editorial
label: Editorial
type: content_moderation
type_settings:
  states:
    draft:
      label: Draft
      weight: -5
      published: false
      default_revision: false
    review:
      label: In review
      weight: -3
      published: false
      default_revision: false
    published:
      label: Published
      weight: 0
      published: true
      default_revision: true
    archived:
      label: Archived
      weight: 5
      published: false
      default_revision: true
  transitions:
    create_new_draft:
      label: Create New Draft
      from:
        - draft
        - review
        - published
        - archived
      to: draft
      weight: 0
    submit_for_review:
      label: Submit for Review
      from:
        - draft
      to: review
      weight: 1
    publish:
      label: Publish
      from:
        - draft
        - review
      to: published
      weight: 2
    archive:
      label: Archive
      from:
        - published
      to: archived
      weight: 3
  entity_types:
    node:
      - article
      - page
    block_content:
      - basic
```

**Key fields to extract**:

| YAML Path | What It Tells You |
|---|---|
| `id` | Machine name of the workflow |
| `label` | Human-readable name |
| `type` | Should be `content_moderation` for editorial workflows |
| `type_settings.states.*` | Every moderation state: published flag, default_revision flag |
| `type_settings.transitions.*` | Every transition: from states, to state |
| `type_settings.entity_types` | Which entity types and bundles use this workflow |
| `dependencies.config` | Config entities this workflow depends on (bundle definitions) |

**Extract all workflow definitions to JSON**:

```bash
# Requires yq (https://github.com/mikefarah/yq)
for f in config/sync/workflows.workflow.*.yml; do
  echo "=== $(basename "$f" .yml) ==="
  yq eval '{
    "id": .id,
    "label": .label,
    "states": .type_settings.states,
    "transitions": .type_settings.transitions,
    "entity_types": .type_settings.entity_types
  }' "$f"
done
```

### Method 2: Drush (D8+)

Use when you have shell access but no config export.

**Export workflow config**:

```bash
# List all workflow config names
drush config:list | grep workflows.workflow

# Export a specific workflow
drush config:get workflows.workflow.editorial --format=yaml

# Export all workflows to files
for wf in $(drush config:list | grep workflows.workflow); do
  drush config:get "$wf" --format=yaml > "export/${wf}.yml"
done
```

**Get the default moderation state for new content**:

The first state listed with `default_revision: false` and `published: false` is the initial state for new drafts. Drupal picks the state with the lowest weight that is not published.

```bash
drush config:get workflows.workflow.editorial type_settings.states --format=yaml
```

**List entity types and bundles assigned to each workflow**:

```bash
drush config:get workflows.workflow.editorial type_settings.entity_types --format=yaml
```

### Method 3: Database (D8+)

Use when you have database access but no Drush or config files.

**Get workflow definitions from the config table**:

```sql
SELECT name, data
FROM config
WHERE name LIKE 'workflows.workflow.%';
```

The `data` column contains serialized PHP. Deserialize it to read the full workflow definition:

```bash
drush php:eval "
  \$config = \Drupal::config('workflows.workflow.editorial');
  print_r(\$config->getRawData());
"
```

Or query the raw serialized data and parse it externally:

```bash
drush sql:query "SELECT data FROM config WHERE name = 'workflows.workflow.editorial'" \
  | php -r "print_r(unserialize(file_get_contents('php://stdin')));"
```

**Get current moderation state for every entity**:

```sql
-- Current moderation state per entity
SELECT
  content_entity_type_id AS entity_type,
  content_entity_id AS entity_id,
  content_entity_revision_id AS revision_id,
  workflow,
  moderation_state
FROM content_moderation_state_field_data
ORDER BY content_entity_type_id, content_entity_id;
```

**Count entities by moderation state**:

```sql
SELECT
  content_entity_type_id AS entity_type,
  workflow,
  moderation_state,
  COUNT(*) AS count
FROM content_moderation_state_field_data
GROUP BY content_entity_type_id, workflow, moderation_state
ORDER BY content_entity_type_id, moderation_state;
```

**Get moderation state history (all revisions)**:

```sql
-- Full revision history with moderation states
SELECT
  r.content_entity_type_id AS entity_type,
  r.content_entity_id AS entity_id,
  r.content_entity_revision_id AS revision_id,
  r.workflow,
  r.moderation_state
FROM content_moderation_state_field_revision r
ORDER BY r.content_entity_type_id, r.content_entity_id, r.content_entity_revision_id;
```

**Join with node data to get timestamps and authors**:

```sql
-- Node revision history with moderation states and metadata
SELECT
  cms.content_entity_id AS nid,
  cms.content_entity_revision_id AS vid,
  cms.moderation_state,
  nr.revision_timestamp,
  FROM_UNIXTIME(nr.revision_timestamp) AS revision_date,
  nr.revision_uid,
  ufd.name AS revision_author,
  nr.revision_log
FROM content_moderation_state_field_revision cms
JOIN node_revision nr
  ON cms.content_entity_revision_id = nr.vid
  AND cms.content_entity_type_id = 'node'
LEFT JOIN users_field_data ufd
  ON nr.revision_uid = ufd.uid
ORDER BY cms.content_entity_id, cms.content_entity_revision_id;
```

### Method 4: Database (D7 workbench_moderation)

Different table structure. Different column names.

**Get current moderation state**:

```sql
SELECT
  nid,
  vid,
  from_state,
  state AS current_state,
  uid,
  stamp AS timestamp,
  FROM_UNIXTIME(stamp) AS date,
  published,
  is_current
FROM workbench_moderation_node_history
WHERE is_current = 1
ORDER BY nid;
```

**Get full moderation history**:

```sql
SELECT
  nid,
  vid,
  from_state,
  state,
  uid,
  FROM_UNIXTIME(stamp) AS date,
  published,
  is_current
FROM workbench_moderation_node_history
ORDER BY nid, stamp;
```

**Count by state**:

```sql
SELECT state, COUNT(*) AS count
FROM workbench_moderation_node_history
WHERE is_current = 1
GROUP BY state
ORDER BY count DESC;
```

**Get D7 moderation states** (stored in the database, not config files):

```sql
SELECT name, label, description, weight
FROM workbench_moderation_states
ORDER BY weight;
```

**Get D7 transitions**:

```sql
SELECT from_name, to_name
FROM workbench_moderation_transitions
ORDER BY from_name, to_name;
```

---

## Extracting Transition Permissions

Permissions for workflow transitions control which roles can move content between states.

### D8+: From Config

Transition permissions follow the naming pattern:

```
use {workflow_id} transition {transition_id}
```

Example: `use editorial transition publish` grants a role the right to move content from any allowed "from" state to "Published" via the "publish" transition in the "editorial" workflow.

**Export role-to-transition mapping**:

```bash
# List all roles and their workflow permissions
for role_file in config/sync/user.role.*.yml; do
  role=$(yq eval '.id' "$role_file")
  perms=$(yq eval '.permissions[]' "$role_file" 2>/dev/null | grep 'transition')
  if [ -n "$perms" ]; then
    echo "--- $role ---"
    echo "$perms"
  fi
done
```

**Via Drush**:

```bash
# Get permissions for a specific role
drush config:get user.role.editor permissions --format=yaml | grep transition

# Get all roles with any workflow transition permission
for role in $(drush role:list --format=list); do
  perms=$(drush role:perm:list "$role" 2>/dev/null | grep "transition")
  if [ -n "$perms" ]; then
    echo "=== $role ==="
    echo "$perms"
  fi
done
```

**Via Database**:

```sql
-- D8+: permissions are stored in the config table under user.role.*
-- Easier to use Drush or config files. But if you must:
SELECT name, data
FROM config
WHERE name LIKE 'user.role.%';
```

Parse the serialized PHP `data` column and filter the `permissions` array for entries containing "transition".

### D7: From Database

```sql
SELECT r.name AS role, p.permission
FROM role_permission p
JOIN role r ON p.rid = r.rid
WHERE p.permission LIKE '%moderate%'
ORDER BY r.name, p.permission;
```

D7 workbench_moderation permissions follow patterns like:
- `moderate content from draft to needs_review`
- `moderate content from needs_review to published`

---

## Full Export Script

This script extracts all workflow and moderation data from a D8+ site into structured JSON files.

```bash
#!/bin/bash
# Export workflows, moderation states, and permissions
# Requires: drush, jq

EXPORT_DIR="./export/workflows"
mkdir -p "$EXPORT_DIR"

echo "Exporting workflow definitions..."
for wf_name in $(drush config:list 2>/dev/null | grep workflows.workflow); do
  wf_id=$(echo "$wf_name" | sed 's/workflows.workflow.//')
  drush config:get "$wf_name" --format=json > "$EXPORT_DIR/${wf_id}.definition.json"
  echo "  Exported: $wf_id"
done

echo "Exporting current moderation states..."
drush sql:query "
  SELECT JSON_OBJECT(
    'entity_type', content_entity_type_id,
    'entity_id', content_entity_id,
    'revision_id', content_entity_revision_id,
    'workflow', workflow,
    'moderation_state', moderation_state
  )
  FROM content_moderation_state_field_data
  ORDER BY content_entity_type_id, content_entity_id
" 2>/dev/null | jq -s '.' > "$EXPORT_DIR/current_states.json"
echo "  Exported current states"

echo "Exporting moderation state history..."
drush sql:query "
  SELECT JSON_OBJECT(
    'entity_type', content_entity_type_id,
    'entity_id', content_entity_id,
    'revision_id', content_entity_revision_id,
    'workflow', workflow,
    'moderation_state', moderation_state
  )
  FROM content_moderation_state_field_revision
  ORDER BY content_entity_type_id, content_entity_id, content_entity_revision_id
" 2>/dev/null | jq -s '.' > "$EXPORT_DIR/state_history.json"
echo "  Exported state history"

echo "Exporting state counts..."
drush sql:query "
  SELECT JSON_OBJECT(
    'entity_type', content_entity_type_id,
    'workflow', workflow,
    'moderation_state', moderation_state,
    'count', COUNT(*)
  )
  FROM content_moderation_state_field_data
  GROUP BY content_entity_type_id, workflow, moderation_state
  ORDER BY content_entity_type_id, moderation_state
" 2>/dev/null | jq -s '.' > "$EXPORT_DIR/state_counts.json"
echo "  Exported state counts"

echo "Exporting transition permissions..."
PERMS_FILE="$EXPORT_DIR/transition_permissions.json"
echo "[" > "$PERMS_FILE"
first=true
for role in $(drush role:list --format=list 2>/dev/null); do
  perms=$(drush config:get "user.role.$role" permissions --format=json 2>/dev/null \
    | jq '[.[] | select(contains("transition"))]')
  if [ "$perms" != "[]" ] && [ -n "$perms" ]; then
    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$PERMS_FILE"
    fi
    echo "{\"role\": \"$role\", \"transition_permissions\": $perms}" >> "$PERMS_FILE"
  fi
done
echo "]" >> "$PERMS_FILE"
echo "  Exported transition permissions"

echo "Done. Files in $EXPORT_DIR/"
ls -la "$EXPORT_DIR/"
```

### D7 Export Script

```bash
#!/bin/bash
# Export D7 workbench_moderation data
# Requires: drush (Drush 8), jq

EXPORT_DIR="./export/workflows"
mkdir -p "$EXPORT_DIR"

echo "Exporting D7 moderation states..."
drush sql:query "
  SELECT name, label, description, weight
  FROM workbench_moderation_states
  ORDER BY weight
" > "$EXPORT_DIR/d7_states.tsv"

echo "Exporting D7 transitions..."
drush sql:query "
  SELECT from_name, to_name
  FROM workbench_moderation_transitions
  ORDER BY from_name, to_name
" > "$EXPORT_DIR/d7_transitions.tsv"

echo "Exporting D7 current moderation state..."
drush sql:query "
  SELECT nid, vid, state, uid, FROM_UNIXTIME(stamp), published
  FROM workbench_moderation_node_history
  WHERE is_current = 1
  ORDER BY nid
" > "$EXPORT_DIR/d7_current_states.tsv"

echo "Exporting D7 full moderation history..."
drush sql:query "
  SELECT nid, vid, from_state, state, uid, FROM_UNIXTIME(stamp), published, is_current
  FROM workbench_moderation_node_history
  ORDER BY nid, stamp
" > "$EXPORT_DIR/d7_state_history.tsv"

echo "Exporting D7 moderation permissions..."
drush sql:query "
  SELECT r.name, p.permission
  FROM role_permission p
  JOIN role r ON p.rid = r.rid
  WHERE p.permission LIKE '%moderate%'
  ORDER BY r.name, p.permission
" > "$EXPORT_DIR/d7_moderation_permissions.tsv"

echo "Done. Files in $EXPORT_DIR/"
```

---

## Output Schema

After running the export, you should have these files:

| File | Contents |
|---|---|
| `{workflow_id}.definition.json` | Full workflow config: states, transitions, entity assignments |
| `current_states.json` | Current moderation state for every moderated entity |
| `state_history.json` | Every moderation state change across all revisions |
| `state_counts.json` | Aggregate counts: how many entities sit in each state |
| `transition_permissions.json` | Which roles can execute which transitions |

For D7 sites, the TSV files contain equivalent data in tab-separated format.

---

## What to Do With This Data

### Map states to the target platform

Most target platforms have simpler publishing models. Map Drupal states to target equivalents:

| Drupal State | Typical Target Equivalent |
|---|---|
| `draft` | Draft |
| `review` / `needs_review` | "Pending review" or a custom status field |
| `published` | Published / Live |
| `archived` | Unpublished with an "archived" tag, or soft-deleted |

If the target has no workflow system, flatten to two states: published and draft. Use tags or metadata fields to preserve the original state for reference.

### Preserve state history

If revision history matters (see Skill 27), the moderation state per revision tells you who approved what and when. This is audit trail data. Export it as metadata alongside revision content, even if the target platform cannot natively replay the workflow.

### Recreate transition rules

If the target has a workflow engine (WordPress Editorial Flow, Sanity document actions, Contentful workflows, custom state machines), rebuild the transition graph. The export gives you the exact from/to mappings and role assignments. Match roles using the output from Skill 10.

### Handle the "published" and "default_revision" flags

These two booleans on each state control Drupal's revision behavior:

- `published: true` means the entity is visible to anonymous users when in this state
- `default_revision: true` means this revision is the one loaded by default (the "current" version)

A state can be `published: false, default_revision: true`. This is how "Archived" works: the entity is not published, but the archived revision is the default. No forward draft exists.

A state can be `published: false, default_revision: false`. This is a forward draft: the entity has a newer unpublished revision, but the older published revision remains the default.

Map these flags to the target's draft/publish model. Most systems have simpler semantics. Document any cases where Drupal's behavior cannot be replicated.

---

## Edge Cases

**Multiple workflows**: A site can have more than one workflow. Each workflow is assigned to specific entity type + bundle combinations. A bundle can belong to only one workflow. Check `type_settings.entity_types` in each workflow definition to build the complete mapping.

**Bundles without moderation**: Not every content type uses a workflow. Unmoderated bundles do not appear in any workflow's `entity_types` list. These bundles use simple publish/unpublish. Check which bundles are missing from all workflows.

**Scheduled transitions**: The `scheduler_content_moderation_integration` module (contrib) adds time-based state changes. If the site uses it, check the `node__field_publish_state` and `node__field_unpublish_state` tables for scheduled future transitions. See Skill 28 for full Scheduler export.

**Custom workflow types**: The Workflows module supports custom workflow types beyond content moderation. Other contrib modules can register their own types (e.g., `workflows_field`). Filter for `type: content_moderation` in the workflow config to isolate editorial workflows. Non-content-moderation workflows may still be worth exporting if they drive business logic.

**Entity types beyond nodes**: Content Moderation works on any revisionable entity type. Block content (`block_content`), media (`media`), and taxonomy terms (`taxonomy_term`) can all have moderation states. The `content_moderation_state_field_data` table stores entity type in the `content_entity_type_id` column. Do not assume only nodes are moderated.

---

## Verification

After export, verify completeness:

```bash
# Count moderated entities per type
drush sql:query "
  SELECT content_entity_type_id, COUNT(*)
  FROM content_moderation_state_field_data
  GROUP BY content_entity_type_id
"

# Verify every moderated bundle is accounted for in a workflow
drush sql:query "
  SELECT DISTINCT content_entity_type_id, workflow
  FROM content_moderation_state_field_data
"

# Check for orphaned moderation states (entity deleted, state record remains)
drush sql:query "
  SELECT cms.content_entity_type_id, cms.content_entity_id
  FROM content_moderation_state_field_data cms
  LEFT JOIN node_field_data nfd
    ON cms.content_entity_id = nfd.nid
    AND cms.content_entity_type_id = 'node'
  WHERE cms.content_entity_type_id = 'node'
    AND nfd.nid IS NULL
"
```

If orphaned records exist, exclude them from the migration. They are remnants of deleted content.

---

## Workspaces

The Workspaces module (core, D8.6+ experimental, stable in D10.3+) adds content staging. Editors group pending changes into named workspaces and publish them as a batch. This is separate from Content Moderation but often used alongside it.

Signs the site uses Workspaces:

- `workspaces` appears in `core.extension.yml` or `drush pm:list --status=enabled`
- The database has `workspaces` and `workspace_association` tables
- Config files matching `workspaces.workspace.*.yml` exist

If none of these are present, skip this section.

### Workspace Entities

A workspace is a config entity. Each workspace has:

| Field | Description |
|---|---|
| `id` | Machine name (e.g., `stage`, `spring_campaign`) |
| `label` | Human-readable name |
| `parent` | Machine name of the parent workspace, if nested |
| `uid` | User ID of the workspace owner |
| `created` | Unix timestamp of creation |

Config storage: `workspaces.workspace.{machine_name}.yml`

Every site has a "Live" workspace. This is the default. Published content lives here. You cannot delete it.

### Workspace Associations

The `workspace_association` table tracks which entities have pending changes in which workspace.

| Column | Description |
|---|---|
| `workspace` | Machine name of the workspace |
| `target_entity_type_id` | Entity type (e.g., `node`, `media`, `block_content`) |
| `target_entity_id` | Entity ID |
| `target_entity_revision_id` | Revision ID of the pending change |

A row in this table means: this entity has a draft revision that belongs to this workspace. The revision has not been published to Live.

### Content Staging Model

Workspaces split content into two layers:

1. **Live**: The published state of all content. What anonymous visitors see. This is the baseline.
2. **Named workspaces** (e.g., "Spring Campaign", "Redesign Phase 2"): Hold draft revisions. Editors make changes inside a workspace without affecting Live.

An entity edited in a named workspace gets a new revision. That revision is tagged to the workspace via `workspace_association`. The Live revision stays unchanged. Visitors see the Live revision. Editors switching to the workspace see their pending version.

Multiple workspaces can hold different pending revisions of the same entity. Each workspace is an independent staging area.

### Deploy Workflow

Publishing a workspace merges all its associated entity revisions into Live. This is atomic: every pending change in the workspace goes live together, or none of them do.

The deploy operation:

1. Takes every revision tracked in `workspace_association` for that workspace
2. Marks each as the default, published revision in Live
3. Removes the `workspace_association` rows for the deployed entities
4. The workspace still exists after deploy but has zero pending changes

If Content Moderation is also active, entities must reach a published moderation state before the workspace can deploy. The two systems interact: moderation gates individual entities, workspaces batch-publish them.

### Database Queries

**List all workspaces**:

```sql
SELECT id, label, uid, created
FROM workspaces;
```

**Count pending changes per workspace**:

```sql
SELECT workspace, COUNT(*) AS pending_changes
FROM workspace_association
GROUP BY workspace;
```

**List entities with pending changes in a workspace**:

```sql
SELECT target_entity_type_id, target_entity_id, target_entity_revision_id
FROM workspace_association
WHERE workspace = 'spring_campaign';
```

**Join with node data to see what's staged**:

```sql
SELECT
  wa.target_entity_id AS nid,
  wa.target_entity_revision_id AS vid,
  nfd.title,
  nr.revision_timestamp,
  FROM_UNIXTIME(nr.revision_timestamp) AS revision_date
FROM workspace_association wa
JOIN node_field_data nfd
  ON wa.target_entity_id = nfd.nid
  AND wa.target_entity_type_id = 'node'
JOIN node_revision nr
  ON wa.target_entity_revision_id = nr.vid
WHERE wa.workspace = 'spring_campaign'
ORDER BY nfd.title;
```

### Access via Drush

```bash
# List all workspaces
drush workspace:list

# Switch workspace context (affects subsequent drush commands in the session)
drush workspace:activate spring_campaign

# Export content from Live (default, no switch needed)
drush content:export --format=json

# Export content as seen in a named workspace
drush workspace:activate spring_campaign
drush content:export --format=json

# Return to Live
drush workspace:activate live
```

Workspace context matters for any Drush command that reads entity data. When a workspace is active, Drush loads the workspace's revision of each entity, not the Live revision.

### Config Export

Workspace definitions live in config:

```bash
find /path/to/config -name 'workspaces.workspace.*.yml'
```

Each file contains:

```yaml
id: spring_campaign
label: Spring Campaign
parent: null
uid: 1
created: 1709251200
```

Export all workspace config:

```bash
for wf in $(drush config:list | grep workspaces.workspace); do
  drush config:get "$wf" --format=yaml > "export/${wf}.yml"
done
```

### Migration Implications

Ask this question before exporting: **Do you need staged/draft workspace content, or only what's published?**

Two paths:

| Scenario | What to Export | How |
|---|---|---|
| Published content only | Export from Live workspace | Default behavior. No workspace switching needed. The Live revision of each entity is the published version. |
| Staged content matters | Export from Live, then from each named workspace | Activate each workspace in turn and export. Tag each export with the workspace name so the target platform knows which content was staged vs. live. |

Most migrations only need Live. Staged content is work-in-progress. But if the migration must preserve editorial pipelines (e.g., a campaign launching next week), capture the workspace content and document which workspace it came from.

The `workspace_association` table tells you exactly how much staged content exists. Query it first to decide:

```sql
-- Quick check: is there anything staged?
SELECT workspace, target_entity_type_id, COUNT(*) AS pending
FROM workspace_association
GROUP BY workspace, target_entity_type_id
ORDER BY workspace;
```

If this returns zero rows, no content is staged. Export from Live and move on.
