import PhotosOrganizerCore
import SwiftUI

/// The file table, with its loading and empty states.
struct FileListView: View {
    let model: AppModel

    private var isScanning: Bool { model.isBusy && model.progress.indeterminate }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Files")
                    .font(.headline)
                Spacer()
                Text(model.selectionSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.top, AppTheme.Spacing.m)
            .padding(.bottom, AppTheme.Spacing.s)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if isScanning {
                        LoadingStateView(title: "Scanning folder…")
                    }
                }
        }
        .clipShape(RoundedRectangle.themed(AppTheme.Radius.large))
        .surface()
        .animation(AppTheme.Motion.spring, value: isScanning)
        .animation(AppTheme.Motion.spring, value: model.rows.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if model.sourceDir == nil {
            EmptyStateView(
                systemImage: "photo.stack",
                title: "Choose a folder to begin",
                message: "Every photo and video inside it, sub-folders included, is listed here with the date it was taken."
            ) {
                Button(action: model.chooseSource) {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .buttonStyle(ThemeButtonStyle(kind: .primary))
                .disabled(model.isBusy)
            }
        } else if model.allEntries.isEmpty {
            if !isScanning {
                EmptyStateView(
                    systemImage: "tray",
                    title: "This folder is empty",
                    message: "No visible files were found in it or its sub-folders."
                ) {
                    Button("Choose Another Folder…", action: model.chooseSource)
                        .buttonStyle(ThemeButtonStyle(kind: .secondary))
                        .disabled(model.isBusy)
                }
            }
        } else if model.rows.isEmpty {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease",
                title: "No file types selected",
                message: "Pick the types to process in the list on the left."
            ) {
                Button("Select Photos & Videos") {
                    withAnimation(AppTheme.Motion.spring) { model.checkExtensions(where: MediaTypes.isMedia) }
                }
                .buttonStyle(ThemeButtonStyle(kind: .secondary))
                .disabled(model.isBusy)
            }
        } else {
            table
        }
    }

    private var table: some View {
        Table(model.rows) {
            TableColumn("File") { row in
                Text(row.entry.relativePath)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .help(row.entry.url.path)
            }
            .width(min: 140, ideal: 240)
            TableColumn("Type") { row in
                Text(row.entry.fileExtension.isEmpty ? "—" : row.entry.fileExtension.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .width(min: 40, ideal: 56)
            TableColumn("Size") { row in
                Text(formatSize(row.entry.size))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 76)
            TableColumn("Date taken") { row in
                if let result = row.result, let date = result.date {
                    HStack(spacing: AppTheme.Spacing.s) {
                        Text(date.description)
                            .monospacedDigit()
                        if let source = result.dateSource {
                            Text(source.rawValue)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .help(result.dateSource.map { "Date read from: \($0.rawValue)" } ?? "")
                }
            }
            .width(min: 150, ideal: 190)
            TableColumn("Status") { row in
                if let result = row.result {
                    StatusBadge(status: result.status)
                        .help(result.message)
                }
            }
            .width(min: 90, ideal: 130)
            TableColumn("Destination") { row in
                Text(model.displayDestination(row.result))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .help(row.result?.message ?? "")
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .font(.subheadline)
        .transition(.opacity)
    }
}

struct StatusBadge: View {
    let status: Status

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: Self.symbol(for: status))
                .font(.caption2.weight(.bold))
            Text(status.rawValue)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Self.color(for: status))
        .padding(.horizontal, AppTheme.Spacing.s)
        .padding(.vertical, 2)
        .background(RoundedRectangle.themed(AppTheme.Radius.xs).fill(Self.color(for: status).opacity(0.14)))
        .accessibilityElement(children: .combine)
    }

    /// Success uses the accent; everything else is neutral or a semantic warning/danger colour.
    static func color(for status: Status) -> Color {
        switch status {
        case .copied, .moved: AppTheme.Colors.accent
        case .planned, .trashed, .deleted: AppTheme.Colors.textSecondary
        case .duplicate, .noDate: AppTheme.Colors.warning
        case .error: AppTheme.Colors.danger
        }
    }

    static func symbol(for status: Status) -> String {
        switch status {
        case .planned: "clock"
        case .copied, .moved: "checkmark"
        case .trashed: "trash"
        case .deleted: "xmark"
        case .duplicate: "square.on.square"
        case .noDate: "calendar.badge.exclamationmark"
        case .error: "exclamationmark.triangle"
        }
    }
}
