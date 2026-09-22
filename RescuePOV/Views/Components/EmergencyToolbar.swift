import SwiftUI

public struct EmergencyToolbar: View {
    @ObservedObject var torch = TorchService.shared
    @ObservedObject var audio = AudioAlertService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("緊急救助シグナル")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // 背面LEDトーチ
                Button(action: {
                    torch.toggleTorch()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: torch.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                        Text(torch.isTorchOn ? "ライトON" : "背面ライト")
                            .font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(torch.isTorchOn ? Color.orange : Color(white: 0.16))
                    )
                    .foregroundColor(torch.isTorchOn ? .black : .white)
                }
                
                // SOSモールス点滅
                Button(action: {
                    torch.toggleSOS()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .font(.title2)
                        Text(torch.isSOSActive ? "SOS発信中" : "SOS点滅")
                            .font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(torch.isSOSActive ? Color.red : Color(white: 0.16))
                    )
                    .foregroundColor(.white)
                }
                
                // ホイッスル警報音
                Button(action: {
                    audio.toggleAlert()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: audio.isPlaying ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            .font(.title2)
                        Text(audio.isPlaying ? "吹鳴中" : "ホイッスル")
                            .font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(audio.isPlaying ? Color.yellow : Color(white: 0.16))
                    )
                    .foregroundColor(audio.isPlaying ? .black : .white)
                }
            }
        }
    }
}
