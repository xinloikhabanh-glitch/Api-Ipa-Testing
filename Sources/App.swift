import SwiftUI
import WebKit
import Security
import UIKit

// MARK: - Cấu hình (SỬA Ở ĐÂY)

enum Config {
    /// Địa chỉ server Vercel của bạn, KHÔNG có dấu "/" ở cuối.
    static let apiBase = "https://api-rust-alpha-49.vercel.app"

    /// Trang mở mặc định sau khi nhập key đúng.
    ///  - Trang trên mạng:      "https://ten-mien-cua-ban.vercel.app/panel.html"
    ///  - File HTML nằm trong app: "bundle:panel.html"   (file đặt trong thư mục Web/)
    static let defaultPage = "https://api-rust-alpha-49.vercel.app/activate.html"

    /// Cứ mỗi bao nhiêu giây thì kiểm tra lại key với server.
    static let recheckInterval: TimeInterval = 60
}

// MARK: - Keychain (lưu key + mã thiết bị, giữ lại cả khi xoá app nếu máy cho phép)

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
    @Published var page: String {
        didSet { UserDefaults.standard.set(page, forKey: "page") }
    }

    private var skew: Double = 0   // serverTime - giờ máy (ms)
    private var loop: Task<Void, Never>?

    init() {
        page = UserDefaults.standard.string(forKey: "page") ?? Config.defaultPage
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

// MARK: - File HTML nằm trong app (thư mục Web/)

enum Bundled {
    static var dir: URL? { return Bundle.main.url(forResource: "Web", withExtension: nil) }

    static func list() -> [String] {
        guard let dir = dir,
              let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let skip = dir.standardizedFileURL.pathComponents.count
        var out: [String] = []
        for case let u as URL in en where u.pathExtension.lowercased() == "html" {
            let rel = u.standardizedFileURL.pathComponents.dropFirst(skip).joined(separator: "/")
            out.append(rel)
        }
        return out.sorted()
    }
}

// MARK: - WebView (cầu nối giữa app và file HTML)

struct WebView: UIViewRepresentable {
    let target: String      // "https://..." hoặc "bundle:ten-file.html"
    let info: LicenseInfo

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true

        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: bridgeScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(context.coordinator, name: "native")
        cfg.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.load(target, in: wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.current != target {
            context.coordinator.load(target, in: wv)
        }
    }

    static func dismantleUIView(_ wv: WKWebView, coordinator: Coordinator) {
        wv.configuration.userContentController.removeScriptMessageHandler(forName: "native")
        wv.configuration.userContentController.removeAllUserScripts()
    }

    /// JS chèn vào MỌI trang HTML:
    ///  - window.NATIVE: thông tin key/thiết bị cho trang dùng
    ///  - tự điền key + hwid vào localStorage => trang HTML của bạn không phải nhập key lại
    ///  - fetch("/api/...") tự trỏ về server của bạn, kể cả khi file HTML nằm trong app
    ///  - mọi lời gọi /api/verify đều dùng đúng HWID của iPhone
    ///  - navigator.vibrate chạy được trên iOS (rung nhẹ)
    private func bridgeScript() -> String {
        let obj: [String: Any] = [
            "api": Config.apiBase,
            "key": info.key,
            "hwid": Device.hwid,
            "deviceName": Device.name,
            "tier": info.tier,
            "lifetime": info.lifetime,
            "expiresAt": info.expiresAt.map { $0 as Any } ?? NSNull(),
            "app": "ios"
        ]
        let json = (try? JSONSerialization.data(withJSONObject: obj))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let body = #"""
        window.NATIVE = C;
        try { localStorage.setItem('key', C.key); localStorage.setItem('hwid', C.hwid); } catch (e) {}
        function post(m) { try { window.webkit.messageHandlers.native.postMessage(m); } catch (e) {} }
        window.NATIVE.haptic = function (s) { post({ type: 'haptic', style: s || 'light' }); };
        window.NATIVE.open = function (u) { post({ type: 'open', url: String(u) }); };
        try { navigator.vibrate = function () { post({ type: 'haptic', style: 'light' }); return true; }; } catch (e) {}
        var of = window.fetch;
        window.fetch = function (input, init) {
          try {
            var url = (typeof input === 'string') ? input : ((input && input.url) || '');
            if (typeof input === 'string' && input.indexOf('/api/') === 0) { input = C.api + input; }
            if (url.indexOf('/api/verify') !== -1 && init && typeof init.body === 'string') {
              var b = JSON.parse(init.body);
              b.hwid = C.hwid; b.deviceName = C.deviceName;
              init = Object.assign({}, init, { body: JSON.stringify(b) });
            }
          } catch (e) {}
          return of.call(this, input, init);
        };
        """#

        return "(function(){ var C = " + json + ";\n" + body + "\n})();"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var current = ""

        func load(_ target: String, in wv: WKWebView) {
            current = target
            if target.hasPrefix("bundle:") {
                let rel = String(target.dropFirst("bundle:".count))
                if let dir = Bundled.dir {
                    let file = dir.appendingPathComponent(rel)
                    if FileManager.default.fileExists(atPath: file.path) {
                        wv.loadFileURL(file, allowingReadAccessTo: dir)
                        return
                    }
                }
                showError(wv, "Không tìm thấy file \(rel) trong app.")
            } else if let u = URL(string: target), let s = u.scheme?.lowercased(), s == "http" || s == "https" {
                wv.load(URLRequest(url: u))
            } else {
                showError(wv, "Địa chỉ không hợp lệ.")
            }
        }

        private func showError(_ wv: WKWebView, _ text: String) {
            let safe = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            wv.loadHTMLString("<meta name=viewport content='width=device-width'><body style='background:#111;color:#eee;font:17px -apple-system;padding:40px 24px'>\(safe)", baseURL: nil)
        }

        // Nhận lệnh từ JS
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let d = m.body as? [String: Any], let t = d["type"] as? String else { return }
            if t == "haptic" {
                let style: UIImpactFeedbackGenerator.FeedbackStyle
                switch d["style"] as? String {
                case "heavy": style = .heavy
                case "medium": style = .medium
                default: style = .light
                }
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            } else if t == "open",
                      let s = d["url"] as? String,
                      let u = URL(string: s),
                      let sc = u.scheme?.lowercased(), sc == "http" || sc == "https" {
                UIApplication.shared.open(u)
            }
        }

        // tel:, mailto:, itms-apps:... => mở bằng app hệ thống
        func webView(_ wv: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, let s = u.scheme?.lowercased(),
               !["http", "https", "file", "about", "blob", "data"].contains(s) {
                UIApplication.shared.open(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Link target="_blank" => mở ngay trong cùng WebView
        func webView(_ wv: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil { wv.load(action.request) }
            return nil
        }

        func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
            let code = (error as NSError).code
            if code == NSURLErrorCancelled { return }
            showError(wv, "Không mở được trang: \(error.localizedDescription)")
        }
    }
}

// MARK: - Giao diện

struct ActivationView: View {
    @EnvironmentObject var state: AppState
    @State private var key = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.28), Color(red: 0.30, green: 0.08, blue: 0.32)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Nhập key").font(.title.bold())
                Text("Cần key hợp lệ để sử dụng ứng dụng.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("PREM-XXXX-XXXX-XXXX-XXXX", text: $key)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.black.opacity(0.25))
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
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
                .disabled(state.busy)

                if !state.message.isEmpty {
                    Text(state.message)
                        .font(.footnote)
                        .foregroundColor(.red)
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

struct WebContainer: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.ignoresSafeArea()

            if let info = state.info {
                WebView(target: state.page, info: info)
                    .ignoresSafeArea()
            }

            // Nút nhỏ nửa ẩn ở mép trái để mở cài đặt
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .opacity(0.5)
            .offset(x: -22)

            if state.offline {
                VStack {
                    Text("Mất kết nối · đang dùng key đã lưu")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(state)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.presentationMode) private var presentation
    @State private var url = ""

    private var files: [String] { Bundled.list() }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Giấy phép")) {
                    if let i = state.info {
                        row("Gói", i.tier.uppercased())
                        row("Thời hạn", state.expiryText(i))
                        row("Thiết bị", i.deviceLock ? "\(i.devicesUsed)/\(i.maxDevices)" : "Không giới hạn")
                        row("Key", mask(i.key))
                    }
                }

                Section(header: Text("Trang web"),
                        footer: Text("Dán link trang HTML của bạn (https://…) hoặc chọn file HTML có sẵn trong app.")) {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    Button("Mở địa chỉ này") { apply(url) }
                    Button("Về trang mặc định") { apply(Config.defaultPage) }
                }

                if !files.isEmpty {
                    Section(header: Text("File HTML trong app")) {
                        ForEach(files, id: \.self) { f in
                            Button(f) { apply("bundle:" + f) }
                        }
                    }
                }

                Section {
                    Button("Đăng xuất key", role: .destructive) {
                        presentation.wrappedValue.dismiss()
                        state.logout()
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .onAppear { url = state.page.hasPrefix("bundle:") ? "" : state.page }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a)
            Spacer()
            Text(b).foregroundColor(.secondary)
        }
    }

    private func mask(_ k: String) -> String {
        return k.count > 10 ? String(k.prefix(4)) + "••••" + String(k.suffix(4)) : k
    }

    private func apply(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        state.page = t
        presentation.wrappedValue.dismiss()
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.info != nil {
            WebContainer()
        } else {
            ActivationView()
        }
    }
}

@main
struct LicenseApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { p in
                    if p == .active { Task { await state.recheck() } }
                }
        }
    }
}
