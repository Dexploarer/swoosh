// SwooshPlugins/CodableHelpers.swift — Tiny decode-or-default helper — 0.9A
//
// Every plugin schema type that supports backward-compatible decoding
// uses the same `(try? c.decode(T.self, forKey: key)) ?? default` pattern.
// This helper centralises that idiom so the three custom-Codable impls in
// this module stay readable.
//
// Semantics deliberately preserved from the original sites: a thrown
// decode error (key missing OR value wrong type) returns the default.
// That's more permissive than `decodeIfPresent`, which only handles the
// key-missing case — and we want the permissive form here so older
// manifests with mild schema drift still load.

import Foundation

extension KeyedDecodingContainer {
    /// Decode `key` as `T`, returning `defaultValue` on any decode failure
    /// (missing key, wrong type, malformed value). Use only on optional
    /// fields where backward compatibility outweighs strictness.
    func decodeOrDefault<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        default defaultValue: T
    ) -> T {
        (try? decode(type, forKey: key)) ?? defaultValue
    }

    /// Decode `key` as optional `T`. Mirrors `decodeIfPresent` but swallows
    /// type-mismatch errors too — same backward-compat reason as
    /// `decodeOrDefault`. Returns `nil` when the value is absent or
    /// unparseable.
    func decodeOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decode(type, forKey: key)
    }
}
