import Foundation
import Observation

@MainActor @Observable final class MarkupWorkspace {
    let tool: MarkupTool
    var input = "" { didSet { if !input.utf16.elementsEqual(oldValue.utf16) { invalidate(revokeExternal: true) } } }
    var options: MarkupOptions { didSet {
        if let data=try? JSONEncoder().encode(options) { defaults.set(data,forKey:key) }
        var a=oldValue,b=options;a.wrap=b.wrap;a.live=b.live;a.viewport=b.viewport
        if a != b { invalidate() }
        else if options.live && !oldValue.live && tool.isPreview { schedule() }
    } }
    private(set) var allowsExternalResources = false
    func setExternalResourcesAllowed(_ allowed: Bool) {
        guard tool.isPreview else { return }
        allowsExternalResources = allowed
        run()
    }
    var collapsed = false
    private(set) var result: MarkupResult?
    private(set) var snapshot: MarkupPreviewSnapshot?
    private(set) var busy = false
    private(set) var status = "Ready"
    private(set) var output = ""
    private(set) var sizeSummary = ""
    private(set) var revision = UUID()
    private(set) var imageMappings: [String:MarkupImage] = [:]
    var jumpTarget: NSRange?
    var jump = 0
    var showDetails = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var debounce: Task<Void,Never>?
    @ObservationIgnored private var cancellation: MarkupCancellation?
    @ObservationIgnored private var visible = false
    @ObservationIgnored var inputIsComposing: (() -> Bool)?
    init(_ tool: MarkupTool, defaults: UserDefaults = .standard) {
        self.tool=tool;self.defaults=defaults;key="codeMarkup.preferences."+tool.rawValue
        options=defaults.data(forKey:key).flatMap { try? JSONDecoder().decode(MarkupOptions.self,from:$0) } ?? .init()
        if ![2,4].contains(options.indent) { options.indent=2 }
        if !MarkupOptions.dialects.contains(options.dialect) { options.dialect="sql" }
        if options.viewport != 0 && !(280...1920).contains(options.viewport) { options.viewport=0 }
    }
    deinit { task?.cancel();debounce?.cancel();cancellation?.cancel() }
    var exportText: String { tool == .markdown ? snapshot?.exportHTML ?? "" : output }
    var canCopy: Bool { result?.succeeded == true && !exportText.isEmpty && exportText.utf8.count <= 4*1024*1024 }
    func appeared() { visible=true;if tool.isPreview && result == nil { schedule() } }
    func disappeared() { visible=false;debounce?.cancel();cancel(quiet:true) }
    private func invalidate(revokeExternal: Bool = false) {
        if revokeExternal { allowsExternalResources = false }
        revision=UUID();task?.cancel();cancellation?.cancel();debounce?.cancel()
        result=nil;output="";sizeSummary="";busy=false;jumpTarget=nil;status=input.isEmpty ? "Ready" : "Not checked"
        if input.isEmpty { snapshot=nil;imageMappings.removeAll() }
        if tool.isPreview { schedule() }
    }
    private func schedule() {
        guard visible,options.live,!input.isEmpty else { return }
        let rev=revision;debounce?.cancel()
        debounce=Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(350)) } catch {return}
            guard let self,self.revision==rev else{return}
            while self.inputIsComposing?() == true {
                do {try await Task.sleep(for:.milliseconds(100))} catch {return}
                guard self.visible,self.revision==rev else{return}
            }
            self.run()
        }
    }
    func pasted(automatic: Bool) { if tool.isPreview && options.live {run()} else if tool.canValidate && automatic {run("validate")} }
    func cancel(quiet: Bool = false) {
        revision=UUID();task?.cancel();cancellation?.cancel();debounce?.cancel();busy=false
        if !quiet { status="Cancelled" }
    }
    func run(_ operation: String? = nil) {
        guard inputIsComposing?() != true else {return}
        debounce?.cancel();task?.cancel();cancellation?.cancel();revision=UUID()
        let rev=revision,source=input,op=operation ?? (tool.isPreview ? "render" : "format")
        let request=MarkupRequest(tool:tool,source:source,operation:op,options:options,allowsExternalResources:allowsExternalResources)
        let token=MarkupCancellation();cancellation=token;busy=true;status="Processing"
        let mappings=imageMappings
        task=Task { [weak self] in
            let r=await MarkupProcessor.process(request,cancellation:token)
            var notices=r.notices
            var prepared: MarkupPreviewSnapshot?
            if let html=r.preview {
                let images=await Task.detached { () -> [String:Data] in
                    var images:[String:Data]=[:],pixels=0,bytes=0
                    for ref in r.images ?? [] {
                        if Task.isCancelled {break}
                        let image=mappings[ref.reference] ?? MarkupImage.dataURI(ref.reference).flatMap { try? MarkupImage.decode($0) }
                        if let image, pixels+image.pixels<=24_000_000,bytes+image.png.count<=16*1024*1024 {
                            images[ref.id]=image.png;pixels+=image.pixels;bytes+=image.png.count
                        }
                    };return images
                }.value
                if images.count < (r.images?.count ?? 0) { notices.append("\((r.images?.count ?? 0)-images.count) external or unavailable image(s) blocked. Use Preview Images to map a local raster file. GIF previews use the first frame.") }
                var stableHTML=html
                for ref in r.images ?? [] where images[ref.id] == nil {
                    stableHTML=stableHTML.replacingOccurrences(of:" src=\"toolbox-preview://\(request.nonce)/\(ref.id)\"",with:" data-toolbox-blocked=\"true\"")
                }
                prepared = .init(nonce:request.nonce,html:stableHTML,images:images,allowsExternalResources:request.allowsExternalResources)
            }
            guard let self,self.revision==rev,!Task.isCancelled else{return}
            self.busy=false;var value=r;value.notices=notices;self.result=value;self.status=r.label
            if r.succeeded && self.tool.isPreview && prepared == nil {self.status="Preview unavailable · see details"}
            if r.succeeded {
                if let output=r.output {self.output=self.tool == .markdown ? prepared?.exportHTML ?? "" : output;self.sizeSummary="\(source.utf8.count) → \(self.output.utf8.count) bytes"}
                if op != "validate" {self.snapshot=prepared}
                if !self.tool.isPreview && op != "validate" && self.output.utf16.elementsEqual(source.utf16) {self.status=op == "minify" ? "No safe size reduction" : "Already formatted"}
                if self.tool.canValidate && op=="validate" {self.status=r.diagnostics.isEmpty ? "Valid \(self.tool.rawValue.uppercased())" : "Valid with warnings"}
            }else if r.status != "cancelled" {self.output="";self.sizeSummary="";self.snapshot=nil}
        }
    }
    func show(_ diagnostic: MarkupDiagnostic) { jumpTarget=diagnostic.range(in:input);jump += 1;collapsed=false }
    func mapImage(reference: String, image: MarkupImage) -> Bool {
        let others=imageMappings.filter{$0.key != reference}
        guard others.count<16,others.values.reduce(0,{$0+$1.png.count})+image.png.count<=16*1024*1024,
              others.values.reduce(0,{$0+$1.pixels})+image.pixels<=24_000_000 else{return false}
        imageMappings[reference]=image;run();return true
    }
    func removeImage(_ reference: String) {imageMappings.removeValue(forKey:reference);run()}
}
