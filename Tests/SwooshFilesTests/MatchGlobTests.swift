// Tests/SwooshFilesTests/MatchGlobTests.swift — 0.4D
//
// `SafeFileAccessor.matchGlob` is internal and used by `searchFiles` to
// filter results by basename. Exhaustively walks every supported form
// added in 0.4D and documents what is deliberately NOT supported.

import Foundation
import Testing
@testable import SwooshFiles

@Suite("SafeFileAccessor.matchGlob")
struct MatchGlobTests {

    private let fa = SafeFileAccessor(rootStore: InMemoryRootStore())

    // MARK: - Exact match (no wildcard)

    @Test("Exact name matches when identical")
    func exact() {
        #expect(fa.matchGlob(name: "README.md", pattern: "README.md"))
        #expect(!fa.matchGlob(name: "README.md", pattern: "readme.md"))
        #expect(!fa.matchGlob(name: "README", pattern: "README.md"))
    }

    // MARK: - Suffix (*X / *.ext)

    @Test("Suffix pattern '*.swift' matches all swift files")
    func suffixExtension() {
        #expect(fa.matchGlob(name: "Foo.swift", pattern: "*.swift"))
        #expect(fa.matchGlob(name: "Bar.swift", pattern: "*.swift"))
        #expect(!fa.matchGlob(name: "Foo.kt", pattern: "*.swift"))
        #expect(!fa.matchGlob(name: "Foo.swiftBackup", pattern: "*.swift"))
    }

    @Test("Suffix pattern '*Tests' matches anything ending Tests")
    func suffixGeneric() {
        #expect(fa.matchGlob(name: "FooTests", pattern: "*Tests"))
        #expect(fa.matchGlob(name: "BarTests", pattern: "*Tests"))
        #expect(!fa.matchGlob(name: "TestsFoo", pattern: "*Tests"))
    }

    // MARK: - Prefix (X*)

    @Test("Prefix pattern 'Tests*' matches anything starting Tests")
    func prefixGeneric() {
        #expect(fa.matchGlob(name: "TestsFoo", pattern: "Tests*"))
        #expect(fa.matchGlob(name: "Tests.swift", pattern: "Tests*"))
        #expect(!fa.matchGlob(name: "FooTests", pattern: "Tests*"))
    }

    // MARK: - Contains (*X*)

    @Test("Contains pattern '*Foo*' matches anywhere in the name")
    func contains() {
        #expect(fa.matchGlob(name: "FooBar", pattern: "*Foo*"))
        #expect(fa.matchGlob(name: "BarFooBaz", pattern: "*Foo*"))
        #expect(fa.matchGlob(name: "BarFoo", pattern: "*Foo*"))
        #expect(!fa.matchGlob(name: "Bar", pattern: "*Foo*"))
    }

    // MARK: - Prefix+suffix (X*Y)

    @Test("Embedded star 'Tests*.swift' splits into prefix + suffix")
    func prefixAndSuffix() {
        #expect(fa.matchGlob(name: "TestsFoo.swift", pattern: "Tests*.swift"))
        #expect(fa.matchGlob(name: "Tests.swift", pattern: "Tests*.swift"))
        #expect(!fa.matchGlob(name: "FooTests.swift", pattern: "Tests*.swift"))
        #expect(!fa.matchGlob(name: "TestsFoo.kt", pattern: "Tests*.swift"))
    }

    // MARK: - Star-only

    @Test("Bare '*' matches everything")
    func bareStar() {
        #expect(fa.matchGlob(name: "", pattern: "*"))
        #expect(fa.matchGlob(name: "anything.swift", pattern: "*"))
        #expect(fa.matchGlob(name: "no-extension", pattern: "*"))
    }

    @Test("'**' also matches everything (graceful, not a recursive glob)")
    func doubleStar() {
        #expect(fa.matchGlob(name: "anything", pattern: "**"))
    }

    // MARK: - Unsupported forms (documented as out-of-spec)

    @Test("Multiple embedded stars (e.g. 'A*B*C') are not supported")
    func multipleEmbeddedStars() {
        // Documented limit: only one embedded `*` is supported. Names
        // that "should" match under a richer glob return false.
        #expect(!fa.matchGlob(name: "AxBxC", pattern: "A*B*C"))
    }

    @Test("Path separators in input are not stripped (caller's responsibility)")
    func pathSeparators() {
        // The caller is responsible for passing only a basename. The
        // matcher treats slashes literally.
        #expect(!fa.matchGlob(name: "dir/Foo.swift", pattern: "*.swift") == false)
        // Confirming positive case: the substring after the last slash
        // would match, but our matcher doesn't split — it tests the
        // full input.
        #expect(fa.matchGlob(name: "dir/Foo.swift", pattern: "*.swift"))
    }
}
