// 红果短剧 · Mac 原生壳
// 职责: 启动/停止本地后端(unidbg 签名 :9099 + FastAPI :8010), 用 WKWebView 承载 UI。
// 编译: build.sh (swiftc -O -parse-as-library)

import AppKit
import SwiftUI
import WebKit

// MARK: - 路径常量
// 运行目录默认 ~/hongguo-mac, 可用环境变量 HONGGUO_HOME 覆盖(setup_mac.command 安装布局)

let kHome = NSHomeDirectory()
let kRoot = ProcessInfo.processInfo.environment["HONGGUO_HOME"] ?? (kHome + "/hongguo-mac")
let kRunDir = kRoot + "/run"
let kApiBase = "http://127.0.0.1:8010"

/// Java 查找顺序: 安装器解压的 Temurin JRE → Homebrew openjdk@17 → Homebrew openjdk → 系统 PATH
let kJavaBin: String = {
    let candidates = [
        kRoot + "/jre/Contents/Home/bin/java",
        kRoot + "/jre/Home/bin/java",
        "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java",
        "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home/bin/java",
        "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java",
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
    return "java"
}()

// MARK: - 状态

enum Phase { case starting, ready, failed }

final class AppState: ObservableObject {
    @Published var phase: Phase = .starting
    @Published var statusText = "正在启动本地服务…"
    @Published var errorText = ""
}

let appState = AppState()

// MARK: - 服务管理

final class ServiceManager {
    static let shared = ServiceManager()
    private var javaProc: Process?
    private var pyProc: Process?
    private var logHandles: [FileHandle] = []   // 保持存活, 防 SIGPIPE
    let spawnedJava: Bool
    let spawnedPy: Bool

    private init() {
        // 若外部已把服务跑起来(如 start_all.sh), 则采用之, 退出时不杀
        spawnedJava = false
        spawnedPy = false
    }

    /// 127.0.0.1 端口可连 = 服务在
    private func portOpen(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    private func appendLogHandle(_ path: String) -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        guard let h = FileHandle(forWritingAtPath: path) else { return nil }
        h.seekToEndOfFile()
        logHandles.append(h)
        return h
    }

    /// 本机 server.py 的尺寸+修改时间, 与后端 /health 的 code_sig 对比, 判断是否同一份代码
    private func localCodeSig() -> String? {
        let path = kRunDir + "/app/server.py"
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let size = (a[.size] as? NSNumber)?.int64Value ?? -1
        let mtime = Int64((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1)
        return "\(size)-\(mtime)"
    }

    private struct Health: Decodable {
        let service: String
        let pid: Int32
        let code_sig: String
        let app_pid: Int32
    }

    private func fetchHealth() async -> Health? {
        guard let url = URL(string: kApiBase + "/health") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Health.self, from: data)
        } catch { return nil }
    }

    private func terminate(_ pid: Int32) async {
        kill(pid, SIGTERM)
        for _ in 0..<10 { if !portOpen(8010) { return }; try? await Task.sleep(nanoseconds: 300_000_000) }
        kill(pid, SIGKILL)
        for _ in 0..<10 { if !portOpen(8010) { return }; try? await Task.sleep(nanoseconds: 200_000_000) }
    }

    /// 处理 8010 上的既有服务: adopt=复用, spawn=需要自己拉起, fail=端口被他人占用/关不掉。
    private enum PyPrep: Equatable { case adopt, spawn, fail }

    private func preparePython() async -> PyPrep {
        guard portOpen(8010) else { return .spawn }
        guard let h = await fetchHealth(), h.service == "红果短剧API" else {
            appState.errorText = "端口 8010 被其他程序占用，无法启动后端"
            return .fail
        }
        let mine = Int32(ProcessInfo.processInfo.processIdentifier)
        if h.code_sig == localCodeSig() && (h.app_pid == 0 || h.app_pid == mine) {
            return .adopt                             // 同一份代码, 且属于当前 App 或外部启动
        }
        appState.statusText = "检测到旧后端，正在重启…"
        await terminate(h.pid)                        // 旧 python 退出时会顺带收掉它的签名服务
        return portOpen(8010) ? .fail : .spawn
    }

    private func spawnPython(signPid: Int32) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: kRunDir + "/venv/bin/python")
        p.arguments = ["server.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: kRunDir + "/app")
        p.environment = [
            "SIGN_SERVER": "http://127.0.0.1:9099",
            "PORT": "8010",
            "HONGGUO_APP_PID": String(ProcessInfo.processInfo.processIdentifier),
            "HONGGUO_SIGN_PID": String(signPid),
            "HOME": kHome,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
            "LANG": "zh_CN.UTF-8",
        ]
        if let log = appendLogHandle("/tmp/hongguo-api.log") {
            p.standardOutput = log
            p.standardError = log
        }
        do { try p.run(); pyProc = p } catch {
            appState.errorText = "后端服务启动失败: \(error.localizedDescription)"
            return false
        }
        return true
    }

    /// 启动全部服务并等 API 就绪(最长 ~40s)。已运行的端口直接复用。
    func startAll() async -> Bool {
        let hadPython = portOpen(8010)
        let prep = await preparePython()
        guard prep != .fail else {
            if appState.errorText.isEmpty { appState.errorText = "旧后端无法关闭，请手动结束占用 8010 的进程" }
            return false
        }
        if hadPython && prep == .spawn {
            try? await Task.sleep(nanoseconds: 1_000_000_000)   // 等旧 python 收掉它拉起的签名服务
        }
        if !portOpen(9099) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: kJavaBin)
            p.arguments = ["--add-opens", "java.base/java.lang=ALL-UNNAMED",
                           "-cp", "unidbg-sign.jar", "com.hongguo.sign.FqTrace", "serve", "9099"]
            p.currentDirectoryURL = URL(fileURLWithPath: kRunDir + "/sign")
            if let log = appendLogHandle("/tmp/hongguo-sign.log") {
                p.standardOutput = log
                p.standardError = log
            }
            do { try p.run(); javaProc = p } catch {
                appState.errorText = "签名服务启动失败: \(error.localizedDescription)"
                return false
            }
        }
        if prep == .spawn, !spawnPython(signPid: javaProc?.processIdentifier ?? 0) { return false }
        for i in 0..<80 {
            if await apiHealthy() { return true }
            if let p = pyProc, !p.isRunning { break }
            if i == 20 { appState.statusText = "等待签名服务初始化(so 模拟器加载中)…" }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return await apiHealthy()
    }

    private func apiHealthy() async -> Bool {
        guard let url = URL(string: kApiBase + "/ui") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    /// 只收掉自己拉起的进程(外部启动的不动)
    func stopSpawned() {
        javaProc?.terminate()
        pyProc?.terminate()
    }
}

// MARK: - WKWebView

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []   // 允许自动连播
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {}
}

// MARK: - 界面

struct ContentView: View {
    @ObservedObject var state = appState

    var body: some View {
        switch state.phase {
        case .starting:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(state.statusText).foregroundStyle(.secondary)
                Text("首次启动需加载签名模拟器, 约 5~10 秒")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            WebView(url: URL(string: kApiBase + "/ui")!)
                .ignoresSafeArea()
        case .failed:
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                Text("本地服务未能启动").font(.title3.bold())
                Text(state.errorText.isEmpty ? "请查看 /tmp/hongguo-api.log 与 /tmp/hongguo-sign.log" : state.errorText)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("重试") {
                        appState.phase = .starting
                        appState.statusText = "正在重试…"
                        Task { @MainActor in
                            if await ServiceManager.shared.startAll() {
                                appState.phase = .ready
                            } else { appState.phase = .failed }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("打开日志") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp"))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - App

@main
struct HongguoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("红果短剧") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let ok = await ServiceManager.shared.startAll()
            appState.phase = ok ? .ready : .failed
            if !ok && appState.errorText.isEmpty {
                appState.errorText = "服务在 40 秒内未就绪"
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServiceManager.shared.stopSpawned()
    }
}
