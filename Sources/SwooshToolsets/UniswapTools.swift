// SwooshToolsets/UniswapTools.swift
// Uniswap V2/V3 DEX tools for the EVM toolset.
// UniswapKit.Swift is iOS-only, so we implement the same patterns using our
// BigInt-backed EVMQuantity types and direct Uniswap V3 QuoterV2 ABI calls.
//
// Security model: same as EVMTools — build unsigned transactions only.
// Agent never holds a signing key.

import Foundation
import SwooshTools
import BigInt

// MARK: - Uniswap fee tier

public enum UniswapFeeTier: Int, Codable, Sendable, CaseIterable {
    case fee100  = 100     // 0.01% — stable pairs
    case fee500  = 500     // 0.05% — stable
    case fee3000 = 3000    // 0.30% — most pairs
    case fee10000 = 10000  // 1.00% — exotic pairs

    public var bps: Int { rawValue }
    public var label: String {
        switch self {
        case .fee100:   return "0.01%"
        case .fee500:   return "0.05%"
        case .fee3000:  return "0.30%"
        case .fee10000: return "1.00%"
        }
    }
}

// MARK: - Quote (read-only)

public struct UniswapQuoteInput: Codable, Sendable {
    public let tokenIn: EVMAddress
    public let tokenOut: EVMAddress
    public let amountIn: EVMQuantity
    public let feeTier: UniswapFeeTier
    public let chainID: EVMChainID
    /// Keychain ref for the RPC endpoint URL (resolved at call time)
    public let rpcURLSecretRef: String
    public init(tokenIn: EVMAddress, tokenOut: EVMAddress, amountIn: EVMQuantity,
                feeTier: UniswapFeeTier = .fee3000, chainID: EVMChainID = .mainnet,
                rpcURLSecretRef: String) {
        self.tokenIn = tokenIn; self.tokenOut = tokenOut; self.amountIn = amountIn
        self.feeTier = feeTier; self.chainID = chainID; self.rpcURLSecretRef = rpcURLSecretRef
    }
}

public struct UniswapQuoteOutput: Codable, Sendable {
    public let amountOut: EVMQuantity
    public let amountOutMin: EVMQuantity        // with 0.5% slippage
    public let priceImpactBps: Int             // estimated, basis points
    public let feeTier: UniswapFeeTier
    public let sqrtPriceX96After: String       // for V3 pool state inspection
    public let gasEstimate: EVMQuantity
}

public struct UniswapQuoteTool: SwooshTool {
    public typealias Input = UniswapQuoteInput
    public typealias Output = UniswapQuoteOutput
    public static let name: ToolName = "uniswap.quote"
    public static let displayName = "Uniswap V3 Quote"
    public static let description = "Get a Uniswap V3 swap quote via QuoterV2 (read-only, no signing)"
    public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.uniswap

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let evmClient = dependencies.evmClient else {
            throw ToolError.executionFailed("No EVM RPC client configured for chain \(input.chainID.value)")
        }
        let quoterV2 = EVMAddress(quoterV2Address(chainID: input.chainID))
        let calldata = encodeQuoteExactInputSingle(
            tokenIn: input.tokenIn, tokenOut: input.tokenOut,
            fee: input.feeTier.rawValue, amountIn: input.amountIn.value
        )
        let callInput = EVMContractCallInput(
            chainID: input.chainID, from: nil, to: quoterV2,
            data: EVMHexData(calldata)
        )
        let config = EVMRPCConfig(chainID: input.chainID, rpcURLSecretRef: input.rpcURLSecretRef)
        let result = try await evmClient.call(config: config, call: callInput)
        let (amountOut, sqrtPriceX96After, _, gasEstimate) = decodeQuoteResult(result.hex)
        let slippageFactor = BigInt(995)
        let amountOutMin = (amountOut * slippageFactor) / BigInt(1000)
        return UniswapQuoteOutput(
            amountOut: EVMQuantity(amountOut),
            amountOutMin: EVMQuantity(amountOutMin),
            priceImpactBps: 0,
            feeTier: input.feeTier,
            sqrtPriceX96After: "0x" + String(sqrtPriceX96After, radix: 16),
            gasEstimate: EVMQuantity(gasEstimate)
        )
    }
}

// MARK: - Build swap transaction (unsigned)

public struct UniswapSwapInput: Codable, Sendable {
    public let tokenIn: EVMAddress
    public let tokenOut: EVMAddress
    public let amountIn: EVMQuantity
    public let amountOutMin: EVMQuantity
    public let feeTier: UniswapFeeTier
    public let recipient: EVMAddress
    public let deadlineSeconds: Int       // seconds from now
    public let chainID: EVMChainID
    public init(tokenIn: EVMAddress, tokenOut: EVMAddress, amountIn: EVMQuantity,
                amountOutMin: EVMQuantity, feeTier: UniswapFeeTier = .fee3000,
                recipient: EVMAddress, deadlineSeconds: Int = 1200, chainID: EVMChainID = .mainnet) {
        self.tokenIn = tokenIn; self.tokenOut = tokenOut; self.amountIn = amountIn
        self.amountOutMin = amountOutMin; self.feeTier = feeTier; self.recipient = recipient
        self.deadlineSeconds = deadlineSeconds; self.chainID = chainID
    }
}

public struct UniswapSwapOutput: Codable, Sendable {
    public let unsignedTransaction: EVMUnsignedTransaction
    public let humanPreview: String
    public let routerAddress: EVMAddress
}

public struct UniswapSwapTool: SwooshTool {
    public typealias Input = UniswapSwapInput
    public typealias Output = UniswapSwapOutput
    public static let name: ToolName = "uniswap.build_swap"
    public static let displayName = "Uniswap Build Swap"
    public static let description = "Build an unsigned Uniswap V3 exactInputSingle swap transaction"
    public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.uniswap

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let _ = dependencies.evmClient else {
            throw ToolError.executionFailed("No EVM RPC client configured")
        }

        let router = EVMAddress(swapRouter02Address(chainID: input.chainID))
        let deadline = UInt64(Date().timeIntervalSince1970) + UInt64(input.deadlineSeconds)

        let calldata = encodeExactInputSingle(
            tokenIn: input.tokenIn, tokenOut: input.tokenOut,
            fee: input.feeTier.rawValue, recipient: input.recipient,
            amountIn: input.amountIn.value, amountOutMinimum: input.amountOutMin.value,
            sqrtPriceLimitX96: BigInt(0), deadline: BigInt(deadline)
        )

        let risk = TransactionRiskSummary(
            network: "EVM-\(input.chainID.value)", isMainnet: input.chainID.isMainnet,
            from: input.recipient.hex, to: router.hex,
            asset: "\(input.tokenIn.hex) → \(input.tokenOut.hex)",
            amountHuman: "\(input.amountIn.hex) in, ≥\(input.amountOutMin.hex) out",
            estimatedFeeHuman: nil,
            warnings: input.chainID.isMainnet ? ["MAINNET Uniswap swap"] : [],
            requiresExplicitUserConfirmation: input.chainID.isMainnet
        )

        let tx = EVMUnsignedTransaction(
            chainID: input.chainID, from: input.recipient, to: router,
            valueWei: nil, data: EVMHexData(calldata),
            gasLimit: nil, maxFeePerGas: nil, maxPriorityFeePerGas: nil, nonce: nil,
            riskSummary: risk
        )

        return UniswapSwapOutput(
            unsignedTransaction: tx,
            humanPreview: "Swap \(input.amountIn.hex) of \(input.tokenIn.hex) → ≥\(input.amountOutMin.hex) of \(input.tokenOut.hex) via Uniswap V3 (\(input.feeTier.label))",
            routerAddress: router
        )
    }
}

// MARK: - Pool address query

public struct UniswapPoolInput: Codable, Sendable {
    public let tokenA: EVMAddress
    public let tokenB: EVMAddress
    public let feeTier: UniswapFeeTier
    public let chainID: EVMChainID
    public init(tokenA: EVMAddress, tokenB: EVMAddress, feeTier: UniswapFeeTier = .fee3000, chainID: EVMChainID = .mainnet) {
        self.tokenA = tokenA; self.tokenB = tokenB; self.feeTier = feeTier; self.chainID = chainID
    }
}

public struct UniswapPoolOutput: Codable, Sendable {
    public let poolAddress: EVMAddress
    public let token0: EVMAddress
    public let token1: EVMAddress
    public let feeTier: UniswapFeeTier
}

public struct UniswapPoolTool: SwooshTool {
    public typealias Input = UniswapPoolInput
    public typealias Output = UniswapPoolOutput
    public static let name: ToolName = "uniswap.pool_address"
    public static let displayName = "Uniswap Pool Address"
    public static let description = "Compute the deterministic Uniswap V3 pool address for a token pair and fee tier"
    public static let permission = SwooshPermission.evmRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.uniswap

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        // Sort tokens: Uniswap requires token0 < token1 (lexicographic on address hex)
        let (token0, token1) = input.tokenA.hex < input.tokenB.hex
            ? (input.tokenA, input.tokenB)
            : (input.tokenB, input.tokenA)

        let poolAddr = try computeV3PoolAddress(
            factory: factoryAddress(chainID: input.chainID),
            token0: token0, token1: token1, fee: input.feeTier.rawValue
        )
        return UniswapPoolOutput(
            poolAddress: EVMAddress(poolAddr),
            token0: token0, token1: token1, feeTier: input.feeTier
        )
    }
}

// MARK: - ABI encoding helpers (minimal, no external dep)

/// Canonical Uniswap V3 contract addresses
private func quoterV2Address(chainID: EVMChainID) -> String {
    switch chainID.value {
    case 1:     return "0x61ffe014ba17989e743c5f6cb21bf9697530b21e" // Ethereum
    case 8453:  return "0x3d4e44Eb1374240CE5F1B136132D486bab77e3c3" // Base
    case 42161: return "0x61ffe014ba17989e743c5f6cb21bf9697530b21e" // Arbitrum
    case 137:   return "0x61ffe014ba17989e743c5f6cb21bf9697530b21e" // Polygon
    default:    return "0x61ffe014ba17989e743c5f6cb21bf9697530b21e"
    }
}

private func swapRouter02Address(chainID: EVMChainID) -> String {
    switch chainID.value {
    case 1:     return "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" // Ethereum
    case 8453:  return "0x2626664c2603336E57B271c5C0b26F421741e481" // Base
    case 42161: return "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" // Arbitrum
    case 137:   return "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" // Polygon
    default:    return "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
    }
}

private func factoryAddress(chainID: EVMChainID) -> String {
    "0x1F98431c8aD98523631AE4a59f267346ea31F984" // same across all chains
}

/// Encode quoteExactInputSingle(tokenIn, tokenOut, amountIn, fee, sqrtPriceLimitX96)
private func encodeQuoteExactInputSingle(tokenIn: EVMAddress, tokenOut: EVMAddress, fee: Int, amountIn: BigInt) -> String {
    // selector: quoteExactInputSingle((address,address,uint256,uint24,uint160))
    // keccak("quoteExactInputSingle((address,address,uint256,uint24,uint160))") = 0xcdca1753
    let selector = "cdca1753"
    let t0 = padLeft(tokenIn.hex.replacingOccurrences(of: "0x", with: ""), 64)
    let t1 = padLeft(tokenOut.hex.replacingOccurrences(of: "0x", with: ""), 64)
    let amt = padLeft(String(amountIn, radix: 16), 64)
    let f = padLeft(String(fee, radix: 16), 64)
    let lim = padLeft("0", 64)
    // struct offset
    let offset = padLeft("20", 64)
    return "0x" + selector + offset + t0 + t1 + amt + f + lim
}

/// Encode exactInputSingle for SwapRouter02
private func encodeExactInputSingle(
    tokenIn: EVMAddress, tokenOut: EVMAddress, fee: Int, recipient: EVMAddress,
    amountIn: BigInt, amountOutMinimum: BigInt, sqrtPriceLimitX96: BigInt, deadline: BigInt
) -> String {
    // selector: exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))
    // 0x414bf389
    let selector = "414bf389"
    let t0 = padLeft(tokenIn.hex.replacingOccurrences(of: "0x", with: ""), 64)
    let t1 = padLeft(tokenOut.hex.replacingOccurrences(of: "0x", with: ""), 64)
    let f  = padLeft(String(fee, radix: 16), 64)
    let rec = padLeft(recipient.hex.replacingOccurrences(of: "0x", with: ""), 64)
    let dl  = padLeft(String(deadline, radix: 16), 64)
    let ain = padLeft(String(amountIn, radix: 16), 64)
    let amin = padLeft(String(amountOutMinimum, radix: 16), 64)
    let lim  = padLeft(String(sqrtPriceLimitX96, radix: 16), 64)
    let offset = padLeft("20", 64)
    return "0x" + selector + offset + t0 + t1 + f + rec + dl + ain + amin + lim
}

/// Decode QuoterV2 quoteExactInputSingle result
private func decodeQuoteResult(_ hex: String) -> (BigInt, BigInt, Int, BigInt) {
    let data = hex.replacingOccurrences(of: "0x", with: "")
    func word(_ i: Int) -> String { String(data.dropFirst(i * 64).prefix(64)) }
    let amountOut = BigInt(word(0), radix: 16) ?? BigInt(0)
    let sqrtPrice = BigInt(word(1), radix: 16) ?? BigInt(0)
    let ticksAfter = Int(word(2), radix: 16) ?? 0
    let gasEstimate = BigInt(word(3), radix: 16) ?? BigInt(0)
    return (amountOut, sqrtPrice, ticksAfter, gasEstimate)
}

/// Compute Uniswap V3 pool CREATE2 address (off-chain, no RPC needed)
private func computeV3PoolAddress(factory: String, token0: EVMAddress, token1: EVMAddress, fee: Int) throws -> String {
    let factoryBytes = try addressBytes(factory)
    let token0Bytes = try addressBytes(token0.hex)
    let token1Bytes = try addressBytes(token1.hex)
    guard (0...0xFF_FFFF).contains(fee) else {
        throw ToolError.executionFailed("Invalid Uniswap V3 fee tier \(fee)")
    }

    let saltInput = addressWord(token0Bytes) + addressWord(token1Bytes) + uint24Word(fee)
    let salt = keccak256(saltInput)
    let initCodeHash = try hexBytes("e34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54")
    let create2Input = [UInt8(0xff)] + factoryBytes + salt + initCodeHash
    let hash = keccak256(create2Input)
    return "0x" + hexString(Array(hash.suffix(20)))
}

private func padLeft(_ s: String, _ n: Int) -> String {
    let clean = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
    return String(repeating: "0", count: max(0, n - clean.count)) + clean
}

private func addressBytes(_ hex: String) throws -> [UInt8] {
    let bytes = try hexBytes(hex)
    guard bytes.count == 20 else {
        throw ToolError.executionFailed("Invalid EVM address length for \(hex)")
    }
    return bytes
}

private func hexBytes(_ hex: String) throws -> [UInt8] {
    let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    guard clean.count.isMultiple(of: 2) else {
        throw ToolError.executionFailed("Invalid hex length")
    }
    var bytes: [UInt8] = []
    var index = clean.startIndex
    while index < clean.endIndex {
        let next = clean.index(index, offsetBy: 2)
        guard let byte = UInt8(clean[index..<next], radix: 16) else {
            throw ToolError.executionFailed("Invalid hex byte")
        }
        bytes.append(byte)
        index = next
    }
    return bytes
}

private func addressWord(_ bytes: [UInt8]) -> [UInt8] {
    Array(repeating: 0, count: 12) + bytes
}

private func uint24Word(_ value: Int) -> [UInt8] {
    var word = Array(repeating: UInt8(0), count: 32)
    word[29] = UInt8((value >> 16) & 0xff)
    word[30] = UInt8((value >> 8) & 0xff)
    word[31] = UInt8(value & 0xff)
    return word
}

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func keccak256(_ input: [UInt8]) -> [UInt8] {
    let rate = 136
    var state = [UInt64](repeating: 0, count: 25)
    var offset = 0

    while input.count - offset >= rate {
        absorbKeccakBlock(Array(input[offset..<(offset + rate)]), into: &state)
        keccakF1600(&state)
        offset += rate
    }

    var block = Array(repeating: UInt8(0), count: rate)
    let remaining = input.count - offset
    if remaining > 0 {
        for i in 0..<remaining {
            block[i] = input[offset + i]
        }
    }
    block[remaining] ^= 0x01
    block[rate - 1] ^= 0x80
    absorbKeccakBlock(block, into: &state)
    keccakF1600(&state)

    var output: [UInt8] = []
    output.reserveCapacity(32)
    for lane in state.prefix(4) {
        for shift in stride(from: 0, to: 64, by: 8) {
            output.append(UInt8((lane >> UInt64(shift)) & 0xff))
        }
    }
    return Array(output.prefix(32))
}

private func absorbKeccakBlock(_ block: [UInt8], into state: inout [UInt64]) {
    for laneIndex in 0..<(block.count / 8) {
        var lane = UInt64(0)
        for byteIndex in 0..<8 {
            lane |= UInt64(block[laneIndex * 8 + byteIndex]) << UInt64(byteIndex * 8)
        }
        state[laneIndex] ^= lane
    }
}

private func keccakF1600(_ state: inout [UInt64]) {
    let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
        0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
        0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
        0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
        0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
        0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    let rotations = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    for roundConstant in roundConstants {
        var c = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 {
            c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
        }

        var d = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 {
            d[x] = c[(x + 4) % 5] ^ rotateLeft(c[(x + 1) % 5], by: 1)
        }
        for x in 0..<5 {
            for y in 0..<5 {
                state[x + 5 * y] ^= d[x]
            }
        }

        var b = [UInt64](repeating: 0, count: 25)
        for x in 0..<5 {
            for y in 0..<5 {
                b[y + 5 * ((2 * x + 3 * y) % 5)] = rotateLeft(state[x + 5 * y], by: rotations[x + 5 * y])
            }
        }

        for x in 0..<5 {
            for y in 0..<5 {
                state[x + 5 * y] = b[x + 5 * y] ^ ((~b[((x + 1) % 5) + 5 * y]) & b[((x + 2) % 5) + 5 * y])
            }
        }

        state[0] ^= roundConstant
    }
}

private func rotateLeft(_ value: UInt64, by offset: Int) -> UInt64 {
    guard offset != 0 else { return value }
    return (value << UInt64(offset)) | (value >> UInt64(64 - offset))
}
