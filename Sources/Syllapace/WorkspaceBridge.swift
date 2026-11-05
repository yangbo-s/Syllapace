import AppKit
import SyllapaceKit
import WebKit

/// Only bundled UI receives a bridge. External content is never loaded here.
final class WorkspaceBridge: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    private var snapshot: WorkspaceSnapshot
    private let state: WorkspaceWebViewState
    private let generation = UUID()
    private var onCommand: @MainActor (WorkspaceCommand) async -> WorkspaceResponse
    private weak var webView: WKWebView?
    private var indexURL: URL?
    private var webReady = false
    private var delivered: WorkspaceSnapshot?
    private var deliveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requests: Set<String> = []
    private var completedRequests: [String: (WorkspaceCommand, WorkspaceResponse)] = [:]
    private var completionOrder: [String] = []

    init(snapshot: WorkspaceSnapshot, state: WorkspaceWebViewState,
         onCommand: @escaping @MainActor (WorkspaceCommand) async -> WorkspaceResponse) {
        self.snapshot = snapshot; self.state = state; self.onCommand = onCommand
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        state.generation = generation; state.isReady = false; state.renderedRevision = nil
        state.renderedView = nil; state.renderedSnapshot = nil; state.failure = nil
        guard let resources = Bundle.main.resourceURL else { fail(missingResources); return }
        let directory = resources.appendingPathComponent("Workspace", isDirectory: true)
        let index = directory.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else { fail(missingResources); return }
        indexURL = index
        webView.loadFileURL(index, allowingReadAccessTo: directory)
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, !self.state.isReady else { return }
            self.fail(self.snapshot.language == "zh-Hans" ? "工作区加载超时。请重新加载。" : "The workspace took too long to load. Try reloading it.")
        }
    }

    func detach() {
        deliveryTask?.cancel(); deliveryTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        webReady = false; webView = nil
        if state.generation == generation { state.isReady = false; state.renderedRevision = nil; state.renderedView = nil; state.renderedSnapshot = nil }
    }

    func update(snapshot: WorkspaceSnapshot, onCommand: @escaping @MainActor (WorkspaceCommand) async -> WorkspaceResponse) {
        self.snapshot = snapshot; self.onCommand = onCommand
        deliver()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let frameURL = message.frameInfo.request.url, let indexURL,
              WorkspaceNavigation.isLocalDocument(frameURL, indexURL: indexURL),
              JSONSerialization.isValidJSONObject(message.body) else {
            replyHandler(nil, "Workspace request origin was rejected."); return
        }
        let request: WorkspaceRequest
        do { request = try WorkspaceRequest.decode(JSONSerialization.data(withJSONObject: message.body)) }
        catch { replyHandler(nil, error.localizedDescription); return }
        if let (command, cached) = completedRequests[request.id] {
            guard command == request.command else { replyHandler(nil, "Workspace request identifier was reused."); return }
            var response = cached
            if response.ok { response.snapshot = snapshot }
            reply(response, handler: replyHandler)
            return
        }
        guard requests.insert(request.id).inserted else { replyHandler(nil, "Workspace request is already running."); return }
        Task { [weak self] in
            guard let self, self.webView != nil else { replyHandler(nil, "Workspace is closed."); return }
            defer { self.requests.remove(request.id) }
            if request.command == .ready { self.webReady = true }
            var response = await self.onCommand(request.command)
            guard self.webView != nil else { replyHandler(nil, "Workspace is closed."); return }
            if let newSnapshot = response.snapshot { self.snapshot = newSnapshot }
            if response.ok { response.snapshot = self.snapshot }
            self.deliver()
            var cached = response
            cached.snapshot = nil
            self.completedRequests[request.id] = (request.command, cached)
            self.completionOrder.append(request.id)
            if self.completionOrder.count > 64 { self.completedRequests.removeValue(forKey: self.completionOrder.removeFirst()) }
            self.reply(response, handler: replyHandler)
        }
    }

    private func reply(_ response: WorkspaceResponse, handler: @escaping @MainActor (Any?, String?) -> Void) {
        do { handler(try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)), nil) }
        catch { handler(nil, "The workspace response could not be encoded.") }
    }

    private func deliver() {
        guard webReady, deliveryTask == nil, delivered != snapshot else { return }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.deliveryTask = nil }
            while !Task.isCancelled, let webView = self.webView, self.webReady, self.delivered != self.snapshot {
                let value = self.snapshot
                do {
                    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
                    // Values are arguments, never executable source text. receive resolves after rendering.
                    let acknowledgement = try await webView.callAsyncJavaScript("return await window.syllapace.receive(snapshot)",
                                                                               arguments: ["snapshot": object], in: nil, contentWorld: .page)
                    guard acknowledgement as? Bool == true else { throw WorkspaceContractError.invalidMessage }
                    guard !Task.isCancelled, self.state.generation == self.generation else { return }
                    self.delivered = value
                    self.state.isReady = true; self.state.failure = nil
                    self.state.renderedRevision = value.revision; self.state.renderedView = value.view
                    self.state.renderedSnapshot = value
                    self.timeoutTask?.cancel(); self.timeoutTask = nil
                } catch {
                    if !Task.isCancelled {
                        self.fail(self.snapshot.language == "zh-Hans" ? "工作区未能显示最新资料。请重新加载。" : "The workspace could not display the latest data. Try reloading it.")
                    }
                    return
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let indexURL else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == true, WorkspaceNavigation.isLocalDocument(url, indexURL: indexURL) {
            decisionHandler(.allow); return
        }
        if navigationAction.navigationType == .linkActivated, let external = WorkspaceNavigation.externalURL(url) {
            NSWorkspace.shared.open(external)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { navigationFailed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webReady = false
        fail(snapshot.language == "zh-Hans" ? "工作区已停止响应。请重新加载。" : "The workspace stopped responding. Try reloading it.")
    }
    private func navigationFailed(_ error: any Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        fail(snapshot.language == "zh-Hans" ? "工作区资源未能加载。请重新加载。" : "The workspace resources could not be loaded. Try reloading it.")
    }
    private func fail(_ message: String) {
        guard state.generation == generation else { return }
        state.failure = message; state.isReady = false
    }
    private var missingResources: String {
        snapshot.language == "zh-Hans" ? "此应用缺少工作区资源，请重新下载完整安装包。" : "Workspace resources are missing. Download the complete application again."
    }
}
