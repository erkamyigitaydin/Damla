import Foundation

/// Every Apple Events script goes through here. A script is compiled once and reused: a fresh `NSAppleScript`
/// per call left about 0.7 KB behind and cost 0.2 ms each (measured), tens of thousands of times a day while a
/// background Music or Spotify was polled. They also run on one serial queue, since `NSAppleScript` is not safe
/// to use from several threads at once, and the players answer one request at a time anyway.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "app.damla.applescript", qos: .utility)
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]
    nonisolated(unsafe) private static var order: [String] = []   // least recently compiled first
    /// Scripts with a value baked in (a volume level, a seek position) each compile once; the oldest go.
    private static let limit = 32

    /// Compiles (or finds) and runs the script; the error dictionary is `NSAppleScript`'s, nil on success.
    static func run(_ source: String) -> (result: NSAppleEventDescriptor?, error: NSDictionary?) {
        queue.sync {
            var error: NSDictionary?
            let script: NSAppleScript
            if let cached = compiled[source] {
                script = cached
            } else {
                guard let fresh = NSAppleScript(source: source) else { return (nil, nil) }
                guard fresh.compileAndReturnError(&error) else { return (nil, error) }   // a bad script is not kept
                compiled[source] = fresh; order.append(source)
                if order.count > limit { compiled.removeValue(forKey: order.removeFirst()) }
                script = fresh
            }
            let result = script.executeAndReturnError(&error)
            return (result, error)
        }
    }
}
