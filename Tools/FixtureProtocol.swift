import Foundation

func webFixtureURL(_ name: String) -> URL {
    let root = URL(fileURLWithPath: name)
    return FileManager.default.fileExists(atPath: root.path) ? root : URL(fileURLWithPath: "WebCatalog/" + name)
}

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { ["swcdn.apple.com", "api.ipsw.me", "raw.githubusercontent.com"].contains(request.url?.host ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if path == "/redirect.dmg" {
                let response = HTTPURLResponse(url: self.request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://untrusted.invalid/file.dmg"])!
                self.client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://untrusted.invalid/file.dmg")!), redirectResponse: response)
                return
            }
            var body = Data((path == "/html.dmg" ? "<html>not an installer</html>" : "MacDownUp fixture\n").utf8)
            if self.request.url?.host == "raw.githubusercontent.com" {
                body = try! Data(contentsOf: webFixtureURL("catalog.json"))
                if path.hasSuffix("future.json") || path.hasSuffix("invalid.json") {
                    var document = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
                    if path.hasSuffix("invalid.json") { document["schemaVersion"] = 99 }
                    else {
                        var releases = document["releases"] as! [[String: Any]]
                        var next = releases[0]
                        next["id"] = "99"; next["number"] = "99"; next["marketingName"] = "Future Fixture"
                        next["finalVersion"] = "99.1"; next["year"] = 2098
                        releases.insert(next, at: 0); document["releases"] = releases; document["revision"] = 2
                    }
                    body = try! JSONSerialization.data(withJSONObject: document)
                }
            }
            if self.request.url?.host == "api.ipsw.me" {
                if path == "/v4/devices" {
                    body = Data(#"[{"name":"MacBook Air (M1)","identifier":"MacBookAir10,1"},{"name":"iPhone","identifier":"iPhone1,1"},{"name":"iMac (M1)","identifier":"iMac21,1"}]"#.utf8)
                } else {
                    let identifier = self.request.url!.lastPathComponent
                    let digest = identifier == "Mac99,2" ? String(repeating: "0", count: 40) : "38b0643c2c5381c4f95e0b31ff520b8498ed8ca2"
                    let sha256 = identifier == "Mac99,2" ? String(repeating: "0", count: 64) : "d3fbf44ee2765d2a4895306b787e1ba668030e8b85c6e083aeaa8b0d971438aa"
                    let firmware: [String: Any] = ["version": "27.2.1", "buildid": "26B131", "url": "https://swcdn.apple.com/file.ipsw", "filesize": identifier == "Mac99,3" ? 100 : 18, "signed": identifier != "Mac99,1", "sha1sum": digest, "sha256sum": sha256]
                    body = try! JSONSerialization.data(withJSONObject: ["identifier": identifier == "Mac99,4" ? "MacOther1,1" : identifier, "firmwares": [firmware]])
                }
            }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: path == "/missing.dmg" || path.hasSuffix("missing.json") ? 404 : 200,
                                            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": self.request.url?.host == "api.ipsw.me" ? "application/json" : path == "/html.dmg" ? "text/html" : "application/octet-stream", "Content-Length": String(body.count)])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        work = item
        DispatchQueue.global().asyncAfter(deadline: .now() + (path == "/slow.dmg" ? 1 : 0.01), execute: item)
    }
    override func stopLoading() { work?.cancel() }
}
