import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PrintHubModel
    @State private var name: String = ""
    @State private var host: String = ""
    @AppStorage(NotificationManager.enabledKey) private var notificationsEnabled = true

    var body: some View {
        Form {
            if let printer = model.selectedPrinter {
                Section("Printer") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("IP address or hostname", text: $host)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text(printer.name)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.selectedSession?.stateLabel ?? "Not connected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Camera") {
                    Text("K2 cameras use the bundled go2rtc helper and WebRTC playback. The first frame can take a few seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Open Printer Web UI") {
                        guard let url = URL(string: "http://\(host):4408/") else { return }
                        NSWorkspace.shared.open(url)
                    }

                    Spacer()

                    Button("Save and Reconnect") {
                        model.updatePrinter(id: printer.id, name: name, host: host)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Section("Printers") {
                    Text("Add a printer from the main window.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle("Print complete, error, and paused alerts", isOn: $notificationsEnabled)
                Button("Test Notification") {
                    NotificationManager.requestAuthorization()
                    NotificationManager.postTest()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: sync)
        .onChange(of: model.selectedID) { _, _ in
            sync()
        }
    }

    private func sync() {
        name = model.selectedPrinter?.name ?? ""
        host = model.selectedPrinter?.host ?? ""
    }
}
