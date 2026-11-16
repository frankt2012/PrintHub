import AppKit
import SwiftUI
import ChamberKit

struct ContentView: View {
    @ObservedObject var model: ChamberModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = true
    @State private var focusMode = false
    @State private var showAddPrinter = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let session = model.selectedSession {
                PrinterDetailView(session: session, showInspector: $showInspector)
            } else {
                emptyState
            }
        }
        .navigationTitle("Chamber")
        .sheet(isPresented: $showAddPrinter) {
            AddPrinterView { name, host in
                model.addPrinter(name: name, host: host)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    toggleFocusMode()
                } label: {
                    Label(
                        focusMode ? "Show Controls" : "Focus Camera",
                        systemImage: focusMode ? "sidebar.left" : "rectangle.expand.vertical"
                    )
                }
                .help(focusMode ? "Show the printer sidebar and inspector" : "Hide the sidebar and inspector")

                Button {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Toggle full screen")

                Button {
                    model.selectedSession?.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh printer state")

                Button {
                    model.selectedSession?.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "bolt.horizontal")
                }
                .help("Reconnect to the printer")
            }
        }
    }

    private func toggleFocusMode() {
        focusMode.toggle()
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = focusMode ? .detailOnly : .all
            showInspector = !focusMode
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                Section("Printers") {
                    if model.printers.isEmpty {
                        Text("No printers")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.printers) { printer in
                            Group {
                                if let session = model.sessions[printer.id] {
                                    PrinterRow(session: session)
                                } else {
                                    Text(printer.name)
                                }
                            }
                            .tag(printer.id)
                            .contextMenu {
                                Button("Remove Printer", role: .destructive) {
                                    model.removePrinter(id: printer.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button {
                    showAddPrinter = true
                } label: {
                    Label("Add Printer", systemImage: "plus")
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No printer selected")
                .font(.title3.weight(.semibold))
            Text("Add a Creality printer to get started.")
                .foregroundStyle(.secondary)
            Button("Add Printer") {
                showAddPrinter = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrinterRow: View {
    @ObservedObject var session: PrinterSession

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(session.stateLabel)
                    if let progress = session.snapshot.progress, session.snapshot.isPrinting {
                        Text("·")
                        Text("\(Int(progress))%")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if session.connection.isLive {
                ProgressView(
                    value: session.snapshot.progress ?? 0,
                    total: 100
                )
                .progressViewStyle(.linear)
                .frame(width: 36)
            }
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch session.connection {
        case .live:
            switch session.snapshot.derivedState {
            case .printing, .processing: return .teal
            case .paused: return .orange
            case .error: return .red
            case .complete: return .blue
            default: return .gray
            }
        case .connecting: return .orange
        case .offline: return .red
        case .idle: return .gray
        }
    }
}


struct AddPrinterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "K2 Plus"
    @State private var host = ""

    let onAdd: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Printer")
                .font(.title2.weight(.semibold))
            Text("Enter the printer's local IP address. Discovery is coming next.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                TextField("Name", text: $name)
                TextField("IP address or hostname", text: $host)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(name, host)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
