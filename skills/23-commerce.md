# Skill 23: Drupal Commerce Data Export

Export the full Drupal Commerce data model: stores, products, variations, attributes, orders, order items, payments, shipping, promotions, coupons, tax types, and customer profiles. Covers Commerce 2.x (D8/D9/D10/D11) and Commerce 1.x (D7).

Run Skill 01 (Site Audit) first. You need the Drupal version and access methods. Run Skill 04 (Content Types and Fields) if you need the field definitions for custom fields attached to commerce entity types.

---

## Detect Commerce Version

Commerce 1.x and 2.x share nothing. Different entity systems, different table structures, different data models. Identify which version is installed before running any queries.

### Via Drush

```bash
drush pm:list --filter=commerce --format=json
```

Look at the version string:
- `7.x-1.*` = Commerce 1.x on Drupal 7
- `2.*` or `8.x-2.*` = Commerce 2.x on Drupal 8/9/10/11

### Via Database

```sql
-- D8+ config store
SELECT data FROM config WHERE name = 'core.extension';
-- Unserialize. If 'commerce' appears in the module list, it's Commerce 2.x.

-- D7 system table
SELECT name, info FROM system WHERE name LIKE 'commerce%' AND status = 1;
-- The info blob is PHP-serialized. The 'version' key tells you 7.x-1.x.
```

### Module Inventory

Commerce 2.x is modular. Check which submodules are enabled:

| Module | What it adds |
|---|---|
| `commerce_store` | Store entities |
| `commerce_product` | Products and variations |
| `commerce_order` | Orders and order items |
| `commerce_payment` | Payments and payment gateways |
| `commerce_checkout` | Checkout flows |
| `commerce_cart` | Cart functionality (extends orders) |
| `commerce_promotion` | Promotions and coupons |
| `commerce_tax` | Tax types and calculations |
| `commerce_shipping` | Shipments, shipping methods, rates |
| `commerce_license` | License entities tied to purchases |
| `commerce_recurring` | Subscriptions and billing schedules |
| `commerce_stock` | Stock/inventory tracking |

Only export data for enabled modules. If `commerce_shipping` is not installed, skip Section 8.

---

## 1. Stores

A store is the top-level container. Most sites have one store. Multi-store setups assign products and orders to specific stores.

### Commerce 2.x Tables

**`commerce_store` table:**

| Column | Type | Notes |
|---|---|---|
| `store_id` | int | Primary key. |
| `uuid` | varchar(128) | Globally unique identifier. |
| `type` | varchar(255) | Store type bundle (e.g. `online`, `physical`). |
| `langcode` | varchar(12) | Default language. |

**`commerce_store_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `store_id` | int | Foreign key to `commerce_store.store_id`. |
| `type` | varchar(255) | Store type bundle. |
| `langcode` | varchar(12) | Language of this row. |
| `name` | varchar(255) | Store name. |
| `mail` | varchar(254) | Store email address. |
| `default_currency` | varchar(3) | ISO 4217 currency code (e.g. `USD`, `EUR`). |
| `is_default` | tinyint | 1 = default store for new orders. |
| `uid` | int | Owner user ID. |
| `status` | tinyint | 1 = published. |
| `created` | int | UNIX timestamp. |
| `changed` | int | UNIX timestamp. |
| `default_langcode` | tinyint | 1 = this row is the default translation. |

Export query:

```sql
SELECT
  cs.store_id,
  cs.uuid,
  csfd.type,
  csfd.name,
  csfd.mail,
  csfd.default_currency,
  csfd.is_default,
  csfd.uid,
  csfd.status,
  csfd.created,
  csfd.changed
FROM commerce_store cs
JOIN commerce_store_field_data csfd
  ON cs.store_id = csfd.store_id
WHERE csfd.default_langcode = 1
ORDER BY cs.store_id;
```

### Store Configuration

Store types and their field configuration live in config YAML:

```bash
# List store types
drush config:list | grep commerce_store.commerce_store_type

# Export a store type
drush config:get commerce_store.commerce_store_type.online --format=yaml
```

Each store type config contains:
- `id`: machine name
- `label`: human-readable name
- `traits`: array of trait plugins (e.g. tax handling)

### Billing Countries and Tax Config

Stores reference billing countries and tax configuration through additional fields:

```sql
-- Billing countries (stored as a multi-value field)
SELECT entity_id AS store_id, field_billing_countries_value AS country_code
FROM commerce_store__field_billing_countries
ORDER BY entity_id, delta;

-- Tax registrations
SELECT entity_id AS store_id, field_tax_registrations_value AS country_code
FROM commerce_store__field_tax_registrations
ORDER BY entity_id, delta;
```

Note: These field names are defaults. Custom store types may use different field names. Check the field config:

```bash
drush config:list | grep field.field.commerce_store
```

### Via Drush

```bash
# Count stores
drush ev "echo \Drupal::entityTypeManager()->getStorage('commerce_store')->getQuery()->accessCheck(FALSE)->count()->execute();"

# Export all stores as JSON
drush ev "
  \$stores = \Drupal::entityTypeManager()->getStorage('commerce_store')->loadMultiple();
  foreach (\$stores as \$store) {
    echo json_encode(\$store->toArray(), JSON_PRETTY_PRINT) . \"\n---\n\";
  }
"
```

### Commerce 1.x (D7)

Commerce 1.x stores are not entities. Store-level settings live in `variable` table entries and Rules configuration. There is no `commerce_store` table.

```sql
-- Store name and address from variables
SELECT name, value FROM variable
WHERE name IN ('site_name', 'commerce_default_currency', 'site_default_country');
-- Values are PHP-serialized.
```

---

## 2. Product Types and Product Variation Types

Commerce 2.x separates the product (the thing a customer sees) from the product variation (a purchasable combination of attributes like size and color). This is the single most important distinction in the data model.

### Product Types

Stored in config: `commerce_product.commerce_product_type.{machine_name}.yml`

```bash
# List all product types
drush config:list | grep commerce_product.commerce_product_type

# Export one product type
drush config:get commerce_product.commerce_product_type.default --format=yaml
```

Config keys:
- `id`: machine name (e.g. `default`, `clothing`)
- `label`: display name
- `description`: admin description
- `variationTypes`: array of variation type machine names this product type accepts
- `injectVariationFields`: boolean. When true, variation fields show on the product display.
- `multipleVariations`: boolean. When true, products of this type support multiple variations.
- `traits`: array of trait plugin IDs

### Product Variation Types

Stored in config: `commerce_product.commerce_product_variation_type.{machine_name}.yml`

```bash
# List all variation types
drush config:list | grep commerce_product.commerce_product_variation_type

# Export one
drush config:get commerce_product.commerce_product_variation_type.default --format=yaml
```

Config keys:
- `id`: machine name
- `label`: display name
- `traits`: array (e.g. `commerce_license` adds license fields)
- `orderItemType`: the order item type used when this variation is purchased
- `generateTitle`: boolean. Auto-generate variation titles from attribute values.

### Custom Fields on Products and Variations

List fields attached to each product type and variation type:

```bash
# Fields on a product type
drush config:list | grep field.field.commerce_product.default

# Fields on a variation type
drush config:list | grep field.field.commerce_product_variation.default
```

Via database:

```sql
-- All field instances for commerce_product entities
SELECT bundle, field_name, field_type
FROM config
WHERE name LIKE 'field.field.commerce_product.%'
-- Parse the YAML data column for field_type and settings.
```

Faster approach with a direct query:

```sql
-- Custom field tables for product entity
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'commerce_product__%'
  AND table_name NOT LIKE '%revision%'
ORDER BY table_name;

-- Custom field tables for product variation entity
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'commerce_product_variation__%'
  AND table_name NOT LIKE '%revision%'
ORDER BY table_name;
```

### Commerce 1.x (D7)

D7 Commerce has no product/variation split. A "product" in D7 is equivalent to a "product variation" in Commerce 2.x. What Commerce 2.x calls a "product" was handled by product display nodes in D7.

Product types in D7:

```sql
SELECT type, name, description, help, revision
FROM commerce_product_type
ORDER BY type;
```

---

## 3. Products

### Commerce 2.x Tables

**`commerce_product` table:**

| Column | Type | Notes |
|---|---|---|
| `product_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Product type bundle. |
| `langcode` | varchar(12) | Default language. |

**`commerce_product_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `product_id` | int | Foreign key. |
| `type` | varchar(255) | Bundle. |
| `langcode` | varchar(12) | |
| `uid` | int | Author user ID. |
| `title` | varchar(255) | Product title. |
| `status` | tinyint | 1 = published. |
| `created` | int | UNIX timestamp. |
| `changed` | int | UNIX timestamp. |
| `default_langcode` | tinyint | |

Export query:

```sql
SELECT
  cp.product_id,
  cp.uuid,
  cpfd.type,
  cpfd.title,
  cpfd.uid,
  cpfd.status,
  cpfd.created,
  cpfd.changed
FROM commerce_product cp
JOIN commerce_product_field_data cpfd
  ON cp.product_id = cpfd.product_id
WHERE cpfd.default_langcode = 1
ORDER BY cp.product_id;
```

### Product-Store Relationship

Products are assigned to stores through a multi-value entity reference field:

```sql
SELECT entity_id AS product_id, stores_target_id AS store_id
FROM commerce_product__stores
ORDER BY entity_id, delta;
```

### Product-Variation Relationship

Each product references its variations:

```sql
SELECT entity_id AS product_id, variations_target_id AS variation_id
FROM commerce_product__variations
ORDER BY entity_id, delta;
```

The `delta` column preserves display ordering.

### Product Body and Custom Fields

The body field on products uses the standard field table pattern:

```sql
SELECT entity_id AS product_id, body_value, body_format
FROM commerce_product__body
ORDER BY entity_id;
```

For every custom field `field_{name}` attached to a product type:

```sql
SELECT entity_id AS product_id, bundle, delta, field_{name}_value
FROM commerce_product__field_{name}
ORDER BY entity_id, delta;
```

### Product Counts

```sql
-- Total products by type
SELECT cpfd.type, COUNT(*) AS total
FROM commerce_product_field_data cpfd
WHERE cpfd.default_langcode = 1
GROUP BY cpfd.type;

-- Published vs unpublished
SELECT cpfd.type, cpfd.status, COUNT(*) AS total
FROM commerce_product_field_data cpfd
WHERE cpfd.default_langcode = 1
GROUP BY cpfd.type, cpfd.status;
```

### Via Drush

```bash
# Product count
drush ev "echo \Drupal::entityTypeManager()->getStorage('commerce_product')->getQuery()->accessCheck(FALSE)->count()->execute();"

# Export all products with variations
drush ev "
  \$products = \Drupal::entityTypeManager()->getStorage('commerce_product')->loadMultiple();
  foreach (\$products as \$product) {
    \$data = \$product->toArray();
    echo json_encode(\$data, JSON_PRETTY_PRINT) . \"\n---\n\";
  }
"
```

### Commerce 1.x (D7)

D7 has no `commerce_product_field_data` table. Product data lives in `commerce_product`:

```sql
SELECT
  product_id,
  revision_id,
  sku,
  title,
  type,
  language,
  uid,
  status,
  created,
  changed
FROM commerce_product
ORDER BY product_id;
```

Product display nodes (the D7 equivalent of Commerce 2.x products) are regular nodes with an entity reference field pointing to commerce products:

```sql
-- Find the field that references products (usually field_product)
SELECT entity_id AS nid, field_product_product_id AS product_id
FROM field_data_field_product
ORDER BY entity_id, delta;
```

---

## 4. Product Variations

### Commerce 2.x Tables

**`commerce_product_variation` table:**

| Column | Type | Notes |
|---|---|---|
| `variation_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Variation type bundle. |
| `langcode` | varchar(12) | |

**`commerce_product_variation_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `variation_id` | int | Foreign key. |
| `type` | varchar(255) | Bundle. |
| `langcode` | varchar(12) | |
| `uid` | int | Author user ID. |
| `product_id` | int | Parent product ID. |
| `sku` | varchar(255) | Stock Keeping Unit. Unique across the site. |
| `title` | varchar(255) | Auto-generated from attribute values when `generateTitle` is true. |
| `price__number` | decimal(19,6) | Price amount. Six decimal places. |
| `price__currency_code` | varchar(3) | ISO 4217 currency code. |
| `list_price__number` | decimal(19,6) | Original/compare-at price. NULL if not set. |
| `list_price__currency_code` | varchar(3) | Currency for list price. |
| `status` | tinyint | 1 = active. |
| `created` | int | UNIX timestamp. |
| `changed` | int | UNIX timestamp. |
| `default_langcode` | tinyint | |

Export query:

```sql
SELECT
  cpv.variation_id,
  cpv.uuid,
  cpvfd.type,
  cpvfd.product_id,
  cpvfd.sku,
  cpvfd.title,
  cpvfd.price__number,
  cpvfd.price__currency_code,
  cpvfd.list_price__number,
  cpvfd.list_price__currency_code,
  cpvfd.status,
  cpvfd.created,
  cpvfd.changed
FROM commerce_product_variation cpv
JOIN commerce_product_variation_field_data cpvfd
  ON cpv.variation_id = cpvfd.variation_id
WHERE cpvfd.default_langcode = 1
ORDER BY cpvfd.product_id, cpv.variation_id;
```

### Stock Data

If `commerce_stock` is enabled, stock levels are stored in a separate table:

```sql
-- commerce_stock module (basic stock)
SELECT entity_id AS variation_id, field_commerce_stock_value AS stock_level
FROM commerce_product_variation__field_commerce_stock;
```

Some sites use `commerce_stock` with the `StockLevel` transaction log instead:

```sql
-- Stock transaction log (commerce_stock 2.x)
SELECT
  id,
  entity_id AS variation_id,
  qty,
  location_id,
  transaction_type_id,
  transaction_time,
  related_oid AS related_order_id
FROM commerce_stock_transaction
ORDER BY entity_id, transaction_time;

-- Current stock level per variation (sum of transactions)
SELECT entity_id AS variation_id, SUM(qty) AS current_stock
FROM commerce_stock_transaction
GROUP BY entity_id;
```

### Variation Counts

```sql
SELECT cpvfd.type, COUNT(*) AS total
FROM commerce_product_variation_field_data cpvfd
WHERE cpvfd.default_langcode = 1
GROUP BY cpvfd.type;
```

### Commerce 1.x (D7)

In D7, there is no separate variation entity. The `commerce_product` table IS the variation. Price is stored in a field table:

```sql
-- Price field (D7)
SELECT
  entity_id AS product_id,
  commerce_price_amount AS amount_raw,
  commerce_price_currency_code AS currency_code,
  commerce_price_data AS price_data
FROM field_data_commerce_price
WHERE entity_type = 'commerce_product';
```

The `amount_raw` value is in minor units (cents). Divide by the currency's minor unit factor (100 for USD, EUR; 1 for JPY) to get the decimal price. The `price_data` column is PHP-serialized and may contain price component breakdowns.

---

## 5. Product Attributes

Attributes define the axes of variation: Size, Color, Material. Each attribute has a set of values. Variations reference one value per attribute.

### Attribute Configuration

```bash
# List all product attributes
drush config:list | grep commerce_product.commerce_product_attribute

# Export one attribute
drush config:get commerce_product.commerce_product_attribute.color --format=yaml
```

Config keys:
- `id`: machine name (e.g. `color`, `size`)
- `label`: display name
- `elementType`: form element type (`select`, `radios`, `commerce_product_rendered_attribute`)

### Attribute Values

Attribute values are entities stored in their own tables.

**`commerce_product_attribute_value` table:**

| Column | Type | Notes |
|---|---|---|
| `attribute_value_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `attribute` | varchar(255) | Attribute machine name (e.g. `color`). |
| `langcode` | varchar(12) | |

**`commerce_product_attribute_value_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `attribute_value_id` | int | Foreign key. |
| `attribute` | varchar(255) | |
| `langcode` | varchar(12) | |
| `name` | varchar(255) | Human-readable value (e.g. `Red`, `Large`). |
| `weight` | int | Sort order. |
| `default_langcode` | tinyint | |

Export all attribute values:

```sql
SELECT
  av.attribute_value_id,
  av.attribute,
  avfd.name,
  avfd.weight
FROM commerce_product_attribute_value av
JOIN commerce_product_attribute_value_field_data avfd
  ON av.attribute_value_id = avfd.attribute_value_id
WHERE avfd.default_langcode = 1
ORDER BY av.attribute, avfd.weight;
```

### Attribute-Variation Mapping

Each variation references its attribute values through entity reference fields. The field name follows the pattern `attribute_{attribute_name}`:

```sql
-- Color attribute on variations
SELECT
  entity_id AS variation_id,
  attribute_color_target_id AS color_value_id
FROM commerce_product_variation__attribute_color;

-- Size attribute on variations
SELECT
  entity_id AS variation_id,
  attribute_size_target_id AS size_value_id
FROM commerce_product_variation__attribute_size;
```

To get a complete variation-to-attribute mapping with resolved names:

```sql
SELECT
  cpvfd.variation_id,
  cpvfd.sku,
  color_val.name AS color,
  size_val.name AS size
FROM commerce_product_variation_field_data cpvfd
LEFT JOIN commerce_product_variation__attribute_color ac
  ON cpvfd.variation_id = ac.entity_id
LEFT JOIN commerce_product_attribute_value_field_data color_val
  ON ac.attribute_color_target_id = color_val.attribute_value_id
  AND color_val.default_langcode = 1
LEFT JOIN commerce_product_variation__attribute_size as2
  ON cpvfd.variation_id = as2.entity_id
LEFT JOIN commerce_product_attribute_value_field_data size_val
  ON as2.attribute_size_target_id = size_val.attribute_value_id
  AND size_val.default_langcode = 1
WHERE cpvfd.default_langcode = 1
ORDER BY cpvfd.variation_id;
```

Adapt this query for the actual attributes on the site. List the attribute field tables:

```sql
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'commerce_product_variation__attribute_%'
ORDER BY table_name;
```

### Custom Attribute Fields

Attributes can carry custom fields beyond the name (e.g., a color swatch image, a hex code):

```sql
-- Custom fields on attribute values
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'commerce_product_attribute_value__%'
  AND table_name NOT LIKE '%revision%'
ORDER BY table_name;
```

### Commerce 1.x (D7)

D7 Commerce does not have attribute entities. Attributes are taxonomy vocabularies or option list fields. Each product (variation) carries field values for the attribute fields:

```sql
-- Find attribute fields on D7 products
-- These are typically taxonomy term reference or list fields
SELECT fc.field_name, fc.type, fc.data
FROM field_config fc
JOIN field_config_instance fci ON fc.id = fci.field_id
WHERE fci.entity_type = 'commerce_product'
  AND fc.type IN ('taxonomy_term_reference', 'list_text', 'list_integer')
ORDER BY fc.field_name;
```

---

## 6. Orders

### Commerce 2.x Tables

**`commerce_order` table:**

| Column | Type | Notes |
|---|---|---|
| `order_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Order type bundle (e.g. `default`). |
| `langcode` | varchar(12) | |

**`commerce_order_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `order_id` | int | Foreign key. |
| `type` | varchar(255) | Bundle. |
| `order_number` | varchar(255) | Customer-facing order number. May differ from `order_id`. NULL for draft/cart orders. |
| `store_id` | int | Store this order belongs to. |
| `uid` | int | Customer user ID. 0 = anonymous. |
| `mail` | varchar(254) | Customer email at time of order. |
| `ip_address` | varchar(128) | Customer IP at checkout. |
| `state` | varchar(255) | Order workflow state. See state reference below. |
| `data` | longblob | PHP-serialized array of miscellaneous order data. |
| `locked` | tinyint | 1 = order is locked for editing. |
| `total_price__number` | decimal(19,6) | Order total after adjustments. |
| `total_price__currency_code` | varchar(3) | |
| `created` | int | UNIX timestamp. Cart creation time. |
| `changed` | int | UNIX timestamp. Last modification. |
| `placed` | int | UNIX timestamp. When the order was placed (checkout complete). NULL for carts. |
| `completed` | int | UNIX timestamp. When the order reached a fulfillment/completed state. NULL if not yet completed. |
| `cart` | tinyint | 1 = this order is a cart, not a placed order. |
| `checkout_step` | varchar(255) | Current checkout step. NULL after completion. |
| `billing_profile__target_id` | int | Profile entity ID for billing address. |
| `billing_profile__target_revision_id` | int | Revision ID of the billing profile at order time. |
| `default_langcode` | tinyint | |

### Order State Reference

Commerce 2.x uses state machine workflows for orders. The default order workflow defines these states:

| State | Meaning |
|---|---|
| `draft` | Cart / in-progress order. Not yet placed. |
| `completed` | Placed and fulfilled. Default end state for simple workflows. |
| `canceled` | Canceled by admin or customer. |

The fulfillment workflow (`order_fulfillment`) adds:

| State | Meaning |
|---|---|
| `draft` | Cart. |
| `fulfillment` | Placed, awaiting fulfillment. |
| `completed` | Shipped/fulfilled. |
| `canceled` | Canceled. |

The validation workflow (`order_default_validation`) adds:

| State | Meaning |
|---|---|
| `draft` | Cart. |
| `validation` | Pending validation/review. |
| `fulfillment` | Approved, awaiting fulfillment. |
| `completed` | Complete. |
| `canceled` | Canceled. |

Custom workflows may define additional states. Check:

```bash
drush config:list | grep commerce_order.commerce_order_type
drush config:get commerce_order.commerce_order_type.default --format=yaml
# Look at the 'workflow' key to identify which workflow is active.
```

### Export Orders

```sql
SELECT
  co.order_id,
  co.uuid,
  cofd.type,
  cofd.order_number,
  cofd.store_id,
  cofd.uid,
  cofd.mail,
  cofd.ip_address,
  cofd.state,
  cofd.total_price__number,
  cofd.total_price__currency_code,
  cofd.cart,
  cofd.checkout_step,
  cofd.billing_profile__target_id,
  cofd.billing_profile__target_revision_id,
  cofd.placed,
  cofd.completed,
  cofd.created,
  cofd.changed
FROM commerce_order co
JOIN commerce_order_field_data cofd
  ON co.order_id = cofd.order_id
WHERE cofd.default_langcode = 1
ORDER BY co.order_id;
```

To exclude carts and export only placed orders:

```sql
-- Add to WHERE clause:
AND cofd.cart = 0
AND cofd.placed IS NOT NULL
```

### Order Adjustments

Price adjustments (tax, promotions, shipping fees, custom) are stored as a serialized field on the order. They are also stored in the order item adjustments field.

```sql
-- Order-level adjustments
SELECT entity_id AS order_id, adjustments__value
FROM commerce_order__adjustments
ORDER BY entity_id, delta;
```

Each adjustment value is PHP-serialized and contains:
- `type`: adjustment type (`tax`, `promotion`, `shipping`, `fee`, `custom`)
- `label`: human-readable label
- `amount`: nested object with `number` and `currency_code`
- `percentage`: decimal percentage (for percentage-based adjustments)
- `source_id`: the entity that created the adjustment (promotion ID, tax type ID)
- `included`: boolean. TRUE = included in the price, FALSE = added on top.
- `locked`: boolean. TRUE = cannot be removed by the system.

Deserialize these in PHP or use Drush:

```bash
drush ev "
  \$orders = \Drupal::entityTypeManager()->getStorage('commerce_order')->loadMultiple();
  foreach (\$orders as \$order) {
    \$adjustments = \$order->getAdjustments();
    foreach (\$adjustments as \$adj) {
      echo json_encode([
        'order_id' => \$order->id(),
        'type' => \$adj->getType(),
        'label' => \$adj->getLabel(),
        'amount' => \$adj->getAmount()->toArray(),
        'percentage' => \$adj->getPercentage(),
        'source_id' => \$adj->getSourceId(),
        'included' => \$adj->isIncluded(),
        'locked' => \$adj->isLocked(),
      ]) . \"\n\";
    }
  }
"
```

### Order Counts

```sql
-- Orders by state
SELECT cofd.state, COUNT(*) AS total
FROM commerce_order_field_data cofd
WHERE cofd.default_langcode = 1
  AND cofd.cart = 0
GROUP BY cofd.state;

-- Orders by month
SELECT
  DATE_FORMAT(FROM_UNIXTIME(cofd.placed), '%Y-%m') AS month,
  COUNT(*) AS orders,
  SUM(cofd.total_price__number) AS revenue
FROM commerce_order_field_data cofd
WHERE cofd.default_langcode = 1
  AND cofd.placed IS NOT NULL
GROUP BY month
ORDER BY month;
```

### Commerce 1.x (D7)

D7 orders live in `commerce_order`:

```sql
SELECT
  order_id,
  order_number,
  revision_id,
  type,
  uid,
  mail,
  status,
  created,
  changed,
  hostname AS ip_address
FROM commerce_order
ORDER BY order_id;
```

D7 order statuses differ from 2.x states:
- `cart`, `checkout_checkout`, `checkout_review`, `checkout_payment`, `checkout_complete`
- `pending`, `processing`, `completed`, `canceled`

Order total in D7 is a price field:

```sql
SELECT
  entity_id AS order_id,
  commerce_order_total_amount AS total_raw,
  commerce_order_total_currency_code AS currency_code
FROM field_data_commerce_order_total
WHERE entity_type = 'commerce_order';
-- amount is in minor units (cents)
```

---

## 7. Order Items

Order items represent individual line items in an order.

### Commerce 2.x Tables

**`commerce_order_item` table:**

| Column | Type | Notes |
|---|---|---|
| `order_item_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Order item type bundle. |
| `langcode` | varchar(12) | |

**`commerce_order_item_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `order_item_id` | int | Foreign key. |
| `type` | varchar(255) | Bundle. |
| `order_id` | int | Parent order. |
| `purchased_entity` | int | Entity ID of the purchased item (usually a product variation). |
| `title` | varchar(512) | Snapshot of the product title at purchase time. |
| `quantity` | decimal(14,4) | Quantity purchased. |
| `unit_price__number` | decimal(19,6) | Price per unit. |
| `unit_price__currency_code` | varchar(3) | |
| `overridden_unit_price` | tinyint | 1 = unit price was manually set, not derived from variation. |
| `total_price__number` | decimal(19,6) | quantity * unit_price (before order-level adjustments). |
| `total_price__currency_code` | varchar(3) | |
| `uses_legacy_adjustments` | tinyint | Migration flag from older Commerce 2.x versions. |
| `created` | int | UNIX timestamp. |
| `changed` | int | UNIX timestamp. |
| `default_langcode` | tinyint | |

Export query:

```sql
SELECT
  coi.order_item_id,
  coi.uuid,
  coifd.type,
  coifd.order_id,
  coifd.purchased_entity,
  coifd.title,
  coifd.quantity,
  coifd.unit_price__number,
  coifd.unit_price__currency_code,
  coifd.overridden_unit_price,
  coifd.total_price__number,
  coifd.total_price__currency_code,
  coifd.created,
  coifd.changed
FROM commerce_order_item coi
JOIN commerce_order_item_field_data coifd
  ON coi.order_item_id = coifd.order_item_id
WHERE coifd.default_langcode = 1
ORDER BY coifd.order_id, coi.order_item_id;
```

### Order-to-Order Item Relationship

```sql
SELECT entity_id AS order_id, order_items_target_id AS order_item_id
FROM commerce_order__order_items
ORDER BY entity_id, delta;
```

### Order Item Adjustments

Each order item can carry its own adjustments (per-item promotions, taxes):

```sql
SELECT entity_id AS order_item_id, adjustments__value
FROM commerce_order_item__adjustments
ORDER BY entity_id, delta;
```

Same serialized structure as order-level adjustments.

### Commerce 1.x (D7)

D7 line items live in `commerce_line_item`:

```sql
SELECT
  line_item_id,
  order_id,
  type,
  line_item_label AS sku,
  quantity,
  created,
  changed
FROM commerce_line_item
ORDER BY order_id, line_item_id;
```

Line item prices:

```sql
SELECT
  entity_id AS line_item_id,
  commerce_unit_price_amount AS unit_price_raw,
  commerce_unit_price_currency_code AS currency_code,
  commerce_unit_price_data AS price_components
FROM field_data_commerce_unit_price
WHERE entity_type = 'commerce_line_item';

SELECT
  entity_id AS line_item_id,
  commerce_total_amount AS total_raw,
  commerce_total_currency_code AS currency_code
FROM field_data_commerce_total
WHERE entity_type = 'commerce_line_item';
```

The `price_components` column is PHP-serialized and contains the full price breakdown: base price, discounts, taxes, fees.

---

## 8. Payments

### Commerce 2.x Tables

**`commerce_payment` table:**

| Column | Type | Notes |
|---|---|---|
| `payment_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Payment type (e.g. `payment_default`, `payment_manual`). |
| `langcode` | varchar(12) | |

**`commerce_payment_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `payment_id` | int | Foreign key. |
| `type` | varchar(255) | |
| `payment_gateway` | varchar(255) | Machine name of the payment gateway plugin. |
| `payment_gateway_mode` | varchar(255) | `test` or `live`. |
| `payment_method` | int | Payment method entity ID (stored card, etc.). NULL for manual/offsite. |
| `order_id` | int | Order this payment applies to. |
| `remote_id` | varchar(255) | Transaction ID from the payment processor (Stripe charge ID, PayPal transaction ID). |
| `remote_state` | varchar(255) | State reported by the payment processor. |
| `amount__number` | decimal(19,6) | Payment amount. |
| `amount__currency_code` | varchar(3) | |
| `refunded_amount__number` | decimal(19,6) | Refunded portion. NULL or 0 if no refund. |
| `refunded_amount__currency_code` | varchar(3) | |
| `state` | varchar(255) | Local payment state. |
| `authorized` | int | UNIX timestamp. When payment was authorized. |
| `expires` | int | UNIX timestamp. Authorization expiry. 0 if N/A. |
| `completed` | int | UNIX timestamp. When payment was captured. |
| `test` | tinyint | 1 = test payment (sandbox transaction). |
| `captured` | int | UNIX timestamp. Alias for completed in some versions. |
| `uid` | int | User who created/processed the payment. |
| `created` | int | UNIX timestamp. |
| `changed` | int | UNIX timestamp. |
| `default_langcode` | tinyint | |

### Payment States

| State | Meaning |
|---|---|
| `new` | Payment created, not yet processed. |
| `authorization` | Authorized but not captured. Funds reserved. |
| `completed` | Captured. Money transferred. |
| `authorization_voided` | Authorization canceled before capture. |
| `refunded` | Fully refunded. |
| `partially_refunded` | Partial refund issued. |

Export query:

```sql
SELECT
  cp.payment_id,
  cpfd.type,
  cpfd.payment_gateway,
  cpfd.payment_gateway_mode,
  cpfd.payment_method,
  cpfd.order_id,
  cpfd.remote_id,
  cpfd.remote_state,
  cpfd.amount__number,
  cpfd.amount__currency_code,
  cpfd.refunded_amount__number,
  cpfd.refunded_amount__currency_code,
  cpfd.state,
  cpfd.authorized,
  cpfd.completed,
  cpfd.test,
  cpfd.uid,
  cpfd.created,
  cpfd.changed
FROM commerce_payment cp
JOIN commerce_payment_field_data cpfd
  ON cp.payment_id = cpfd.payment_id
WHERE cpfd.default_langcode = 1
ORDER BY cpfd.order_id, cp.payment_id;
```

### Payment Gateways

Gateway configuration is in config YAML. Export the config but strip API keys and secrets.

```bash
# List payment gateways
drush config:list | grep commerce_payment.commerce_payment_gateway

# Export gateway config (contains API keys -- sanitize before saving)
drush config:get commerce_payment.commerce_payment_gateway.stripe --format=yaml
```

The export must capture:
- `id`: machine name
- `label`: display name
- `plugin`: gateway plugin ID (e.g. `stripe`, `paypal_checkout`, `manual`)
- `mode`: `test` or `live`
- `conditions`: order conditions for gateway availability
- `weight`: sort order

Strip these keys from the `configuration` block:
- Any key containing `secret`, `key`, `password`, `token`, `api_key`
- `configuration.secret_key`, `configuration.publishable_key` (Stripe)
- `configuration.client_id`, `configuration.client_secret` (PayPal)

Replace stripped values with `"[REDACTED]"`.

### Payment Methods (Stored)

If on-site payment gateways store payment methods (cards on file):

```sql
-- Check if the table exists
SELECT COUNT(*)
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name = 'commerce_payment_method_field_data';

-- Export stored payment methods (no sensitive card data stored -- Drupal stores tokens only)
SELECT
  pm.payment_method_id,
  pmfd.type,
  pmfd.payment_gateway,
  pmfd.payment_gateway_mode,
  pmfd.uid,
  pmfd.remote_id,
  pmfd.billing_profile__target_id,
  pmfd.is_reusable,
  pmfd.is_default,
  pmfd.expires,
  pmfd.created,
  pmfd.changed
FROM commerce_payment_method pm
JOIN commerce_payment_method_field_data pmfd
  ON pm.payment_method_id = pmfd.payment_method_id
WHERE pmfd.default_langcode = 1
ORDER BY pmfd.uid, pm.payment_method_id;
```

Note: Drupal Commerce stores tokenized payment method references, not raw card numbers. The `remote_id` is a token from the payment processor. These tokens are not portable between processors and are tied to the merchant's account.

### Commerce 1.x (D7)

D7 payment data lives in `commerce_payment_transaction`:

```sql
SELECT
  transaction_id,
  revision_id,
  uid,
  order_id,
  payment_method AS payment_gateway,
  instance_id,
  remote_id,
  message,
  amount AS amount_raw,
  currency_code,
  status,
  remote_status,
  created,
  changed
FROM commerce_payment_transaction
ORDER BY order_id, transaction_id;
```

D7 statuses: `pending`, `success`, `failure`.

Amount is in minor units.

---

## 9. Shipping

Only present when `commerce_shipping` is installed.

### Check for Shipping Tables

```sql
SELECT COUNT(*)
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name = 'commerce_shipment_field_data';
```

### Shipments

**`commerce_shipment_field_data` table (key columns):**

| Column | Type | Notes |
|---|---|---|
| `shipment_id` | int | Primary key (via join to `commerce_shipment`). |
| `type` | varchar(255) | Shipment type bundle. |
| `order_id` | int | Parent order. |
| `shipping_method` | int | Shipping method entity ID. |
| `shipping_service` | varchar(255) | Machine name of the selected shipping service/rate. |
| `shipping_profile__target_id` | int | Profile entity ID for shipping address. |
| `title` | varchar(255) | Service label shown to customer. |
| `amount__number` | decimal(19,6) | Shipping cost. |
| `amount__currency_code` | varchar(3) | |
| `original_amount__number` | decimal(19,6) | Pre-adjustment shipping cost. |
| `original_amount__currency_code` | varchar(3) | |
| `tracking_code` | varchar(255) | Carrier tracking number. |
| `state` | varchar(255) | `draft`, `ready`, `shipped`, `canceled`. |
| `weight__number` | decimal(14,4) | Total weight. |
| `weight__unit` | varchar(255) | Weight unit (g, kg, lb, oz). |
| `created` | int | |
| `changed` | int | |

Export query:

```sql
SELECT
  cs.shipment_id,
  cs.uuid,
  csfd.type,
  csfd.order_id,
  csfd.shipping_method,
  csfd.shipping_service,
  csfd.shipping_profile__target_id,
  csfd.title,
  csfd.amount__number,
  csfd.amount__currency_code,
  csfd.original_amount__number,
  csfd.original_amount__currency_code,
  csfd.tracking_code,
  csfd.state,
  csfd.weight__number,
  csfd.weight__unit,
  csfd.created,
  csfd.changed
FROM commerce_shipment cs
JOIN commerce_shipment_field_data csfd
  ON cs.shipment_id = csfd.shipment_id
WHERE csfd.default_langcode = 1
ORDER BY csfd.order_id, cs.shipment_id;
```

### Shipment Items

Each shipment contains items referencing order items:

```sql
SELECT entity_id AS shipment_id, items__target_id AS order_item_id
FROM commerce_shipment__items
ORDER BY entity_id, delta;
```

### Shipping Methods

Shipping method configuration:

```bash
drush config:list | grep commerce_shipping.commerce_shipping_method
drush config:get commerce_shipping.commerce_shipping_method.standard --format=yaml
```

Key config fields:
- `id`: machine name
- `label`: display name
- `plugin`: shipping method plugin (e.g. `flat_rate`, `usps`, `fedex`)
- `configuration`: plugin-specific settings (rates, service types)
- `conditions`: order conditions for method availability
- `stores`: store IDs this method applies to

### Commerce 1.x (D7)

D7 uses `commerce_shipping` as a contrib module with a different architecture. Shipping is added as a line item type:

```sql
SELECT
  line_item_id,
  order_id,
  type,
  line_item_label AS shipping_service,
  quantity,
  created
FROM commerce_line_item
WHERE type = 'shipping'
ORDER BY order_id;
```

Shipping rate data is in the line item price components.

---

## 10. Promotions and Coupons

### Promotions

**`commerce_promotion` table:**

| Column | Type | Notes |
|---|---|---|
| `promotion_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Promotion type bundle. |
| `langcode` | varchar(12) | |

**`commerce_promotion_field_data` table (key columns):**

| Column | Type | Notes |
|---|---|---|
| `promotion_id` | int | Foreign key. |
| `type` | varchar(255) | |
| `name` | varchar(255) | Internal admin name. |
| `display_name` | varchar(255) | Customer-facing name (shows on cart). |
| `description` | text | Admin description. |
| `order_type_id` | varchar(255) | Which order type this promotion applies to. |
| `offer` | longblob | Serialized offer plugin configuration. |
| `start_date` | varchar(255) | ISO 8601 start datetime. |
| `end_date` | varchar(255) | ISO 8601 end datetime. NULL = no end. |
| `usage_limit` | int | Max total uses. 0 = unlimited. |
| `usage_limit_customer` | int | Max uses per customer. 0 = unlimited. |
| `current_usage` | int | Current total usage count. |
| `compatibility` | varchar(255) | `any` or `none`. Whether this promotion combines with others. |
| `weight` | int | Processing order. Lower = higher priority. |
| `status` | tinyint | 1 = enabled. |
| `require_coupon` | tinyint | 1 = only applies when a coupon code is entered. |
| `conditions` | longblob | Serialized condition plugin configuration. |
| `created` | int | |
| `changed` | int | |

Export query:

```sql
SELECT
  cp.promotion_id,
  cp.uuid,
  cpfd.type,
  cpfd.name,
  cpfd.display_name,
  cpfd.order_type_id,
  cpfd.start_date,
  cpfd.end_date,
  cpfd.usage_limit,
  cpfd.usage_limit_customer,
  cpfd.current_usage,
  cpfd.compatibility,
  cpfd.weight,
  cpfd.status,
  cpfd.require_coupon,
  cpfd.created,
  cpfd.changed
FROM commerce_promotion cp
JOIN commerce_promotion_field_data cpfd
  ON cp.promotion_id = cpfd.promotion_id
WHERE cpfd.default_langcode = 1
ORDER BY cpfd.weight, cp.promotion_id;
```

### Offer Types

The `offer` column contains a serialized plugin configuration. Common offer types:

| Offer Plugin ID | What It Does |
|---|---|
| `order_percentage_off` | Percentage off the order total. |
| `order_fixed_amount_off` | Fixed amount off the order total. |
| `order_item_percentage_off` | Percentage off matching items. |
| `order_item_fixed_amount_off` | Fixed amount off matching items. |
| `order_buy_x_get_y` | Buy X get Y free/discounted. |
| `order_item_free_shipping` | Free shipping on matching items. |
| `shipment_percentage_off` | Percentage off shipping. |
| `shipment_fixed_amount_off` | Fixed amount off shipping. |

Deserialize the offer column with Drush:

```bash
drush ev "
  \$promos = \Drupal::entityTypeManager()->getStorage('commerce_promotion')->loadMultiple();
  foreach (\$promos as \$promo) {
    \$offer = \$promo->getOffer();
    echo json_encode([
      'promotion_id' => \$promo->id(),
      'name' => \$promo->getName(),
      'offer_plugin' => \$offer->getPluginId(),
      'offer_config' => \$offer->getConfiguration(),
    ], JSON_PRETTY_PRINT) . \"\n---\n\";
  }
"
```

### Promotion Conditions

The `conditions` column is serialized. Common condition types:

| Condition Plugin ID | What It Checks |
|---|---|
| `order_total_price` | Order total above/below a threshold. |
| `order_item_quantity` | Quantity of specific items. |
| `order_item_product` | Specific product IDs. |
| `order_item_product_type` | Product type bundles. |
| `order_customer` | Specific customer user IDs. |
| `order_customer_role` | Customer role membership. |
| `order_store` | Specific store IDs. |
| `order_item_purchased_entity:commerce_product_variation_type` | Specific variation types. |

Deserialize conditions:

```bash
drush ev "
  \$promos = \Drupal::entityTypeManager()->getStorage('commerce_promotion')->loadMultiple();
  foreach (\$promos as \$promo) {
    \$conditions = [];
    foreach (\$promo->getConditions() as \$condition) {
      \$conditions[] = [
        'plugin' => \$condition->getPluginId(),
        'config' => \$condition->getConfiguration(),
      ];
    }
    echo json_encode([
      'promotion_id' => \$promo->id(),
      'conditions' => \$conditions,
    ], JSON_PRETTY_PRINT) . \"\n---\n\";
  }
"
```

### Promotion-Store Relationship

```sql
SELECT entity_id AS promotion_id, stores_target_id AS store_id
FROM commerce_promotion__stores
ORDER BY entity_id, delta;
```

### Coupons

**`commerce_promotion_coupon` table:**

| Column | Type | Notes |
|---|---|---|
| `id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Coupon type bundle. |
| `langcode` | varchar(12) | |

**`commerce_promotion_coupon_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `id` | int | Foreign key. |
| `type` | varchar(255) | |
| `promotion_id` | int | Parent promotion. |
| `code` | varchar(255) | The coupon code customers enter. |
| `usage_limit` | int | Max uses for this coupon. 0 = unlimited. |
| `usage_limit_customer` | int | Max per customer. 0 = unlimited. |
| `current_usage` | int | Current use count. |
| `status` | tinyint | 1 = enabled. |
| `created` | int | |
| `changed` | int | |

Export query:

```sql
SELECT
  cc.id AS coupon_id,
  cc.uuid,
  ccfd.promotion_id,
  ccfd.code,
  ccfd.usage_limit,
  ccfd.usage_limit_customer,
  ccfd.current_usage,
  ccfd.status,
  ccfd.created,
  ccfd.changed
FROM commerce_promotion_coupon cc
JOIN commerce_promotion_coupon_field_data ccfd
  ON cc.id = ccfd.id
WHERE ccfd.default_langcode = 1
ORDER BY ccfd.promotion_id, cc.id;
```

### Commerce 1.x (D7)

D7 Commerce uses a different discount system via `commerce_discount` module:

```sql
-- Discount entities
SELECT
  discount_id,
  name,
  label,
  type,
  status,
  export_status,
  sort_order
FROM commerce_discount
ORDER BY sort_order;

-- Discount offers
SELECT
  offer_id,
  type,
  commerce_fixed_amount_amount AS fixed_amount,
  commerce_fixed_amount_currency_code AS currency,
  commerce_percentage_value AS percentage
FROM commerce_discount_offer;
```

D7 coupons (via `commerce_coupon` module):

```sql
SELECT
  coupon_id,
  code,
  type,
  is_active,
  created,
  changed
FROM commerce_coupon
ORDER BY coupon_id;
```

---

## 11. Tax Types

### Commerce 2.x

Tax type configuration lives in config YAML:

```bash
drush config:list | grep commerce_tax.commerce_tax_type
drush config:get commerce_tax.commerce_tax_type.us_sales_tax --format=yaml
```

Key config fields:
- `id`: machine name
- `label`: display name
- `plugin`: tax type plugin (`custom`, `european_union_vat`, `canadian_sales_tax`, etc.)
- `configuration`: plugin-specific config including zones and rates
- `displayInclusive`: boolean. TRUE = tax-inclusive pricing.

For `custom` tax types, the configuration contains zone and rate definitions:

```bash
drush ev "
  \$tax_types = \Drupal::entityTypeManager()->getStorage('commerce_tax_type')->loadMultiple();
  foreach (\$tax_types as \$tax) {
    echo json_encode([
      'id' => \$tax->id(),
      'label' => \$tax->label(),
      'plugin' => \$tax->getPluginId(),
      'config' => \$tax->getPlugin()->getConfiguration(),
      'display_inclusive' => \$tax->isDisplayInclusive(),
    ], JSON_PRETTY_PRINT) . \"\n---\n\";
  }
"
```

Each custom zone contains:
- `id`: zone ID
- `label`: zone name
- `display_label`: what customers see (e.g. "Sales Tax", "VAT")
- `territories`: array of country codes and optional subdivisions
- `rates`: array of rate objects, each with `id`, `label`, `percentage`, `default` flag

### Commerce 1.x (D7)

D7 tax handling uses `commerce_tax` with Rules:

```sql
-- Tax rates defined in code and stored in variable table
SELECT name, value FROM variable WHERE name LIKE 'commerce_tax%';
```

Tax rates in D7 are typically defined in module code or Features exports, not in the database. Check for tax module files:

```bash
# Find custom tax modules
find . -name "*.module" -exec grep -l "commerce_tax_rate_info" {} \;
```

---

## 12. Profiles (Billing and Shipping Addresses)

Commerce uses profile entities (from the `profile` module) for billing and shipping addresses.

### Profile Tables

**`profile` table:**

| Column | Type | Notes |
|---|---|---|
| `profile_id` | int | Primary key. |
| `uuid` | varchar(128) | |
| `type` | varchar(255) | Profile type (e.g. `customer`, `billing`, `shipping`). |
| `revision_id` | int | Current revision. |
| `langcode` | varchar(12) | |

**`profile_field_data` table:**

| Column | Type | Notes |
|---|---|---|
| `profile_id` | int | Foreign key. |
| `type` | varchar(255) | |
| `uid` | int | User who owns this profile. |
| `status` | tinyint | 1 = active. |
| `is_default` | tinyint | 1 = default profile for this type. |
| `created` | int | |
| `changed` | int | |
| `default_langcode` | tinyint | |

### Address Data

The address field is stored in the standard field table format:

```sql
SELECT
  entity_id AS profile_id,
  bundle AS profile_type,
  field_address_country_code,
  field_address_administrative_area,
  field_address_locality,
  field_address_dependent_locality,
  field_address_postal_code,
  field_address_sorting_code,
  field_address_address_line1,
  field_address_address_line2,
  field_address_organization,
  field_address_given_name,
  field_address_additional_name,
  field_address_family_name
FROM profile__field_address
ORDER BY entity_id;
```

Note: The field name may vary. `field_address` is the default. Check:

```sql
SELECT table_name
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name LIKE 'profile__field_%address%';
```

### Link Profiles to Orders

Orders reference billing profiles directly. Shipping profiles are on shipment entities.

```sql
-- Billing profiles from orders
SELECT
  cofd.order_id,
  cofd.billing_profile__target_id AS billing_profile_id,
  cofd.billing_profile__target_revision_id AS billing_profile_revision_id
FROM commerce_order_field_data cofd
WHERE cofd.billing_profile__target_id IS NOT NULL
ORDER BY cofd.order_id;

-- Shipping profiles from shipments
SELECT
  csfd.shipment_id,
  csfd.order_id,
  csfd.shipping_profile__target_id AS shipping_profile_id
FROM commerce_shipment_field_data csfd
WHERE csfd.shipping_profile__target_id IS NOT NULL
ORDER BY csfd.order_id;
```

### Commerce 1.x (D7)

D7 stores addresses as `addressfield` field data on customer profile entities:

```sql
SELECT
  profile_id,
  revision_id,
  type,
  uid,
  status,
  created,
  changed
FROM commerce_customer_profile
ORDER BY profile_id;

-- Address data
SELECT
  entity_id AS profile_id,
  commerce_customer_address_country AS country,
  commerce_customer_address_administrative_area AS state,
  commerce_customer_address_locality AS city,
  commerce_customer_address_postal_code AS postal_code,
  commerce_customer_address_thoroughfare AS address_line1,
  commerce_customer_address_premise AS address_line2,
  commerce_customer_address_first_name AS given_name,
  commerce_customer_address_last_name AS family_name,
  commerce_customer_address_organisation_name AS organization
FROM field_data_commerce_customer_address
WHERE entity_type = 'commerce_customer_profile';
```

---

## 13. Licenses and Subscriptions

Only present when `commerce_license` or `commerce_recurring` is installed.

### Licenses

```sql
-- Check if license tables exist
SELECT COUNT(*)
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name = 'commerce_license_field_data';
```

**`commerce_license_field_data` table (key columns):**

| Column | Type | Notes |
|---|---|---|
| `license_id` | int | Primary key (via join). |
| `type` | varchar(255) | License type plugin (e.g. `role`, `file`). |
| `uid` | int | License owner. |
| `product_variation` | int | Purchased variation that granted this license. |
| `state` | varchar(255) | `new`, `active`, `suspended`, `revoked`, `expired`. |
| `granted` | int | UNIX timestamp. When license was activated. |
| `expires` | int | UNIX timestamp. 0 = never expires. |
| `renewed` | int | UNIX timestamp. Last renewal. |
| `created` | int | |
| `changed` | int | |

Export query:

```sql
SELECT
  cl.license_id,
  cl.uuid,
  clfd.type,
  clfd.uid,
  clfd.product_variation,
  clfd.state,
  clfd.granted,
  clfd.expires,
  clfd.renewed,
  clfd.created,
  clfd.changed
FROM commerce_license cl
JOIN commerce_license_field_data clfd
  ON cl.license_id = clfd.license_id
WHERE clfd.default_langcode = 1
ORDER BY cl.license_id;
```

### Subscriptions

```sql
-- Check if subscription tables exist
SELECT COUNT(*)
FROM information_schema.TABLES
WHERE table_schema = DATABASE()
  AND table_name = 'commerce_subscription_field_data';
```

**`commerce_subscription_field_data` table (key columns):**

| Column | Type | Notes |
|---|---|---|
| `subscription_id` | int | Primary key (via join). |
| `type` | varchar(255) | Subscription type. |
| `store_id` | int | Store. |
| `billing_schedule` | varchar(255) | Billing schedule config entity ID. |
| `uid` | int | Subscriber. |
| `payment_method` | int | Stored payment method for recurring charges. |
| `purchased_entity` | int | Variation that started the subscription. |
| `title` | varchar(255) | |
| `quantity` | decimal(14,4) | |
| `unit_price__number` | decimal(19,6) | |
| `unit_price__currency_code` | varchar(3) | |
| `state` | varchar(255) | `active`, `trial`, `pending_cancel`, `canceled`, `expired`. |
| `initial_order` | int | Order that created the subscription. |
| `trial_starts` | int | UNIX timestamp. |
| `trial_ends` | int | UNIX timestamp. |
| `starts` | int | UNIX timestamp. |
| `ends` | int | UNIX timestamp. |
| `renewed` | int | UNIX timestamp. Last renewal. |
| `next_renewal` | int | UNIX timestamp. Scheduled next charge. |
| `created` | int | |
| `changed` | int | |

Export query:

```sql
SELECT
  csub.subscription_id,
  csub.uuid,
  csubfd.type,
  csubfd.store_id,
  csubfd.billing_schedule,
  csubfd.uid,
  csubfd.payment_method,
  csubfd.purchased_entity,
  csubfd.title,
  csubfd.quantity,
  csubfd.unit_price__number,
  csubfd.unit_price__currency_code,
  csubfd.state,
  csubfd.initial_order,
  csubfd.starts,
  csubfd.ends,
  csubfd.renewed,
  csubfd.next_renewal,
  csubfd.created,
  csubfd.changed
FROM commerce_subscription csub
JOIN commerce_subscription_field_data csubfd
  ON csub.subscription_id = csubfd.subscription_id
WHERE csubfd.default_langcode = 1
ORDER BY csub.subscription_id;
```

### Billing Schedules

```bash
drush config:list | grep commerce_recurring.commerce_billing_schedule
drush config:get commerce_recurring.commerce_billing_schedule.monthly --format=yaml
```

Key config fields:
- `id`: machine name
- `label`: display name
- `billingType`: `prepaid` or `postpaid`
- `plugin`: billing schedule plugin
- `configuration`: interval, retry schedule, dunning settings

---

## 14. Full Export via Drush

For large sites, entity-by-entity Drush export is more reliable than raw SQL because it handles serialized fields and computed properties.

```bash
#!/bin/bash
# Export all commerce entities to JSON files.
# Run from the Drupal root with Drush available.

EXPORT_DIR="./commerce_export"
mkdir -p "$EXPORT_DIR"

ENTITY_TYPES=(
  commerce_store
  commerce_product
  commerce_product_variation
  commerce_order
  commerce_order_item
  commerce_payment
  commerce_shipment
  commerce_promotion
  commerce_promotion_coupon
  commerce_license
  commerce_subscription
)

for ENTITY_TYPE in "${ENTITY_TYPES[@]}"; do
  echo "Exporting $ENTITY_TYPE..."

  # Check if entity type exists
  COUNT=$(drush ev "
    try {
      echo \Drupal::entityTypeManager()
        ->getStorage('$ENTITY_TYPE')
        ->getQuery()
        ->accessCheck(FALSE)
        ->count()
        ->execute();
    } catch (\Exception \$e) {
      echo 0;
    }
  " 2>/dev/null)

  if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
    echo "  Skipped (no data or entity type not found)."
    continue
  fi

  echo "  Found $COUNT entities."

  drush ev "
    \$storage = \Drupal::entityTypeManager()->getStorage('$ENTITY_TYPE');
    \$ids = \$storage->getQuery()->accessCheck(FALSE)->execute();
    \$entities = \$storage->loadMultiple(\$ids);
    \$output = [];
    foreach (\$entities as \$entity) {
      \$output[] = \$entity->toArray();
    }
    echo json_encode(\$output, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
  " > "$EXPORT_DIR/${ENTITY_TYPE}.json"

  echo "  Exported to $EXPORT_DIR/${ENTITY_TYPE}.json"
done

# Export config entities (types, gateways, tax, shipping methods)
CONFIG_PREFIXES=(
  commerce_store.commerce_store_type
  commerce_product.commerce_product_type
  commerce_product.commerce_product_variation_type
  commerce_product.commerce_product_attribute
  commerce_order.commerce_order_type
  commerce_order.commerce_order_item_type
  commerce_payment.commerce_payment_gateway
  commerce_tax.commerce_tax_type
  commerce_shipping.commerce_shipping_method
  commerce_recurring.commerce_billing_schedule
)

mkdir -p "$EXPORT_DIR/config"

for PREFIX in "${CONFIG_PREFIXES[@]}"; do
  NAMES=$(drush config:list 2>/dev/null | grep "^$PREFIX\.")
  for NAME in $NAMES; do
    FILENAME=$(echo "$NAME" | tr '.' '_')
    drush config:get "$NAME" --format=json > "$EXPORT_DIR/config/${FILENAME}.json" 2>/dev/null
    echo "  Config: $NAME"
  done
done

echo "Export complete. Files in $EXPORT_DIR/"
```

### Sanitize Payment Gateway Config

After export, strip secrets from gateway configs:

```bash
# Find and redact API keys in payment gateway configs
cd "$EXPORT_DIR/config"
for f in commerce_payment_commerce_payment_gateway_*.json; do
  [ -f "$f" ] || continue
  # Use jq to redact known secret keys
  jq '
    if .configuration then
      .configuration |= with_entries(
        if (.key | test("secret|key|password|token|api_key"; "i"))
        then .value = "[REDACTED]"
        else .
        end
      )
    else .
    end
  ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  echo "Sanitized $f"
done
```

---

## 15. JSON:API Export

If you have authenticated JSON:API access but no database or Drush:

```bash
BASE="https://example.com/jsonapi"

# Products
curl -s "$BASE/commerce-product/default" | jq '.data[] | {id, attributes, relationships}'

# Product variations
curl -s "$BASE/commerce-product-variation/default" | jq '.data[] | {id, attributes, relationships}'

# Orders (requires admin or appropriate permissions)
curl -s "$BASE/commerce-order/default" | jq '.data[] | {id, attributes, relationships}'
```

JSON:API entity type paths follow the pattern: `{entity_type_id}/{bundle}` with underscores replaced by dashes.

Pagination:

```bash
# Follow the next link for paginated results
NEXT="$BASE/commerce-product/default?page[limit]=50"
while [ -n "$NEXT" ] && [ "$NEXT" != "null" ]; do
  RESPONSE=$(curl -s "$NEXT")
  echo "$RESPONSE" | jq '.data[]' >> products.jsonl
  NEXT=$(echo "$RESPONSE" | jq -r '.links.next.href // empty')
done
```

Note: Commerce order and payment entities are often excluded from JSON:API access for anonymous users. You need a user with `view commerce_order` and `view commerce_payment` permissions.

---

## 16. Data Model Diagram

This shows how Commerce 2.x entities relate to each other:

```
Store
 ├── Products ──→ Product Variations ──→ Attribute Values
 │                  ├── price
 │                  ├── sku
 │                  └── stock
 │
 ├── Orders
 │    ├── Order Items ──→ Purchased Entity (variation)
 │    ├── Billing Profile ──→ Address
 │    ├── Adjustments (tax, promo, shipping)
 │    ├── Payments ──→ Payment Gateway
 │    │    └── remote_id (processor transaction)
 │    └── Shipments ──→ Shipping Profile ──→ Address
 │         ├── Shipping Method
 │         └── tracking_code
 │
 ├── Promotions
 │    ├── Offer (percentage_off, fixed_amount_off, buy_x_get_y)
 │    ├── Conditions (order total, product type, customer role)
 │    └── Coupons ──→ code, usage_limit
 │
 └── Tax Types
      └── Zones ──→ Rates
```

---

## Migration Notes

### Price Precision

Commerce 2.x stores prices as `decimal(19,6)` in full currency units (e.g. `29.990000` for $29.99). Commerce 1.x stores prices as integers in minor units (e.g. `2999` for $29.99). Convert D7 prices during export: divide by 100 for most currencies, by 1 for zero-decimal currencies (JPY, KRW).

### Order History Integrity

Orders are historical records. Preserve them as snapshots:
- The `title` on an order item is the product name at purchase time, not the current product name.
- The `unit_price` on an order item is the price paid, not the current variation price.
- Billing and shipping profiles on orders reference specific revisions, preserving the address at checkout time.

Do not resolve order data through current product or profile entities. Use the snapshot values stored on the order and order items.

### Payment Tokens Are Not Portable

Payment method `remote_id` values are tokens tied to a specific merchant account on a specific processor. They cannot be transferred to a new processor or a new merchant account on the same processor. Plan for customers to re-enter payment methods on the target platform.

### Coupon Codes and Usage Counts

Export both the code and its `current_usage` count. If the target platform enforces usage limits, import the count to prevent reuse beyond the original limit.

### Cart Orders

Orders with `cart = 1` are abandoned carts. Decide whether to migrate these. They contain useful analytics data (abandonment rate, popular cart items) but are not completed transactions.

### Multi-Store Considerations

If the site has multiple stores, products and orders are scoped to stores. The target platform needs equivalent scoping or a flattening strategy. Export the store assignments for products (Section 3) and the `store_id` on orders (Section 6) to preserve this relationship.
