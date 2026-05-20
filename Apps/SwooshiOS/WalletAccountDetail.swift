// Apps/SwooshiOS/WalletAccountDetail.swift — Per-account dashboard
//
// Pushed from WalletScreen. Shows the balance, the full address with
// copy/share + a receive-QR sheet, and reserves a slot for the upcoming
// send flow.

import SwiftUI
import CoreImage.CIFilterBuiltins
import SwooshWallet

struct WalletAccountDetail: View {
    @Environment(WalletSession.self) private var wallet
    let account: WalletAccount
    @State private var copied: Bool = false
    @State private var showingReceive: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 12) {
                    actionRow

                    addressCard
                }
                .padding(.horizontal, 16)

                comingSoonCard
                    .padding(.horizontal, 16)

                if let error = wallet.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 24)
        }
        .navigationTitle(account.chain.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReceive) {
            WalletReceiveSheet(account: account)
        }
        .task { await wallet.refreshBalance(for: account) }
        .refreshable { await wallet.refreshBalance(for: account) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ChainBadge(chain: account.chain, size: 64)
            Text(account.label)
                .font(.title3.weight(.semibold))
            balanceText
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
    }

    @ViewBuilder
    private var balanceText: some View {
        if wallet.refreshing.contains(account.id) {
            ProgressView()
        } else if let balance = wallet.balances[account.id] {
            Text(balance.formatted)
        } else {
            Text("— \(account.chain.nativeSymbol)").foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(symbol: "qrcode", label: "Receive") { showingReceive = true }
            actionButton(symbol: "paperplane", label: "Send", disabled: true) { }
            actionButton(symbol: "arrow.clockwise", label: "Refresh") {
                Task { await wallet.refreshBalance(for: account) }
            }
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(disabled ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
            )
            .foregroundStyle(disabled ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .overlay(alignment: .topTrailing) {
            if disabled {
                Text("next")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                    .foregroundStyle(.orange)
                    .padding(6)
            }
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Address")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(account.address)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
            HStack(spacing: 10) {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = account.address
                    #endif
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.medium))
                }
                ShareLink(item: account.address) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.footnote.weight(.medium))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var comingSoonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sending", systemImage: "paperplane")
                .font(.callout.weight(.semibold))
            Text("Signed transfers + token / SPL support land in the next iteration. Balances and receive are live now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

// MARK: - Receive sheet (QR)

struct WalletReceiveSheet: View {
    let account: WalletAccount
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Receive \(account.chain.nativeSymbol)")
                    .font(.title3.weight(.semibold))

                if let image = WalletReceiveSheet.qrImage(for: account.address) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Could not render QR")
                        .foregroundStyle(.red)
                }

                Text(account.address)
                    .font(.system(.footnote, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                ShareLink(item: account.address) {
                    Label("Share address", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    static func qrImage(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}
