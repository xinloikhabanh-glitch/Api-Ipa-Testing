import SwiftUI
import UIKit

// MARK: - Cơ sở dữ liệu dòng máy

struct DeviceSpec: Identifiable, Hashable {
    let name: String
    let ids: [String]      // mã máy (vd "iPhone14,5"), dùng để tự nhận diện
    let inches: Double
    let hz: Int
    var id: String { return name }
}

enum DeviceDB {
    static let all: [DeviceSpec] = [
        DeviceSpec(name: "iPhone 8", ids: ["iPhone10,1", "iPhone10,4"], inches: 4.7, hz: 60),
        DeviceSpec(name: "iPhone 8 Plus", ids: ["iPhone10,2", "iPhone10,5"], inches: 5.5, hz: 60),
        DeviceSpec(name: "iPhone X", ids: ["iPhone10,3", "iPhone10,6"], inches: 5.8, hz: 60),
        DeviceSpec(name: "iPhone XS", ids: ["iPhone11,2"], inches: 5.8, hz: 60),
        DeviceSpec(name: "iPhone XS Max", ids: ["iPhone11,4", "iPhone11,6"], inches: 6.5, hz: 60),
        DeviceSpec(name: "iPhone XR", ids: ["iPhone11,8"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 11", ids: ["iPhone12,1"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 11 Pro", ids: ["iPhone12,3"], inches: 5.8, hz: 60),
        DeviceSpec(name: "iPhone 11 Pro Max", ids: ["iPhone12,5"], inches: 6.5, hz: 60),
        DeviceSpec(name: "iPhone SE (2020)", ids: ["iPhone12,8"], inches: 4.7, hz: 60),
        DeviceSpec(name: "iPhone 12 mini", ids: ["iPhone13,1"], inches: 5.4, hz: 60),
        DeviceSpec(name: "iPhone 12", ids: ["iPhone13,2"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 12 Pro", ids: ["iPhone13,3"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 12 Pro Max", ids: ["iPhone13,4"], inches: 6.7, hz: 60),
        DeviceSpec(name: "iPhone 13 mini", ids: ["iPhone14,4"], inches: 5.4, hz: 60),
        DeviceSpec(name: "iPhone 13", ids: ["iPhone14,5"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 13 Pro", ids: ["iPhone14,2"], inches: 6.1, hz: 120),
        DeviceSpec(name: "iPhone 13 Pro Max", ids: ["iPhone14,3"], inches: 6.7, hz: 120),
        DeviceSpec(name: "iPhone SE (2022)", ids: ["iPhone14,6"], inches: 4.7, hz: 60),
        DeviceSpec(name: "iPhone 14", ids: ["iPhone14,7"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 14 Plus", ids: ["iPhone14,8"], inches: 6.7, hz: 60),
        DeviceSpec(name: "iPhone 14 Pro", ids: ["iPhone15,2"], inches: 6.1, hz: 120),
        DeviceSpec(name: "iPhone 14 Pro Max", ids: ["iPhone15,3"], inches: 6.7, hz: 120),
        DeviceSpec(name: "iPhone 15", ids: ["iPhone15,4"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 15 Plus", ids: ["iPhone15,5"], inches: 6.7, hz: 60),
        DeviceSpec(name: "iPhone 15 Pro", ids: ["iPhone16,1"], inches: 6.1, hz: 120),
        DeviceSpec(name: "iPhone 15 Pro Max", ids: ["iPhone16,2"], inches: 6.7, hz: 120),
        DeviceSpec(name: "iPhone 16", ids: ["iPhone17,3"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 16 Plus", ids: ["iPhone17,4"], inches: 6.7, hz: 60),
        DeviceSpec(name: "iPhone 16e", ids: ["iPhone17,5"], inches: 6.1, hz: 60),
        DeviceSpec(name: "iPhone 16 Pro", ids: ["iPhone17,1"], inches: 6.3, hz: 120),
        DeviceSpec(name: "iPhone 16 Pro Max", ids: ["iPhone17,2"], inches: 6.9, hz: 120),
        DeviceSpec(name: "iPhone 17", ids: ["iPhone18,3"], inches: 6.3, hz: 120),
        DeviceSpec(name: "iPhone Air", ids: ["iPhone18,4"], inches: 6.5, hz: 120),
        DeviceSpec(name: "iPhone 17 Pro", ids: ["iPhone18,1"], inches: 6.3, hz: 120),
        DeviceSpec(name: "iPhone 17 Pro Max", ids: ["iPhone18,2"], inches: 6.9, hz: 120),
        DeviceSpec(name: "iPad mini", ids: [], inches: 8.3, hz: 60),
        DeviceSpec(name: "iPad / iPad Air", ids: [], inches: 10.9, hz: 60),
        DeviceSpec(name: "iPad Pro 11", ids: [], inches: 11.0, hz: 120),
        DeviceSpec(name: "iPad Pro 13", ids: [], inches: 12.9, hz: 120)
    ]

    /// Mã máy thật, ví dụ "iPhone14,5"
    static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    /// Tự nhận diện máy đang dùng; nếu là máy mới chưa có trong bảng thì ước lượng theo màn hình.
    static func detect() -> DeviceSpec {
        let m = machine()
        if let d = all.first(where: { $0.ids.contains(m) }) { return d }

        let b = UIScreen.main.bounds
        let h = max(b.width, b.height)
        let hz = UIScreen.main.maximumFramesPerSecond
        if UIDevice.current.userInterfaceIdiom == .pad {
            let inches: Double = h < 1100 ? 8.3 : (h < 1250 ? 10.9 : 12.9)
            return DeviceSpec(name: "iPad (\(m))", ids: [m], inches: inches, hz: hz)
        }
        let inches: Double = h < 700 ? 4.7 : (h < 760 ? 5.5 : (h < 830 ? 5.8 : (h < 900 ? 6.1 : (h < 940 ? 6.7 : 6.9))))
        return DeviceSpec(name: "iPhone mới (\(m))", ids: [m], inches: inches, hz: hz)
    }
}

// MARK: - Gợi ý độ nhạy

enum PlayStyle: String, CaseIterable, Identifiable {
    case balanced = "Cân bằng"
    case drag = "Kéo tâm"
    case steady = "Ổn định"
    var id: String { return rawValue }

    var detail: String {
        switch self {
        case .balanced: return "Phù hợp đa số người chơi, dễ làm quen."
        case .drag: return "Nhạy cao để kéo tâm nhanh lên đầu."
        case .steady: return "Thấp hơn để tâm chắc, hợp bắn xa / ngắm kỹ."
        }
    }
}

struct Sens {
    var general: Int
    var redDot: Int
    var scope2x: Int
    var scope4x: Int
    var awm: Int
    var freeLook: Int
}

enum SensEngine {
    private static func clamp(_ v: Double) -> Int { return Int(max(10, min(100, v.rounded()))) }

    static func suggest(_ d: DeviceSpec, _ style: PlayStyle) -> Sens {
        var g = 92.0
        if d.inches <= 5.5 { g += 3 }          // màn hình nhỏ: ít chỗ để vuốt => cần nhạy hơn
        if d.inches >= 8.0 { g -= 8 }          // máy tính bảng: quãng vuốt dài => hạ xuống
        if d.hz >= 120 { g -= 2 }              // quét 120Hz: tâm mượt hơn nên không cần quá nhạy

        switch style {
        case .balanced: break
        case .drag: g += 4
        case .steady: g -= 6
        }

        return Sens(
            general: clamp(g),
            redDot: clamp(g - 4),
            scope2x: clamp(g - 9),
            scope4x: clamp(g - 16),
            awm: clamp(g - 30),
            freeLook: clamp(g - 36)
        )
    }
}

// MARK: - Mục 2: Độ nhạy Free Fire

struct SensitivityView: View {
    @State private var selected = DeviceDB.detect()
    @State private var style = PlayStyle.balanced
    @State private var query = ""

    private let detected = DeviceDB.detect()

    private var results: [DeviceSpec] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return [] }
        return DeviceDB.all.filter { $0.name.lowercased().contains(q) }.prefix(8).map { $0 }
    }

    var body: some View {
        let s = SensEngine.suggest(selected, style)

        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    BrandHeader(subtitle: "Gợi ý độ nhạy Free Fire theo dòng máy")

                    Card("Dòng máy", icon: "iphone") {
                        Text(selected.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.cyan)
                        Text(String(format: "Màn hình %.1f\" · %d Hz", selected.inches, selected.hz))
                            .font(.subheadline).foregroundColor(Color.white.opacity(0.65))
                        if selected.name == detected.name {
                            Text("Đã tự nhận diện máy của bạn").font(.caption).foregroundColor(Theme.good)
                        } else {
                            Button("Về máy của tôi (\(detected.name))") { selected = detected }
                                .font(.caption.weight(.semibold))
                        }

                        TextField("Tìm dòng máy (vd: 15 Pro Max, XR, iPad)", text: $query)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)

                        ForEach(results) { d in
                            Button {
                                selected = d
                                query = ""
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } label: {
                                HStack {
                                    Text(d.name).foregroundColor(.white)
                                    Spacer()
                                    Text(String(format: "%.1f\" · %dHz", d.inches, d.hz))
                                        .font(.caption).foregroundColor(Color.white.opacity(0.55))
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    Card("Lối chơi", icon: "scope") {
                        Picker("Lối chơi", selection: $style) {
                            ForEach(PlayStyle.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        Text(style.detail).font(.footnote).foregroundColor(Color.white.opacity(0.6))
                    }

                    Card("Độ nhạy đề xuất", icon: "slider.horizontal.3") {
                        bar("Tổng quan", s.general)
                        bar("Red Dot", s.redDot)
                        bar("Ống ngắm 2x", s.scope2x)
                        bar("Ống ngắm 4x", s.scope4x)
                        bar("Ống ngắm AWM", s.awm)
                        bar("Nhìn xung quanh", s.freeLook)
                    }

                    Card("Cách dùng", icon: "info.circle") {
                        Text("1. Vào Free Fire → Cài đặt → Độ nhạy, nhập các số ở trên.\n2. Vào phòng tập, bắn thử vào bia ở nhiều khoảng cách.\n3. Tâm văng quá đà thì giảm 3–5; kéo không tới thì tăng 3–5, chỉnh từng mục một.")
                            .font(.footnote).foregroundColor(Color.white.opacity(0.75))
                        Text("Đây là gợi ý khởi điểm tính theo kích thước màn hình, tần số quét và lối chơi. Free Fire không có bảng độ nhạy chính thức theo từng máy, nên hãy tinh chỉnh theo cảm giác của bạn.")
                            .font(.caption).foregroundColor(Color.white.opacity(0.45))
                    }
                }
                .padding(16)
            }
        }
    }

    private func bar(_ name: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(value)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.cyan)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Theme.cyan).frame(width: g.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Mục 3: Thông tin admin

struct AdminView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    BrandHeader(subtitle: "Thông tin admin")

                    Card("Liên hệ", icon: "person.2.fill") {
                        contact(
                            icon: "message.fill", label: "Zalo", value: Config.zaloNumber,
                            action: "Nhắn Zalo",
                            onOpen: { if let u = URL(string: "https://zalo.me/" + Config.zaloNumber) { openURL(u) } },
                            copy: Config.zaloNumber
                        )
                        Divider().background(Color.white.opacity(0.15))
                        contact(
                            icon: "play.rectangle.fill", label: "TikTok", value: "@" + Config.tiktokUser,
                            action: "Mở TikTok",
                            onOpen: { if let u = URL(string: "https://www.tiktok.com/@" + Config.tiktokUser) { openURL(u) } },
                            copy: "@" + Config.tiktokUser
                        )
                        if copied {
                            Text("Đã sao chép").font(.caption).foregroundColor(Theme.good)
                        }
                    }

                    Card("Giấy phép của bạn", icon: "key.fill") {
                        if let i = state.info {
                            line("Gói", i.tier.uppercased())
                            line("Hạn dùng", state.expiryText(i))
                            line("Thiết bị", i.deviceLock ? "\(i.devicesUsed)/\(i.maxDevices)" : "Không giới hạn")
                            line("Key", mask(i.key))
                        }
                        if state.offline {
                            Text("Đang offline — dùng key đã lưu").font(.caption).foregroundColor(Theme.warn)
                        }
                        Button(role: .destructive) { state.logout() } label: {
                            Text("Đăng xuất key").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10)
                        }
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                    }

                    Text("Touch Technology · v\(version)")
                        .font(.caption).foregroundColor(Color.white.opacity(0.4))
                        .padding(.bottom, 20)
                }
                .padding(16)
            }
        }
    }

    private func line(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).foregroundColor(Color.white.opacity(0.65))
            Spacer()
            Text(b).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func mask(_ k: String) -> String {
        return k.count > 10 ? String(k.prefix(4)) + "••••" + String(k.suffix(4)) : k
    }

    private func contact(icon: String, label: String, value: String, action: String,
                         onOpen: @escaping () -> Void, copy: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.cyan)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(Color.white.opacity(0.55))
                Text(value).font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            Spacer()
            Button {
                UIPasteboard.general.string = copy
                copied = true
            } label: {
                Image(systemName: "doc.on.doc").padding(8)
            }
            Button(action: onOpen) {
                Text(action).font(.footnote.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.cyan).foregroundColor(.black).cornerRadius(10)
            }
        }
    }
}
