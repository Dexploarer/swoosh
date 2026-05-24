// SwooshModels/Exports.swift — Re-export Foundation.URL for SwooshModels consumers — 0.9U
//
// SwooshModels' public APIs (e.g. `DynamicModelLoader.init(ollamaBase:hfBase:session:)`)
// take `URL` parameters. Re-exporting `Foundation.URL` from this module lets
// callers `import SwooshModels` without also writing `import Foundation` just
// to construct a `URL`. The underscored `@_exported` is the only mechanism
// Swift offers for selective re-export; the alternative is to delete this
// line and force every consumer to add `import Foundation` themselves —
// rejected because most consumers already pay that cost via SwiftUI/Foundation
// transitively, and the keystroke saving is worth the well-known attribute.
@_exported import struct Foundation.URL
