import SwiftUI

/// ヘルプ＆チュートリアル。最初は短い4つのテーマ別チュートリアルを表示し、
/// 従来の詳細解説は「詳細ガイド（上級）」へ移動。
public struct TutorialHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    // MARK: - チュートリアル定義
    struct TutorialStep: Identifiable {
        let id = UUID()
        let icon: String
        let ja: String
        let en: String
    }
    
    struct TutorialTopic: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let titleJa: String
        let titleEn: String
        let summaryJa: String
        let summaryEn: String
        let steps: [TutorialStep]
    }
    
    private var topics: [TutorialTopic] {
        [helpTopic, calibrationTopic, battleTopic, disasterTopic]
    }
    
    private var helpTopic: TutorialTopic {
        TutorialTopic(
            id: "help", icon: "light.beacon.max.fill", color: .red,
            titleJa: "① HELPの出し方", titleEn: "1. Showing HELP",
            summaryJa: "声・文字入力で空中にHELPを描く", summaryEn: "Draw HELP in the air by voice or typing",
            steps: [
                TutorialStep(icon: "1.circle.fill", ja: "上のスイッチを【🚨 RESCUE】にします。文字は最初「HELP」です。", en: "Set the top switch to RESCUE. The text starts as HELP."),
                TutorialStep(icon: "2.circle.fill", ja: "一番下の【救難POV空間照射を開始】を押します。画面が最大輝度になります。", en: "Tap the big Start Rescue POV Beam button. The screen goes to max brightness."),
                TutorialStep(icon: "3.circle.fill", ja: "スマホを頭の上で左右に振ります。空中に文字が浮かびます。（振れない時は静止すると1文字ずつ点滅）", en: "Swing the phone left and right overhead. Letters appear in the air. If you cannot swing, hold still for one-letter strobe."),
                TutorialStep(icon: "mic.fill", ja: "【音声で変更】振りながら「HELP」「たすけて」「SOS」などと叫ぶと、日本語でも英語でも自動で認識して文字が変わります。しばらく無言だと最初の文字（HELP）に戻ります。", en: "Voice: shout HELP / SOS while swinging. Japanese and English are both recognized automatically. After a few seconds of silence the text returns to HELP."),
                TutorialStep(icon: "keyboard", ja: "【文字入力で変更】メイン画面の入力欄に好きな文字を入力。キーボードは「完了」か下へスクロールで閉じます。プリセットのボタンもワンタップで使えます。", en: "Typing: enter any text in the input field. Close the keyboard with Done or by scrolling down. Preset chips work with one tap.")
            ]
        )
    }
    
    private var calibrationTopic: TutorialTopic {
        TutorialTopic(
            id: "calib", icon: "waveform.path.ecg", color: .cyan,
            titleJa: "② キャリブレーションのやり方", titleEn: "2. Calibration",
            summaryJa: "あなたの振り方に光のタイミングを合わせる", summaryEn: "Match flash timing to your swing",
            steps: [
                TutorialStep(icon: "1.circle.fill", ja: "メイン画面右上の【練習】を開きます。", en: "Open Practice at the top right of the main screen."),
                TutorialStep(icon: "2.circle.fill", ja: "【頭上ワイド大振り】か【手首30cmスナップ】を選びます。", en: "Choose Wide overhead swing or Wrist 30cm snap."),
                TutorialStep(icon: "3.circle.fill", ja: "光る球が緑のゾーンを通る瞬間に合わせて振ります。画面の端が光って振動したら折り返しです。", en: "Swing so you pass the green zone when the orb does. The screen edge flashes and vibrates at each turn."),
                TutorialStep(icon: "4.circle.fill", ja: "【10往復サンプリング計測を開始】→ 10往復振る → 【この結果を発光タイミングに適用する】。", en: "Tap Start 10-swing sampling, swing 10 times, then tap Apply this result."),
                TutorialStep(icon: "arrow.counterclockwise", ja: "うまくいかない時は【キャリブレーションをデフォルトに戻す】で初期状態に戻せます。", en: "If it feels off, tap Reset calibration to default to go back.")
            ]
        )
    }
    
    private var battleTopic: TutorialTopic {
        TutorialTopic(
            id: "battle", icon: "flame.fill", color: .orange,
            titleJa: "③ 魔法バトルの遊び方", titleEn: "3. Magic Battle",
            summaryJa: "炎・水・雷・草を空中に描いて対戦", summaryEn: "Cast fire, water, thunder, grass in the air",
            steps: [
                TutorialStep(icon: "1.circle.fill", ja: "上のスイッチを【🎉 PARTY】にして【MAGIC BATTLE】を押します。", en: "Switch to PARTY and tap MAGIC BATTLE."),
                TutorialStep(icon: "2.circle.fill", ja: "【SYNC & BATTLE START】を押すと、毎分0秒・30秒に合わせて全員同時にカウントダウンが始まります。", en: "Tap SYNC & BATTLE START. Everyone counts down together at :00 and :30 of each minute."),
                TutorialStep(icon: "3.circle.fill", ja: "「3,2,1,GO!」の後、スマホを振って魔法を発動します。右振り＝炎🔥 左振り＝水💧 縦振り＝雷⚡ 円を描く＝草🌿", en: "After 3,2,1,GO! swing to cast. Right = Fire, Left = Water, Vertical = Thunder, Circle = Grass."),
                TutorialStep(icon: "4.circle.fill", ja: "相手の光をカメラが読み取り、属性の相性で勝敗が決まります。水💧＞炎🔥＞草🌿＞雷⚡＞水💧 の輪になっていて、それ以外の組み合わせ（炎と雷、水と草）は引き分けで再戦です。", en: "The camera reads the opponent's light and the element matchup decides. Water > Fire > Grass > Thunder > Water in a loop; any other pairing (Fire vs Thunder, Water vs Grass) is a draw and replays."),
                TutorialStep(icon: "xmark.circle", ja: "魔法の照射中は閉じるボタンが消えます（残像が欠けないように）。待機中に左上の×で戻れます。", en: "The close button hides while casting so the afterimage is not blocked. Use X at the top left while waiting.")
            ]
        )
    }
    
    private var disasterTopic: TutorialTopic {
        TutorialTopic(
            id: "disaster", icon: "cross.case.fill", color: .green,
            titleJa: "④ 防災機能の使い方", titleEn: "4. Disaster tools",
            summaryJa: "ビーコン・背面ライト・SOS・光通信", summaryEn: "Beacon, torch, SOS, light communication",
            steps: [
                TutorialStep(icon: "moon.stars.fill", ja: "【省電力ビーコン】画面をほぼ消灯して、8秒おきに背面ライトの閃光と笛を出します。バッテリーを温存したい夜間・長期の孤立時に。", en: "Power-Saver Beacon: screen almost off; every 8 s the rear flash and whistle fire. For nights and long isolation."),
                TutorialStep(icon: "flashlight.on.fill", ja: "【背面ライト】ワンタップで常時点灯。懐中電灯として使えます。", en: "Torch: one tap for constant light."),
                TutorialStep(icon: "bolt.badge.automatic.fill", ja: "【SOS点滅】背面ライトが国際モールス信号（・・・ーーー・・・）で自動点滅。【ホイッスル】は3kHzの救助笛を鳴らします。", en: "SOS Flash blinks ··· −−− ··· automatically. Whistle plays a 3 kHz rescue tone."),
                TutorialStep(icon: "dot.radiowaves.left.and.right", ja: "【光通信】右下のボタン。送信は背面ライトの点滅だけで定型語（HELP・WATER・MEDICALなど）を送り、受信はカメラで読み取って自分の言語に翻訳表示します。声が届かない遠距離向けです。", en: "Light Comm (bottom right): send preset words (HELP, WATER, MEDICAL…) only with the rear flash; receive with the camera and see it in your language. For long distance."),
                TutorialStep(icon: "envelope.badge.shield.half.filled.fill", ja: "【SOSメール】設定で家族のメールを登録すると、SOS発動時にリアルタイムGPS地図リンクが届きます。", en: "SOS mail: register a family email in Settings; a live GPS map link is sent when SOS starts.")
            ]
        )
    }
    
    // MARK: - 本体
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerBanner
                    ForEach(topics) { topic in
                        NavigationLink {
                            TutorialDetailView(topic: topic)
                        } label: {
                            topicRow(topic)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        AdvancedGuideView()
                    } label: {
                        advancedRow
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L.pick("チュートリアル", "Tutorial"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("閉じる")) { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RescuePOV")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(L.pick("知りたいテーマを選んでください。各テーマは数ステップで読めます。", "Pick a topic. Each one takes only a few steps."))
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    @ViewBuilder
    private func topicRow(_ topic: TutorialTopic) -> some View {
        HStack(spacing: 14) {
            Image(systemName: topic.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(topic.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(topic.color.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(L.pick(topic.titleJa, topic.titleEn))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(L.pick(topic.summaryJa, topic.summaryEn))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(topic.color.opacity(0.35), lineWidth: 1))
    }
    
    @ViewBuilder
    private var advancedRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.purple)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.purple.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(L.pick("詳細ガイド（上級・補足）", "Advanced guide"))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(L.pick("30cmモード・誤押し防止・AI判断・メール設定など", "30cm mode, button safety, AI, email setup…"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// テーマ別の短いステップ表示
struct TutorialDetailView: View {
    let topic: TutorialHelpSheet.TutorialTopic
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(topic.steps) { step in
                    stepRow(step)
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L.pick(topic.titleJa, topic.titleEn))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func stepRow(_ step: TutorialHelpSheet.TutorialStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(topic.color)
                .frame(width: 32)
            Text(L.pick(step.ja, step.en))
                .font(.system(size: 15))
                .foregroundColor(.white)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
    }
}

/// 従来の詳細解説（内容はそのまま保持）
struct AdvancedGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                
                guideCard(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .cyan,
                    title: "1. フェーズフリー（日常と非常時の一致）",
                    content: "日常の誕生日（HAPPY BIRTHDAY）、乾杯（CHEERS）、推し活・ライブ、夜間ランニングから、遭難・孤立・水害時の救助要請（HELP・SOS）まで、同じ操作で直感的に使いこなせます。"
                )
                
                guideCard(
                    icon: "hand.raised.fill",
                    iconColor: .green,
                    title: "2. 手首30cm浮き出しホログラム（疲れ知らず）",
                    content: "腕を頭上に掲げ続ける必要はありません。手首のスナップだけで左右約25〜35cmの狭い幅を高速往復させると、空中に文字が3Dホログラムのように立体的に浮き出ます。パーティーでグラスを持ちながらでも楽に楽しめます。"
                )
                
                guideCard(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "3. 0cmゼロスイング（静止・全画面ストロボ）",
                    content: "体力が尽きて振れなくなった時や、瓦礫の下・車内など狭くて振るスペースがない時、振りを止めると約0.8秒で自動的に全画面一文字ストロボ（H-E-L-P）へ移行します。画面を上に向けて置くだけで遠方に文字を伝達できます。"
                )
                
                guideCard(
                    icon: "shield.checkered",
                    iconColor: .orange,
                    title: "4. サイドボタン誤押し防止（実機セーフティ）",
                    content: "① iPhoneを【上下逆さま】（充電口を上）にして左右を握ると、サイドボタンに触れずに安全に振れます。（自動180度正立対応）\n② 設定 > アクセシビリティ >「アクセスガイド」をトリプルクリックで開始すると、サイドボタンをOSレベルで完全無効化できます。"
                )
                
                guideCard(
                    icon: "mic.badge.waveform.fill",
                    iconColor: .yellow,
                    title: "5. 叫び声音声リアルタイム反映",
                    content: "端末を振りながら「HELP」「たすけて」「乾杯！」と叫ぶと、マイクで叫び声を拾って即座に空中の文字へ反映させます。日本語・英語を同時に認識し、しばらく無言だと最初の文字へ戻ります。"
                )
                
                guideCard(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "6. Apple Intelligence 状況判断 & MCP",
                    content: "急激なGショック（衝突・滑落）や高度急変をCoreMotionでオンデバイス推論（オフライン完全対応）。自動で最適な救難サインを提案します。またMCP（Model Context Protocol）エージェントとの連携もサポートしています。"
                )
                
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
        .navigationTitle(L.pick("詳細ガイド", "Advanced guide"))
        .navigationBarTitleDisplayMode(.inline)
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
