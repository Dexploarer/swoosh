// SwooshUI/Dashboard/WalletCreateSheet.swift — Create-wallet form sheet — 0.9Y
//
// Collects chain + label and hands them back to WalletPane, which posts to
// POST /api/wallet/accounts. Chain ids match SwooshWallet.WalletChain raw
// values (solana/ethereum/base/bnb) but are kept as strings so SwooshUI
// stays SwooshClient-only (no SwooshWallet dependency).

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI

struct WalletCreateSheet: View {
    let isCreating: Bool
    let errorMessage: String?
    let onCreate: (_ chain: String, _ label: String) -> Void
    let onCancel: () -> Void

    @State private var chain = "solana"
    @State private var label = ""

    private let chains: [(id: String, name: String, icon: String, color: Color)] = [
        ("solana", "Solana", "s.circle.fill", VoltPaper.Chart.c1),
        ("ethereum", "Ethereum", "e.circle.fill", VoltPaper.Chart.c3),
        ("base", "Base", "b.square.fill", VoltPaper.Chart.c3),
        ("bnb", "BNB Chain", "b.circle.fill", VoltPaper.Chart.c4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Wallet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(VoltPaper.foreground)

            VStack(alignment: .leading, spacing: 8) {
                Text("CHAIN")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(VoltPaper.mutedFg)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(chains, id: \.id) { c in
                        chainOption(c)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LABEL (OPTIONAL)")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(VoltPaper.mutedFg)
                TextField("e.g. Trading wallet", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCreating)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(VoltPaper.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("A fresh keypair is generated and stored in your Keychain. Detour never imports or accepts private keys or seed phrases.")
                .font(.system(size: 10))
                .foregroundStyle(VoltPaper.mutedFg)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(VoltPaper.mutedFg)
                    .disabled(isCreating)
                Spacer()
                Button {
                    onCreate(chain, label)
                } label: {
                    HStack(spacing: 6) {
                        if isCreating { ProgressView().controlSize(.small) }
                        Text(isCreating ? "Creating…" : "Create")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(VoltPaper.accentFg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(VoltPaper.accent))
                }
                .buttonStyle(.plain)
                .disabled(isCreating)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(VoltPaper.background)
    }

    private func chainOption(_ c: (id: String, name: String, icon: String, color: Color)) -> some View {
        let selected = chain == c.id
        return Button { chain = c.id } label: {
            HStack(spacing: 8) {
                Image(systemName: c.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(c.color)
                Text(c.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VoltPaper.foreground)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VoltPaper.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? VoltPaper.accent.opacity(0.1) : VoltPaper.foreground.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? VoltPaper.accent.opacity(0.4) : VoltPaper.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
    }
}

#endif
