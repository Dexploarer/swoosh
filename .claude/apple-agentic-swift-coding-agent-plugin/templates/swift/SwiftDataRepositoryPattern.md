# SwiftData Repository Pattern

Use a repository or use-case boundary so Foundation Models tools, App Intents, widgets, and views do not directly duplicate persistence logic.

```swift
import SwiftData

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date

    init(title: String, body: String, createdAt: Date = .now) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

@MainActor
struct NoteRepository {
    let context: ModelContext

    func create(title: String, body: String) throws {
        context.insert(Note(title: title, body: body))
        try context.save()
    }
}
```

For non-main actor access, design a dedicated model actor or service and verify current SwiftData concurrency guidance in the installed SDK.
