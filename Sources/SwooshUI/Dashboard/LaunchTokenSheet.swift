// SwooshUI/Dashboard/LaunchTokenSheet.swift — Token launch form — 0.9Y
//
// Collects the launch metadata (logo image, socials, dev-buy) and submits it
// through the tool pipeline: POST /api/tools/:name/execute → ToolRegistry.call
// (firewall + audit + askEveryTime approval + $DTOUR gate). Today only
// pump.fun executes, and only in PREPARE mode (pins IPFS metadata, no
// broadcast). Args are built as a raw JSON string so this view stays
// SwooshClient-only (no SwooshToolsets import).

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import SwooshGenerativeUI
import SwooshClient

struct LaunchTokenSheet: View {
    let platformID: String
    let platformName: String
    let onClose: () -> Void

    @State private var name = ""
    @State private var symbol = ""
    @State private var tokenDescription = ""
    @State private var website = ""
    @State private var twitter = ""
    @State private var telegram = ""
    @State private var devBuySOL = "0"
    @State private var imageData: Data?
    @State private var imageMime = "image/png"
    @State private var imageName: String?
    @State private var showImporter = false
    @State private var isSubmitting = false
    @State private var result: ResultState?

    private enum ResultState { case prepared(String), pending, info(String), error(String) }

    private var toolName: String? {
        switch platformID.lowercased() {
        case "pumpportal", "pump", "pumpfun", "pump.fun": return "launchpad.pumpportal.launch"
        case "bags": return "launchpad.bags.launch"
        case "flap": return "launchpad.flap.launch"
        case "four-meme", "fourmeme", "four_meme": return "launchpad.four_meme.launch"
        default: return nil
        }
    }

    private var isPump: Bool { toolName == "launchpad.pumpportal.launch" }
    private var canSubmit: Bool {
        !name.isEmpty && !symbol.isEmpty && imageData != nil && !isSubmitting && toolName != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !isPump {
                    notice("Only pump.fun launches are wired today. \(platformName) collects metadata but its executor is not implemented yet.")
                } else {
                    notice("pump.fun launches run in PREPARE mode: this pins your logo + metadata to IPFS and assembles the launch for review. It does not broadcast or move funds yet.")
                }
                imageWell
                field("Token Name", text: $name, placeholder: "My Token")
                field("Symbol", text: $symbol, placeholder: "MYTKN")
                field("Description", text: $tokenDescription, placeholder: "The next big thing…")
                field("Website", text: $website, placeholder: "https://…")
                field("Twitter / X", text: $twitter, placeholder: "https://x.com/…")
                field("Telegram", text: $telegram, placeholder: "https://t.me/…")
                field("Dev buy (SOL)", text: $devBuySOL, placeholder: "0")
                if let result { resultView(result) }
                actions
            }
            .padding(24)
        }
        .frame(width: 460, height: 640)
        .background(VoltPaper.background)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.png, .jpeg, .gif, .image]) { res in
            handlePickedFile(res)
        }
    }

    private var header: some View {
        HStack {
            Text("Launch on \(platformName)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(VoltPaper.foreground)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(VoltPaper.mutedFg)
            }
            .buttonStyle(.plain)
        }
    }

    private var imageWell: some View {
        Button { showImporter = true } label: {
            HStack(spacing: 12) {
                if let imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VoltPaper.foreground.opacity(0.05))
                        .frame(width: 54, height: 54)
                        .overlay(Image(systemName: "photo.badge.plus").foregroundStyle(VoltPaper.mutedFg))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(imageName ?? "Choose logo image")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VoltPaper.foreground)
                    Text("PNG / JPG / GIF · square ~1000×1000 recommended")
                        .font(.system(size: 10))
                        .foregroundStyle(VoltPaper.mutedFg)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VoltPaper.foreground.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(VoltPaper.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onClose)
                .buttonStyle(.plain)
                .foregroundStyle(VoltPaper.mutedFg)
                .disabled(isSubmitting)
            Button { Task { await submit() } } label: {
                HStack(spacing: 6) {
                    if isSubmitting { ProgressView().controlSize(.small) }
                    Image(systemName: "bolt.fill")
                    Text(isPump ? "Prepare Launch" : "Submit")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(VoltPaper.accentFg)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(Capsule().fill(VoltPaper.accent))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private func resultView(_ state: ResultState) -> some View {
        switch state {
        case .prepared(let summary):
            calloutBox(summary, color: VoltPaper.accent, icon: "checkmark.seal")
        case .pending:
            calloutBox("Sent for approval — open the Approvals tab to confirm before it runs.", color: VoltPaper.Chart.c4, icon: "hourglass")
        case .info(let msg):
            calloutBox(msg, color: VoltPaper.Chart.c1, icon: "info.circle")
        case .error(let msg):
            calloutBox(msg, color: VoltPaper.destructive, icon: "exclamationmark.triangle")
        }
    }

    private func calloutBox(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(VoltPaper.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(VoltPaper.mutedFg)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(VoltPaper.mutedFg)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(isSubmitting)
        }
    }

    // MARK: - File pick

    private func handlePickedFile(_ res: Result<URL, Error>) {
        switch res {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                result = .error("Could not read the selected image.")
                return
            }
            if data.count > 5_000_000 {
                result = .error("Image is \(data.count / 1_000_000)MB — please pick one under 5MB.")
                return
            }
            imageData = data
            imageName = url.lastPathComponent
            imageMime = Self.mime(for: url.pathExtension)
            result = nil
        case .failure(let err):
            result = .error(err.localizedDescription)
        }
    }

    private static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard let toolName, let client = SwooshDaemonClient.client() else {
            result = .error("Daemon not reachable.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let args = buildArgsJSON()
        do {
            let response = try await client.executeTool(name: toolName, body: ToolExecuteRequest(argsJSON: args))
            if response.success, let out = response.outputJSON {
                interpretOutput(out)
            } else if let err = response.error {
                let lower = err.lowercased()
                if lower.contains("approval") || lower.contains("pending") {
                    result = .pending
                } else if lower.contains("notimplemented") || lower.contains("pending") {
                    result = .info(err)
                } else {
                    result = .error(err)
                }
            } else {
                result = .error("Unknown response from daemon.")
            }
        } catch {
            result = .error(error.localizedDescription)
        }
    }

    private func interpretOutput(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            result = .info("Submitted.")
            return
        }
        let summary = (obj["reviewSummary"] as? String) ?? "Prepared."
        result = .prepared(summary)
    }

    private func buildArgsJSON() -> String {
        var dict: [String: Any] = [
            "platformID": platformID,
            "name": name,
            "symbol": symbol,
            "description": tokenDescription,
        ]
        if let imageData { dict["imageBase64"] = imageData.base64EncodedString(); dict["imageMimeType"] = imageMime }
        if !website.isEmpty { dict["website"] = website }
        if !twitter.isEmpty { dict["twitter"] = twitter }
        if !telegram.isEmpty { dict["telegram"] = telegram }
        if let buy = Double(devBuySOL) { dict["devBuySOL"] = buy }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

#endif
