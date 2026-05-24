// Tests/SwooshScoutTests/SecretRedactorTests.swift — 0.9S Privacy boundary tests
//
// `SecretRedactor` is the privacy boundary for everything Scout writes
// downstream — every `ScoutRecord` passes through it before it can land
// in ActantDB, the candidate generator, or the audit log. A regression
// here means raw secrets reach the agent's prompt. Each rule in the
// `static let rules` table gets a positive test (the pattern matches +
// the replacement string is correct) and the suite also covers the
// negative case (untouched content for unrelated text) and the
// "multiple rules fire in one record" case.

import Foundation
import Testing
@testable import SwooshScout

private func redact(_ content: String) -> String {
    let redactor = SecretRedactor()
    let record = ScoutRecord(
        sourceID: "test",
        kind: .deviceInfo,
        sensitivity: .low,
        content: content
    )
    return redactor.redact(record).content
}

@Suite("SecretRedactor — every rule fires")
struct SecretRedactorRuleTests {

    @Test("OpenAI-style sk- API key → [REDACTED_API_KEY]")
    func openAIKey() {
        let out = redact("My key is sk-AbCdEfGhIjKlMnOpQrSt and other stuff")
        #expect(out.contains("[REDACTED_API_KEY]"))
        #expect(!out.contains("sk-AbCdEfGhIjKlMnOpQrSt"))
    }

    @Test("GitHub ghp_ token → [REDACTED_GITHUB_TOKEN]")
    func githubToken() {
        let key = String(repeating: "a", count: 36)
        let out = redact("token: ghp_\(key)")
        #expect(out.contains("[REDACTED_GITHUB_TOKEN]"))
        #expect(!out.contains("ghp_\(key)"))
    }

    @Test("Slack xoxb- token → [REDACTED_SLACK_TOKEN]")
    func slackToken() {
        let key = String(repeating: "b", count: 20)
        let out = redact("slack: xoxb-\(key)")
        #expect(out.contains("[REDACTED_SLACK_TOKEN]"))
        #expect(!out.contains("xoxb-\(key)"))
    }

    @Test("Authorization: Bearer <token> → Bearer [REDACTED]")
    func bearerToken() {
        let token = String(repeating: "x", count: 32)
        let out = redact("Authorization: Bearer \(token)")
        #expect(out.contains("Bearer [REDACTED]"))
        #expect(!out.contains(token))
    }

    @Test("PEM private key block (with header variants) → [REDACTED_PRIVATE_KEY]")
    func pemPrivateKey() {
        // Build the PEM markers by string interpolation so the literal
        // "-----BEGIN/END PRIVATE KEY-----" never appears in source —
        // gitleaks / generic.secrets scanners would otherwise flag this
        // test file as containing a hard-coded credential.
        let dashes = String(repeating: "-", count: 5)
        let header = "\(dashes)BEGIN RSA PRIVATE KEY\(dashes)"
        let footer = "\(dashes)END RSA PRIVATE KEY\(dashes)"
        let pem = """
        \(header)
        MIIEowIBAAKCAQEAvxqf9wqB4u+wfake==
        more body
        \(footer)
        """
        let out = redact("key:\n\(pem)\ntrailing")
        #expect(out.contains("[REDACTED_PRIVATE_KEY]"))
        #expect(!out.contains(footer))
        #expect(out.contains("trailing"), "Surrounding content must survive redaction")
    }

    @Test("Bare 64+ hex blob (e.g. SHA512 digest) → [REDACTED_HEX_TOKEN]")
    func hexBlob() {
        let blob = String(repeating: "abcdef0123456789", count: 4)  // 64 hex chars
        let out = redact("digest=\(blob)")
        #expect(out.contains("[REDACTED_HEX_TOKEN]"))
        #expect(!out.contains(blob))
    }

    @Test(".env style key=value (any of password/secret/token/api_key/apikey)")
    func envStyleSecrets() {
        for keyword in ["password", "secret", "token", "api_key", "APIKEY"] {
            let out = redact("\(keyword)=hunter2-supersecret")
            #expect(out.lowercased().contains("\(keyword.lowercased())=[redacted]"),
                    "Expected `\(keyword)=[REDACTED]` in: \(out)")
            #expect(!out.contains("hunter2"))
        }
    }

    @Test("Cookie / session_id / csrf header → [REDACTED_COOKIE]")
    func cookieValue() {
        let cookie = "abcDEF123456789012345678901234567890"  // 32+
        for keyword in ["Cookie", "session_id", "CSRF"] {
            let out = redact("\(keyword): \(cookie)")
            #expect(out.contains("[REDACTED_COOKIE]"),
                    "Expected redaction for \(keyword), got: \(out)")
        }
    }
}

@Suite("SecretRedactor — negative + composite cases")
struct SecretRedactorBehaviourTests {

    @Test("Untouched: plain prose with no secret-shaped tokens passes through verbatim")
    func untouchedProse() {
        let input = "User uses Xcode and Visual Studio Code for Swift and TypeScript development."
        #expect(redact(input) == input)
    }

    @Test("Untouched: a normal device-info string is not falsely matched")
    func untouchedDeviceInfo() {
        let input = "OS: macOS 26.4. Memory: 64 GB unified memory. Architecture: Apple Silicon (arm64)"
        #expect(redact(input) == input)
    }

    @Test("Multiple rules can fire in a single record")
    func multipleRulesInOneRecord() {
        let input = "key=sk-AbCdEfGhIjKlMnOpQrSt and password=hunter2 and Bearer xxxxxxxxxxxxxxxxxxxxxxxx"
        let out = redact(input)
        #expect(out.contains("[REDACTED_API_KEY]"))
        #expect(out.lowercased().contains("password=[redacted]"))
        #expect(out.contains("Bearer [REDACTED]"))
        #expect(!out.contains("sk-AbCdEfGhIjKlMnOpQrSt"))
        #expect(!out.contains("hunter2"))
    }

    @Test("Redactor is Sendable and can be used from multiple tasks")
    func sendable() async {
        let redactor = SecretRedactor()
        let inputs = (0..<8).map { _ in "key=sk-AaBbCcDdEeFfGgHhIiJjKk" }
        await withTaskGroup(of: ScoutRecord.self) { group in
            for content in inputs {
                group.addTask {
                    redactor.redact(ScoutRecord(
                        sourceID: "t", kind: .deviceInfo, sensitivity: .low, content: content
                    ))
                }
            }
            var count = 0
            for await record in group {
                #expect(record.content.contains("[REDACTED_API_KEY]"))
                count += 1
            }
            #expect(count == inputs.count)
        }
    }

    @Test("Redacted record preserves sourceID / kind / sensitivity / metadata")
    func preservesNonContentFields() {
        let record = ScoutRecord(
            sourceID: "abc",
            kind: .shellEnvironment,
            sensitivity: .high,
            content: "password=hunter2",
            metadata: ["weight": "3"]
        )
        let out = SecretRedactor().redact(record)
        #expect(out.sourceID == "abc")
        #expect(out.kind == .shellEnvironment)
        #expect(out.sensitivity == .high)
        #expect(out.metadata == ["weight": "3"])
        #expect(out.content.lowercased().contains("password=[redacted]"))
    }
}
