import SwiftUI
import UIKit

/// アプリケーションのフェーズフリー運用モード
public enum AppOperationalMode: String, CaseIterable, Identifiable {
    case rescue = "🚨 RESCUE"
    case party = "🎉 PARTY"
    
    public var id: String { rawValue }
    
    public var accentColor: Color {
        switch self {
        case .rescue: return Color(red: 1.0, green: 0.15, blue: 0.15)
        case .party: return Color(red: 0.0, green: 0.95, blue: 1.0)
        }
    }
    
    public var glassGlow: Color {
        switch self {
        case .rescue: return Color.red.opacity(0.4)
        case .party: return Color.cyan.opacity(0.4)
        }
    }
}

public struct MainDashboardView: View {
    @State private var operationalMode: AppOperationalMode = .rescue
    @State private var targetText: String = "HELP"
    @State private var selectedDirection: POVDirection = .horizontal
    @State private var selectedColor: POVColor = .white
    @State private var mirrorForViewer: Bool = true
    
    @State private var isShowingPOV: Bool = false
    @State private var isShowingHelp: Bool = false
    @State private var isShowingSettings: Bool = false
    
    @ObservedObject private var motionDetector = MotionDetector.shared
    @ObservedObject private var voiceService = VoiceRescueService.shared
    @ObservedObject private var aiEngine = HybridIntelligenceEngine.shared
    
    // Liquid Glass 水滴歪みモーフィング演出状態
    @State private var liquidDropletScaleX: CGFloat = 1.0
    @State private var liquidDropletScaleY: CGFloat = 1.0
    @State private var previewOffset: CGFloat = -40
    @State private var previewStrobeChar: String = "H"
    @State private var previewStrobeIndex: Int = 0
    @State private var isButtonPressed: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // 漆黒の背景と極上の流体ガラスバックライト
                Color.black.ignoresSafeArea()
                
                // 有機的アンビエント・リキッド・グロー（水滴の屈折光）
                Circle()
                    .fill(operationalMode.glassGlow)
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(y: operationalMode == .rescue ? -120 : 100)
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: operationalMode)
                
                // 一画面完結・スクロール不要のスマートレイアウト
                VStack(spacing: 16) {
                    // 1. Apple Liquid Glass 水滴モーフィング・モードスイッチ
                    liquidGlassModeSwitcher
                    
                    // 2. Apple Intelligence 状況推論・対話プロポーザル（検知時のみ流体展開）
                    if let suggestion = aiEngine.aiSuggestionMessage {
                        aiProposalGlassBanner(message: suggestion)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    
                    // 3. Liquid Glass 3Dホログラム・プレビュー窓
                    liquidGlassPreviewDome
                    
                    // 4. テキスト入力 ＆ 水滴プリセットカプセル
                    liquidGlassInputRow
                    
                    // 5. リアルタイム・オプティクス状態バー（極小ピル）
                    opticsMiniStatusPill
                    
                    Spacer(minLength: 4)
                    
                    // 6. 超大型 Liquid Glass 送信ボタン（水滴弾性フィードバック）
                    liquidGlassTransmissionButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("RescuePOV")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Circle()
                            .fill(operationalMode.accentColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: operationalMode.accentColor, radius: 4)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingSettings = true
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingHelp = true
                        }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingHelp) {
                TutorialHelpSheet()
            }
            .sheet(isPresented: $isShowingSettings) {
                quickSettingsSheet
            }
            .onAppear {
                motionDetector.start(direction: selectedDirection)
            }
            .onChange(of: motionDetector.isOverheadSwinging) { _, isSwinging in
                if isSwinging && !isShowingPOV {
                    isShowingPOV = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 1. Liquid Glass 水滴モーフィング・モードスイッチャー
    @ViewBuilder
    private var liquidGlassModeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(AppOperationalMode.allCases) { mode in
                Button(action: {
                    guard operationalMode != mode else { return }
                    triggerLiquidDropletDistortion()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.65)) {
                        operationalMode = mode
                        if mode == .party {
                            targetText = "HAPPY"
                            selectedColor = .cyan
                        } else {
                            targetText = "HELP"
                            selectedColor = .white
                        }
                    }
                }) {
                    ZStack {
                        if operationalMode == mode {
                            // 水滴が歪む流体ガラスピル（Liquid Droplet）
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            mode.accentColor.opacity(0.35),
                                            mode.accentColor.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.7), mode.accentColor.opacity(0.4)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.2
                                        )
                                )
                                .shadow(color: mode.accentColor.opacity(0.4), radius: 10, y: 3)
                                .scaleEffect(x: liquidDropletScaleX, y: liquidDropletScaleY)
                        }
                        
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(operationalMode == mode ? .white : .gray)
                            .padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(white: 0.08).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    /// 水滴が歪んで跳ねるジェリーエフェクト
    private func triggerLiquidDropletDistortion() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.12)) {
            liquidDropletScaleX = 1.22
            liquidDropletScaleY = 0.82
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                liquidDropletScaleX = 1.0
                liquidDropletScaleY = 1.0
            }
        }
    }
    
    // MARK: - 2. Apple Intelligence 状況対話プロポーザル
    @ViewBuilder
    private func aiProposalGlassBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(.cyan)
                .font(.system(size: 14, weight: .bold))
            
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            Button("適用") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                aiEngine.acceptSuggestion { text, mode in
                    withAnimation {
                        self.targetText = text
                        self.operationalMode = mode
                    }
                }
            }
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.cyan))
            .foregroundColor(.black)
            
            Button(action: {
                withAnimation { aiEngine.dismissSuggestion() }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
        )
    }
    
    // MARK: - 3. Liquid Glass 3Dホログラム・プレビュー窓
    @ViewBuilder
    private var liquidGlassPreviewDome: some View {
        ZStack {
            // ガラスドームの背景
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.08).opacity(0.7), Color(white: 0.02).opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: operationalMode.glassGlow.opacity(0.3), radius: 16, y: 6)
            
            // 内部の3Dホログラム文字演出
            VStack(spacing: 6) {
                HStack {
                    Text(motionDetector.activeRangeMode.shortTitle)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(operationalMode.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(operationalMode.accentColor.opacity(0.2)))
                    Spacer()
                    Text("100% 最大光束 ｜ 120Hz")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                Spacer()
                
                // ホログラム浮き出し・テキスト
                ZStack {
                    Text(targetText)
                        .font(.system(size: 42, weight: .black, design: .monospaced))
                        .foregroundColor(selectedColor.swiftUIColor.opacity(0.3))
                        .blur(radius: 6)
                        .offset(x: previewOffset * 0.4)
                    
                    Text(targetText)
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundColor(selectedColor.swiftUIColor)
                        .shadow(color: selectedColor.swiftUIColor, radius: 12)
                        .offset(x: previewOffset)
                }
                
                Spacer()
                
                // スイング誘導
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10))
                    Text("手首30cmスナップで3D浮出 ⇄ 静止で全画面ストロボ自動切替")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 10)
            }
        }
        .frame(height: 155)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.75)
                .repeatForever(autoreverses: true)
            ) {
                previewOffset = 40
            }
        }
    }
    
    // MARK: - 4. テキスト入力 ＆ 水滴プリセットカプセル
    @ViewBuilder
    private var liquidGlassInputRow: some View {
        VStack(spacing: 8) {
            // 一行入力フィールド
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .foregroundColor(operationalMode.accentColor)
                    .font(.system(size: 13))
                
                TextField("表示文字", text: $targetText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                if !targetText.isEmpty {
                    Button(action: { targetText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // クイック水滴プリセットカプセル（横スクロール・一列）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let presets = (operationalMode == .rescue)
                        ? ["HELP", "SOS", "たすけて", "ココ", "孤立", "119", "OK"]
                        : ["HAPPY", "CHEERS", "LOVE", "CONGRAT", "YES!", "RUN"]
                    
                    ForEach(presets, id: \.self) { word in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            targetText = word
                        }) {
                            Text(word)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(
                                        targetText == word
                                            ? operationalMode.accentColor.opacity(0.3)
                                            : Color(white: 0.14)
                                    )
                                )
                                .overlay(
                                    Capsule().stroke(
                                        targetText == word
                                            ? operationalMode.accentColor
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                                )
                                .foregroundColor(targetText == word ? .white : .gray)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    // MARK: - 5. オプティクス状態バー
    @ViewBuilder
    private var opticsMiniStatusPill: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text(String(format: "角速度 %.1f rad/s", motionDetector.swingIntensity))
            }
            Text("｜")
            HStack(spacing: 4) {
                Circle().fill(Color.cyan).frame(width: 5, height: 5)
                Text(String(format: "周期 %.1f Hz", motionDetector.swingFrequencyHz))
            }
            Text("｜")
            HStack(spacing: 4) {
                Circle().fill(Color.yellow).frame(width: 5, height: 5)
                Text(String(format: "振幅 %.0f°", motionDetector.strokeAngleRange))
            }
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.08)))
    }
    
    // MARK: - 6. 超大型 Liquid Glass 送信ボタン
    @ViewBuilder
    private var liquidGlassTransmissionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isShowingPOV = true
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                    Text(operationalMode == .rescue ? "救難POV送信を開始" : "パーティーPOV発光を開始")
                        .font(.title3.bold())
                }
                
                Text("タップして暗闇で振る（100%全モード最大光束 ＆ Shake-Undo防止）")
                    .font(.system(size: 10.5, weight: .medium))
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [
                        operationalMode.accentColor,
                        operationalMode.accentColor.opacity(0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(22)
            .shadow(color: operationalMode.glassGlow, radius: 18, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
            )
            .scaleEffect(isButtonPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isButtonPressed = true }
                .onEnded { _ in isButtonPressed = false }
        )
        .fullScreenCover(isPresented: $isShowingPOV, onDismiss: {
            motionDetector.resetOverheadTrigger()
        }) {
            POVFullscreenView(
                text: targetText,
                direction: selectedDirection,
                color: selectedColor,
                mirrorForViewer: mirrorForViewer,
                onDismiss: {
                    isShowingPOV = false
                    motionDetector.resetOverheadTrigger()
                }
            )
        }
    }
    
    // MARK: - クイック設定シート
    @ViewBuilder
    private var quickSettingsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("オプティクス設定")) {
                    Picker("振る方向", selection: $selectedDirection) {
                        ForEach(POVDirection.allCases) { dir in
                            Label(dir.rawValue, systemImage: dir.iconName).tag(dir)
                        }
                    }
                    
                    Picker("発光カラー", selection: $selectedColor) {
                        ForEach(POVColor.allCases) { col in
                            Text(col.rawValue).tag(col)
                        }
                    }
                    
                    Toggle("観察者向け正像表示", isOn: $mirrorForViewer)
                }
                
                Section(header: Text("叫び声AI音声同期")) {
                    Toggle("叫び声をマイクで拾って文字に反映", isOn: $voiceService.isVoiceSyncEnabled)
                    if voiceService.isVoiceSyncEnabled {
                        Toggle("声が止んだら元の文字に復帰", isOn: $voiceService.autoResetToDefault)
                    }
                }
                
                Section(header: Text("Apple Intelligence & 状況判断")) {
                    Toggle("シチュエーション自動適応", isOn: $aiEngine.isAutoSituationAdaptationEnabled)
                    HStack {
                        Text("現在の推定状況")
                        Spacer()
                        Text(aiEngine.currentSituation.rawValue)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { isShowingSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
