import AppKit
import AltForMacCore
import AltForMacKit

/// Wires key capture, the KeyTip state machine, the command runner and the HUD together.
/// One mappings file and one state machine per Office app (Excel, Word, PowerPoint); the one for the
/// frontmost app is the "current context".
///
/// Threading: the state machine, `executing` and the timers live on the INPUT THREAD (the event tap's
/// thread), so a key is classified, swallowed and counted without waiting for the main thread.
/// Drawing happens on the main thread; commands run on `runQueue`.
final class AppController {
    private struct Context {
        let app: OfficeApp
        let mappings: [Mapping]
        let trie: SequenceTrie<Mapping>
        let machine: KeyTipStateMachine<Mapping>
    }

    private let capture = KeyCapture()
    private let overlay = Overlay()
    private let runner = CommandRunner()
    private let runQueue = DispatchQueue(label: "altformac.run", qos: .userInitiated)
    /// Window-geometry lookups get their own queue so they can never delay a command.
    private let anchorQueue = DispatchQueue(label: "altformac.anchor", qos: .utility)

    /// Built once before the tap starts, read-only afterwards.
    private var contexts: [String: Context] = [:]

    // Input-thread state. Always describes the app that is currently in front (or nothing).
    private var app: OfficeApp?
    private var mappings: [Mapping] = []
    private var trie = SequenceTrie<Mapping>()
    private var machine = KeyTipStateMachine<Mapping>(trie: SequenceTrie<Mapping>())
    private var executing = false
    private var runToken = 0
    private var idleTimer: Timer?
    private var commitTimer: Timer?
    private var optionReleasedAt: DispatchTime?

    var onStatus: ((Status) -> Void)?
    enum Status { case ready, needsPermission, appSlow }

    func start() {
        loadMappings()
        overlay.prewarm()
        capture.handler = { [weak self] input in self?.handle(input) ?? false }
        installTapWhenPermitted()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let front = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontAppChanged(OfficeApp.from(bundleID: front?.bundleIdentifier))
        }
        frontAppChanged(OfficeApp.frontmost)
    }

    // MARK: setup

    private func loadMappings() {
        for office in OfficeApp.all {
            do {
                let url = try Self.findMappingsFile(stem: office.stem)
                let yaml = try String(contentsOf: url, encoding: .utf8)
                let list = try MappingLoader.load(yaml: yaml)
                let trie = MappingLoader.buildTrie(list)
                contexts[office.bundleID] = Context(app: office, mappings: list, trie: trie,
                                                    machine: KeyTipStateMachine(trie: trie))
                runner.precompile(list)
                log("\(office.displayName): loaded \(list.count) mappings from \(url.path)")
            } catch {
                log("\(office.displayName): no mappings loaded (\(error))")
            }
        }
    }

    /// Release: the .app carries its mappings in Contents/Resources. Dev: ALTFORMAC_MAPPINGS_DIR, then
    /// walk up from the working directory and the binary to find `mappings/<stem>.yaml`.
    static func findMappingsFile(stem: String = "excel") throws -> URL {
        if let dir = ProcessInfo.processInfo.environment["ALTFORMAC_MAPPINGS_DIR"] {
            return URL(fileURLWithPath: dir).appendingPathComponent("\(stem).yaml")
        }
        if let bundled = Bundle.main.url(forResource: stem, withExtension: "yaml"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        var starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        if let exe = Bundle.main.executableURL { starts.append(exe.deletingLastPathComponent()) }
        for start in starts {
            var dir = start
            for _ in 0..<8 {
                let candidate = dir.appendingPathComponent("mappings/\(stem).yaml")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                dir.deleteLastPathComponent()
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func installTapWhenPermitted() {
        if capture.install() {
            onStatus?(.ready)
            frontAppChanged(OfficeApp.frontmost)
            return
        }
        onStatus?(.needsPermission)
        AXPermission.requestPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installTapWhenPermitted() }
    }

    /// Main thread. `office` is nil when any other app is in front: the tap is then off completely.
    private func frontAppChanged(_ office: OfficeApp?) {
        let context = office.flatMap { contexts[$0.bundleID] }
        capture.setActive(context != nil)
        if let office, context != nil {
            refreshAnchor(office)
            warmUp(office)
        }
        capture.perform { [weak self] in
            guard let self else { return }
            self.cancelTimers()
            self.route(self.machine.handle(.cancel))
            self.switchContext(context)
        }
    }

    /// Input thread.
    private func switchContext(_ context: Context?) {
        app = context?.app
        mappings = context?.mappings ?? []
        trie = context?.trie ?? SequenceTrie<Mapping>()
        machine = context?.machine ?? KeyTipStateMachine(trie: trie)
    }

    // MARK: input (input thread)

    /// Runs inside the event-tap callback on the input thread: classify, update state, defer all drawing.
    private func handle(_ input: RawInput) -> Bool {
        if executing {
            // Keyboard stays blocked until the executor returns (max 1 s, see watchdog).
            switch input {
            case .key, .escape, .backspace: return true
            default: return false
            }
        }
        cancelTimers()

        let wasActive = machine.isActive
        var action: KeyTipAction<Mapping>
        var swallow = false

        switch input {
        case .optionTap:
            // Second line of defense next to the tap being disabled outside Office apps: never start (or
            // toggle) a KeyTip sequence unless the app we hold mappings for really is frontmost right now.
            guard let app, app.isFrontmost else { return false }
            optionReleasedAt = .now()
            action = machine.handle(.optionTap)
        case .key(let ch, let optionHeld):
            if wasActive {
                // Option may still be held while the user types fast: ignore it, it is still a KeyTip key.
                action = machine.handle(.key(ch))
                swallow = true
            } else if optionHeld, let app, app.isFrontmost, startsSequence(ch) {
                // Option+letter chord (Alt+W typed together): same as tap-then-letter in Windows.
                optionReleasedAt = .now()
                _ = machine.handle(.optionTap)
                action = machine.handle(.key(ch))
                swallow = true
            } else {
                action = .passthrough
            }
        case .escape:
            action = machine.handle(.escape)
            swallow = wasActive
        case .backspace:
            action = machine.handle(.backspace)
            swallow = wasActive
        case .other, .mouse:
            action = machine.handle(.cancel)
        }
        route(action)
        return swallow
    }

    private func startsSequence(_ ch: Character) -> Bool {
        trie.nextKeys(after: "").contains(Character(String(ch).uppercased()))
    }

    private func cancelTimers() {
        idleTimer?.invalidate()
        commitTimer?.invalidate()
        idleTimer = nil
        commitTimer = nil
    }

    /// Input thread. Machine state is already updated; this only schedules drawing, timers and runs.
    private func route(_ action: KeyTipAction<Mapping>) {
        switch action {
        case .passthrough, .none:
            break
        case .show(let buffer, let next):
            let hud = items(after: buffer, next: next)
            let released = optionReleasedAt
            optionReleasedAt = nil
            let office = app
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.overlay.show(typed: buffer, items: hud)
                if let released {
                    self.log(String(format: "latency: option release -> HUD %.1f ms", CommandRunner.ms(since: released)))
                    if let office { self.refreshAnchor(office) }
                }
            }
            armTimers(buffer: buffer)
        case .execute(let mapping, _):
            execute(mapping, lastKeyAt: .now())
        case .invalid:
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("No command for that key", isError: true) }
        case .hide:
            DispatchQueue.main.async { [weak self] in self?.overlay.hide() }
        }
    }

    private func armTimers(buffer: String) {
        idleTimer = makeTimer(after: 5) { [weak self] in
            guard let self else { return }
            self.route(self.machine.handle(.cancel))
        }
        // Ambiguous sequence (for example H F with H F C also defined): run the short one after a pause.
        if case .exact(_, let hasLonger) = trie.lookup(buffer), hasLonger {
            commitTimer = makeTimer(after: 0.7) { [weak self] in
                guard let self else { return }
                self.route(self.machine.commitPending())
            }
        }
    }

    /// Must be called on the input thread: the timer fires on the same run loop.
    private func makeTimer(after seconds: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in block() }
        RunLoop.current.add(timer, forMode: .common)
        return timer
    }

    // MARK: execution

    private func execute(_ mapping: Mapping, lastKeyAt: DispatchTime) {
        guard let office = app, let pid = office.running?.processIdentifier else {
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("App is not running", isError: true) }
            return
        }
        executing = true
        runToken += 1
        let token = runToken
        DispatchQueue.main.async { [weak self] in self?.overlay.flash(mapping.label, isError: false, duration: 0.6) }

        runQueue.async { [weak self] in
            guard let self else { return }
            let report = self.runner.run(mapping, pid: pid)
            self.capture.perform { [weak self] in
                guard let self, self.runToken == token else { return }
                self.executing = false
                self.report(mapping, report, lastKeyAt: lastKeyAt)
            }
        }
        // Never block typing: after 1 s release the keyboard and warn.
        _ = makeTimer(after: 1) { [weak self] in
            guard let self, self.executing, self.runToken == token else { return }
            self.executing = false
            DispatchQueue.main.async {
                self.overlay.flash("\(office.displayName) is slow to respond: keys released", isError: true, duration: 2)
                self.onStatus?(.appSlow)
            }
            self.log("WARNING: executor exceeded 1 s, keyboard released")
        }
    }

    private func report(_ mapping: Mapping, _ report: RunReport, lastKeyAt: DispatchTime) {
        let total = CommandRunner.ms(since: lastKeyAt)
        let tries = report.attempts.map {
            "\($0.executor) \($0.error == nil ? "ok" : "FAILED: \($0.error ?? "")") \(String(format: "%.1f", $0.milliseconds)) ms"
        }.joined(separator: " | ")
        log(String(format: "ran \"%@\" via %@ | last key -> done %.1f ms | %@",
                   mapping.label, report.winner ?? "none", total, tries))
        DispatchQueue.main.async { [weak self] in
            if report.succeeded {
                self?.overlay.hide()
            } else {
                self?.overlay.flash("Couldn't run: \(mapping.label)", isError: true, duration: 2)
            }
        }
    }

    // MARK: HUD data

    private func items(after buffer: String, next: [Character]) -> [HUDItem] {
        next.map { key in
            let candidate = buffer + String(key)
            switch trie.lookup(candidate) {
            case .exact(let mapping, _):
                return HUDItem(key: key, label: mapping.label)
            default:
                return HUDItem(key: key, label: groupName(for: candidate) + "\u{2026}")
            }
        }
    }

    /// Ribbon path segment that matches the key position, e.g. "W" -> "View" from "View > Show > Gridlines".
    private func groupName(for prefix: String) -> String {
        let normalized = prefix.uppercased().filter { !$0.isWhitespace }
        for m in mappings {
            let keys = m.keys.uppercased().filter { !$0.isWhitespace }
            guard keys.hasPrefix(normalized), let path = m.ribbon else { continue }
            let parts = path.components(separatedBy: " > ")
            let index = normalized.count - 1
            if index < parts.count { return parts[index] }
        }
        return "More"
    }

    private func warmUp(_ office: OfficeApp) {
        guard let pid = office.running?.processIdentifier, let context = contexts[office.bundleID] else { return }
        runQueue.async { [weak self] in
            guard let self else { return }
            let ms = self.runner.warmUp(context.mappings, pid: pid, scriptingName: office.scriptingName)
            self.log(String(format: "%@ warm-up done in %.1f ms", office.displayName, ms))
        }
    }

    private func refreshAnchor(_ office: OfficeApp) {
        guard let pid = office.running?.processIdentifier else { return }
        anchorQueue.async { [weak self] in
            let app = AXNode.application(pid: pid, timeout: 0.5)
            let frame = office.focusedWindow(of: app)?.frame()
            DispatchQueue.main.async { self?.overlay.anchor = frame }
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[altformac] \(message)\n".utf8))
    }
}
