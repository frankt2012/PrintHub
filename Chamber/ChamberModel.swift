import AppKit
import Foundation

@MainActor
final class ChamberModel: ObservableObject {
    @Published private(set) var printers: [PrinterConfig]
    @Published private(set) var sessions: [UUID: PrinterSession] = [:]
    @Published var selectedID: UUID?

    private var started = false
    private let printersKey = "printers"

    var selectedSession: PrinterSession? {
        guard let selectedID else { return nil }
        return sessions[selectedID]
    }

    var selectedPrinter: PrinterConfig? {
        guard let selectedID else { return nil }
        return printers.first { $0.id == selectedID }
    }

    init() {
        printers = Self.loadPrinters()
        selectedID = printers.first?.id

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shutdown()
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationManager.requestAuthorization()
        createSessions()
    }

    func addPrinter(name: String, host: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = PrinterConfig(
            name: trimmedName.isEmpty ? "Creality Printer" : trimmedName,
            host: trimmedHost
        )

        printers.append(config)
        savePrinters()

        let session = makeSession(config, index: printers.count - 1)
        sessions[config.id] = session
        selectedID = config.id
        session.start()
    }

    func removePrinter(id: UUID) {
        sessions[id]?.stop()
        sessions[id] = nil
        printers.removeAll { $0.id == id }
        savePrinters()

        if selectedID == id {
            selectedID = printers.first?.id
        }
    }

    func updatePrinter(id: UUID, name: String, host: String) {
        guard let index = printers.firstIndex(where: { $0.id == id }) else { return }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = PrinterConfig(
            id: id,
            name: trimmedName.isEmpty ? printers[index].name : trimmedName,
            host: trimmedHost
        )

        sessions[id]?.stop()
        sessions[id] = nil
        printers[index] = updated
        savePrinters()

        let session = makeSession(updated, index: index)
        sessions[id] = session
        selectedID = id
        session.start()
    }

    func updateSelectedPrinter(name: String? = nil, host: String) {
        guard let id = selectedID else { return }
        let currentName = selectedPrinter?.name ?? "Creality Printer"
        updatePrinter(id: id, name: name ?? currentName, host: host)
    }

    func shutdown() {
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
    }

    private func createSessions() {
        for (index, config) in printers.enumerated() where sessions[config.id] == nil {
            let session = makeSession(config, index: index)
            sessions[config.id] = session
            session.start()
        }
    }

    private func makeSession(_ config: PrinterConfig, index: Int) -> PrinterSession {
        let port = UInt16(1984 + max(0, index))
        let go2rtc = Go2RTCSupervisor(port: port)
        return PrinterSession(config: config, go2rtc: go2rtc)
    }

    private func savePrinters() {
        guard let data = try? JSONEncoder().encode(printers) else { return }
        UserDefaults.standard.set(data, forKey: printersKey)
    }

    private static func loadPrinters() -> [PrinterConfig] {
        if let data = UserDefaults.standard.data(forKey: "printers"),
           let decoded = try? JSONDecoder().decode([PrinterConfig].self, from: data) {
            return decoded
        }

        // Migration from the first single-printer build.
        if let host = UserDefaults.standard.string(forKey: "printerHost"),
           !host.isEmpty {
            return [PrinterConfig(name: "K2 Plus", host: host)]
        }

        return []
    }
}

struct PrinterConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
}
