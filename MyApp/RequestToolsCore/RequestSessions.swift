import Foundation
import Observation
@MainActor @Observable public final class CurlWorkspace {
    public var input=""{didSet{if !input.utf16.elementsEqual(oldValue.utf16){invalidate()}}}
    public var language:RequestLanguage = .swift {didSet{defaults.set(language.rawValue,forKey:"curl.target");invalidate()}}
    public var includeSecrets=false{didSet{invalidate()}}
    public var masked=true
    public private(set) var result:GeneratedRequest?
    public private(set) var request:HTTPRequestSpec?
    public private(set) var status="Ready"
    public private(set) var busy=false
    public private(set) var issue:RequestIssue?
    private var revision=0
    @ObservationIgnored private var task:Task<Void,Never>?
    private let defaults:UserDefaults
    public init(defaults:UserDefaults = .standard){self.defaults=defaults;language=RequestLanguage(rawValue:defaults.string(forKey:"curl.target") ?? "") ?? .swift}
    private func invalidate(){revision+=1;task?.cancel();busy=false;result=nil;request=nil;issue=nil;status="Not processed"}
    public func cancel(){revision+=1;task?.cancel();busy=false;status="Cancelled"}
    public func run(){revision+=1;let rev=revision,source=input,target=language,secrets=includeSecrets;task?.cancel();busy=true;status="Processing…";issue=nil
        task=Task{let worker=Task.detached{let r=try CurlProcessor.parse(source);return (r,Result{try RequestEmitters.generate(r,language:target,includeSecrets:secrets)})}
            do{let (r,value)=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard rev==revision,!Task.isCancelled else{return};request=r;busy=false
                switch value{case .success(let generated):result=generated;status=generated.needsValues ? "Needs values":"Completed";case .failure(let error):result=nil;issue=error as? RequestIssue;status=issue?.message ?? "Generation failed"}
            }catch{guard rev==revision else{return};busy=false;result=nil;issue=error as? RequestIssue;status=issue?.message ?? "Cancelled"}
        }
    }
}
@MainActor @Observable public final class ConnectionWorkspace {
    public var input=""{didSet{if !input.utf16.elementsEqual(oldValue.utf16){invalidate()}}}
    public var profile:ConnectionProfile = .automatic{didSet{if profile != oldValue{defaults.set(profile.rawValue,forKey:"connection.profile");invalidate()}}}
    public var masked=true
    public var search=""
    public var hideAllValues=false
    public private(set) var document:ConnectionDocument?
    public private(set) var status="Ready"
    public private(set) var busy=false
    public private(set) var issue:RequestIssue?
    private var revision=0
    @ObservationIgnored private var task:Task<Void,Never>?
    private let defaults:UserDefaults
    public init(defaults:UserDefaults = .standard){self.defaults=defaults;profile=ConnectionProfile(rawValue:defaults.string(forKey:"connection.profile") ?? "") ?? .automatic}
    private func invalidate(){revision+=1;task?.cancel();busy=false;document=nil;issue=nil;status="Not processed"}
    public func cancel(){revision+=1;task?.cancel();busy=false;status="Cancelled"}
    public func run(){revision+=1;let rev=revision,source=input,profile=profile;task?.cancel();busy=true;status="Processing…";issue=nil
        task=Task{let worker=Task.detached{try ConnectionProcessor.parse(source,profile:profile)};do{let value=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard rev==revision,!Task.isCancelled else{return};document=value;busy=false;status="Completed"}catch{guard rev==revision else{return};busy=false;issue=error as? RequestIssue;status=issue?.message ?? "Cancelled"}}
    }
    public func apply(id:Int,value:String){guard let document else{return};revision+=1;let rev=revision;task?.cancel();busy=true;status="Applying…"
        task=Task{let worker=Task.detached{try document.editing(id,value:value)};do{let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard revision==rev,!Task.isCancelled else{return};input=result.source;self.document=result;busy=false;status="Completed"}catch{guard revision==rev else{return};busy=false;status=(error as? RequestIssue)?.message ?? "Invalid edited value"}}
    }
}
