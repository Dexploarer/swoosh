// SwooshDaemonSupport/DaemonTokenResolver.swift — swooshd bearer token resolution

import Foundation
#if canImport(Security)
import Security
#endif

public enum DaemonTokenError: Error, Sendable, LocalizedError {
    case secureRandomUnavailable(Int32)

    public var errorDescription: String? {
        switch self {
        case .secureRandomUnavailable(let status):
            return "SecRandomCopyBytes failed with status \(status)"
        }
    }
}

public enum DaemonTokenResolver {
    public static func resolve(swooshDir: URL, env: [String: String]) throws -> String {
        try resolve(swooshDir: swooshDir, env: env, tokenGenerator: mintToken)
    }

    public static func resolve(
        swooshDir: URL,
        env: [String: String],
        tokenGenerator: () throws -> String
    ) throws -> String {
        if let explicit = env["SWOOSH_API_TOKEN"], !explicit.isEmpty {
            return explicit
        }

        let tokenFile = swooshDir.appendingPathComponent("api_token")
        if let data = try? Data(contentsOf: tokenFile),
           let cached = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }

        let fresh = try tokenGenerator()
        try FileManager.default.createDirectory(at: swooshDir, withIntermediateDirectories: true)
        try Data(fresh.utf8).write(to: tokenFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        return fresh
    }

    public static func mintToken() throws -> String {
        #if canImport(Security)
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DaemonTokenError.secureRandomUnavailable(Int32(status))
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #else
        throw DaemonTokenError.secureRandomUnavailable(-1)
        #endif
    }
}
