// SwooshBrowser/BrowserSupervisor.swift — Launch/manage Chrome instances
import Foundation

/// Manages Chrome/Chromium process lifecycle for browser automation.
public actor BrowserSupervisor {
    private var process: Process?
    private var debugPort: Int
    private var chromePath: String?

    public init(debugPort: Int = 9222) {
        self.debugPort = debugPort
    }

    /// Find Chrome/Chromium on the system.
    public func findChrome() -> String? {
        let candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                chromePath = path
                return path
            }
        }
        return nil
    }

    /// Launch Chrome with remote debugging enabled.
    public func launch(headless: Bool = true, userDataDir: String? = nil) async throws {
        guard let chrome = findChrome() else { throw BrowserError.chromeNotFound }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chrome)

        var args = [
            "--remote-debugging-port=\(debugPort)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-sync",
        ]
        if headless { args.append("--headless=new") }
        if let dir = userDataDir {
            args.append("--user-data-dir=\(dir)")
        } else {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("swoosh-chrome-\(UUID().uuidString)")
            args.append("--user-data-dir=\(tmp.path)")
        }

        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()
        process = proc

        // Wait for CDP to become available
        try await Task.sleep(for: .seconds(1.5))
    }

    /// Connect to the running Chrome instance.
    public func connect() async throws -> CDPConnection {
        let endpoint = URL(string: "http://localhost:\(debugPort)")!
        let connection = try await CDPConnection.fromDebugEndpoint(endpoint)
        try await connection.connect()
        return connection
    }

    /// Create a full browser session.
    public func createSession(headless: Bool = true) async throws -> CDPBrowserSession {
        if process == nil || !(process?.isRunning ?? false) {
            try await launch(headless: headless)
        }
        let connection = try await connect()
        return CDPBrowserSession(connection: connection)
    }

    /// Shut down Chrome.
    public func shutdown() {
        process?.terminate()
        process = nil
    }

    /// Whether Chrome is running.
    public var isRunning: Bool { process?.isRunning ?? false }
}
