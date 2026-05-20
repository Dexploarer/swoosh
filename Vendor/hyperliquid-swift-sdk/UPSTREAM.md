# Hyperliquid Swift SDK

Vendored from `https://github.com/tranhoangpich/hyperliquid-swift-sdk.git` at revision `87fcc5296c37a4a414ab9eb4bad9979f79fb5136`.

Swoosh uses only the `HyperliquidSwift` library target. The upstream manifest also declares multiple executable example targets that share one `Examples/` directory, which makes SwiftPM print unhandled-file warnings on every build and run. This local package keeps the library source and transitive dependencies while omitting those example targets.
