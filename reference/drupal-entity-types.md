# Drupal Entity Types and Database Tables

## Content Entities

Content entities store user-created data. They have database tables for base fields, revisions, and translations.

### Core Content Entities

#### node

The primary content entity. Articles, pages, landing pages, events, products in non-Commerce sites.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `node` | `nid` | `vid`, `type`, `uuid`, `langcode` |
| `node_field_data` | `(nid, langcode)` | `vid`, `type`, `title`, `uid`, `status`, `created`, `changed`, `promote`, `sticky`, `default_langcode` |
| `node_revision` | `vid` | `nid`, `langcode`, `revision_uid`, `revision_timestamp`, `revision_log` |
| `node_field_revision` | `(nid, vid, langcode)` | Same as `node_field_data` |
| `node__field_{name}` | `(entity_id, deleted, delta, langcode)` | `bundle`, `revision_id`, field value columns |
| `node_revision__field_{name}` | `(entity_id, revision_id, deleted, delta, langcode)` | Same |

#### taxonomy_term

Categorization vocabulary terms. Tags, categories, content types, locations.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `taxonomy_term_data` | `tid` | `vid` (revision_id), `uuid`, `langcode` |
| `taxonomy_term_field_data` | `(tid, langcode)` | `vid`, `name`, `description__value`, `description__format`, `weight`, `changed`, `default_langcode` |
| `taxonomy_term_revision` | `vid` | `tid`, `langcode`, `revision_created`, `revision_user`, `revision_log_message` |
| `taxonomy_term_field_revision` | `(tid, vid, langcode)` | Same as field_data |
| `taxonomy_term__parent` | `(entity_id, deleted, delta, langcode)` | `parent_target_id` (0 = root) |

#### media

Reusable media assets wrapping file entities. Images, documents, videos, remote video embeds, audio.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `media` | `mid` | `vid`, `bundle`, `uuid`, `langcode` |
| `media_field_data` | `(mid, langcode)` | `vid`, `bundle`, `name`, `thumbnail__target_id`, `thumbnail__alt`, `uid`, `status`, `created`, `changed` |
| `media_revision` | `vid` | `mid`, `langcode`, `revision_created`, `revision_user` |
| `media_field_revision` | `(mid, vid, langcode)` | Same as field_data |

#### file_managed

Raw file records. Not directly viewable. Referenced by media entities or file fields.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `file_managed` | `fid` | `uuid`, `uid`, `filename`, `uri`, `filemime`, `filesize`, `status`, `created`, `changed` |
| `file_usage` | `(fid, type, id, module)` | `count` |

No revision or translation tables.

#### users

User accounts. Drupal user 0 is "anonymous", user 1 is the superadmin.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `users` | `uid` | `uuid`, `langcode` |
| `users_field_data` | `(uid, langcode)` | `name`, `pass`, `mail`, `timezone`, `status`, `created`, `changed`, `access`, `login`, `init` |

No revision tables. Roles stored in `user__roles` field table.

#### comment

Threaded comments attached to any entity.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `comment` | `cid` | `uuid`, `comment_type`, `langcode` |
| `comment_field_data` | `(cid, langcode)` | `comment_type`, `pid` (parent comment), `entity_id`, `entity_type`, `field_name`, `uid`, `subject`, `name`, `mail`, `homepage`, `hostname`, `created`, `changed`, `status`, `thread` |

No revision tables by default.

#### block_content

Custom blocks (not to be confused with block placement config).

| Table | PK | Key Columns |
|-------|-----|-------------|
| `block_content` | `id` | `revision_id`, `type`, `uuid`, `langcode` |
| `block_content_field_data` | `(id, langcode)` | `revision_id`, `type`, `info` (admin label), `langcode`, `status`, `changed`, `reusable` |
| `block_content_revision` | `revision_id` | `id`, `langcode`, `revision_created`, `revision_user` |
| `block_content_field_revision` | `(id, revision_id, langcode)` | Same as field_data |

#### menu_link_content

Custom menu links (not system-generated ones).

| Table | PK | Key Columns |
|-------|-----|-------------|
| `menu_link_content` | `id` | `revision_id`, `bundle`, `uuid`, `langcode` |
| `menu_link_content_data` | `(id, langcode)` | `revision_id`, `bundle`, `title`, `description`, `menu_name`, `link__uri`, `link__title`, `link__options`, `external`, `rediscover`, `weight`, `expanded`, `enabled`, `parent` |
| `menu_link_content_revision` | `revision_id` | `id`, `langcode` |
| `menu_link_content_field_revision` | `(id, revision_id, langcode)` | Same as data table |

#### path_alias (D9+)

URL alias records. Replaces D7's `url_alias` table.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `path_alias` | `id` | `revision_id`, `uuid`, `langcode` |
| `path_alias_revision` | `revision_id` | `id`, `langcode`, `path`, `alias`, `status` |

### Contrib Content Entities

#### paragraph (Paragraphs module)

Reusable content components embedded in other entities via entity_reference_revisions fields.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `paragraphs_item` | `id` | `revision_id`, `type`, `uuid`, `langcode` |
| `paragraphs_item_field_data` | `(id, langcode)` | `revision_id`, `type`, `status`, `parent_id`, `parent_type`, `parent_field_name`, `behavior_settings`, `created`, `changed`, `default_langcode` |
| `paragraphs_item_revision` | `revision_id` | `id`, `langcode` |
| `paragraphs_item_field_revision` | `(id, revision_id, langcode)` | Same as field_data |

Key: `parent_type` + `parent_id` + `parent_field_name` let you trace a paragraph back to its host entity.

#### redirect (Redirect module)

HTTP redirects.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `redirect` | `rid` | `uuid`, `hash`, `type`, `uid`, `redirect_source__path`, `redirect_source__query`, `redirect_redirect__uri`, `redirect_redirect__title`, `status_code`, `language`, `created` |

No revision tables.

#### webform_submission (Webform module)

| Table | PK | Key Columns |
|-------|-----|-------------|
| `webform_submission` | `sid` | `webform_id`, `uuid`, `uri`, `created`, `completed`, `changed`, `in_draft`, `current_page`, `remote_addr`, `uid`, `langcode`, `entity_type`, `entity_id`, `sticky`, `locked`, `notes` |
| `webform_submission_data` | `(webform_id, sid, name, property, delta)` | `value` |

Submission data uses an EAV (entity-attribute-value) pattern rather than field tables.

#### content_moderation_state

Tracks editorial workflow state per entity revision.

| Table | PK | Key Columns |
|-------|-----|-------------|
| `content_moderation_state` | `id` | `revision_id`, `uuid`, `langcode` |
| `content_moderation_state_field_data` | `(id, langcode)` | `content_entity_type_id`, `content_entity_id`, `content_entity_revision_id`, `moderation_state`, `workflow` |
| `content_moderation_state_revision` | `revision_id` | `id`, `langcode` |
| `content_moderation_state_field_revision` | `(id, revision_id, langcode)` | Same as field_data |

#### shortcut

Toolbar shortcuts.

| Table | PK |
|-------|-----|
| `shortcut` | `id` |
| `shortcut_field_data` | `(id, langcode)` |

#### aggregator_feed / aggregator_item (pre-D10.1)

RSS feed aggregation. Removed in Drupal 10.1.

| Table | PK |
|-------|-----|
| `aggregator_feed` | `fid` |
| `aggregator_item` | `iid` |

#### contact_message

Contact form submissions. Not stored by default (sent as email). If the `contact_storage` contrib module is installed, they persist.

## Config Entities

Config entities are stored as YAML blobs in the `config` table. They have no dedicated database tables. Read them from `config` or from exported YAML files in `sites/default/files/config_*/` or a config split directory.

### How to Query Config Entities

```sql
-- List all node types
SELECT name, data FROM config WHERE name LIKE 'node.type.%';

-- List all taxonomy vocabularies
SELECT name, data FROM config WHERE name LIKE 'taxonomy.vocabulary.%';

-- List all views
SELECT name, data FROM config WHERE name LIKE 'views.view.%';

-- List all media types
SELECT name, data FROM config WHERE name LIKE 'media.type.%';

-- List all field storage definitions
SELECT name, data FROM config WHERE name LIKE 'field.storage.%';

-- List all field instance definitions
SELECT name, data FROM config WHERE name LIKE 'field.field.%';
```

### Config Entity Types

| Config Entity | Config Name Pattern | Key Properties |
|---------------|--------------------|-----------------| 
| `node_type` | `node.type.{bundle}` | `type`, `name`, `description`, `new_revision`, `display_submitted` |
| `taxonomy_vocabulary` | `taxonomy.vocabulary.{vid}` | `vid`, `name`, `description`, `weight` |
| `media_type` | `media.type.{bundle}` | `id`, `label`, `source`, `source_configuration` |
| `comment_type` | `comment.type.{bundle}` | `id`, `label`, `target_entity_type_id` |
| `block_content_type` | `block_content.type.{bundle}` | `id`, `label`, `description`, `revision` |
| `image_style` | `image.style.{name}` | `name`, `label`, `effects` (list of transforms) |
| `responsive_image_style` | `responsive_image.style.{name}` | `id`, `label`, `image_style_mappings`, `fallback_image_style` |
| `view` | `views.view.{name}` | `id`, `label`, `base_table`, `display` (array of display plugins) |
| `filter_format` | `filter.format.{name}` | `format`, `name`, `filters` (array of filter plugins) |
| `editor` | `editor.editor.{format}` | `format`, `editor` (ckeditor5, ckeditor), `settings` |
| `user_role` | `user.role.{rid}` | `id`, `label`, `permissions`, `is_admin`, `weight` |
| `workflow` | `workflows.workflow.{name}` | `id`, `label`, `type`, `type_settings` (states, transitions) |
| `search_api_index` | `search_api.index.{name}` | `id`, `name`, `server`, `datasource_settings`, `field_settings`, `processor_settings` |
| `search_api_server` | `search_api.server.{name}` | `id`, `name`, `backend`, `backend_config` |
| `webform` | `webform.webform.{id}` | `id`, `title`, `elements` (YAML), `settings`, `handlers` |
| `menu` | `system.menu.{name}` | `id`, `label`, `description`, `locked` |
| `field_storage_config` | `field.storage.{entity_type}.{field_name}` | `entity_type`, `field_name`, `type`, `cardinality`, `settings` |
| `field_config` | `field.field.{entity_type}.{bundle}.{field_name}` | `entity_type`, `bundle`, `field_name`, `field_type`, `label`, `required`, `settings` |

## Commerce Entities (Drupal Commerce 2.x)

All commerce entities are revisionable.

| Entity | Base Table | Data Table | Revision Table | Key Columns |
|--------|-----------|------------|----------------|-------------|
| `commerce_store` | `commerce_store` | `commerce_store_field_data` | `commerce_store_revision` | `store_id`, `type`, `name`, `mail`, `default_currency`, `is_default`, `uid` |
| `commerce_product` | `commerce_product` | `commerce_product_field_data` | `commerce_product_revision` | `product_id`, `type`, `title`, `stores` (via field table), `uid`, `status` |
| `commerce_product_variation` | `commerce_product_variation` | `commerce_product_variation_field_data` | `commerce_product_variation_revision` | `variation_id`, `type`, `product_id`, `sku`, `title`, `price__number`, `price__currency_code`, `status` |
| `commerce_order` | `commerce_order` | `commerce_order_field_data` | none by default | `order_id`, `type`, `order_number`, `store_id`, `uid`, `mail`, `ip_address`, `state`, `total_price__number`, `total_price__currency_code`, `placed`, `completed` |
| `commerce_order_item` | `commerce_order_item` | `commerce_order_item_field_data` | none by default | `order_item_id`, `type`, `order_id`, `purchased_entity` (via field), `title`, `quantity`, `unit_price__number`, `unit_price__currency_code`, `total_price__number`, `total_price__currency_code` |
| `commerce_payment` | `commerce_payment` | `commerce_payment_field_data` | none | `payment_id`, `type`, `payment_gateway`, `payment_gateway_mode`, `payment_method`, `order_id`, `remote_id`, `remote_state`, `amount__number`, `amount__currency_code`, `refunded_amount__number`, `state` |
| `commerce_payment_method` | `commerce_payment_method` | `commerce_payment_method_field_data` | none | `payment_method_id`, `type`, `uid`, `payment_gateway`, `payment_gateway_mode`, `remote_id`, `card_type`, `card_number`, `expires` |
| `commerce_shipment` | `commerce_shipment` | `commerce_shipment_field_data` | none | `shipment_id`, `type`, `order_id`, `shipping_method`, `shipping_service`, `shipping_profile`, `tracking_code`, `amount__number`, `state` |
| `commerce_promotion` | `commerce_promotion` | `commerce_promotion_field_data` | none | `promotion_id`, `type`, `name`, `display_name`, `order_types`, `stores`, `offer`, `conditions`, `start_date`, `end_date`, `usage_limit`, `status` |
| `commerce_promotion_coupon` | `commerce_promotion_coupon` | none | none | `id`, `type`, `promotion_id`, `code`, `usage_limit`, `status` |

### Commerce Price Fields

Price fields use a composite column pattern:

```
{field_name}__number        -- decimal string, e.g. "29.99"
{field_name}__currency_code -- ISO 4217, e.g. "USD"
```

### Commerce Address Fields

Stored via the `address` module. See `drupal-field-types.md` for column details.

## Entity Query: Finding All Entity Types in a Database

```sql
-- All entity base tables (look for uuid column as a marker)
SELECT table_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND column_name = 'uuid'
ORDER BY table_name;

-- All field tables (current data)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name REGEXP '^[a-z_]+__field_'
  AND table_name NOT LIKE '%_revision__field_%'
ORDER BY table_name;

-- Map entity types to their bundles
SELECT DISTINCT
  SUBSTRING_INDEX(table_name, '__field_', 1) AS entity_type,
  bundle
FROM node__field_body
UNION ALL
SELECT DISTINCT 'taxonomy_term', bundle FROM taxonomy_term_field_data
UNION ALL
SELECT DISTINCT 'media', bundle FROM media_field_data
UNION ALL
SELECT DISTINCT 'block_content', type FROM block_content_field_data
UNION ALL
SELECT DISTINCT 'paragraph', type FROM paragraphs_item_field_data;
```
