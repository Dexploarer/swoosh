// SwooshTools/EVMToolTypes.swift — EVM Tool I/O Types
import Foundation

// ── evm.chain_info ────────────────────────────────────────────────
public struct EVMChainInfoInput: Codable, Sendable {
    public let chainID: EVMChainID
    public init(chainID: EVMChainID) { self.chainID = chainID }
}
public struct EVMChainInfoOutput: Codable, Sendable {
    public let chainID: EVMChainID
    public let latestBlockNumber: EVMQuantity
    public let rpcHealthy: Bool
    public init(chainID: EVMChainID, latestBlockNumber: EVMQuantity, rpcHealthy: Bool) {
        self.chainID = chainID; self.latestBlockNumber = latestBlockNumber; self.rpcHealthy = rpcHealthy
    }
}

// ── evm.address_validate ──────────────────────────────────────────
public struct EVMAddressValidateInput: Codable, Sendable {
    public let address: String
    public init(address: String) { self.address = address }
}
public struct EVMAddressValidateOutput: Codable, Sendable {
    public let valid: Bool
    public let normalized: EVMAddress?
    public let isChecksummed: Bool
    public init(valid: Bool, normalized: EVMAddress? = nil, isChecksummed: Bool = false) {
        self.valid = valid; self.normalized = normalized; self.isChecksummed = isChecksummed
    }
}

// ── evm.account_balance_native ────────────────────────────────────
public struct EVMAccountBalanceNativeInput: Codable, Sendable {
    public let chainID: EVMChainID; public let address: EVMAddress; public let block: EVMBlockParameter
    public init(chainID: EVMChainID, address: EVMAddress, block: EVMBlockParameter = .tag(.latest)) {
        self.chainID = chainID; self.address = address; self.block = block
    }
}
public struct EVMAccountBalanceNativeOutput: Codable, Sendable {
    public let address: EVMAddress; public let balanceWei: EVMQuantity; public let block: EVMBlockParameter
    public init(address: EVMAddress, balanceWei: EVMQuantity, block: EVMBlockParameter) {
        self.address = address; self.balanceWei = balanceWei; self.block = block
    }
}

// ── evm.account_nonce ─────────────────────────────────────────────
public struct EVMAccountNonceInput: Codable, Sendable {
    public let chainID: EVMChainID; public let address: EVMAddress; public let block: EVMBlockParameter
    public init(chainID: EVMChainID, address: EVMAddress, block: EVMBlockParameter = .tag(.latest)) {
        self.chainID = chainID; self.address = address; self.block = block
    }
}
public struct EVMAccountNonceOutput: Codable, Sendable {
    public let address: EVMAddress; public let nonce: EVMQuantity
    public init(address: EVMAddress, nonce: EVMQuantity) { self.address = address; self.nonce = nonce }
}

// ── evm.contract_get_code ─────────────────────────────────────────
public struct EVMContractGetCodeInput: Codable, Sendable {
    public let chainID: EVMChainID; public let address: EVMAddress; public let block: EVMBlockParameter
    public init(chainID: EVMChainID, address: EVMAddress, block: EVMBlockParameter = .tag(.latest)) {
        self.chainID = chainID; self.address = address; self.block = block
    }
}
public struct EVMContractGetCodeOutput: Codable, Sendable {
    public let address: EVMAddress; public let code: EVMHexData; public let isContract: Bool
    public init(address: EVMAddress, code: EVMHexData, isContract: Bool) {
        self.address = address; self.code = code; self.isContract = isContract
    }
}

// ── evm.contract_call ─────────────────────────────────────────────
public struct EVMContractCallInput: Codable, Sendable {
    public let chainID: EVMChainID; public let from: EVMAddress?; public let to: EVMAddress
    public let data: EVMHexData; public let valueWei: EVMQuantity?; public let block: EVMBlockParameter
    public init(chainID: EVMChainID, from: EVMAddress? = nil, to: EVMAddress, data: EVMHexData, valueWei: EVMQuantity? = nil, block: EVMBlockParameter = .tag(.latest)) {
        self.chainID = chainID; self.from = from; self.to = to; self.data = data; self.valueWei = valueWei; self.block = block
    }
}
public struct EVMContractCallOutput: Codable, Sendable {
    public let returnData: EVMHexData
    public init(returnData: EVMHexData) { self.returnData = returnData }
}

// ── evm.contract_get_logs ─────────────────────────────────────────
public struct EVMGetLogsInput: Codable, Sendable {
    public let chainID: EVMChainID; public let fromBlock: EVMBlockParameter?; public let toBlock: EVMBlockParameter?
    public let address: EVMAddress?; public let topics: [EVMHexData?]
    public init(chainID: EVMChainID, fromBlock: EVMBlockParameter? = nil, toBlock: EVMBlockParameter? = nil, address: EVMAddress? = nil, topics: [EVMHexData?] = []) {
        self.chainID = chainID; self.fromBlock = fromBlock; self.toBlock = toBlock; self.address = address; self.topics = topics
    }
}
public struct EVMGetLogsOutput: Codable, Sendable {
    public let logs: [EVMLog]
    public init(logs: [EVMLog]) { self.logs = logs }
}

// ── evm.erc20_balance ─────────────────────────────────────────────
public struct EVMERC20BalanceInput: Codable, Sendable {
    public let chainID: EVMChainID; public let tokenContract: EVMAddress; public let owner: EVMAddress
    public init(chainID: EVMChainID, tokenContract: EVMAddress, owner: EVMAddress) {
        self.chainID = chainID; self.tokenContract = tokenContract; self.owner = owner
    }
}
public struct EVMERC20BalanceOutput: Codable, Sendable {
    public let balance: EVMQuantity; public let tokenSymbol: String?; public let tokenDecimals: Int?
    public init(balance: EVMQuantity, tokenSymbol: String? = nil, tokenDecimals: Int? = nil) {
        self.balance = balance; self.tokenSymbol = tokenSymbol; self.tokenDecimals = tokenDecimals
    }
}

// ── evm.erc20_allowance ───────────────────────────────────────────
public struct EVMERC20AllowanceInput: Codable, Sendable {
    public let chainID: EVMChainID; public let tokenContract: EVMAddress; public let owner: EVMAddress; public let spender: EVMAddress
    public init(chainID: EVMChainID, tokenContract: EVMAddress, owner: EVMAddress, spender: EVMAddress) {
        self.chainID = chainID; self.tokenContract = tokenContract; self.owner = owner; self.spender = spender
    }
}
public struct EVMERC20AllowanceOutput: Codable, Sendable {
    public let allowance: EVMQuantity; public let isUnlimited: Bool
    public init(allowance: EVMQuantity, isUnlimited: Bool) { self.allowance = allowance; self.isUnlimited = isUnlimited }
}

// ── evm.abi_encode_call / abi_decode_result ────────────────────────
public struct EVMABIEncodeCallInput: Codable, Sendable {
    public let functionSignature: String; public let arguments: [String]
    public init(functionSignature: String, arguments: [String]) { self.functionSignature = functionSignature; self.arguments = arguments }
}
public struct EVMABIEncodeCallOutput: Codable, Sendable {
    public let encodedData: EVMHexData
    public init(encodedData: EVMHexData) { self.encodedData = encodedData }
}
public struct EVMABIDecodeResultInput: Codable, Sendable {
    public let types: [String]; public let data: EVMHexData
    public init(types: [String], data: EVMHexData) { self.types = types; self.data = data }
}
public struct EVMABIDecodeResultOutput: Codable, Sendable {
    public let values: [String]
    public init(values: [String]) { self.values = values }
}

// ── evm.tx_estimate_gas ───────────────────────────────────────────
public struct EVMTxEstimateGasInput: Codable, Sendable {
    public let chainID: EVMChainID; public let from: EVMAddress?; public let to: EVMAddress?
    public let data: EVMHexData?; public let valueWei: EVMQuantity?
    public init(chainID: EVMChainID, from: EVMAddress? = nil, to: EVMAddress? = nil, data: EVMHexData? = nil, valueWei: EVMQuantity? = nil) {
        self.chainID = chainID; self.from = from; self.to = to; self.data = data; self.valueWei = valueWei
    }
}
public struct EVMTxEstimateGasOutput: Codable, Sendable {
    public let gas: EVMQuantity
    public init(gas: EVMQuantity) { self.gas = gas }
}

// ── evm.tx_preflight ──────────────────────────────────────────────
public struct EVMTxPreflightInput: Codable, Sendable {
    public let chainID: EVMChainID; public let from: EVMAddress; public let to: EVMAddress
    public let data: EVMHexData?; public let valueWei: EVMQuantity?
    public init(chainID: EVMChainID, from: EVMAddress, to: EVMAddress, data: EVMHexData? = nil, valueWei: EVMQuantity? = nil) {
        self.chainID = chainID; self.from = from; self.to = to; self.data = data; self.valueWei = valueWei
    }
}
public struct EVMTxPreflightOutput: Codable, Sendable {
    public let estimatedGas: EVMQuantity; public let callResult: EVMHexData?; public let warnings: [String]
    public init(estimatedGas: EVMQuantity, callResult: EVMHexData? = nil, warnings: [String] = []) {
        self.estimatedGas = estimatedGas; self.callResult = callResult; self.warnings = warnings
    }
}

// ── evm.tx_build_native_transfer ──────────────────────────────────
public struct EVMBuildNativeTransferInput: Codable, Sendable {
    public let chainID: EVMChainID; public let from: EVMAddress; public let to: EVMAddress
    public let valueWei: EVMQuantity; public let maxFeePerGas: EVMQuantity?
    public let maxPriorityFeePerGas: EVMQuantity?; public let gasLimit: EVMQuantity?; public let nonce: EVMQuantity?
    public init(chainID: EVMChainID, from: EVMAddress, to: EVMAddress, valueWei: EVMQuantity, maxFeePerGas: EVMQuantity? = nil, maxPriorityFeePerGas: EVMQuantity? = nil, gasLimit: EVMQuantity? = nil, nonce: EVMQuantity? = nil) {
        self.chainID = chainID; self.from = from; self.to = to; self.valueWei = valueWei
        self.maxFeePerGas = maxFeePerGas; self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.gasLimit = gasLimit; self.nonce = nonce
    }
}
public struct EVMBuildNativeTransferOutput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction; public let humanPreview: String
    public init(unsignedTransaction: EVMUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// ── evm.tx_build_contract_call ────────────────────────────────────
public struct EVMBuildContractCallInput: Codable, Sendable {
    public let chainID: EVMChainID; public let from: EVMAddress; public let to: EVMAddress
    public let data: EVMHexData; public let valueWei: EVMQuantity?; public let gasLimit: EVMQuantity?; public let nonce: EVMQuantity?
    public init(chainID: EVMChainID, from: EVMAddress, to: EVMAddress, data: EVMHexData, valueWei: EVMQuantity? = nil, gasLimit: EVMQuantity? = nil, nonce: EVMQuantity? = nil) {
        self.chainID = chainID; self.from = from; self.to = to; self.data = data
        self.valueWei = valueWei; self.gasLimit = gasLimit; self.nonce = nonce
    }
}
public struct EVMBuildContractCallOutput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction; public let humanPreview: String
    public init(unsignedTransaction: EVMUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// ── evm.erc20_build_transfer ──────────────────────────────────────
public struct EVMERC20BuildTransferInput: Codable, Sendable {
    public let chainID: EVMChainID; public let tokenContract: EVMAddress; public let from: EVMAddress
    public let to: EVMAddress; public let amountRaw: EVMQuantity; public let tokenSymbol: String?; public let tokenDecimals: Int?
    public init(chainID: EVMChainID, tokenContract: EVMAddress, from: EVMAddress, to: EVMAddress, amountRaw: EVMQuantity, tokenSymbol: String? = nil, tokenDecimals: Int? = nil) {
        self.chainID = chainID; self.tokenContract = tokenContract; self.from = from; self.to = to
        self.amountRaw = amountRaw; self.tokenSymbol = tokenSymbol; self.tokenDecimals = tokenDecimals
    }
}
public struct EVMERC20BuildTransferOutput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction; public let humanPreview: String
    public init(unsignedTransaction: EVMUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// ── evm.erc20_build_approve ───────────────────────────────────────
public struct EVMERC20BuildApproveInput: Codable, Sendable {
    public let chainID: EVMChainID; public let tokenContract: EVMAddress; public let owner: EVMAddress
    public let spender: EVMAddress; public let amountRaw: EVMQuantity
    public let tokenSymbol: String?; public let tokenDecimals: Int?
    public init(chainID: EVMChainID, tokenContract: EVMAddress, owner: EVMAddress, spender: EVMAddress, amountRaw: EVMQuantity, tokenSymbol: String? = nil, tokenDecimals: Int? = nil) {
        self.chainID = chainID; self.tokenContract = tokenContract; self.owner = owner; self.spender = spender
        self.amountRaw = amountRaw; self.tokenSymbol = tokenSymbol; self.tokenDecimals = tokenDecimals
    }
}
public struct EVMERC20BuildApproveOutput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction; public let isUnlimitedApproval: Bool
    public let warnings: [String]; public let humanPreview: String
    public init(unsignedTransaction: EVMUnsignedTransaction, isUnlimitedApproval: Bool, warnings: [String], humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.isUnlimitedApproval = isUnlimitedApproval
        self.warnings = warnings; self.humanPreview = humanPreview
    }
}

// ── evm.wallet_connect / wallet_accounts ──────────────────────────
public struct EVMWalletConnectInput: Codable, Sendable {
    public let chainID: EVMChainID?
    public init(chainID: EVMChainID? = nil) { self.chainID = chainID }
}
public struct EVMWalletConnectOutput: Codable, Sendable {
    public let walletSessionID: String; public let connectedAccounts: [EVMAddress]
    public init(walletSessionID: String, connectedAccounts: [EVMAddress]) {
        self.walletSessionID = walletSessionID; self.connectedAccounts = connectedAccounts
    }
}
public struct EVMWalletAccountsInput: Codable, Sendable {
    public let walletSessionID: String?
    public init(walletSessionID: String? = nil) { self.walletSessionID = walletSessionID }
}
public struct EVMWalletAccountsOutput: Codable, Sendable {
    public let accounts: [EVMAddress]
    public init(accounts: [EVMAddress]) { self.accounts = accounts }
}

// ── evm.tx_request_signature ──────────────────────────────────────
public struct EVMTxRequestSignatureInput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction; public let walletSessionID: String; public let userConfirmationText: String
    public init(unsignedTransaction: EVMUnsignedTransaction, walletSessionID: String, userConfirmationText: String) {
        self.unsignedTransaction = unsignedTransaction; self.walletSessionID = walletSessionID; self.userConfirmationText = userConfirmationText
    }
}
public struct EVMTxRequestSignatureOutput: Codable, Sendable {
    public let signedTransaction: EVMHexData; public let walletAddress: EVMAddress
    public init(signedTransaction: EVMHexData, walletAddress: EVMAddress) {
        self.signedTransaction = signedTransaction; self.walletAddress = walletAddress
    }
}

// ── evm.tx_broadcast_signed ───────────────────────────────────────
public struct EVMTxBroadcastSignedInput: Codable, Sendable {
    public let chainID: EVMChainID; public let signedTransaction: EVMHexData; public let userConfirmationText: String
    public init(chainID: EVMChainID, signedTransaction: EVMHexData, userConfirmationText: String) {
        self.chainID = chainID; self.signedTransaction = signedTransaction; self.userConfirmationText = userConfirmationText
    }
}
public struct EVMTxBroadcastSignedOutput: Codable, Sendable {
    public let transactionHash: EVMHexData
    public init(transactionHash: EVMHexData) { self.transactionHash = transactionHash }
}

// ── evm.tx_get_receipt / tx_get_by_hash ───────────────────────────
public struct EVMTxGetReceiptInput: Codable, Sendable {
    public let chainID: EVMChainID; public let transactionHash: EVMHexData
    public init(chainID: EVMChainID, transactionHash: EVMHexData) { self.chainID = chainID; self.transactionHash = transactionHash }
}
public struct EVMTxGetReceiptOutput: Codable, Sendable {
    public let receipt: EVMTransactionReceipt?
    public init(receipt: EVMTransactionReceipt?) { self.receipt = receipt }
}
public struct EVMTxGetByHashInput: Codable, Sendable {
    public let chainID: EVMChainID; public let transactionHash: EVMHexData
    public init(chainID: EVMChainID, transactionHash: EVMHexData) { self.chainID = chainID; self.transactionHash = transactionHash }
}
public struct EVMTxGetByHashOutput: Codable, Sendable {
    public let found: Bool; public let rawJSON: String?
    public init(found: Bool, rawJSON: String? = nil) { self.found = found; self.rawJSON = rawJSON }
}
