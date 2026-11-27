import SwiftUI

public struct EmojiPickerView: View {
    public let height: CGFloat
    public let onSelect: (String) -> Void

    @State private var searchText = ""

    public init(height: CGFloat = 220, onSelect: @escaping (String) -> Void) {
        self.height = height
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("筛选表情…", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

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
            .scrollEdgeEffectHidden(true)
            .frame(height: max(160, height - 54))
        }
        .frame(height: height)
        .background(Color(.secondarySystemBackground))
    }
}
