---
description: Add or update bundled Swoosh skills.
---

1. Add markdown skills under `Skills/Bundled/`.
2. Include frontmatter keys: `name`, `description`, `category`, `tags`, `trust`, `platforms`, and `triggers`.
3. Keep built-in skills promoted only when they are safe to enter the prompt catalog.
4. Run `swift test --filter SwooshSkills` if a skill parser or store changed.
