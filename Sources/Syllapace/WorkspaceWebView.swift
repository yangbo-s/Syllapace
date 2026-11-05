import AppKit
import Observation
import SwiftUI
import SyllapaceKit
import WebKit

@Observable final class WorkspaceWebViewState {
    static let shared = WorkspaceWebViewState()
    var isReady = false
    var renderedRevision: Int?
    var renderedView: WorkspaceViewMode?
    var renderedSnapshot: WorkspaceSnapshot?
    var failure: String?
    var generation = UUID()

    func matches(_ snapshot: WorkspaceSnapshot) -> Bool {
        guard isReady, var rendered = renderedSnapshot else { return false }
        // Capturing a screen takes time; the clock alone does not invalidate its data.
        rendered.now = snapshot.now
        return rendered == snapshot
    }
}

struct WorkspaceWebView: View {
    let snapshot: WorkspaceSnapshot
    let onCommand: @MainActor (WorkspaceCommand) async -> WorkspaceResponse
    @State private var state = WorkspaceWebViewState.shared
    @State private var reloadID = UUID()

    var body: some View {
        ZStack {
            WorkspaceRepresentable(snapshot: snapshot, state: state, onCommand: onCommand).id(reloadID)
            if let failure = state.failure {
                ContentUnavailableView {
                    Label(snapshot.language == "zh-Hans" ? "工作区未能打开" : "Could not open workspace", systemImage: "rectangle.slash")
                } description: {
                    Text(failure)
                } actions: {
                    Button(snapshot.language == "zh-Hans" ? "重新加载" : "Reload") { reloadID = UUID() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
            } else if !state.isReady {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

private struct WorkspaceRepresentable: NSViewRepresentable {
    let snapshot: WorkspaceSnapshot
    let state: WorkspaceWebViewState
    let onCommand: @MainActor (WorkspaceCommand) async -> WorkspaceResponse

    func makeCoordinator() -> WorkspaceBridge { WorkspaceBridge(snapshot: snapshot, state: state, onCommand: onCommand) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "workspace")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.setAccessibilityLabel(snapshot.language == "zh-Hans" ? "课程工作区" : "Course workspace")
        context.coordinator.attach(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.setAccessibilityLabel(snapshot.language == "zh-Hans" ? "课程工作区" : "Course workspace")
        context.coordinator.update(snapshot: snapshot, onCommand: onCommand)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: WorkspaceBridge) {
        coordinator.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "workspace", contentWorld: .page)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }
}
