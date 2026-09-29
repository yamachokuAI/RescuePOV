import SwiftUI

/// 実機スイング・ヒステリシス計測＆シンクロトレーニング画面
public struct SamplingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sampler = MotionSampler.shared
    @ObservedObject private var detector = MotionDetector.shared
    
    @State private var copiedNotice: String?
    @State private var calibrationAppliedNotice: String?
    @State private var isTrainingMode: Bool = true
    
    // 教師データ（光る球）アニメーション用
    @State private var orbPhase: Double = 0.0
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 1. タイトル＆概要説明
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.cyan)
                                .font(.title3)
                            Text("スイング・ヒステリシス同期トレーニング")
                                .font(.headline.bold())
                                .foregroundColor(.white)
                            Spacer()
                            if detector.isUserCalibrated {
                                Text("校正済🟢")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.25)))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text("人間が腕を左右に振る運動には筋肉の非対称性（ヒステリシス）が存在します。下のグラフの【光る球（教師データ）】のテンポに合わせて手を左右に振ることで、あなたの動きとiPhoneの発光タイミングを極限まで同期させます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.1)))
                    
                    // 2. 【ヒステリシス曲線 ＆ 光る球の教師データビジュアライザー】
                    VStack(spacing: 12) {
                        HStack {
                            Label("スイング・ヒステリシス位相ループ", systemImage: "circle.circle.fill")
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                            Spacer()
                            Text("横軸: 角度 ｜ 縦軸: 角速度")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        
                        // ヒステリシス曲線キャンバス
                        HysteresisGraphView(
                            orbPhase: orbPhase,
                            asymmetryRatio: detector.userAsymmetryRatio,
                            userTheta: detector.currentAngleDegrees,
                            userGyro: detector.currentGyroZ,
                            isEmitting: detector.isEmitting
                        )
                        .frame(height: 220)
                        
                        // ガイドテキスト
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 8, height: 8)
                            Text("光る球が緑の【最高速発光ゾーン】を通過する瞬間に合わせて振ってください")
                                .font(.caption2.bold())
                                .foregroundColor(.yellow)
                        }
                        .padding(.vertical, 4)
                        
                        // リアルタイムシンクロ率インジケーター
                        HStack {
                            Text("リアルタイム角速度:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f rad/s", detector.currentGyroZ))
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundColor(.white)
                            Spacer()
                            Text("現在のスイング角度:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f°", detector.currentAngleDegrees))
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundColor(.cyan)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
                    
                    // 3. 【実機サンプリング＆キャリブレーション計測】
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("実機キャリブレーション計測（10往復）")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            if sampler.isRecording {
                                Text("REC")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        if sampler.isRecording {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.cyan)
                                Text("頭上で大きく左右に振ってください")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("進行: \(sampler.detectedSwings / 2) / \(sampler.targetSwings) 往復")
                                    .font(.title3.monospacedDigit().bold())
                                    .foregroundColor(.cyan)
                                Text("取得サンプル数: \(sampler.sampleCount) 件 (100Hz)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Text("「10往復計測を開始」を押し、頭上で左右にリズムよく10回往復させてください。あなたの腕の振りの非対称性を解析し、最適な発光タイミングを学習します。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineSpacing(3)
                        }
                        
                        // 計測開始/中断ボタン
                        Button(action: {
                            if sampler.isRecording {
                                sampler.stopSampling()
                            } else {
                                sampler.startSampling(targetSwings: 10)
                            }
                        }) {
                            HStack {
                                Image(systemName: sampler.isRecording ? "stop.circle.fill" : "record.circle")
                                Text(sampler.isRecording ? "計測を中断" : "10往復サンプリング計測を開始")
                            }
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(sampler.isRecording ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
                    
                    // 4. 【解析結果＆キャリブレーション適用カード】
                    if let profile = sampler.profile {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("【計測結果プロファイル】")
                                    .font(.headline.bold())
                                    .foregroundColor(.green)
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("往路ピーク加速度")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f G", profile.forwardPeakAccel))
                                        .font(.title3.monospacedDigit().bold())
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("復路ピーク加速度")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f G", profile.backwardPeakAccel))
                                        .font(.title3.monospacedDigit().bold())
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("非対称比 (往/復)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f", profile.asymmetryRatio))
                                        .font(.title3.monospacedDigit().bold())
                                        .foregroundColor(.yellow)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
                            
                            // キャリブレーション即時適用ボタン
                            Button(action: {
                                detector.saveCalibration(
                                    asymmetryRatio: profile.asymmetryRatio,
                                    strokeWidthRad: 1.65 // 平均振れ幅
                                )
                                showCalibrationNotice("✅ キャリブレーションを保存・適用しました！")
                            }) {
                                HStack {
                                    Image(systemName: "slider.horizontal.2.square.on.square")
                                    Text("この結果を発光タイミングに適用する")
                                }
                                .font(.headline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color.green, Color(red: 0.1, green: 0.7, blue: 0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.black)
                                .cornerRadius(12)
                            }
                            
                            if let notice = calibrationAppliedNotice {
                                Text(notice)
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            
                            Divider().background(Color.white.opacity(0.15))
                            
                            // データコピーボタン
                            VStack(spacing: 8) {
                                Button(action: {
                                    UIPasteboard.general.string = sampler.summaryReport()
                                    showCopied("要約レポートをコピーしました")
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("要約レポートをコピー（チャット用）")
                                    }
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                                    .foregroundColor(.white)
                                }
                                
                                Button(action: {
                                    UIPasteboard.general.string = sampler.exportCSV()
                                    showCopied("全100Hz CSVデータをコピーしました")
                                }) {
                                    HStack {
                                        Image(systemName: "tablecells.badge.ellipsis")
                                        Text("100Hz CSV生データを全コピー")
                                    }
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                                    .foregroundColor(.cyan)
                                }
                            }
                            
                            if let notice = copiedNotice {
                                Text(notice)
                                    .font(.caption.bold())
                                    .foregroundColor(.cyan)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
                    }
                    
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("スイング・ヒステリシス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .onReceive(timer) { _ in
                // 教師データの光る球を一定リズムで周回（周期約0.9秒）
                orbPhase += 0.070
                if orbPhase > Double.pi * 2 {
                    orbPhase -= Double.pi * 2
                }
            }
            .onAppear {
                detector.start(direction: .horizontal)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func showCopied(_ msg: String) {
        copiedNotice = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copiedNotice = nil
        }
    }
    
    private func showCalibrationNotice(_ msg: String) {
        calibrationAppliedNotice = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            calibrationAppliedNotice = nil
        }
    }
}

/// ヒステリシス曲線（B-Hループ風）＆光る球ビジュアライザー
public struct HysteresisGraphView: View {
    let orbPhase: Double
    let asymmetryRatio: Double
    let userTheta: Double
    let userGyro: Double
    let isEmitting: Bool
    
    public var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2.0
            let cy = h / 2.0
            
            let scaleX = w * 0.40
            let scaleY = h * 0.36
            
            // 1. 背景グリッドと座標軸
            var axisPath = Path()
            // 横軸（スイング角度 H）
            axisPath.move(to: CGPoint(x: 10, y: cy))
            axisPath.addLine(to: CGPoint(x: w - 10, y: cy))
            // 縦軸（角速度 B）
            axisPath.move(to: CGPoint(x: cx, y: 15))
            axisPath.addLine(to: CGPoint(x: cx, y: h - 15))
            
            ctx.stroke(axisPath, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
            
            // 軸ラベル
            ctx.draw(Text("-θ (左端)").font(.system(size: 9)).foregroundColor(.gray), at: CGPoint(x: 30, y: cy + 12))
            ctx.draw(Text("+θ (右端)").font(.system(size: 9)).foregroundColor(.gray), at: CGPoint(x: w - 30, y: cy + 12))
            ctx.draw(Text("+ω 往路(右へ)").font(.system(size: 9)).foregroundColor(.cyan), at: CGPoint(x: cx + 45, y: 22))
            ctx.draw(Text("-ω 復路(左へ)").font(.system(size: 9)).foregroundColor(.cyan), at: CGPoint(x: cx + 45, y: h - 22))
            
            // 2. ヒステリシス曲線の計算
            // 往路（上側の弧）: 左から右へ
            let fwdScale = 1.0
            let bwdScale = max(min(1.0 / asymmetryRatio, 1.4), 0.7)
            
            var loopPath = Path()
            let steps = 60
            
            // 往路: s = -1.0 -> 1.0 (上側)
            for i in 0...steps {
                let s = -1.0 + 2.0 * Double(i) / Double(steps)
                let px = cx + CGFloat(s) * scaleX
                let curve = pow(max(1.0 - s * s, 0.0), 0.65)
                let py = cy - CGFloat(curve) * scaleY * CGFloat(fwdScale)
                if i == 0 {
                    loopPath.move(to: CGPoint(x: px, y: py))
                } else {
                    loopPath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            
            // 復路: s = 1.0 -> -1.0 (下側)
            for i in 0...steps {
                let s = 1.0 - 2.0 * Double(i) / Double(steps)
                let px = cx + CGFloat(s) * scaleX
                let curve = pow(max(1.0 - s * s, 0.0), 0.65)
                let py = cy + CGFloat(curve) * scaleY * CGFloat(bwdScale)
                loopPath.addLine(to: CGPoint(x: px, y: py))
            }
            loopPath.closeSubpath()
            
            // ループ背景のうっすらシアン塗り
            ctx.fill(loopPath, with: .color(Color.cyan.opacity(0.06)))
            // ベース曲線のストローク
            ctx.stroke(loopPath, with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
            
            // 3. 【最高速発光ゾーン（中央域）のハイライトネオン】
            var emitPath = Path()
            // 往路の発光ゾーン (s = -0.70 -> +0.70)
            for i in 0...30 {
                let s = -0.70 + 1.40 * Double(i) / 30.0
                let px = cx + CGFloat(s) * scaleX
                let curve = pow(max(1.0 - s * s, 0.0), 0.65)
                let py = cy - CGFloat(curve) * scaleY * CGFloat(fwdScale)
                if i == 0 {
                    emitPath.move(to: CGPoint(x: px, y: py))
                } else {
                    emitPath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            // 復路の発光ゾーン (s = +0.70 -> -0.70)
            var emitBwdPath = Path()
            for i in 0...30 {
                let s = 0.70 - 1.40 * Double(i) / 30.0
                let px = cx + CGFloat(s) * scaleX
                let curve = pow(max(1.0 - s * s, 0.0), 0.65)
                let py = cy + CGFloat(curve) * scaleY * CGFloat(bwdScale)
                if i == 0 {
                    emitBwdPath.move(to: CGPoint(x: px, y: py))
                } else {
                    emitBwdPath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            
            ctx.stroke(emitPath, with: .color(Color.green), lineWidth: 3.5)
            ctx.stroke(emitBwdPath, with: .color(Color.green), lineWidth: 3.5)
            
            // 発光ゾーン注記
            ctx.draw(Text("⚡️最高速発光ゾーン").font(.system(size: 9).bold()).foregroundColor(.green), at: CGPoint(x: cx, y: cy - scaleY - 8))
            
            // 4. 【教師データ: 光る球（オーブ）の位置と描画】
            let s = -cos(orbPhase)
            let isForward = sin(orbPhase) >= 0
            let orbCurve = pow(max(1.0 - s * s, 0.0), 0.65)
            let orbY = isForward ? (cy - CGFloat(orbCurve) * scaleY * CGFloat(fwdScale)) : (cy + CGFloat(orbCurve) * scaleY * CGFloat(bwdScale))
            let orbX = cx + CGFloat(s) * scaleX
            
            let isInEmitZone = abs(s) <= 0.70
            let orbRadius: CGFloat = isInEmitZone ? 9.0 : 6.0
            let orbColor = isInEmitZone ? Color.yellow : Color.white
            
            // 外側グロー
            let glowRect = CGRect(x: orbX - orbRadius * 2.0, y: orbY - orbRadius * 2.0, width: orbRadius * 4.0, height: orbRadius * 4.0)
            ctx.fill(Path(ellipseIn: glowRect), with: .color(orbColor.opacity(isInEmitZone ? 0.45 : 0.2)))
            
            // 内側コア球
            let coreRect = CGRect(x: orbX - orbRadius, y: orbY - orbRadius, width: orbRadius * 2.0, height: orbRadius * 2.0)
            ctx.fill(Path(ellipseIn: coreRect), with: .color(orbColor))
            
            // 5. 【ユーザーのリアルタイムスイングポインタ（赤）】
            let clampedTheta = min(max(userTheta / 50.0, -1.0), 1.0)
            let userPx = cx + CGFloat(clampedTheta) * scaleX
            let clampedGyro = min(max(userGyro / 4.5, -1.0), 1.0)
            let userPy = cy - CGFloat(clampedGyro) * scaleY
            
            let userRadius: CGFloat = isEmitting ? 8.0 : 5.0
            let userGlowRect = CGRect(x: userPx - userRadius * 1.8, y: userPy - userRadius * 1.8, width: userRadius * 3.6, height: userRadius * 3.6)
            ctx.fill(Path(ellipseIn: userGlowRect), with: .color(Color.red.opacity(0.4)))
            
            let userCoreRect = CGRect(x: userPx - userRadius, y: userPy - userRadius, width: userRadius * 2.0, height: userRadius * 2.0)
            ctx.fill(Path(ellipseIn: userCoreRect), with: .color(Color.red))
            
            // ポインタラベル
            ctx.draw(Text("あなた").font(.system(size: 8).bold()).foregroundColor(.red), at: CGPoint(x: userPx, y: userPy - 12))
        }
    }
}
