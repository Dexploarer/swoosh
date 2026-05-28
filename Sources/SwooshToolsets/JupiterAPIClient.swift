// SwooshToolsets/JupiterAPIClient.swift

import Foundation

enum JupiterApi {
    static func token(mint: String) async throws -> TokenInfoResponse {
        let results: [TokenInfoResponse] = try await get(
            path: "/tokens/v2/search",
            queryItems: [URLQueryItem(name: "query", value: mint)]
        )
        guard let exact = results.first(where: { $0.address == mint }) ?? results.first else {
            throw JupiterAPIError.emptyResponse("token search returned no result for \(mint)")
        }
        return exact
    }

    static func market(market: String) async throws -> [String] {
        try await get(path: "/tokens/v1/market/\(market)/mints")
    }

    static func tradableTokens() async throws -> [String] {
        try await get(path: "/tokens/v1/mints/tradable")
    }

    static func taggedTokens(for tag: String) async throws -> TaggedTokenListResponse {
        try await get(
            path: "/tokens/v2/tag",
            queryItems: [URLQueryItem(name: "query", value: tag)]
        )
    }

    static func newTokens() async throws -> NewTokenListResponse {
        try await get(path: "/tokens/v2/recent")
    }

    static func allTokens() async throws -> [TokenInfoResponse] {
        try await get(
            path: "/tokens/v2/toporganicscore/24h",
            queryItems: [URLQueryItem(name: "limit", value: "2000")]
        )
    }

    static func prices(ids: String) async throws -> JupiterPriceResponse {
        try await get(
            path: "/price/v3",
            queryItems: [URLQueryItem(name: "ids", value: ids)]
        )
    }

    static func balances(account: String) async throws -> BalancesResponse {
        try await get(path: "/ultra/v1/balances/\(account)")
    }

    static func shield(mints: [String]) async throws -> ShieldResponse {
        try await get(
            path: "/ultra/v1/shield",
            queryItems: [URLQueryItem(name: "mints", value: mints.joined(separator: ","))]
        )
    }

    static func routers() async throws -> [Router] {
        try await get(path: "/ultra/v1/order/routers")
    }

    static func order(
        inputMint: String,
        outputMint: String,
        amount: String,
        taker: String?,
        platformFeeBps: Int? = nil,
        feeAccount: String? = nil
    ) async throws -> OrderResponse {
        var items = [
            URLQueryItem(name: "inputMint", value: inputMint),
            URLQueryItem(name: "outputMint", value: outputMint),
            URLQueryItem(name: "amount", value: amount),
        ]
        if let taker {
            items.append(URLQueryItem(name: "taker", value: taker))
        }
        // $DTOUR trade tax — Jupiter collects the fee and routes to our account
        if let bps = platformFeeBps, bps > 0 {
            items.append(URLQueryItem(name: "platformFeeBps", value: String(bps)))
        }
        if let account = feeAccount, !account.isEmpty {
            items.append(URLQueryItem(name: "feeAccount", value: account))
        }
        return try await get(path: "/swap/v2/order", queryItems: items)
    }

    static func execute(signedTransaction: String, requestId: String) async throws -> ExecuteResponse {
        try await post(
            path: "/swap/v2/execute",
            body: ExecuteOrderRequest(signedTransaction: signedTransaction, requestId: requestId)
        )
    }

    static func createOrder(
        inputMint: String,
        outputMint: String,
        makingAmount: String,
        takingAmount: String,
        payer: String
    ) async throws -> CreateTriggerOrderResponse {
        let body = CreateTriggerOrderRequest(
            inputMint: inputMint,
            outputMint: outputMint,
            maker: payer,
            payer: payer,
            params: TriggerParams(makingAmount: makingAmount, takingAmount: takingAmount),
            feeAccount: feeAccount(for: outputMint)
        )
        return try await post(path: "/trigger/v1/createOrder", body: body)
    }

    static func cancelTriggerOrder(maker: String, order: String) async throws -> CancelTriggerOrderResponse {
        try await post(path: "/trigger/v1/cancelOrder", body: CancelOrder(maker: maker, order: order))
    }

    static func getActiveTriggerOrders(user: String) async throws -> GetTriggerOrdersResponse {
        try await getTriggerOrders(user: user, orderStatus: "active")
    }

    static func getHistoryTriggerOrders(user: String) async throws -> GetTriggerOrdersResponse {
        try await getTriggerOrders(user: user, orderStatus: "history")
    }

    static func getTriggerOrders(user: String, orderStatus: String) async throws -> GetTriggerOrdersResponse {
        try await get(
            path: "/trigger/v1/getTriggerOrders",
            queryItems: [
                URLQueryItem(name: "user", value: user),
                URLQueryItem(name: "orderStatus", value: orderStatus),
            ]
        )
    }

    static func createRecurringOrder(
        inputMint: String,
        outputMint: String,
        params: RecurringParams,
        user: String
    ) async throws -> CreateRecurringOrderResponse {
        try await post(
            path: "/recurring/v1/createOrder",
            body: CreateRecurringOrderRequest(
                user: user,
                inputMint: inputMint,
                outputMint: outputMint,
                params: params
            )
        )
    }

    static func getRecurringOrders(
        account: String,
        orderStatus: OrderStatus,
        recurringType: RecurringType
    ) async throws -> GetRecurringOrdersResponse {
        try await get(
            path: "/recurring/v1/getRecurringOrders",
            queryItems: [
                URLQueryItem(name: "user", value: account),
                URLQueryItem(name: "orderStatus", value: orderStatus.rawValue),
                URLQueryItem(name: "recurringType", value: recurringType.rawValue),
                URLQueryItem(name: "includeFailedTx", value: "true"),
            ]
        )
    }

    static func cancelRecurringOrder(order: String, user: String, recurringType: String) async throws -> CancelRecurringOrderResponse {
        try await post(
            path: "/recurring/v1/cancelOrder",
            body: CancelRecurringOrderRequest(order: order, user: user, recurringType: recurringType)
        )
    }

    static func priceDeposit(order: String, user: String, amount: UInt64) async throws -> PriceDepositeResponse {
        try await post(
            path: "/recurring/v1/priceDeposit",
            body: PriceDepositeRequest(order: order, user: user, amount: amount)
        )
    }

    static func priceWithdraw(order: String, user: String, amount: UInt64) async throws -> PriceWithdrawResponse {
        try await post(
            path: "/recurring/v1/priceWithdraw",
            body: PriceWithdrawRequest(order: order, user: user, amount: amount)
        )
    }

    private static func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return try await send(request)
    }

    private static func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body
    ) async throws -> T {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JupiterAPIError.transport("missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw JupiterAPIError.httpStatus(http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw JupiterAPIError.decode("\(error) — body: \(body)")
        }
    }

    private static func url(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.jup.ag"
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw JupiterAPIError.invalidURL(path: path)
        }
        return url
    }

    private static func applyHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = ProcessInfo.processInfo.environment["JUPITER_API_KEY"],
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
    }

    private static func feeAccount(for outputMint: String) -> String? {
        switch outputMint {
        case "So11111111111111111111111111111111111111112":
            return "3ssPtzEQc42w5zRMjNZSroQ36cToxUGx5AjD3HZCku9N"
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v":
            return "Afkk6kwhiGtRnKwYEJY1XbSG4J8oedB5CXW4zrPy6MLV"
        case "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN":
            return "4eNzPMjH2Xw5ggXGLeRbZNgxTdDD5KxqKrFAxMJQ5hya"
        default:
            return nil
        }
    }
}

enum JupiterAPIError: Error, Sendable {
    case invalidURL(path: String)
    case emptyResponse(String)
    case transport(String)
    case httpStatus(Int, body: String)
    case decode(String)
}

public struct TokenBalance: Codable, Hashable, Sendable {
    public let amount: String
    public let uiAmount: Double
    public let slot: Int
    public let isFrozen: Bool
}

public typealias JupiterPriceResponse = [String: JupiterPriceValue]

public struct JupiterPriceValue: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let liquidity: Double?
    public let usdPrice: Double?
    public let blockId: Int?
    public let decimals: Int?
    public let priceChange24h: Double?
}

public struct BalancesResponse: Codable, Hashable, Sendable {
    public let balances: [String: TokenBalance]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        balances = try container.decode([String: TokenBalance].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(balances)
    }
}

public typealias TaggedTokenListResponse = [TokenInfoResponse]

public struct TokenInfoResponse: Codable, Hashable, Sendable {
    public let address: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let logoURI: String?
    public let tags: [String]?
    public let dailyVolume: Double?
    public let freezeAuthority: String?
    public let mintAuthority: String?

    enum CodingKeys: String, CodingKey {
        case id
        case address
        case mint
        case name
        case symbol
        case decimals
        case icon
        case logoURI
        case logoURIUnderscored = "logo_uri"
        case tags
        case stats24h
        case dailyVolumeCamel = "dailyVolume"
        case dailyVolume = "daily_volume"
        case freezeAuthorityCamel = "freezeAuthority"
        case freezeAuthority = "freeze_authority"
        case mintAuthorityCamel = "mintAuthority"
        case mintAuthority = "mint_authority"
    }

    public init(
        address: String,
        name: String,
        symbol: String,
        decimals: Int,
        logoURI: String?,
        tags: [String]?,
        dailyVolume: Double?,
        freezeAuthority: String?,
        mintAuthority: String?
    ) {
        self.address = address
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.logoURI = logoURI
        self.tags = tags
        self.dailyVolume = dailyVolume
        self.freezeAuthority = freezeAuthority
        self.mintAuthority = mintAuthority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAddress = try container.decodeIfPresent(String.self, forKey: .address)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .mint)
        guard let decodedAddress else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected token mint address in id, address, or mint"
                )
            )
        }
        let stats24h = try container.decodeIfPresent(TokenStats24h.self, forKey: .stats24h)
        address = decodedAddress
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)
        logoURI = try container.decodeIfPresent(String.self, forKey: .logoURI)
            ?? container.decodeIfPresent(String.self, forKey: .logoURIUnderscored)
            ?? container.decodeIfPresent(String.self, forKey: .icon)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        dailyVolume = try container.decodeIfPresent(Double.self, forKey: .dailyVolume)
            ?? container.decodeIfPresent(Double.self, forKey: .dailyVolumeCamel)
            ?? stats24h?.dailyVolume
        freezeAuthority = try container.decodeIfPresent(String.self, forKey: .freezeAuthority)
            ?? container.decodeIfPresent(String.self, forKey: .freezeAuthorityCamel)
        mintAuthority = try container.decodeIfPresent(String.self, forKey: .mintAuthority)
            ?? container.decodeIfPresent(String.self, forKey: .mintAuthorityCamel)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(decimals, forKey: .decimals)
        try container.encodeIfPresent(logoURI, forKey: .logoURI)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(dailyVolume, forKey: .dailyVolume)
        try container.encodeIfPresent(freezeAuthority, forKey: .freezeAuthority)
        try container.encodeIfPresent(mintAuthority, forKey: .mintAuthority)
    }
}

private struct TokenStats24h: Codable, Hashable, Sendable {
    let volume: Double?
    let buyVolume: Double?
    let sellVolume: Double?

    var dailyVolume: Double? {
        if let volume {
            return volume
        }
        guard let buyVolume, let sellVolume else {
            return nil
        }
        return buyVolume + sellVolume
    }
}

public typealias NewTokenListResponse = [NewToken]

public struct NewToken: Codable, Hashable, Sendable {
    public let createdAt: String
    public let decimals: Int
    public let freezeAuthority: String?
    public let knownMarkets: [String]
    public let logoURI: String?
    public let mint: String
    public let mintAuthority: String?
    public let name: String
    public let symbol: String

    enum CodingKeys: String, CodingKey {
        case id
        case address
        case createdAt = "created_at"
        case createdAtCamel = "createdAt"
        case decimals
        case firstPool
        case freezeAuthorityCamel = "freezeAuthority"
        case freezeAuthority = "freeze_authority"
        case markets
        case knownMarkets = "known_markets"
        case icon
        case logoURI = "logo_uri"
        case logoURICamel = "logoURI"
        case mint
        case mintAuthorityCamel = "mintAuthority"
        case mintAuthority = "mint_authority"
        case name
        case symbol
    }

    public init(
        createdAt: String,
        decimals: Int,
        freezeAuthority: String?,
        knownMarkets: [String],
        logoURI: String?,
        mint: String,
        mintAuthority: String?,
        name: String,
        symbol: String
    ) {
        self.createdAt = createdAt
        self.decimals = decimals
        self.freezeAuthority = freezeAuthority
        self.knownMarkets = knownMarkets
        self.logoURI = logoURI
        self.mint = mint
        self.mintAuthority = mintAuthority
        self.name = name
        self.symbol = symbol
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMint = try container.decodeIfPresent(String.self, forKey: .mint)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .address)
        guard let decodedMint else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected token mint address in id, address, or mint"
                )
            )
        }
        let firstPool = try container.decodeIfPresent(TokenFirstPool.self, forKey: .firstPool)
        let decodedCreatedAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAtCamel)
            ?? firstPool?.createdAt
        guard let decodedCreatedAt else {
            throw DecodingError.keyNotFound(
                CodingKeys.createdAtCamel,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected token creation or first pool timestamp"
                )
            )
        }
        createdAt = decodedCreatedAt
        decimals = try container.decode(Int.self, forKey: .decimals)
        freezeAuthority = try container.decodeIfPresent(String.self, forKey: .freezeAuthority)
            ?? container.decodeIfPresent(String.self, forKey: .freezeAuthorityCamel)
        knownMarkets = try container.decodeIfPresent([String].self, forKey: .knownMarkets)
            ?? container.decodeIfPresent([String].self, forKey: .markets)
            ?? []
        logoURI = try container.decodeIfPresent(String.self, forKey: .logoURI)
            ?? container.decodeIfPresent(String.self, forKey: .logoURICamel)
            ?? container.decodeIfPresent(String.self, forKey: .icon)
        mint = decodedMint
        mintAuthority = try container.decodeIfPresent(String.self, forKey: .mintAuthority)
            ?? container.decodeIfPresent(String.self, forKey: .mintAuthorityCamel)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(decimals, forKey: .decimals)
        try container.encodeIfPresent(freezeAuthority, forKey: .freezeAuthority)
        try container.encode(knownMarkets, forKey: .knownMarkets)
        try container.encodeIfPresent(logoURI, forKey: .logoURI)
        try container.encode(mint, forKey: .mint)
        try container.encodeIfPresent(mintAuthority, forKey: .mintAuthority)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
    }
}

private struct TokenFirstPool: Codable, Hashable, Sendable {
    let createdAt: String?
}

public struct TokenWarning: Codable, Hashable, Sendable {
    public let type: String
    public let message: String
    public let severity: String
}

public struct ShieldResponse: Codable, Hashable, Sendable {
    public let warnings: [String: [TokenWarning]]
}

public struct Router: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
}

public struct RoutePlan: Codable, Hashable, Sendable {
    public let swapInfo: SwapInfo
    public let percent: Int

    enum CodingKeys: String, CodingKey {
        case swapInfo
        case percent
        case bps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        swapInfo = try container.decode(SwapInfo.self, forKey: .swapInfo)
        if let decodedPercent = try container.decodeIfPresent(Int.self, forKey: .percent) {
            percent = decodedPercent
        } else if let bps = try container.decodeIfPresent(Int.self, forKey: .bps) {
            percent = bps / 100
        } else {
            percent = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(swapInfo, forKey: .swapInfo)
        try container.encode(percent, forKey: .percent)
    }
}

public struct SwapInfo: Codable, Hashable, Sendable {
    public let ammKey: String
    public let label: String
    public let inputMint: String
    public let outputMint: String
    public let inAmount: String
    public let outAmount: String
    public let feeAmount: String
    public let feeMint: String

    enum CodingKeys: String, CodingKey {
        case ammKey
        case label
        case inputMint
        case outputMint
        case inAmount
        case outAmount
        case feeAmount
        case feeMint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ammKey = try container.decode(String.self, forKey: .ammKey)
        label = try container.decode(String.self, forKey: .label)
        inputMint = try container.decode(String.self, forKey: .inputMint)
        outputMint = try container.decode(String.self, forKey: .outputMint)
        inAmount = try container.decode(String.self, forKey: .inAmount)
        outAmount = try container.decode(String.self, forKey: .outAmount)
        feeAmount = try container.decodeIfPresent(String.self, forKey: .feeAmount) ?? ""
        feeMint = try container.decodeIfPresent(String.self, forKey: .feeMint) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ammKey, forKey: .ammKey)
        try container.encode(label, forKey: .label)
        try container.encode(inputMint, forKey: .inputMint)
        try container.encode(outputMint, forKey: .outputMint)
        try container.encode(inAmount, forKey: .inAmount)
        try container.encode(outAmount, forKey: .outAmount)
        try container.encode(feeAmount, forKey: .feeAmount)
        try container.encode(feeMint, forKey: .feeMint)
    }
}

public struct OrderResponse: Codable, Hashable, Sendable {
    public let mode: String?
    public let inputMint: String
    public let outputMint: String
    public let inAmount: String
    public let outAmount: String
    public let slippageBps: Int
    public let priceImpactPct: String
    public let routePlan: [RoutePlan]
    public let router: String?
    public let prioritizationFeeLamports: Int
    public let transaction: String?
    public let requestId: String
    public let errorCode: Int?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case inputMint
        case outputMint
        case inAmount
        case outAmount
        case slippageBps
        case priceImpact
        case priceImpactPct
        case routePlan
        case router
        case prioritizationFeeLamports
        case transaction
        case requestId
        case errorCode
        case errorMessage
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        inputMint = try container.decode(String.self, forKey: .inputMint)
        outputMint = try container.decode(String.self, forKey: .outputMint)
        inAmount = try container.decode(String.self, forKey: .inAmount)
        outAmount = try container.decode(String.self, forKey: .outAmount)
        slippageBps = try container.decodeIfPresent(Int.self, forKey: .slippageBps) ?? 0
        if let decodedPriceImpactPct = try container.decodeIfPresent(String.self, forKey: .priceImpactPct) {
            priceImpactPct = decodedPriceImpactPct
        } else if let priceImpact = try container.decodeIfPresent(Double.self, forKey: .priceImpact) {
            priceImpactPct = String(priceImpact * 100)
        } else {
            priceImpactPct = "0"
        }
        routePlan = try container.decodeIfPresent([RoutePlan].self, forKey: .routePlan) ?? []
        router = try container.decodeIfPresent(String.self, forKey: .router)
        prioritizationFeeLamports = try container.decodeIfPresent(Int.self, forKey: .prioritizationFeeLamports) ?? 0
        let decodedTransaction = try container.decodeIfPresent(String.self, forKey: .transaction)
        transaction = decodedTransaction?.isEmpty == true ? nil : decodedTransaction
        requestId = try container.decode(String.self, forKey: .requestId)
        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encode(inputMint, forKey: .inputMint)
        try container.encode(outputMint, forKey: .outputMint)
        try container.encode(inAmount, forKey: .inAmount)
        try container.encode(outAmount, forKey: .outAmount)
        try container.encode(slippageBps, forKey: .slippageBps)
        try container.encode(priceImpactPct, forKey: .priceImpactPct)
        try container.encode(routePlan, forKey: .routePlan)
        try container.encodeIfPresent(router, forKey: .router)
        try container.encode(prioritizationFeeLamports, forKey: .prioritizationFeeLamports)
        try container.encodeIfPresent(transaction, forKey: .transaction)
        try container.encode(requestId, forKey: .requestId)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }
}

public typealias CancelTriggerOrderResponse = RequestTransactionResponse
public typealias CreateRecurringOrderResponse = RequestTransactionResponse
public typealias CancelRecurringOrderResponse = RequestTransactionResponse
public typealias PriceDepositeResponse = RequestTransactionResponse
public typealias PriceWithdrawResponse = RequestTransactionResponse

public struct RequestTransactionResponse: Codable, Hashable, Sendable {
    public let requestId: String
    public let transaction: String
}

public struct CreateTriggerOrderResponse: Codable, Hashable, Sendable {
    public let requestId: String
    public let transaction: String
    public let order: String?
}

public struct SwapEvent: Codable, Hashable, Sendable {
    public let inputMint: String
    public let inputAmount: String
    public let outputMint: String
    public let outputAmount: String
}

public struct ExecuteResponse: Codable, Hashable, Sendable {
    public let status: String
    public let signature: String?
    public let slot: String?
    public let error: String?
    public let code: Int?
    public let totalInputAmount: String?
    public let totalOutputAmount: String?
    public let inputAmountResult: String?
    public let outputAmountResult: String?
    public let swapEvents: [SwapEvent]?

    enum CodingKeys: String, CodingKey {
        case status
        case signature
        case slot
        case error
        case code
        case totalInputAmount
        case totalOutputAmount
        case inputAmountResult
        case outputAmountResult
        case swapEvents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCode = try container.decodeIfPresent(Int.self, forKey: .code)
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? (decodedCode == 0 ? "Success" : "Failed")
        signature = try container.decodeIfPresent(String.self, forKey: .signature)
        slot = try container.decodeIfPresent(String.self, forKey: .slot)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        code = decodedCode
        totalInputAmount = try container.decodeIfPresent(String.self, forKey: .totalInputAmount)
        totalOutputAmount = try container.decodeIfPresent(String.self, forKey: .totalOutputAmount)
        inputAmountResult = try container.decodeIfPresent(String.self, forKey: .inputAmountResult)
        outputAmountResult = try container.decodeIfPresent(String.self, forKey: .outputAmountResult)
        swapEvents = try container.decodeIfPresent([SwapEvent].self, forKey: .swapEvents)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(signature, forKey: .signature)
        try container.encodeIfPresent(slot, forKey: .slot)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(totalInputAmount, forKey: .totalInputAmount)
        try container.encodeIfPresent(totalOutputAmount, forKey: .totalOutputAmount)
        try container.encodeIfPresent(inputAmountResult, forKey: .inputAmountResult)
        try container.encodeIfPresent(outputAmountResult, forKey: .outputAmountResult)
        try container.encodeIfPresent(swapEvents, forKey: .swapEvents)
    }
}

private struct ExecuteOrderRequest: Encodable {
    let signedTransaction: String
    let requestId: String
}

private struct CreateTriggerOrderRequest: Encodable {
    let inputMint: String
    let outputMint: String
    let maker: String
    let payer: String
    let params: TriggerParams
    var feeAccount: String?
}

public struct TriggerParams: Encodable, Sendable {
    let makingAmount: String
    let takingAmount: String
    let feeBps: String = "50"
}

private struct CancelOrder: Encodable {
    let maker: String
    let order: String
}

public struct GetTriggerOrdersResponse: Codable, Hashable, Sendable {
    public let user: String
    public let orderStatus: String
    public let orders: [Order]
    public let totalPages: Int
    public let page: Int
    public let totalItems: Int?
}

public struct Order: Codable, Hashable, Sendable {
    public let orderKey: String
    public let inputMint: String
    public let outputMint: String
    public let makingAmount: String
    public let takingAmount: String
    public let remainingMakingAmount: String
    public let status: String
    public let createdAt: String
}

public struct CreateRecurringOrderRequest: Encodable, Sendable {
    let user: String
    let inputMint: String
    let outputMint: String
    let params: RecurringParams
}

public enum RecurringParams: Encodable, Sendable {
    case time(TimeParams)
    case price(PriceParams)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .time(let value):
            try container.encode(value, forKey: .time)
        case .price(let value):
            try container.encode(value, forKey: .price)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case time
        case price
    }
}

public struct TimeParams: Encodable, Sendable {
    let inAmount: UInt64
    let interval: UInt64
    var maxPrice: Double?
    var minPrice: Double?
    let numberOfOrders: UInt64
    var startAt: UInt64?

    public init(
        inAmount: UInt64,
        interval: UInt64,
        maxPrice: Double? = nil,
        minPrice: Double? = nil,
        numberOfOrders: UInt64,
        startAt: UInt64? = nil
    ) {
        self.inAmount = inAmount
        self.interval = interval
        self.maxPrice = maxPrice
        self.minPrice = minPrice
        self.numberOfOrders = numberOfOrders
        self.startAt = startAt
    }
}

public struct PriceParams: Encodable, Sendable {
    let depositAmount: UInt64
    let incrementUsdcValue: UInt64
    let interval: UInt64
    var startAt: UInt64?

    public init(depositAmount: UInt64, incrementUsdcValue: UInt64, interval: UInt64, startAt: UInt64? = nil) {
        self.depositAmount = depositAmount
        self.incrementUsdcValue = incrementUsdcValue
        self.interval = interval
        self.startAt = startAt
    }
}

public struct GetRecurringOrdersResponse: Codable, Sendable {
    public let user: String
    public let orderStatus: OrderStatus
    public let all: [RecurringOrder]
    public let totalPages: Int
    public let totalItems: Int
    public let page: Int
}

public enum OrderStatus: String, Codable, Sendable {
    case active
    case history
}

public enum RecurringType: String, Codable, Sendable {
    case time
    case price
    case all
}

public struct RecurringOrder: Codable, Sendable {
    public let recurringType: String
    public let orderKey: String
    public let inputMint: String
    public let outputMint: String
    public let cycleFrequency: String
    public let inAmountPerCycle: String
    public let inUsed: String
    public let outReceived: String
    public let createdAt: String
}

private struct CancelRecurringOrderRequest: Encodable, Sendable {
    let order: String
    let user: String
    let recurringType: String
}

private struct PriceDepositeRequest: Encodable, Sendable {
    let order: String
    let user: String
    let amount: UInt64
}

private struct PriceWithdrawRequest: Encodable, Sendable {
    let order: String
    let user: String
    let inputOrOutput: String = "In"
    let amount: UInt64
}
