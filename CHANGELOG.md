# Changelog

## [Unreleased]

### Changed
- Made `web/` the canonical landing site and converted root `index.html` to a redirect.
- Standardized waitlist submission in `web/index.html` to Formspree (`mvzwveen`).
- Improved landing accessibility (removed forced hidden cursor, restored visible scrollbars, modal ARIA + focus trap).
- Added `web/privacy.html` and linked privacy disclosure from the waitlist modal/footer.
- Updated Pages workflow to lint web HTML and validate non-placeholder form configuration before deploy.
- Clarified root README deployment instructions and corrected repository naming/path examples.
- Rebuilt the landing page into a minimal/lightweight single-page layout with one image and removed unsupported marketing claims.
- Replaced synthetic beta counter behavior with `web/data/beta-count.json` consumption.
- Added scheduled Formspree sync workflow (`update_formspree_beta_count.yml`) for `web/data/beta-count.json`.
