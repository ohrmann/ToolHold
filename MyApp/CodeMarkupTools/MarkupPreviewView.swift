import SwiftUI
import WebKit

/// A static renderer, never an editor or a general-purpose browser.
@MainActor struct MarkupPreviewView {
    let snapshot: MarkupPreviewSnapshot
    var dark = false
    var markdown = false
    var allowsExternalResources = false
    @Binding var failure: String?
    func makeCoordinator() -> MarkupPreviewCoordinator { .init(failure: $failure, allowsExternalResources: allowsExternalResources) }
    func make(_ coordinator: MarkupPreviewCoordinator) -> WKWebView {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript=false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically=false
        configuration.setURLSchemeHandler(coordinator,forURLScheme:"toolbox-preview")
        let view=WKWebView(frame:.zero,configuration:configuration)
        view.navigationDelegate=coordinator;view.uiDelegate=coordinator
        #if os(macOS)
        view.allowsMagnification=true
        #else
        view.scrollView.showsHorizontalScrollIndicator=true
        view.scrollView.showsVerticalScrollIndicator=true
        #endif
        coordinator.view=view
        coordinator.prepare()
        return view
    }
    func update(_ coordinator: MarkupPreviewCoordinator) {
        coordinator.failure=$failure
        coordinator.update(snapshot,dark:dark,markdown:markdown)
    }
}
#if os(macOS)
extension MarkupPreviewView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {make(context.coordinator)}
    func updateNSView(_ view: WKWebView,context: Context) {update(context.coordinator)}
    static func dismantleNSView(_ view: WKWebView,coordinator: MarkupPreviewCoordinator) {coordinator.stop()}
}
#else
extension MarkupPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {make(context.coordinator)}
    func updateUIView(_ view: WKWebView,context: Context) {update(context.coordinator)}
    static func dismantleUIView(_ view: WKWebView,coordinator: MarkupPreviewCoordinator) {coordinator.stop()}
}
#endif

@MainActor final class MarkupPreviewCoordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate {
    weak var view: WKWebView?
    var failure: Binding<String?>
    private var snapshot: MarkupPreviewSnapshot?
    private var loadingSnapshot: MarkupPreviewSnapshot?
    private let allowsExternalResources: Bool
    private var ready=false,loaded=false,loading=false
    private var renderedNonce:String?
    private var sequence=0
    private var dark=false,markdown=false
    init(failure: Binding<String?>, allowsExternalResources: Bool = false) {self.failure=failure;self.allowsExternalResources=allowsExternalResources}
    func stop() {view?.stopLoading();view?.navigationDelegate=nil;view?.uiDelegate=nil;view=nil;sequence += 1;loadingSnapshot=nil;snapshot=nil}
    func prepare() {
        // Static rules contain no working text and are installed before the first document load.
        let remoteRule=allowsExternalResources ? #",{"trigger":{"url-filter":"^https://","resource-type":["image","style-sheet","font"]},"action":{"type":"ignore-previous-rules"}}"# : ""
        let rules=#"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^toolbox-preview://"},"action":{"type":"ignore-previous-rules"}}"# + remoteRule + "]"
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier:allowsExternalResources ? "ToolboxStaticPreview-https-v2" : "ToolboxStaticPreview-v2",encodedContentRuleList:rules) { [weak self] list,error in
            guard let self,self.view != nil else{return}
            guard let list,error == nil else{self.failure.wrappedValue="Preview security rules are unavailable. Content was not loaded.";return}
            self.view?.configuration.userContentController.add(list);self.ready=true;self.render()
        }
    }
    func update(_ snapshot: MarkupPreviewSnapshot,dark: Bool,markdown: Bool) {
        let appearanceChanged=self.dark != dark || self.markdown != markdown
        self.snapshot=snapshot;self.dark=dark;self.markdown=markdown
        if renderedNonce != snapshot.nonce {render()}
        else if appearanceChanged {applyTheme()}
    }
    private func render() {
        guard ready,let snapshot,let view else{return}
        if !loaded {
            guard !loading else{return};loading=true;loadingSnapshot=snapshot
            view.load(URLRequest(url:URL(string:"toolbox-preview://\(snapshot.nonce)/document")!));return
        }
        guard renderedNonce != snapshot.nonce else{return}
        renderedNonce=snapshot.nonce;sequence += 1;let seq=sequence
        // App-owned constant script, isolated world. Markup is data; page scripts remain disabled.
        let script="""
        if ((globalThis.toolboxSequence || 0) >= sequence) return;
        globalThis.toolboxSequence = sequence;
        const x = scrollX, y = scrollY;
        const parsed = new DOMParser().parseFromString(markup, 'text/html');
        document.documentElement.replaceChildren(document.importNode(parsed.head,true),document.importNode(parsed.body,true));
        for(const a of Array.from(document.documentElement.attributes)) document.documentElement.removeAttribute(a.name);
        for(const a of Array.from(parsed.documentElement.attributes)) document.documentElement.setAttribute(a.name,a.value);
        scrollTo(x,y);
        """
        view.callAsyncJavaScript(script,arguments:["markup":snapshot.html,"sequence":seq],in:nil,in:.defaultClient) { [weak self] result in
            guard let self,self.sequence==seq else{return}
            if case .failure = result {self.failure.wrappedValue="Preview update failed. Use Render to retry.";self.renderedNonce=nil}
            else {self.failure.wrappedValue=nil;self.applyTheme()}
        }
    }
    private func applyTheme() {
        guard markdown else{return}
        view?.callAsyncJavaScript("document.documentElement.style.colorScheme = scheme;",arguments:["scheme":dark ? "dark" : "light"],in:nil,in:.defaultClient,completionHandler:nil)
    }
    func webView(_ webView: WKWebView,start urlSchemeTask: any WKURLSchemeTask) {
        guard let url=urlSchemeTask.request.url,
              let snapshot = url.host == snapshot?.nonce ? snapshot : (url.path == "/document" && url.host == loadingSnapshot?.nonce ? loadingSnapshot : nil),
              url.scheme=="toolbox-preview",url.host==snapshot.nonce,
              url.query==nil,url.fragment==nil,url.user==nil,url.password==nil,url.port==nil,
              url.absoluteString=="toolbox-preview://\(snapshot.nonce)\(url.path)" else {urlSchemeTask.didFailWithError(URLError(.resourceUnavailable));return}
        let data:Data,mime:String
        if url.path=="/document" {data=Data(snapshot.html.utf8);mime="text/html"}
        else if let image=snapshot.images[String(url.path.dropFirst())] {data=image;mime="image/png"}
        else {urlSchemeTask.didFailWithError(URLError(.resourceUnavailable));return}
        urlSchemeTask.didReceive(URLResponse(url:url,mimeType:mime,expectedContentLength:data.count,textEncodingName:mime=="text/html" ? "utf-8" : nil))
        urlSchemeTask.didReceive(data);urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView,stop urlSchemeTask: any WKURLSchemeTask) {}
    func webView(_ webView: WKWebView,decidePolicyFor navigationAction: WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url,let snapshot,navigationAction.targetFrame?.isMainFrame==true,
              url.scheme=="toolbox-preview",url.path=="/document",(url.host==snapshot.nonce || url.host==loadingSnapshot?.nonce || url.fragment != nil && url.host==webView.url?.host) else{decisionHandler(.cancel);return}
        decisionHandler(navigationAction.navigationType == .other || url.fragment != nil ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) {
        loaded=true;loading=false;loadingSnapshot=nil;renderedNonce=nil;render()
    }
    func webView(_ webView: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error: Error) {loading=false;failure.wrappedValue="Static preview could not load. Use Render to retry."}
    func webView(_ webView: WKWebView,didFail navigation: WKNavigation!,withError error: Error) {loading=false;loaded=false;renderedNonce=nil;failure.wrappedValue="Static preview could not load. Use Retry Preview."}
    func webView(_ webView: WKWebView,didReceive challenge: URLAuthenticationChallenge,completionHandler:@escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        // Keep normal TLS validation; never prompt for credentials or use account authentication.
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge,nil)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {loaded=false;loading=false;renderedNonce=nil;failure.wrappedValue="Preview process ended. Input is preserved; use Render to retry."}
    func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for navigationAction: WKNavigationAction,windowFeatures: WKWindowFeatures) -> WKWebView? {nil}
    func webView(_ webView: WKWebView,requestMediaCapturePermissionFor origin: WKSecurityOrigin,initiatedByFrame frame: WKFrameInfo,type: WKMediaCaptureType,decisionHandler:@escaping(WKPermissionDecision)->Void) {decisionHandler(.deny)}
}
