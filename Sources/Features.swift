import SwiftUI
import UIKit
import AVFoundation
import os

// MARK: - 1) Tình trạng máy (đo thật từ hệ thống)

struct HealthSnapshot {
    var thermalText = "—"
    var thermalLevel = 0            // 0 mát, 1 hơi ấm, 2 nóng, 3 rất nóng
    var lowPower = false
    var battery: Float = -1
    var charging = false
    var freeGB = 0.0
    var ramGB = 0.0
    var appFreeMB = 0.0
    var maxFPS = 60
    var score = 100
    var warnings: [String] = []

    static func current() -> HealthSnapshot {
        var s = HealthSnapshot()
        let pi = ProcessInfo.processInfo

        switch pi.thermalState {
        case .nominal: s.thermalText = "Mát"; s.thermalLevel = 0
        case .fair: s.thermalText = "Hơi ấm"; s.thermalLevel = 1
        case .serious: s.thermalText = "Nóng"; s.thermalLevel = 2
        case .critical: s.thermalText = "Rất nóng"; s.thermalLevel = 3
        @unknown default: s.thermalText = "—"
        }

        s.lowPower = pi.isLowPowerModeEnabled

        UIDevice.current.isBatteryMonitoringEnabled = true
        s.battery = UIDevice.current.batteryLevel
        let st = UIDevice.current.batteryState
        s.charging = (st == .charging || st == .full)

        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage {
            s.freeGB = Double(free) / 1_000_000_000
        }

        s.ramGB = Double(pi.physicalMemory) / 1_073_741_824
        s.appFreeMB = Double(os_proc_available_memory()) / 1_048_576
        s.maxFPS = UIScreen.main.maximumFramesPerSecond

        var score = 100
        if s.thermalLevel == 1 { score -= 10; s.warnings.append("Máy hơi ấm, nên nghỉ chơi 1–2 phút nếu thấy tụt FPS.") }
        if s.thermalLevel == 2 { score -= 30; s.warnings.append("Máy đang NÓNG: iOS sẽ giảm hiệu năng, game dễ giật. Tháo ốp, nghỉ cho máy mát.") }
        if s.thermalLevel >= 3 { score -= 50; s.warnings.append("Máy RẤT NÓNG: hãy dừng chơi để máy nguội.") }
        if s.lowPower { score -= 25; s.warnings.append("Chế độ nguồn điện thấp đang BẬT: giới hạn CPU và tần số quét. Tắt trong Cài đặt → Pin.") }
        if s.battery >= 0 && s.battery < 0.2 && !s.charging {
            score -= 10
            s.warnings.append("Pin dưới 20%, máy dễ bị hạn chế hiệu năng.")
        }
        if s.freeGB > 0 && s.freeGB < 3 {
            score -= 10
            s.warnings.append("Bộ nhớ trống dưới 3 GB, game có thể tải/lưu chậm.")
        }
        s.score = max(0, score)
        return s
    }
}

struct ReadinessCard: View {
    @State private var snap = HealthSnapshot.current()
    @State private var keepAwake = UIApplication.shared.isIdleTimerDisabled
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var scoreColor: Color {
        snap.score >= 80 ? Theme.good : (snap.score >= 50 ? Theme.warn : Theme.bad)
    }

    var body: some View {
        Card("Sẵn sàng chơi game", icon: "speedometer") {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(snap.score) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: snap.score)
                    VStack(spacing: 0) {
                        Text("\(snap.score)").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("điểm").font(.caption2).foregroundColor(Color.white.opacity(0.6))
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    row("Nhiệt độ", snap.thermalText, snap.thermalLevel == 0 ? Theme.good : (snap.thermalLevel == 1 ? Theme.warn : Theme.bad))
                    row("Nguồn điện thấp", snap.lowPower ? "BẬT" : "Tắt", snap.lowPower ? Theme.bad : Theme.good)
                    row("Pin", snap.battery < 0 ? "—" : "\(Int(snap.battery * 100))%\(snap.charging ? " ⚡︎" : "")", .white)
                }
            }

            HStack {
                mini("Tần số quét", "\(snap.maxFPS) Hz")
                mini("RAM máy", String(format: "%.0f GB", snap.ramGB))
                mini("Trống", String(format: "%.0f GB", snap.freeGB))
            }

            ForEach(snap.warnings, id: \.self) { w in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warn)
                    Text(w).font(.footnote).foregroundColor(Color.white.opacity(0.85))
                }
            }

            Toggle(isOn: Binding(get: { keepAwake }, set: { v in
                keepAwake = v
                UIApplication.shared.isIdleTimerDisabled = v
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Giữ màn hình luôn sáng").font(.subheadline.weight(.semibold))
                    Text("Chỉ có tác dụng khi đang mở app này").font(.caption).foregroundColor(Color.white.opacity(0.55))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
        }
        .onReceive(timer) { _ in snap = HealthSnapshot.current() }
    }

    private func row(_ a: String, _ b: String, _ c: Color) -> some View {
        HStack {
            Text(a).font(.subheadline).foregroundColor(Color.white.opacity(0.65))
            Spacer()
            Text(b).font(.subheadline.weight(.semibold)).foregroundColor(c)
        }
    }

    private func mini(_ a: String, _ b: String) -> some View {
        VStack(spacing: 2) {
            Text(b).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(a).font(.caption2).foregroundColor(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
}

// MARK: - 2) Đo tốc độ lấy mẫu cảm ứng (đo thật bằng UITouch)

struct TouchStats: Equatable {
    var hz: Double = 0
    var avgMs: Double = 0
    var jitterMs: Double = 0
    var samples: Int = 0
}

final class TouchPadView: UIView {
    var onStats: ((TouchStats) -> Void)?

    private var stamps: [TimeInterval] = []
    private let trail = CAShapeLayer()
    private var path = UIBezierPath()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(white: 0, alpha: 0.28)
        layer.cornerRadius = 16
        clipsToBounds = true
        trail.strokeColor = UIColor(red: 0.16, green: 0.78, blue: 1.0, alpha: 1).cgColor
        trail.fillColor = nil
        trail.lineWidth = 3
        trail.lineCap = .round
        trail.lineJoin = .round
        layer.addSublayer(trail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        trail.frame = bounds
    }

    private func record(_ touch: UITouch, _ event: UIEvent?) {
        let list = event?.coalescedTouches(for: touch) ?? [touch]
        for t in list {
            stamps.append(t.timestamp)
            let p = t.location(in: self)
            if path.isEmpty { path.move(to: p) } else { path.addLine(to: p) }
        }
        trail.path = path.cgPath
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stamps = []
        path = UIBezierPath()
        for t in touches { record(t, event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { record(t, event) }
        if stamps.count % 10 == 0 { publish() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { record(t, event) }
        publish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        publish()
    }

    private func publish() {
        guard stamps.count >= 4 else { return }
        var gaps: [Double] = []
        for i in 1..<stamps.count {
            let d = stamps[i] - stamps[i - 1]
            if d > 0 && d < 0.1 { gaps.append(d) }     // bỏ các lúc ngón tay đứng yên
        }
        guard gaps.count >= 3 else { return }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let variance = gaps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(gaps.count)
        var s = TouchStats()
        s.avgMs = mean * 1000
        s.hz = 1 / mean
        s.jitterMs = variance.squareRoot() * 1000
        s.samples = stamps.count
        onStats?(s)
    }
}

struct TouchPadRepresentable: UIViewRepresentable {
    let onStats: (TouchStats) -> Void

    func makeUIView(context: Context) -> TouchPadView {
        let v = TouchPadView()
        v.onStats = onStats
        return v
    }

    func updateUIView(_ v: TouchPadView, context: Context) {
        v.onStats = onStats
    }
}

struct TouchTestCard: View {
    @State private var stats = TouchStats()

    private var verdict: (String, Color) {
        if stats.samples == 0 { return ("Chạm và kéo 1 ngón trong khung", Color.white.opacity(0.6)) }
        if stats.hz >= 200 { return ("Cảm ứng rất nhanh", Theme.good) }
        if stats.hz >= 100 { return ("Cảm ứng nhanh", Theme.good) }
        if stats.hz >= 55 { return ("Cảm ứng tiêu chuẩn", Theme.warn) }
        return ("Cảm ứng đang bị chậm — kiểm tra nhiệt độ / nguồn điện thấp", Theme.bad)
    }

    var body: some View {
        Card("Đo tốc độ cảm ứng", icon: "hand.tap.fill") {
            TouchPadRepresentable { stats = $0 }
                .frame(height: 170)
                .overlay(
                    Text(stats.samples == 0 ? "Kéo ngón tay ở đây" : "")
                        .foregroundColor(Color.white.opacity(0.4))
                        .allowsHitTesting(false)
                )

            HStack {
                big(stats.samples == 0 ? "—" : String(format: "%.0f", stats.hz), "Hz lấy mẫu")
                big(stats.samples == 0 ? "—" : String(format: "%.1f", stats.avgMs), "ms / lần")
                big(stats.samples == 0 ? "—" : String(format: "%.1f", stats.jitterMs), "ms dao động")
            }

            Text(verdict.0).font(.subheadline.weight(.semibold)).foregroundColor(verdict.1)
            Text("Số càng cao, ms và dao động càng thấp thì cảm ứng càng mượt. Đo ngay khi máy đang nóng / đang bật tiết kiệm pin để thấy khác biệt.")
                .font(.caption).foregroundColor(Color.white.opacity(0.5))
        }
    }

    private func big(_ a: String, _ b: String) -> some View {
        VStack(spacing: 2) {
            Text(a).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Theme.cyan)
            Text(b).font(.caption2).foregroundColor(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3) Đo ping mạng (đo thật)

struct PingResult: Identifiable {
    let id = UUID()
    var name: String
    var avg: Double?
    var best: Double?
    var worst: Double?
    var jitter: Double?
    var lost = 0
    var samples = 0
}

enum PingTester {
    static func run(name: String, url: URL, samples: Int = 6) async -> PingResult {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 4
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        var times: [Double] = []
        var lost = 0

        for i in 0...samples {                       // lần 0 = khởi động kết nối, bỏ qua
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await session.data(for: req)
                if i > 0 { times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000) }
            } catch {
                if i > 0 { lost += 1 }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        var r = PingResult(name: name)
        r.samples = samples
        r.lost = lost
        if !times.isEmpty {
            r.avg = times.reduce(0, +) / Double(times.count)
            r.best = times.min()
            r.worst = times.max()
            if times.count > 1 {
                var sum = 0.0
                for i in 1..<times.count { sum += abs(times[i] - times[i - 1]) }
                r.jitter = sum / Double(times.count - 1)
            } else {
                r.jitter = 0
            }
        }
        return r
    }
}

struct PingCard: View {
    @State private var results: [PingResult] = []
    @State private var running = false

    private let targets: [(String, String)] = [
        ("Google", "https://www.gstatic.com/generate_204"),
        ("Cloudflare", "https://www.cloudflare.com/cdn-cgi/trace"),
        ("Garena", "https://www.garena.com"),
        ("Server của bạn", Config.apiBase + "/api/verify")
    ]

    private func color(_ ms: Double?) -> Color {
        guard let ms = ms else { return Theme.bad }
        return ms < 60 ? Theme.good : (ms < 130 ? Theme.warn : Theme.bad)
    }

    var body: some View {
        Card("Đo ping mạng", icon: "wifi") {
            if results.isEmpty && !running {
                Text("Đo độ trễ từ máy bạn tới vài máy chủ. Ping cao hoặc dao động lớn thì game online sẽ giật/trễ.")
                    .font(.footnote).foregroundColor(Color.white.opacity(0.6))
            }

            ForEach(results) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.subheadline.weight(.semibold))
                        if let j = r.jitter, let b = r.best, let w = r.worst {
                            Text(String(format: "min %.0f · max %.0f · dao động %.0f ms · mất %d/%d", b, w, j, r.lost, r.samples))
                                .font(.caption2).foregroundColor(Color.white.opacity(0.5))
                        } else {
                            Text("Không kết nối được").font(.caption2).foregroundColor(Theme.bad)
                        }
                    }
                    Spacer()
                    Text(r.avg.map { String(format: "%.0f ms", $0) } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(color(r.avg))
                }
                .padding(.vertical, 2)
            }

            Button(action: start) {
                HStack(spacing: 8) {
                    if running { ProgressView() }
                    Text(running ? "Đang đo…" : (results.isEmpty ? "Đo ngay" : "Đo lại")).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
            }
            .background(Theme.cyan.opacity(running ? 0.4 : 0.9))
            .foregroundColor(.black)
            .cornerRadius(12)
            .disabled(running)
        }
    }

    private func start() {
        running = true
        results = []
        let list = targets
        Task { @MainActor in
            for (name, s) in list {
                guard let u = URL(string: s) else { continue }
                let r = await PingTester.run(name: name, url: u)
                results.append(r)
            }
            running = false
        }
    }
}

// MARK: - 4) Danh sách tối ưu iOS (làm theo là có tác dụng thật)

struct Tip: Identifiable {
    let id: Int
    let title: String
    let detail: String
}

struct TipRow: View {
    let tip: Tip
    @AppStorage private var done: Bool

    init(tip: Tip) {
        self.tip = tip
        _done = AppStorage(wrappedValue: false, "tip_\(tip.id)")
    }

    var body: some View {
        Button { done.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(done ? Theme.good : Color.white.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    Text(tip.detail).font(.caption).foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TipsCard: View {
    static let tips: [Tip] = [
        Tip(id: 1, title: "Tắt Chế độ nguồn điện thấp",
            detail: "Cài đặt → Pin. Chế độ này giảm CPU và có thể hạ tần số quét, làm game giật."),
        Tip(id: 2, title: "Tắt Điều chỉnh cảm ứng (Touch Accommodations)",
            detail: "Cài đặt → Trợ năng → Cảm ứng → Điều chỉnh cảm ứng → Tắt. Tuỳ chọn 'Thời gian giữ' làm cảm ứng bị trễ."),
        Tip(id: 3, title: "Bật Không làm phiền / Tập trung",
            detail: "Chặn thông báo bật lên giữa trận gây giật hình."),
        Tip(id: 4, title: "Đóng ứng dụng chạy nền",
            detail: "Vuốt đóng các app nặng (video, mạng xã hội) để giải phóng RAM trước khi vào game."),
        Tip(id: 5, title: "Tắt Làm mới ứng dụng trong nền",
            detail: "Cài đặt → Cài đặt chung → Làm mới ứng dụng trong nền → Tắt (hoặc chỉ Wi-Fi)."),
        Tip(id: 6, title: "Dùng Wi-Fi 5 GHz, ngồi gần router, tắt VPN",
            detail: "Giảm ping và dao động ping. Dùng mục 'Đo ping mạng' ở trên để so sánh trước/sau."),
        Tip(id: 7, title: "Lau sạch màn hình, bỏ miếng dán dày/ốp che cạnh",
            detail: "Màn hình bẩn hoặc miếng dán dày làm cảm ứng kém nhạy. Kiểm tra bằng mục 'Đo tốc độ cảm ứng'."),
        Tip(id: 8, title: "Giữ máy mát: không vừa sạc vừa chơi",
            detail: "Máy nóng sẽ bị iOS hạ hiệu năng. Theo dõi mục Nhiệt độ ở thẻ 'Sẵn sàng chơi game'.")
    ]

    var body: some View {
        Card("Danh sách tối ưu cho iPhone", icon: "list.bullet.rectangle") {
            ForEach(TipsCard.tips) { t in
                TipRow(tip: t)
            }
            Text("Chạm để đánh dấu những bước bạn đã làm. Đây là các cài đặt thật của iOS mà ứng dụng không được phép tự đổi thay bạn.")
                .font(.caption).foregroundColor(Color.white.opacity(0.5))
        }
    }
}

// MARK: - 5) Nhạc (phát cả khi thoát ra chơi game)

final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    struct Track: Identifiable, Equatable {
        let id: String
        let title: String
        let url: URL
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var loopOne = false
    @Published var shuffle = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        var urls: [URL] = []
        for ext in ["mp3", "m4a", "wav"] {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        tracks = urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { Track(id: $0.lastPathComponent, title: MusicPlayer.title(from: $0), url: $0) }

        // mixWithOthers: nhạc chạy cùng âm thanh game, không bị game ngắt
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        if !tracks.isEmpty { prepare(0, autoplay: false) }
    }

    /// Lấy tên bài từ tên file: bỏ phần sau " | " hoặc " _ " (tên tải từ YouTube hay có đuôi dài).
    private static func title(from url: URL) -> String {
        var s = url.deletingPathExtension().lastPathComponent
        for sep in [" | ", " _ ", "｜"] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        let t = s.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? url.deletingPathExtension().lastPathComponent : t
    }

    private func prepare(_ i: Int, autoplay: Bool) {
        guard tracks.indices.contains(i) else { return }
        index = i
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: tracks[i].url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            progress = 0
            if autoplay { p.play() }
            isPlaying = autoplay
            startTimer()
        } catch {
            player = nil
            isPlaying = false
            duration = 0
            progress = 0
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player else { return }
            self.progress = p.currentTime
            self.isPlaying = p.isPlaying
        }
    }

    func toggle() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            p.play()
            isPlaying = true
        }
    }

    func play(at i: Int) { prepare(i, autoplay: true) }

    func next() {
        guard !tracks.isEmpty else { return }
        var n = (index + 1) % tracks.count
        if shuffle && tracks.count > 1 {
            repeat { n = Int.random(in: 0..<tracks.count) } while n == index
        }
        prepare(n, autoplay: true)
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if progress > 3 { seek(0); return }
        prepare((index - 1 + tracks.count) % tracks.count, autoplay: true)
    }

    func seek(_ t: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(t, duration))
        progress = p.currentTime
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        if loopOne {
            p.currentTime = 0
            p.play()
            isPlaying = true
        } else {
            next()
        }
    }
}

struct MusicCard: View {
    @EnvironmentObject var music: MusicPlayer

    private func fmt(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var body: some View {
        Card("Nhạc", icon: "music.note") {
            if music.tracks.isEmpty {
                Text("Chưa có bài nhạc nào. Thêm file .mp3 vào repo rồi build lại.")
                    .font(.footnote).foregroundColor(Color.white.opacity(0.6))
            } else {
                Text(music.tracks[music.index].title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                Slider(
                    value: Binding(get: { music.progress }, set: { music.seek($0) }),
                    in: 0...max(music.duration, 1)
                )
                .accentColor(Theme.cyan)

                HStack {
                    Text(fmt(music.progress))
                    Spacer()
                    Text(fmt(music.duration))
                }
                .font(.caption2).foregroundColor(Color.white.opacity(0.55))

                HStack(spacing: 26) {
                    Button { music.shuffle.toggle() } label: {
                        Image(systemName: "shuffle").foregroundColor(music.shuffle ? Theme.cyan : Color.white.opacity(0.5))
                    }
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }
                    Button { music.toggle() } label: {
                        Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundColor(Theme.cyan)
                    }
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                    Button { music.loopOne.toggle() } label: {
                        Image(systemName: "repeat.1").foregroundColor(music.loopOne ? Theme.cyan : Color.white.opacity(0.5))
                    }
                }
                .font(.title3)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)

                if music.tracks.count > 1 {
                    ForEach(Array(music.tracks.enumerated()), id: \.element.id) { i, t in
                        Button { music.play(at: i) } label: {
                            HStack {
                                Image(systemName: i == music.index ? "speaker.wave.2.fill" : "music.note")
                                    .foregroundColor(i == music.index ? Theme.cyan : Color.white.opacity(0.4))
                                Text(t.title).font(.footnote).lineLimit(1).foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Text("Nhạc tiếp tục phát khi bạn thoát ra chơi game (hoà cùng âm thanh game).")
                    .font(.caption).foregroundColor(Color.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Mục 1: Chức năng

struct FeaturesView: View {
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    BrandHeader(subtitle: "Đo & tối ưu máy khi chơi game")
                    ReadinessCard()
                    TouchTestCard()
                    PingCard()
                    MusicCard()
                    TipsCard()
                    Text("Lưu ý: iOS không cho ứng dụng nào tự thay đổi cảm ứng hay hiệu năng của game khác. App này đo thật, cảnh báo và hướng dẫn bạn chỉnh đúng chỗ.")
                        .font(.caption).foregroundColor(Color.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(16)
            }
        }
    }
}
