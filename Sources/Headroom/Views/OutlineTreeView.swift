import SwiftUI
import AppKit

/// Virtualized folder tree on NSOutlineView: only visible rows exist, cells are recycled,
/// so expanding a 150k-entry node_modules costs nothing at render time.
struct OutlineTreeView: NSViewRepresentable {
    @EnvironmentObject var state: AppState
    @Environment(\.requestDelete) private var requestDelete

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = KeyOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.rowHeight = 22
        outline.rowSizeStyle = .default
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.allowsColumnReordering = true
        outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = 14
        outline.floatsGroupRows = false
        outline.autosaveName = "Headroom.outline"
        outline.autosaveTableColumns = true

        func col(_ id: String, _ title: String, _ width: CGFloat, min: CGFloat, sortKey: String? = nil) -> NSTableColumn {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = width
            c.minWidth = min
            if let sortKey { c.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: false) }
            return c
        }
        let name = col("name", "Name", 320, min: 160, sortKey: "name")
        name.resizingMask = .autoresizingMask
        outline.addTableColumn(name)
        outline.outlineTableColumn = name
        outline.addTableColumn(col("size", "Size", 190, min: 120, sortKey: "size"))
        outline.addTableColumn(col("pct", "% of parent", 80, min: 60, sortKey: "size"))
        outline.addTableColumn(col("files", "Files", 80, min: 50, sortKey: "files"))
        outline.addTableColumn(col("safety", "Safe to delete?", 120, min: 90))
        outline.addTableColumn(col("category", "Category", 110, min: 80))
        outline.addTableColumn(col("modified", "Modified", 100, min: 80, sortKey: "modified"))
        outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]

        let coord = context.coordinator
        outline.dataSource = coord
        outline.delegate = coord
        outline.onDeleteKey = { [weak coord] in coord?.deleteSelection() }
        outline.target = coord
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        coord.outline = outline

        let menu = NSMenu()
        menu.delegate = coord
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.requestDelete = requestDelete
        coord.reveal = { [state] in state.revealInFinder($0) }
        coord.onSelectionChange = { [state] ids, node in
            state.selection = ids
            if let node { state.selectedNode = node }
        }
        coord.deleteLabel = state.deleteMode.actionLabel

        if coord.root !== state.root || coord.treeVersion != state.treeVersion {
            coord.root = state.root
            coord.treeVersion = state.treeVersion
            coord.outline?.reloadData()
            if let root = state.root, root.children.count <= 400 {
                // small trees: open the first level so the view isn't a single collapsed row
                coord.outline?.expandItem(nil, expandChildren: false)
            }
        }
        // Mirror external selection (treemap / category clicks) onto visible rows.
        coord.applyExternalSelection(state.selection)
        // Animated-removal hook (re-installed each update so it always targets the live view).
        state.treeRemovalHandler = { [weak coord] nodes in coord?.animateRemoval(nodes) ?? false }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        var root: FileNode?
        var treeVersion = -1
        var requestDelete: RequestDeleteAction?
        var reveal: ((FileNode) -> Void)?
        var onSelectionChange: ((Set<FileNode.ID>, FileNode?) -> Void)?
        var deleteLabel = "Delete…"
        private var suppressSelectionCallback = false
        private var lastPushedSelection: Set<FileNode.ID> = []

        // MARK: data source

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return root.map { sortedChildren(of: $0).count } ?? 0 }
            guard let node = item as? FileNode, node.isDirectory, !node.isPackage else { return 0 }
            return sortedChildren(of: node).count
        }
        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            sortedChildren(of: (item as? FileNode) ?? root!)[index]
        }
        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let n = item as? FileNode else { return false }
            return n.isDirectory && !n.isPackage && !n.children.isEmpty
        }

        func outlineView(_ ov: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let root, let d = ov.sortDescriptors.first, let key = d.key else { return }
            let order: SortOrder = d.ascending ? .forward : .reverse
            let comparators: [KeyPathComparator<FileNode>]
            switch key {
            case "name": comparators = [KeyPathComparator(\FileNode.name, comparator: .localizedStandard, order: order)]
            case "files": comparators = [KeyPathComparator(\FileNode.fileCount, order: order)]
            case "modified": comparators = [KeyPathComparator(\FileNode.modifiedForSort, order: order)]
            default: comparators = [KeyPathComparator(\FileNode.allocatedSize, order: order)]
            }
            let selected = ov.selectedRowIndexes.compactMap { ov.item(atRow: $0) as? FileNode }
            sortComparators = comparators
            sortGeneration += 1
            ov.reloadData()
            reselect(selected)
        }

        private var sortComparators: [KeyPathComparator<FileNode>] = []
        private var sortGeneration = 0

        /// Children of `node`, sorted for the active header choice (sorted on first access).
        private func sortedChildren(of node: FileNode) -> [FileNode] {
            if sortGeneration > 0 { node.ensureSorted(generation: sortGeneration, using: sortComparators) }
            return node.children
        }

        // MARK: cells

        func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode, let id = tableColumn?.identifier.rawValue else { return nil }
            switch id {
            case "name":
                let cell: NameCell = dequeue(ov, "name") { NameCell() }
                cell.configure(node)
                return cell
            case "size":
                let cell: SizeBarCell = dequeue(ov, "size") { SizeBarCell() }
                cell.configure(fraction: node.shareOfParent, label: node.allocatedSize.humanBytes,
                               color: node.isDirectory && !node.isPackage ? .controlAccentColor : NSColor(node.effectiveCategory.color))
                return cell
            case "pct":
                return textCell(ov, "pct", String(format: "%.1f%%", node.shareOfParent * 100), secondary: true, mono: true, align: .right)
            case "files":
                return textCell(ov, "files", node.isDirectory ? node.fileCount.formatted() : "", secondary: true, mono: true, align: .right)
            case "safety":
                let cell: BadgeCell = dequeue(ov, "safety") { BadgeCell() }
                cell.configure(SafetyKB.info(for: node))
                return cell
            case "category":
                let show = !(node.isDirectory && !node.isPackage && node.category == nil)
                return textCell(ov, "category", show ? node.effectiveCategory.title : "", secondary: true)
            case "modified":
                return textCell(ov, "modified", node.modified.map { Self.dateFormatter.string(from: $0) } ?? "", secondary: true)
            default: return nil
            }
        }

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
        }()

        private func dequeue<T: NSView>(_ ov: NSOutlineView, _ id: String, make: () -> T) -> T {
            let ident = NSUserInterfaceItemIdentifier(id)
            if let v = ov.makeView(withIdentifier: ident, owner: nil) as? T { return v }
            let v = make(); v.identifier = ident; return v
        }

        private func textCell(_ ov: NSOutlineView, _ id: String, _ text: String, secondary: Bool = false,
                              mono: Bool = false, align: NSTextAlignment = .left) -> NSView {
            let cell = dequeue(ov, id) { () -> NSTableCellView in
                let c = NSTableCellView()
                let tf = NSTextField(labelWithString: "")
                tf.lineBreakMode = .byTruncatingTail
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(tf); c.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }
            cell.textField?.stringValue = text
            cell.textField?.textColor = secondary ? .secondaryLabelColor : .labelColor
            cell.textField?.font = mono ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.alignment = align
            return cell
        }

        // MARK: selection

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionCallback, let ov = outline else { return }
            let nodes = ov.selectedRowIndexes.compactMap { ov.item(atRow: $0) as? FileNode }
            let ids = Set(nodes.map(\.id))
            lastPushedSelection = ids
            onSelectionChange?(ids, nodes.last)
        }

        func applyExternalSelection(_ ids: Set<FileNode.ID>) {
            guard let ov = outline, ids != lastPushedSelection else { return }
            lastPushedSelection = ids
            var rows = IndexSet()
            for row in 0..<ov.numberOfRows {
                if let n = ov.item(atRow: row) as? FileNode, ids.contains(n.id) { rows.insert(row) }
            }
            suppressSelectionCallback = true
            ov.selectRowIndexes(rows, byExtendingSelection: false)
            if let first = rows.first { ov.scrollRowToVisible(first) }
            suppressSelectionCallback = false
        }

        private func reselect(_ nodes: [FileNode]) {
            guard let ov = outline else { return }
            var rows = IndexSet()
            for n in nodes { let r = ov.row(forItem: n); if r >= 0 { rows.insert(r) } }
            suppressSelectionCallback = true
            ov.selectRowIndexes(rows, byExtendingSelection: false)
            suppressSelectionCallback = false
        }

        var selectedNodes: [FileNode] {
            guard let ov = outline else { return [] }
            return ov.selectedRowIndexes.compactMap { ov.item(atRow: $0) as? FileNode }
        }

        func deleteSelection() {
            let nodes = selectedNodes
            if !nodes.isEmpty { requestDelete?(nodes) }
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let ov = outline, ov.clickedRow >= 0, let n = ov.item(atRow: ov.clickedRow) as? FileNode else { return }
            if ov.isExpandable(n) {
                ov.isItemExpanded(n) ? ov.animator().collapseItem(n) : ov.animator().expandItem(n)
            } else {
                reveal?(n)
            }
        }

        // MARK: context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let ov = outline, ov.clickedRow >= 0, let node = ov.item(atRow: ov.clickedRow) as? FileNode else { return }
            let targets = ov.selectedRowIndexes.contains(ov.clickedRow) ? selectedNodes : [node]
            let title = NSMenuItem(title: targets.count == 1 ? node.name : "\(targets.count) items", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealAction(_:)), keyEquivalent: "")
            revealItem.target = self; revealItem.representedObject = node
            menu.addItem(revealItem)
            if ov.isExpandable(node) {
                let expandAll = NSMenuItem(title: "Expand All", action: #selector(expandAllAction(_:)), keyEquivalent: "")
                expandAll.target = self; expandAll.representedObject = node
                menu.addItem(expandAll)
            }
            menu.addItem(.separator())
            let del = NSMenuItem(title: deleteLabel, action: #selector(deleteAction(_:)), keyEquivalent: "")
            del.target = self; del.representedObject = targets
            menu.addItem(del)
        }
        @objc private func revealAction(_ s: NSMenuItem) { if let n = s.representedObject as? FileNode { reveal?(n) } }
        @objc private func expandAllAction(_ s: NSMenuItem) {
            if let n = s.representedObject as? FileNode { outline?.animator().expandItem(n, expandChildren: true) }
        }
        @objc private func deleteAction(_ s: NSMenuItem) { if let n = s.representedObject as? [FileNode] { requestDelete?(n) } }

        // MARK: animated removal (called by AppState.delete)

        /// Removes the nodes from the model and the view with a slide-up animation.
        /// Returns false if the view isn't showing this tree, so the caller removes plainly.
        func animateRemoval(_ nodes: [FileNode]) -> Bool {
            guard let ov = outline, let root else { return false }
            ov.beginUpdates()
            for n in nodes {
                guard let parent = n.parent else { continue }
                if let idx = parent.children.firstIndex(where: { $0 === n }) {
                    parent.removeChild(n)
                    let parentItem: Any? = parent === root ? nil : parent
                    if parent === root || ov.isItemExpanded(parent) {
                        ov.removeItems(at: IndexSet(integer: idx), inParent: parentItem, withAnimation: [.slideUp, .effectFade])
                    }
                }
            }
            ov.endUpdates()
            // Sizes of ancestors changed → refresh visible rows without a full reload.
            let visible = ov.rows(in: ov.visibleRect)
            if visible.length > 0 {
                ov.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                              columnIndexes: IndexSet(integersIn: 0..<ov.numberOfColumns))
            }
            return true
        }
    }
}

extension FileNode {
    var modifiedForSort: Date { modified ?? .distantPast }
}

// MARK: - Outline subclass: delete key

final class KeyOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDeleteKey?(); return }   // backspace / forward delete
        super.keyDown(with: event)
    }
}

// MARK: - Cells

final class NameCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        addSubview(icon); addSubview(label)
        imageView = icon; textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ node: FileNode) {
        label.stringValue = node.name
        icon.image = NSImage(systemSymbolName: node.iconName, accessibilityDescription: nil)
        icon.contentTintColor = node.isDirectory && !node.isPackage ? .controlAccentColor : NSColor(node.effectiveCategory.color)
        toolTip = node.path
    }
}

final class SizeBarCell: NSTableCellView {
    private let bar = SizeBarView()
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        bar.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        addSubview(bar); addSubview(label); textField = label
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 10),
            label.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            label.widthAnchor.constraint(equalToConstant: 72),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(fraction: Double, label text: String, color: NSColor) {
        bar.fraction = fraction; bar.color = color; bar.needsDisplay = true
        label.stringValue = text
    }
}

final class SizeBarView: NSView {
    var fraction: Double = 0
    var color: NSColor = .controlAccentColor
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill(); track.fill()
        let w = max(2, bounds.width * CGFloat(min(1, max(0, fraction))))
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.75).setFill(); fill.fill()
    }
}

final class BadgeCell: NSTableCellView {
    private let pill = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.layer?.borderWidth = 0.5
        [pill, icon, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        label.font = .systemFont(ofSize: 10.5, weight: .regular)
        icon.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        addSubview(pill); pill.addSubview(icon); pill.addSubview(label)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 16),
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ info: SafetyInfo) {
        let c = info.level == .unknown ? NSColor.secondaryLabelColor : NSColor(info.level.color)
        icon.image = NSImage(systemSymbolName: info.level.symbol, accessibilityDescription: nil)
        icon.contentTintColor = c
        label.stringValue = info.level.short
        label.textColor = c
        pill.layer?.backgroundColor = (info.level == .unknown ? NSColor.clear : c.withAlphaComponent(0.12)).cgColor
        pill.layer?.borderColor = (info.level == .unknown ? NSColor.clear : c.withAlphaComponent(0.28)).cgColor
        toolTip = info.level.title + "\n\n" + info.what + "\n\n" + info.advice
    }
}
