# Skill 19: Webform Definitions & Submissions Export

Extract form definitions and submitted data from the Drupal Webform module. Output: complete form structures with every element, conditional rule, handler, and setting, plus all submission data in a flat, portable format.

---

## When to Use This Skill

The site uses the `webform` contrib module (D8+) or the `webform` module in Drupal 7 (different architecture, covered separately below).

Signs the site uses Webform:

- `webform` appears in `core.extension.yml` or `drush pm:list --status=enabled`
- Config files matching `webform.webform.*.yml` exist
- The database has `webform_submission` and `webform_submission_data` tables
- Paths like `/form/{id}` or `/webform/{id}` resolve on the site

If none of these are present, check for `contact` module forms or `entityform` (D7 contrib). Those are different systems.

---

## Background: D7 vs D8+

### Drupal 7: webform (3.x / 4.x)

Drupal 7 Webform stores everything in the database. No YAML. No config entities.

| Table | Purpose |
|---|---|
| `webform` | One row per webform-enabled node. Stores confirmation message, redirect URL, submission limits, status. |
| `webform_component` | One row per form element. Columns: `nid`, `cid`, `pid` (parent component ID for nesting), `form_key`, `name`, `type`, `value` (default), `extra` (serialized PHP array with all settings), `required`, `weight` |
| `webform_conditional` | Conditional rules. Links source component to target component with an action (show/hide/set). |
| `webform_conditional_rules` | Individual conditions within a conditional group. |
| `webform_emails` | Email handlers. One row per email config per webform. |
| `webform_submissions` | Submission metadata: `sid`, `nid`, `uid`, `is_draft`, `submitted` (timestamp), `remote_addr` |
| `webform_submitted_data` | EAV table: `sid`, `cid`, `no` (delta for multi-value), `data` (the value) |

D7 element types: `textfield`, `textarea`, `email`, `number`, `select`, `radios`, `checkboxes`, `date`, `time`, `file`, `markup`, `fieldset`, `pagebreak`, `hidden`, `grid`.

### Drupal 8+ (5.x / 6.x)

Complete rewrite. Forms are config entities stored as YAML. Submissions stay in the database. The element system is plugin-based with 80+ element types.

---

## What to Extract

### 1. Form Definitions

Source: `webform.webform.{id}.yml`

#### Top-Level Properties

| Key | What It Is |
|---|---|
| `id` | Machine name |
| `title` | Human-readable form title |
| `description` | Admin description |
| `category` | Grouping category string |
| `status` | `open` or `closed` |
| `open` | Scheduled open date (ISO 8601) or empty |
| `close` | Scheduled close date or empty |
| `weight` | Sort weight |
| `uid` | Author user ID |
| `template` | Boolean. True if this is a reusable template, not a live form. |
| `archive` | Boolean. True if archived. |
| `elements` | YAML string containing all form elements (see below) |
| `css` | Custom CSS injected on the form page |
| `javascript` | Custom JS injected on the form page |
| `settings` | Form-level settings (confirmation, drafts, limits, etc.) |
| `access` | Access control rules per operation |
| `handlers` | Submission handlers (email, remote post, etc.) |
| `variants` | Form variants/overrides |

#### Elements

The `elements` key contains a YAML string (not nested YAML — a literal scalar that gets parsed separately). Each top-level key is an element machine name. Elements can nest inside containers and wizard pages.

Example structure:

```yaml
elements: |
  name:
    '#type': textfield
    '#title': 'Your name'
    '#required': true
    '#maxlength': 255
    '#placeholder': 'Jane Smith'
  email:
    '#type': email
    '#title': 'Email address'
    '#required': true
    '#pattern': '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
  topic:
    '#type': select
    '#title': Topic
    '#options':
      general: 'General inquiry'
      support: 'Technical support'
      billing: Billing
    '#empty_option': '- Select -'
    '#required': true
  details:
    '#type': textarea
    '#title': Details
    '#rows': 5
    '#states':
      visible:
        ':input[name="topic"]':
          value: support
  resume:
    '#type': managed_file
    '#title': 'Upload resume'
    '#file_extensions': 'pdf doc docx'
    '#max_filesize': '10'
    '#uri_scheme': private
  wizard_page_1:
    '#type': wizard_page
    '#title': 'Contact Info'
    name_in_wizard:
      '#type': textfield
      '#title': Name
    email_in_wizard:
      '#type': email
      '#title': Email
  wizard_page_2:
    '#type': wizard_page
    '#title': 'Your Message'
    message_body:
      '#type': textarea
      '#title': Message
```

#### Element Properties (Common)

Every element can have these properties. All prefixed with `#`.

| Property | Purpose |
|---|---|
| `#type` | Element plugin ID (see type reference below) |
| `#title` | Label shown to the user |
| `#description` | Help text below the element |
| `#description_display` | Where help text appears: `before`, `after`, `invisible`, `tooltip` |
| `#required` | Boolean |
| `#required_error` | Custom error message when required validation fails |
| `#default_value` | Default value (static or token) |
| `#placeholder` | Placeholder text |
| `#maxlength` | Max character count (textfield, email, tel, url) |
| `#pattern` | Regex pattern for validation |
| `#pattern_error` | Custom error for pattern mismatch |
| `#counter_type` | `character` or `word` for counter display |
| `#counter_maximum` | Max count for counter |
| `#min` | Minimum value (number, range) |
| `#max` | Maximum value |
| `#step` | Step increment (number, range) |
| `#multiple` | Integer. Number of allowed values. 0 = unlimited. Absent or 1 = single value. |
| `#prepopulate` | Boolean. Allow value to be set via query parameter. |
| `#disabled` | Boolean |
| `#readonly` | Boolean |
| `#access` | Boolean. False hides the element entirely. |
| `#private` | Boolean. Mark submissions for this element as private (admin-only). |
| `#admin_title` | Alternate label for admin UI / exports |
| `#title_display` | `before`, `after`, `inline`, `invisible`, `none` |
| `#wrapper_attributes` | HTML attributes on wrapper div (class, id, style) |
| `#attributes` | HTML attributes on the element itself |
| `#flex` | Flexbox weight when inside a `flexbox` container |
| `#states` | Conditional logic (see States section below) |
| `#access_create_roles` | Roles that see this element on new submissions |
| `#access_update_roles` | Roles that see this element when editing |
| `#access_view_roles` | Roles that see this element in submission view |

#### Element Type Reference

**Basic input:**

| Type | Description |
|---|---|
| `textfield` | Single-line text |
| `textarea` | Multi-line text |
| `email` | Email address with validation |
| `tel` | Telephone number |
| `url` | URL with validation |
| `number` | Numeric input |
| `range` | Slider |
| `hidden` | Hidden field |
| `value` | Hidden computed value (never shown, always submitted) |
| `color` | Color picker |
| `search` | Search input |
| `password` | Password field |
| `password_confirm` | Password with confirmation |

**Options / selection:**

| Type | Description | Key Properties |
|---|---|---|
| `select` | Dropdown | `#options`, `#empty_option`, `#empty_value`, `#multiple` |
| `radios` | Radio buttons | `#options`, `#options_display` (`one_column`, `two_columns`, `three_columns`, `side_by_side`, `buttons`, `buttons_horizontal`) |
| `checkboxes` | Checkbox group | `#options`, same display options as radios |
| `checkbox` | Single checkbox | `#return_value` (what gets submitted when checked) |
| `tableselect` | Table with selectable rows | `#options`, `#multiple`, `#js_select` |
| `webform_buttons` | Styled option buttons | `#options` |
| `webform_buttons_other` | Option buttons + other text | `#options`, `#other__placeholder` |
| `webform_radios_other` | Radios + other text | `#options`, `#other__type`, `#other__placeholder` |
| `webform_checkboxes_other` | Checkboxes + other text | `#options`, `#other__type` |
| `webform_select_other` | Select + other text | `#options` |
| `webform_entity_select` | Select populated from entities | `#target_type`, `#selection_handler`, `#selection_settings` |
| `webform_entity_checkboxes` | Checkboxes from entities | Same as above |
| `webform_entity_radios` | Radios from entities | Same as above |
| `webform_term_select` | Taxonomy term select | `#vocabulary`, `#breadcrumb`, `#tree_delimiter` |
| `webform_term_checkboxes` | Taxonomy checkboxes | `#vocabulary` |
| `webform_autocomplete` | Text with autocomplete | `#autocomplete_items` or `#autocomplete_existing` |
| `webform_rating` | Star rating | `#min`, `#max`, `#step` |
| `webform_scale` | Likert-style scale | `#min`, `#max`, `#min_text`, `#max_text` |
| `webform_toggle` | On/off toggle | `#toggle_size`, `#toggle_theme`, `#on_text`, `#off_text` |
| `webform_toggles` | Multiple toggles | `#options` |

**Date / time:**

| Type | Description | Key Properties |
|---|---|---|
| `date` | HTML5 date | `#min`, `#max`, `#step` |
| `datetime` | Date and time | `#date_date_min`, `#date_date_max`, `#date_time_min`, `#date_time_max` |
| `datelist` | Date as separate select fields | `#date_part_order`, `#date_year_range` |
| `webform_time` | Time only | `#time_format`, `#min`, `#max`, `#step` |

**File uploads:**

| Type | Description | Key Properties |
|---|---|---|
| `managed_file` | File upload | `#file_extensions`, `#max_filesize` (MB), `#uri_scheme` (`public` or `private`), `#file_name` (token pattern) |
| `webform_image_file` | Image upload | Same as managed_file plus `#max_resolution`, `#min_resolution` |
| `webform_audio_file` | Audio upload | `#file_extensions` defaults to audio types |
| `webform_video_file` | Video upload | `#file_extensions` defaults to video types |
| `webform_document_file` | Document upload | `#file_extensions` defaults to doc types |
| `webform_signature` | Signature pad | Canvas-based, stored as base64 PNG data URI |

**Composite elements (multi-part):**

| Type | Description |
|---|---|
| `webform_name` | Title, first, middle, last, suffix, degree |
| `webform_address` | Address line 1/2, city, state/province, postal code, country |
| `webform_contact` | Name + address + email + phone combined |
| `webform_link` | Title + URL pair |
| `webform_telephone` | Phone type + phone number |
| `webform_custom_composite` | Admin-defined composite with sub-elements |

Composite elements store values as keyed arrays. A `webform_address` submission looks like:

```yaml
address:
  address: '123 Main St'
  address_2: 'Suite 4'
  city: Springfield
  state_province: IL
  postal_code: '62704'
  country: US
```

**Containers and layout:**

| Type | Description |
|---|---|
| `container` | Generic wrapper div |
| `fieldset` | Fieldset with legend |
| `details` | Collapsible details/summary |
| `webform_flexbox` | Flexbox row for side-by-side elements |
| `webform_section` | Section with heading (h2-h6) |
| `webform_wizard_page` / `wizard_page` | Page in multi-step wizard |
| `webform_horizontal_rule` | Visual separator |

**Markup and display:**

| Type | Description |
|---|---|
| `markup` | Static HTML. Not a form input. Rendered but never submitted. |
| `webform_markup` | Same as markup (alias) |
| `webform_message` | Status/warning/error message box |
| `webform_computed_twig` | Computed value via Twig template |
| `webform_computed_token` | Computed value via token replacement |
| `processed_text` | Rendered text format content |
| `label` | Read-only label display |
| `webform_more` | Expandable "more" text |
| `webform_terms_of_service` | Checkbox with modal terms |

**Special:**

| Type | Description |
|---|---|
| `webform_likert` | Likert scale table. `#questions` (keyed labels), `#answers` (keyed labels) |
| `webform_mapping` | Key-value mapping table |
| `webform_table` | Table input. `#header` defines columns, child elements define rows. |
| `webform_table_row` | Row within a webform_table |
| `webform_table_sort` | Sortable table |
| `captcha` | CAPTCHA challenge (from captcha module) |
| `recaptcha` | reCAPTCHA (from recaptcha module) |
| `webform_same` | "Same as" checkbox that copies values between elements |
| `webform_actions` | Submit/draft/reset buttons container |

---

### 2. Conditional Logic (States)

The `#states` property controls element visibility, required status, and enabled/disabled state based on other elements. This is the Form API `#states` system, not Webform-specific.

#### Structure

```yaml
element_key:
  '#type': textfield
  '#title': 'Explain why'
  '#states':
    visible:
      ':input[name="reason"]':
        value: other
    required:
      ':input[name="reason"]':
        value: other
```

#### State Types

| State | Effect |
|---|---|
| `visible` / `invisible` | Show or hide the element |
| `enabled` / `disabled` | Enable or disable input |
| `required` / `optional` | Toggle required validation |
| `checked` / `unchecked` | Set checkbox state |
| `expanded` / `collapsed` | Toggle details element |
| `readwrite` / `readonly` | Toggle read-only |

#### Condition Selectors

The key under each state is a jQuery selector targeting the trigger element. Common patterns:

```yaml
# By element name
':input[name="field_name"]':
  value: 'some_value'

# Checkbox checked
':input[name="agree"]':
  checked: true

# Not empty
':input[name="other_text"]':
  filled: true

# Empty
':input[name="other_text"]':
  empty: true

# Select has specific value
'select[name="country"]':
  value: US
```

#### Multiple Conditions

AND logic (all conditions must be true):

```yaml
'#states':
  visible:
    ':input[name="role"]':
      value: manager
    ':input[name="department"]':
      value: engineering
```

OR logic (any condition triggers the state):

```yaml
'#states':
  visible:
    - ':input[name="contact_method"]':
        value: phone
    - ':input[name="contact_method"]':
        value: sms
```

XOR and complex boolean logic use nested arrays. In practice, most sites use simple AND/OR.

#### Webform-Specific Conditional Logic

Webform adds its own conditional system on top of Form API `#states`. Stored in the element's `#states` but with extended selector syntax:

```yaml
'#states':
  visible:
    ':input[name="topic"]':
      value:
        pattern: '^(support|billing)$'
```

Pattern matching, greater-than/less-than comparisons, and between ranges are Webform extensions.

---

### 3. Multi-Step Wizards

Wizard forms use `wizard_page` (or `webform_wizard_page`) elements as top-level containers. Each page groups its child elements.

```yaml
elements: |
  page_1:
    '#type': wizard_page
    '#title': 'Personal Info'
    '#prev_button_label': ''
    '#next_button_label': 'Continue'
    name:
      '#type': textfield
      '#title': Name
  page_2:
    '#type': wizard_page
    '#title': 'Job Details'
    '#prev_button_label': Back
    '#next_button_label': 'Review'
    position:
      '#type': textfield
      '#title': Position
  page_3:
    '#type': webform_wizard_page
    '#title': 'Review & Submit'
    '#prev_button_label': Back
```

Wizard settings in the form's `settings` key:

| Setting | Purpose |
|---|---|
| `wizard_progress_bar` | Show progress bar (boolean) |
| `wizard_progress_pages` | Show "Page X of Y" text |
| `wizard_progress_percentage` | Show percentage complete |
| `wizard_progress_link` | Allow clicking progress bar to navigate |
| `wizard_progress_states` | Show states in progress bar |
| `wizard_start_label` | Label for the first page in progress bar |
| `wizard_confirmation` | Show confirmation as final "page" in progress bar |
| `wizard_confirmation_label` | Label for confirmation step |
| `wizard_track` | Track wizard progress in URL fragment |
| `wizard_prev_button_label` | Global default for previous button |
| `wizard_next_button_label` | Global default for next button |

---

### 4. Confirmation Settings

Stored in `settings` within the form config.

| Setting | Purpose |
|---|---|
| `confirmation_type` | `page`, `inline`, `message`, `url`, `url_message`, `none` |
| `confirmation_url` | Redirect URL (when type is `url` or `url_message`) |
| `confirmation_title` | Page title for confirmation page |
| `confirmation_message` | HTML message shown after submission |
| `confirmation_attributes` | HTML attributes on the confirmation wrapper |
| `confirmation_back` | Show "Back to form" link (boolean) |
| `confirmation_back_label` | Label for back link |
| `confirmation_back_attributes` | Attributes on back link |
| `confirmation_exclude_query` | Exclude query string from confirmation URL |
| `confirmation_exclude_token` | Exclude tokens from confirmation message |

---

### 5. Handlers

Handlers define what happens when a form is submitted. Stored in the `handlers` key of the form config.

#### Structure

```yaml
handlers:
  email_handler:
    id: email
    handler_id: email_handler
    label: 'Send notification'
    notes: ''
    status: true
    conditions: {}
    weight: 0
    settings:
      states:
        - completed
      to_mail: admin@example.com
      to_options: {}
      bcc_mail: ''
      cc_mail: ''
      from_mail: '[webform_submission:values:email:raw]'
      from_name: '[webform_submission:values:name:raw]'
      reply_to: ''
      subject: 'New submission: [webform_submission:values:topic:raw]'
      body: '[webform_submission:values]'
      excluded_elements: {}
      ignore_access: false
      exclude_empty: true
      exclude_empty_checkbox: false
      html: true
      attachments: false
      twig: false
      theme_name: ''
      parameters: {}
      debug: false
```

#### Handler Types

| Handler ID | Purpose | Key Settings |
|---|---|---|
| `email` | Send email on submission | `to_mail`, `from_mail`, `subject`, `body`, `cc_mail`, `bcc_mail`, `states` (which submission states trigger it), `html`, `attachments`, `excluded_elements` |
| `remote_post` | POST/PUT submission data to a URL | `method` (POST/PUT/GET/DELETE), `url`, `type` (json/form), `custom_data`, `custom_options`, `excluded_data`, `states` |
| `action` | Change submission values or state | `title`, `message`, `state` (sticky, locked, starred), `notes` |
| `log` | Log submission to dblog | `message`, `states` |
| `settings` | Override form settings per handler state | Various form setting overrides |
| `broken` | Placeholder for handlers whose module is missing | No settings |

Custom handlers from contrib or custom modules add their own handler IDs (`mailchimp`, `salesforce`, `stripe`, etc.). The handler `id` tells you which plugin class processes the submission.

#### Handler Conditions

Handlers can fire conditionally based on submitted values:

```yaml
handlers:
  conditional_email:
    id: email
    conditions:
      enabled:
        ':input[name="topic"]':
          value: billing
    settings:
      to_mail: billing@example.com
      # ...
```

Same `#states`-style syntax. The handler only fires when conditions are met.

#### Handler States

The `states` array in handler settings controls which submission lifecycle events trigger the handler:

| State | When |
|---|---|
| `completed` | Form submitted (not draft) |
| `updated` | Existing submission updated |
| `draft_created` | New draft saved |
| `draft_updated` | Existing draft updated |
| `converted` | Draft converted to completed |
| `deleted` | Submission deleted |

---

### 6. Form Settings

The `settings` key in the form config holds form-level behavior.

#### Draft Support

| Setting | Purpose |
|---|---|
| `draft` | `none`, `authenticated`, or `all` (who can save drafts) |
| `draft_multiple` | Boolean. Allow multiple drafts per user. |
| `draft_auto_save` | Boolean. Auto-save drafts periodically. |
| `draft_saved_message` | Message shown when draft is saved. |
| `draft_loaded_message` | Message shown when a saved draft is loaded. |

#### Submission Limits

| Setting | Purpose |
|---|---|
| `limit_total` | Max total submissions. Empty = unlimited. |
| `limit_total_interval` | Time window for total limit (seconds). Empty = lifetime. |
| `limit_total_message` | Message when total limit reached. |
| `limit_total_unique` | Boolean. Count unique submissions only. |
| `limit_user` | Max submissions per user. |
| `limit_user_interval` | Time window for per-user limit. |
| `limit_user_message` | Message when user limit reached. |
| `limit_user_unique` | Boolean. |
| `entity_limit_total` | Limit when form is attached to an entity (node). |
| `entity_limit_user` | Per-user limit per entity. |

#### Scheduling

| Setting | Purpose |
|---|---|
| `form_open` | Boolean. Override global open/close dates. |
| `form_close` | Boolean. |
| `form_open_message` | Message shown before open date. |
| `form_close_message` | Message shown after close date. |
| `form_exception_message` | Message for date exceptions. |

#### Submission Behavior

| Setting | Purpose |
|---|---|
| `form_submit_once` | Prevent duplicate submissions (boolean) |
| `form_submit_label` | Custom submit button text |
| `submission_label` | Label used in admin lists |
| `submission_log` | Log submission events (boolean) |
| `submission_access_denied` | What to show on access denied: `default`, `page`, `login`, `message` |
| `submission_exception_message` | Error message for failed submissions |
| `purge` | `none`, `completed`, `draft`, `all` — auto-purge setting |
| `purge_days` | Days before auto-purge |
| `results_disabled` | Boolean. When true, submissions are not saved to the database. Used with remote_post handlers. |
| `token_update` | Boolean. Allow anonymous users to update via token in URL. |
| `autofill` | Boolean. Remember previous form values for the user. |

---

### 7. Access Control

The `access` key defines who can do what with the form and its submissions.

```yaml
access:
  create:
    roles:
      - anonymous
      - authenticated
    users: []
    permissions: []
  view_any:
    roles:
      - administrator
    users: []
    permissions: []
  update_any:
    roles:
      - administrator
    users: []
    permissions: []
  delete_any:
    roles: []
    users: []
    permissions: []
  purge_any:
    roles: []
    users: []
    permissions: []
  view_own:
    roles:
      - authenticated
    users: []
    permissions: []
  update_own:
    roles:
      - authenticated
    users: []
    permissions: []
  delete_own:
    roles: []
    users: []
    permissions: []
  administer:
    roles: []
    users: []
    permissions: []
  test:
    roles: []
    users: []
    permissions: []
  configuration:
    roles: []
    users: []
    permissions: []
```

Operations: `create`, `view_any`, `update_any`, `delete_any`, `purge_any`, `view_own`, `update_own`, `delete_own`, `administer`, `test`, `configuration`.

Each operation specifies `roles` (array of role IDs), `users` (array of UIDs), and `permissions` (array of permission strings).

---

### 8. Variants

Variants override element properties based on conditions. Used for A/B testing, multi-language overrides, or per-node customization.

```yaml
variants:
  short_form:
    id: override
    variant_id: short_form
    label: 'Short form'
    notes: ''
    status: true
    weight: 0
    element_key: ''
    settings:
      elements: |
        details:
          '#access': false
        resume:
          '#access': false
```

Variant types:

| Type | Purpose |
|---|---|
| `override` | Override element properties. The `elements` setting contains partial YAML that merges on top of the base form. |

Variants are activated by query parameter (`?variant=short_form`), by the node that embeds the form, or programmatically.

---

## Submission Data

### Database Schema (D8+)

**`webform_submission` table** — one row per submission:

| Column | Type | Purpose |
|---|---|---|
| `sid` | INT (PK, auto-increment) | Submission ID |
| `webform_id` | VARCHAR(32) | Machine name of the form |
| `uuid` | VARCHAR(128) | UUID |
| `serial` | INT | Per-form sequential number (form-specific counter, not global) |
| `token` | VARCHAR(255) | Update token for anonymous users |
| `uri` | VARCHAR(2000) | Page URI where form was submitted |
| `created` | INT | Unix timestamp of creation |
| `completed` | INT | Unix timestamp of completion (0 if draft) |
| `changed` | INT | Unix timestamp of last change |
| `in_draft` | TINYINT | 1 = draft, 0 = completed |
| `current_page` | VARCHAR(128) | Current wizard page (for drafts) |
| `remote_addr` | VARCHAR(128) | IP address |
| `uid` | INT | User ID (0 for anonymous) |
| `langcode` | VARCHAR(12) | Language code |
| `entity_type` | VARCHAR(32) | Source entity type if form is embedded (e.g., `node`) |
| `entity_id` | VARCHAR(32) | Source entity ID |
| `locked` | TINYINT | Locked status |
| `sticky` | TINYINT | Starred/sticky flag |
| `notes` | TEXT | Admin notes |

**`webform_submission_data` table** — EAV structure, one row per value per submission:

| Column | Type | Purpose |
|---|---|---|
| `webform_id` | VARCHAR(32) | Form machine name |
| `sid` | INT | Submission ID (FK to webform_submission) |
| `name` | VARCHAR(128) | Element key (matches the element's machine name in the YAML) |
| `property` | VARCHAR(128) | Sub-property for composite elements (e.g., `city`, `state_province` for address). Empty string for simple elements. |
| `delta` | INT | Delta for multi-value elements (0-based index). 0 for single-value. |
| `value` | LONGTEXT | The submitted value |

**Reading composite elements**: A `webform_address` element named `home_address` produces rows like:

| sid | name | property | delta | value |
|---|---|---|---|---|
| 42 | home_address | address | 0 | 123 Main St |
| 42 | home_address | city | 0 | Springfield |
| 42 | home_address | state_province | 0 | IL |
| 42 | home_address | postal_code | 0 | 62704 |
| 42 | home_address | country | 0 | US |

**Reading multi-value elements**: A checkboxes element named `interests` with three selected values:

| sid | name | property | delta | value |
|---|---|---|---|---|
| 42 | interests | | 0 | coding |
| 42 | interests | | 1 | music |
| 42 | interests | | 2 | hiking |

### File Uploads

Files attached to webform submissions are managed file entities. The `webform_submission_data` value column stores the file ID (`fid`).

To resolve files:

```sql
-- Get file metadata for all uploads in a webform
SELECT
  wsd.sid,
  wsd.name AS element_key,
  fm.fid,
  fm.uuid,
  fm.filename,
  fm.uri,
  fm.filemime,
  fm.filesize,
  fm.created
FROM webform_submission_data wsd
JOIN file_managed fm ON fm.fid = wsd.value
JOIN webform_submission ws ON ws.sid = wsd.sid
WHERE ws.webform_id = 'TARGET_FORM_ID'
  AND wsd.name IN ('resume', 'attachment', 'photo')
ORDER BY wsd.sid, wsd.name;
```

The `uri` column contains the Drupal stream wrapper path (`public://webform/TARGET_FORM_ID/FILE.pdf` or `private://webform/TARGET_FORM_ID/FILE.pdf`). Resolve `public://` to `sites/default/files/` (or whatever the public file path is). Private files require Drush or direct filesystem access.

---

## Extraction Methods

### Method 1: Config YAML (D8+)

Best for form definitions. Requires exported config.

```bash
# Find all webform configs
find config/sync -name 'webform.webform.*.yml' | sort

# List just the form IDs
find config/sync -name 'webform.webform.*.yml' -exec basename {} .yml \; | sed 's/webform\.webform\.//'
```

Read each file. Parse the `elements` value as a separate YAML document.

### Method 2: Drush

```bash
# List all webforms
drush webform:list --format=json

# Export a single webform definition as YAML
drush config:get webform.webform.contact_form --format=yaml

# Export all webform configs
drush config:export --destination=/tmp/config-export

# Count submissions per form
drush sql:query "SELECT webform_id, COUNT(*) AS total FROM webform_submission GROUP BY webform_id ORDER BY total DESC"

# Export submissions for a specific form (CSV)
drush webform:export contact_form --exporter=delimited --destination=/tmp/contact_submissions.csv

# Export submissions with file attachments
drush webform:export contact_form --exporter=delimited --destination=/tmp/contact_export --attachments

# Export options for drush webform:export
# --exporter: delimited (CSV/TSV), table (HTML), yaml, json
# --delimiter: , (default), \t, |, ;
# --header-format: label (default), key
# --options-single-format: compact (value only) or separate (value + text)
# --options-multiple-format: compact or separate
# --entity-reference-items: id, title, url
# --excluded-columns: sid,serial,uuid,token,...
# --range-type: all, latest, sid, date
# --range-start: start SID or date
# --range-end: end SID or date
# --state: completed, draft, all
# --attachments: include file attachments in export directory
```

### Method 3: Database Queries (D8+)

For bulk submission export when Drush is unavailable.

```sql
-- All form definitions (the elements column contains the YAML)
SELECT id, title, status, elements, settings
FROM config
WHERE name LIKE 'webform.webform.%';

-- Submission metadata for one form
SELECT
  sid, serial, uuid, token, uri,
  FROM_UNIXTIME(created) AS created_at,
  FROM_UNIXTIME(completed) AS completed_at,
  FROM_UNIXTIME(changed) AS changed_at,
  in_draft, current_page, remote_addr, uid, langcode,
  entity_type, entity_id, locked, sticky, notes
FROM webform_submission
WHERE webform_id = 'TARGET_FORM_ID'
ORDER BY sid;

-- All submitted values for one form, pivoted with metadata
SELECT
  ws.sid,
  ws.serial,
  ws.uid,
  FROM_UNIXTIME(ws.created) AS created_at,
  FROM_UNIXTIME(ws.completed) AS completed_at,
  ws.remote_addr,
  ws.in_draft,
  wsd.name,
  wsd.property,
  wsd.delta,
  wsd.value
FROM webform_submission ws
JOIN webform_submission_data wsd ON wsd.sid = ws.sid AND wsd.webform_id = ws.webform_id
WHERE ws.webform_id = 'TARGET_FORM_ID'
ORDER BY ws.sid, wsd.name, wsd.delta;

-- Pivot simple (non-composite) values into columns
-- This only works for known element keys. Generate the query dynamically from the form definition.
SELECT
  ws.sid,
  ws.serial,
  FROM_UNIXTIME(ws.created) AS created_at,
  MAX(CASE WHEN wsd.name = 'name' THEN wsd.value END) AS name,
  MAX(CASE WHEN wsd.name = 'email' THEN wsd.value END) AS email,
  MAX(CASE WHEN wsd.name = 'topic' THEN wsd.value END) AS topic,
  MAX(CASE WHEN wsd.name = 'message' THEN wsd.value END) AS message
FROM webform_submission ws
JOIN webform_submission_data wsd ON wsd.sid = ws.sid AND wsd.webform_id = ws.webform_id
WHERE ws.webform_id = 'TARGET_FORM_ID'
  AND wsd.property = ''
GROUP BY ws.sid, ws.serial, ws.created
ORDER BY ws.sid;

-- Submission count and date range per form
SELECT
  webform_id,
  COUNT(*) AS total,
  SUM(in_draft) AS drafts,
  COUNT(*) - SUM(in_draft) AS completed,
  FROM_UNIXTIME(MIN(created)) AS earliest,
  FROM_UNIXTIME(MAX(created)) AS latest
FROM webform_submission
GROUP BY webform_id
ORDER BY total DESC;
```

### Method 4: Database Queries (D7)

```sql
-- All webform-enabled nodes
SELECT w.nid, n.title, w.confirmation, w.redirect_url, w.status,
       w.submit_limit, w.submit_interval, w.total_submit_limit, w.total_submit_interval
FROM webform w
JOIN node n ON n.nid = w.nid;

-- Components (elements) for one form
SELECT cid, pid, form_key, name, type, value, extra, required, weight
FROM webform_component
WHERE nid = TARGET_NID
ORDER BY weight, cid;
-- The 'extra' column is serialized PHP. Unserialize it to get element settings.

-- Submissions for one form
SELECT sid, uid, is_draft, submitted, remote_addr
FROM webform_submissions
WHERE nid = TARGET_NID
ORDER BY sid;

-- Submitted data for one form
SELECT ws.sid, wc.form_key, wsd.no AS delta, wsd.data AS value
FROM webform_submitted_data wsd
JOIN webform_submissions ws ON ws.sid = wsd.sid
JOIN webform_component wc ON wc.nid = wsd.nid AND wc.cid = wsd.cid
WHERE wsd.nid = TARGET_NID
ORDER BY wsd.sid, wc.form_key, wsd.no;

-- Email handlers
SELECT * FROM webform_emails WHERE nid = TARGET_NID;

-- Conditionals
SELECT wc.*, wcr.*
FROM webform_conditional wc
JOIN webform_conditional_rules wcr ON wcr.nid = wc.nid AND wcr.rgid = wc.rgid
WHERE wc.nid = TARGET_NID;
```

### Method 5: REST API (Webform REST Module)

Requires the `webform_rest` contrib module. Not installed by default.

```bash
# Get form definition
curl -s https://SITE/webform_rest/FORM_ID/fields?_format=json \
  -H "Authorization: Bearer TOKEN"

# Get submission list
curl -s "https://SITE/webform_rest/FORM_ID/submissions?_format=json&page=0" \
  -H "Authorization: Bearer TOKEN"

# Get single submission
curl -s https://SITE/webform_rest/FORM_ID/submission/SID?_format=json \
  -H "Authorization: Bearer TOKEN"

# Create a test submission (useful for verifying form structure)
curl -s -X POST https://SITE/webform_rest/submit?_format=json \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer TOKEN" \
  -d '{"webform_id": "FORM_ID", "name": "Test", "email": "test@example.com"}'
```

The Webform REST module requires explicit permission grants per form per operation. If you get 403s, the form's REST access is not configured.

---

## Export Procedure

### Step 1: Inventory

```bash
# Config approach
find config/sync -name 'webform.webform.*.yml' | wc -l

# Drush approach
drush webform:list --format=json | python3 -c "
import json, sys
forms = json.load(sys.stdin)
for fid, info in forms.items():
    print(f\"{fid}: {info.get('title', 'N/A')} (status: {info.get('status', 'N/A')})\"
"

# Database approach (D8+)
drush sql:query "
  SELECT webform_id, COUNT(*) AS submissions
  FROM webform_submission
  GROUP BY webform_id
  ORDER BY submissions DESC
"
```

### Step 2: Export Definitions

For each form, extract the full config YAML. Parse and validate the `elements` string separately.

```bash
# Export all webform configs to individual files
for config in $(drush config:list | grep '^webform\.webform\.'); do
  id=$(echo "$config" | sed 's/webform\.webform\.//')
  drush config:get "$config" --format=yaml > "export/webforms/definitions/${id}.yml"
done
```

### Step 3: Export Submissions

Prefer Drush `webform:export` when available. It handles composite elements, multi-value fields, and file paths.

```bash
# Export all submissions for every form
mkdir -p export/webforms/submissions

for config in $(drush config:list | grep '^webform\.webform\.'); do
  id=$(echo "$config" | sed 's/webform\.webform\.//')
  count=$(drush sql:query "SELECT COUNT(*) FROM webform_submission WHERE webform_id = '${id}'" 2>/dev/null | tr -d '[:space:]')
  if [ "$count" -gt 0 ]; then
    drush webform:export "$id" \
      --exporter=delimited \
      --header-format=key \
      --destination="export/webforms/submissions/${id}.csv" \
      --attachments
    echo "Exported ${id}: ${count} submissions"
  fi
done
```

Without Drush, use the database queries from Method 3 above. Dump to CSV with:

```bash
drush sql:query "
  SELECT ws.sid, ws.serial, ws.uid, ws.created, ws.completed,
         ws.in_draft, ws.remote_addr, wsd.name, wsd.property, wsd.delta, wsd.value
  FROM webform_submission ws
  JOIN webform_submission_data wsd ON wsd.sid = ws.sid AND wsd.webform_id = ws.webform_id
  WHERE ws.webform_id = 'TARGET_FORM_ID'
  ORDER BY ws.sid, wsd.name, wsd.delta
" --result-file=/tmp/TARGET_FORM_ID_data.csv
```

Post-process the EAV data into one-row-per-submission format using a script. The form definition tells you which element keys exist and whether they are composite or multi-value.

### Step 4: Export File Attachments

```bash
# List all files attached to webform submissions
drush sql:query "
  SELECT DISTINCT fm.uri, fm.filename, fm.filemime, fm.filesize
  FROM webform_submission_data wsd
  JOIN file_managed fm ON fm.fid = wsd.value
  JOIN webform_submission ws ON ws.sid = wsd.sid
  WHERE ws.webform_id = 'TARGET_FORM_ID'
    AND wsd.name IN (SELECT name FROM webform_submission_data WHERE value REGEXP '^[0-9]+$')
  ORDER BY fm.uri
"

# Copy public files
rsync -av sites/default/files/webform/ export/webforms/files/

# For private files, use Drush
drush webform:export TARGET_FORM_ID --attachments --destination=export/webforms/files/TARGET_FORM_ID/
```

### Step 5: Validate

Check that every element key in the definition has corresponding data rows (or is a container/markup type that does not submit data).

```bash
# Elements that should have submission data (not containers, not markup)
# Parse from definition YAML, filter out: wizard_page, container, fieldset,
# details, webform_flexbox, webform_section, markup, webform_markup,
# webform_message, webform_horizontal_rule, processed_text, label,
# webform_more, webform_actions

# Compare against actual data keys
drush sql:query "
  SELECT DISTINCT name
  FROM webform_submission_data
  WHERE webform_id = 'TARGET_FORM_ID'
  ORDER BY name
"
```

---

## Output Format

Produce two artifacts per form:

**1. Definition file** (`{form_id}.definition.yml`):

```yaml
id: contact_form
title: Contact Us
status: open
category: Contact
elements:
  - key: name
    type: textfield
    title: 'Your name'
    required: true
    maxlength: 255
  - key: email
    type: email
    title: 'Email address'
    required: true
  - key: topic
    type: select
    title: Topic
    required: true
    options:
      general: 'General inquiry'
      support: 'Technical support'
      billing: Billing
  - key: details
    type: textarea
    title: Details
    conditions:
      visible_when:
        field: topic
        equals: support
  - key: resume
    type: file
    title: 'Upload resume'
    allowed_extensions: 'pdf doc docx'
    max_size_mb: 10
wizard:
  enabled: false
  pages: []
confirmation:
  type: message
  message: 'Thank you for contacting us.'
handlers:
  - id: email_handler
    type: email
    to: admin@example.com
    subject: 'New submission: [topic]'
    conditions: {}
    states: [completed]
access:
  create: [anonymous, authenticated]
  view_own: [authenticated]
  administer: [administrator]
settings:
  draft: none
  submission_limit_total: null
  submission_limit_user: null
  results_disabled: false
```

**2. Submissions file** (`{form_id}.submissions.csv` or `.json`):

CSV with one row per submission. Column headers use element keys. Multi-value fields use `key.0`, `key.1`, etc. Composite fields use `key.property` (e.g., `address.city`, `address.state_province`). File fields contain the original filename and relative path to the exported file.

---

## Edge Cases

**Forms attached to nodes**: Webforms can be embedded as fields on content types via the `webform` field type. The submission records `entity_type` and `entity_id`. Export these columns to preserve the relationship between submissions and the content they were submitted from.

**Encrypted submissions**: The `webform_encrypt` module encrypts field values in `webform_submission_data`. Values are stored as encrypted blobs. You need the encryption key and the `encrypt` module's config to decrypt. Check for `third_party_settings.webform_encrypt` in element definitions.

**Computed elements**: `webform_computed_twig` and `webform_computed_token` elements generate values at render time. Their stored submission values are the computed result, not the template. Export both the template (from the definition) and stored values (from submissions).

**Prepopulated values**: Elements with `#prepopulate: true` accept values via query parameters. The definition tells you which elements allow this. The submitted values reflect whatever was actually submitted, prepopulated or not.

**Options from hooks**: Some select/radios/checkboxes elements use `#options` set to a callback ID (e.g., `country_codes`, `time_zones`). These reference Webform options config entities stored as `webform.webform_options.*.yml`. Export these config entities alongside the forms that reference them.

```bash
# Find all webform options configs
find config/sync -name 'webform.webform_options.*.yml' | sort

# Or via Drush
drush config:list | grep 'webform.webform_options'
```

**Multilingual forms**: Translated forms store translations in `config_translation` tables. Export translations via:

```bash
drush config:get webform.webform.TARGET_FORM_ID --format=yaml --langcode=es
```

**Submission purging**: If `purge` is set in form settings, old submissions may already be deleted. Check the setting and the actual submission date range to assess data completeness.

**Results disabled**: Forms with `results_disabled: true` do not save submissions to the database. Data only exists in the handler destinations (email inboxes, remote APIs). Flag these forms. There is nothing to export from Drupal.
