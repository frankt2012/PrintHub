import Foundation

/// Bonjour discovery for the command-line spike.
///
/// The app will use `NWBrowser` with the proper `NSBonjourServices` and local
/// network permission. In a plain CLI those APIs can be blocked by local
/// network privacy, so the spike uses the system `dns-sd` tool instead.
public enum DNSSDDiscovery {
    public static func browse(seconds: TimeInterval = 5) -> [String] {
        let output = run(
            arguments: ["-B", "_http._tcp", "local."],
            seconds: seconds
        )

        let regex = try? NSRegularExpression(
            pattern: #"Add\s+\d+\s+\d+\s+local\.\s+_http\._tcp\.\s+(.+)$"#,
            options: [.anchorsMatchLines]
        )
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex?.matches(in: output, options: [], range: range) ?? []

        var names: [String] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: output) else { continue }
            let name = String(output[nameRange]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    public static func resolve(name: String, seconds: TimeInterval = 2) -> DiscoveredPrinter? {
        let output = run(
            arguments: ["-L", name, "_http._tcp", "local."],
            seconds: seconds
        )

        let regex = try? NSRegularExpression(
            pattern: #"can be reached at ([^:\s]+):(\d+)"#,
            options: []
        )
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex?.firstMatch(in: output, options: [], range: range),
              let hostRange = Range(match.range(at: 1), in: output),
              let portRange = Range(match.range(at: 2), in: output) else {
            return nil
        }

        var host = String(output[hostRange])
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard let port = UInt16(output[portRange]) else { return nil }
        return DiscoveredPrinter(name: name, host: host, servicePort: port)
    }

    private static func run(arguments: [String], seconds: TimeInterval) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ""
        }

        Thread.sleep(forTimeInterval: max(0.2, seconds))
        process.terminate()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

public struct DiscoveredPrinter: Sendable, Hashable {
    public let name: String
    public let host: String
    public let servicePort: UInt16

    public init(name: String, host: String, servicePort: UInt16) {
        self.name = name
        self.host = host
        self.servicePort = servicePort
    }
}
