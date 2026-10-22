import SwiftUI
import PhotosUI
import UIKit

/// アプリケーションのフェーズフリー運用モード
public enum AppOperationalMode: String, CaseIterable, Identifiable {
    case rescue = "🚨 RESCUE"
    case party = "🎉 PARTY"
    
    public var id: String { rawValue }
    
    public var accentColor: Color {
        switch self {
        case .rescue: return Color(red: 1.0, green: 0.18, blue: 0.22)
        case .party: return Color(red: 0.0, green: 0.92, blue: 1.0)
        }
    }
    
    public var secondaryColor: Color {
        switch self {
        case .rescue: return Color.orange
        case .party: return Color(red: 0.85, green: 0.2, blue: 1.0)
        }
    }
    
    public var glassGlow: Color {
        switch self {
        case .rescue: return Color.red.opacity(0.45)
        case .party: return Color.cyan.opacity(0.45)
        }
    }
}

/// 弁当箱（Bento Grid）の各仕切り（コンパートメント）識別子
private enum BentoCompartment: String, CaseIterable, Identifiable {
    case previewDome      // メイン空中ホログラム窓（特大仕切り）
    case swingRange       // 振れ幅・手首スナップ仕切り（左中仕切り）
    case specialAction    // 非常時: サバイバルビーコン / 日常: マジックバトル（右中仕切り）
    case wordPalette      // テキスト入力＆プリセット仕切り（下段ワイド仕切り）
    case emergencySignal  // 背面トーチ＆ホイッスル即応仕切り（最下段仕切り）
    
    var id: String { rawValue }
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
    @State private var isShowingTraining: Bool = false
    @State private var isShowingMagicBattle: Bool = false
    @State private var isShowingSurvivalBeacon: Bool = false
    
    @ObservedObject private var motionDetector = MotionDetector.shared
    @ObservedObject private var voiceService = VoiceRescueService.shared
    @ObservedObject private var aiEngine = HybridIntelligenceEngine.shared
    @ObservedObject private var cloudService = SupabaseCloudService.shared
    @ObservedObject private var torchService = TorchService.shared
    @ObservedObject private var audioService = AudioAlertService.shared
    
    @Namespace private var bentoGlassNamespace
    @State private var activeCompartment: BentoCompartment = .previewDome
    @State private var dropletMorphScaleX: CGFloat = 1.0
    @State private var dropletMorphScaleY: CGFloat = 1.0
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var customWallpaperImage: UIImage? = nil
    @AppStorage("wallpaperPresetIndex") private var wallpaperPresetIndex: Int = 0
    
    @State private var previewOffset: CGFloat = -36
    @State private var isButtonPressed: Bool = false
    
    @AppStorage("appLanguage") private var appLanguage: String = "auto"
    @Environment(\.scenePhase) private var scenePhase
    
    public init() {}
    
    public var body: some View {
        navigationContainer
            .id(appLanguage)
            .environment(\.locale, appLanguage == "auto" ? .current : Locale(identifier: appLanguage))
            .preferredColorScheme(.dark)
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
            .onAppear {
                loadSavedWallpaper()
                motionDetector.start(direction: selectedDirection)
                LocationService.shared.requestLocation()
            }
            .onChange(of: motionDetector.isOverheadSwinging) { _, isSwinging in
                guard !isShowingMagicBattle && !isShowingSurvivalBeacon else { return }
                if isSwinging && !isShowingPOV {
                    isShowingPOV = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    motionDetector.start(direction: selectedDirection)
                } else {
                    motionDetector.stop()
                }
            }
    }
    
    @ViewBuilder
    private var navigationContainer: some View {
        NavigationStack {
            mainBentoScrollContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leadingBrandTitle
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarButtons
                    }
                }
        }
        .sheet(isPresented: $isShowingHelp) {
            TutorialHelpSheet()
        }
        .sheet(isPresented: $isShowingSettings) {
            quickSettingsSheet
        }
        .sheet(isPresented: $isShowingTraining) {
            SamplingView()
        }
        .fullScreenCover(isPresented: $isShowingSurvivalBeacon) {
            BlackoutSurvivalBeaconView(onDismiss: {
                isShowingSurvivalBeacon = false
            })
        }
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
        .fullScreenCover(isPresented: $isShowingMagicBattle) {
            POVMagicBattleView()
        }
    }
    
    @ViewBuilder
    private var mainBentoScrollContent: some View {
        ZStack {
            wallpaperBackgroundLayer
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    revolverModeDial
                    
                    if let suggestion = aiEngine.aiSuggestionMessage {
                        aiProposalGlassBanner(message: suggestion)
                    }
                    
                    bentoPreviewCompartment
                    
                    HStack(spacing: 12) {
                        bentoRangeModeCompartment
                        bentoSpecialActionCompartment
                    }
                    
                    bentoWordPaletteCompartment
                    
                    bentoQuickSignalCompartment
                    
                    liquidGlassTransmissionButton
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
    }
    
    @ViewBuilder
    private var leadingBrandTitle: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(operationalMode.accentColor)
                .frame(width: 8, height: 8)
                .shadow(color: operationalMode.accentColor, radius: 5)
            Text("RescuePOV")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var trailingToolbarButtons: some View {
        HStack(spacing: 8) {
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("写真フォルダから壁紙を選択", systemImage: "photo.on.rectangle")
                }
                Button(action: {
                    customWallpaperImage = nil
                    saveCustomWallpaper(nil)
                    wallpaperPresetIndex = (wallpaperPresetIndex + 1) % 3
                }) {
                    Label("内蔵グラデーション壁紙を切替", systemImage: "sparkles.rectangle.stack")
                }
            } label: {
                Image(systemName: "photo.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appLanguage = (appLanguage == "en") ? "auto" : "en"
            }) {
                Text(appLanguage == "en" ? "EN" : "JP")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingTraining = true
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path.ecg")
                    Text("練習")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.cyan.opacity(0.6), lineWidth: 1))
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingSettings = true
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingHelp = true
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
    
    @ViewBuilder
    private var wallpaperBackgroundLayer: some View {
        GeometryReader { geo in
            ZStack {
                if let customImg = customWallpaperImage {
                    Image(uiImage: customImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(Color.black.opacity(0.35))
                } else {
                    presetGradientBackground
                }
            }
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var presetGradientBackground: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.06)
            
            Circle()
                .fill(operationalMode.accentColor.opacity(0.38))
                .frame(width: 340, height: 340)
                .blur(radius: 75)
                .offset(x: -90, y: -180)
            
            Circle()
                .fill(operationalMode.secondaryColor.opacity(0.32))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 110, y: 160)
            
            if wallpaperPresetIndex == 1 {
                Circle()
                    .fill(Color.purple.opacity(0.30))
                    .frame(width: 260, height: 260)
                    .blur(radius: 65)
                    .offset(x: 60, y: -60)
            } else if wallpaperPresetIndex == 2 {
                Circle()
                    .fill(Color.mint.opacity(0.28))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: -40, y: 80)
            }
        }
    }
    
    @ViewBuilder
    private func bentoCompartmentBackground(for compartment: BentoCompartment, tint: Color, cornerRadius: CGFloat = 24) -> some View {
        let isSelected = (activeCompartment == compartment)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        ZStack {
            shape.fill(.ultraThinMaterial)
            
            shape.fill(
                LinearGradient(
                    colors: [tint.opacity(isSelected ? 0.28 : 0.14), tint.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(isSelected ? 0.28 : 0.14), Color.white.opacity(0.02), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .padding(1)
            
            if isSelected {
                selectedDropletOverlay(shape: shape, tint: tint)
            } else {
                unselectedCompartmentBorder(shape: shape, tint: tint)
            }
        }
    }
    
    @ViewBuilder
    private func selectedDropletOverlay(shape: RoundedRectangle, tint: Color) -> some View {
        let borderGrad = LinearGradient(
            colors: [.white, tint, .white.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        shape
            .fill(tint.opacity(0.12))
            .overlay(shape.stroke(borderGrad, lineWidth: 2.2))
            .shadow(color: tint.opacity(0.55), radius: 14, y: 4)
            .scaleEffect(x: dropletMorphScaleX, y: dropletMorphScaleY)
            .matchedGeometryEffect(id: "FLOATING_LIQUID_DROPLET", in: bentoGlassNamespace)
    }
    
    @ViewBuilder
    private func unselectedCompartmentBorder(shape: RoundedRectangle, tint: Color) -> some View {
        let borderGrad = LinearGradient(
            colors: [Color.white.opacity(0.45), tint.opacity(0.35), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        shape.stroke(borderGrad, lineWidth: 1.2)
    }
    
    private func selectCompartment(_ compartment: BentoCompartment) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            activeCompartment = compartment
        }
        withAnimation(.easeOut(duration: 0.10)) {
            dropletMorphScaleX = 1.03
            dropletMorphScaleY = 0.97
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                dropletMorphScaleX = 1.0
                dropletMorphScaleY = 1.0
            }
        }
    }
    
    @ViewBuilder
    private var revolverModeDial: some View {
        HStack(spacing: 8) {
            ForEach(AppOperationalMode.allCases) { mode in
                revolverModeItem(for: mode)
            }
        }
        .padding(5)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
    
    @ViewBuilder
    private func revolverModeItem(for mode: AppOperationalMode) -> some View {
        let isSelected = (operationalMode == mode)
        let iconName = (mode == .rescue) ? "light.beacon.max.fill" : "party.popper.fill"
        
        Button(action: {
            guard operationalMode != mode else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.68)) {
                operationalMode = mode
                if mode == .party {
                    targetText = "HAPPY"
                    selectedColor = .cyan
                    voiceService.isVoiceSyncEnabled = false
                } else {
                    targetText = "HELP"
                    selectedColor = .white
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(revolverItemBackground(for: mode, isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func revolverItemBackground(for mode: AppOperationalMode, isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [mode.accentColor.opacity(0.65), mode.accentColor.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: mode.accentColor.opacity(0.5), radius: 8, y: 2)
        } else {
            Color.clear
        }
    }
    
    @ViewBuilder
    private var bentoPreviewCompartment: some View {
        let displayStr = targetText.isEmpty ? "HELP" : targetText
        let statusStr = String(format: "周期 %.1fHz ｜ 振幅 %.0f°", motionDetector.swingFrequencyHz, motionDetector.strokeAngleRange)
        
        VStack(spacing: 6) {
            previewTopHeader
            
            ZStack {
                Text(displayStr)
                    .font(.system(size: 42, weight: .black, design: .monospaced))
                    .foregroundColor(selectedColor.swiftUIColor.opacity(0.35))
                    .blur(radius: 5)
                    .offset(x: previewOffset * 0.45)
                
                Text(displayStr)
                    .font(.system(size: 44, weight: .black, design: .monospaced))
                    .foregroundColor(selectedColor.swiftUIColor)
                    .shadow(color: selectedColor.swiftUIColor, radius: 14)
                    .offset(x: previewOffset)
            }
            .frame(height: 68)
            
            HStack {
                Label("120Hz OLED 黒締め", systemImage: "sparkles")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(statusStr)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(bentoCompartmentBackground(for: .previewDome, tint: operationalMode.accentColor, cornerRadius: 26))
        .onTapGesture {
            selectCompartment(.previewDome)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                previewOffset = 36
            }
        }
    }
    
    @ViewBuilder
    private var previewTopHeader: some View {
        let paletteColors: [POVColor] = [.white, .red, .yellow, .cyan, .green, .magenta]
        
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 11))
                Text(motionDetector.activeRangeMode.shortTitle)
                    .font(.system(size: 10.5, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(operationalMode.accentColor.opacity(0.45)))
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
            
            Spacer()
            
            HStack(spacing: 6) {
                ForEach(paletteColors, id: \.id) { col in
                    colorDotButton(for: col)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }
    
    @ViewBuilder
    private func colorDotButton(for col: POVColor) -> some View {
        let isColSelected = (selectedColor == col)
        let dotSize: CGFloat = isColSelected ? 18 : 13
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedColor = col
            selectCompartment(.previewDome)
        }) {
            Circle()
                .fill(col.swiftUIColor)
                .frame(width: dotSize, height: dotSize)
                .overlay(Circle().stroke(Color.white, lineWidth: isColSelected ? 2.0 : 0.6))
                .shadow(color: col.swiftUIColor.opacity(0.8), radius: isColSelected ? 5 : 0)
        }
    }
    
    @ViewBuilder
    private var bentoRangeModeCompartment: some View {
        let mainModes: [POVDisplayRangeMode] = [.auto, .compactSnap, .wide, .zeroStatic]
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.cyan)
                Text("スイング振幅")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(mainModes) { mode in
                    rangeModeGridButton(for: mode)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bentoCompartmentBackground(for: .swingRange, tint: .cyan, cornerRadius: 22))
        .onTapGesture {
            selectCompartment(.swingRange)
        }
    }
    
    @ViewBuilder
    private func rangeModeGridButton(for mode: POVDisplayRangeMode) -> some View {
        let isSelected = (motionDetector.selectedRangeMode == mode)
        let bgFill = isSelected ? Color.cyan.opacity(0.45) : Color.black.opacity(0.28)
        let strokeCol = isSelected ? Color.white : Color.white.opacity(0.22)
        
        Button(action: {
            selectCompartment(.swingRange)
            motionDetector.selectedRangeMode = mode
        }) {
            Text(mode.shortTitle)
                .font(.system(size: 10, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bgFill))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(strokeCol, lineWidth: isSelected ? 1.4 : 0.8))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var bentoSpecialActionCompartment: some View {
        if operationalMode == .party {
            partyMagicBattleTile
        } else {
            rescueSurvivalBeaconTile
        }
    }
    
    @ViewBuilder
    private var partyMagicBattleTile: some View {
        Button(action: {
            selectCompartment(.specialAction)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isShowingMagicBattle = true
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.orange)
                    Text("MAGIC BATTLE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                Spacer(minLength: 2)
                Text("炎・水・雷・草\n空間属性バトル")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .lineSpacing(2)
                HStack {
                    Text("対戦開始")
                        .font(.system(size: 10.5, weight: .black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bentoCompartmentBackground(for: .specialAction, tint: .orange, cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var rescueSurvivalBeaconTile: some View {
        Button(action: {
            selectCompartment(.specialAction)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isShowingSurvivalBeacon = true
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.yellow)
                    Text("省電力ビーコン")
                        .font(.system(size: 11.5, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                }
                Spacer(minLength: 2)
                Text("画面消灯＋間欠\n閃光＆電子笛")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(2)
                HStack {
                    Text("手動起動")
                        .font(.system(size: 10.5, weight: .black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.yellow))
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.yellow)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bentoCompartmentBackground(for: .specialAction, tint: .yellow, cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var bentoWordPaletteCompartment: some View {
        let presets = (operationalMode == .rescue)
        ? ["HELP", "SOS", "たすけて", "ココ", "孤立", "119", "OK"]
        : ["HAPPY", "CHEERS", "LOVE", "CONGRAT", "YES!", "THANKS"]
        
        VStack(alignment: .leading, spacing: 10) {
            wordInputFieldRow
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { word in
                        presetWordCapsule(word: word)
                    }
                }
            }
        }
        .padding(12)
        .background(bentoCompartmentBackground(for: .wordPalette, tint: .purple, cornerRadius: 22))
        .onTapGesture {
            selectCompartment(.wordPalette)
        }
    }
    
    @ViewBuilder
    private var wordInputFieldRow: some View {
        HStack(spacing: 8) {
            wordInputIcon
            wordInputTextField
            directionToggleButton
            wordClearButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(wordInputRowBackground)
        .overlay(wordInputRowBorder)
    }
    
    @ViewBuilder
    private var wordInputIcon: some View {
        Image(systemName: "pencil.and.outline")
            .foregroundColor(operationalMode.accentColor)
            .font(.system(size: 14, weight: .bold))
    }
    
    @ViewBuilder
    private var wordInputTextField: some View {
        TextField("表示文字を入力", text: $targetText)
            .font(.system(size: 16, weight: .black, design: .monospaced))
            .foregroundColor(.white)
            .onTapGesture {
                selectCompartment(.wordPalette)
            }
    }
    
    @ViewBuilder
    private var directionToggleLabel: some View {
        let isHorizontal = (selectedDirection == .horizontal)
        let title: String = isHorizontal ? "横振り" : "縦振り"
        HStack(spacing: 4) {
            Image(systemName: selectedDirection.iconName)
            Text(title)
        }
        .font(.system(size: 10.5, weight: .bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.18)))
        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
        .foregroundColor(.white)
    }
    
    @ViewBuilder
    private var directionToggleButton: some View {
        Button(action: {
            selectCompartment(.wordPalette)
            selectedDirection = (selectedDirection == .horizontal) ? .vertical : .horizontal
            motionDetector.start(direction: selectedDirection)
        }) {
            directionToggleLabel
        }
    }
    
    @ViewBuilder
    private var wordClearButton: some View {
        if !targetText.isEmpty {
            Button(action: { targetText = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    @ViewBuilder
    private var wordInputRowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.32))
    }
    
    @ViewBuilder
    private var wordInputRowBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
    }
    
    @ViewBuilder
    private func presetWordCapsule(word: String) -> some View {
        let isSelected = (targetText == word)
        let fillCol = isSelected ? operationalMode.accentColor.opacity(0.55) : Color.black.opacity(0.28)
        let strokeCol = isSelected ? Color.white : Color.white.opacity(0.28)
        
        Button(action: {
            selectCompartment(.wordPalette)
            targetText = word
        }) {
            Text(word)
                .font(.system(size: 12.5, weight: .black, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(fillCol))
                .overlay(Capsule().stroke(strokeCol, lineWidth: isSelected ? 1.5 : 0.9))
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var bentoQuickSignalCompartment: some View {
        HStack(spacing: 8) {
            quickGlassActionButton(
                title: torchService.isTorchOn ? "ライトON" : "背面ライト",
                icon: torchService.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                tint: .orange,
                isActive: torchService.isTorchOn
            ) {
                selectCompartment(.emergencySignal)
                torchService.toggleTorch()
            }
            
            quickGlassActionButton(
                title: torchService.isSOSActive ? "SOS発信中" : "SOS点滅",
                icon: "bolt.badge.automatic.fill",
                tint: .red,
                isActive: torchService.isSOSActive
            ) {
                selectCompartment(.emergencySignal)
                torchService.toggleSOS()
            }
            
            quickGlassActionButton(
                title: audioService.isPlaying ? "吹鳴中" : "ホイッスル",
                icon: audioService.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                tint: .yellow,
                isActive: audioService.isPlaying
            ) {
                selectCompartment(.emergencySignal)
                audioService.toggleAlert()
            }
            
            quickGlassActionButton(
                title: "バトル",
                icon: "sparkles",
                tint: .cyan,
                isActive: false
            ) {
                selectCompartment(.emergencySignal)
                isShowingMagicBattle = true
            }
        }
        .padding(10)
        .background(bentoCompartmentBackground(for: .emergencySignal, tint: .mint, cornerRadius: 22))
    }
    
    @ViewBuilder
    private func quickGlassActionButton(title: String, icon: String, tint: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        let bgFill = isActive ? tint.opacity(0.65) : Color.black.opacity(0.28)
        let strokeCol = isActive ? Color.white : tint.opacity(0.45)
        
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 9.5, weight: .heavy))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bgFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(strokeCol, lineWidth: isActive ? 1.6 : 1.0))
            .foregroundColor(.white)
            .shadow(color: isActive ? tint.opacity(0.6) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func aiProposalGlassBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(.cyan)
                .font(.system(size: 14, weight: .bold))
            
            Text(message)
                .font(.system(size: 11, weight: .semibold))
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
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.6), lineWidth: 1.2))
    }
    
    @ViewBuilder
    private var liquidGlassTransmissionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isShowingPOV = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                Text((operationalMode == .rescue) ? "救難POV空間照射を開始" : "パーティーPOV空間照射を開始")
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .background(transmissionButtonBackground)
        .overlay(transmissionButtonBorder)
        .cornerRadius(24)
        .shadow(color: operationalMode.glassGlow, radius: 16, y: 6)
        .scaleEffect(isButtonPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
    }
    
    @ViewBuilder
    private var transmissionButtonBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            operationalMode.accentColor.opacity(0.85),
                            operationalMode.secondaryColor.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    @ViewBuilder
    private var transmissionButtonBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.white, .white.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.8
            )
    }
    
    // MARK: - クイック設定シート（セクションごとに分割して型推論タイムアウトを完全防止）
    @ViewBuilder
    private var quickSettingsSheet: some View {
        NavigationStack {
            Form {
                opticsSettingsSection
                voiceSyncSettingsSection
                emergencyEmailSettingsSection
                aiSituationSettingsSection
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
    
    @ViewBuilder
    private var opticsSettingsSection: some View {
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
    }
    
    @ViewBuilder
    private var voiceSyncSettingsSection: some View {
        Section(header: Text("叫び声AI音声同期")) {
            Toggle("叫び声をマイクで拾って文字に反映", isOn: $voiceService.isVoiceSyncEnabled)
            if voiceService.isVoiceSyncEnabled {
                Toggle("声が止んだら元の文字に復帰", isOn: $voiceService.autoResetToDefault)
            }
        }
    }
    
    @ViewBuilder
    private var emergencyEmailSettingsSection: some View {
        Section(header: Text("緊急救難SOSメール自動配信（Google連携）")) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.green)
                Text("送信元Google")
                Spacer()
                Text(cloudService.senderGmail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .foregroundColor(.red)
                Text("通知先（ご家族等）")
                Spacer()
                TextField("例: family@example.com", text: $cloudService.emergencyRecipientEmail)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.cyan)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            
            Text("※SOS発動時、通知先（ご家族宛て）に【暗号化されたリアルタイムGPS地図リンク】と【ワンタイム合鍵】が自動送信されます。送信元（ご本人Gmail）にも控えが自動送信されます。")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
    
    @ViewBuilder
    private var aiSituationSettingsSection: some View {
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
    
    // MARK: - 壁紙保存・復元ヘルパー
    private func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        Task {
            if let data = try? await newItem.loadTransferable(type: Data.self),
               let uiImg = UIImage(data: data) {
                await MainActor.run {
                    self.customWallpaperImage = uiImg
                    saveCustomWallpaper(data)
                }
            }
        }
    }
    
    private func saveCustomWallpaper(_ data: Data?) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("custom_wallpaper.jpg")
        if let data = data {
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func loadSavedWallpaper() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("custom_wallpaper.jpg")
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            self.customWallpaperImage = img
        }
    }
}

// MARK: - 手動起動「ブラックアウト・サバイバル・ビーコン」専用画面（OLED完全消灯＋間欠閃光＆ホイッスル）
public struct BlackoutSurvivalBeaconView: View {
    public var onDismiss: () -> Void
    
    @State private var intervalSeconds: Double = 8.0
    @State private var countdown: Int = 8
    @State private var isFlashingNow: Bool = false
    @State private var useWhistle: Bool = true
    @State private var useTorch: Bool = true
    @State private var previousBrightness: CGFloat = 0.5
    @State private var beaconTimer: Timer? = nil
    
    public var body: some View {
        ZStack {
            (isFlashingNow ? Color.red : Color.black)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.yellow)
                    Text("BLACKOUT SURVIVAL BEACON")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.top, 24)
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2)
                        .frame(width: 150, height: 150)
                    
                    VStack(spacing: 6) {
                        Text("\(countdown)")
                            .font(.system(size: 54, weight: .black, design: .monospaced))
                            .foregroundColor(isFlashingNow ? .white : .yellow.opacity(0.75))
                        Text("秒後に自動閃光")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                
                Text("有機EL完全消灯によりバッテリーを極限まで温存しながら\n8秒おきに【背面フラッシュ閃光＋3kHz救助笛】を発信します")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                
                HStack(spacing: 16) {
                    Toggle("背面LED閃光", isOn: $useTorch)
                        .toggleStyle(.button)
                        .tint(.orange)
                    Toggle("3kHz電子笛", isOn: $useWhistle)
                        .toggleStyle(.button)
                        .tint(.yellow)
                }
                .font(.caption.bold())
                
                Spacer()
                
                Button(action: {
                    stopBeacon()
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("サバイバル・ビーコンを終了して戻る")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1.2))
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .statusBarHidden(true)
        .onAppear {
            startBeacon()
        }
        .onDisappear {
            stopBeacon()
        }
    }
    
    private func startBeacon() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.02
        UIApplication.shared.isIdleTimerDisabled = true
        MotionDetector.shared.stop()
        
        countdown = Int(intervalSeconds)
        beaconTimer?.invalidate()
        beaconTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 1 {
                countdown -= 1
            } else {
                triggerSurvivalPulse()
                countdown = Int(intervalSeconds)
            }
        }
    }
    
    private func triggerSurvivalPulse() {
        isFlashingNow = true
        UIScreen.main.brightness = 1.0
        
        if useTorch {
            TorchService.shared.toggleTorch()
        }
        if useWhistle && !AudioAlertService.shared.isPlaying {
            AudioAlertService.shared.start()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            isFlashingNow = false
            UIScreen.main.brightness = 0.02
            if TorchService.shared.isTorchOn {
                TorchService.shared.toggleTorch()
            }
            if AudioAlertService.shared.isPlaying {
                AudioAlertService.shared.stop()
            }
        }
    }
    
    private func stopBeacon() {
        beaconTimer?.invalidate()
        beaconTimer = nil
        UIScreen.main.brightness = previousBrightness
        if TorchService.shared.isTorchOn {
            TorchService.shared.toggleTorch()
        }
        if AudioAlertService.shared.isPlaying {
            AudioAlertService.shared.stop()
        }
    }
}
