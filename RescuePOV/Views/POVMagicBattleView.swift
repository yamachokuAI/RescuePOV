import SwiftUI
import AVFoundation

public struct POVMagicBattleView: View {
    @StateObject private var colorDetector = CameraColorDetector()
    @ObservedObject private var motionDetector = MotionDetector.shared
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var gameState: GameState = .ready
    @State private var countdownValue: Int = 0
    @State private var myElementSlices: [[Bool]] = []
    @State private var myImageSlices: [CGImage] = []
    @State private var matchTimer: Timer?
    @State private var myElement: MagicElement? = nil
    @State private var grassAngle: CGFloat? = nil
    @State private var battleResult: BattleResult? = nil
    
    @State private var myWins: Int = 0
    @State private var opponentWins: Int = 0
    @State private var totalMagicWins: Int = 0
    
    private let synthesizer = AVSpeechSynthesizer()
    
    enum GameState {
        case ready, counting, casting, resolving, finished
    }
    
    enum BattleResult {
        case win, lose, draw
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let element = myElement, gameState == .casting || gameState == .resolving {
                // 魔法発動中: HELPと全く同じPOVCanvasRepresentableを使用し、同じアルゴリズムで描画
                POVCanvasRepresentable(
                    slices: [],
                    imageSlices: myImageSlices,
                    rawText: "",
                    direction: element == .thunder ? .vertical : .horizontal,
                    color: .white,
                    slitWidth: 90.0, // HELPと同じ90.0
                    isDiagonal: element == .grass,
                    diagonalAngle: element == .grass ? grassAngle : nil,
                    activeDotRatio: 0.82 // HELPと同じ
                )
                .ignoresSafeArea()
            }
            
            if gameState == .finished, let result = battleResult {
                // 結果発表: YOU WIN / YOU LOSE / DRAW の文字を投影
                let isMatchOver = (myWins >= 3 || opponentWins >= 3)
                let resultText = result == .win ? (isMatchOver ? "CHAMPION" : "YOU WIN") : (result == .lose ? "YOU LOSE" : "DRAW")
                let resultColor: POVColor = result == .win ? .green : (result == .lose ? .red : .yellow)
                POVFullscreenView(
                    text: resultText,
                    direction: .horizontal,
                    color: resultColor,
                    mirrorForViewer: true,
                    onDismiss: { dismiss() }
                )
            }
            
            // 報酬クリーチャー（10, 100, 1000勝で出現）
            if totalMagicWins >= 10 && motionDetector.isEmitting {
                creatureOverlay
            }
            
            // UI Overlay (ゲーム進行)
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
                
                if gameState == .ready {
                    Button("SYNC & BATTLE START") {
                        startSyncTimer()
                    }
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(16)
                    
                    Text("Total Wins: \(totalMagicWins)")
                        .foregroundColor(.gray)
                        .padding(.top, 5)
                } else if gameState == .counting {
                    Text(countdownValue > 3 ? "WAIT..." : "\(countdownValue)")
                        .font(.system(size: countdownValue > 3 ? 40 : 120, weight: .black, design: .monospaced))
                        .foregroundColor(countdownValue > 3 ? .gray : .white)
                        
                    if countdownValue > 3 {
                        Text("\(countdownValue)s")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                } else if gameState == .casting && myElement == nil {
                    // 振り待ち中（加速度判定待ち）のUI
                    Text("SWING TO CAST!")
                        .font(.system(size: 40, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(16)
                    
                    Text("スマホを思いっきり振って\n魔法を発動しろ！")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                } else if gameState == .finished {
                    VStack(spacing: 20) {
                        Text(battleResult == .win ? "VICTORY!" : (battleResult == .lose ? "DEFEAT" : "DRAW"))
                            .font(.system(size: 50, weight: .black))
                            .foregroundColor(battleResult == .win ? .green : (battleResult == .lose ? .red : .yellow))
                            
                        Text("SCORE: \(myWins) - \(opponentWins)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        
                        if myWins >= 3 || opponentWins >= 3 {
                            Text("MATCH OVER!")
                                .font(.title)
                                .foregroundColor(myWins >= 3 ? .yellow : .gray)
                            
                            Button("NEW MATCH") {
                                resetMatch()
                            }
                            .font(.system(size: 20, weight: .bold))
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                        } else {
                            Button("NEXT ROUND") {
                                startSyncTimer()
                            }
                            .font(.system(size: 20, weight: .bold))
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .statusBarHidden(gameState != .ready)
        .onAppear {
            totalMagicWins = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: "totalMagicWins"))
            motionDetector.start(direction: .horizontal)
        }
        .onDisappear {
            colorDetector.stop()
            motionDetector.stop()
        }
    }
    
    private func resetMatch() {
        myWins = 0
        opponentWins = 0
        gameState = .ready
        myElement = nil
        battleResult = nil
    }

    private func startSyncTimer() {
        gameState = .counting
        myElement = nil
        grassAngle = nil
        battleResult = nil
        // POVFullscreenViewのonDisappearでストップされる可能性があるので、開始直前に再度起動する
        
        matchTimer?.invalidate()
        matchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            let seconds = Calendar.current.component(.second, from: Date())
            
            let diff: Int
            if seconds == 0 || seconds == 30 {
                diff = 0
            } else if seconds < 30 {
                diff = 30 - seconds
            } else {
                diff = 60 - seconds
            }
            
            if diff != self.countdownValue {
                self.countdownValue = diff
                
                if diff == 3 {
                    speak("3")
                } else if diff == 2 {
                    speak("2")
                } else if diff == 1 {
                    speak("1")
                }
            }
            
            if diff <= 0 {
                timer.invalidate()
                self.gameState = .casting
                self.speak("Go!")
                self.detectGestureAndCast()
            }
        }
    }
    
    private func detectGestureAndCast() {
        // バトル開始直前、確実にセンサーを再起動する（前回の終了画面で止められている場合があるため）
        motionDetector.start(direction: .horizontal)
        
        // バトル開始直後は「振り始め」を待つ
        let pollInterval = 0.05
        var waitTime = 0.0
        
        var isGathering = false
        var gatherTime = 0.0
        var accelXHistory: [Double] = []
        var accelYHistory: [Double] = []
        
        // 判定用のクロージャ
        func applyChosenElement(_ element: MagicElement) {
            self.myElement = element
            
            // サンダーの場合は縦振りなので、MotionDetectorを.verticalで再起動してstrokeProgressを縦軸(Y軸)に切り替える
            motionDetector.stop()
            motionDetector.start(direction: element == .thunder ? .vertical : .horizontal)
            
            // HELPと全く同じアルゴリズムで画像スライスを生成
            let uiImage = MagicImageGenerator.generateImage(for: element)
            self.myImageSlices = BitmapGenerator.shared.generateColorSlices(
                from: uiImage,
                targetSlices: 32
            )
            
            // 効果音の再生 (.m4a)
            AudioManager.shared.playMagicSound(for: element)
            self.speak(element.nameEnglish)
            
            // 判定開始：カメラを起動し、過去の判定結果をリセット
            let colorDetector = CameraColorDetector.shared
            colorDetector.detectedElement = nil
            colorDetector.start()
            
            // 最大10秒間振り続けることができる。相手の属性が判別でき次第即終了する。
            var elapsed = 0.0
            let checkInterval = 0.2
            
            Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { battleTimer in
                elapsed += checkInterval
                
                // 相手の色（属性）が判別できたか、または10秒経過したら判定に進む
                if colorDetector.detectedElement != nil || elapsed >= 10.0 {
                    battleTimer.invalidate()
                    colorDetector.stop() // バッテリー節約のため直ちにカメラ停止
                    self.resolveBattle()
                }
            }
        }
        
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { timer in
            waitTime += pollInterval
            
            if let motion = motionDetector.motionManager.deviceMotion {
                let x = motion.userAcceleration.x
                let y = motion.userAcceleration.y
                
                // 疲労対応: 時間が経つほど判定を極限まで緩くする (1.2G -> 0.4G)
                let currentThreshold = max(0.4, 1.2 - (waitTime * 0.4))
                
                if !isGathering {
                    if abs(x) > currentThreshold || abs(y) > currentThreshold {
                        isGathering = true
                    }
                }
                
                if isGathering {
                    gatherTime += pollInterval
                    accelXHistory.append(x)
                    accelYHistory.append(y)
                    
                    if gatherTime >= 0.75 { // 全体的に発動を遅らせて、すべての判定にかける時間を統一（誤判定防止）
                        timer.invalidate() // 判定終了
                        
                        var chosenElement: MagicElement = .fire
                        
                        let minX = accelXHistory.min() ?? 0
                        let maxX = accelXHistory.max() ?? 0
                        let minY = accelYHistory.min() ?? 0
                        let maxY = accelYHistory.max() ?? 0
                        
                        let rangeX = maxX - minX
                        let rangeY = maxY - minY
                        
                        // 草の判定: XY両方に大きな変動があり、かつどちらか一方が極端に強くない（さまざまな方向に切り替わる・円を描くなど）
                        let ratio = rangeX > 0 ? rangeY / rangeX : 0
                        if rangeX > 1.5 && rangeY > 1.5 && ratio > 0.6 && ratio < 1.6 {
                            chosenElement = .grass
                            
                            // 円の回転方向（右回りか左回りか）を外積の和で判定
                            var crossSum = 0.0
                            for i in 0..<(accelXHistory.count - 1) {
                                crossSum += accelXHistory[i] * accelYHistory[i+1] - accelXHistory[i+1] * accelYHistory[i]
                            }
                            // 画面の対角線角度を計算し、回転方向に応じて符号を変える
                            let screenAngle = atan2(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
                            self.grassAngle = crossSum > 0 ? screenAngle : -screenAngle
                            
                        } else {
                            // 最初の強い入力を探す
                            if let firstSigIndex = accelXHistory.firstIndex(where: { abs($0) > currentThreshold || abs(accelYHistory[accelXHistory.firstIndex(of: $0) ?? 0]) > currentThreshold }) {
                                let firstX = accelXHistory[firstSigIndex]
                                let firstY = accelYHistory[firstSigIndex]
                                
                                if abs(firstY) > abs(firstX) * 1.5 {
                                    // 縦振り（サンダー）
                                    chosenElement = .thunder
                                } else {
                                    // 横振り
                                    // 右から左（加速度はマイナスX）: 水
                                    // 左から右（加速度はプラスX）: 炎
                                    if firstX < 0 {
                                        chosenElement = .water
                                    } else {
                                        chosenElement = .fire
                                    }
                                }
                            }
                        }
                        
                        applyChosenElement(chosenElement)
                    }
                }
            }
            
            // 3秒経過しても振りが検知できない場合の強制フォールバック
            if !isGathering && waitTime > 3.0 {
                timer.invalidate()
                applyChosenElement(.fire)
            }
        }
    }
    
    private func resolveBattle() {
        AudioManager.shared.stopMagicSound()
        
        gameState = .resolving
        
        // 相手の属性が検出できた場合のみ勝敗判定を行う。検出できなかった場合は強制ドロー。
        if let opponent = colorDetector.detectedElement {
            if let result = myElement?.defeats(opponent) {
                battleResult = result ? .win : .lose
                if result {
                    myWins += 1
                    totalMagicWins += 1 // iCloud synced
                    NSUbiquitousKeyValueStore.default.set(Int64(totalMagicWins), forKey: "totalMagicWins")
                    NSUbiquitousKeyValueStore.default.synchronize()
                } else {
                    opponentWins += 1
                }
            } else {
                battleResult = .draw // あいこ
            }
        } else {
            // タイムアップで相手が見つからなかった
            battleResult = .draw
        }
        
        gameState = .finished
        
        if battleResult == .win {
            speak("You win")
        } else if battleResult == .lose {
            speak("You lose")
        } else {
            speak("Draw")
        }
    }
    
    @ViewBuilder
    private var creatureOverlay: some View {
        // POV投影中に浮かび上がる小さな妖精/クリーチャー
        let size: CGFloat = totalMagicWins >= 1000 ? 120 : (totalMagicWins >= 100 ? 80 : 50)
        let color: Color = totalMagicWins >= 1000 ? .purple : (totalMagicWins >= 100 ? Color(red: 1.0, green: 0.84, blue: 0.0) : .pink)
        
        GeometryReader { geo in
            Image(systemName: "hare.fill") // クリーチャーのアイコン
                .font(.system(size: size))
                .foregroundColor(color)
                .shadow(color: color, radius: 10)
                .position(
                    x: geo.size.width * CGFloat(motionDetector.strokeProgress),
                    y: geo.size.height * 0.2 // 上部に浮遊
                )
                .animation(.linear(duration: 0.1), value: motionDetector.strokeProgress)
        }
    }
    
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.55
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
    
    private func povColor(for element: MagicElement) -> POVColor {
        switch element {
        case .fire: return .red
        case .water: return .cyan
        case .grass: return .green
        case .thunder: return .yellow
        }
    }
}
