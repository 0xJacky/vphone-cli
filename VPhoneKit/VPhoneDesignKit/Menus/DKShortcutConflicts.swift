import Foundation

/// Finds shortcuts that more than one item claims. Only one of them can win, and
/// AppKit gives the key to whichever menu comes first in the menu bar, so a
/// clash silently disables the later item's shortcut.
///
/// Alternates count with the shortcut they actually get (their own, or the
/// previous item's plus ⌥). Disabled items count too: they still own the key.
public enum DKShortcutConflicts {
    /// One shortcut and every item that claims it, as "Menu › Submenu › Item" paths
    /// in menu order.
    public struct Conflict: Hashable, Sendable, CustomStringConvertible {
        public let shortcut: DKShortcut
        public let paths: [String]

        public init(shortcut: DKShortcut, paths: [String]) {
            self.shortcut = shortcut
            self.paths = paths
        }

        public var description: String {
            "\(shortcut): \(paths.joined(separator: ", "))"
        }
    }

    /// Clashes across a whole menu bar, or any set of menus that are live at once.
    public static func find(in menus: [DKMenu]) -> [Conflict] {
        var claims: [(DKShortcut, String)] = []
        for menu in menus {
            collect(menu.items, path: [menu.title], into: &claims)
        }
        return conflicts(claims)
    }

    /// Clashes within one menu tree, its submenus included.
    public static func find(in items: [DKMenuItem], menuTitle: String? = nil) -> [Conflict] {
        var claims: [(DKShortcut, String)] = []
        collect(items, path: menuTitle.map { [$0] } ?? [], into: &claims)
        return conflicts(claims)
    }

    private static func collect(_ items: [DKMenuItem], path: [String], into claims: inout [(DKShortcut, String)]) {
        for section in DKMenuLayout(items).sections {
            for row in section.rows {
                claim(row.item, row.shortcut, path: path, into: &claims)
                if let alternate = row.alternate {
                    claim(alternate.item, alternate.shortcut, path: path, into: &claims)
                }
            }
        }
    }

    private static func claim(
        _ item: DKMenuItem,
        _ shortcut: DKShortcut?,
        path: [String],
        into claims: inout [(DKShortcut, String)],
    ) {
        let itemPath = path + [item.title]
        if let shortcut {
            claims.append((shortcut, itemPath.joined(separator: " › ")))
        }
        if item.kind == .submenu {
            collect(item.children, path: itemPath, into: &claims)
        }
    }

    private static func conflicts(_ claims: [(DKShortcut, String)]) -> [Conflict] {
        var order: [DKShortcut] = []
        var paths: [DKShortcut: [String]] = [:]
        for (shortcut, path) in claims {
            if paths[shortcut] == nil {
                order.append(shortcut)
            }
            paths[shortcut, default: []].append(path)
        }
        return order.compactMap { shortcut in
            guard let claimed = paths[shortcut], claimed.count > 1 else { return nil }
            return Conflict(shortcut: shortcut, paths: claimed)
        }
    }
}
