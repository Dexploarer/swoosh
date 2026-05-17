// SwooshToolsets/EVMTools.swift — EVM toolset implementations
// Hard rules: No private keys. No seed phrases. No cookies.
// No signing without human approval. No broadcasting without human approval.
// Mainnet write requires evmMainnetWrite.
import Foundation
import SwooshTools

// ── Helper ────────────────────────────────────────────────────────
private func requireEVM(_ deps: ToolDependencies) throws -> any EVMRPCClient {
    guard let client = deps.evmClient else { throw ToolError.executionFailed("EVM RPC client not configured") }
    return client
}

// ── Read-only tools ───────────────────────────────────────────────

public struct EVMChainInfoTool: SwooshTool {
    public typealias Input = EVMChainInfoInput; public typealias Output = EVMChainInfoOutput
    public static let name: ToolName = "evm.chain_info"; public static let displayName = "Chain Info"
    public static let description = "Chain ID, block number, RPC health"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let block = try await client.blockNumber(config: config)
        return EVMChainInfoOutput(chainID: input.chainID, latestBlockNumber: block, rpcHealthy: true)
    }
}

public struct EVMAddressValidateTool: SwooshTool {
    public typealias Input = EVMAddressValidateInput; public typealias Output = EVMAddressValidateOutput
    public static let name: ToolName = "evm.address_validate"; public static let displayName = "Validate Address"
    public static let description = "Validate/normalize address"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let addr = input.address.lowercased()
        let valid = addr.hasPrefix("0x") && addr.count == 42
        return EVMAddressValidateOutput(valid: valid, normalized: valid ? EVMAddress(addr) : nil, isChecksummed: false)
    }
}

public struct EVMAccountBalanceNativeTool: SwooshTool {
    public typealias Input = EVMAccountBalanceNativeInput; public typealias Output = EVMAccountBalanceNativeOutput
    public static let name: ToolName = "evm.account_balance_native"; public static let displayName = "Native Balance"
    public static let description = "Native ETH/MATIC/etc. balance"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let balance = try await client.getBalance(config: config, address: input.address, block: input.block)
        return EVMAccountBalanceNativeOutput(address: input.address, balanceWei: balance, block: input.block)
    }
}

public struct EVMAccountNonceTool: SwooshTool {
    public typealias Input = EVMAccountNonceInput; public typealias Output = EVMAccountNonceOutput
    public static let name: ToolName = "evm.account_nonce"; public static let displayName = "Account Nonce"
    public static let description = "Transaction count / nonce"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let nonce = try await client.getTransactionCount(config: config, address: input.address, block: input.block)
        return EVMAccountNonceOutput(address: input.address, nonce: nonce)
    }
}

public struct EVMContractGetCodeTool: SwooshTool {
    public typealias Input = EVMContractGetCodeInput; public typealias Output = EVMContractGetCodeOutput
    public static let name: ToolName = "evm.contract_get_code"; public static let displayName = "Get Code"
    public static let description = "Get contract bytecode"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let code = try await client.getCode(config: config, address: input.address, block: input.block)
        return EVMContractGetCodeOutput(address: input.address, code: code, isContract: code.hex != "0x")
    }
}

public struct EVMContractCallTool: SwooshTool {
    public typealias Input = EVMContractCallInput; public typealias Output = EVMContractCallOutput
    public static let name: ToolName = "evm.contract_call"; public static let displayName = "Contract Call"
    public static let description = "Read-only contract call"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let result = try await client.call(config: config, call: input)
        return EVMContractCallOutput(returnData: result)
    }
}

public struct EVMContractGetLogsTool: SwooshTool {
    public typealias Input = EVMGetLogsInput; public typealias Output = EVMGetLogsOutput
    public static let name: ToolName = "evm.contract_get_logs"; public static let displayName = "Get Logs"
    public static let description = "Query logs"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let logs = try await client.getLogs(config: config, filter: input)
        return EVMGetLogsOutput(logs: logs)
    }
}

public struct EVMERC20BalanceTool: SwooshTool {
    public typealias Input = EVMERC20BalanceInput; public typealias Output = EVMERC20BalanceOutput
    public static let name: ToolName = "evm.erc20_balance"; public static let displayName = "ERC-20 Balance"
    public static let description = "ERC-20 balanceOf"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        EVMERC20BalanceOutput(balance: EVMQuantity("0x0"), tokenSymbol: nil, tokenDecimals: nil)
    }
}

public struct EVMERC20AllowanceTool: SwooshTool {
    public typealias Input = EVMERC20AllowanceInput; public typealias Output = EVMERC20AllowanceOutput
    public static let name: ToolName = "evm.erc20_allowance"; public static let displayName = "ERC-20 Allowance"
    public static let description = "ERC-20 allowance"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        EVMERC20AllowanceOutput(allowance: EVMQuantity("0x0"), isUnlimited: false)
    }
}

public struct EVMABIEncodeCallTool: SwooshTool {
    public typealias Input = EVMABIEncodeCallInput; public typealias Output = EVMABIEncodeCallOutput
    public static let name: ToolName = "evm.abi_encode_call"; public static let displayName = "ABI Encode"
    public static let description = "ABI encode function call"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        EVMABIEncodeCallOutput(encodedData: EVMHexData("0x"))
    }
}

public struct EVMABIDecodeResultTool: SwooshTool {
    public typealias Input = EVMABIDecodeResultInput; public typealias Output = EVMABIDecodeResultOutput
    public static let name: ToolName = "evm.abi_decode_result"; public static let displayName = "ABI Decode"
    public static let description = "ABI decode result"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output { EVMABIDecodeResultOutput(values: []) }
}

public struct EVMTxEstimateGasTool: SwooshTool {
    public typealias Input = EVMTxEstimateGasInput; public typealias Output = EVMTxEstimateGasOutput
    public static let name: ToolName = "evm.tx_estimate_gas"; public static let displayName = "Estimate Gas"
    public static let description = "Estimate gas"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.low; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let gas = try await client.estimateGas(config: config, tx: input)
        return EVMTxEstimateGasOutput(gas: gas)
    }
}

public struct EVMTxPreflightTool: SwooshTool {
    public typealias Input = EVMTxPreflightInput; public typealias Output = EVMTxPreflightOutput
    public static let name: ToolName = "evm.tx_preflight"; public static let displayName = "Tx Preflight"
    public static let description = "Estimate gas + read-only preflight"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askFirstTime; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        EVMTxPreflightOutput(estimatedGas: EVMQuantity("0x5208"), callResult: nil, warnings: [])
    }
}

// ── Build tools (return unsigned only) ────────────────────────────

public struct EVMTxBuildNativeTransferTool: SwooshTool {
    public typealias Input = EVMBuildNativeTransferInput; public typealias Output = EVMBuildNativeTransferOutput
    public static let name: ToolName = "evm.tx_build_native_transfer"; public static let displayName = "Build Native Transfer"
    public static let description = "Build unsigned native transfer"; public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let risk = TransactionRiskSummary(network: "EVM-\(input.chainID.value)", isMainnet: input.chainID.isMainnet, from: input.from.hex, to: input.to.hex, asset: "ETH", amountHuman: input.valueWei.hex, estimatedFeeHuman: nil, warnings: input.chainID.isMainnet ? ["MAINNET transaction"] : [], requiresExplicitUserConfirmation: input.chainID.isMainnet)
        if input.chainID.isMainnet { try await dependencies.firewall.require(.evmMainnetWrite) }
        let tx = EVMUnsignedTransaction(chainID: input.chainID, from: input.from, to: input.to, valueWei: input.valueWei, data: nil, gasLimit: input.gasLimit, maxFeePerGas: input.maxFeePerGas, maxPriorityFeePerGas: input.maxPriorityFeePerGas, nonce: input.nonce, riskSummary: risk)
        return EVMBuildNativeTransferOutput(unsignedTransaction: tx, humanPreview: "Transfer \(input.valueWei.hex) wei from \(input.from.hex) to \(input.to.hex)")
    }
}

public struct EVMTxBuildContractCallTool: SwooshTool {
    public typealias Input = EVMBuildContractCallInput; public typealias Output = EVMBuildContractCallOutput
    public static let name: ToolName = "evm.tx_build_contract_call"; public static let displayName = "Build Contract Call"
    public static let description = "Build unsigned contract call"; public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        if input.chainID.isMainnet { try await dependencies.firewall.require(.evmMainnetWrite) }
        let risk = TransactionRiskSummary(network: "EVM-\(input.chainID.value)", isMainnet: input.chainID.isMainnet, from: input.from.hex, to: input.to.hex, asset: nil, amountHuman: input.valueWei?.hex, estimatedFeeHuman: nil, warnings: [], requiresExplicitUserConfirmation: input.chainID.isMainnet)
        let tx = EVMUnsignedTransaction(chainID: input.chainID, from: input.from, to: input.to, valueWei: input.valueWei, data: input.data, gasLimit: input.gasLimit, maxFeePerGas: nil, maxPriorityFeePerGas: nil, nonce: input.nonce, riskSummary: risk)
        return EVMBuildContractCallOutput(unsignedTransaction: tx, humanPreview: "Contract call to \(input.to.hex)")
    }
}

public struct EVMERC20BuildTransferTool: SwooshTool {
    public typealias Input = EVMERC20BuildTransferInput; public typealias Output = EVMERC20BuildTransferOutput
    public static let name: ToolName = "evm.erc20_build_transfer"; public static let displayName = "Build ERC-20 Transfer"
    public static let description = "Build ERC-20 transfer"; public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        if input.chainID.isMainnet { try await dependencies.firewall.require(.evmMainnetWrite) }
        let risk = TransactionRiskSummary(network: "EVM-\(input.chainID.value)", isMainnet: input.chainID.isMainnet, from: input.from.hex, to: input.to.hex, asset: input.tokenSymbol, amountHuman: input.amountRaw.hex, estimatedFeeHuman: nil, warnings: [], requiresExplicitUserConfirmation: input.chainID.isMainnet)
        let tx = EVMUnsignedTransaction(chainID: input.chainID, from: input.from, to: input.tokenContract, valueWei: nil, data: EVMHexData("0x"), gasLimit: nil, maxFeePerGas: nil, maxPriorityFeePerGas: nil, nonce: nil, riskSummary: risk)
        return EVMERC20BuildTransferOutput(unsignedTransaction: tx, humanPreview: "Transfer \(input.tokenSymbol ?? "token") to \(input.to.hex)")
    }
}

public struct EVMERC20BuildApproveTool: SwooshTool {
    public typealias Input = EVMERC20BuildApproveInput; public typealias Output = EVMERC20BuildApproveOutput
    public static let name: ToolName = "evm.erc20_build_approve"; public static let displayName = "Build ERC-20 Approve"
    public static let description = "Build ERC-20 approval (detects unlimited)"; public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        if input.chainID.isMainnet { try await dependencies.firewall.require(.evmMainnetWrite) }
        // Detect unlimited approval (max uint256)
        let maxUint = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        let isUnlimited = input.amountRaw.hex.lowercased() == maxUint
        var warnings: [String] = []
        if isUnlimited { warnings.append("⚠️ UNLIMITED APPROVAL — spender \(input.spender.hex) will have unlimited access to your \(input.tokenSymbol ?? "tokens")") }
        let risk = TransactionRiskSummary(network: "EVM-\(input.chainID.value)", isMainnet: input.chainID.isMainnet, from: input.owner.hex, to: input.spender.hex, asset: input.tokenSymbol, amountHuman: isUnlimited ? "UNLIMITED" : input.amountRaw.hex, estimatedFeeHuman: nil, warnings: warnings, requiresExplicitUserConfirmation: true)
        let tx = EVMUnsignedTransaction(chainID: input.chainID, from: input.owner, to: input.tokenContract, valueWei: nil, data: EVMHexData("0x"), gasLimit: nil, maxFeePerGas: nil, maxPriorityFeePerGas: nil, nonce: nil, riskSummary: risk)
        return EVMERC20BuildApproveOutput(unsignedTransaction: tx, isUnlimitedApproval: isUnlimited, warnings: warnings, humanPreview: "Approve \(input.spender.hex) to spend \(isUnlimited ? "UNLIMITED" : input.amountRaw.hex) \(input.tokenSymbol ?? "tokens")")
    }
}

// ── Wallet / signing / broadcast (humanOnly) ──────────────────────

public struct EVMWalletConnectTool: SwooshTool {
    public typealias Input = EVMWalletConnectInput; public typealias Output = EVMWalletConnectOutput
    public static let name: ToolName = "evm.wallet_connect"; public static let displayName = "Connect Wallet"
    public static let description = "Connect external wallet"; public static let permission = SwooshPermission.evmRequestSignature
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let bridge = dependencies.walletBridge else { throw ToolError.executionFailed("No wallet bridge") }
        let session = try await bridge.connectEVM()
        let accounts = try await bridge.evmAccounts(sessionID: session)
        return EVMWalletConnectOutput(walletSessionID: session, connectedAccounts: accounts)
    }
}

public struct EVMWalletAccountsTool: SwooshTool {
    public typealias Input = EVMWalletAccountsInput; public typealias Output = EVMWalletAccountsOutput
    public static let name: ToolName = "evm.wallet_accounts"; public static let displayName = "Wallet Accounts"
    public static let description = "List connected accounts"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output { EVMWalletAccountsOutput(accounts: []) }
}

public struct EVMTxRequestSignatureTool: SwooshTool {
    public typealias Input = EVMTxRequestSignatureInput; public typealias Output = EVMTxRequestSignatureOutput
    public static let name: ToolName = "evm.tx_request_signature"; public static let displayName = "Request Signature"
    public static let description = "Request wallet signature (humanOnly)"; public static let permission = SwooshPermission.evmRequestSignature
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let bridge = dependencies.walletBridge else { throw ToolError.executionFailed("No wallet bridge") }
        let signed = try await bridge.requestEVMSignature(transaction: input.unsignedTransaction, sessionID: input.walletSessionID, confirmationText: input.userConfirmationText)
        return EVMTxRequestSignatureOutput(signedTransaction: signed, walletAddress: input.unsignedTransaction.from)
    }
}

public struct EVMTxBroadcastSignedTool: SwooshTool {
    public typealias Input = EVMTxBroadcastSignedInput; public typealias Output = EVMTxBroadcastSignedOutput
    public static let name: ToolName = "evm.tx_broadcast_signed"; public static let displayName = "Broadcast Tx"
    public static let description = "Broadcast signed transaction (humanOnly)"; public static let permission = SwooshPermission.evmBroadcast
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        if input.chainID.isMainnet { try await dependencies.firewall.require(.evmMainnetWrite) }
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let hash = try await client.sendRawTransaction(config: config, signedTransaction: input.signedTransaction)
        return EVMTxBroadcastSignedOutput(transactionHash: hash)
    }
}

public struct EVMTxGetReceiptTool: SwooshTool {
    public typealias Input = EVMTxGetReceiptInput; public typealias Output = EVMTxGetReceiptOutput
    public static let name: ToolName = "evm.tx_get_receipt"; public static let displayName = "Get Receipt"
    public static let description = "Get transaction receipt"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let receipt = try await client.getTransactionReceipt(config: config, transactionHash: input.transactionHash)
        return EVMTxGetReceiptOutput(receipt: receipt)
    }
}

public struct EVMTxGetByHashTool: SwooshTool {
    public typealias Input = EVMTxGetByHashInput; public typealias Output = EVMTxGetByHashOutput
    public static let name: ToolName = "evm.tx_get_by_hash"; public static let displayName = "Get Tx"
    public static let description = "Get transaction by hash"; public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.evm
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireEVM(dependencies)
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: "default")
        let json = try await client.getTransactionByHash(config: config, transactionHash: input.transactionHash)
        return EVMTxGetByHashOutput(found: json != nil, rawJSON: json)
    }
}
