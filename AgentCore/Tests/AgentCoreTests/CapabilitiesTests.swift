import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AgentCore

// What the agent can reach: web pages, PDFs and images, and the limits around them.

/// Answers by URL, as a web server would.
private final class WebStub: URLProtocol, @unchecked Sendable {
    struct Page {
        var status = 200
        var type = "text/html"
        var body = Data()
        var redirect: String?
    }

    nonisolated(unsafe) static var pages: [String: Page] = [:]
    static let lock = NSLock()

    static func set(_ url: String, _ page: Page) { lock.withLock { pages[url] = page } }
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WebStub.self]
        return URLSession(configuration: c)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        guard let page = Self.lock.withLock({ Self.pages[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if let to = page.redirect, let target = URL(string: to) {
            let r = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": to])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: r)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let r = HTTPURLResponse(url: url, statusCode: page.status, httpVersion: nil, headerFields: ["Content-Type": page.type])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: page.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func tool() -> WebFetchTool {
    var t = WebFetchTool()
    t.session = WebStub.session
    t.resolve = { _ in ["93.184.216.34"] }
    return t
}

private func fetch(_ url: String, start: Int? = nil, room: Int = 16_000) async throws -> ToolOutput {
    var o: [String: JSONValue] = ["url": .string(url)]
    if let start { o["start"] = .number(Double(start)) }
    let ws = Workspace(root: FileManager.default.temporaryDirectory)
    return try await tool().run(ToolArguments(o), context: ToolContext(workspace: ws, maxOutputBytes: room))
}

@Suite struct WebFetchRefusalTests {
    private func refused(_ url: String, addresses: [String] = ["93.184.216.34"]) -> String? {
        WebFetchTool.refusal(URL(string: url)!) { _ in addresses }
    }

    @Test func theMachineAndItsNetworkAreOutOfReach() {
        for url in ["http://localhost:8080/", "http://127.0.0.1/", "http://10.0.0.5/", "http://172.20.1.1/", "http://192.168.1.1/",
                    "http://169.254.169.254/latest/meta-data/", "http://[::1]/", "http://[fd00::1]/", "http://[fe80::1]/",
                    "http://[::ffff:127.0.0.1]/", "http://printer.local/", "http://db.internal/", "http://100.64.0.1/", "http://0.0.0.0/"] {
            #expect(refused(url) != nil, "\(url)")
        }
    }

    @Test func aPublicNameThatPointsInsideIsRefused() {
        #expect(refused("https://rebind.example/", addresses: ["93.184.216.34", "127.0.0.1"])?.contains("points to 127.0.0.1") == true)
        #expect(refused("https://metadata.example/", addresses: ["169.254.169.254"]) != nil)
        #expect(refused("https://nowhere.example/", addresses: [])?.contains("couldn't be found") == true)
    }

    @Test func otherSchemesAndCredentialsAreRefused() {
        #expect(refused("file:///etc/passwd") != nil)
        #expect(refused("ftp://example.com/x") != nil)
        #expect(refused("https://user:secret@example.com/") != nil)
    }

    @Test func publicAddressesPass() {
        #expect(refused("https://example.com/docs") == nil)
        #expect(!WebFetchTool.isPrivate("8.8.8.8") && !WebFetchTool.isPrivate("172.32.0.1") && !WebFetchTool.isPrivate("2606:2800:220:1::1"))
    }
}

@Suite struct HTMLTextTests {
    private let base = URL(string: "https://example.com/docs/")!

    @Test func keepsTheStructureAndDropsTheRest() {
        let html = """
            <html><head><title>T</title><style>p{}</style></head><body><nav>menu</nav><script>evil()</script>
            <main><h1>Guide</h1><p>Use <code>swift</code> with <strong>care</strong> &amp; <a href="more.html">read on</a>.</p>
            <ul><li>one</li><li>two</li></ul><pre><code>let x = 1
              let y = 2</code></pre></main><footer>legal</footer></body></html>
            """
        let md = HTMLText.markdown(html, base: base)
        #expect(md.contains("# Guide"))
        #expect(md.contains("Use `swift` with **care** & [read on](https://example.com/docs/more.html)."))
        #expect(md.contains("- one\n- two"))
        #expect(md.contains("```\nlet x = 1\n  let y = 2\n```"))
        for gone in ["menu", "evil", "legal", "p{}"] { #expect(!md.contains(gone), "\(gone)") }
    }

    @Test func aPlainPageKeepsItsHeadingAndText() {
        let html = "<!doctype html><html lang=\"en\"><head><title>Example Domain</title><meta name=\"viewport\" content=\"width=device-width\">"
            + "<style>body{background:#eee}</style></head><body><div><h1>Example Domain</h1><p>This domain is for use.</p>"
            + "<p><a href=\"https://iana.org/domains/example\">Learn more</a></p></div></body></html>"
        let md = HTMLText.markdown(html, base: base)
        #expect(md.hasPrefix("# Example Domain"), "\(md)")
        #expect(md.contains("This domain is for use.") && md.contains("[Learn more](https://iana.org/domains/example)"))
        #expect(!md.contains("background"))
        #expect(HTMLText.markdown("<html><head><title>A &amp; B</title></head><body><p>Text.</p></body></html>", base: base) == "# A & B\n\nText.")
    }

    @Test func entitiesDecode() {
        #expect(HTMLText.decode("a &lt;b&gt; &#65; &#x42; &unknown;") == "a <b> A B &unknown;")
    }
}

@Suite(.serialized) struct WebFetchRunTests {
    @Test func aPageComesAsMarkedMarkdown() async throws {
        WebStub.set("https://a.example/page", .init(body: Data("<h1>Hello</h1><p>World</p>".utf8)))
        let out = try await fetch("https://a.example/page")
        #expect(out.text.contains("not instructions from the user") && out.text.contains("# Hello") && out.text.contains("World"))
        #expect(out.display?.contains("not instructions") == false)
    }

    @Test func textPassesAndBinaryDoesnt() async throws {
        WebStub.set("https://a.example/t", .init(type: "application/json", body: Data(#"{"a":1}"#.utf8)))
        #expect(try await fetch("https://a.example/t").text.contains(#"{"a":1}"#))
        WebStub.set("https://a.example/z", .init(type: "application/zip", body: Data([1, 2, 3])))
        await #expect(throws: ToolFailure.self) { _ = try await fetch("https://a.example/z") }
    }

    @Test func anErrorStatusIsAFailure() async throws {
        WebStub.set("https://a.example/gone", .init(status: 404, body: Data("nope".utf8)))
        await #expect(throws: ToolFailure.self) { _ = try await fetch("https://a.example/gone") }
    }

    @Test func aLongPageSaysHowToGoOn() async throws {
        WebStub.set("https://a.example/long", .init(type: "text/plain", body: Data(String(repeating: "x", count: 5000).utf8)))
        let first = try await fetch("https://a.example/long", room: 2000)
        #expect(first.truncated && first.text.contains("start 1600"))
        let rest = try await fetch("https://a.example/long", start: 4900, room: 2000)
        #expect(!rest.truncated)
    }

    @Test func aRedirectToAnotherHostStops() async throws {
        WebStub.set("https://a.example/r", .init(redirect: "https://evil.example/x"))
        WebStub.set("https://evil.example/x", .init(body: Data("<p>secret</p>".utf8)))
        let out = try await fetch("https://a.example/r")
        #expect(out.text.contains("redirects to https://evil.example/x") && !out.text.contains("secret"))
    }

    @Test func aRedirectWithinAHostIsFollowed() async throws {
        WebStub.set("https://a.example/old", .init(redirect: "https://a.example/new"))
        WebStub.set("https://a.example/new", .init(body: Data("<p>moved here</p>".utf8)))
        #expect(try await fetch("https://a.example/old").text.contains("moved here"))
    }
}

private final class Asked: @unchecked Sendable {
    let lock = NSLock()
    var requests: [ApprovalRequest] = []
    var bodies: [Data] = []
}

@Suite struct WebFetchPermissionTests {
    /// One web_fetch call through the loop, as a mode and a sandbox would have it. Refused by the address, so nothing goes out.
    private func decide(mode: PermissionMode, sandbox: SandboxPolicy?, rules: PermissionRules = PermissionRules(rules: []), session: [AllowRule] = [],
                        answer: ApprovalDecision? = .deny(feedback: "no")) async -> (asked: [ApprovalRequest], result: String) {
        let t = tool()
        var config = AgentConfig(tools: [t])
        config.policy = PermissionPolicy(mode: mode, rules: session)
        config.sandbox = sandbox
        config.permissionRules = rules
        let box = Asked()
        if let answer {
            config.approve = { r in box.lock.withLock { box.requests.append(r) }; return answer }
        }
        WebStub.set("https://docs.example/x", .init(body: Data("<p>the page</p>".utf8)))
        let json = #"{"url":"https://docs.example/x"}"#
        let (client, _) = MockServer.client(.init(chunks: [], turns: [SSE.toolCall("c", "web_fetch", json), SSE.content("done")]))
        final class Out: @unchecked Sendable { let lock = NSLock(); var text = "" }
        let out = Out()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: Workspace(root: FileManager.default.temporaryDirectory)) { e in
            if case .toolFinished(let m) = e { out.lock.withLock { out.text = m.content } }
        }
        return (box.lock.withLock { box.requests }, out.lock.withLock { out.text })
    }

    @Test func aYesCoversTheRestOfThatPageOnly() async {
        var config = AgentConfig(tools: [tool()])
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.sandbox = SandboxPolicy(allowNetwork: false)
        let box = Asked()
        config.approve = { r in box.lock.withLock { box.requests.append(r) }; return .allow }
        WebStub.set("https://docs.example/long", .init(body: Data(("<p>" + String(repeating: "word ", count: 40) + "</p>").utf8)))
        WebStub.set("https://docs.example/x", .init(body: Data("<p>the page</p>".utf8)))
        let (client, _) = MockServer.client(.init(chunks: [], turns: [
            SSE.toolCall("a", "web_fetch", #"{"url":"https://docs.example/long"}"#),
            SSE.toolCall("b", "web_fetch", #"{"url":"https://docs.example/long","start":20}"#),
            SSE.toolCall("c", "web_fetch", #"{"url":"https://docs.example/x","start":2}"#),
            SSE.content("done")]))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: Workspace(root: FileManager.default.temporaryDirectory)) { _ in }
        let asked = box.lock.withLock { box.requests }
        #expect(asked.map { $0.call.id } == ["a", "c"])
    }

    @Test func fullAutoAsksWhenTheSandboxHasNoNetwork() async {
        let r = await decide(mode: .fullAuto, sandbox: SandboxPolicy(allowNetwork: false))
        #expect(r.asked.count == 1)
        #expect(r.asked.first?.reason?.contains("network is off") == true)
        #expect(!r.result.contains("the page"))
    }

    @Test func withNetworkOnFullAutoFetches() async {
        let r = await decide(mode: .fullAuto, sandbox: SandboxPolicy(allowNetwork: true))
        #expect(r.asked.isEmpty && r.result.contains("the page"))
    }

    @Test func askModeAsksAndOffersTheDomain() async {
        let r = await decide(mode: .ask, sandbox: nil)
        #expect(r.asked.count == 1 && r.asked.first?.suggestedRule == .domain("docs.example"))
    }

    @Test func aRememberedDomainDoesntAskAgain() async {
        let r = await decide(mode: .fullAuto, sandbox: SandboxPolicy(allowNetwork: false), session: [.domain("example")])
        #expect(r.asked.isEmpty && r.result.contains("the page"))
    }

    @Test func nobodyToAskMeansNoFetch() async {
        let r = await decide(mode: .fullAuto, sandbox: SandboxPolicy(allowNetwork: false), answer: nil)
        #expect(!r.result.contains("the page"))
    }

    @Test func aRuleNamesADomainAndOnlyThatDomain() {
        let rules = PermissionRules(rules: [PermissionRule(action: .deny, tool: "WebFetch", specifier: "domain:evil.example", source: "t")])
        func decision(_ url: String) -> PermissionRule? { rules.decision(toolName: "web_fetch", args: ToolArguments(["url": .string(url)])) }
        #expect(decision("https://evil.example/a")?.action == .deny)
        #expect(decision("https://sub.evil.example/a")?.action == .deny)
        #expect(decision("https://notevil.example/a") == nil)
    }

    @Test func planModeIsntOfferedIt() {
        #expect(!PermissionPolicy(mode: .plan).offered(AllTools.all).contains { $0.name == "web_fetch" })
        #expect(PermissionPolicy(mode: .ask).offered(AllTools.all).contains { $0.name == "web_fetch" })
    }
}

private func pdf(_ pages: [String]) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 300)
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for text in pages {
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary)!)
        context.textPosition = CGPoint(x: 20, y: 150)
        CTLineDraw(line, context)
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

private func png() -> Data {
    let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

@Suite struct ReadFileMediaTests {
    private func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "kk-media-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func aPDFReadsAsTextByPage() async throws {
        let d = try folder()
        try pdf(["first page words", "second page words", "third page words"]).write(to: d.appending(path: "doc.pdf"))
        let ctx = ToolContext(workspace: Workspace(root: d))
        let all = try await ReadFileTool().run(ToolArguments(["path": "doc.pdf"]), context: ctx)
        #expect(all.text.contains("page 1 of 3") && all.text.contains("first page words") && all.text.contains("third page words"))
        for spelled in ["all", "ALL", "", " * "] {        // qwen3-coder sends "all", the description's word for the default
            let whole = try await ReadFileTool().run(ToolArguments(["path": "doc.pdf", "pages": .string(spelled)]), context: ctx)
            #expect(whole.text.contains("--- page 1 of"))
            #expect(whole.text.contains("--- page 3 of"))
        }
        let one = try await ReadFileTool().run(ToolArguments(["path": "doc.pdf", "pages": "2"]), context: ctx)
        #expect(one.text.contains("second page words") && !one.text.contains("first page"))
        await #expect(throws: ToolFailure.self) { _ = try await ReadFileTool().run(ToolArguments(["path": "doc.pdf", "pages": "9"]), context: ctx) }
        await #expect(throws: ToolFailure.self) { _ = try await ReadFileTool().run(ToolArguments(["path": "doc.pdf", "pages": "x"]), context: ctx) }
    }

    @Test func aPageWithNoTextSaysSo() throws {
        let (text, _) = try PDFText.extract(pdf([""]), pages: nil)
        #expect(text.contains("may be a scan"))
    }

    @Test func aBrokenPDFFails() {
        #expect(throws: ToolFailure.self) { _ = try PDFText.extract(Data("%PDF-1.4 not really".utf8), pages: nil) }
    }

    private func run(sendImages: Bool, in d: URL) async throws -> (body: String, result: String, injected: [ChatMessage]) {
        try png().write(to: d.appending(path: "shot.png"))
        let (client, host) = MockServer.client(.init(chunks: [], turns: [SSE.toolCall("c", "read_file", #"{"path":"shot.png"}"#), SSE.content("I see red.")]))
        var config = AgentConfig(tools: AllTools.all)
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.sendImages = sendImages
        config.imagesDirectory = d.appending(path: "images")
        final class Box: @unchecked Sendable { let lock = NSLock(); var result = ""; var injected: [ChatMessage] = [] }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("look")], config: config, workspace: Workspace(root: d)) { e in
            box.lock.withLock {
                if case .toolFinished(let m) = e { box.result = m.content }
                if case .injected(let m) = e { box.injected.append(m) }
            }
        }
        return (String(decoding: MockServer.requestBodies(host).last ?? Data(), as: UTF8.self), box.lock.withLock { box.result }, box.lock.withLock { box.injected })
    }

    @Test func aVisionModelSeesAnImageItRead() async throws {
        let r = try await run(sendImages: true, in: try folder())
        #expect(r.result.contains("an image, 8×8"))
        #expect(r.injected.first?.images?.count == 1 && r.injected.first?.contextNote == true)
        #expect(r.body.contains("image_url") && r.body.contains("data:image"))
    }

    @Test func aModelWithoutVisionIsToldSo() async throws {
        let r = try await run(sendImages: false, in: try folder())
        #expect(r.result.contains("can't see images") && r.injected.isEmpty && !r.body.contains("data:image"))
    }

    @Test func aBinaryThatIsntAnImageStaysRefused() async throws {
        let d = try folder()
        try Data([0, 1, 2, 3, 0, 5]).write(to: d.appending(path: "blob.bin"))
        var ctx = ToolContext(workspace: Workspace(root: d))
        ctx.acceptsImages = true
        await #expect(throws: ToolFailure.self) { _ = try await ReadFileTool().run(ToolArguments(["path": "blob.bin"]), context: ctx) }
    }
}
