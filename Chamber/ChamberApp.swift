import SwiftUI

@main
struct ChamberApp: App {
    @StateObject private var model = ChamberModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1050, minHeight: 660)
                .task {
                    model.start()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Reconnect Printer") {
                    model.selectedSession?.reconnect()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Printer") {
                Button("Pause / Resume") { model.selectedSession?.togglePause() }
                Button("Stop Print") { model.selectedSession?.stopPrint() }
                Divider()
                Button("Home X") { model.selectedSession?.home(axis: .x) }
                Button("Home Y") { model.selectedSession?.home(axis: .y) }
                Button("Home Z") { model.selectedSession?.home(axis: .z) }
                Button("Home All") { model.selectedSession?.homeAll() }
                Divider()
                Button("Toggle Light") { model.selectedSession?.toggleLight() }
            }
        }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: "cube.transparent")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
