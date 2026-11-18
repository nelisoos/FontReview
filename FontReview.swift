import SwiftUI
import CoreText
import UniformTypeIdentifiers

struct FontItem: Identifiable {
    let id: String     // PostScript name
    let name: String   // display name
    let family: String
}

struct Family: Identifiable {
    let id: String
    let items: [FontItem]
    var rep: FontItem {
        items.first { $0.name.lowercased().hasSuffix("regular") } ?? items.first { $0.name == id } ?? items[0]
    }
}

func loadUserFonts() -> [Family] {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts")
    guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var seen = Set<String>()
    var items: [FontItem] = []
    for case let url as URL in en {
        guard ["ttf", "otf", "ttc", "otc"].contains(url.pathExtension.lowercased()) else { continue }
        let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        for d in descs {
            guard let ps = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String,
                  !seen.contains(ps) else { continue }
            let name = CTFontDescriptorCopyAttribute(d, kCTFontDisplayNameAttribute) as? String ?? ps
            let fam = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? name
            seen.insert(ps)
            items.append(FontItem(id: ps, name: name, family: fam))
        }
    }
    return Dictionary(grouping: items, by: { $0.family })
        .map { Family(id: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
        .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
}

final class Model: ObservableObject {
    @Published var text = ""
    @Published var search = ""
    @Published var expanded = Set<String>()
    @Published var size: Double = 28
    @Published var families: [Family] = loadUserFonts()
    @Published var status = ""
    @Published var detail: FontItem?

    var filtered: [Family] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return families }
        return families.filter { f in
            f.id.localizedCaseInsensitiveContains(q) ||
            f.items.contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
    }

    func fontFiles(_ urls: [URL]) -> [URL] {
        let exts = ["ttf", "otf", "ttc", "otc"]
        var out: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                if let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil) {
                    for case let f as URL in en where exts.contains(f.pathExtension.lowercased()) { out.append(f) }
                }
            } else if exts.contains(u.pathExtension.lowercased()) {
                out.append(u)
            }
        }
        return out
    }

    func install(_ urls: [URL]) {
        let files = fontFiles(urls)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var ok = 0, skipped = 0
        for f in files {
            let dest = dir.appendingPathComponent(f.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { skipped += 1; continue }
            do {
                try FileManager.default.copyItem(at: f, to: dest)
                CTFontManagerRegisterFontsForURL(dest as CFURL, .process, nil)
                ok += 1
            } catch { skipped += 1 }
        }
        families = loadUserFonts()
        status = files.isEmpty ? "No font files found" : "Installed \(ok), skipped \(skipped)"
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK { install(panel.urls) }
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) {
                    lock.lock(); urls.append(u); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { self.install(urls) }
    }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

struct GlyphInfo: Identifiable {
    let id: Int
    let name: String
    var isOrnament: Bool { name.lowercased().hasPrefix("orn") }
}

struct GlyphShape: Shape {
    let font: CTFont
    let glyph: CGGlyph

    func path(in rect: CGRect) -> Path {
        guard let cg = CTFontCreatePathForGlyph(font, glyph, nil) else { return Path() }
        let b = cg.boundingBoxOfPath
        guard b.width > 0, b.height > 0 else { return Path() }
        var s = min(rect.width, rect.height) * 0.6 / 100   // font is created at 100pt
        if b.width * s > rect.width * 0.9 { s = rect.width * 0.9 / b.width }
        if b.height * s > rect.height * 0.9 { s = rect.height * 0.9 / b.height }
        var ty = rect.minY + rect.height * 0.7
        let top = ty - b.maxY * s
        let bottom = ty - b.minY * s
        if top < rect.minY + rect.height * 0.05 || bottom > rect.maxY - rect.height * 0.05 {
            ty = rect.midY + b.midY * s
        }
        let t = CGAffineTransform(translationX: rect.midX - b.midX * s, y: ty).scaledBy(x: s, y: -s)
        return Path(cg).applying(t)
    }
}

final class GlyphModel: ObservableObject {
    let ct: CTFont
    let glyphs: [GlyphInfo]
    @Published var search = ""
    @Published var selected: GlyphInfo?

    init(ps: String) {
        ct = CTFontCreateWithName(ps as CFString, 100, nil)
        let cg = CTFontCopyGraphicsFont(ct, nil)
        let all = (0..<cg.numberOfGlyphs).map { i -> GlyphInfo in
            let n = cg.name(for: CGGlyph(i)).map { $0 as String } ?? "gid\(i)"
            return GlyphInfo(id: i, name: n)
        }
        // regular glyphs first, ornaments (orn*) at the end, original order kept
        glyphs = all.filter { !$0.isOrnament } + all.filter { $0.isOrnament }
    }

    var ornamentCount: Int { glyphs.filter { $0.isOrnament }.count }

    var filtered: [GlyphInfo] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return glyphs.filter { g in
            q.isEmpty || g.name.localizedCaseInsensitiveContains(q)
        }
    }
}

struct GlyphBookView: View {
    let item: FontItem
    let close: () -> Void
    @StateObject private var g: GlyphModel

    init(item: FontItem, close: @escaping () -> Void) {
        self.item = item
        self.close = close
        _g = StateObject(wrappedValue: GlyphModel(ps: item.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    Text(g.ornamentCount > 0 ? "\(g.glyphs.count) glyphs, \(g.ornamentCount) ornaments at the end" : "\(g.glyphs.count) glyphs").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { close() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            HStack {
                TextField("Glyph name", text: $g.search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 72), spacing: 6)], spacing: 6) {
                    ForEach(g.filtered) { gl in
                        GlyphShape(font: g.ct, glyph: CGGlyph(gl.id))
                            .fill(Color.primary)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Rectangle().stroke(
                                    g.selected?.id == gl.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: g.selected?.id == gl.id ? 2 : 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { g.selected = gl }
                    }
                }
                .padding(12)
            }
            Divider()
            HStack(spacing: 16) {
                if let sel = g.selected {
                    GlyphShape(font: g.ct, glyph: CGGlyph(sel.id))
                        .fill(Color.primary)
                        .frame(width: 100, height: 100)
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sel.name).font(.headline).textSelection(.enabled)
                        Text("Glyph index \(sel.id)").foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a glyph").foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(height: 124)
        }
        .frame(minWidth: 720, minHeight: 600)
    }
}

struct ContentView: View {
    @StateObject private var m = Model()
    static let defaultSize: Double = 28

    var body: some View {
        NavigationSplitView {
            List {
                Section("Search") {
                    TextField("Font name", text: $m.search)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Text("\(m.filtered.count) of \(m.families.count) families")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Preview text") {
                    TextField("Empty = font name", text: $m.text)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                Section("Size") {
                    Slider(value: $m.size, in: 12...96, step: 1)
                    HStack {
                        Text("\(Int(m.size)) pt").foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") { m.size = ContentView.defaultSize }
                            .disabled(m.size == ContentView.defaultSize)
                    }
                }
                Section("Install") {
                    Button("Install Fonts…") { m.pick() }
                    Text("or drop font files / folders onto the list")
                        .font(.caption).foregroundColor(.secondary)
                    if !m.status.isEmpty {
                        Text(m.status).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(m.filtered) { fam in
                        let multi = fam.items.count > 1
                        let open = m.expanded.contains(fam.id)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                            Button { if multi { m.toggle(fam.id) } } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: open ? "chevron.down" : "chevron.right")
                                        .frame(width: 14)
                                        .opacity(multi ? 1 : 0)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if !m.text.isEmpty {
                                            Text(fam.id).font(.caption).foregroundColor(.secondary)
                                        }
                                        Text(m.text.isEmpty ? fam.id : m.text)
                                            .font(.custom(fam.rep.id, size: m.size))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if multi { Text("\(fam.items.count)").foregroundColor(.secondary) }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button("Details") { m.detail = fam.rep }
                                .padding(.trailing, 12)
                            }
                            if multi && open {
                                ForEach(fam.items) { it in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.name).font(.caption).foregroundColor(.secondary)
                                        Text(m.text.isEmpty ? it.name : m.text)
                                            .font(.custom(it.id, size: max(m.size - 4, 8)))
                                            .lineLimit(2)
                                    }
                                    .padding(.leading, 34)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .topTrailing) {
                                        Button("Details") { m.detail = it }
                                            .padding(.trailing, 12)
                                            .padding(.top, 6)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                m.handleDrop(providers)
                return true
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(item: $m.detail) { it in
            GlyphBookView(item: it) { m.detail = nil }
        }
    }
}

@main
struct FontReviewApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup("FontReview") { ContentView() }
    }
}
