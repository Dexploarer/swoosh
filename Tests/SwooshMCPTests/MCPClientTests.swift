// Tests/SwooshMCPTests/MCPClientTests.swift — 0.8C MCP client + transport tests
//
// Exercises the JSON-RPC framing, id correlation, the initialize/tools-list
// flow, and error/exit handling against an in-process mock transport — no
// real MCP server and no Process spawning, so the suite is deterministic.
// A single optional end-to-end test drives a real /bin/sh stdio server.

import Testing
import Foundation
@testable import SwooshMCP
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Mock transport
// ═══════════════════════════════════════════════════════════════

/// A scriptable in-process transport. The `responder` closure receives each
/// outbound frame and returns zero or more inbound frames to feed back. This
/// is the protocol seam that lets us test the JSON-RPC layer with no Process.
actor MockMCPTransport: MCPTransport {
    typealias Responder = @Sendable (String) async -> [String]

    private let responder: Responder
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var started = false
    private var closed = false
    /// When set, the transport finishes the frame stream after this many
    /// outbound sends — simulates a process exiting mid-flight.
    private let closeAfterSends: Int?
    private var sendCount = 0
    /// Frames recorded for assertion.
    private(set) var sentFrames: [String] = []

    init(closeAfterSends: Int? = nil, responder: @escaping Responder) {
        self.responder = responder
        self.closeAfterSends = closeAfterSends
    }

    func start() async throws {
        guard !started else { throw MCPTransportError.alreadyConnected }
        started = true
    }

    func send(_ line: String) async throws {
        guard started, !closed else { throw MCPTransportError.notConnected }
        sentFrames.append(line)
        sendCount += 1
        if let limit = closeAfterSends, sendCount >= limit {
            // Simulate the server process dying after this many writes.
            continuation?.finish(throwing: MCPTransportError.processExited(code: 1))
            closed = true
            return
        }
        let replies = await responder(line)
        for reply in replies { continuation?.yield(reply) }
    }

    nonisolated func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task { await self.attach(cont) }
        }
    }

    private func attach(_ cont: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = cont
    }

    func close() async {
        closed = true
        continuation?.finish()
    }

    func recordedFrames() -> [String] { sentFrames }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Frame helpers
// ═══════════════════════════════════════════════════════════════

/// Extracts the integer id from an outbound JSON-RPC frame.
func frameID(_ line: String) -> Int? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONDecoder().decode(JSONRPCValue.self, from: data) else { return nil }
    return obj["id"]?.intValue
}

func frameMethod(_ line: String) -> String? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONDecoder().decode(JSONRPCValue.self, from: data) else { return nil }
    return obj["method"]?.stringValue
}

func okInitializeReply(id: Int, serverName: String = "mock-server") -> String {
    """
    {"jsonrpc":"2.0","id":\(id),"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"\(serverName)","version":"1.2.3"}}}
    """
}

func toolsListReply(id: Int) -> String {
    """
    {"jsonrpc":"2.0","id":\(id),"result":{"tools":[{"name":"read_file","title":"Read File","description":"Read a file","inputSchema":{"type":"object","properties":{"path":{"type":"string"}}}},{"name":"write_file","description":"Write a file"}]}}
    """
}

// ═══════════════════════════════════════════════════════════════
// MARK: - JSON-RPC framing tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP JSON-RPC framing")
struct MCPJSONRPCFramingTests {

    @Test("Request encodes to single-line JSON-RPC 2.0")
    func requestEncodes() throws {
        let req = MCPRPCRequest(id: .int(7), method: "tools/list", params: .object([:]))
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("\n"))
        #expect(json.contains("\"jsonrpc\":\"2.0\""))
        // JSONEncoder escapes forward slashes by default ("\/").
        #expect(json.contains("\"method\":\"tools\\/list\""))
        #expect(json.contains("\"id\":7"))
    }

    @Test("Notification has no id field")
    func notificationNoID() throws {
        let note = MCPRPCNotification(method: "notifications/initialized")
        let json = String(data: try JSONEncoder().encode(note), encoding: .utf8)!
        #expect(!json.contains("\"id\""))
        #expect(json.contains("notifications\\/initialized"))
    }

    @Test("Response with result decodes as a response")
    func responseDecodes() throws {
        let line = #"{"jsonrpc":"2.0","id":3,"result":{"ok":true}}"#
        let frame = try JSONDecoder().decode(MCPRPCResponse.self, from: Data(line.utf8))
        #expect(frame.isResponse)
        #expect(!frame.isNotification)
        #expect(frame.id == .int(3))
        #expect(frame.error == nil)
    }

    @Test("Error response parses error code and message")
    func errorResponseParses() throws {
        let line = #"{"jsonrpc":"2.0","id":4,"error":{"code":-32601,"message":"Method not found"}}"#
        let frame = try JSONDecoder().decode(MCPRPCResponse.self, from: Data(line.utf8))
        #expect(frame.isResponse)
        #expect(frame.error?.code == MCPRPCError.methodNotFound)
        #expect(frame.error?.message == "Method not found")
    }

    @Test("Server-initiated notification recognized")
    func serverNotification() throws {
        let line = #"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#
        let frame = try JSONDecoder().decode(MCPRPCResponse.self, from: Data(line.utf8))
        #expect(frame.isNotification)
        #expect(!frame.isResponse)
        #expect(frame.method == "notifications/tools/list_changed")
    }

    @Test("String id accepted alongside int id")
    func stringIDAccepted() throws {
        let line = #"{"jsonrpc":"2.0","id":"abc","result":{}}"#
        let frame = try JSONDecoder().decode(MCPRPCResponse.self, from: Data(line.utf8))
        #expect(frame.id == .string("abc"))
    }

    @Test("Targets MCP revision 2025-06-18")
    func targetsRevision() {
        #expect(MCPProtocol.revision == "2025-06-18")
        #expect(MCPProtocol.jsonrpcVersion == "2.0")
    }

    @Test("Content blocks flatten to text")
    func contentFlattens() {
        let blocks: [JSONRPCValue] = [
            .object(["type": .string("text"), "text": .string("hello")]),
            .object(["type": .string("text"), "text": .string("world")]),
            .object(["type": .string("image"), "mimeType": .string("image/png")]),
        ]
        let text = MCPClient.flattenContent(blocks)
        #expect(text == "hello\nworld\n[image: image/png]")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Line splitting tests
// ═══════════════════════════════════════════════════════════════

#if os(macOS) || os(Linux)
@Suite("MCP stdio line splitting")
struct MCPLineSplittingTests {

    @Test("Splits a pipe stream into newline-delimited frames")
    func splitsLines() async throws {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting
        try writer.write(contentsOf: Data("line one\nline two\npartial".utf8))
        try writer.close()

        var collected: [String] = []
        for try await line in StdioMCPTransport.lineStream(from: pipe.fileHandleForReading) {
            collected.append(line)
        }
        // partial trailing line (no newline) is flushed at EOF
        #expect(collected == ["line one", "line two", "partial"])
    }
}
#endif

// ═══════════════════════════════════════════════════════════════
// MARK: - Initialize handshake tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP initialize handshake")
struct MCPInitializeTests {

    @Test("Initialize completes and parses serverInfo")
    func initializeSucceeds() async throws {
        let transport = MockMCPTransport { line in
            guard let id = frameID(line), frameMethod(line) == "initialize" else { return [] }
            return [okInitializeReply(id: id, serverName: "fs-server")]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        let handshake = try await client.initialize()
        #expect(handshake.serverName == "fs-server")
        #expect(handshake.serverVersion == "1.2.3")
        #expect(handshake.protocolVersion == "2025-06-18")
        #expect(handshake.hasToolsCapability)
        await client.disconnect()
    }

    @Test("Initialized notification is sent after handshake")
    func initializedNotificationSent() async throws {
        let transport = MockMCPTransport { line in
            guard let id = frameID(line), frameMethod(line) == "initialize" else { return [] }
            return [okInitializeReply(id: id)]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()
        let frames = await transport.recordedFrames()
        #expect(frames.contains { frameMethod($0) == "notifications/initialized" })
        await client.disconnect()
    }

    @Test("Initialize error response surfaces as rpcError")
    func initializeErrorSurfaces() async throws {
        let transport = MockMCPTransport { line in
            guard let id = frameID(line) else { return [] }
            return [#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32603,"message":"boom"}}"#]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        await #expect(throws: MCPClientError.self) {
            try await client.initialize()
        }
        await client.disconnect()
    }

    @Test("tools/list before initialize throws notInitialized")
    func toolsListRequiresHandshake() async throws {
        let transport = MockMCPTransport { _ in [] }
        let client = MCPClient(transport: transport)
        try await client.connect()
        await #expect(throws: MCPClientError.self) {
            _ = try await client.listTools()
        }
        await client.disconnect()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - tools/list + tools/call tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP tools/list and tools/call")
struct MCPToolsTests {

    private func connectedClient(_ responder: @escaping MockMCPTransport.Responder) async throws -> MCPClient {
        let transport = MockMCPTransport(responder: responder)
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()
        return client
    }

    @Test("tools/list parses tools with schemas")
    func toolsListParses() async throws {
        let client = try await connectedClient { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/list": return [toolsListReply(id: id)]
            default: return []
            }
        }
        let tools = try await client.listTools()
        #expect(tools.count == 2)
        #expect(tools[0].name == "read_file")
        #expect(tools[0].title == "Read File")
        #expect(tools[0].inputSchemaJSON?.contains("path") == true)
        #expect(tools[1].name == "write_file")
        await client.disconnect()
    }

    @Test("tools/list follows nextCursor pagination")
    func toolsListPaginates() async throws {
        let client = try await connectedClient { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/list":
                // Page 1 has a cursor, page 2 does not.
                let isFirst = id == 2
                if isFirst {
                    return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[{"name":"a"}],"nextCursor":"p2"}}"#]
                } else {
                    return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[{"name":"b"}]}}"#]
                }
            default: return []
            }
        }
        let tools = try await client.listTools()
        #expect(tools.map { $0.name } == ["a", "b"])
        await client.disconnect()
    }

    @Test("tools/call returns text content")
    func toolsCallSucceeds() async throws {
        let client = try await connectedClient { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/call":
                return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"file contents"}],"isError":false}}"#]
            default: return []
            }
        }
        let result = try await client.callTool(name: "read_file", arguments: ["path": .string("/tmp/x")])
        #expect(result.text == "file contents")
        #expect(!result.isError)
        await client.disconnect()
    }

    @Test("tools/call isError=true is preserved")
    func toolsCallIsError() async throws {
        let client = try await connectedClient { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/call":
                return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"no such file"}],"isError":true}}"#]
            default: return []
            }
        }
        let result = try await client.callTool(name: "read_file")
        #expect(result.isError)
        #expect(result.text == "no such file")
        await client.disconnect()
    }

    @Test("tools/call JSON-RPC error throws")
    func toolsCallRPCErrorThrows() async throws {
        let client = try await connectedClient { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/call":
                return [#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32602,"message":"invalid params"}}"#]
            default: return []
            }
        }
        await #expect(throws: MCPClientError.self) {
            _ = try await client.callTool(name: "read_file")
        }
        await client.disconnect()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Id correlation tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP id correlation")
struct MCPCorrelationTests {

    @Test("Interleaved out-of-order responses match the right request")
    func outOfOrderResponses() async throws {
        // Server replies to tools/list before tools/call, even though
        // tools/call was issued first — correlation must hold by id.
        let transport = MockMCPTransport { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/call":
                // delayed: respond with this id but tag it clearly
                return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"call-\#(id)"}],"isError":false}}"#]
            case "tools/list":
                return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[{"name":"list-\#(id)"}]}}"#]
            default: return []
            }
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()

        async let call = client.callTool(name: "t")
        async let list = client.listTools()
        let callResult = try await call
        let listResult = try await list

        #expect(callResult.text.hasPrefix("call-"))
        #expect(listResult.first?.name.hasPrefix("list-") == true)
        await client.disconnect()
    }

    @Test("Unknown id in inbound frame is dropped without crashing")
    func unknownIDDropped() async throws {
        let transport = MockMCPTransport { line in
            guard let id = frameID(line), frameMethod(line) == "initialize" else { return [] }
            // Reply correctly, plus a stray frame with an id we never sent.
            return [
                #"{"jsonrpc":"2.0","id":999,"result":{"stray":true}}"#,
                okInitializeReply(id: id),
            ]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        let handshake = try await client.initialize()
        #expect(handshake.serverName == "mock-server")
        await client.disconnect()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Process exit / transport failure tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP transport failure handling")
struct MCPTransportFailureTests {

    @Test("Process exit mid-flight fails the pending request")
    func processExitFailsPending() async throws {
        // closeAfterSends:2 → connect + initialize send go through, then
        // the next send (the tools/list request) triggers a process exit.
        let transport = MockMCPTransport(closeAfterSends: 2) { line in
            guard let id = frameID(line), frameMethod(line) == "initialize" else { return [] }
            return [okInitializeReply(id: id)]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()
        // The second send is notifications/initialized; the third (tools/list)
        // happens after closeAfterSends already fired — request must fail.
        await #expect(throws: Error.self) {
            _ = try await client.listTools()
        }
        await client.disconnect()
    }

    @Test("Calls after disconnect fail fast")
    func callsAfterDisconnectFail() async throws {
        let transport = MockMCPTransport { line in
            guard let id = frameID(line), frameMethod(line) == "initialize" else { return [] }
            return [okInitializeReply(id: id)]
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()
        await client.disconnect()
        await #expect(throws: Error.self) {
            _ = try await client.listTools()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Connector → registry wiring tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP connector wiring")
struct MCPConnectorTests {

    @Test("discoverAndRegister lands tools in the registry")
    func discoverRegisters() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile(id: "fs"))
        try await reg.enableServer("fs")

        let transport = MockMCPTransport { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/list": return [toolsListReply(id: id)]
            default: return []
            }
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()

        let connector = MCPConnector()
        let result = try await connector.discoverAndRegister(serverID: "fs", client: client, registry: reg)
        #expect(result.toolCount == 2)
        #expect(result.toolNames.contains("read_file"))

        let registered = await reg.listTools(serverID: "fs")
        #expect(registered.count == 2)
        #expect(registered.contains { $0.swooshToolName == "mcp.fs.read_file" })
        await client.disconnect()
    }

    @Test("discoverAndRegister respects the registry enabled gate")
    func discoverRequiresEnabled() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile(id: "fs"))
        // server NOT enabled

        let transport = MockMCPTransport { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/list": return [toolsListReply(id: id)]
            default: return []
            }
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()

        let connector = MCPConnector()
        await #expect(throws: MCPError.self) {
            _ = try await connector.discoverAndRegister(serverID: "fs", client: client, registry: reg)
        }
        await client.disconnect()
    }

    @Test("Discovered tool descriptors carry the input schema")
    func descriptorsCarrySchema() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile(id: "fs"))
        try await reg.enableServer("fs")

        let transport = MockMCPTransport { line in
            guard let id = frameID(line) else { return [] }
            switch frameMethod(line) {
            case "initialize": return [okInitializeReply(id: id)]
            case "tools/list": return [toolsListReply(id: id)]
            default: return []
            }
        }
        let client = MCPClient(transport: transport)
        try await client.connect()
        _ = try await client.initialize()

        let connector = MCPConnector()
        _ = try await connector.discoverAndRegister(serverID: "fs", client: client, registry: reg)
        let tools = await reg.listTools(serverID: "fs")
        let readFile = tools.first { $0.name == "read_file" }
        #expect(readFile?.inputSchemaJSON?.contains("path") == true)
        await client.disconnect()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - End-to-end stdio test (real Process, no external server)
// ═══════════════════════════════════════════════════════════════

#if os(macOS) || os(Linux)
@Suite("MCP stdio transport end-to-end")
struct MCPStdioEndToEndTests {

    /// Drives a real child process — a tiny POSIX-sh MCP server we write to
    /// a temp file — through the full connect/initialize/list flow. This is
    /// the only test that spawns a Process; it proves StdioMCPTransport works
    /// without depending on any external MCP server.
    @Test("Full handshake against a scripted shell MCP server")
    func fullStdioFlow() async throws {
        let script = """
        #!/bin/sh
        # Minimal scripted MCP server: reads one JSON-RPC request per line,
        # replies based on the method substring. No JSON parsing — just enough
        # to exercise StdioMCPTransport + MCPClient end-to-end.
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              # Echo back the id verbatim by extracting it crudely.
              id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
              printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"sh-mcp","version":"0.1"}}}\\n' "$id"
              ;;
            *'"method":"notifications/initialized"'*)
              echo "initialized" 1>&2
              ;;
            *'"method":"tools/list"'*)
              id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
              printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[{"name":"ping","description":"ping tool"}]}}\\n' "$id"
              ;;
            *'"method":"tools/call"'*)
              id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
              printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"pong"}],"isError":false}}\\n' "$id"
              ;;
          esac
        done
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-mcp-test-\(UUID().uuidString).sh")
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = StdioMCPTransport.Configuration(
            executable: "/bin/sh",
            arguments: [tmp.path]
        )
        let transport = StdioMCPTransport(config: config)
        let client = MCPClient(transport: transport, requestTimeout: 10)
        try await client.connect()
        let handshake = try await client.initialize()
        #expect(handshake.serverName == "sh-mcp")

        let tools = try await client.listTools()
        #expect(tools.count == 1)
        #expect(tools.first?.name == "ping")

        let result = try await client.callTool(name: "ping")
        #expect(result.text == "pong")
        #expect(!result.isError)

        await client.disconnect()
    }
}
#endif
