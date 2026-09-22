import SwiftUI

public struct PresetSelector: View {
    @Binding var selectedText: String
    
    let presets = [
        "SOS", "HELP", "ココ", "↑", "→", "119", "110", "OK"
    ]
    
    public init(selectedText: Binding<String>) {
        self._selectedText = selectedText
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("レスキュー定型プリセット")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button(action: {
                            selectedText = preset
                        }) {
                            Text(preset)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedText == preset ? Color.red : Color(white: 0.18))
                                )
                                .foregroundColor(selectedText == preset ? .white : .primary)
                        }
                    }
                }
            }
        }
    }
}
