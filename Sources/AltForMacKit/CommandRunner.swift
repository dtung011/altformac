import Foundation
import AltForMacCore

public struct RunReport {
    public struct Attempt {
        public let executor: String
        public let milliseconds: Double
        public let error: String?
    }
    public let attempts: [Attempt]
    public let totalMilliseconds: Double
    /// Name of the executor that worked, nil if every step failed.
    public var winner: String? { attempts.last(where: { $0.error == nil })?.executor }
    public var succeeded: Bool { winner != nil }
}

/// Tries a mapping's steps in order (shortcut -> menu -> applescript -> ribbon, as listed in the file).
/// A failed step falls through to the next one. Run on a single serial queue.
public final class CommandRunner {
    private let executors: [String: StepExecutor]
    private let appleScript = AppleScriptExecutor()

    public init() {
        var table: [String: StepExecutor] = [:]
        for e in [ShortcutExecutor(), MenuExecutor(), RibbonExecutor()] as [StepExecutor] { table[e.name] = e }
        table[appleScript.name] = appleScript
        executors = table
    }

    public static func name(of step: ExecutorStep) -> String {
        switch step {
        case .shortcut: return "shortcut"
        case .menu: return "menu"
        case .applescript: return "applescript"
        case .ribbon: return "ribbon"
        }
    }

    public func precompile(_ mappings: [Mapping]) {
        for m in mappings {
            for case .applescript(let source) in m.run { appleScript.precompile(source) }
        }
    }

    /// Primes the Apple Event connection and Accessibility lookups (resolves menu items, never presses
    /// them). Call on the runner's queue when Excel comes to the front. Returns elapsed milliseconds.
    @discardableResult
    public func warmUp(_ mappings: [Mapping], pid: pid_t, scriptingName: String) -> Double {
        let start = DispatchTime.now()
        appleScript.warmUp(scriptingName: scriptingName)
        let app = AXNode.application(pid: pid, timeout: 1.0)
        for m in mappings {
            for case .menu(let path) in m.run { _ = try? MenuNavigator.resolve(app: app, path: path) }
        }
        return Self.ms(since: start)
    }

    public func run(_ mapping: Mapping, pid: pid_t) -> RunReport {
        let start = DispatchTime.now()
        var attempts: [RunReport.Attempt] = []
        for step in mapping.run {
            let name = Self.name(of: step)
            let t0 = DispatchTime.now()
            var failure: String?
            if let executor = executors[name] {
                do { try executor.run(step, pid: pid) }
                catch { failure = String(describing: error) }
            } else {
                failure = "no executor for \(name)"
            }
            attempts.append(.init(executor: name, milliseconds: Self.ms(since: t0), error: failure))
            if failure == nil { break }
        }
        return RunReport(attempts: attempts, totalMilliseconds: Self.ms(since: start))
    }

    public static func ms(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
