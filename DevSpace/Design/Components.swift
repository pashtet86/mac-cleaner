import SwiftUI

/// Quiet surface: solid card color, hairline border, continuous corners.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline)
            }
    }
}

/// Small uppercase label used above figures and sections.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let symbol {
                Glyph(symbol: symbol, tint: tint, size: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.pageTitle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, symbol: String? = nil, tint: Color = .secondary) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// Icon on a soft tinted tile.
struct Glyph: View {
    let symbol: String
    var tint: Color = .secondary
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: .rect(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct Stat: View {
    let label: String
    let value: String
    var caption: String? = nil
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(label)
            Text(value)
                .font(large ? .figure : .figureSmall)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Thin segmented capacity bar.
struct CapacityBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 6

    private let gap: CGFloat = 2
    /// Narrowest a non-empty segment may get, so tiny values stay visible.
    private let minimumSegment: CGFloat = 3
    private let cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.fraction > 0 }
            let widths = Self.widths(
                for: visible.map(\.fraction), total: proxy.size.width, minimum: minimumSegment, gap: gap)
            HStack(spacing: gap) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: widths[index])
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.track)
            .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .frame(height: height)
    }

    /// Proportional widths where every non-empty segment is at least `minimum`
    /// wide (never a hairline); the space is taken from the larger segments.
    static func widths(for fractions: [Double], total: CGFloat, minimum: CGFloat, gap: CGFloat) -> [CGFloat] {
        var widths = fractions.map { max(0, total * CGFloat($0) - gap) }
        let deficit = widths.reduce(0) { $0 + max(0, minimum - $1) }
        let surplus = widths.reduce(0) { $0 + max(0, $1 - minimum) }
        guard deficit > 0, surplus > deficit else { return widths.map { max($0, minimum) } }
        widths = widths.map { width in
            width < minimum ? minimum : width - (width - minimum) / surplus * deficit
        }
        return widths
    }
}

struct LegendDot: View {
    let color: Color
    let label: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
            if let value {
                Text(value).monospacedDigit()
            }
        }
        .font(.caption)
    }
}

// MARK: - Buttons

/// Shared timing for every hover response: quick, never bouncy.
extension Animation {
    static let hover = Animation.easeOut(duration: 0.16)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(Theme.onAccent)
                .background(Theme.accent, in: Capsule())
                // A soft sheen on hover instead of a color change.
                .overlay { Capsule().fill(Theme.onAccent.opacity(isHovered && isEnabled ? 0.1 : 0)) }
                .shadow(color: Theme.accent.opacity(isHovered && isEnabled ? 0.25 : 0), radius: 8, y: 2)
                .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.35)
                .onHover { hovering in withAnimation(.hover) { isHovered = hovering } }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// The shared pill shape for quiet buttons and chips, so they line up side by side.
struct PillModifier: ViewModifier {
    var isPressed = false
    var isHovered = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(isPressed ? 0.1 : (isHovered ? 0.07 : 0.04)), in: Capsule())
            .overlay { Capsule().strokeBorder(isHovered ? Color.primary.opacity(0.16) : Theme.hairline) }
    }
}

extension View {
    func pill(isPressed: Bool = false, isHovered: Bool = false) -> some View {
        modifier(PillModifier(isPressed: isPressed, isHovered: isHovered))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .pill(isPressed: configuration.isPressed, isHovered: isHovered && isEnabled)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering in withAnimation(.hover) { isHovered = hovering } }
        }
    }
}

/// Small icon-only buttons (chevrons, Finder, remove): muted until hovered.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered && isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(3)
                .background(
                    Circle().fill(Color.primary.opacity(isHovered && isEnabled ? 0.07 : 0))
                )
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering in withAnimation(.hover) { isHovered = hovering } }
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

// MARK: - Hover

/// A faint wash behind list rows on hover.
struct HoverRow: ViewModifier {
    var isActive = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle().fill(
                    isActive ? Theme.accent.opacity(0.07) : Color.primary.opacity(isHovered ? 0.035 : 0))
            }
            .onHover { hovering in withAnimation(.hover) { isHovered = hovering } }
    }
}

/// Clickable cards rise slightly and pick up an accent edge on hover.
struct HoverLift: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(isHovered ? 0.28 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 14, y: 6)
            .offset(y: isHovered ? -2 : 0)
            .onHover { hovering in withAnimation(.hover) { isHovered = hovering } }
    }
}

extension View {
    func hoverRow(isActive: Bool = false) -> some View { modifier(HoverRow(isActive: isActive)) }
    func hoverLift() -> some View { modifier(HoverLift()) }
}

/// Selection checkbox that supports a mixed state.
struct SelectionMark: View {
    enum State { case off, mixed, on }
    let state: State

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .off ? Color.clear : Theme.accent)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(state == .off ? Color.primary.opacity(0.25) : Color.clear, lineWidth: 1.2)
            if state != .off {
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
    }
}

struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

/// Wraps children onto new lines, keeping each child on one line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 18
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Muted footnote naming supported items that were not found on this Mac.
struct AlsoSupported: View {
    var title = "Also supported — not found on this Mac"
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(title)
            Text(names.joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
