import Foundation
import UIKit

public enum MagicElement: String, CaseIterable, Equatable {
    case fire = "炎"
    case water = "水"
    case grass = "草"
    case thunder = "雷"
    
    public var povColor: UIColor {
        switch self {
        case .fire: return UIColor.red // Pure Red
        case .water: return UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0) // Cyan
        case .grass: return UIColor(red: 0.5, green: 1.0, blue: 0.0, alpha: 1.0) // Yellow-Green
        case .thunder: return UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0) // Yellow
        }
    }
    
    public var nameEnglish: String {
        switch self {
        case .fire: return "FIRE"
        case .water: return "WATER"
        case .grass: return "GRASS"
        case .thunder: return "THUNDER"
        }
    }
    
    // 勝敗判定: selfが相手に勝つ場合はtrue、負けはfalse、引き分け（同じ）はnil
    // ルール: 水は炎に勝つ、炎は草に勝つ、草は雷に勝つ、雷は水に勝つ
    // その他（隣り合わないもの、例えば火と雷、水と草）はドローとする？
    // ユーザー指示: 「その他は引き分けで再戦する」
    public func defeats(_ opponent: MagicElement) -> Bool? {
        if self == opponent { return nil }
        switch (self, opponent) {
        case (.water, .fire): return true
        case (.fire, .grass): return true
        case (.grass, .thunder): return true
        case (.thunder, .water): return true
        
        case (.fire, .water): return false
        case (.grass, .fire): return false
        case (.thunder, .grass): return false
        case (.water, .thunder): return false
        
        default: return nil // 引き分け
        }
    }
}
