import SwiftUI
import AppKit

/// Prominent glass button on macOS 26+, bordered prominent before that or when transparency is reduced.
private struct ReaderPrimaryAction: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

extension View {
    func readerPrimaryAction() -> some View { modifier(ReaderPrimaryAction()) }
}

/// Liquid Glass on macOS 26+; material before that; a solid, outlined fill when transparency is reduced
/// or contrast is increased, so the control edge stays visible.
private struct ReaderGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let hovering: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45 : 0.18)))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                material(content)
            }
            #else
            material(content)
            #endif
        }
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
    }
}

extension View {
    func readerGlass<S: InsettableShape>(in shape: S, hovering: Bool = false) -> some View {
        modifier(ReaderGlass(shape: shape, hovering: hovering))
    }
}

/// A dropdown whose trigger is a glass surface. The list itself stays the system menu,
/// which is glass on macOS 26 and keeps checkmarks, type-to-select and keyboard navigation.
struct GlassMenu<Content: View>: View {
    let title: String
    var caption: String? = nil
    var symbol: String? = nil
    var compact = false
    @ViewBuilder var content: Content
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu { content } label: { label }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize(horizontal: compact, vertical: true)
            .onHover { hovering = $0 }
            .accessibilityLabel(caption.map { "\($0): \(title)" } ?? title)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if let symbol {
                // A tinted chip keeps the icon legible as a colour cue even when the window is inactive
                // and macOS desaturates control content.
                Image(systemName: symbol).font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(ReaderStyle.accent)
                    .frame(width: compact ? 16 : 22, height: compact ? 16 : 22)
                    .background(ReaderStyle.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
            }
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
            }
            Text(title).font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
                .lineLimit(1).truncationMode(.tail)
            if !compact { Spacer(minLength: 4) }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: compact ? 8 : 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 9 : 11).padding(.vertical, compact ? 4 : 7)
        .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .readerGlass(in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous), hovering: hovering && isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

/// Secondary actions (pager, small toolbar-like buttons) as glass capsules.
struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassCapsule(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct GlassCapsule<Label: View>: View {
        let label: Label
        let pressed: Bool
        @ViewState private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .contentShape(Capsule())
                .readerGlass(in: Capsule(), hovering: hovering && isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(.snappy(duration: 0.15), value: pressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Clickable cards (suggestions, sources): glass with a hover lift.
struct GlassCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        GlassCard(label: configuration.label, pressed: configuration.isPressed, cornerRadius: cornerRadius)
    }

    private struct GlassCard<Label: View>: View {
        let label: Label
        let pressed: Bool
        let cornerRadius: CGFloat
        @ViewState private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .readerGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), hovering: hovering && isEnabled)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ReaderStyle.accent.opacity(hovering && isEnabled ? 0.45 : 0)))
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: hovering)
                .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: pressed)
                .onHover { hovering = $0 }
        }
    }
}

struct ReaderBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Color(nsColor: .windowBackgroundColor)
            } else {
                WindowVibrancy()
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
