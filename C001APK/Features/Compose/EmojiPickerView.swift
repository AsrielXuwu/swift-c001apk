import SwiftUI

public struct EmojiPickerView: View {
    public let onSelect: (String) -> Void

    @State private var searchText = ""

    public init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    private var filteredNames: [String] {
        let all = EmojiBundleStore.allNames
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("筛选表情…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 40), spacing: 8), count: 7), spacing: 10) {
                    ForEach(filteredNames, id: \.self) { name in
                        Button {
                            onSelect(name)
                        } label: {
                            if let image = EmojiBundleStore.image(named: name) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .padding(4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(height: 220)
        }
        .background(Color(.secondarySystemBackground))
    }
}
