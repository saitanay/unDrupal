# Skill 17: Users, Profiles, and Custom User Fields

Export user accounts, roles, profile entities, user pictures, and custom user fields from a Drupal site. Produces a complete user dataset for rebuilding identity and account data on the target platform.

Run Skill 01 (Site Audit) first. You need the Drupal version and available access methods. Run Skill 10 (Roles and Permissions) first if you need the role definitions and permission matrix. This skill exports users and their role assignments, not the role definitions themselves.

## Security Warning

User data is sensitive. Follow these rules throughout this skill:

1. Never commit password hashes to a public repository. Store user exports in a directory excluded by `.gitignore`.
2. Sanitize email addresses in development and staging exports. Replace real addresses with generated ones (e.g. `user_{uid}@example.com`) unless the export targets a production migration.
3. Strip or mask IP addresses in access logs and session data.
4. GDPR and privacy laws may require user consent before exporting personal data. Confirm with the site owner before exporting.
5. Encrypt export files at rest if they contain real email addresses, names, or password hashes. Use `gpg` or `age` for file-level encryption.

---

## Prerequisites

Same access methods as Skill 01. Each method exposes different parts of the user picture:

| Access method | What it unlocks |
|---|---|
| **Drush** | User list, role assignments, field values, password hash format detection |
| **Database** | Everything: accounts, hashes, custom fields, profile entities, pictures, sessions |
| **Config directory** (YAML) | User field definitions and profile type configs. No user data. |
| **JSON:API** (authenticated) | User accounts and fields. Restricted by permissions. Anonymous access typically blocked. |

---

## 1. User Account Data

### 1a. Core User Fields (D8/D9/D10/D11)

User data lives in two tables. The `users` table holds the bare minimum. The `users_field_data` table holds all translatable and non-translatable properties.

**`users` table:**

| Column | Type | Notes |
|---|---|---|
| `uid` | int | Primary key. uid 0 = anonymous, uid 1 = superadmin. |
| `uuid` | varchar(128) | Globally unique identifier. |
| `langcode` | varchar(12) | Default language of the user entity. |

**`users_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `uid` | int | Foreign key to `users.uid`. |
| `langcode` | varchar(12) | Language of this row. Multilingual sites have one row per language per user. |
| `preferred_langcode` | varchar(12) | Language the user prefers for UI. |
| `preferred_admin_langcode` | varchar(12) | Language for admin pages. NULL = use preferred_langcode. |
| `name` | varchar(60) | Username. Unique across the site. |
| `pass` | varchar(255) | Password hash. See Section 5. |
| `mail` | varchar(254) | Email address. |
| `timezone` | varchar(32) | IANA timezone string (e.g. `America/New_York`). |
| `status` | tinyint | 0 = blocked, 1 = active. |
| `created` | int | UNIX timestamp. Account creation time. |
| `changed` | int | UNIX timestamp. Last profile update. |
| `access` | int | UNIX timestamp. Last page access. 0 = never logged in. |
| `login` | int | UNIX timestamp. Last login. 0 = never logged in. |
| `init` | varchar(254) | Email address used at registration. May differ from current `mail`. |
| `default_langcode` | tinyint | 1 = this row is the default translation. |

Export query:

```sql
SELECT
  u.uid,
  u.uuid,
  ufd.name,
  ufd.mail,
  ufd.status,
  ufd.created,
  ufd.changed,
  ufd.access,
  ufd.login,
  ufd.init,
  ufd.timezone,
  ufd.langcode,
  ufd.preferred_langcode,
  ufd.preferred_admin_langcode,
  ufd.default_langcode
FROM users u
JOIN users_field_data ufd ON u.uid = ufd.uid
WHERE ufd.default_langcode = 1
ORDER BY u.uid;
```

Skip uid 0 (anonymous placeholder) in the export unless the target platform needs it:

```sql
-- Add to WHERE clause:
AND u.uid > 0
```

Total user count:

```sql
SELECT COUNT(*) AS total_users FROM users WHERE uid > 0;
SELECT status, COUNT(*) AS count FROM users_field_data
WHERE uid > 0 AND default_langcode = 1
GROUP BY status;
```

### 1b. Core User Fields (D7)

D7 stores everything in a single `users` table.

**`users` table (D7):**

| Column | Type | Notes |
|---|---|---|
| `uid` | int | Primary key. uid 0 = anonymous, uid 1 = superadmin. |
| `name` | varchar(60) | Username. |
| `pass` | varchar(128) | Password hash (phpass). See Section 5. |
| `mail` | varchar(254) | Email address. |
| `theme` | varchar(255) | User-selected theme. Empty = site default. |
| `signature` | varchar(255) | User signature text. |
| `signature_format` | varchar(255) | Text format for signature. |
| `created` | int | UNIX timestamp. |
| `access` | int | UNIX timestamp. Last page access. |
| `login` | int | UNIX timestamp. Last login. |
| `status` | tinyint | 0 = blocked, 1 = active. |
| `timezone` | varchar(32) | IANA timezone string. |
| `language` | varchar(12) | Preferred language. |
| `picture` | int | File ID (fid) referencing `file_managed` table. 0 = no picture. |
| `init` | varchar(254) | Email at registration. |
| `data` | longblob | PHP-serialized array of misc user data (contact form settings, etc.). |

Export query:

```sql
SELECT
  uid, name, mail, status, created, access, login,
  timezone, language, picture, init, signature, theme, data
FROM users
WHERE uid > 0
ORDER BY uid;
```

The `data` column needs PHP unserialization. It often contains:

- `contact`: 1 or 0 (personal contact form enabled)
- `overlay`: 1 or 0 (overlay module preference)
- Custom module data stored via `user_save()`

```php
// Decode the data column
$user_data = unserialize($row['data']);
```

---

## 2. User Role Assignments

### 2a. D8/D9/D10/D11

Role assignments live in the `user__roles` table. This is a standard field storage table for the `roles` base field on the user entity.

```sql
SELECT
  ur.entity_id AS uid,
  ur.roles_target_id AS role_id
FROM user__roles ur
ORDER BY ur.entity_id, ur.roles_target_id;
```

Join with user data for a complete picture:

```sql
SELECT
  ufd.uid,
  ufd.name,
  ufd.mail,
  ufd.status,
  GROUP_CONCAT(ur.roles_target_id ORDER BY ur.roles_target_id SEPARATOR ', ') AS roles
FROM users_field_data ufd
LEFT JOIN user__roles ur ON ufd.uid = ur.entity_id
WHERE ufd.uid > 0 AND ufd.default_langcode = 1
GROUP BY ufd.uid, ufd.name, ufd.mail, ufd.status
ORDER BY ufd.uid;
```

Note: the `authenticated` role is implicit for all users with uid > 0. It does not appear in `user__roles`. The `anonymous` role applies only to uid 0. Neither is stored as a role assignment.

### 2b. D7

D7 uses a `users_roles` table:

```sql
SELECT uid, rid FROM users_roles ORDER BY uid, rid;
```

Map `rid` values to role names:

```sql
SELECT
  u.uid,
  u.name,
  u.mail,
  u.status,
  GROUP_CONCAT(r.name ORDER BY r.name SEPARATOR ', ') AS roles
FROM users u
LEFT JOIN users_roles ur ON u.uid = ur.uid
LEFT JOIN role r ON ur.rid = r.rid
WHERE u.uid > 0
GROUP BY u.uid, u.name, u.mail, u.status
ORDER BY u.uid;
```

Same implicit role behavior: `authenticated user` (rid 2) is implicit for all uid > 0. `anonymous user` (rid 1) applies to uid 0.

### 2c. Via Drush (D8+)

```bash
# List all users with roles
drush user:list --format=json

# Filter by role
drush user:list --roles=content_editor --format=json

# Single user details
drush user:information admin --format=json
```

`drush user:list` returns JSON keyed by uid:

```json
{
  "1": {
    "uid": "1",
    "name": "admin",
    "mail": "admin@example.com",
    "status": "1",
    "roles": ["authenticated", "administrator"],
    "user_created": "1609459200"
  }
}
```

For large user bases (>10,000 users), Drush output may be slow or truncated. Use database queries instead.

---

## 3. Custom User Fields

The user entity is fieldable in D8+. Custom fields added to user profiles use the same field storage system as node fields (covered in Skill 04). The difference: `entity_type` is `user` and there is only one bundle (also called `user`).

### 3a. Discover Custom User Fields (D8+)

**Via config YAML:**

```bash
# Field storage definitions for user entity
ls config/sync/field.storage.user.*.yml

# Field instance definitions
ls config/sync/field.field.user.user.*.yml
# Pattern: field.field.user.user.{field_name}.yml
```

**Via Drush:**

```bash
# List field storage configs for user entity
drush config:list --prefix=field.storage.user --format=list

# List field instances
drush config:list --prefix=field.field.user.user --format=list

# Get a specific field definition
drush config:get field.field.user.user.field_bio --format=yaml
```

**Via database:**

```sql
-- All field storage configs for user entity
SELECT name FROM config WHERE name LIKE 'field.storage.user.%';

-- All field instance configs
SELECT name FROM config WHERE name LIKE 'field.field.user.user.%';
```

### 3b. Export Custom User Field Values (D8+)

Each custom field has a dedicated table named `user__field_{name}`. Structure is identical to node field tables:

```sql
-- Example: export a "bio" text field
SELECT
  entity_id AS uid,
  field_bio_value,
  field_bio_format
FROM user__field_bio
ORDER BY entity_id;
```

To discover all user field tables:

```sql
-- MySQL/MariaDB
SHOW TABLES LIKE 'user__field_%';

-- PostgreSQL
SELECT tablename FROM pg_tables
WHERE tablename LIKE 'user__field_%'
ORDER BY tablename;
```

Batch export all custom user fields joined to the user account:

```bash
#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-./_user_field_export}"
mkdir -p "$OUTPUT_DIR"

# Get all user field tables
TABLES=$(drush sql:query "SHOW TABLES LIKE 'user__field_%'" 2>/dev/null)

for table in $TABLES; do
  field_name="${table#user__}"
  echo "Exporting $field_name..."
  drush sql:query "
    SELECT entity_id AS uid, ${field_name}_value
    FROM $table
    ORDER BY entity_id;
  " > "$OUTPUT_DIR/${field_name}.csv"
done

echo "Exported to $OUTPUT_DIR"
```

For fields with multiple columns (e.g. address fields, link fields), inspect the table structure first:

```sql
DESCRIBE user__field_address;
```

Then include all value columns in the export.

### 3c. Discover and Export Custom User Fields (D7)

D7 stores user field data in `field_data_field_{name}` tables (shared with all entity types) and `field_revision_field_{name}` for revisions.

```sql
-- Find all fields attached to user entities
SELECT fc.field_name, fc.data AS field_config
FROM field_config fc
JOIN field_config_instance fci ON fc.id = fci.field_id
WHERE fci.entity_type = 'user'
ORDER BY fc.field_name;
```

Export field values:

```sql
-- Example: a text field on users
SELECT
  entity_id AS uid,
  field_bio_value,
  field_bio_format
FROM field_data_field_bio
WHERE entity_type = 'user'
ORDER BY entity_id;
```

The `entity_type = 'user'` filter is required because D7 field data tables store values for all entity types that share the field name.

---

## 4. User Pictures

### 4a. D8/D9/D10/D11

User pictures are stored as a field on the user entity. The field is `user_picture` by default (a base field, not a configurable field). The file reference lives in the `user__user_picture` table.

```sql
SELECT
  up.entity_id AS uid,
  up.user_picture_target_id AS file_id,
  up.user_picture_alt AS alt_text,
  up.user_picture_title AS title,
  up.user_picture_width AS width,
  up.user_picture_height AS height,
  fm.uri AS file_uri,
  fm.filename
FROM user__user_picture up
JOIN file_managed fm ON up.user_picture_target_id = fm.fid
ORDER BY up.entity_id;
```

The `file_uri` column contains a stream wrapper path like `public://pictures/2024-01/photo.jpg`. Resolve it to a filesystem path:

- `public://` maps to `sites/default/files/` (or whatever `file_public_path` is set to)
- `private://` maps to the private file path configured in `settings.php`

Check if the site has customized the user picture field or replaced it entirely:

```bash
# Is user_picture still a base field or overridden?
drush config:get field.field.user.user.user_picture --format=yaml 2>/dev/null
```

If no config exists for `field.field.user.user.user_picture`, the site uses the default base field definition. If config exists, it may have custom settings (allowed file extensions, max dimensions, file directory).

Some sites remove the default user picture field and add a custom image or media reference field instead. Check:

```sql
-- Look for image or media reference fields on the user entity
SELECT name FROM config
WHERE name LIKE 'field.field.user.user.%'
AND (
  data LIKE '%image%'
  OR data LIKE '%media%'
  OR data LIKE '%user_picture%'
);
```

### 4b. D7

D7 stores the user picture as a file ID in the `users.picture` column.

```sql
SELECT
  u.uid,
  u.picture AS file_id,
  fm.uri AS file_uri,
  fm.filename,
  fm.filemime,
  fm.filesize
FROM users u
JOIN file_managed fm ON u.picture = fm.fid
WHERE u.uid > 0 AND u.picture > 0
ORDER BY u.uid;
```

The file URI uses the same stream wrapper format. Default upload location is `public://pictures/`.

### 4c. Copy Picture Files

After exporting the file metadata, copy the actual files:

```bash
#!/usr/bin/env bash
set -euo pipefail

DRUPAL_ROOT="${1:-.}"
OUTPUT_DIR="${2:-./_user_pictures}"
PUBLIC_PATH="$DRUPAL_ROOT/sites/default/files"

mkdir -p "$OUTPUT_DIR"

# Read file URIs from export, resolve paths, copy
while IFS=$'\t' read -r uid file_uri; do
  # Convert public:// to filesystem path
  rel_path="${file_uri#public://}"
  src="$PUBLIC_PATH/$rel_path"
  if [ -f "$src" ]; then
    mkdir -p "$OUTPUT_DIR/$(dirname "$rel_path")"
    cp "$src" "$OUTPUT_DIR/$rel_path"
  else
    echo "MISSING: uid=$uid path=$src" >&2
  fi
done < <(drush sql:query "
  SELECT up.entity_id, fm.uri
  FROM user__user_picture up
  JOIN file_managed fm ON up.user_picture_target_id = fm.fid
  ORDER BY up.entity_id;
")

echo "Copied to $OUTPUT_DIR"
```

---

## 5. Password Hashes and Migration Strategy

Drupal passwords cannot be migrated directly to most target platforms. The hashing algorithms are Drupal-specific.

### 5a. D8/D9/D10/D11 Password Hashing

D8+ uses SHA-512 with a site-specific hash salt. The hash string starts with `$S$` followed by the iteration count indicator and the hash.

Format: `$S$<iteration_char><salt><hash>`

- The iteration count character is a base64-encoded log2 of the iteration count (default: 16384 iterations, represented by `D`).
- The salt is the first 8 characters after the iteration indicator.
- The hash is the remainder.

The hash salt is stored in `settings.php` as `$settings['hash_salt']`. Without this salt, the hashes are useless even to Drupal itself.

### 5b. D7 Password Hashing

D7 uses phpass (Portable PHP password hashing framework) with SHA-512. Same `$S$` prefix format.

Format is identical to D8: `$S$<iteration_char><salt><hash>`. The algorithm is the same. D7 and D8 password hashes are interoperable within Drupal.

Older D7 sites migrated from D6 may contain MD5 hashes (no prefix or `$P$` prefix). Drupal re-hashes these on next login. The `pass` column may contain a mix of formats.

Detect hash formats:

```sql
-- D7 or D8+
SELECT
  CASE
    WHEN pass LIKE '$S$%' THEN 'SHA-512 (phpass)'
    WHEN pass LIKE '$P$%' THEN 'Portable phpass MD5'
    WHEN LENGTH(pass) = 32 AND pass REGEXP '^[0-9a-f]+$' THEN 'Raw MD5 (D6 legacy)'
    WHEN pass = '' THEN 'Empty (external auth or blocked)'
    ELSE 'Unknown'
  END AS hash_type,
  COUNT(*) AS user_count
FROM users_field_data  -- use 'users' for D7
WHERE uid > 0
GROUP BY hash_type;
```

### 5c. Migration Strategies

No target platform outside Drupal will accept `$S$` hashes natively. Choose one of these strategies:

**Strategy 1: Force password reset for all users.**

The simplest approach. On the target platform, create all user accounts with no password or a random password. Send a password reset email to every user on launch day.

Pros: No hash migration. Clean start.
Cons: Users must act on the reset email. Some will not. Support burden on launch.

```bash
# Generate reset links in bulk (Drupal side, useful for testing)
drush sql:query "SELECT uid, name, mail FROM users_field_data WHERE uid > 0 AND status = 1" | \
  while IFS=$'\t' read -r uid name mail; do
    echo "$mail"
  done > active_user_emails.txt
```

**Strategy 2: Rehash on first login (if target supports custom auth).**

Export the Drupal password hashes and the site hash salt. On the target platform, implement a custom authentication check:

1. User submits username + password.
2. Target platform hashes the submitted password using Drupal's algorithm and the exported hash salt.
3. If it matches the stored Drupal hash, authenticate the user and rehash the password using the target platform's native algorithm.
4. Replace the stored hash with the native one.
5. On subsequent logins, use the native hash.

This requires the target platform to support custom authentication plugins or middleware. Libraries exist for validating Drupal hashes outside Drupal:

- PHP: Port the `PhpassHashedPassword` class from `core/lib/Drupal/Core/Password/PhpassHashedPassword.php`
- Python: `passlib.hash.drupal7` in the `passlib` library
- Node.js: `drupal-hash` npm package (verify before using; check maintenance status)
- Go: Implement SHA-512 with the same iteration logic (see Drupal source)

Pros: Transparent to users. No reset email needed.
Cons: Requires custom auth code on the target. Must store and protect the Drupal hash salt.

**Strategy 3: Dual-hash period.**

Combine strategies 1 and 2. Implement rehash-on-login for a migration period (30-90 days). After the period ends, force reset for any accounts that have not logged in and still carry Drupal hashes.

Pros: Most users migrate transparently. Stale accounts get cleaned up.
Cons: More implementation work. Needs a scheduled job to identify un-migrated accounts.

### 5d. Exporting Password Hashes (when using Strategy 2 or 3)

```sql
-- D8+
SELECT uid, name, mail, pass
FROM users_field_data
WHERE uid > 0 AND default_langcode = 1
ORDER BY uid;

-- D7
SELECT uid, name, mail, pass
FROM users
WHERE uid > 0
ORDER BY uid;
```

Also export the hash salt:

```bash
# From settings.php
grep 'hash_salt' sites/default/settings.php
```

Store the hash export and salt in an encrypted file. Never commit to version control.

```bash
# Encrypt with age
drush sql:query "SELECT uid, pass FROM users_field_data WHERE uid > 0" | \
  age -r age1xxxxxxxxx... -o user_hashes.age

# Encrypt with gpg
drush sql:query "SELECT uid, pass FROM users_field_data WHERE uid > 0" | \
  gpg --symmetric --cipher-algo AES256 -o user_hashes.gpg
```

---

## 6. Profile Module Entities

The contrib `profile` module (machine name: `profile`) creates separate fieldable entities attached to users. Sites use it when user data is complex enough to warrant multiple profile types (e.g. billing profile, shipping profile, professional profile).

### 6a. Detect Profile Module

```bash
# D8+
drush pm:list --filter=profile --format=json

# Check config
grep 'profile' config/sync/core.extension.yml
```

If the profile module is not installed, skip this section. All custom user data lives in user entity fields (Section 3).

### 6b. Profile Types (D8+)

Profile types are config entities. Each type defines a separate bundle of the `profile` entity.

```bash
# List profile type configs
ls config/sync/profile.type.*.yml

# Via Drush
drush config:list --prefix=profile.type --format=list
```

Profile type config structure:

```yaml
langcode: en
status: true
dependencies:
  enforced:
    module:
      - profile
id: customer
label: Customer profile
display_label: Customer information
description: 'Customer billing and shipping information.'
registration: false
multiple: false
roles: {  }
```

Key fields:

| Field | Meaning |
|---|---|
| `id` | Machine name. |
| `label` | Human-readable name. |
| `registration` | If `true`, this profile type's fields appear on the user registration form. |
| `multiple` | If `true`, a user can have more than one profile of this type. |
| `roles` | Array of role machine names. If non-empty, only users with these roles see this profile type. |

### 6c. Profile Fields

Profile entities use the same field system as nodes and users. Field configs follow the pattern:

```bash
# Field storage for profile entity
ls config/sync/field.storage.profile.*.yml

# Field instances per profile type
ls config/sync/field.field.profile.{type_name}.*.yml
```

### 6d. Export Profile Data

Profile entity data lives in these tables:

```sql
-- Profile entities (base table)
SELECT profile_id, type, uid, status, created, changed
FROM profile
ORDER BY type, uid;

-- Profile field data (translatable properties)
SELECT profile_id, type, uid, status, created, changed,
  langcode, default_langcode
FROM profile_field_data
ORDER BY type, uid;
```

Custom fields on profiles use `profile__field_{name}` tables:

```sql
-- Discover profile field tables
SHOW TABLES LIKE 'profile__field_%';

-- Export a profile field
SELECT
  entity_id AS profile_id,
  field_company_name_value
FROM profile__field_company_name
ORDER BY entity_id;
```

Join profiles to users:

```sql
SELECT
  p.profile_id,
  p.type AS profile_type,
  p.uid,
  ufd.name AS username,
  ufd.mail,
  p.status AS profile_status,
  p.created,
  p.changed
FROM profile p
JOIN users_field_data ufd ON p.uid = ufd.uid AND ufd.default_langcode = 1
ORDER BY p.type, p.uid;
```

For profile types with `multiple: true`, one user may have several profiles of the same type. The target platform needs a data model that supports this (e.g. a one-to-many relationship between user and address records).

### 6e. Batch Export Script

```bash
#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-./_profile_export}"
mkdir -p "$OUTPUT_DIR"

# Export profile types
for pt in $(drush config:list --prefix=profile.type --format=list 2>/dev/null); do
  drush config:get "$pt" --format=json > "$OUTPUT_DIR/${pt}.json"
done

# Export profile entities
drush sql:query "
  SELECT p.profile_id, p.type, p.uid, ufd.name, ufd.mail, p.status, p.created, p.changed
  FROM profile p
  JOIN users_field_data ufd ON p.uid = ufd.uid AND ufd.default_langcode = 1
  ORDER BY p.type, p.uid;
" > "$OUTPUT_DIR/profiles.csv"

# Export profile field tables
TABLES=$(drush sql:query "SHOW TABLES LIKE 'profile__field_%'" 2>/dev/null)
for table in $TABLES; do
  echo "Exporting $table..."
  drush sql:query "SELECT * FROM $table ORDER BY entity_id;" > "$OUTPUT_DIR/${table}.csv"
done

echo "Exported to $OUTPUT_DIR"
```

---

## 7. JSON:API Access

### 7a. Endpoint

The user entity is exposed at `/jsonapi/user/user` in D8+ with JSON:API enabled.

```bash
# Fetch users (authenticated request)
curl -s -u admin:password \
  'https://example.com/jsonapi/user/user?page[limit]=50' | python3 -m json.tool
```

### 7b. Permission Requirements

JSON:API user access depends on Drupal permissions:

| Permission | What it grants |
|---|---|
| `access user profiles` | View other users' profile pages. Required for JSON:API to return user data. |
| `administer users` | Full user admin. Returns all fields including mail, status, created, access, login. |
| `view field_FIELDNAME` | Required for field_permissions-protected fields. |

Without `administer users`, the response omits sensitive fields (mail, status, created, access, login, init). Only the username and custom fields are returned.

Anonymous users cannot access `/jsonapi/user/user` by default. The JSON:API module respects entity access. Test with an authenticated admin account.

```bash
# Check what fields are returned for the current user
curl -s -u admin:password \
  'https://example.com/jsonapi/user/user?page[limit]=1' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(list(d['data'][0]['attributes'].keys()), indent=2))"
```

### 7c. Include Relationships

```bash
# Users with roles and user picture
curl -s -u admin:password \
  'https://example.com/jsonapi/user/user?include=roles,user_picture&page[limit]=50'
```

### 7d. Pagination

JSON:API paginates. Follow the `next` link until it disappears:

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://example.com"
AUTH="admin:password"
OUTPUT_DIR="${1:-./_jsonapi_users}"
mkdir -p "$OUTPUT_DIR"

URL="$BASE_URL/jsonapi/user/user?page[limit]=50&include=roles,user_picture"
PAGE=0

while [ -n "$URL" ]; do
  echo "Fetching page $PAGE..."
  RESPONSE=$(curl -s -u "$AUTH" "$URL")
  echo "$RESPONSE" > "$OUTPUT_DIR/page_${PAGE}.json"

  URL=$(echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('links', {}).get('next', {}).get('href', ''))
" 2>/dev/null || true)

  PAGE=$((PAGE + 1))
done

echo "Fetched $PAGE pages to $OUTPUT_DIR"
```

---

## 8. Full Export Script

Combines user accounts, roles, custom fields, pictures, and profile entities into a single export directory.

```bash
#!/usr/bin/env bash
# Full user data export for migration
# Requires: Drush with database access
set -euo pipefail

OUTPUT_DIR="${1:-./_user_export}"
mkdir -p "$OUTPUT_DIR"/{accounts,fields,pictures,profiles}

echo "=== User Accounts ==="
drush sql:query "
  SELECT
    u.uid, u.uuid, ufd.name, ufd.mail, ufd.status,
    ufd.created, ufd.changed, ufd.access, ufd.login,
    ufd.init, ufd.timezone, ufd.langcode,
    ufd.preferred_langcode
  FROM users u
  JOIN users_field_data ufd ON u.uid = ufd.uid
  WHERE ufd.default_langcode = 1 AND u.uid > 0
  ORDER BY u.uid;
" > "$OUTPUT_DIR/accounts/users.csv"

echo "=== Role Assignments ==="
drush sql:query "
  SELECT entity_id AS uid, roles_target_id AS role
  FROM user__roles
  ORDER BY entity_id, roles_target_id;
" > "$OUTPUT_DIR/accounts/user_roles.csv"

echo "=== Custom User Fields ==="
FIELD_TABLES=$(drush sql:query "SHOW TABLES LIKE 'user__field_%'" 2>/dev/null)
for table in $FIELD_TABLES; do
  echo "  Exporting $table..."
  drush sql:query "SELECT * FROM $table ORDER BY entity_id;" \
    > "$OUTPUT_DIR/fields/${table}.csv"
done

echo "=== User Pictures ==="
drush sql:query "
  SELECT up.entity_id AS uid, fm.uri, fm.filename, fm.filemime,
    up.user_picture_alt, up.user_picture_width, up.user_picture_height
  FROM user__user_picture up
  JOIN file_managed fm ON up.user_picture_target_id = fm.fid
  ORDER BY up.entity_id;
" > "$OUTPUT_DIR/pictures/picture_metadata.csv"

echo "=== Profile Entities ==="
HAS_PROFILE=$(drush sql:query "SHOW TABLES LIKE 'profile'" 2>/dev/null)
if [ -n "$HAS_PROFILE" ]; then
  drush sql:query "
    SELECT profile_id, type, uid, status, created, changed
    FROM profile
    ORDER BY type, uid;
  " > "$OUTPUT_DIR/profiles/profiles.csv"

  PROFILE_TABLES=$(drush sql:query "SHOW TABLES LIKE 'profile__field_%'" 2>/dev/null)
  for table in $PROFILE_TABLES; do
    echo "  Exporting $table..."
    drush sql:query "SELECT * FROM $table ORDER BY entity_id;" \
      > "$OUTPUT_DIR/profiles/${table}.csv"
  done
else
  echo "  Profile module not installed. Skipping."
fi

echo "=== Summary ==="
TOTAL=$(wc -l < "$OUTPUT_DIR/accounts/users.csv" | tr -d ' ')
echo "Exported $TOTAL users to $OUTPUT_DIR"
echo ""
echo "WARNING: This export may contain PII (email addresses, names)."
echo "Do not commit to version control. Encrypt before storing."
```

---

## 9. D7 Full Export Script

```bash
#!/usr/bin/env bash
# Full user data export for D7 migration
set -euo pipefail

OUTPUT_DIR="${1:-./_user_export_d7}"
mkdir -p "$OUTPUT_DIR"/{accounts,fields,pictures}

echo "=== User Accounts ==="
drush sql:query "
  SELECT uid, name, mail, status, created, access, login,
    timezone, language, picture, init, theme, signature
  FROM users
  WHERE uid > 0
  ORDER BY uid;
" > "$OUTPUT_DIR/accounts/users.csv"

echo "=== Role Assignments ==="
drush sql:query "
  SELECT u.uid, r.name AS role_name
  FROM users_roles ur
  JOIN users u ON ur.uid = u.uid
  JOIN role r ON ur.rid = r.rid
  WHERE u.uid > 0
  ORDER BY u.uid, r.name;
" > "$OUTPUT_DIR/accounts/user_roles.csv"

echo "=== Custom User Fields ==="
# Find fields attached to user entity
FIELDS=$(drush sql:query "
  SELECT fc.field_name
  FROM field_config fc
  JOIN field_config_instance fci ON fc.id = fci.field_id
  WHERE fci.entity_type = 'user' AND fc.active = 1 AND fc.deleted = 0
  ORDER BY fc.field_name;
" 2>/dev/null)

for field in $FIELDS; do
  table="field_data_${field}"
  echo "  Exporting $table..."
  drush sql:query "
    SELECT * FROM $table WHERE entity_type = 'user' ORDER BY entity_id;
  " > "$OUTPUT_DIR/fields/${table}.csv" 2>/dev/null || echo "  Table $table not found"
done

echo "=== User Pictures ==="
drush sql:query "
  SELECT u.uid, fm.uri, fm.filename, fm.filemime, fm.filesize
  FROM users u
  JOIN file_managed fm ON u.picture = fm.fid
  WHERE u.uid > 0 AND u.picture > 0
  ORDER BY u.uid;
" > "$OUTPUT_DIR/pictures/picture_metadata.csv"

echo "=== Summary ==="
TOTAL=$(wc -l < "$OUTPUT_DIR/accounts/users.csv" | tr -d ' ')
echo "Exported $TOTAL users to $OUTPUT_DIR"
```

---

## 10. Export Checklist

Run through this checklist to confirm a complete extraction:

- [ ] All user accounts exported with uid, uuid (D8+), name, mail, status, created, access, login, timezone, langcode
- [ ] uid 0 (anonymous) excluded from account export
- [ ] uid 1 (superadmin) included and flagged in documentation
- [ ] Role assignments exported per user (Section 2)
- [ ] Implicit roles noted (authenticated for uid > 0, anonymous for uid 0)
- [ ] Custom user fields discovered (Section 3). All `user__field_*` tables exported.
- [ ] User pictures exported with file metadata and actual files copied (Section 4)
- [ ] Password hash format identified (Section 5). Migration strategy chosen and documented.
- [ ] Hash salt exported and encrypted (if using rehash strategy)
- [ ] Profile module checked (Section 6). If present: profile types, profile entities, and profile field data exported.
- [ ] Multi-profile types flagged (profiles with `multiple: true`)
- [ ] Email addresses sanitized in non-production exports
- [ ] Export files encrypted or stored outside version control
- [ ] Total user count verified: export row count matches `SELECT COUNT(*) FROM users WHERE uid > 0`

## 11. Migration Notes for Target Platforms

**Usernames**: Drupal allows spaces and special characters in usernames. Some target platforms restrict usernames to alphanumeric characters. Detect conflicts before migration:

```sql
SELECT uid, name FROM users_field_data
WHERE name REGEXP '[^a-zA-Z0-9._-]'
AND uid > 0;
```

**Email uniqueness**: Drupal enforces unique emails per user. Verify the target platform does the same. If not, duplicates from merged D7 + D8 exports can cause collisions.

**User status**: Drupal has two states: active (1) and blocked (0). Map to the target's equivalent. Some platforms have additional states (pending, suspended, deactivated). Decide how blocked users map.

**Timestamps**: Drupal stores UNIX timestamps as integers. Convert to the target platform's datetime format. Watch for timezone handling: `created`, `access`, and `login` are UTC epoch values, not user-local times.

**uid 1**: Drupal's superadmin (uid 1) bypasses all access checks regardless of roles. This is hardcoded, not configurable. The target platform needs an equivalent admin account. Do not assign uid 1's permissions based on its role assignments alone.

**Profile entities vs. user fields**: If the source site uses both custom user fields and profile entities, decide whether to merge them into a single user model on the target or maintain the separation. Profile entities with `multiple: true` require a one-to-many relationship (e.g. a user with multiple addresses).

**External authentication**: Sites using LDAP, SAML, OAuth, or CAS may have users with empty password hashes. These users authenticate through external providers. Check for external auth records:

```sql
-- D8+ authmap (externalauth module)
SELECT uid, provider, authname FROM authmap ORDER BY uid;

-- D7 authmap
SELECT uid, module, authname FROM authmap ORDER BY uid;
```

Users in the authmap table may need their external auth configuration recreated on the target platform rather than password migration.
