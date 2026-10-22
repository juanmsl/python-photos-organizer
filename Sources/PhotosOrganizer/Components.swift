import SwiftUI

// MARK: - Surfaces

/// A layered card: material blur, a faint tint, a 1-pt hairline and a soft shadow.
struct SurfaceModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle.themed(radius)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle.themed(radius).fill(AppTheme.Colors.surfaceTint))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            }
            .overlay(RoundedRectangle.themed(radius).strokeBorder(AppTheme.Colors.border, lineWidth: 1))
    }
}

extension View {
    func surface(radius: CGFloat = AppTheme.Radius.large) -> some View {
        modifier(SurfaceModifier(radius: radius))
    }
}

/// Small upper-case caption used above fields.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(AppTheme.Colors.textSecondary)
    }
}

// MARK: - Buttons

/// Feedback starts on pointer-down (`isPressed` flips as soon as the button is pressed); the action
/// itself still runs on release, so a press can be cancelled by dragging away, as everywhere on macOS.
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppTheme.Motion.press, value: configuration.isPressed)
    }
}

struct ThemeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, ghost }

    var kind: Kind = .secondary
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        ThemeButton(configuration: configuration, kind: kind, iconOnly: iconOnly)
    }
}

private struct ThemeButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: ThemeButtonStyle.Kind
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(kind == .primary || kind == .destructive ? .headline : .body.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : AppTheme.Spacing.m)
            .frame(minWidth: AppTheme.Metrics.hitTarget, minHeight: AppTheme.Metrics.hitTarget)
            .background(RoundedRectangle.themed(AppTheme.Radius.medium).fill(fill))
            .overlay(RoundedRectangle.themed(AppTheme.Radius.medium).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle.themed(AppTheme.Radius.medium))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(AppTheme.Motion.press, value: configuration.isPressed)
            .animation(AppTheme.Motion.spring, value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
    }

    private var foreground: Color {
        switch kind {
        case .primary: AppTheme.Colors.onAccent
        case .destructive: AppTheme.Colors.onDanger
        case .secondary, .ghost: AppTheme.Colors.textPrimary
        }
    }

    private var fill: Color {
        let pressed = configuration.isPressed
        switch kind {
        case .primary: return AppTheme.Colors.accent.opacity(pressed ? 0.8 : isHovered ? 0.9 : 1)
        case .destructive: return AppTheme.Colors.danger.opacity(pressed ? 0.8 : isHovered ? 0.9 : 1)
        case .secondary: return pressed ? AppTheme.Colors.well : isHovered ? AppTheme.Colors.hover : AppTheme.Colors.backgroundRaised.opacity(0.6)
        case .ghost: return pressed ? AppTheme.Colors.well : isHovered ? AppTheme.Colors.hover : .clear
        }
    }

    private var border: Color {
        kind == .secondary ? AppTheme.Colors.borderStrong : .clear
    }
}

// MARK: - Segmented picker

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String?

    var id: Value { value }
}

/// A segmented control whose selection indicator slides between segments with a spring.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SegmentOption<Value>]
    var tint: Color = AppTheme.Colors.accent

    @Namespace private var namespace
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .background(RoundedRectangle.themed(AppTheme.Radius.medium).fill(AppTheme.Colors.well))
        .overlay(RoundedRectangle.themed(AppTheme.Radius.medium).strokeBorder(AppTheme.Colors.border, lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func segment(_ option: SegmentOption<Value>) -> some View {
        let isSelected = option.value == selection
        return Button {
            withAnimation(AppTheme.Motion.spring) { selection = option.value }
        } label: {
            HStack(spacing: AppTheme.Spacing.s) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(isSelected ? tint : AppTheme.Colors.textSecondary)
                }
                Text(option.title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.m)
            .frame(minWidth: AppTheme.Metrics.hitTarget, minHeight: AppTheme.Metrics.hitTarget)
            .background {
                if isSelected {
                    RoundedRectangle.themed(AppTheme.Radius.small)
                        .fill(AppTheme.Colors.backgroundRaised)
                        .overlay(RoundedRectangle.themed(AppTheme.Radius.small).strokeBorder(tint.opacity(0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                        .padding(AppTheme.Spacing.xs)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(RoundedRectangle.themed(AppTheme.Radius.small))
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Switch

/// A switch whose whole row (track and label) is one 44-pt target.
struct ThemeSwitchStyle: ToggleStyle {
    var tint: Color = AppTheme.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        ThemeSwitch(configuration: configuration, tint: tint)
    }
}

private struct ThemeSwitch: View {
    let configuration: ToggleStyleConfiguration
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(AppTheme.Motion.spring) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: AppTheme.Spacing.s) {
                RoundedRectangle.themed(AppTheme.Radius.small)
                    .fill(configuration.isOn ? tint : AppTheme.Colors.well)
                    .overlay(RoundedRectangle.themed(AppTheme.Radius.small).strokeBorder(AppTheme.Colors.border, lineWidth: 1))
                    .frame(width: 36, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        RoundedRectangle.themed(AppTheme.Radius.small - 2)
                            .fill(AppTheme.Colors.knob)
                            .frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                            .padding(2)
                    }
                configuration.label
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(minHeight: AppTheme.Metrics.hitTarget)
            .contentShape(RoundedRectangle.themed(AppTheme.Radius.small))
        }
        .buttonStyle(PressFeedbackStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Progress

/// A slim progress track. The fill follows live values with a spring, so updates retarget smoothly.
struct ProgressTrack: View {
    let fraction: Double
    var tint: Color = AppTheme.Colors.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle.themed(AppTheme.Radius.xs).fill(AppTheme.Colors.well)
                RoundedRectangle.themed(AppTheme.Radius.xs)
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(AppTheme.Motion.spring, value: fraction)
    }
}

// MARK: - Empty and loading states

struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle.themed(AppTheme.Radius.large).fill(AppTheme.Colors.accent.opacity(0.12)))
                .overlay(RoundedRectangle.themed(AppTheme.Radius.large).strokeBorder(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1))
            VStack(spacing: AppTheme.Spacing.s) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            actions
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

struct LoadingStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(AppTheme.Spacing.xl)
        .surface(radius: AppTheme.Radius.large)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
