import SwiftUI

/// 実機で10往復スイングを計測・ヒステリシス解析するサンプリングシート画面
public struct SamplingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sampler = MotionSampler.shared
    
    @State private var copiedNotice: String?
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 説明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("実機スイング・ヒステリシス計測")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("端末を右手または左手に持ち、開始ボタンを押してから頭上で左右に約10往復大きく振ってください。100Hzで精密サンプリングし、往路と復路の非対称速度曲線を抽出します。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.1)))
                    
                    // 計測ステータスカード
                    VStack(spacing: 16) {
                        if sampler.isRecording {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(1.3)
                                    .tint(.green)
                                Text("計測中...")
                                    .font(.headline.bold())
                                    .foregroundColor(.green)
                                Text("左右に振ってください: \(sampler.detectedSwings / 2) / \(sampler.targetSwings) 往復")
                                    .font(.title3.monospacedDigit().bold())
                                    .foregroundColor(.white)
                                Text("取得サンプル: \(sampler.sampleCount) 件")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        } else {
                            Text(sampler.statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.yellow)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                        }
                        
                        // 計測開始/停止ボタン
                        Button(action: {
                            if sampler.isRecording {
                                sampler.stopSampling()
                            } else {
                                sampler.startSampling(targetSwings: 10)
                            }
                        }) {
                            HStack {
                                Image(systemName: sampler.isRecording ? "stop.circle.fill" : "record.circle")
                                Text(sampler.isRecording ? "計測を中断" : "10往復サンプリングを開始")
                            }
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(sampler.isRecording ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
                    
                    // 計測結果レポートカード（完了後表示）
                    if let profile = sampler.profile {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("【ヒステリシス解析結果】")
                                .font(.headline)
                                .foregroundColor(.green)
                            
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
                            
                            // コピーボタン群
                            VStack(spacing: 10) {
                                Button(action: {
                                    UIPasteboard.general.string = sampler.summaryReport()
                                    showCopied("要約レポートをコピーしました")
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("要約レポートをコピー（チャット用）")
                                    }
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.15)))
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
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                                    .foregroundColor(.green)
                                }
                            }
                            
                            if let notice = copiedNotice {
                                Text(notice)
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
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
            .navigationTitle("スイングサンプリング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.white)
                }
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
}
