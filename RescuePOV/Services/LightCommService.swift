import Foundation
import AVFoundation
import UIKit
import Combine

// MARK: - 光通信プロトコル v2
// ・定型語モード : 16bitフレーム = プリアンブル4bit + 英単語ID(ハミング12,8) 。連送を多数決。1bit=0.2秒
// ・自由文字モード: プリアンブル4bit + [長さ] + [文字×n] + [チェックサム]（各シンボルはハミング(12,8)）。1bit=0.15秒
//   文字は ASCII / ひらがな(カタカナは同音のひらがなへ) / その他はUnicode(エスケープ)で送る。
//   メッセージ全体を繰り返し送信し、受信側は周回を重ねて多数決＋訂正する。

/// 光通信で送れる定型語。内部プロトコルは英語ID(8bit)に統一し、受信側で端末の言語に翻訳して表示する。
public struct LightCommWord: Identifiable, Hashable {
    public let id: UInt8
    public let en: String
    public let ja: String
    
    /// 受信側の言語で表示（端末が日本語なら日本語、それ以外は英語）
    public var localized: String { L.pick(ja, en) }
}

public enum LightCommCodec {
    public static let preamble: [Bool] = [true, false, true, true]  // 巡回シフトでも別フレームと誤認しないことを全IDで検証済み
    public static let bitDuration: Double = 0.2
    public static let textBitDuration: Double = 0.15
    public static let frameBits: Int = 16
    public static let textMaxSymbols: Int = 24
    
    public static let words: [LightCommWord] = [
        LightCommWord(id: 1, en: "HELP", ja: "たすけて"),
        LightCommWord(id: 2, en: "SOS", ja: "SOS"),
        LightCommWord(id: 3, en: "OK", ja: "大丈夫"),
        LightCommWord(id: 4, en: "YES", ja: "はい"),
        LightCommWord(id: 5, en: "NO", ja: "いいえ"),
        LightCommWord(id: 6, en: "WATER", ja: "水が欲しい"),
        LightCommWord(id: 7, en: "FOOD", ja: "食べ物が欲しい"),
        LightCommWord(id: 8, en: "MEDICAL", ja: "医療が必要"),
        LightCommWord(id: 9, en: "INJURED", ja: "けが人がいる"),
        LightCommWord(id: 10, en: "TRAPPED", ja: "閉じ込められた"),
        LightCommWord(id: 11, en: "FIRE", ja: "火事"),
        LightCommWord(id: 12, en: "FLOOD", ja: "浸水・洪水"),
        LightCommWord(id: 13, en: "LOST", ja: "道に迷った"),
        LightCommWord(id: 14, en: "HERE", ja: "ここにいる"),
        LightCommWord(id: 15, en: "COMING", ja: "向かっている"),
        LightCommWord(id: 16, en: "WAIT", ja: "待って"),
        LightCommWord(id: 17, en: "SAFE", ja: "安全"),
        LightCommWord(id: 18, en: "DANGER", ja: "危険"),
        LightCommWord(id: 19, en: "COLD", ja: "寒い"),
        LightCommWord(id: 20, en: "HOT", ja: "暑い"),
        LightCommWord(id: 21, en: "BATTERY LOW", ja: "電池が少ない"),
        LightCommWord(id: 22, en: "STAY", ja: "動かないで"),
        LightCommWord(id: 23, en: "NEED HELP", ja: "助けが必要"),
        LightCommWord(id: 24, en: "I SEE YOU", ja: "見えています"),
        LightCommWord(id: 25, en: "HEARD", ja: "聞こえました"),
        LightCommWord(id: 26, en: "MANY PEOPLE", ja: "複数人いる"),
        LightCommWord(id: 27, en: "CHILD", ja: "子供がいる"),
        LightCommWord(id: 28, en: "ELDERLY", ja: "高齢者がいる"),
        LightCommWord(id: 29, en: "PREGNANT", ja: "妊婦がいる"),
        LightCommWord(id: 30, en: "CAN'T BREATHE", ja: "息ができない"),
        LightCommWord(id: 31, en: "PAIN", ja: "痛い"),
        LightCommWord(id: 32, en: "THIRSTY", ja: "喉が渇いた"),
        LightCommWord(id: 33, en: "THANK YOU", ja: "ありがとう"),
        LightCommWord(id: 34, en: "SORRY", ja: "ごめんなさい"),
        LightCommWord(id: 35, en: "REPEAT", ja: "もう一度"),
        LightCommWord(id: 36, en: "RESCUE TEAM", ja: "救助隊です"),
        LightCommWord(id: 37, en: "EXIT", ja: "出口")
    ]
    
    public static func word(for id: UInt8) -> LightCommWord? {
        words.first { $0.id == id }
    }
    
    // MARK: ハミング(12,8)  パリティ位置 1,2,4,8 / データ位置 3,5,6,7,9,10,11,12
    private static let dataPositions: [Int] = [3, 5, 6, 7, 9, 10, 11, 12]
    
    public static func hammingEncode(_ byte: UInt8) -> [Bool] {
        var code = [Bool](repeating: false, count: 13)
        for (i, pos) in dataPositions.enumerated() {
            code[pos] = ((byte >> UInt8(7 - i)) & 1) == 1
        }
        for p in [1, 2, 4, 8] {
            var parity = false
            for pos in 1...12 where (pos & p) != 0 && pos != p {
                if code[pos] { parity.toggle() }
            }
            code[p] = parity
        }
        return Array(code[1...12])
    }
    
    /// 1bitまでの誤りを訂正してデコード
    public static func hammingDecode(_ bits: [Bool]) -> (value: UInt8, corrected: Bool)? {
        guard bits.count == 12 else { return nil }
        var code = [false] + bits
        var syndrome = 0
        for pos in 1...12 where code[pos] { syndrome ^= pos }
        var corrected = false
        if syndrome != 0 {
            guard syndrome <= 12 else { return nil }
            code[syndrome].toggle()
            corrected = true
        }
        var value: UInt8 = 0
        for pos in dataPositions {
            value = (value << 1) | (code[pos] ? 1 : 0)
        }
        return (value, corrected)
    }
    
    /// 定型語フレーム(16bit)
    public static func frame(for id: UInt8) -> [Bool] {
        preamble + hammingEncode(id)
    }
    
    // MARK: 自由文字 <-> シンボル
    public static func textToSymbols(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        for scalar in text.unicodeScalars {
            var c = Int(scalar.value)
            if c >= 0x30A1 && c <= 0x30F3 { c -= 0x60 }   // カタカナ→ひらがな
            var syms: [UInt8]
            if c >= 0x20 && c <= 0x7E { syms = [UInt8(c)] }
            else if c >= 0x3041 && c <= 0x3093 { syms = [UInt8(0x80 + (c - 0x3041))] }
            else if c == 0x30FC { syms = [0xD3] }
            else if c == 0x3001 { syms = [0xD4] }
            else if c == 0x3002 { syms = [0xD5] }
            else if c == 0xFF01 { syms = [0xD6] }
            else if c == 0xFF1F { syms = [0xD7] }
            else if c <= 0xFFFF { syms = [0xFF, UInt8(c >> 8), UInt8(c & 0xFF)] }
            else { syms = [0x3F] }
            if out.count + syms.count > textMaxSymbols { break }
            out.append(contentsOf: syms)
        }
        return out
    }
    
    public static func symbolsToText(_ syms: [UInt8]) -> String {
        var s = ""
        var i = 0
        while i < syms.count {
            let b = syms[i]
            if b >= 0x20 && b <= 0x7E {
                s.append(Character(UnicodeScalar(b)))
            } else if b >= 0x80 && b <= 0xD2 {
                if let u = UnicodeScalar(0x3041 + Int(b) - 0x80) { s.append(Character(u)) }
            } else if b == 0xD3 { s.append("ー") }
            else if b == 0xD4 { s.append("、") }
            else if b == 0xD5 { s.append("。") }
            else if b == 0xD6 { s.append("！") }
            else if b == 0xD7 { s.append("？") }
            else if b == 0xFF && i + 2 < syms.count {
                let code = (Int(syms[i + 1]) << 8) | Int(syms[i + 2])
                if let u = UnicodeScalar(code) { s.append(Character(u)) } else { s.append("?") }
                i += 2
            } else { s.append("?") }
            i += 1
        }
        return s
    }
    
    /// 実際に送られる（符号化後の）文字列。カタカナはひらがなに変わる等を送信前に見せるため。
    public static func transmittedText(_ text: String) -> String {
        symbolsToText(textToSymbols(text))
    }
    
    private static func textChecksum(_ n: Int, _ syms: [UInt8]) -> UInt8 {
        var c = UInt8(n & 0xFF) ^ 0x5A
        for b in syms { c ^= b }
        return c
    }
    
    /// 自由文字メッセージの送信ビット列（1周分）
    public static func textFrame(_ text: String) -> [Bool] {
        let syms = textToSymbols(text)
        let n = syms.count
        var bits = preamble
        bits.append(contentsOf: hammingEncode(0x80 | UInt8(n)))
        for b in syms { bits.append(contentsOf: hammingEncode(b)) }
        bits.append(contentsOf: hammingEncode(textChecksum(n, syms)))
        return bits
    }
    
    // MARK: 復調
    public struct Sample {
        public let t: Double   // 秒
        public let v: Double   // 0...1 の明るさ
        public init(t: Double, v: Double) { self.t = t; self.v = v }
    }
    
    public struct DecodeResult {
        public let word: LightCommWord
        public let repeats: Int
        public let corrected: Bool
        public let quality: Double
    }
    
    public struct TextResult {
        public let text: String
        public let repeats: Int
        public let corrected: Int
        public let quality: Double
    }
    
    /// 全体の明るさ統計（コントラストと中間しきい値）
    public static func stats(_ samples: [Sample]) -> (contrast: Double, threshold: Double)? {
        guard samples.count > 10 else { return nil }
        let sv = samples.map { $0.v }.sorted()
        let p10 = sv[Int(Double(sv.count - 1) * 0.10)]
        let p90 = sv[Int(Double(sv.count - 1) * 0.90)]
        return (p90 - p10, (p10 + p90) / 2.0)
    }
    
    /// 時間基準でビット列を取り出す。しきい値は前後±1秒の局所min/maxの中点（カメラの自動露出ドリフト対策）。
    private static func sampleBits(_ samples: [Sample], T: Double, phase: Int, threshold: Double, contrast: Double) -> [Bool] {
        guard let first = samples.first, let last = samples.last else { return [] }
        let start = first.t + T * Double(phase) / 8.0
        var bits: [Bool] = []
        var idx = 0, k = 0, wlo = 0, whi = 0
        var prev = false
        while true {
            let center = start + (Double(k) + 0.5) * T
            let lo = center - T * 0.25
            let hi = center + T * 0.25
            if hi > last.t { break }
            while idx < samples.count && samples[idx].t < lo { idx += 1 }
            var j = idx
            var sum = 0.0
            var n = 0
            while j < samples.count && samples[j].t <= hi {
                sum += samples[j].v
                n += 1
                j += 1
            }
            if n > 0 {
                while wlo < samples.count && samples[wlo].t < center - 1.0 { wlo += 1 }
                if whi < wlo { whi = wlo }
                while whi < samples.count && samples[whi].t <= center + 1.0 { whi += 1 }
                var mn = Double.greatestFiniteMagnitude
                var mx = -Double.greatestFiniteMagnitude
                if wlo < whi {
                    for q in wlo..<whi {
                        let v = samples[q].v
                        if v < mn { mn = v }
                        if v > mx { mx = v }
                    }
                }
                let localOK = (mx - mn) >= max(0.08, 0.4 * contrast)
                let th = localOK ? (mn + mx) / 2.0 : threshold
                prev = (sum / Double(n)) > th
            }
            bits.append(prev)
            k += 1
        }
        return bits
    }
    
    private static func preDist(_ bits: [Bool], _ i: Int) -> Int {
        var d = 0
        for b in 0..<4 where bits[i + b] != preamble[b] { d += 1 }
        return d
    }
    
    /// 定型語の復調（連送フレームを多数決＋ハミング訂正）
    public static func decode(samples: [Sample]) -> DecodeResult? {
        guard samples.count > 40, let first = samples.first, let last = samples.last else { return nil }
        let T = bitDuration
        guard last.t - first.t >= T * Double(frameBits) * 2.0 else { return nil }
        guard let st = stats(samples), st.contrast >= 0.10 else { return nil }
        
        var best: DecodeResult? = nil
        var bestScore: Double = 0
        
        for phase in 0..<8 {
            let bits = sampleBits(samples, T: T, phase: phase, threshold: st.threshold, contrast: st.contrast)
            let count = bits.count
            guard count >= frameBits * 2 else { continue }
            
            var starts = Set<Int>()
            for i in 0...(count - frameBits) where preDist(bits, i) <= 1 { starts.insert(i) }
            
            for s in starts.sorted() where !starts.contains(s - frameBits) {
                var chain = [s]
                var next = s + frameBits
                while starts.contains(next) {
                    chain.append(next)
                    next += frameBits
                }
                guard chain.count >= 2 else { continue }
                
                var votes = [Int](repeating: 0, count: 12)
                for c in chain {
                    for b in 0..<12 { votes[b] += bits[c + 4 + b] ? 1 : -1 }
                }
                guard let dec = hammingDecode(votes.map { $0 > 0 }), let w = word(for: dec.value) else { continue }
                
                let agreement = Double(votes.map { abs($0) }.reduce(0, +)) / Double(12 * chain.count)
                let exactPre = chain.allSatisfy { preDist(bits, $0) == 0 }
                if chain.count == 2 {
                    if agreement < 1.0 || dec.corrected || !exactPre { continue }
                } else if agreement < 0.8 {
                    continue
                }
                let score = Double(chain.count) - (dec.corrected ? 0.5 : 0.0) + agreement + (exactPre ? 0.75 : 0.0)
                if score > bestScore {
                    bestScore = score
                    best = DecodeResult(word: w, repeats: chain.count, corrected: dec.corrected, quality: min(1.0, agreement))
                }
            }
        }
        return best
    }
    
    /// 自由文字の復調。1周でも「完全一致＋チェックサム一致」なら採用、複数周回なら多数決で訂正して採用。
    public static func decodeText(samples: [Sample]) -> TextResult? {
        guard samples.count > 60 else { return nil }
        guard let st = stats(samples), st.contrast >= 0.10 else { return nil }
        let T = textBitDuration
        
        var best: TextResult? = nil
        var bestScore: Double = 0
        
        for phase in 0..<8 {
            let bits = sampleBits(samples, T: T, phase: phase, threshold: st.threshold, contrast: st.contrast)
            let count = bits.count
            guard count >= 4 + 12 * 3 else { continue }
            
            var i = 0
            while i + 16 <= count {
                defer { i += 1 }
                if preDist(bits, i) > 1 { continue }
                guard let h = hammingDecode(Array(bits[(i + 4)..<(i + 16)])), h.value >= 0x80 else { continue }
                let n = Int(h.value & 0x7F)
                if n < 1 || n > textMaxSymbols { continue }
                let P = 4 + 12 * (n + 2)
                if i + P > count { continue }
                
                var chain = [i]
                var j = i + P
                while j + P <= count && preDist(bits, j) <= 1 {
                    chain.append(j)
                    j += P
                }
                
                let body = P - 4
                var votes = [Int](repeating: 0, count: body)
                for c in chain {
                    for b in 0..<body { votes[b] += bits[c + 4 + b] ? 1 : -1 }
                }
                let voted = votes.map { $0 > 0 }
                let agreement = Double(votes.map { abs($0) }.reduce(0, +)) / Double(body * chain.count)
                let exactPre = chain.allSatisfy { preDist(bits, $0) == 0 }
                
                var corrected = 0
                var syms: [UInt8] = []
                var ok = true
                for s in 0..<(n + 2) {
                    guard let d = hammingDecode(Array(voted[(s * 12)..<(s * 12 + 12)])) else { ok = false; break }
                    if d.corrected { corrected += 1 }
                    syms.append(d.value)
                }
                if !ok { continue }
                let payload = Array(syms[1...n])
                let chk = syms[n + 1]
                if syms[0] != (0x80 | UInt8(n)) { continue }
                if chk != textChecksum(n, payload) { continue }
                if chain.count == 1 {
                    if corrected > 0 || !exactPre { continue }
                } else if agreement < 0.85 {
                    continue
                }
                
                let score = Double(chain.count) * 2.0 + Double(n) * 0.1 - Double(corrected) * 0.3 + (exactPre ? 0.5 : 0.0)
                if score > bestScore {
                    bestScore = score
                    best = TextResult(text: symbolsToText(payload), repeats: chain.count, corrected: corrected, quality: min(1.0, agreement))
                }
            }
        }
        return best
    }
}

// MARK: - 送信機（背面LEDフラッシュのみで送信）

public final class LightCommTransmitter: ObservableObject {
    public static let shared = LightCommTransmitter()
    
    @Published public private(set) var isSending: Bool = false
    @Published public private(set) var currentBitIndex: Int = 0
    @Published public private(set) var totalBits: Int = 0
    @Published public private(set) var currentBitOn: Bool = false
    @Published public private(set) var sentFrames: Int = 0
    @Published public private(set) var sendingLabel: String = ""
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.rescuepov.lightcomm.tx", qos: .userInteractive)
    private var frame: [Bool] = []
    private var bitCursor: Int = 0
    
    private init() {}
    
    /// 定型語を送信
    public func start(word: LightCommWord) {
        begin(bits: LightCommCodec.frame(for: word.id), bitDuration: LightCommCodec.bitDuration, label: word.en)
    }
    
    /// 自由文字を送信（空文字の場合は何もしない）
    public func start(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !LightCommCodec.textToSymbols(trimmed).isEmpty else { return }
        begin(bits: LightCommCodec.textFrame(trimmed), bitDuration: LightCommCodec.textBitDuration, label: LightCommCodec.transmittedText(trimmed))
    }
    
    private func begin(bits: [Bool], bitDuration: Double, label: String) {
        stopTimerOnly()
        TorchService.shared.stopSOS()
        frame = bits
        bitCursor = 0
        sentFrames = 0
        totalBits = bits.count
        sendingLabel = label
        isSending = true
        UIApplicationIdleKeeper.keepAwake(true)
        
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.3, repeating: bitDuration, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self = self, !self.frame.isEmpty else { return }
            let bit = self.frame[self.bitCursor]
            TorchService.shared.setTorchDirect(on: bit)
            let index = self.bitCursor
            self.bitCursor += 1
            var frameDone = false
            if self.bitCursor >= self.frame.count {
                self.bitCursor = 0
                frameDone = true
            }
            DispatchQueue.main.async {
                self.currentBitIndex = index
                self.currentBitOn = bit
                if frameDone { self.sentFrames += 1 }
            }
        }
        timer = t
        t.resume()
    }
    
    private func stopTimerOnly() {
        timer?.cancel()
        timer = nil
    }
    
    public func stop() {
        stopTimerOnly()
        if isSending {
            TorchService.shared.setTorchDirect(on: false)
        }
        isSending = false
        currentBitOn = false
        currentBitIndex = 0
        UIApplicationIdleKeeper.keepAwake(false)
    }
}

// MARK: - 受信機（背面カメラで相手のライト/Mac画面の点滅を復調）

public final class LightCommReceiver: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public static let shared = LightCommReceiver()
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var recentLevels: [Double] = []
    @Published public private(set) var threshold: Double = 0.5
    @Published public private(set) var contrast: Double = 0
    @Published public private(set) var currentLevel: Double = 0
    @Published public private(set) var decoded: LightCommCodec.DecodeResult? = nil
    @Published public private(set) var decodedText: LightCommCodec.TextResult? = nil
    @Published public private(set) var statusMessage: String = "待機中"
    @Published public private(set) var permissionDenied: Bool = false
    
    /// 受光感度 0(暗い)〜1(明るい)。固定露出のISOに対応。点滅が弱い/飽和する時に調整する。
    @Published public var sensitivity: Double = 0.3 {
        didSet { queue.async { [weak self] in self?.applyExposure() } }
    }
    
    public let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.rescuepov.lightcomm.rx", qos: .userInitiated)
    private var configured = false
    private var device: AVCaptureDevice?
    
    // queue上でのみアクセス
    private var samples: [LightCommCodec.Sample] = []
    private var frameCounter: Int = 0
    private var lastDecodeTime: Double = 0
    private let windowSeconds: Double = 60.0
    
    public override init() { super.init() }
    
    public func start() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.begin() } else { self?.permissionDenied = true; self?.statusMessage = "カメラ権限が必要です" }
                }
            }
        default:
            permissionDenied = true
            statusMessage = "カメラ権限が必要です（設定アプリで許可）"
        }
    }
    
    public func clearResults() {
        decoded = nil
        decodedText = nil
    }
    
    private func begin() {
        clearResults()
        recentLevels = []
        statusMessage = "受信待機中… 相手の光を枠の中に入れてください"
        queue.async { [weak self] in
            guard let self = self else { return }
            self.samples.removeAll()
            self.frameCounter = 0
            self.lastDecodeTime = 0
            if !self.configured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
            self.applyExposure()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
                if !self.isRunning { self.statusMessage = "カメラを開始できませんでした" }
            }
        }
        UIApplicationIdleKeeper.keepAwake(true)
    }
    
    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
        UIApplicationIdleKeeper.keepAwake(false)
    }
    
    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }
        device = camera
        if session.canAddInput(input) { session.addInput(input) }
        
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        
        if (try? camera.lockForConfiguration()) != nil {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        }
        configured = true
    }
    
    /// 自動露出は点滅光に追従して明るさの基準がずれるため、固定露出にして
    /// 「画面や懐中電灯のような強い光だけが白く、周囲は暗く」写るようにする。
    private func applyExposure() {
        guard let camera = device else { return }
        let format = camera.activeFormat
        let minD = format.minExposureDuration
        let maxD = format.maxExposureDuration
        var duration = CMTime(value: 1, timescale: 60) // 60Hz画面の1周期ぶんを積分してバンディングを避ける
        if CMTimeCompare(duration, minD) < 0 { duration = minD }
        if CMTimeCompare(duration, maxD) > 0 { duration = maxD }
        
        let minISO = format.minISO
        let maxISO = min(format.maxISO, 1600)
        let ratio = Float(max(0.0, min(1.0, sensitivity)))
        let iso = minISO * powf(max(maxISO / max(minISO, 1), 1.0), ratio)
        
        if (try? camera.lockForConfiguration()) != nil {
            camera.setExposureModeCustom(duration: duration, iso: min(max(iso, minISO), maxISO), completionHandler: nil)
            camera.unlockForConfiguration()
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        
        // 画面中央50%のうち、最も明るい上位2%の平均を「光源の明るさ」とする
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        let x0 = width / 4, x1 = width * 3 / 4
        let y0 = height / 4, y1 = height * 3 / 4
        for y in Swift.stride(from: y0, to: y1, by: 3) {
            let row = y * stride
            for x in Swift.stride(from: x0, to: x1, by: 3) {
                histogram[Int(ptr[row + x])] += 1
                total += 1
            }
        }
        guard total > 0 else { return }
        let topCount = max(1, total * 2 / 100)
        var remaining = topCount
        var sum = 0
        var level = 255
        while level >= 0 && remaining > 0 {
            let take = min(histogram[level], remaining)
            sum += take * level
            remaining -= take
            level -= 1
        }
        let value = Double(sum) / Double(topCount) / 255.0
        
        samples.append(LightCommCodec.Sample(t: time, v: value))
        while let f = samples.first, time - f.t > windowSeconds { samples.removeFirst() }
        frameCounter += 1
        
        if frameCounter % 3 == 0 {
            let levels = samples.suffix(150).map { $0.v }
            DispatchQueue.main.async {
                self.recentLevels = levels
                self.currentLevel = value
            }
        }
        
        if time - lastDecodeTime >= 1.0 {
            lastDecodeTime = time
            let snapshot = samples
            let stat = LightCommCodec.stats(snapshot)
            let textResult = LightCommCodec.decodeText(samples: snapshot)
            let wordResult = LightCommCodec.decode(samples: snapshot)
            let span = (snapshot.last?.t ?? 0) - (snapshot.first?.t ?? 0)
            DispatchQueue.main.async {
                self.threshold = stat?.threshold ?? 0.5
                self.contrast = stat?.contrast ?? 0
                if let r = textResult {
                    self.decodedText = r
                    self.decoded = nil
                    self.statusMessage = "文字を受信（\(r.repeats)周の多数決\(r.corrected > 0 ? "・誤り訂正あり" : "")）"
                } else if let r = wordResult {
                    self.decoded = r
                    self.decodedText = nil
                    self.statusMessage = "受信成功（連送\(r.repeats)回の多数決\(r.corrected ? "・誤り訂正あり" : "")）"
                } else if self.contrast < 0.10 {
                    self.statusMessage = "点滅を検出できません。光を枠の中に入れ、感度を調整してください"
                } else if span < 12.5 {
                    self.statusMessage = "受信中… データを集めています（文字は約12秒〜、長い文ほど時間がかかります）"
                } else {
                    self.statusMessage = "同期中… 光の点滅を解析しています"
                }
            }
        }
    }
}

/// 送受信中に画面スリープさせないための小さなヘルパー
enum UIApplicationIdleKeeper {
    static func keepAwake(_ on: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = on
        }
    }
}
