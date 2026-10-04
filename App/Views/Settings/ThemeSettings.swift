import AppKit
import GreedifyKit
import SwiftUI

/// Settings → Themes: the built-in and curated themes (curated skins spec §4). Debug builds also list the recipes
/// being tuned (`dev.`), which reload as their files change.
struct ThemeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.themes
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    ForEach(store.entries) { entry in
                        ThemeSwatch(entry: entry, selected: entry.id == store.current.id)
                            .onTapGesture { if entry.theme != nil { model.selectTheme(entry.id) } }
                    }
                }
                .padding(4)
            }
            .frame(height: 290)
            #if DEBUG
            HStack {
                Button("Show Recipes Folder") { model.showRecipesFolder() }
                Text("Recipes here load as dev themes and reload when saved.").font(.caption).foregroundStyle(.secondary)
            }
            #endif
        }
        .padding(20)
        .modifier(BannerOverlay())
        .onAppear { model.reloadThemes() }
    }
}

/// A 120×80 preview of a theme: surface strip, background, title text, accent pill and a line of secondary text.
struct ThemeSwatch: View {
    let entry: ThemeEntry
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                preview.frame(width: 120, height: 80)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(5)
                }
            }
            Text(entry.name).font(.caption).lineLimit(1)
        }
        .hoverHelp(entry.error ?? entry.theme?.source ?? entry.name)
        .opacity(entry.theme == nil ? 0.5 : 1)
    }

    @ViewBuilder var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if entry.theme == nil {
            shape.fill(.quaternary).overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary))
        } else {
            let t = ResolvedTheme(entry)
            HStack(spacing: 0) {
                t.surface.frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aa").font(t.font(15, weight: t.titleWeight)).foregroundStyle(t.text)
                    RoundedRectangle(cornerRadius: min(t.buttonRadius, 6)).fill(t.accent).frame(width: 44, height: 12)
                    RoundedRectangle(cornerRadius: 2).fill(t.textSecondary).frame(width: 60, height: 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(t.background)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1))
        }
    }
}
