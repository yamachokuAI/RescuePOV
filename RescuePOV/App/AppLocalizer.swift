import Foundation

/// アプリ内言語切替（端末のネイティブ言語 ⇄ 英語）。
/// UIの元文字列は日本語。英語選択時のみ辞書で置換し、未登録の文字列は元の文字列をそのまま表示する。
public enum L {
    /// 端末のネイティブ言語コード（例: "ja", "en", "fr"）
    public static var nativeCode: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    }
    
    /// 現在、英語表示が選ばれているか
    public static var isEnglish: Bool {
        UserDefaults.standard.string(forKey: "appLanguage") == "en"
    }
    
    /// 端末がすでに日本語以外（=ネイティブ表示でも英語系）か
    public static var nativeIsJapanese: Bool { nativeCode == "ja" }
    
    /// 切替ボタンに表示する現在の言語ラベル
    public static var currentLabel: String {
        isEnglish ? "EN" : nativeCode.uppercased()
    }
    
    /// 日本語の元文字列を現在の言語へ変換
    public static func t(_ ja: String) -> String {
        guard isEnglish || !nativeIsJapanese else {
            return ja
        }
        // 端末が日本語以外で「ネイティブ」選択の場合は、翻訳辞書の英語を代替表示する（日本語UIしか持たないため）
        return en[ja] ?? ja
    }
    
    /// 日本語・英語の2択を直接指定（チュートリアル等）
    public static func pick(_ ja: String, _ english: String) -> String {
        (isEnglish || !nativeIsJapanese) ? english : ja
    }
    
    // MARK: - 英語辞書
    private static let en: [String: String] = [
        // ツールバー・共通
        "練習": "Practice",
        "写真フォルダから壁紙を選択": "Choose wallpaper from Photos",
        "内蔵グラデーション壁紙を切替": "Switch built-in wallpaper",
        "標準の壁紙に戻す": "Reset to default wallpaper",
        "閉じる": "Close",
        "完了": "Done",
        "設定": "Settings",
        // モード
        "🚨 RESCUE": "🚨 RESCUE",
        "🎉 PARTY": "🎉 PARTY",
        // プレビュー
        "120Hz OLED 黒締め": "120Hz OLED black-out",
        // 振幅
        "スイング振幅": "Swing Range",
        // ビーコン・バトル
        "省電力ビーコン": "Power-Saver Beacon",
        "画面消灯＋間欠\n閃光＆電子笛": "Screen off + intermittent\nflash & whistle",
        "手動起動": "Start",
        "炎・水・雷・草\n空間属性バトル": "Fire/Water/Thunder/Grass\nAir Element Battle",
        "対戦開始": "Battle",
        // 入力
        "表示文字を入力": "Enter display text",
        "横振り": "Horizontal",
        "縦振り": "Vertical",
        // クイック
        "ホイッスル": "Whistle",
        "吹鳴中": "Sounding",
        "光通信": "Light Comm",
        "バトル": "Battle",
        "SOS点滅": "SOS Flash",
        "ライト": "Light",
        // 照射ボタン
        "救難POV空間照射を開始": "Start Rescue POV Beam",
        "パーティーPOV空間照射を開始": "Start Party POV Beam",
        // 設定
        "叫び声をマイクで拾って文字に反映": "Pick up voice with mic and show as text",
        "通知先（ご家族等）": "Notify (family etc.)",
        "現在の推定状況": "Estimated situation",
        "シチュエーション自動適応": "Auto situation adaptation",
        // ビーコン
        "秒後に自動閃光": "sec to next flash",
        "背面LED閃光": "Rear LED flash",
        "3kHz電子笛": "3kHz whistle",
        "サバイバル・ビーコンを終了して戻る": "Stop beacon and go back",
        // ヘルプ
        "ヘルプ & 使い方": "Help & Guide",
        "適用": "Apply",
        "背面ライト": "Torch",
        "ライトON": "Torch ON",
        "SOS発信中": "SOS active",
        "オプティクス設定": "Optics",
        "観察者向け正像表示": "Mirror for viewer",
        "叫び声AI音声同期": "Voice sync",
        "声が止んだら元の文字に復帰": "Return to original text after silence",
        "緊急救難SOSメール自動配信（Google連携）": "Emergency SOS mail (Google)",
        "送信元Google": "Sender (Google)",
        "例: family@example.com": "e.g. family@example.com",
        "Apple Intelligence & 状況判断": "Apple Intelligence & Situation",
        "有機EL完全消灯によりバッテリーを極限まで温存しながら\n8秒おきに【背面フラッシュ閃光＋3kHz救助笛】を発信します": "Keeps the OLED fully off to save battery\nand fires rear flash + 3 kHz whistle every 8 seconds",
        "※SOS発動時、通知先（ご家族宛て）に【暗号化されたリアルタイムGPS地図リンク】と【ワンタイム合鍵】が自動送信されます。送信元（ご本人Gmail）にも控えが自動送信されます。": "When SOS starts, an encrypted live GPS map link and a one-time passcode are sent to the recipient. A copy goes to your own Gmail."
    ]
}
