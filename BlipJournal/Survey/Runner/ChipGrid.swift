import BlipJournalCore
import SwiftUI
struct ChipGrid: View { let question: Question; let value: AnswerValue?; let onChange: (AnswerValue?) -> Void; let onAdd: () -> Void; private var selected: Set<String> { switch value { case .single(let id): [id]; case .multi(let ids): Set(ids); default: [] } }; var body: some View { FlexibleLayout { ForEach(question.activeOptions) { option in Button { toggle(option.id) } label: { Text(option.label).padding(.horizontal, 14).frame(minHeight: 44).background(selected.contains(option.id) ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule()).foregroundStyle(selected.contains(option.id) ? .white : .primary) }.accessibilityLabel("\(option.label), \(selected.contains(option.id) ? "selected" : "not selected")").accessibilityAddTraits(selected.contains(option.id) ? .isSelected : []) }; if question.allowsCustomOptions { Button("Add…", action: onAdd).frame(minHeight: 44) } } }; private func toggle(_ id: String) { if question.kind == .singleChoice { onChange(selected.contains(id) ? nil : .single(optionId: id)) } else { var ids = Array(selected); if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }; onChange(ids.isEmpty ? nil : .multi(optionIds: ids)) } } }
private struct FlexibleLayout: Layout {
    private let spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? 300, subviews: subviews)
        return CGSize(width: proposal.width ?? 300, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items { item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size)); x += item.size.width + spacing }
            y += row.height + spacing
        }
    }
    private struct Row { var items: [(view: LayoutSubviews.Element, size: CGSize)] = []; var height: CGFloat = 0 }
    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var result: [Row] = []; var row = Row(); var used: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if !row.items.isEmpty && used + spacing + size.width > width { result.append(row); row = Row(); used = 0 }
            row.items.append((view, size)); used += (row.items.count == 1 ? 0 : spacing) + size.width; row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { result.append(row) }; return result
    }
}
