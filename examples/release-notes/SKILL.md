---
name: release-notes
description: Write user-facing release notes from supplied changes. Use when preparing a changelog entry or release announcement.
---

# Release notes

Group changes by what users can now do, what was fixed, and what requires action.
Lead each item with the user-visible effect. Preserve issue references supplied by the user.
Exclude internal refactors unless they change behavior. Do not invent availability dates or compatibility claims.
For ordinary releases, return a concise Markdown entry using these rules alone.

- When an upgrade requires user action, read [migration guidance](references/migrations.md).
- When choosing the level of detail, read [sample entries](examples/entries.md).
