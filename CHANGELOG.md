# Changelog

## 2026-05-18
- Standardized the canonical landing page to `web/index.html` and set root `index.html` to redirect to `/web/`.
- Unified waitlist submission in `web/index.html` to use Formspree (`mvzwveen`) with fetch-based handling.
- Improved landing-page accessibility with modal ARIA attributes, keyboard focus trapping, overlay click-to-close, and privacy disclosure link.
- Added `web/privacy.html` and updated deployment guidance in root `README.md`.
- Added a web CI workflow to detect placeholder form IDs and validate static HTML files.
