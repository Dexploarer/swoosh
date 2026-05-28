import Foundation
import SwooshProviders

let provider = CodexBridgeProvider()
Task {
    let auth = await provider.isAuthenticated()
    print("Is authenticated: \(auth)")
    exit(0)
}
dispatchMain()
