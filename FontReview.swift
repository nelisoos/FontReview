import SwiftUI
import CoreText

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
    let families = loadUserFonts()

    var filtered: [Family] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return families }
        return families.filter { f in
            f.id.localizedCaseInsensitiveContains(q) ||
            f.items.contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
    }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
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
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
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
