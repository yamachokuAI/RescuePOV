import SwiftUI
import UIKit

/// フェーズフリー（日常・フェス・推し活 ⇄ 非常時・遭難・SOS）カテゴリー
public enum PresetCategory: String, CaseIterable, Identifiable {
    case party = "🎉 日常・パーティー・お祝い"
    case rescue = "🚨 非常時・遭難・SOS"
    case daily = "🏃 ナイトラン・防犯・安全"
    
    public var id: String { rawValue }
    
    public var shortTitle: String {
        switch self {
        case .party: return "🎉 パーティー"
        case .rescue: return "🚨 遭難・救助"
        case .daily: return "🏃 防犯・安全"
        }
    }
}

public struct PresetSelector: View {
    @Binding var selectedText: String
    @Binding var selectedCategory: PresetCategory
    
    public struct PresetItem: Identifiable {
        public let id = UUID()
        public let text: String
        public let icon: String
        public let label: String
    }
    
    public let partyPresets: [PresetItem] = [
        PresetItem(text: "HAPPY", icon: "birthday.cake.fill", label: "誕生日"),
        PresetItem(text: "BIRTH", icon: "gift.fill", label: "バースデー"),
        PresetItem(text: "CHEERS", icon: "wineglass.fill", label: "乾杯"),
        PresetItem(text: "CONGRAT", icon: "sparkles", label: "お祝い"),
        PresetItem(text: "LOVE", icon: "heart.fill", label: "推し活・愛"),
        PresetItem(text: "WELCOME", icon: "door.left.hand.open", label: "歓迎"),
        PresetItem(text: "YES!", icon: "hand.thumbsup.fill", label: "賛同"),
        PresetItem(text: "THANKS", icon: "hands.sparkles.fill", label: "感謝")
    ]
    
    public let rescuePresets: [PresetItem] = [
        PresetItem(text: "HELP", icon: "sos.circle.fill", label: "救助要請"),
        PresetItem(text: "SOS", icon: "exclamationmark.triangle.fill", label: "国際SOS"),
        PresetItem(text: "たすけて", icon: "person.crop.circle.badge.exclamationmark", label: "叫びSOS"),
        PresetItem(text: "ココ", icon: "location.fill", label: "現在位置"),
        PresetItem(text: "孤立", icon: "water.waves.and.arrow.trianglehead.down", label: "浸水孤立"),
        PresetItem(text: "119", icon: "cross.fill", label: "消防救急"),
        PresetItem(text: "110", icon: "shield.fill", label: "警察通報"),
        PresetItem(text: "OK", icon: "checkmark.circle.fill", label: "無事・生存")
    ]
    
    public let dailyPresets: [PresetItem] = [
        PresetItem(text: "RUN", icon: "figure.run", label: "夜間ラン"),
        PresetItem(text: "SLOW", icon: "tortoise.fill", label: "減速指示"),
        PresetItem(text: "POLICE", icon: "shield.lefthalf.filled", label: "防犯警戒"),
        PresetItem(text: "SAFE", icon: "lock.shield.fill", label: "安全確保")
    ]
    
    public init(selectedText: Binding<String>, selectedCategory: Binding<PresetCategory> = .constant(.rescue)) {
        self._selectedText = selectedText
        self._selectedCategory = selectedCategory
    }
    
    private var currentPresets: [PresetItem] {
        switch selectedCategory {
        case .party: return partyPresets
        case .rescue: return rescuePresets
        case .daily: return dailyPresets
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // カテゴリー切り替えタブ
            HStack(spacing: 8) {
                ForEach(PresetCategory.allCases) { cat in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCategory = cat
                    }) {
                        Text(cat.shortTitle)
                            .font(.system(size: 11.5, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    selectedCategory == cat
                                        ? (cat == .rescue ? Color.red : Color.cyan.opacity(0.85))
                                        : Color(white: 0.16)
                                )
                            )
                            .foregroundColor(selectedCategory == cat ? .white : .gray)
                    }
                }
            }
            
            // プリセット横スクロールグリッド
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(currentPresets) { item in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedText = item.text
                        }) {
                            VStack(spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 11))
                                    Text(item.text)
                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                }
                                Text(item.label)
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        selectedText == item.text
                                            ? (selectedCategory == .rescue ? Color.red : Color.cyan)
                                            : Color(white: 0.14)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        selectedText == item.text
                                            ? Color.white.opacity(0.6)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundColor(selectedText == item.text ? .white : .primary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
