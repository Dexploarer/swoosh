import Foundation
import Testing
@testable import SwooshChatSDK

@Suite("SwooshChatSDK")
struct ChatSDKTests {
    @Test("Adapter catalog exposes Chat SDK platforms as toggles")
    func catalogHasPlatforms() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ChatAdapterToggleStore(url: root)
        let statuses = try await ChatAdapterCatalog().statuses(store: store, env: [:])
        let ids = Set(statuses.map(\.id))
        #expect(ids.isSuperset(of: [
            "slack", "teams", "googleChat", "discord", "telegram", "github", "linear", "whatsApp", "messenger", "web",
            "beeperMatrix", "photonIMessage", "resendEmail", "zernioSocial", "liveblocks", "webex", "baileys", "sendblue",
            "blooio", "zalo", "mattermost", "swoosh",
        ]))
        #expect(statuses.first { $0.id == "web" }?.enabled == true)
        #expect(statuses.first { $0.id == "slack" }?.configured == false)
        #expect(statuses.first { $0.id == "webex" }?.definition.distribution == .community)
    }

    @Test("Adapter catalog exposes Chat SDK state adapters as toggles")
    func catalogHasStateAdapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ChatStateAdapterToggleStore(url: root)
        let statuses = try await ChatStateAdapterCatalog().statuses(store: store, env: [:])
        let ids = Set(statuses.map(\.id))
        #expect(ids.isSuperset(of: ["state-actantdb", "state-memory", "state-redis", "state-ioredis", "state-postgres", "state-cloudflare-do", "state-mysql"]))
        #expect(statuses.first { $0.id == "state-actantdb" }?.enabled == true)
        #expect(statuses.first { $0.id == "state-postgres" }?.missingCredentials == ["POSTGRES_URL"])
    }

    @Test("Routes mentions and subscriptions")
    func routesMentionsAndSubscriptions() async throws {
        let adapter = MemoryChatAdapter()
        let state = InMemoryChatStateAdapter()
        let chat = Chat(
            configuration: ChatConfiguration(userName: "swoosh"),
            adapters: ["memory": adapter],
            state: state
        )
        let threadID = ChatThreadID("memory:C1:T1")
        let mentionCount = Counter()
        let subscribedCount = Counter()
        await chat.onNewMention { thread, _ in
            await mentionCount.increment()
            try await thread.subscribe()
        }
        await chat.onSubscribedMessage { _, _ in
            await subscribedCount.increment()
        }
        let user = ChatAuthor(userID: "u1", userName: "alice")
        try await chat.handle(ChatMessage(threadID: threadID, text: "@swoosh hi", author: user, isMention: true))
        try await chat.handle(ChatMessage(threadID: threadID, text: "follow-up", author: user))
        #expect(await mentionCount.value == 1)
        #expect(await subscribedCount.value == 1)
    }

    @Test("Converts chat messages to AI messages")
    func convertsToAI() async throws {
        let messages = [
            ChatMessage(
                threadID: "memory:C1:T1",
                text: "hello",
                author: ChatAuthor(userID: "u1", userName: "alice"),
                metadata: ChatMessageMetadata(dateSent: Date(timeIntervalSince1970: 2))
            ),
            ChatMessage(
                threadID: "memory:C1:T1",
                text: "hi",
                author: ChatAuthor(userID: "bot", userName: "swoosh", isBot: true, isMe: true),
                metadata: ChatMessageMetadata(dateSent: Date(timeIntervalSince1970: 3))
            ),
        ]
        let ai = await toAiMessages(messages, options: ToAiMessagesOptions(includeNames: true))
        #expect(ai.count == 2)
        #expect(ai.first?.role == .user)
        if case .text(let content) = ai.first?.content {
            #expect(content == "[alice]: hello")
        } else {
            Issue.record("expected text content")
        }
    }
}

private actor Counter {
    private var storage = 0

    var value: Int { storage }

    func increment() {
        storage += 1
    }
}
