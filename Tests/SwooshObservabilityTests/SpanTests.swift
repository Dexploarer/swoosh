// Tests/SwooshObservabilityTests/SpanTests.swift — Span and tracing tests
//
// Tests the OpenTelemetry-inspired span model, span lifecycle,
// and token usage tracking within spans.

import Testing
import Foundation
@testable import SwooshObservability

// MARK: - SpanKind Tests

@Suite("SpanKind")
struct SpanKindTests {

    @Test("All SpanKind cases exist")
    func allCasesExist() {
        let kinds: [SpanKind] = [
            .agent, .inference, .tool, .approval,
            .workflow, .system, .browser, .media, .skill
        ]
        #expect(kinds.count == 9)
    }

    @Test("SpanKind raw values are correct")
    func rawValuesCorrect() {
        #expect(SpanKind.agent.rawValue == "agent")
        #expect(SpanKind.inference.rawValue == "inference")
        #expect(SpanKind.tool.rawValue == "tool")
        #expect(SpanKind.approval.rawValue == "approval")
        #expect(SpanKind.workflow.rawValue == "workflow")
        #expect(SpanKind.system.rawValue == "system")
        #expect(SpanKind.browser.rawValue == "browser")
        #expect(SpanKind.media.rawValue == "media")
        #expect(SpanKind.skill.rawValue == "skill")
    }

    @Test("SpanKind is Codable and Sendable")
    func isCodableAndSendable() {
        let kind: SpanKind = .inference

        // Codable
        let data = try? JSONEncoder().encode(kind)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(SpanKind.self, from: data!)
        #expect(decoded == .inference)

        // Sendable (compile-time check)
        let _: any Sendable.Type = SpanKind.self
    }
}

// MARK: - SpanStatus Tests

@Suite("SpanStatus")
struct SpanStatusTests {

    @Test("All SpanStatus cases exist")
    func allCasesExist() {
        let statuses: [SpanStatus] = [.running, .ok, .error, .cancelled, .timedOut]
        #expect(statuses.count == 5)
    }

    @Test("SpanStatus raw values are correct")
    func rawValuesCorrect() {
        #expect(SpanStatus.running.rawValue == "running")
        #expect(SpanStatus.ok.rawValue == "ok")
        #expect(SpanStatus.error.rawValue == "error")
        #expect(SpanStatus.cancelled.rawValue == "cancelled")
        #expect(SpanStatus.timedOut.rawValue == "timedOut")
    }

    @Test("SpanStatus is Codable and Sendable")
    func isCodableAndSendable() {
        let status: SpanStatus = .ok

        // Codable
        let data = try? JSONEncoder().encode(status)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(SpanStatus.self, from: data!)
        #expect(decoded == .ok)
    }
}

// MARK: - SpanEvent Tests

@Suite("SpanEvent")
struct SpanEventTests {

    @Test("Event initializes with name")
    func initializesWithName() {
        let event = SpanEvent(name: "tool_returned")

        #expect(event.name == "tool_returned")
        #expect(event.attributes.isEmpty)
        #expect(event.id != "")
        #expect(event.timestamp <= Date())
    }

    @Test("Event initializes with attributes")
    func initializesWithAttributes() {
        let event = SpanEvent(
            name: "budget_warning",
            attributes: ["threshold": "0.80", "current": "0.85"]
        )

        #expect(event.name == "budget_warning")
        #expect(event.attributes["threshold"] == "0.80")
        #expect(event.attributes["current"] == "0.85")
    }

    @Test("Event is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let event = SpanEvent(name: "test")

        // Identifiable
        _ = event.id

        // Codable
        let data = try? JSONEncoder().encode(event)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = SpanEvent.self
    }

    @Test("Event round-trip encoding")
    func roundTrip() throws {
        let original = SpanEvent(
            name: "test_event",
            attributes: ["key1": "value1", "key2": "value2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpanEvent.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.attributes == original.attributes)
        #expect(decoded.timestamp == original.timestamp)
    }
}

// MARK: - TokenUsage Tests

@Suite("TokenUsage")
struct TokenUsageTests {

    @Test("Usage initializes with all values")
    func initializesCorrectly() {
        let usage = TokenUsage(
            promptTokens: 1000,
            completionTokens: 500,
            provider: "openai",
            model: "gpt-4o"
        )

        #expect(usage.promptTokens == 1000)
        #expect(usage.completionTokens == 500)
        #expect(usage.totalTokens == 1500)
        #expect(usage.provider == "openai")
        #expect(usage.model == "gpt-4o")
    }

    @Test("Total tokens calculated correctly")
    func totalCalculated() {
        let usage = TokenUsage(
            promptTokens: 2000,
            completionTokens: 1000,
            provider: "test",
            model: "test"
        )

        #expect(usage.totalTokens == 3000)
    }

    @Test("TokenUsage is Codable and Sendable")
    func conformsToProtocols() {
        let usage = TokenUsage(
            promptTokens: 100,
            completionTokens: 100,
            provider: "test",
            model: "test"
        )

        // Codable
        let data = try? JSONEncoder().encode(usage)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = TokenUsage.self
    }
}

// MARK: - Span Tests

@Suite("Span Initialization")
struct SpanInitializationTests {

    @Test("Span initializes with required values")
    func initializesWithRequired() {
        let span = Span(
            traceID: "trace-123",
            name: "inference_call",
            kind: .inference
        )

        #expect(span.traceID == "trace-123")
        #expect(span.name == "inference_call")
        #expect(span.kind == .inference)
        #expect(span.status == .running)
        #expect(span.attributes.isEmpty)
        #expect(span.events.isEmpty)
        #expect(span.parentSpanID == nil)
        #expect(span.endTime == nil)
        #expect(span.tokenUsage == nil)
        #expect(span.costUSD == nil)
        #expect(span.id != "")
        #expect(span.startTime <= Date())
    }

    @Test("Span initializes with parent")
    func initializesWithParent() {
        let parent = Span(
            traceID: "trace-123",
            name: "agent_turn",
            kind: .agent
        )

        let child = Span(
            traceID: "trace-123",
            parentSpanID: parent.id,
            name: "tool_execution",
            kind: .tool
        )

        #expect(child.parentSpanID == parent.id)
        #expect(child.traceID == parent.traceID)
    }

    @Test("Span initializes with attributes")
    func initializesWithAttributes() {
        let span = Span(
            traceID: "trace-123",
            name: "workflow_step",
            kind: .workflow,
            attributes: ["step_name": "build", "target": "debug"]
        )

        #expect(span.attributes["step_name"] == "build")
        #expect(span.attributes["target"] == "debug")
    }

    @Test("Span is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .system
        )

        // Identifiable
        _ = span.id

        // Codable
        let data = try? JSONEncoder().encode(span)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = Span.self
    }
}

@Suite("Span Lifecycle")
struct SpanLifecycleTests {

    @Test("Finish sets status and end time")
    func finishSetsStatusAndTime() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .tool
        )

        span.finish(status: .ok)

        #expect(span.status == .ok)
        #expect(span.endTime != nil)
        #expect(span.endTime! >= span.startTime)
    }

    @Test("Finish with error status")
    func finishWithError() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .tool
        )

        span.finish(status: .error)

        #expect(span.status == .error)
    }

    @Test("Finish with cancelled status")
    func finishWithCancelled() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .tool
        )

        span.finish(status: .cancelled)

        #expect(span.status == .cancelled)
    }

    @Test("Finish with timedOut status")
    func finishWithTimedOut() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .tool
        )

        span.finish(status: .timedOut)

        #expect(span.status == .timedOut)
    }

    @Test("Duration is nil while running")
    func durationNilWhileRunning() {
        let span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .inference
        )

        #expect(span.duration == nil)
    }

    @Test("Duration is set after finish")
    func durationSetAfterFinish() throws {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .inference
        )

        // Simulate some work
        Thread.sleep(forTimeInterval: 0.01)

        span.finish(status: .ok)

        let duration = try #require(span.duration)
        #expect(duration >= 0.01)
    }
}

@Suite("Span Events")
struct SpanEventTests2 {

    @Test("AddEvent appends event to span")
    func addEventAppends() {
        var span = Span(
            traceID: "trace-123",
            name: "inference",
            kind: .inference
        )

        span.addEvent("prompt_received", attributes: ["tokens": "1000"])

        #expect(span.events.count == 1)
        #expect(span.events[0].name == "prompt_received")
        #expect(span.events[0].attributes["tokens"] == "1000")
    }

    @Test("AddEvent multiple times")
    func addEventMultiple() {
        var span = Span(
            traceID: "trace-123",
            name: "inference",
            kind: .inference
        )

        span.addEvent("prompt_received")
        span.addEvent("generation_started")
        span.addEvent("generation_completed", attributes: ["tokens": "500"])

        #expect(span.events.count == 3)
        #expect(span.events[0].name == "prompt_received")
        #expect(span.events[1].name == "generation_started")
        #expect(span.events[2].name == "generation_completed")
    }
}

@Suite("Span Token Usage and Cost")
struct SpanTokenAndCostTests {

    @Test("Set token usage")
    func setTokenUsage() {
        var span = Span(
            traceID: "trace-123",
            name: "inference",
            kind: .inference
        )

        span.tokenUsage = TokenUsage(
            promptTokens: 1000,
            completionTokens: 500,
            provider: "openai",
            model: "gpt-4o"
        )

        #expect(span.tokenUsage?.promptTokens == 1000)
        #expect(span.tokenUsage?.completionTokens == 500)
        #expect(span.tokenUsage?.totalTokens == 1500)
    }

    @Test("Set cost USD")
    func setCost() {
        var span = Span(
            traceID: "trace-123",
            name: "inference",
            kind: .inference
        )

        span.costUSD = 0.025

        #expect(span.costUSD == 0.025)
    }

    @Test("Complete span with all metadata")
    func completeSpan() {
        var span = Span(
            traceID: "trace-123",
            name: "inference",
            kind: .inference,
            attributes: ["model": "gpt-4o", "temperature": "0.7"]
        )

        span.addEvent("prompt_received")
        span.tokenUsage = TokenUsage(
            promptTokens: 2000,
            completionTokens: 1000,
            provider: "openai",
            model: "gpt-4o"
        )
        span.costUSD = 0.015

        span.finish(status: .ok)

        #expect(span.status == .ok)
        #expect(span.endTime != nil)
        #expect(span.tokenUsage != nil)
        #expect(span.costUSD != nil)
        #expect(span.events.count == 1)
    }
}

@Suite("Span Edge Cases")
struct SpanEdgeCaseTests {

    @Test("Span handles empty name")
    func handlesEmptyName() {
        let span = Span(
            traceID: "trace-123",
            name: "",
            kind: .system
        )

        #expect(span.name == "")
    }

    @Test("Span handles long name")
    func handlesLongName() {
        let longName = String(repeating: "a", count: 1000)
        let span = Span(
            traceID: "trace-123",
            name: longName,
            kind: .system
        )

        #expect(span.name.count == 1000)
    }

    @Test("Span handles many attributes")
    func handlesManyAttributes() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .system
        )

        for i in 1...100 {
            span.attributes["key\(i)"] = "value\(i)"
        }

        #expect(span.attributes.count == 100)
    }

    @Test("Span handles many events")
    func handlesManyEvents() {
        var span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .inference
        )

        for i in 1...50 {
            span.addEvent("event_\(i)", attributes: ["iteration": "\(i)"])
        }

        #expect(span.events.count == 50)
    }

    @Test("Nested span structure")
    func nestedSpanStructure() {
        let root = Span(
            traceID: "trace-123",
            name: "agent_turn",
            kind: .agent
        )

        let inference = Span(
            traceID: "trace-123",
            parentSpanID: root.id,
            name: "model_call",
            kind: .inference
        )

        let tool1 = Span(
            traceID: "trace-123",
            parentSpanID: root.id,
            name: "tool_1",
            kind: .tool
        )

        let tool2 = Span(
            traceID: "trace-123",
            parentSpanID: root.id,
            name: "tool_2",
            kind: .tool
        )

        // Verify hierarchy
        #expect(inference.parentSpanID == root.id)
        #expect(tool1.parentSpanID == root.id)
        #expect(tool2.parentSpanID == root.id)
        #expect(inference.traceID == root.traceID)
    }

    @Test("Span timestamps are consistent")
    func timestampsConsistent() {
        let before = Date()
        let span = Span(
            traceID: "trace-123",
            name: "test",
            kind: .system
        )
        let after = Date()

        #expect(span.startTime >= before)
        #expect(span.startTime <= after)
    }
}

@Suite("Span JSON Serialization")
struct SpanJSONTests {

    @Test("Serializes to valid JSON")
    func serializesToJSON() throws {
        let span = Span(
            traceID: "trace-123",
            parentSpanID: "parent-456",
            name: "inference",
            kind: .inference,
            attributes: ["model": "gpt-4o"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(span)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["traceID"] as? String == "trace-123")
        #expect(json?["parentSpanID"] as? String == "parent-456")
        #expect(json?["name"] as? String == "inference")
        #expect(json?["kind"] as? String == "inference")
        #expect(json?["status"] as? String == "running")
    }

    @Test("Deserializes from JSON")
    func deserializesFromJSON() throws {
        let json = """
        {
            "id": "span-123",
            "traceID": "trace-456",
            "parentSpanID": "parent-789",
            "name": "tool_execution",
            "kind": "tool",
            "status": "ok",
            "attributes": {"tool_name": "git.status"},
            "events": [
                {
                    "id": "evt-1",
                    "name": "started",
                    "timestamp": "2024-01-01T00:00:00Z",
                    "attributes": {}
                }
            ],
            "startTime": "2024-01-01T00:00:00Z",
            "endTime": "2024-01-01T00:00:01Z",
            "tokenUsage": {
                "promptTokens": 100,
                "completionTokens": 50,
                "provider": "openai",
                "model": "gpt-4o"
            },
            "costUSD": 0.005
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let span = try decoder.decode(Span.self, from: json.data(using: .utf8)!)

        #expect(span.id == "span-123")
        #expect(span.traceID == "trace-456")
        #expect(span.parentSpanID == "parent-789")
        #expect(span.name == "tool_execution")
        #expect(span.kind == .tool)
        #expect(span.status == .ok)
        #expect(span.attributes["tool_name"] == "git.status")
        #expect(span.events.count == 1)
        #expect(span.endTime != nil)
        #expect(span.tokenUsage?.promptTokens == 100)
        #expect(span.costUSD == 0.005)
    }
}
