# Swoosh Permission Model

## Permission types

```swift
enum SwooshPermission: String, Codable, Sendable {
    case fileRead
    case fileWrite
    case shellRun
    case calendarRead
    case remindersRead
    case contactsRead
    case browserTabsRead
    case browserHistoryRead
    case screenCapture
    case appleEvents
    case memoryWrite
    case networkAccess
}
```

## Default modes

| Profile | File R/W | Shell | Calendar | Contacts | Browser | Memory |
|---------|----------|-------|----------|----------|---------|--------|
| Safe | deny | deny | deny | deny | deny | ask |
| Developer | ask/allow | ask | deny | deny | deny | ask |
| Automation | allow | ask | allow | deny | ask | allow |
| Power | allow | ask | allow | ask | allow | allow |

## High-risk data — always ask or deny

- Shell destructive commands
- sudo
- File writes outside approved folders
- Contacts
- Messages
- Screen capture
- Raw email

## Excluded from ingestion — never

- Browser cookies
- Passwords / Keychain exports
- Raw API keys (redacted before storage)
- SSH private keys
- .env file values
- Private tokens

## Approval UX

Every risky action produces an approval record:

```
tool_name | arguments_summary | risk_level | status | timestamp
```

Approve from: Swoosh.app, CLI, future mobile companion.

## Audit logging

Every permission decision, Scout scan, memory write, tool call, and approval is logged with:

```
event_type | actor | target | details | timestamp
```

Immutable append-only. User can view full audit trail.
