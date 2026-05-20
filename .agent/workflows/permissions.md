---
description: Add or change a Swoosh permission safely.
---

1. Add the permission case in `Sources/SwooshTools/SwooshPermission.swift`.
2. Update `Docs/PermissionModel.md`.
3. Wire enforcement through `SwooshFirewall`; do not enforce permissions from UI code.
4. Add or update focused tests for the tool or permission path.
