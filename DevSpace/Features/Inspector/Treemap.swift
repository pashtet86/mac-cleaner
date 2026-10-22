import SwiftUI

/// Squarified treemap layout (Bruls, Huizing, van Wijk): keeps tiles close to square.
nonisolated enum Treemap {
    /// - Parameter values: positive, sorted largest first.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowSum = areas[start]
            while end < areas.count,
                worst(areas[start...end], sum: rowSum + areas[end], side: side)
                    <= worst(areas[start..<end], sum: rowSum, side: side)
            {
                rowSum += areas[end]
                end += 1
            }

            let thickness = CGFloat(rowSum / side)
            var offset: CGFloat = 0
            if remaining.width >= remaining.height {
                for index in start..<end {
                    let height = CGFloat(areas[index]) / thickness
                    result[index] = CGRect(
                        x: remaining.minX, y: remaining.minY + offset, width: thickness, height: height)
                    offset += height
                }
                remaining = CGRect(
                    x: remaining.minX + thickness, y: remaining.minY,
                    width: max(0, remaining.width - thickness), height: remaining.height)
            } else {
                for index in start..<end {
                    let width = CGFloat(areas[index]) / thickness
                    result[index] = CGRect(
                        x: remaining.minX + offset, y: remaining.minY, width: width, height: thickness)
                    offset += width
                }
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + thickness,
                    width: remaining.width, height: max(0, remaining.height - thickness))
            }
            start = end
        }
        return result
    }

    /// Worst aspect ratio in a row — the quantity squarify keeps small.
    private static func worst(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        let sideSquared = side * side
        let sumSquared = sum * sum
        return row.reduce(0) { worst, area in
            max(worst, max(sideSquared * area / sumSquared, sumSquared / (sideSquared * area)))
        }
    }
}

/// One rectangle of the mosaic: a node, or the "smaller items" remainder.
struct TreemapTile: Identifiable {
    let node: InspectorNode?
    let rect: CGRect
    let size: Int64
    let safety: Safety
    var id: String { node.map { "\($0.id.hashValue)" } ?? "rest" }

    var title: String { node?.name ?? "Smaller items" }

    /// Tiles for the children of `node`: items under 0.3% of the area join one remainder tile.
    static func tiles(for node: InspectorNode, in rect: CGRect, limit: Int = 80) -> [TreemapTile] {
        let total = Double(max(node.size, 1))
        let shown = node.children.prefix(limit).filter { Double($0.size) / total >= 0.003 }
        let rest = node.size - shown.reduce(0) { $0 + $1.size }
        var values = shown.map { Double($0.size) }
        if rest > 0 { values.append(Double(rest)) }
        // The remainder goes last regardless of size so real items keep their order.
        let rects = Treemap.layout(values.sorted(by: >), in: rect)
        let order = values.indices.sorted { values[$0] > values[$1] }
        var tiles: [TreemapTile] = []
        for (position, index) in order.enumerated() {
            if index < shown.count {
                let child = shown[index]
                tiles.append(
                    TreemapTile(node: child, rect: rects[position], size: child.size, safety: child.displaySafety))
            } else {
                tiles.append(TreemapTile(node: nil, rect: rects[position], size: rest, safety: .personal))
            }
        }
        return tiles
    }
}

struct TreemapView: View {
    let node: InspectorNode
    let isSelected: (InspectorNode) -> Bool
    let focused: InspectorNode?
    let onFocus: (InspectorNode?) -> Void
    let onOpen: (InspectorNode) -> Void
    @State private var hover: (id: ObjectIdentifier, location: CGPoint)?

    /// A top-level tile with the mosaic of its own children, laid out once per render and
    /// shared by drawing and hit testing so the pointer always means what you see.
    private struct Block {
        let tile: TreemapTile
        let rect: CGRect
        let inner: [TreemapTile]
    }

    var body: some View {
        GeometryReader { proxy in
            let blocks = Self.layout(node, in: CGRect(origin: .zero, size: proxy.size))
            Canvas { context, _ in
                for block in blocks { draw(block, in: &context) }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    hover = Self.hit(location, in: blocks).map { (ObjectIdentifier($0), location) }
                case .ended:
                    hover = nil
                }
            }
            .gesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    guard let target = Self.hit(value.location, in: blocks) else { return }
                    if target.canOpen { onOpen(target) } else { onFocus(target) }
                }
                .exclusively(
                    before: SpatialTapGesture().onEnded { value in
                        onFocus(Self.hit(value.location, in: blocks))
                    })
            )
            .overlay(alignment: .topLeading) {
                if let hover, let target = Self.node(hover.id, in: blocks) {
                    tooltip(for: target)
                        .offset(tooltipOffset(at: hover.location, in: proxy.size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.hover, value: hover?.id)
        }
    }

    // MARK: - Layout & hit testing

    private static func layout(_ node: InspectorNode, in bounds: CGRect) -> [Block] {
        TreemapTile.tiles(for: node, in: bounds).map { tile in
            let rect = tile.rect.insetBy(dx: 1, dy: 1)
            guard let child = tile.node, !child.children.isEmpty, rect.width > 40, rect.height > 40 else {
                return Block(tile: tile, rect: rect, inner: [])
            }
            let labelSpace: CGFloat = rect.height > 70 ? 34 : 4
            let area = CGRect(
                x: rect.minX + 4, y: rect.minY + labelSpace, width: rect.width - 8,
                height: rect.height - labelSpace - 4)
            guard area.width > 8, area.height > 8 else { return Block(tile: tile, rect: rect, inner: []) }
            let inner = TreemapTile.tiles(for: child, in: area, limit: 24).filter { $0.node != nil }
            return Block(tile: tile, rect: rect, inner: inner)
        }
    }

    /// The innermost item under the point: a sub-folder inside a tile wins over the tile.
    private static func hit(_ point: CGPoint, in blocks: [Block]) -> InspectorNode? {
        guard let block = blocks.first(where: { $0.rect.contains(point) }) else { return nil }
        return block.inner.first { $0.rect.contains(point) }?.node ?? block.tile.node
    }

    private static func node(_ id: ObjectIdentifier, in blocks: [Block]) -> InspectorNode? {
        for block in blocks {
            if let node = block.tile.node, ObjectIdentifier(node) == id { return node }
            if let node = block.inner.compactMap(\.node).first(where: { ObjectIdentifier($0) == id }) { return node }
        }
        return nil
    }

    // MARK: - Tooltip

    private func tooltip(for node: InspectorNode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder" : "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(node.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(node.size.formattedBytes).monospacedDigit()
                Circle().fill(node.displaySafety.tone).frame(width: 6, height: 6)
                Text(node.displaySafety.label).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            if node.canOpen {
                Text("Double-click to open").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize()
        .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline) }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    /// Follows the pointer and flips to stay inside the map near the right and bottom edges.
    private func tooltipOffset(at point: CGPoint, in size: CGSize) -> CGSize {
        let width: CGFloat = 240, height: CGFloat = 64, gap: CGFloat = 14
        let x = point.x + gap + width > size.width ? point.x - gap - width : point.x + gap
        let y = point.y + gap + height > size.height ? point.y - gap - height : point.y + gap
        return CGSize(width: max(0, x), height: max(0, y))
    }

    // MARK: - Drawing

    private func isHovered(_ node: InspectorNode?) -> Bool {
        guard let node, let hover else { return false }
        return ObjectIdentifier(node) == hover.id
    }

    private func draw(_ block: Block, in context: inout GraphicsContext) {
        let tile = block.tile
        let rect = block.rect
        guard rect.width > 1, rect.height > 1 else { return }
        let shape = Path(roundedRect: rect, cornerRadius: 2)
        let isRest = tile.node == nil
        // Leaves carry the full tone; folders a light wash under their own mosaic.
        let wash = isRest ? 0.12 : (block.inner.isEmpty ? 0.5 : 0.18)
        context.fill(shape, with: .color(tile.safety.tone.opacity(isHovered(tile.node) ? wash + 0.1 : wash)))

        // Inner mosaic: the folder's own children, tinted by their safety; each is hoverable.
        for sub in block.inner {
            let subRect = sub.rect.insetBy(dx: 0.75, dy: 0.75)
            guard subRect.width > 1, subRect.height > 1, let subNode = sub.node else { continue }
            let hovered = isHovered(subNode)
            context.fill(Path(subRect), with: .color(sub.safety.tone.opacity(hovered ? 0.75 : 0.55)))
            if isSelected(subNode) {
                context.stroke(Path(subRect), with: .color(Theme.accent), lineWidth: 2)
            } else if subNode === focused {
                context.stroke(Path(subRect), with: .color(Theme.accent.opacity(0.8)), lineWidth: 1.5)
            } else if hovered {
                context.stroke(Path(subRect), with: .color(Color.primary.opacity(0.5)), lineWidth: 1.25)
            }
        }

        if let node = tile.node, isSelected(node) {
            context.stroke(shape, with: .color(Theme.accent), lineWidth: 2.5)
        } else if let node = tile.node, node === focused {
            context.stroke(shape, with: .color(Theme.accent.opacity(0.8)), lineWidth: 2)
        } else if isHovered(tile.node) {
            context.stroke(shape, with: .color(Color.primary.opacity(0.35)), lineWidth: 1.5)
        }

        guard rect.width > 64, rect.height > 30 else { return }
        var origin = CGPoint(x: rect.minX + 8, y: rect.minY + 6)
        if let node = tile.node, isSelected(node) {
            context.draw(
                Text(Image(systemName: "checkmark.circle.fill")).font(.system(size: 12)).foregroundStyle(Theme.accent),
                at: CGPoint(x: rect.maxX - 12, y: rect.minY + 12))
        }
        let name = Text(tile.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary)
        context.draw(
            context.resolve(name), in: CGRect(origin: origin, size: CGSize(width: rect.width - 28, height: 14)))
        origin.y += 14
        let size = Text(tile.size.formattedBytes).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        context.draw(
            context.resolve(size), in: CGRect(origin: origin, size: CGSize(width: rect.width - 16, height: 13)))
    }
}
