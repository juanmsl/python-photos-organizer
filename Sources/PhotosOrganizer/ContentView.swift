import PhotosOrganizerCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceRow
            HSplitView {
                ExtensionFilterView(model: model)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 340)
                VStack(alignment: .leading, spacing: 6) {
                    FileTableView(model: model)
                    Text(model.selectionSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                .frame(minWidth: 500)
            }
            outputBox
            progressBar
            LogView(lines: model.logLines)
        }
        .padding()
    }

    private var sourceRow: some View {
        HStack {
            Text("Source folder:")
            PathField(url: model.sourceDir, placeholder: "Choose the folder that contains your photos/videos…")
            Button("Browse…", action: model.chooseSource)
                .disabled(model.isBusy)
            Button("Rescan", action: model.startScan)
                .disabled(model.isBusy || model.sourceDir == nil)
        }
    }

    private var outputBox: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Output folder:")
                    PathField(url: model.outputDir, placeholder: "Files will be placed in \(model.exampleDestination)")
                    Button("Browse…", action: model.chooseOutput)
                }
                .disabled(model.isBusy || model.isDeleting)

                HStack(spacing: 20) {
                    Picker("Folder structure:", selection: $model.layout) {
                        ForEach(FolderLayout.allCases) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    .fixedSize()
                    Toggle("Use file date when there is no EXIF/metadata date", isOn: $model.useFilesystemFallback)
                    Spacer()
                }
                .disabled(model.isBusy || model.isDeleting)

                HStack {
                    Picker("Action:", selection: $model.action) {
                        Text("Copy files (keep originals)").tag(Action.copy)
                        Text("Move files").tag(Action.move)
                        Text("Delete matched files").tag(Action.delete)
                            .help("Delete every file in the list. No output folder or metadata is needed.")
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .fixedSize()
                    .disabled(model.isBusy)

                    if model.isDeleting {
                        Toggle("Permanently (skip Trash)", isOn: $model.permanentDelete)
                            .help("Delete files for good instead of moving them to the Trash. This cannot be undone.")
                            .disabled(model.isBusy)
                    }
                    Spacer()

                    Button("Preview") { model.start(dryRun: true) }
                        .help(model.isDeleting
                            ? "List the files that would be deleted, without touching anything."
                            : "Read the metadata and show where each file would go, without touching anything.")
                        .disabled(model.isBusy || !model.isReady)
                    Button(model.isDeleting ? "Delete" : "Organize") { model.start(dryRun: false) }
                        .keyboardShortcut(model.isDeleting ? nil : .defaultAction)
                        .disabled(model.isBusy || !model.isReady)
                    Button("Cancel", action: model.cancel)
                        .disabled(!model.isBusy)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if model.progress.indeterminate {
            ProgressView().progressViewStyle(.linear)
        } else {
            ProgressView(value: Double(model.progress.done), total: Double(max(model.progress.total, 1))) {
                EmptyView()
            } currentValueLabel: {
                Text(model.progress.total > 0 ? "\(model.progress.done) / \(model.progress.total)" : " ")
            }
        }
    }
}

/// A read-only path display that truncates in the middle.
struct PathField: View {
    let url: URL?
    let placeholder: String

    var body: some View {
        Text(url?.path ?? placeholder)
            .foregroundStyle(url == nil ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            .help(url?.path ?? "")
    }
}

struct ExtensionFilterView: View {
    let model: AppModel

    var body: some View {
        GroupBox("File types") {
            VStack(spacing: 6) {
                List(model.extensions) { option in
                    Toggle(isOn: Binding(
                        get: { option.isChecked },
                        set: { model.setChecked(option.fileExtension, $0) }
                    )) {
                        HStack {
                            Text(option.label)
                            Spacer()
                            Text("\(option.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .listStyle(.bordered)
                HStack {
                    Button("All") { model.checkExtensions { _ in true } }
                    Button("None") { model.checkExtensions { _ in false } }
                    Button("Media") { model.checkExtensions(where: MediaTypes.isMedia) }
                }
                .controlSize(.small)
            }
            .disabled(model.isBusy)
        }
    }
}

struct FileTableView: View {
    let model: AppModel

    var body: some View {
        Table(model.rows) {
            TableColumn("File") { row in
                Text(row.entry.relativePath).help(row.entry.url.path)
            }
            .width(min: 160, ideal: 340)
            TableColumn("Type") { row in
                Text(row.entry.fileExtension.isEmpty ? "—" : row.entry.fileExtension.uppercased())
            }
            .width(min: 40, ideal: 60)
            TableColumn("Size") { row in
                Text(formatSize(row.entry.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Date taken") { row in
                Text(row.result?.date?.description ?? "").monospacedDigit()
            }
            .width(min: 100, ideal: 140)
            TableColumn("Date source") { row in
                Text(row.result?.dateSource?.rawValue ?? "")
            }
            .width(min: 70, ideal: 110)
            TableColumn("Status") { row in
                Text(row.result?.status.rawValue ?? "")
                    .foregroundStyle(row.result.map { Self.color(for: $0.status) } ?? .primary)
                    .help(row.result?.message ?? "")
            }
            .width(min: 80, ideal: 130)
            TableColumn("Destination") { row in
                Text(model.displayDestination(row.result))
                    .help(row.result?.message ?? "")
            }
        }
        .alternatingRowBackgrounds()
    }

    static func color(for status: Status) -> Color {
        switch status {
        case .planned: Color(red: 0.18, green: 0.44, blue: 0.87)
        case .copied, .moved: Color(red: 0.18, green: 0.55, blue: 0.34)
        case .trashed, .deleted: Color(red: 0.50, green: 0.55, blue: 0.55)
        case .duplicate, .noDate: Color(red: 0.72, green: 0.53, blue: 0.04)
        case .error: Color(red: 0.75, green: 0.22, blue: 0.17)
        }
    }
}

struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line).id(index)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(height: 110)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            .onChange(of: lines.count) {
                proxy.scrollTo(lines.count - 1, anchor: .bottom)
            }
        }
    }
}
