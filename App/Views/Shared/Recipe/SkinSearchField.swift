import GreedifyKit
import SwiftUI

/// A framed skin's search field, at the top of its sidebar: the LCD's material in a sunken bevel, in the LCD's
/// colours, instead of AppKit's `.searchable` field (which can't be restyled). It drives the same search, and the
/// window's search focus (⌘K) lands here.
struct SkinSearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var focus: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var search = model.search
        let lcd = theme.style?.lcd
        let ink = lcd?.text.map { Color($0) } ?? theme.text
        let info = lcd?.info.map { Color($0) } ?? theme.textSecondary
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .bold)).foregroundStyle(info)
            TextField("Search", text: $search.query, prompt: Text("Search").foregroundStyle(info.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(theme.listFont())
                .foregroundStyle(ink)
                .focused(focus)
                .onExitCommand { search.query = "" }
            if !search.query.isEmpty {
                Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(info)
                    .accessibilityLabel(Text("Clear Search"))
            }
        }
        .tint(ink) // the caret
        .padding(.horizontal, 7)
        .frame(height: 22)
        .recipeSurface(lcd?.material ?? .solid(.black), bevel: lcd?.bevel, radius: CGFloat(lcd?.radius ?? 0))
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}
