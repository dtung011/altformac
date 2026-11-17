import AppKit
import Security
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

    /// Badge lookups read the ribbon through Accessibility. Own queue, so they can never delay a command, and
    /// a generation number so a lookup that a newer key made stale stops early and draws nothing.
    private let badgeQueue = DispatchQueue(label: "altformac.badges", qos: .userInitiated)
    private let badgeGeneration = Generation()
    /// The ribbon dropdown AltForMac opened to badge its items (at most one), closed before a command runs.
    private let dropdown = DropdownHolder()

    /// Menu-bar switch: KeyTip badges on the ribbon (default) or the HUD list.
    static let badgesKey = "showRibbonBadges"
    static var badgesEnabled: Bool { UserDefaults.standard.bool(forKey: badgesKey) }

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

    /// Set when the installed app no longer matches its signature; the tap is then never installed.
    private var bundleModified = false

    var onStatus: ((Status) -> Void)?
    enum Status { case ready, needsPermission, appSlow, bundleModified }

    func start() {
        UserDefaults.standard.register(defaults: [Self.badgesKey: true])
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
        guard Self.bundleMatchesSignature() else {
            bundleModified = true
            log("app bundle does not match its signature: mappings not loaded, keyboard tap stays off")
            return
        }
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

    /// Release: the .app carries its mappings in Contents/Resources and reads them from nowhere else.
    /// Mappings can contain AppleScript, so loading them from an environment variable or a nearby folder
    /// would let another program run scripts with AltForMac's Accessibility and Automation permissions.
    /// Dev only (`swift run`, not inside an .app): ALTFORMAC_MAPPINGS_DIR, then walk up from the working
    /// directory and the binary to find `mappings/<stem>.yaml`.
    static func findMappingsFile(stem: String = "excel") throws -> URL {
        if let bundled = Bundle.main.url(forResource: stem, withExtension: "yaml"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        guard !isPackagedApp else { throw CocoaError(.fileNoSuchFile) }
        if let dir = ProcessInfo.processInfo.environment["ALTFORMAC_MAPPINGS_DIR"] {
            return URL(fileURLWithPath: dir).appendingPathComponent("\(stem).yaml")
        }
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

    static var isPackagedApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// True when the app bundle still matches its code signature, resources (the mappings) included.
    /// If someone edits a mappings file in the installed app, this fails and nothing is loaded. Re-signing
    /// the edited copy gives it a new identity, which macOS does not match to AltForMac's permissions.
    static func bundleMatchesSignature() -> Bool {
        guard isPackagedApp else { return true }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// Creating an event tap can succeed without Accessibility permission (macOS then keeps disabling it),
    /// so trust is checked explicitly first. The system prompt is shown once; after that we poll silently.
    private func installTapWhenPermitted(prompt: Bool = true) {
        if bundleModified {
            onStatus?(.bundleModified)
            return
        }
        if AXPermission.isTrusted, capture.install() {
            onStatus?(.ready)
            frontAppChanged(OfficeApp.frontmost)
            return
        }
        onStatus?(.needsPermission)
        if prompt { AXPermission.requestPrompt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.installTapWhenPermitted(prompt: false)
        }
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
            let generation = badgeGeneration.bump()
            let plan = Self.badgesEnabled ? BadgePlanner.plan(mappings: mappings, buffer: buffer) : []
            let dropdownPlan = Self.badgesEnabled && plan.isEmpty
                ? BadgePlanner.dropdown(mappings: mappings, buffer: buffer) : nil
            closeDropdownLater(pid: office?.running?.processIdentifier)
            if let dropdownPlan, let pid = office?.running?.processIdentifier {
                showDropdown(dropdownPlan, typed: buffer, hud: hud, pid: pid, generation: generation, released: released)
            } else if plan.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.overlay.show(typed: buffer, items: hud)
                    if let released {
                        self.log(String(format: "latency: option release -> HUD %.1f ms", CommandRunner.ms(since: released)))
                        if let office { self.refreshAnchor(office) }
                    }
                }
            } else if let pid = office?.running?.processIdentifier {
                showBadges(plan, typed: buffer, hud: hud, pid: pid, generation: generation, released: released)
            }
            armTimers(buffer: buffer)
            switchTabIfTabKey(buffer)
        case .execute(let mapping, _):
            badgeGeneration.bump()
            execute(mapping, lastKeyAt: .now())
        case .invalid:
            badgeGeneration.bump()
            closeDropdownLater(pid: app?.running?.processIdentifier)
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("No command for that key", isError: true, duration: 2) }
        case .hide:
            badgeGeneration.bump()
            closeDropdownLater(pid: app?.running?.processIdentifier)
            DispatchQueue.main.async { [weak self] in self?.overlay.hide() }
        }
    }

    /// Input thread. Takes down a dropdown opened for item badges, after any lookup already queued.
    private func closeDropdownLater(pid: pid_t?) {
        guard let pid else { return }
        badgeQueue.async { [dropdown] in dropdown.closeNow(pid: pid) }
    }

    /// Input thread. Opens the dropdown the typed keys lead to (AXShowMenu) and puts a badge on each item.
    /// Falls back to the HUD list when it cannot be opened.
    private func showDropdown(_ plan: DropdownPlan, typed: String, hud: [HUDItem], pid: pid_t,
                              generation: Int, released: DispatchTime?) {
        let counter = badgeGeneration
        badgeQueue.async { [weak self] in
            guard let self, counter.value == generation else { return }
            let opened = RibbonGeometry.openDropdown(plan, pid: pid) { counter.value == generation }
            if let opened {
                self.dropdown.set(opened.session)
                if counter.value != generation { self.dropdown.closeNow(pid: pid); return }   // a newer key arrived meanwhile
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, counter.value == generation else { return }
                if let opened, !opened.placements.isEmpty {
                    self.overlay.showBadges(opened.placements)
                    if let released {
                        self.log(String(format: "latency: option release -> dropdown badges %.1f ms (%d)",
                                        CommandRunner.ms(since: released), opened.placements.count))
                    }
                } else {
                    self.overlay.show(typed: typed, items: hud)
                }
            }
        }
    }

    /// Input thread. Looks the controls up on `badgeQueue` and draws the badges on the main thread. When the
    /// ribbon cannot be read (or nothing is on screen for this level) it falls back to the HUD list.
    private func showBadges(_ plan: [RibbonBadge], typed: String, hud: [HUDItem], pid: pid_t,
                            generation: Int, released: DispatchTime?) {
        let counter = badgeGeneration
        badgeQueue.async { [weak self] in
            guard counter.value == generation else { return }
            let placed = RibbonGeometry.place(plan, pid: pid) { counter.value == generation }
            DispatchQueue.main.async { [weak self] in
                guard let self, counter.value == generation else { return }
                if let placed, !placed.isEmpty {
                    self.overlay.showBadges(placed)
                    if let released {
                        self.log(String(format: "latency: option release -> badges %.1f ms (%d)",
                                        CommandRunner.ms(since: released), placed.count))
                    }
                } else {
                    self.overlay.show(typed: typed, items: hud)
                }
            }
        }
    }

    private func armTimers(buffer: String) {
        idleTimer = makeTimer(after: 5) { [weak self] in
            guard let self else { return }
            self.route(self.machine.handle(.cancel))
        }
        // Ambiguous sequence (for example H F with H F C also defined): run the short one after a pause.
        // Tab letters (N = Insert) are not ambiguous: they switch the tab and wait for the next key.
        if case .exact(let mapping, let hasLonger) = trie.lookup(buffer), hasLonger,
           !mapping.isTabSwitch, !mapping.isMenuOpener {
            commitTimer = makeTimer(after: 0.7) { [weak self] in
                guard let self else { return }
                self.route(self.machine.commitPending())
            }
        }
    }

    /// Input thread. A tab letter switches the ribbon tab immediately but keeps the sequence (and HUD) open.
    /// Runs on the serial `runQueue`, so a command typed right after it still runs after the tab switch.
    private func switchTabIfTabKey(_ buffer: String) {
        guard case .exact(let mapping, _) = trie.lookup(buffer), mapping.isTabSwitch,
              let pid = app?.running?.processIdentifier else { return }
        runQueue.async { [weak self] in
            guard let self else { return }
            let report = self.runner.run(mapping, pid: pid)
            self.log(String(format: "tab \"%@\" via %@ | %.1f ms", mapping.label,
                            report.winner ?? "none", report.attempts.reduce(0) { $0 + $1.milliseconds }))
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
        DispatchQueue.main.async { [weak self] in self?.overlay.flash(mapping.label, isError: false, duration: 1.2) }

        runQueue.async { [weak self] in
            guard let self else { return }
            self.dropdown.closeNow(pid: pid)   // a dropdown opened for badges must be gone before the command runs
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
            // On success the confirmation flash started in execute() fades out on its own timer.
            if !report.succeeded {
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

/// Counter shared between the input thread and the badge queue: bumping it makes older lookups stale.
final class Generation: @unchecked Sendable {
    private let lock = NSLock()
    private var number = 0

    var value: Int { lock.lock(); defer { lock.unlock() }; return number }

    @discardableResult
    func bump() -> Int { lock.lock(); defer { lock.unlock() }; number += 1; return number }
}

/// Holds the dropdown AltForMac has open, shared between the badge queue and the run queue.
final class DropdownHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var session: DropdownSession?

    func set(_ new: DropdownSession) {
        lock.lock(); defer { lock.unlock() }
        session = new
    }

    /// Closes the open dropdown, if any. Safe to call when none is open.
    func closeNow(pid: pid_t) {
        lock.lock()
        let current = session
        session = nil
        lock.unlock()
        current?.close(pid: pid)
    }
}
