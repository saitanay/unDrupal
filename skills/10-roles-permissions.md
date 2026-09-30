# Skill 10: Roles, Permissions, and Access Control

Export user roles, permissions, and access control configuration from a Drupal site. Produces a complete map of who can do what, suitable for rebuilding access control on any target platform.

Run Skill 01 (Site Audit) first. You need to know the Drupal version and available access methods before starting.

## Prerequisites

Same access methods as Skill 01. Each method exposes different parts of the access control picture:

| Access method | What it unlocks |
|---|---|
| **Drush** | Role list, full permission matrix, node access rebuild status |
| **Database** | Everything: roles, permissions, node_access grants, field permissions, custom entity access |
| **Config directory** (YAML) | Role definitions and permissions (D8+). No runtime grant data. |
| **Admin UI** | Manual review only. Not scriptable. Last resort. |

---

## 1. Role Definitions

### 1a. Via Config YAML (D8/D9/D10/D11)

Roles are config entities stored as `user.role.{machine_name}.yml`. Each file follows this structure:

```yaml
uuid: 12345678-1234-1234-1234-123456789abc
langcode: en
status: true
dependencies: {  }
id: content_editor
label: Content Editor
weight: 3
is_admin: false
permissions:
  - 'access content'
  - 'create article content'
  - 'edit own article content'
  - 'delete own article content'
  - 'use text format full_html'
  - 'access toolbar'
```

Key fields:

| Field | Meaning |
|---|---|
| `id` | Machine name. Used in code and access checks. |
| `label` | Human-readable name shown in the admin UI. |
| `weight` | Sort order. Lower weight = higher in the list. No access control meaning. |
| `is_admin` | If `true`, this role bypasses all permission checks. The built-in `administrator` role typically has this set. |
| `permissions` | Flat list of permission strings granted to this role. |

Two roles always exist but may not have YAML files:

- `anonymous` (`user.role.anonymous.yml`): unauthenticated visitors
- `authenticated` (`user.role.authenticated.yml`): any logged-in user

Export all role configs:

```bash
# From the config sync directory
ls config/sync/user.role.*.yml

# Or via Drush
drush config:list --prefix=user.role --format=list
```

### 1b. Via Drush (D8+)

```bash
# List all roles with machine name and label
drush role:list --format=json
```

Output is a JSON object keyed by machine name:

```json
{
  "anonymous": {
    "label": "Anonymous user",
    "perms": ["access content", "search content"]
  },
  "authenticated": {
    "label": "Authenticated user",
    "perms": ["access content", "access toolbar", "search content"]
  },
  "content_editor": {
    "label": "Content Editor",
    "perms": ["access content", "create article content", "edit own article content"]
  }
}
```

To get permissions for a single role:

```bash
drush role:perm content_editor --format=json
```

### 1c. Via Database (D8+)

Roles live in the `config` table as serialized blobs:

```sql
-- All role config entities
SELECT name, data FROM config
WHERE name LIKE 'user.role.%'
ORDER BY name;
```

The `data` column is PHP-serialized. Unserialize each row to get the same structure as the YAML files.

### 1d. Via Database (D7)

D7 stores roles and permissions in two dedicated tables, not config.

```sql
-- All roles
SELECT rid, name, weight
FROM role
ORDER BY weight;
```

Default D7 roles:

| rid | name |
|---|---|
| 1 | anonymous user |
| 2 | authenticated user |
| 3+ | custom roles |

D7 has no `is_admin` flag on the role itself. Instead, a single role is designated as the admin role in the `user_admin_role` variable:

```sql
-- Which role is the admin role (D7)
SELECT value FROM variable WHERE name = 'user_admin_role';
-- Returns a PHP-serialized integer (the rid). Unserialize it.
```

```sql
-- All permissions per role (D7)
SELECT r.name AS role_name, rp.permission
FROM role_permission rp
JOIN role r ON rp.rid = r.rid
ORDER BY r.weight, rp.permission;
```

Each row is one permission string for one role. Aggregate by role to build the full matrix.

---

## 2. Full Permission Matrix

### 2a. Build the Matrix (D8+)

Collect every permission the site defines, then check which roles have each one.

```bash
# All available permissions with provider module
drush permission:list --format=json
```

This returns every permission string registered by every enabled module, including the module that provides it and the human-readable title. Cross-reference against the per-role permission lists from Step 1.

Build a matrix: rows = permissions, columns = roles, cells = granted/not granted.

### 2b. Build the Matrix (D7)

D7 has no `drush permission:list` equivalent. Extract permissions from the database:

```sql
-- All granted permissions across all roles
SELECT DISTINCT permission FROM role_permission ORDER BY permission;
```

This only shows granted permissions. To get the full list of available permissions (including ungranted ones), query the module `.info` files or scrape `/admin/people/permissions`. For migration purposes, granted permissions are sufficient.

### 2c. Export Format

Output the permission matrix as JSON:

```json
{
  "roles": {
    "anonymous": {
      "label": "Anonymous user",
      "is_admin": false,
      "weight": 0,
      "permissions": ["access content", "search content"]
    },
    "content_editor": {
      "label": "Content Editor",
      "is_admin": false,
      "weight": 3,
      "permissions": ["access content", "create article content", "edit own article content", "delete own article content"]
    },
    "administrator": {
      "label": "Administrator",
      "is_admin": true,
      "weight": 10,
      "permissions": []
    }
  },
  "drupal_version": 10,
  "total_permissions_available": 342,
  "total_roles": 5
}
```

Note: admin roles with `is_admin: true` may have an empty permissions array. They bypass checks entirely. Record this fact in the export. The target platform needs explicit permission grants for admin users.

---

## 3. Node Access Grants

Drupal's node access system controls view/update/delete access at the node level. Modules register grant records in the `node_access` table. Core populates a default fallback row. Custom modules add granular per-node grants.

### 3a. Check for Custom Node Access

```sql
-- Count grant records beyond the default
SELECT COUNT(*) AS grant_count FROM node_access
WHERE nid != 0;
```

If the count is 0, only the default grant exists (all published content visible to everyone). Skip to Section 4.

If the count is greater than 0, a module is writing custom grants.

```sql
-- Which realms are in use
SELECT realm, COUNT(*) AS grant_count,
  SUM(grant_view) AS can_view,
  SUM(grant_update) AS can_update,
  SUM(grant_delete) AS can_delete
FROM node_access
WHERE nid != 0
GROUP BY realm
ORDER BY grant_count DESC;
```

Common realms and the modules that create them:

| Realm | Module | Purpose |
|---|---|---|
| `all` | Core | Default fallback grant (nid=0). Published nodes visible to all. |
| `node_access_test` | Testing only | Ignore. |
| `content_access_author` | content_access | Per-content-type access by author |
| `content_access_rid` | content_access | Per-content-type access by role |
| `nodeaccess_rid` | nodeaccess | Per-node access by role |
| `nodeaccess_uid` | nodeaccess | Per-node access by user |
| `nodeaccess_author` | nodeaccess | Author-based access |
| `group_access_open` | group / og | Open group content |
| `group_access_closed` | group / og | Members-only group content |
| `taxonomy_access` | taxonomy_access_control | Term-based access |
| `workbench_access` | workbench_access | Section-based editorial access |

### 3b. Export Node Access Grants

```sql
-- Full grant table (may be large on sites with per-node grants)
SELECT nid, langcode, fallback, gid, realm, grant_view, grant_update, grant_delete
FROM node_access
WHERE nid != 0
ORDER BY realm, nid;
```

For large sites, export by realm:

```bash
drush sql:query "
  SELECT nid, gid, realm, grant_view, grant_update, grant_delete
  FROM node_access
  WHERE realm = 'content_access_rid'
  ORDER BY nid;
" > node_access_content_access_rid.csv
```

### 3c. Node Access in D7

Same table structure. The query is identical. D7 does not have the `langcode` or `fallback` columns:

```sql
SELECT nid, gid, realm, grant_view, grant_update, grant_delete
FROM node_access
WHERE nid != 0
ORDER BY realm, nid;
```

---

## 4. Field-Level Permissions

The `field_permissions` contrib module adds per-field access control. When installed, each field can have separate permissions for create, edit own, edit any, view own, view any.

### 4a. Detect Field Permissions

```bash
# Check if field_permissions is enabled
drush pm:list --filter=field_permissions --format=json
```

Or from config:

```bash
grep -l field_permissions config/sync/core.extension.yml
```

### 4b. Extract Field Permission Settings (D8+)

Field permissions are stored in the field storage config. Check each field storage config for a `third_party_settings.field_permissions` key:

```bash
# Find field storage configs with field_permissions settings
grep -rl 'field_permissions' config/sync/field.storage.*.yml
```

Each matching file contains:

```yaml
third_party_settings:
  field_permissions:
    permission_type: custom
```

The `permission_type` values:

| Value | Meaning |
|---|---|
| `public` | No field-level access control. Standard entity access applies. |
| `private` | Only the content author can view and edit the field value. |
| `custom` | Custom permissions are defined. Check the role configs for grants like `view field_myfield`, `edit field_myfield`. |

When `permission_type` is `custom`, the module registers these permissions:

- `create field_FIELDNAME` (set value when creating entity)
- `edit own field_FIELDNAME` (edit value on own entities)
- `edit field_FIELDNAME` (edit value on any entity)
- `view own field_FIELDNAME` (view value on own entities)
- `view field_FIELDNAME` (view value on any entity)

Search the role permission lists for these:

```bash
# Find all field permission grants across roles
grep -h 'field_' config/sync/user.role.*.yml | sort | uniq
```

### 4c. Field Permissions in D7

D7's field_permissions module stores settings differently. The permissions appear directly in the `role_permission` table:

```sql
-- All field-level permissions (D7)
SELECT r.name AS role_name, rp.permission
FROM role_permission rp
JOIN role r ON rp.rid = r.rid
WHERE rp.permission LIKE '%field_field_%'
   OR rp.permission LIKE 'create field_%'
   OR rp.permission LIKE 'edit field_%'
   OR rp.permission LIKE 'edit own field_%'
   OR rp.permission LIKE 'view field_%'
   OR rp.permission LIKE 'view own field_%'
ORDER BY rp.permission, r.name;
```

---

## 5. Group Module Permissions

The Group module (D8+) and Organic Groups (D7) create a parallel permission system. Groups are entities. Users join groups. Content belongs to groups. Access checks run against group membership and group-level roles, separate from site-wide roles.

### 5a. Detect Group Module

```bash
# D8+
drush pm:list --filter=group --format=json

# D7: check for og (Organic Groups)
drush pm:list --filter=og --format=json
```

### 5b. Group Module (D8+)

Group types define group-level roles and permissions. Each group type is a config entity.

```bash
# List group type configs
ls config/sync/group.type.*.yml

# List group role configs
ls config/sync/group.role.*.yml
```

Group role config structure:

```yaml
id: organization-admin
label: Organization Admin
group_type: organization
weight: 0
is_admin: false
scope: individual
permissions:
  - 'administer members'
  - 'create group_node:article entity'
  - 'delete any group_node:article entity'
  - 'update any group_node:article entity'
  - 'view group_node:article entity'
```

Three built-in scopes for each group type:

| Scope | Meaning |
|---|---|
| `outsider` | Authenticated users who are not members of the group |
| `insider` | Members of the group (default member role) |
| `individual` | Custom roles assigned to specific members |

Export all group roles:

```bash
# Via config directory
cat config/sync/group.role.*.yml

# Via Drush
drush config:list --prefix=group.role --format=list | while read name; do
  drush config:get "$name" --format=yaml
done
```

Group membership data:

```sql
-- Members per group type (D8+)
SELECT gc.type AS group_type, COUNT(*) AS member_count
FROM group_content_field_data gc
WHERE gc.type LIKE '%-group_membership'
GROUP BY gc.type
ORDER BY member_count DESC;

-- Content per group type
SELECT gc.type AS relationship_type, COUNT(*) AS content_count
FROM group_content_field_data gc
WHERE gc.type NOT LIKE '%-group_membership'
GROUP BY gc.type
ORDER BY content_count DESC;
```

Note: Group module 2.x (used on D9.4+/D10) renamed `group_content` to `group_relationship`. The table may be `group_relationship_field_data`:

```sql
-- Group module 2.x
SELECT gr.type AS relationship_type, COUNT(*) AS count
FROM group_relationship_field_data gr
GROUP BY gr.type
ORDER BY count DESC;
```

### 5c. Organic Groups (D7)

D7 uses the `og` (Organic Groups) module. Different architecture.

```sql
-- OG roles
SELECT rid, gid, group_type, name
FROM og_role
ORDER BY group_type, gid, rid;

-- OG permissions per role
SELECT r.name AS role_name, r.group_type, p.permission
FROM og_role_permission p
JOIN og_role r ON p.rid = r.rid
ORDER BY r.group_type, r.name, p.permission;

-- OG membership counts per group
SELECT gid, group_type, entity_type,
  COUNT(*) AS member_count
FROM og_membership
WHERE state = 1
GROUP BY gid, group_type, entity_type
ORDER BY member_count DESC;
```

OG default roles (per group):

| Role | Meaning |
|---|---|
| `non-member` | Users who are not group members |
| `member` | Standard group members |
| `administrator member` | Group admins |

---

## 6. Entity Access from Custom Modules

Custom modules can implement access hooks that override or supplement the standard permission system. These are invisible in config. You need code inspection or database clues to find them.

### 6a. Detect Custom Access Hooks (D8+)

Search the codebase for access hook implementations:

```bash
# Entity access hooks
grep -rl 'function .*_entity_access(' modules/custom/ --include='*.module'
grep -rl 'function .*_node_access(' modules/custom/ --include='*.module'
grep -rl 'function .*_ENTITY_TYPE_access(' modules/custom/ --include='*.module'

# Access check classes
grep -rl 'implements AccessInterface' modules/custom/ --include='*.php'
grep -rl 'extends AccessCheckInterface' modules/custom/ --include='*.php'
grep -rl 'class.*Access.*Check' modules/custom/ --include='*.php'

# Route-level access in routing.yml files
grep -rl '_custom_access' modules/custom/ --include='*.routing.yml'
grep -rl '_permission' modules/custom/ --include='*.routing.yml'
grep -rl '_role' modules/custom/ --include='*.routing.yml'

# Custom entity access control handlers
grep -rl 'extends EntityAccessControlHandler' modules/custom/ --include='*.php'
```

### 6b. Detect Custom Access Hooks (D7)

```bash
# Node access hooks
grep -rl 'function .*_node_access(' sites/all/modules/custom/ --include='*.module'
grep -rl 'function .*_node_grants(' sites/all/modules/custom/ --include='*.module'

# Entity access via Entity API
grep -rl 'function .*_entity_access(' sites/all/modules/custom/ --include='*.module'

# Menu access callbacks
grep -rl "'access callback'" sites/all/modules/custom/ --include='*.module'
```

### 6c. Document Custom Access Logic

For each custom access hook found, record:

1. The module name
2. The hook or class name
3. Which entity types it affects
4. A summary of the logic (read the function body)
5. Whether it grants access, denies access, or is neutral

This information cannot be auto-migrated. It becomes a specification for the target platform's access control implementation.

---

## 7. Content Type Permission Patterns

Drupal generates permissions for each content type. Extract the mapping.

### 7a. Standard Node Permissions (D8+)

For each content type `{type}`, Drupal registers:

- `create {type} content`
- `edit own {type} content`
- `edit any {type} content`
- `delete own {type} content`
- `delete any {type} content`

```bash
# Extract content-type-specific permissions from roles
for role_file in config/sync/user.role.*.yml; do
  role=$(basename "$role_file" .yml | sed 's/user.role.//')
  echo "=== $role ==="
  grep -E '(create|edit own|edit any|delete own|delete any) .* content' "$role_file" | sed "s/^  - '//;s/'$//"
done
```

### 7b. Standard Node Permissions (D7)

Same permission strings. Extract from the database:

```sql
SELECT r.name AS role_name, rp.permission
FROM role_permission rp
JOIN role r ON rp.rid = r.rid
WHERE rp.permission LIKE 'create % content'
   OR rp.permission LIKE 'edit own % content'
   OR rp.permission LIKE 'edit any % content'
   OR rp.permission LIKE 'delete own % content'
   OR rp.permission LIKE 'delete any % content'
ORDER BY rp.permission, r.name;
```

---

## 8. Workflow and Editorial Permissions

If the site uses Content Moderation (core, D8.5+) or Workbench Moderation (contrib), editorial transitions have their own permissions.

### 8a. Content Moderation (D8+)

```bash
# List workflow configs
ls config/sync/workflows.workflow.*.yml
```

Each workflow config contains transitions with permission requirements. The permission format is `use {workflow_id} transition {transition_id}`.

```bash
# Find moderation-related permissions in role configs
grep -h 'use .* transition' config/sync/user.role.*.yml | sort | uniq
```

### 8b. Workbench Moderation (D7)

```sql
-- Workbench moderation permissions
SELECT r.name AS role_name, rp.permission
FROM role_permission rp
JOIN role r ON rp.rid = r.rid
WHERE rp.permission LIKE 'moderate content from%'
ORDER BY r.name, rp.permission;
```

---

## 9. Export Checklist

Run through this checklist to confirm a complete extraction:

- [ ] All roles exported with machine name, label, weight, is_admin flag
- [ ] Full permission list per role
- [ ] Admin role(s) identified (is_admin flag or D7 user_admin_role variable)
- [ ] Anonymous and authenticated base permissions recorded
- [ ] Node access grants checked (Section 3). If custom grants exist, realms and modules documented.
- [ ] Field permissions checked (Section 4). If field_permissions module exists, per-field permission type and role grants exported.
- [ ] Group/OG permissions checked (Section 5). If present, group types, group roles, and group permissions exported.
- [ ] Custom access hooks audited (Section 6). Each hook documented with affected entity types and logic summary.
- [ ] Content type permission matrix built (Section 7)
- [ ] Editorial workflow permissions exported (Section 8), if applicable

## 10. Migration Notes for Target Platforms

Drupal's permission system is unusually granular. Most target platforms will not have a 1:1 equivalent for every Drupal permission string. Expect these translation challenges:

**Permission granularity**: Drupal defines separate permissions for create, edit-own, edit-any, delete-own, delete-any per content type. Many CMS platforms use coarser role-based access (e.g. "editor can edit all content"). Map Drupal's fine-grained permissions to the target's model. Document any access patterns that collapse.

**Admin bypass**: Drupal's `is_admin` flag grants all permissions implicitly. The target platform needs an explicit admin role with all permissions assigned, or an equivalent bypass mechanism.

**Node access grants**: These are runtime, per-node access records. No static config can represent them. The target platform needs either per-item access control or a query-time filter system. If the source site uses node access grants for section-based access, consider mapping to the target's taxonomy or role-based filtering.

**Field-level access**: Rare outside Drupal. If the target platform lacks field-level permissions, the migration may need to split restricted fields into separate content types or use a custom middleware layer.

**Group permissions**: Group-level roles and permissions form a second permission system parallel to site-wide roles. The target platform needs either native multi-tenant support or a custom group membership + permission check layer.

**Custom access hooks**: These are code, not config. Read the logic, write a specification, and implement equivalent logic on the target platform. There is no automated path.
