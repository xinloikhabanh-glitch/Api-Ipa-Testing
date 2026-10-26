import SwiftUI
import UIKit
import Security

// MARK: - Cấu hình (SỬA Ở ĐÂY)

enum Config {
    /// Địa chỉ server Vercel của bạn, KHÔNG có dấu "/" ở cuối.
    static let apiBase = "https://api-rust-alpha-49.vercel.app"

    /// Cứ mỗi bao nhiêu giây thì kiểm tra lại key với server.
    static let recheckInterval: TimeInterval = 60

    static let zaloNumber = "0335849687"
    static let tiktokUser = "thaitunhahotran"
}

// MARK: - Giao diện chung

enum Theme {
    static let bg = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let cyan = Color(red: 0.16, green: 0.78, blue: 1.0)
    static let card = Color.white.opacity(0.07)
    static let good = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let warn = Color(red: 1.0, green: 0.78, blue: 0.2)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.38)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.cyan.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color.purple.opacity(0.18), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    let title: String
    var icon: String = ""
    let content: Content

    init(_ title: String, icon: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if !icon.isEmpty {
                    Image(systemName: icon).foregroundColor(Theme.cyan)
                }
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.65))
                    .tracking(1)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .cornerRadius(20)
    }
}

struct BrandHeader: View {
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOUCH TECHNOLOGY")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(Theme.cyan)
                .shadow(color: Theme.cyan.opacity(0.7), radius: 10)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Keychain (lưu key + mã thiết bị)

enum Keychain {
    private static let service = "app.license"

    private static func base(_ account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func get(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data,
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        // Một số bản ký sideload không cho dùng Keychain => dự phòng UserDefaults
        return UserDefaults.standard.string(forKey: "kc_" + account)
    }

    static func set(_ value: String, for account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var add = base(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: "kc_" + account)
        } else {
            UserDefaults.standard.set(value, forKey: "kc_" + account)
        }
    }

    static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "kc_" + account)
    }
}

// MARK: - Thiết bị (HWID)

enum Device {
    /// Mã thiết bị: tạo 1 lần từ identifierForVendor rồi lưu cố định.
    static var hwid: String {
        if let v = Keychain.get("hwid"), v.count >= 6 { return v }
        let id = "ios-" + (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)
        Keychain.set(id, for: "hwid")
        return id
    }

    static var name: String { return UIDevice.current.model }
}

// MARK: - Gọi API

struct LicenseInfo: Codable, Equatable {
    let key: String
    let tier: String
    let duration: String?
    let lifetime: Bool
    let activatedAt: Double?
    let expiresAt: Double?
    let remainingMs: Double?
    let deviceLock: Bool
    let maxDevices: Int
    let devicesUsed: Int
    let serverTime: Double
}

struct ErrorBody: Decodable {
    let error: String?
    let message: String?
}

enum LicenseError: Error {
    case rejected(String)     // server từ chối key (sai, hết hạn, bị khoá, đủ thiết bị...)
    case unavailable(String)  // server lỗi / không có mạng => không khoá người dùng
}

enum LicenseService {
    static func verify(key: String) async throws -> LicenseInfo {
        guard let url = URL(string: Config.apiBase + "/api/verify") else {
            throw LicenseError.unavailable("Sai địa chỉ máy chủ")
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "hwid": Device.hwid,
            "deviceName": Device.name
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if status == 200, let info = try? JSONDecoder().decode(LicenseInfo.self, from: data) {
            return info
        }
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let msg = body?.message ?? "Lỗi máy chủ (\(status))"
        // 404 không kèm mã lỗi JSON = sai đường dẫn API, không phải key sai
        if status >= 500 || status == 0 || (status == 404 && body?.error == nil) {
            throw LicenseError.unavailable(msg)
        }
        throw LicenseError.rejected(msg)
    }
}

// MARK: - Trạng thái ứng dụng

@MainActor
final class AppState: ObservableObject {
    @Published var info: LicenseInfo?
    @Published var busy = false
    @Published var message = ""
    @Published var offline = false

    private var skew: Double = 0   // serverTime - giờ máy (ms)
    private var loop: Task<Void, Never>?

    init() {
        if let k = Keychain.get("key") {
            Task { await self.activate(k) }
        }
    }

    func activate(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { message = "Hãy nhập key."; return }
        guard !busy else { return }
        busy = true
        message = ""
        defer { busy = false }

        do {
            let i = try await LicenseService.verify(key: key)
            accept(i, key: key)
        } catch LicenseError.rejected(let m) {
            Keychain.delete("key")
            clearCache()
            info = nil
            message = m
        } catch LicenseError.unavailable(let m) {
            if let cached = loadCache(), cached.key == key, !isExpired(cached) {
                info = cached          // tạm dùng offline cho đến khi có mạng
                offline = true
                startLoop()
            } else {
                message = m
            }
        } catch {
            if let cached = loadCache(), cached.key == key, !isExpired(cached) {
                info = cached
                offline = true
                startLoop()
            } else {
                message = "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại."
            }
        }
    }

    func recheck() async {
        guard !busy, info != nil, let key = Keychain.get("key") else { return }
        do {
            let i = try await LicenseService.verify(key: key)
            accept(i, key: key)
        } catch LicenseError.rejected(let m) {
            lock(m)
        } catch {
            offline = true
            if let i = info, isExpired(i) { lock("Key đã hết hạn") }
        }
    }

    func logout() { lock("") }

    func expiryText(_ i: LicenseInfo) -> String {
        if i.lifetime { return "Vĩnh viễn" }
        guard let e = i.expiresAt else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: e / 1000))
    }

    // MARK: nội bộ

    private func accept(_ i: LicenseInfo, key: String) {
        Keychain.set(key, for: "key")
        skew = i.serverTime - Date().timeIntervalSince1970 * 1000
        offline = false
        message = ""
        saveCache(i)
        if info != i { info = i }
        startLoop()
    }

    private func lock(_ msg: String) {
        loop?.cancel()
        loop = nil
        Keychain.delete("key")
        clearCache()
        info = nil
        offline = false
        message = msg
    }

    private func isExpired(_ i: LicenseInfo) -> Bool {
        if i.lifetime { return false }
        guard let e = i.expiresAt else { return false }
        return e <= Date().timeIntervalSince1970 * 1000 + skew
    }

    private func startLoop() {
        loop?.cancel()
        let ns = UInt64(Config.recheckInterval * 1_000_000_000)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                if Task.isCancelled { break }
                await self?.recheck()
            }
        }
    }

    private func saveCache(_ i: LicenseInfo) {
        if let d = try? JSONEncoder().encode(i) { UserDefaults.standard.set(d, forKey: "license_cache") }
    }

    private func loadCache() -> LicenseInfo? {
        guard let d = UserDefaults.standard.data(forKey: "license_cache") else { return nil }
        return try? JSONDecoder().decode(LicenseInfo.self, from: d)
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: "license_cache")
    }
}

// MARK: - Màn hình nhập key

struct ActivationView: View {
    @EnvironmentObject var state: AppState
    @State private var key = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 14) {
                Text("TOUCH TECHNOLOGY")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Theme.cyan)
                    .shadow(color: Theme.cyan.opacity(0.7), radius: 10)
                Text("Nhập key để mở khoá ứng dụng")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)

                TextField("PREM-XXXX-XXXX-XXXX-XXXX", text: $key)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(14)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if state.busy { ProgressView() }
                        Text(state.busy ? "Đang kiểm tra…" : "Mở khoá").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                }
                .background(Theme.cyan.opacity(state.busy ? 0.5 : 0.9))
                .foregroundColor(.black)
                .cornerRadius(14)
                .disabled(state.busy)

                if !state.message.isEmpty {
                    Text(state.message)
                        .font(.footnote)
                        .foregroundColor(Theme.bad)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
            .padding(20)
        }
        .onAppear {
            if key.isEmpty, let k = Keychain.get("key") { key = k }
        }
    }

    private func submit() {
        focused = false
        let k = key
        Task { await state.activate(k) }
    }
}

// MARK: - 3 mục chính

struct MainTabs: View {
    var body: some View {
        TabView {
            FeaturesView()
                .tabItem { Label("Chức năng", systemImage: "bolt.fill") }
            SensitivityView()
                .tabItem { Label("Độ nhạy FF", systemImage: "slider.horizontal.3") }
            AdminView()
                .tabItem { Label("Admin", systemImage: "person.crop.circle.fill") }
        }
        .accentColor(Theme.cyan)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.info != nil {
            MainTabs()
        } else {
            ActivationView()
        }
    }
}

@main
struct LicenseApp: App {
    @StateObject private var state = AppState()
    @StateObject private var music = MusicPlayer()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(music)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { p in
                    if p == .active { Task { await state.recheck() } }
                }
        }
    }
}
