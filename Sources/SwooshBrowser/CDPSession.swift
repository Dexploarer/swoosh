// SwooshBrowser/CDPSession.swift — CDP browser session
import Foundation

public actor CDPBrowserSession: BrowserSession {
    public nonisolated let sessionID: String
    private let connection: CDPConnection
    private var _currentURL: URL?
    private var _isActive: Bool = true
    public var currentURL: URL? { _currentURL }
    public var isActive: Bool { _isActive }

    public init(connection: CDPConnection) {
        self.sessionID = UUID().uuidString
        self.connection = connection
    }

    public func navigate(to url: URL) async throws {
        let _ = try await connection.send(method: "Page.navigate", params: ["url": .string(url.absoluteString)])
        _currentURL = url
        try await waitForLoad(timeout: 30)
    }
    public func goBack() async throws { let _ = try await connection.send(method: "Page.goBack") }
    public func goForward() async throws { let _ = try await connection.send(method: "Page.goForward") }
    public func reload() async throws { let _ = try await connection.send(method: "Page.reload") }
    public func waitForLoad(timeout: TimeInterval) async throws { try await Task.sleep(for: .seconds(min(timeout, 2))) }

    public func click(selector: String) async throws {
        let _ = try await evaluate(javascript: "document.querySelector('\(esc(selector))').click()")
    }
    public func type(selector: String, text: String) async throws {
        let t = text.replacingOccurrences(of: "'", with: "\\'")
        let _ = try await evaluate(javascript: "var e=document.querySelector('\(esc(selector))');e.focus();e.value='\(t)';e.dispatchEvent(new Event('input',{bubbles:true}))")
    }
    public func clear(selector: String) async throws {
        let _ = try await evaluate(javascript: "var e=document.querySelector('\(esc(selector))');if(e){e.value='';e.dispatchEvent(new Event('input',{bubbles:true}))}")
    }
    public func select(selector: String, value: String) async throws {
        let v = value.replacingOccurrences(of: "'", with: "\\'")
        let _ = try await evaluate(javascript: "var e=document.querySelector('\(esc(selector))');if(e){e.value='\(v)';e.dispatchEvent(new Event('change',{bubbles:true}))}")
    }
    public func scroll(x: Int, y: Int) async throws { let _ = try await evaluate(javascript: "window.scrollBy(\(x),\(y))") }
    public func hover(selector: String) async throws {
        let _ = try await evaluate(javascript: "var e=document.querySelector('\(esc(selector))');if(e)e.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}))")
    }

    public func screenshot(fullPage: Bool = false) async throws -> Data {
        var params: [String: AnyCodableValue] = ["format": .string("png")]
        if fullPage { params["captureBeyondViewport"] = .bool(true) }
        let r = try await connection.send(method: "Page.captureScreenshot", params: params)
        guard let b64 = r.result?["data"]?.stringValue, let data = Data(base64Encoded: b64) else { throw BrowserError.screenshotFailed("No data") }
        return data
    }
    public func extractText() async throws -> String { try await evaluate(javascript: "document.body.innerText") }
    public func extractHTML() async throws -> String { try await evaluate(javascript: "document.documentElement.outerHTML") }
    public func extractLinks() async throws -> [PageLink] {
        let r = try await evaluate(javascript: "JSON.stringify(Array.from(document.querySelectorAll('a[href]')).map(a=>({href:a.href,text:a.innerText.trim().substring(0,200),isExternal:a.hostname!==location.hostname})))")
        guard let d = r.data(using: .utf8) else { return [] }
        struct R: Decodable { let href: String; let text: String; let isExternal: Bool }
        return ((try? JSONDecoder().decode([R].self, from: d)) ?? []).map { PageLink(href: $0.href, text: $0.text, isExternal: $0.isExternal) }
    }
    public func extractForms() async throws -> [PageForm] {
        let r = try await evaluate(javascript: "JSON.stringify(Array.from(document.querySelectorAll('form')).map(f=>({action:f.action,method:f.method||'GET',fields:Array.from(f.querySelectorAll('input,select,textarea')).map(e=>({name:e.name||'',type:e.type||'text',value:e.value||null,placeholder:e.placeholder||null,required:e.required}))})))")
        guard let d = r.data(using: .utf8) else { return [] }
        struct RF: Decodable { let action: String?; let method: String; let fields: [RFF] }
        struct RFF: Decodable { let name: String; let type: String; let value: String?; let placeholder: String?; let required: Bool }
        return ((try? JSONDecoder().decode([RF].self, from: d)) ?? []).map { f in PageForm(action: f.action, method: f.method, fields: f.fields.map { FormField(name: $0.name, type: $0.type, value: $0.value, placeholder: $0.placeholder, required: $0.required) }) }
    }
    public func querySelector(_ selector: String) async throws -> ElementInfo? {
        let r = try await evaluate(javascript: "(function(){var e=document.querySelector('\(esc(selector))');if(!e)return'null';var r=e.getBoundingClientRect();return JSON.stringify({tagName:e.tagName.toLowerCase(),id:e.id||null,className:e.className||null,text:e.innerText.substring(0,500),attributes:{},boundingBox:{x:r.x,y:r.y,width:r.width,height:r.height},isVisible:r.width>0&&r.height>0})})()")
        guard r != "null", let d = r.data(using: .utf8) else { return nil }
        struct RE: Decodable { let tagName: String; let id: String?; let className: String?; let text: String; let attributes: [String:String]; let boundingBox: BoundingBox; let isVisible: Bool }
        guard let raw = try? JSONDecoder().decode(RE.self, from: d) else { return nil }
        return ElementInfo(tagName: raw.tagName, id: raw.id, className: raw.className, text: raw.text, attributes: raw.attributes, boundingBox: raw.boundingBox, isVisible: raw.isVisible)
    }
    public func querySelectorAll(_ selector: String) async throws -> [ElementInfo] {
        let r = try await evaluate(javascript: "JSON.stringify(Array.from(document.querySelectorAll('\(esc(selector))')).slice(0,50).map(e=>{var r=e.getBoundingClientRect();return{tagName:e.tagName.toLowerCase(),id:e.id||null,className:e.className||null,text:e.innerText.substring(0,200),attributes:{},boundingBox:{x:r.x,y:r.y,width:r.width,height:r.height},isVisible:r.width>0&&r.height>0}}))")
        guard let d = r.data(using: .utf8) else { return [] }
        struct RE: Decodable { let tagName: String; let id: String?; let className: String?; let text: String; let attributes: [String:String]; let boundingBox: BoundingBox; let isVisible: Bool }
        return ((try? JSONDecoder().decode([RE].self, from: d)) ?? []).map { ElementInfo(tagName: $0.tagName, id: $0.id, className: $0.className, text: $0.text, attributes: $0.attributes, boundingBox: $0.boundingBox, isVisible: $0.isVisible) }
    }

    public func evaluate(javascript: String) async throws -> String {
        let r = try await connection.send(method: "Runtime.evaluate", params: ["expression": .string(javascript), "returnByValue": .bool(true)])
        if let err = r.result?["exceptionDetails"] { throw BrowserError.evaluationFailed("JS error: \(err)") }
        return r.result?["result"]?.stringValue ?? r.result?["value"]?.stringValue ?? ""
    }

    public func close() async throws { _isActive = false; await connection.disconnect() }
    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "\\'") }
}
