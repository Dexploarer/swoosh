# SwooshDB Spike 0.2A

## Status: ✅ Milestones A + B PASS

SpacetimeDB v2.1 local standalone + Rust WASM module + 6 tables + 7 reducers = working.

## What was proven

| Test | Result |
|------|--------|
| Local `spacetime start` on 127.0.0.1:3000 | ✅ Works |
| Rust module compiles to WASM | ✅ Works |
| Module publishes to local instance | ✅ Works |
| `create_memory_candidate` reducer | ✅ Creates pending candidate + audit event |
| `approve_memory_candidate` reducer | ✅ Updates status + creates approved_memory + audit event |
| `reject_memory_candidate` reducer | ✅ Updates status to rejected, NO approved_memory created |
| Rejected candidate cannot become approved | ✅ Status check enforced |
| Audit trail captures every mutation | ✅ All events logged with timestamps |

## What is not yet tested

- Swift client subscription (live UI updates)
- CLI → SpacetimeDB reducer bridge
- Concurrent multi-client sync
- Reconnect reliability
- Performance under load
- Long-running stability

## Swift client status

- SwooshStatePlane protocol: ✅ defined
- SQLiteStatePlane: ✅ compiles, wraps existing SwooshStateStore
- SpacetimeStatePlane: ⬜ not yet implemented (needs Swift SDK)
- Community SDK (`avias8/spacetimedb-swift`): not yet evaluated

## Local packaging status

- `spacetime start` runs as a foreground process — needs supervision
- SpacetimeSupervisor actor ready in `SwooshDBClient`
- Data stored in `~/.local/share/spacetime/data` by default
- No SSL in standalone mode — loopback only is correct

## Security

- Secrets remain in Keychain — never in SpacetimeDB
- Audit events on every reducer call
- Memory approval is transactional
- Rejected candidates cannot be approved (reducer enforces)

## Next steps

1. Evaluate `avias8/spacetimedb-swift` SDK for Swift subscriptions
2. If Swift SDK works: implement SpacetimeStatePlane
3. If not: build minimal WebSocket+BSATN client or use TypeScript bridge
4. Wire Scout → SpacetimeDB reducer calls
5. Build SwiftUI live MemoryCandidateReviewView with subscriptions

## Decision checkpoint

- **Promote** if Swift subscriptions work and dev experience is clean
- **Keep experimental** if Swift SDK is too immature but core model works
- **Kill** if packaging is too heavy or reliability is poor
