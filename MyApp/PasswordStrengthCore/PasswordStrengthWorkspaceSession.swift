import Foundation
import Observation

@MainActor @Observable final class PasswordStrengthWorkspaceSession {
    var password = "" { didSet { if !password.utf16.elementsEqual(oldValue.utf16) { changed() } } }
    var personalWords = "" { didSet { if !personalWords.utf16.elementsEqual(oldValue.utf16) { changed() } } }
    var revealed = false
    var hidden = false
    var autoEstimate: Bool { didSet { defaults.set(autoEstimate,forKey:Self.key); if autoEstimate { schedule() } } }
    private(set) var result: PasswordStrengthResult?
    private(set) var busy = false
    var rejection: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let worker: PasswordStrengthWorker
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var pending: PasswordStrengthRequest?
    @ObservationIgnored private var pipeline: Task<Void,Never>?
    @ObservationIgnored private var debounce: Task<Void,Never>?
    private static let key = "developerToolbox.passwordStrength.autoEstimate"
    init(defaults: UserDefaults? = nil, worker: PasswordStrengthWorker = .init()) {
        self.defaults = defaults ?? (ProcessInfo.processInfo.arguments.contains("--navigation-ui-tests") ? UserDefaults(suiteName:"developerToolbox.navigation.ui-tests")! : .standard)
        autoEstimate = self.defaults.object(forKey:Self.key) as? Bool ?? true; self.worker = worker
    }
    deinit { debounce?.cancel(); pipeline?.cancel() }
    private func changed() { revision = UUID(); result = nil; pending = nil; busy = false; rejection = nil; debounce?.cancel(); if autoEstimate && !password.isEmpty { schedule() } }
    private func schedule() {
        debounce?.cancel(); debounce = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(200)) } catch { return }
            self?.estimate()
        }
    }
    func pasted() { if autoEstimate { estimate() } }
    @discardableResult func estimate() -> Task<Void,Never> {
        debounce?.cancel(); pending = .init(password:password,personalWords:personalWords,revision:revision); busy = true
        if let pipeline { return pipeline }
        let task = Task { [weak self] in
            while let request = self?.takePending() {
                guard let worker = self?.worker else { return }
                let result = await worker.estimate(request)
                if let self, self.revision == request.revision { self.result = result; self.busy = false }
            }
            self?.pipeline = nil
        }
        pipeline = task; return task
    }
    private func takePending() -> PasswordStrengthRequest? { defer { pending = nil }; return pending }
    func clear() { debounce?.cancel(); password = ""; personalWords = ""; pending = nil; revision = UUID(); result = nil; busy = false; rejection = nil; revealed = false; hidden = false; worker.reset() }
    func accept(_ text: String) -> Bool {
        if text.utf16.prefix(4097).count > 4096 { rejection = "Input rejected: maximum 4,096 UTF-16 units. Previous value is unchanged."; return false }
        if text.unicodeScalars.contains(where: { [0,9,10,13].contains($0.value) }) { rejection = "Input rejected: use a single line without tab or NUL. Previous value is unchanged."; return false }
        return true
    }
}
