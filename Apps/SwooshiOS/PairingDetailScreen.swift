// Apps/SwooshiOS/PairingDetailScreen.swift
// Version: 0.9R
//
// Extracted from SettingsScreen.swift to honor the <350 LOC convention.
// Hosts the pairing form (host URL + bearer token + QR scan) used by
// the Settings → Daemon → Pairing row.

import SwiftUI
import SwooshClient
import Vision
#if os(iOS)
import UIKit
import AVFoundation
#endif

struct PairingDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var hostText: String = ""
    @State private var tokenText: String = ""
    @State private var saveError: String?
    @State private var isProbing: Bool = false
    @State private var isScanning: Bool = false
    @State private var scanError: String?
    @State private var showScanner: Bool = false
    @State private var pairedFeedback: Int = 0
    @State private var errorFeedback: Int = 0

    var body: some View {
        Form {
            Section {
                LabeledContent("Daemon", value: statusLabel)
                if let host = session.host {
                    LabeledContent("Host", value: host.absoluteString)
                }
                if let status = session.agentStatus {
                    LabeledContent("Provider", value: status.provider ?? "Not configured")
                    LabeledContent("Model", value: status.model ?? "Unavailable")
                }
                if let config = session.runtimeConfig {
                    LabeledContent("Profile", value: config.permissionProfile ?? "Unconfigured")
                    LabeledContent("Mode", value: config.setupMode ?? "Unknown")
                }
            } header: {
                Text("Current pairing")
            }

            Section("Pair with swooshd") {
                TextField("http://mac.local:8787", text: $hostText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Bearer token", text: $tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    startQRScan()
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan QR Code")
                        Spacer()
                        if isScanning { ProgressView() }
                    }
                }
                .disabled(isScanning)
                .sheet(isPresented: $showScanner) {
                    QRScannerView { result in
                        processQRCode(result)
                        showScanner = false
                    }
                }
            }

            if let saveError {
                Section {
                    ErrorRow(message: saveError) { await save() }
                }
            }

            if let scanError {
                Section {
                    Label(scanError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Pair with daemon")
                        Spacer()
                        if isProbing { ProgressView() }
                    }
                }
                .disabled(hostText.isEmpty || tokenText.isEmpty || isProbing)

                if session.isPaired {
                    Button("Unpair", role: .destructive) {
                        Task { await session.unpair() }
                    }
                }
            }

            Section("Where do I find the token?") {
                Text("On your Mac, run `cd /Users/home/swoosh && SWOOSH_HOST=0.0.0.0 swift run swooshd`, then read `~/.swoosh/api_token`. Paste that here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: pairedFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .onAppear {
            if hostText.isEmpty, let host = session.host {
                hostText = host.absoluteString
            }
        }
    }

    private var statusLabel: String {
        switch session.lastHealth {
        case .ok:          "Reachable"
        case .unreachable: "Unreachable"
        case .unknown:     "Not paired"
        }
    }

    private func save() async {
        withAnimation(.easeOut(duration: 0.22)) { saveError = nil }
        guard let url = URL(string: hostText), url.scheme != nil else {
            withAnimation(.easeOut(duration: 0.22)) {
                saveError = "Host URL must include scheme (http:// or https://)."
            }
            errorFeedback &+= 1
            return
        }
        guard !tokenText.isEmpty else {
            withAnimation(.easeOut(duration: 0.22)) {
                saveError = "Paste the bearer token from ~/.swoosh/api_token before pairing."
            }
            errorFeedback &+= 1
            return
        }
        isProbing = true
        defer { isProbing = false }

        let probe = SwooshAPIClient(baseURL: url, token: tokenText)
        let healthy = await probe.health()
        if !healthy {
            withAnimation(.easeOut(duration: 0.22)) {
                saveError = "Couldn't reach \(url.host ?? "host"). Check that swooshd is running and reachable from this phone."
            }
            errorFeedback &+= 1
            return
        }
        do {
            _ = try await probe.agentStatus()
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                saveError = "Reached swooshd, but the bearer token was rejected. Check ~/.swoosh/api_token on your Mac."
            }
            errorFeedback &+= 1
            return
        }
        do {
            try await session.pair(host: url, token: tokenText)
            tokenText = ""
            pairedFeedback &+= 1
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                saveError = error.localizedDescription
            }
            errorFeedback &+= 1
        }
    }

    private func startQRScan() {
        scanError = nil
        isScanning = true

        #if os(iOS)
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.isScanning = false
                    self.showScanner = true
                } else {
                    self.scanError = "Camera permission denied"
                    self.isScanning = false
                }
            }
        }
        #else
        scanError = "QR scanning requires iOS"
        isScanning = false
        #endif
    }

    private func processQRCode(_ result: String) {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = json["host"] as? String,
              let token = json["token"] as? String else {
            scanError = "Invalid QR code format. Expected JSON with host and token."
            return
        }

        hostText = host
        tokenText = token
        scanError = nil
    }
}

#if os(iOS)
class QRScannerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let completion: (String) -> Void

    init(completion: @escaping (String) -> Void) {
        self.completion = completion
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage,
              let cgImage = image.cgImage else {
            self.completion("")
            return
        }

        let request = VNDetectBarcodesRequest { request, error in
            let fire: (String) -> Void = { result in
                DispatchQueue.main.async { self.completion(result) }
            }
            if let error = error {
                print("QR detection error: \(error)")
                fire("")
                return
            }
            guard let observations = request.results as? [VNBarcodeObservation],
                  let first = observations.first,
                  let payload = first.payloadStringValue else {
                fire("")
                return
            }
            fire(payload)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        self.completion("")
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let completion: (String) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> QRScannerDelegate {
        QRScannerDelegate(completion: completion)
    }
}
#endif
