import SwiftUI

public struct MainDashboardView: View {
    @State private var targetText: String = "HELP"
    @State private var selectedMode: POVDisplayMode = .spatialWindow
    @State private var selectedDirection: POVDirection = .horizontal
    @State private var selectedColor: POVColor = .white
    @State private var mirrorForViewer: Bool = true
    @State private var isShowingPOV: Bool = false
    @State private var isShowingSampling: Bool = false
    
    @ObservedObject private var motionDetector = MotionDetector.shared
    @ObservedObject private var spatialTracker = SpatialMotionTracker.shared
    @ObservedObject private var locationService = LocationService.shared
    @State private var copiedLocation: Bool = false
    
    // 仮想シミュレータ用のアニメーション状態
    @State private var previewOffset: CGFloat = -90
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    mainStartButton
                    modeSelectionSection
                    textSettingSection
                    directionAndColorSection
                    EmergencyToolbar()
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
                    locationCardSection
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("RescuePOV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "lifepreserver.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 1. プレビューセクション
    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    selectedMode == .spatialWindow ? "空間固定ウィンドウ・プレビュー" : "残像スリット・プレビュー",
                    systemImage: selectedMode == .spatialWindow ? "gyroscope" : "eye.fill"
                )
                .font(.caption.bold())
                .foregroundColor(.secondary)
                Spacer()
                Text("振った際の見え方イメージ")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.05))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                if selectedMode == .spatialWindow {
                    ZStack {
                        Text(targetText)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(selectedColor.swiftUIColor)
                            .shadow(color: selectedColor.swiftUIColor, radius: 12)
                            .tracking(10)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow, lineWidth: 2)
                            .background(Color.yellow.opacity(0.08))
                            .frame(width: 60, height: 95)
                            .offset(x: previewOffset)
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(targetText)
                            .font(.system(size: 38, weight: .black, design: .monospaced))
                            .foregroundColor(selectedColor.swiftUIColor.opacity(0.35))
                            .blur(radius: 6)
                            .offset(x: previewOffset * 0.7)
                        
                        Text(targetText)
                            .font(.system(size: 38, weight: .black, design: .monospaced))
                            .foregroundColor(selectedColor.swiftUIColor)
                            .shadow(color: selectedColor.swiftUIColor, radius: 10)
                            .offset(x: previewOffset)
                    }
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(selectedMode == .spatialWindow ? "角度に連動して空中に文字が固定" : "左右に素早く振る")
                            .font(.caption2.bold())
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 6)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.1)))
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                previewOffset = 90
            }
        }
    }
    
    // MARK: - 2. メインスタートボタン
    @ViewBuilder
    private var mainStartButton: some View {
        Button(action: {
            isShowingPOV = true
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                    Text("全画面で空中文字を開始")
                        .font(.title2.weight(.heavy))
                }
                
                HStack(spacing: 6) {
                    Text("「\(targetText)」(\(selectedMode.shortTitle))")
                        .bold()
                    Text("•")
                    Text("タップして暗闇で振る")
                }
                .font(.subheadline)
                .opacity(0.95)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                LinearGradient(
                    colors: [Color.red, Color(red: 0.85, green: 0.1, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(18)
            .shadow(color: .red.opacity(0.55), radius: 14, x: 0, y: 7)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            )
        }
        .fullScreenCover(isPresented: $isShowingPOV) {
            POVFullscreenView(
                text: targetText,
                direction: selectedDirection,
                color: selectedColor,
                mode: selectedMode,
                mirrorForViewer: mirrorForViewer
            )
        }
    }
    
    // MARK: - 3. 表示モード選択セクション
    @ViewBuilder
    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("表示方式の選択")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if selectedMode == .spatialWindow {
                    Text("高視認性")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.25)))
                        .foregroundColor(.green)
                }
            }
            
            Picker("表示方式", selection: $selectedMode) {
                ForEach(POVDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            Text(selectedMode.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(3)
            
            if selectedMode == .spatialWindow {
                Divider().background(Color.white.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("振り幅感度（角度レンジ）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "±%.0f度", spatialTracker.maxSwingAngleRadians * 180.0 / .pi))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundColor(.yellow)
                    }
                    Slider(
                        value: Binding(
                            get: { spatialTracker.maxSwingAngleRadians },
                            set: { spatialTracker.maxSwingAngleRadians = $0 }
                        ),
                        in: 0.35...0.80,
                        step: 0.02
                    )
                    .tint(.yellow)
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // スイング・ヒステリシス計測シートを開くボタン
            Button(action: {
                isShowingSampling = true
            }) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                    Text("実機スイング・ヒステリシス計測（10往復サンプリング）")
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.3)))
                .foregroundColor(.purple)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.6), lineWidth: 1)
                )
            }
            .sheet(isPresented: $isShowingSampling) {
                SamplingView()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
    }
    
    // MARK: - 4. 表示文字設定セクション
    @ViewBuilder
    private var textSettingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("表示文字の選択")
                .font(.headline)
                .foregroundColor(.white)
            
            PresetSelector(selectedText: $targetText)
            
            HStack {
                Image(systemName: "character.cursor.ibeam")
                    .foregroundColor(.secondary)
                TextField("自由入力（1〜4文字推奨）", text: $targetText)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                if !targetText.isEmpty {
                    Button(action: { targetText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
    }
    
    // MARK: - 5. スイング方向 & 発光カラー
    @ViewBuilder
    private var directionAndColorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("スイング方向 & 発光カラー")
                .font(.headline)
                .foregroundColor(.white)
            
            Picker("振る方向", selection: $selectedDirection) {
                ForEach(POVDirection.allCases) { dir in
                    Label(dir.rawValue, systemImage: dir.iconName).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Text("発光色")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("カラー", selection: $selectedColor) {
                    ForEach(POVColor.allCases) { col in
                        Text(col.rawValue).tag(col)
                    }
                }
                .pickerStyle(.menu)
                .tint(selectedColor.swiftUIColor)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            Toggle(isOn: $mirrorForViewer) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("観察者向け正像表示")
                        .font(.subheadline.bold())
                    Text("画面を相手に向けて振った時、相手から正しく文字が読めるよう向きを調整します")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.red)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
    }
    
    // MARK: - 6. 現在地カード
    @ViewBuilder
    private var locationCardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.red)
                Text("現在地情報（救助要請用）")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if locationService.latitude == nil {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            if locationService.latitude != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("緯度・経度（度分秒フォーマット）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(locationService.formattedDMS)
                        .font(.title3.monospaced().bold())
                        .foregroundColor(.yellow)
                    
                    Text("10進数: \(locationService.formattedDecimal)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }
                
                Button(action: {
                    UIPasteboard.general.string = "\(locationService.formattedDMS)\n(10進数: \(locationService.formattedDecimal))"
                    copiedLocation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedLocation = false
                    }
                }) {
                    HStack {
                        Image(systemName: copiedLocation ? "checkmark" : "doc.on.doc")
                        Text(copiedLocation ? "位置情報をコピーしました" : "位置情報をクリップボードにコピー")
                    }
                    .font(.caption.bold())
                    .foregroundColor(copiedLocation ? .green : .white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                }
            } else {
                Text("位置情報を取得中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
    }
}
