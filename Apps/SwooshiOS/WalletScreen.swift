// Apps/SwooshiOS/WalletScreen.swift — In-app multi-chain wallet
//
// Drawer destination. Lists every WalletAccount the user has created (one
// per chain), renders a real RPC-fetched balance per row (lamports for
// Solana, wei converted to native for EVM), and lets the user:
//   • create a new account on any of the four supported chains
//   • open an account detail with copy/share address and a QR-code receive
//
// Send flows ship next — the UI shows a clear "next" pill so users know
// signing is intentionally not exposed yet.

import SwiftUI
import SwooshWallet

struct WalletScreen: View {
    @Environment(WalletSession.self) private var wallet
    @State private var showingCreate: Bool = false
    @State private var errorFeedback = 0

    var body: some View {
        Group {
            if !wallet.hasLoadedAccounts, wallet.loadingAccounts {
                LoadingState("Loading wallets…")
            } else if wallet.accounts.isEmpty {
                emptyState
            } else {
                accountsList
            }
        }
        .navigationTitle("Wallet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
                .disabled(!wallet.hasLoadedAccounts && wallet.loadingAccounts)
            }
        }
        .sheet(isPresented: $showingCreate) {
            WalletCreateAccountSheet().environment(wallet)
        }
        .task { await wallet.reload(); await wallet.refreshAllBalances() }
        .refreshable {
            await wallet.refreshAllBalances()
            if wallet.error != nil { errorFeedback &+= 1 }
        }
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No wallets yet")
                .font(.title3.weight(.semibold))
            Text("Create an in-app wallet — keys live in this iPhone's Keychain, gated by Face ID.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Button {
                showingCreate = true
            } label: {
                Label("Create wallet", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accountsList: some View {
        List {
            Section {
                ForEach(wallet.accounts) { account in
                    NavigationLink(value: account) {
                        AccountRow(account: account)
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            let target = wallet.accounts[index]
                            await wallet.delete(target)
                        }
                        if wallet.error != nil { errorFeedback &+= 1 }
                    }
                }
            }
            if let error = wallet.error {
                Section {
                    ErrorRow(message: error) {
                        wallet.clearError()
                        await wallet.refreshAllBalances()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: WalletAccount.self) { account in
            WalletAccountDetail(account: account).environment(wallet)
        }
    }
}

private struct AccountRow: View {
    @Environment(WalletSession.self) private var wallet
    let account: WalletAccount

    var body: some View {
        HStack(spacing: 12) {
            ChainBadge(chain: account.chain)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label)
                    .font(.body.weight(.semibold))
                Text(account.truncatedAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            balanceLabel
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var balanceLabel: some View {
        if wallet.refreshing.contains(account.id) {
            ProgressView()
        } else if let balance = wallet.balances[account.id] {
            Text(balance.formatted)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

struct ChainBadge: View {
    let chain: WalletChain
    var size: CGFloat = 36

    var body: some View {
        ChainLogo(
            chainRawValue: chain.rawValue,
            symbol: symbol,
            tintHex: chain.tintHex,
            size: size,
            cornerRadius: size * 0.28
        )
    }

    private var symbol: String {
        switch chain {
        case .solana:   "SOL"
        case .ethereum: "ETH"
        case .base:     "BASE"
        case .bnb:      "BNB"
        }
    }
}

private extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
