import SwiftUI

/// フェーズフリー＆安全セーフティ・チュートリアルヘルプシート
public struct TutorialHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ヘッダーバナー
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RescuePOV ガイド & セーフティ")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("日常を彩るホログラフィックPOV。普段からパーティーで使うことで、万が一の災害時にも1秒で命を守るフェーズフリー・テクノロジー。")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, 6)
                    
                    // 1. フェーズフリー（日常 ⇄ 非常時）
                    guideCard(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .cyan,
                        title: "1. フェーズフリー（日常と非常時の一致）",
                        content: "日常の誕生日（HAPPY BIRTHDAY）、乾杯（CHEERS）、推し活・ライブ、夜間ランニングから、遭難・孤立・水害時の救助要請（HELP・SOS）まで、同じ操作で直感的に使いこなせます。"
                    )
                    
                    // 2. 30cm手首浮き出しホログラム（真骨頂）
                    guideCard(
                        icon: "hand.raised.fill",
                        iconColor: .green,
                        title: "2. 手首30cm浮き出しホログラム（疲れ知らず）",
                        content: "腕を頭上に掲げ続ける必要はありません。手首のスナップだけで左右約25〜35cmの狭い幅を高速往復させると、空中に文字が3Dホログラムのように立体的に浮き出ます。パーティーでグラスを持ちながらでも楽に楽しめます。"
                    )
                    
                    // 3. 0cm静止ストロボ（体力限界・狭所）
                    guideCard(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "3. 0cmゼロスイング（静止・全画面ストロボ）",
                        content: "体力が尽きて振れなくなった時や、瓦礫の下・車内など狭くて振るスペースがない時、振りを止めると約0.8秒で自動的に全画面一文字ストロボ（H-E-L-P）へ移行します。画面を上に向けて置くだけで遠方に文字を伝達できます。"
                    )
                    
                    // 4. 電源ボタン誤押し対策
                    guideCard(
                        icon: "shield.checkered",
                        iconColor: .orange,
                        title: "4. サイドボタン誤押し防止（実機セーフティ）",
                        content: "① iPhoneを【上下逆さま】（充電口を上）にして左右を握ると、サイドボタンに触れずに安全に振れます。（自動180度正立対応）\n② 設定 > アクセシビリティ >「アクセスガイド」をトリプルクリックで開始すると、サイドボタンをOSレベルで完全無効化できます。"
                    )
                    
                    // 5. 叫び声AI音声同期
                    guideCard(
                        icon: "mic.badge.waveform.fill",
                        iconColor: .yellow,
                        title: "5. 叫び声音声リアルタイム反映",
                        content: "端末を振りながら「HELP」「たすけて」「乾杯！」と叫ぶと、マイクで叫び声を拾って即座に空中の文字へ反映させます。"
                    )
                    
                    // 6. Apple Intelligence / Core ML
                    guideCard(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "6. Apple Intelligence 状況判断 & MCP",
                        content: "急激なGショック（衝突・滑落）や高度急変をCoreMotionでオンデバイス推論（オフライン完全対応）。自動で最適な救難サインを提案します。またMCP（Model Context Protocol）エージェントとの連携もサポートしています。"
                    )
                    
                    // 7. 緊急救難SOSメール自動配信
                    guideCard(
                        icon: "envelope.badge.shield.half.filled.fill",
                        iconColor: .red,
                        title: "7. 緊急SOSメール設定とVercelリンクの注意",
                        content: "【設定方法】\n右上の「設定アイコン」から「緊急救難SOSメール自動配信」の項目に進み、通知先にご家族などのメールアドレスを入力してください。\n\n【ご家族がリンクを開けない場合（Vercelログイン画面）】\nご家族がメールのGPS地図リンクを開いた際、「Vercel」のログイン画面が表示されることがあります。これは開発中環境（Vercel Protection）の制限によるもので、ご家族がアカウントを作成する必要はありません。\nVercelのプロジェクト設定（Settings > Deployment Protection）で「Vercel Authentication」を無効化するか、本番（Production）ドメインのURLを使用することで、誰でも即座に地図を見られるようになります。"
                    )
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("ヘルプ & 使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func guideCard(icon: String, iconColor: Color, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text(content)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
