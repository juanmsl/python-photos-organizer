import PhotosOrganizerCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            header
            HStack(spacing: AppTheme.Spacing.m) {
                sourceCard
                outputCard
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                FileTypeSidebar(model: model)
                    .frame(width: AppTheme.Metrics.sidebarWidth)
                FileListView(model: model)
            }
            .frame(maxHeight: .infinity)
            ControlBar(model: model)
            ActivityLog(lines: model.logLines)
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.top, AppTheme.Spacing.s)
        .padding(.bottom, AppTheme.Spacing.l)
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .tint(AppTheme.Colors.accent)
        .background(WindowBackground())
        .animation(AppTheme.Motion.spring, value: model.isDeleting)
        .animation(AppTheme.Motion.spring, value: model.isBusy)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Photos Organizer")
                    .font(.largeTitle.weight(.bold))
                Text("Rename and file photos and videos by the moment they were taken.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer()
        }
    }

    private var sourceCard: some View {
        FolderCard(
            title: "Source",
            systemImage: "photo.on.rectangle.angled",
            path: model.sourceDir?.path,
            placeholder: "Choose the folder that holds your photos and videos"
        ) {
            Button(action: model.startScan) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(ThemeButtonStyle(kind: .ghost, iconOnly: true))
            .help("Rescan the source folder")
            .disabled(model.isBusy || model.sourceDir == nil)

            Button("Choose…", action: model.chooseSource)
                .buttonStyle(ThemeButtonStyle(kind: .secondary))
                .disabled(model.isBusy)
        }
    }

    private var outputCard: some View {
        FolderCard(
            title: "Destination",
            systemImage: "tray.and.arrow.down",
            path: model.isDeleting ? nil : model.outputDir?.path,
            placeholder: model.isDeleting ? "Not needed when deleting files" : "Files will be placed in \(model.exampleDestination)"
        ) {
            Button("Choose…", action: model.chooseOutput)
                .buttonStyle(ThemeButtonStyle(kind: .secondary))
        }
        .disabled(model.isBusy || model.isDeleting)
        .opacity(model.isDeleting ? 0.55 : 1)
    }
}

// MARK: - Background

/// Three layers: base colour, a soft vertical lift and a faint accent glow, so the material surfaces
/// above have something to blur.
private struct WindowBackground: View {
    var body: some View {
        ZStack {
            AppTheme.Colors.background
            LinearGradient(
                colors: [AppTheme.Colors.backgroundRaised, AppTheme.Colors.background],
                startPoint: .top, endPoint: .center
            )
            RadialGradient(
                colors: [AppTheme.Colors.accent.opacity(0.07), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Folder card

struct FolderCard<Actions: View>: View {
    let title: String
    let systemImage: String
    let path: String?
    let placeholder: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(path == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
                .frame(width: AppTheme.Metrics.hitTarget, height: AppTheme.Metrics.hitTarget)
                .background(RoundedRectangle.themed(AppTheme.Radius.medium).fill(AppTheme.Colors.well))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                SectionLabel(title)
                Text(path ?? placeholder)
                    .font(.subheadline)
                    .foregroundStyle(path == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path ?? "")
                    .contentTransition(.opacity)
            }
            Spacer(minLength: AppTheme.Spacing.s)
            HStack(spacing: AppTheme.Spacing.s) {
                actions
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity)
        .surface()
    }
}

// MARK: - File-type sidebar

struct FileTypeSidebar: View {
    let model: AppModel

    private var checkedCount: Int { model.extensions.filter(\.isChecked).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("File types")
                    .font(.headline)
                Spacer()
                if !model.extensions.isEmpty {
                    Text("\(checkedCount) of \(model.extensions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.top, AppTheme.Spacing.m)
            .padding(.bottom, AppTheme.Spacing.s)

            if model.extensions.isEmpty {
                Text("File types appear here once a folder has been scanned.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.extensions) { option in
                            ExtensionRow(option: option) {
                                model.setChecked(option.fileExtension, !option.isChecked)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.s)
                }
                .scrollIndicators(.automatic)

                Divider()
                    .overlay(AppTheme.Colors.border)
                HStack(spacing: AppTheme.Spacing.xs) {
                    Button("All") { withAnimation(AppTheme.Motion.spring) { model.checkExtensions { _ in true } } }
                    Button("None") { withAnimation(AppTheme.Motion.spring) { model.checkExtensions { _ in false } } }
                    Button("Media") { withAnimation(AppTheme.Motion.spring) { model.checkExtensions(where: MediaTypes.isMedia) } }
                }
                .buttonStyle(ThemeButtonStyle(kind: .ghost))
                .frame(maxWidth: .infinity)
                .padding(AppTheme.Spacing.s)
            }
        }
        .frame(maxHeight: .infinity)
        .surface()
        .disabled(model.isBusy)
    }
}

private struct ExtensionRow: View {
    let option: ExtensionOption
    let toggle: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: AppTheme.Spacing.s) {
                RoundedRectangle.themed(AppTheme.Radius.xs + 1)
                    .fill(option.isChecked ? AppTheme.Colors.accent : .clear)
                    .overlay(
                        RoundedRectangle.themed(AppTheme.Radius.xs + 1)
                            .strokeBorder(option.isChecked ? .clear : AppTheme.Colors.borderStrong, lineWidth: 1.5)
                    )
                    .overlay {
                        if option.isChecked {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(AppTheme.Colors.onAccent)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .frame(width: 18, height: 18)
                Text(option.label)
                    .font(.subheadline.weight(option.isChecked ? .semibold : .regular))
                    .foregroundStyle(option.isChecked ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                Spacer()
                Text("\(option.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.s)
            .frame(minHeight: AppTheme.Metrics.hitTarget)
            .background(RoundedRectangle.themed(AppTheme.Radius.small).fill(isHovered ? AppTheme.Colors.hover : .clear))
            .contentShape(RoundedRectangle.themed(AppTheme.Radius.small))
            .animation(AppTheme.Motion.spring, value: option.isChecked)
            .animation(AppTheme.Motion.spring, value: isHovered)
        }
        .buttonStyle(PressFeedbackStyle())
        .onHover { isHovered = $0 && isEnabled }
        .accessibilityLabel("\(option.label), \(option.count) files")
        .accessibilityAddTraits(option.isChecked ? .isSelected : [])
    }
}

// MARK: - Control bar

struct ControlBar: View {
    @Bindable var model: AppModel

    /// While working, and afterwards for as long as the table shows that run's results.
    private var showsProgress: Bool {
        !model.progress.indeterminate && model.progress.total > 0
            && (model.isBusy || model.rows.contains { $0.result != nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                    SectionLabel("Action")
                    SegmentedPicker(
                        selection: $model.action,
                        options: [
                            SegmentOption(value: .copy, title: "Copy", systemImage: "doc.on.doc"),
                            SegmentOption(value: .move, title: "Move", systemImage: "arrow.right.doc.on.clipboard"),
                            SegmentOption(value: .delete, title: "Delete", systemImage: "trash"),
                        ],
                        tint: model.isDeleting ? AppTheme.Colors.danger : AppTheme.Colors.accent
                    )
                    .fixedSize()
                    .disabled(model.isBusy)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                    SectionLabel("Folder structure")
                    SegmentedPicker(
                        selection: $model.layout,
                        options: [
                            SegmentOption(value: .year, title: "YYYY"),
                            SegmentOption(value: .yearMonth, title: "YYYY / MM"),
                            SegmentOption(value: .yearMonthDay, title: "YYYY / MM / DD"),
                        ]
                    )
                    .fixedSize()
                    .disabled(model.isBusy || model.isDeleting)
                }

                Spacer(minLength: 0)

                if showsProgress {
                    progress
                        .frame(maxWidth: 280)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            Divider()
                .overlay(AppTheme.Colors.border)

            HStack(spacing: AppTheme.Spacing.m) {
                Toggle("Use the file date when there is no metadata", isOn: $model.useFilesystemFallback)
                    .toggleStyle(ThemeSwitchStyle())
                    .disabled(model.isBusy || model.isDeleting)
                    .help("Files without an EXIF/metadata date use their creation or modification date instead of being skipped.")

                if model.isDeleting {
                    Toggle("Permanently (skip Trash)", isOn: $model.permanentDelete)
                        .toggleStyle(ThemeSwitchStyle(tint: AppTheme.Colors.danger))
                        .disabled(model.isBusy)
                        .help("Delete files for good instead of moving them to the Trash. This cannot be undone.")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: AppTheme.Spacing.m)

                if model.isBusy {
                    Button("Cancel", action: model.cancel)
                        .buttonStyle(ThemeButtonStyle(kind: .ghost))
                        .keyboardShortcut(.cancelAction)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Button { model.start(dryRun: true) } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(ThemeButtonStyle(kind: .secondary))
                .help(model.isDeleting
                    ? "List the files that would be deleted, without touching anything."
                    : "Read the metadata and show where each file would go, without touching anything.")
                .disabled(model.isBusy || !model.isReady)

                primaryButton
                    .disabled(model.isBusy || !model.isReady)
            }
        }
        .padding(AppTheme.Spacing.m)
        .surface()
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.isDeleting {
            Button { model.start(dryRun: false) } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(ThemeButtonStyle(kind: .destructive))
        } else {
            Button { model.start(dryRun: false) } label: {
                Label("Organize", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(ThemeButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var progress: some View {
        let done = model.progress.done
        let total = model.progress.total
        let title = model.isBusy ? "Working" : (done < total ? "Stopped" : "Finished")
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title)
                Spacer()
                Text("\(done) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .contentTransition(.numericText())
            }
            ProgressTrack(
                fraction: Double(done) / Double(max(total, 1)),
                tint: model.isDeleting ? AppTheme.Colors.danger : AppTheme.Colors.accent
            )
        }
        .padding(.top, AppTheme.Spacing.xs)
    }
}

// MARK: - Activity log

struct ActivityLog: View {
    let lines: [String]
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(AppTheme.Motion.spring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: AppTheme.Spacing.s) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Activity")
                        .font(.headline)
                    Text(lines.last ?? "Nothing has happened yet.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.m)
                .frame(minHeight: AppTheme.Metrics.hitTarget)
                .contentShape(RoundedRectangle.themed(AppTheme.Radius.medium))
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityLabel(isExpanded ? "Hide activity log" : "Show activity log")

            if isExpanded {
                Divider()
                    .overlay(AppTheme.Colors.border)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line).id(index)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.m)
                    }
                    .frame(height: 128)
                    .onAppear { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                    .onChange(of: lines.count) { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle.themed(AppTheme.Radius.medium))
        .surface(radius: AppTheme.Radius.medium)
    }
}
