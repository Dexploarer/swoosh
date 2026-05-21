// Tests/SwooshGatewayTests/GatewayTests.swift — SwooshGateway
//
// Covers gateway data types (messages, attachments), ChannelDirectory
// actor, GatewayRouter actor, and the generic WebhookPlatform.

import Testing
import Foundation
@testable import SwooshGateway

// MARK: - Data types

@Suite("GatewayMessage")
struct GatewayMessageTests {

    @Test("Default initialization")
    func defaults() {
        let m = GatewayMessage(text: "hi")
        #expect(m.text == "hi")
        #expect(m.attachments.isEmpty)
        #expect(m.replyTo == nil)
        #expect(m.metadata.isEmpty)
    }

    @Test("Codable round-trip")
    func roundTrip() throws {
        let attach = MessageAttachment(type: .image, url: "http://x", filename: "a.png")
        let original = GatewayMessage(text: "hi", attachments: [attach], replyTo: "m1", metadata: ["k": "v"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GatewayMessage.self, from: data)
        #expect(decoded.text == "hi")
        #expect(decoded.attachments.count == 1)
        #expect(decoded.replyTo == "m1")
        #expect(decoded.metadata["k"] == "v")
    }
}

@Suite("MessageAttachment")
struct MessageAttachmentTests {

    @Test("All attachment types round-trip")
    func allTypes() throws {
        for type in [MessageAttachment.AttachmentType.image, .file, .audio, .video, .code] {
            let attach = MessageAttachment(type: type, url: "http://x")
            let data = try JSONEncoder().encode(attach)
            let decoded = try JSONDecoder().decode(MessageAttachment.self, from: data)
            #expect(decoded.type == type)
        }
    }
}

@Suite("IncomingMessage")
struct IncomingMessageTests {

    @Test("Default initialization")
    func defaults() {
        let m = IncomingMessage(platform: "telegram", channelID: "c1", senderID: "u1",
                                senderName: "Alice", text: "hi")
        #expect(m.attachments.isEmpty)
        #expect(m.rawPayload.isEmpty)
        #expect(m.platform == "telegram")
        #expect(m.channelID == "c1")
    }
}

// MARK: - ChannelDirectory

@Suite("ChannelDirectory")
struct ChannelDirectoryTests {

    @Test("Empty directory returns nil for lookup")
    func emptyLookup() async {
        let dir = ChannelDirectory()
        #expect(await dir.lookup("missing") == nil)
    }

    @Test("Register and look up")
    func registerLookup() async {
        let dir = ChannelDirectory()
        await dir.register(channelID: "c1", platform: "telegram", userID: "u1", displayName: "Alice")
        let info = await dir.lookup("c1")
        #expect(info?.channelID == "c1")
        #expect(info?.platform == "telegram")
        #expect(info?.userID == "u1")
        #expect(info?.displayName == "Alice")
        #expect(info?.sessionID == nil)
    }

    @Test("bindSession associates session id")
    func bindSession() async {
        let dir = ChannelDirectory()
        await dir.register(channelID: "c1", platform: "telegram", userID: "u1", displayName: "Alice")
        await dir.bindSession("c1", sessionID: "s-1")
        let info = await dir.lookup("c1")
        #expect(info?.sessionID == "s-1")
    }

    @Test("bindSession on unknown channel is a no-op")
    func bindSessionUnknown() async {
        let dir = ChannelDirectory()
        await dir.bindSession("missing", sessionID: "s-1")
        #expect(await dir.lookup("missing") == nil)
    }
}

// MARK: - WebhookPlatform

@Suite("WebhookPlatform")
struct WebhookPlatformTests {

    @Test("Default IDs")
    func defaults() {
        let p = WebhookPlatform()
        #expect(p.platformID == "webhook")
        #expect(p.displayName == "Webhook")
    }

    @Test("start / stop toggle isConnected")
    func startStop() async throws {
        let p = WebhookPlatform()
        #expect(p.isConnected == false)
        try await p.start()
        #expect(p.isConnected == true)
        try await p.stop()
        #expect(p.isConnected == false)
    }

    @Test("injectMessage invokes handler")
    func injectInvokesHandler() async {
        let p = WebhookPlatform()
        let counter = MessageCounter()
        p.onMessage { msg in await counter.record(msg) }

        let incoming = IncomingMessage(platform: "webhook", channelID: "c", senderID: "u",
                                        senderName: "Alice", text: "hello")
        await p.injectMessage(incoming)
        #expect(await counter.count == 1)
        #expect(await counter.lastText == "hello")
    }

    @Test("send is a no-op (default implementation)")
    func sendNoOp() async throws {
        let p = WebhookPlatform()
        // Should not throw
        try await p.send(message: GatewayMessage(text: "hi"), to: "c1")
    }
}

// MARK: - GatewayRouter

@Suite("GatewayRouter")
struct GatewayRouterTests {

    @Test("Register and send routes to platform")
    func sendRoutes() async throws {
        let router = GatewayRouter()
        let p = WebhookPlatform()
        try await p.start()
        await router.register(platform: p)
        // Should not throw
        try await router.send(GatewayMessage(text: "hi"), platform: "webhook", channel: "c1")
    }

    @Test("Send to unknown platform is silently ignored")
    func unknownPlatform() async throws {
        let router = GatewayRouter()
        // No-op; current implementation returns early
        try await router.send(GatewayMessage(text: "hi"), platform: "nope", channel: "c1")
    }

    @Test("setHandler stores handler closure")
    func setHandler() async {
        let router = GatewayRouter()
        await router.setHandler { _ in nil }
        // No public observable side effect; just ensure no crash.
        #expect(Bool(true))
    }

    @Test("startAll wires handler and pings directory on incoming")
    func startAllRegistersDirectory() async throws {
        let router = GatewayRouter()
        let platform = WebhookPlatform()
        await router.register(platform: platform)

        await router.setHandler { incoming in
            GatewayMessage(text: "ack:\(incoming.text)")
        }
        try await router.startAll()

        await platform.injectMessage(IncomingMessage(
            platform: "webhook", channelID: "c1", senderID: "u1",
            senderName: "Alice", text: "ping"
        ))

        let info = await router.directory.lookup("c1")
        #expect(info?.userID == "u1")
        #expect(info?.platform == "webhook")

        try await router.stopAll()
    }
}

// MARK: - Helpers

private actor MessageCounter {
    private(set) var count = 0
    private(set) var lastText: String = ""

    func record(_ msg: IncomingMessage) {
        count += 1
        lastText = msg.text
    }
}
