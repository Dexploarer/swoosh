// Apps/SwooshiOS/WalletCreateAccountSheet.swift — Create-account modal
//
// Chain picker + label field. On submit, WalletSession.create generates a
// fresh keypair (CryptoKit ed25519 for Solana, secp256k1 for EVM), writes
// the secret to the Keychain with the biometric ACL, and stores the
// public-side WalletAccount in UserDefaults.

import SwiftUI
import SwooshWallet

struct WalletCreateAccountSheet: View {
    @Environment(WalletSession.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var chain: WalletChain = .solana
    @State private var label: String = ""
    @State private var working: Bool = false
    @State private var createdFeedback = 0
    @State private var errorFeedback = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Chain") {
                    Picker("Chain", selection: $chain) {
                        ForEach(WalletChain.allCases, id: \.self) { chain in
                            Label(chain.displayName, systemImage: "circle.fill")
                                .tag(chain)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Label") {
                    TextField("e.g. \(defaultLabel)", text: $label)
                }

                Section {
                    Text("A fresh keypair is generated locally. The private key is sealed in this iPhone's Keychain behind Face ID — Swoosh never sees it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = wallet.error {
                    Section {
                        ErrorRow(message: error) {
                            await create()
                        }
                    }
                }
            }
            .navigationTitle("New wallet")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: createdFeedback)
            .sensoryFeedback(.error, trigger: errorFeedback)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if working {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(working)
                }
            }
        }
    }

    /// Generate the keypair, then dismiss on success. On failure the sheet
    /// stays open so the in-sheet `ErrorRow` can offer a retry.
    private func create() async {
        working = true
        wallet.clearError()
        await wallet.create(chain: chain, label: finalLabel)
        working = false
        if wallet.error == nil {
            createdFeedback &+= 1   // haptic: account created
            dismiss()
        } else {
            errorFeedback &+= 1     // haptic: creation failed
        }
    }

    private var finalLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultLabel : trimmed
    }

    private var defaultLabel: String { "\(chain.displayName) wallet" }
}
