# Post-Migration Validation Checklist

**Source:** Drupal [version] at [URL]
**Target:** [Platform] at [URL]
**Migration date:** [YYYY-MM-DD]
**Validated by:** [Name]

Instructions: Run through each section after migration completes. Check each item when verified. Note discrepancies in the Notes column. A single failed check in a Critical section blocks go-live.

---

## Content Counts (Critical)

Compare source counts (from Skill 01 audit) against target counts.

| Content Type | Source Count | Target Count | Match? |
|---|---|---|---|
| [type] | | | |

- [ ] Total node count matches across all content types
- [ ] Published vs unpublished counts match per content type
- [ ] Taxonomy term count matches per vocabulary
- [ ] Media entity count matches per media type
- [ ] File count matches (files downloaded and accessible)
- [ ] User count matches (excluding blocked/inactive if intentionally skipped)
- [ ] Comment count matches per content type
- [ ] Redirect count matches
- [ ] URL alias count matches
- [ ] Menu link count matches per menu
- [ ] Webform definition count matches
- [ ] Commerce product count matches (if applicable)

---

## Structure Verification (Critical)

Spot-check 5-10 entities per content type.

- [ ] All fields present on each content type
- [ ] Field values transferred correctly (text, numbers, dates, booleans)
- [ ] Entity reference fields resolve to correct targets
- [ ] Paragraph/component nesting matches source structure
- [ ] Paragraph field values are correct at every nesting level
- [ ] Multi-value fields have all values in correct order
- [ ] Taxonomy term references resolve to correct terms
- [ ] Term hierarchy (parent-child) is intact
- [ ] Media references display the correct asset
- [ ] Image alt text and title transferred
- [ ] Link fields have correct URL and title
- [ ] Date fields show correct date and timezone
- [ ] Boolean fields have correct true/false values
- [ ] List/select fields have correct selected values
- [ ] Required fields are populated on all entities
- [ ] Default values applied where source had no value

---

## Media and Files (Critical)

- [ ] All files downloaded and accessible at their target URLs
- [ ] Images render at correct dimensions
- [ ] Image styles / responsive variants generated
- [ ] PDFs and documents downloadable
- [ ] Video embeds display correctly
- [ ] Audio files play correctly
- [ ] SVGs render (not blocked by security policy)
- [ ] File paths follow the target platform's convention
- [ ] No broken image references in content
- [ ] Media library populated (if target uses one)
- [ ] Focal point / crop data transferred (if applicable)
- [ ] Private files require authentication to access (if applicable)

---

## URLs and Redirects (Critical)

- [ ] All path aliases resolve to correct content
- [ ] Old /node/NID paths return 301 to new URL (not 404)
- [ ] Old aliases that changed return 301 to new URL
- [ ] Existing redirects from redirect module are active
- [ ] No redirect chains (A -> B -> C should be A -> C)
- [ ] No redirect loops
- [ ] Trailing slash behavior is consistent
- [ ] Query parameters preserved where needed
- [ ] External links in content still point to correct destinations
- [ ] Internal links in rich text rewritten to new URL structure
- [ ] Anchor links (#fragment) still work

---

## SEO (Critical)

- [ ] Page titles correct on all content types
- [ ] Meta descriptions present where configured
- [ ] Canonical URLs correct (no self-referencing errors)
- [ ] Open Graph tags present (og:title, og:description, og:image)
- [ ] Twitter Card tags present
- [ ] Structured data / JSON-LD present where it existed on source
- [ ] XML sitemap generated and includes all public URLs
- [ ] XML sitemap submitted to Google Search Console
- [ ] robots.txt correct (not blocking content that should be indexed)
- [ ] hreflang tags present on multilingual content
- [ ] Google Search Console shows no new crawl errors (check 48h post-launch)
- [ ] No unintentional noindex tags on public content

---

## Multilingual (if applicable)

- [ ] All translated content present for every language
- [ ] Language switcher displays correct available translations
- [ ] Translated URL aliases correct per language
- [ ] Interface translations loaded (menus, labels, UI strings)
- [ ] Language detection and negotiation works (URL prefix, domain, browser)
- [ ] Default language content displays when translation is missing
- [ ] Translated taxonomy terms present
- [ ] Translated menu items present
- [ ] Translated media alt text present
- [ ] Date and number formats follow locale conventions

---

## Commerce (if applicable)

- [ ] Product types and their fields migrated
- [ ] Product variations with prices migrated
- [ ] Product images display correctly
- [ ] Product categories/taxonomies linked
- [ ] Price formatting correct per currency
- [ ] Tax configuration recreated
- [ ] Shipping methods configured
- [ ] Payment gateway configured
- [ ] Order history migrated (if in scope)
- [ ] Customer profiles migrated
- [ ] Coupons and promotions recreated (if in scope)
- [ ] Cart and checkout flow tested end-to-end
- [ ] Stock levels correct (if tracking inventory)

---

## Rich Text and Embedded Content

- [ ] Embedded images in WYSIWYG content display correctly
- [ ] Embedded media entities render (not raw tokens like `<drupal-media>`)
- [ ] Embedded views/blocks render or are converted to target equivalent
- [ ] Line items (linkit) links rewritten to target URLs
- [ ] Inline code blocks preserved
- [ ] Tables preserved with formatting
- [ ] No raw HTML entities visible to users (&amp; &lt; etc.)
- [ ] Text format filtering applied (no raw script tags, etc.)
- [ ] Alignment classes converted to target CSS
- [ ] Caption text preserved on figures/images

---

## Users and Authentication

- [ ] User accounts created for all in-scope users
- [ ] User roles mapped to target equivalents
- [ ] Email addresses correct
- [ ] Display names / usernames correct
- [ ] Custom profile fields migrated
- [ ] User profile pictures migrated
- [ ] Password reset flow works
- [ ] Password reset emails sent to migrated users (if planned)
- [ ] Admin accounts have correct permissions
- [ ] User registration form works (if public registration is enabled)

---

## Navigation and Menus

- [ ] Main navigation matches source structure
- [ ] Footer menu matches source
- [ ] All menu links resolve (no 404s)
- [ ] Menu hierarchy (parent-child) is correct
- [ ] Active trail highlighting works
- [ ] Mobile menu functions correctly
- [ ] Breadcrumbs display correct hierarchy

---

## Performance

- [ ] Lighthouse performance score within acceptable range on 5 sample pages
- [ ] Largest Contentful Paint under target threshold
- [ ] Time to First Byte acceptable
- [ ] Image optimization pipeline active (WebP/AVIF conversion if configured)
- [ ] Caching headers correct
- [ ] CDN serving static assets (if configured)
- [ ] No N+1 query issues on listing pages
- [ ] Search index built and returning results

---

## Final Sign-off

| Check | Completed |
|---|---|
| All Critical sections pass | [ ] |
| Stakeholder walkthrough completed | [ ] |
| Rollback plan documented and tested | [ ] |
| DNS cutover plan confirmed | [ ] |
| Monitoring and alerting active | [ ] |
| Go-live approved by | [Name, Date] |
