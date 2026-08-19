import Foundation
import UIKit
import Darwin

final class RemoteLogger {
    static let shared = RemoteLogger()
    
    private let queue = DispatchQueue(label: "com.iwin.remotelogger", qos: .utility)
    private var udpSocket: Int32 = -1
    private var serverAddr: sockaddr_in?
    
    var serverURLString: String {
        get {
            UserDefaults.standard.string(forKey: "remote_log_server") ?? "https://colleague-biographies-shut-enterprises.trycloudflare.com/log"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "remote_log_server")
            setupUDP()
        }
    }
    
    private init() {
        setupUDP()
        installCrashHandlers()
    }
    
    private func setupUDP() {
        if udpSocket != -1 {
            close(udpSocket)
            udpSocket = -1
        }
        
        udpSocket = socket(AF_INET, SOCK_DGRAM, 0)
        guard udpSocket >= 0 else { return }
        
        var broadcastEnable: Int32 = 1
        setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        
        var ip = "10.92.38.13"
        var port: UInt16 = 8080
        
        if let url = URL(string: serverURLString), let host = url.host {
            ip = host
            port = UInt16(url.port ?? 8080)
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        self.serverAddr = addr
    }
    
    func send(_ message: String, level: String = "INFO") {
        let text = "[\(level)] \(message)"
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Fast UDP dispatch
            if self.udpSocket >= 0, var addr = self.serverAddr {
                let data = Array(text.utf8)
                data.withUnsafeBytes { ptr in
                    withUnsafePointer(to: &addr) { addrPtr in
                        let rawAddrPtr = UnsafeRawPointer(addrPtr).assumingMemoryBound(to: sockaddr.self)
                        sendto(self.udpSocket, ptr.baseAddress, data.count, 0, rawAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            
            // HTTP async dispatch
            guard let url = URL(string: self.serverURLString) else { return }
            var req = URLRequest(url: url, timeoutInterval: 2.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("true", forHTTPHeaderField: "Bypass-Tunnel-Reminder")
            let payload: [String: String] = [
                "level": level,
                "message": message,
                "timestamp": "\(Date())"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    func testConnection(completion: @escaping (Bool, String) -> Void) {
        guard let baseURL = URL(string: serverURLString),
              let host = baseURL.host else {
            completion(false, "Invalid URL format")
            return
        }
        let scheme = baseURL.scheme ?? "http"
        let portStr = baseURL.port != nil ? ":\(baseURL.port!)" : (scheme == "http" ? ":8080" : "")
        let statusURL = URL(string: "\(scheme)://\(host)\(portStr)/status") ?? baseURL
        var req = URLRequest(url: statusURL, timeoutInterval: 4.0)
        req.httpMethod = "GET"
        req.setValue("true", forHTTPHeaderField: "Bypass-Tunnel-Reminder")
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(false, err.localizedDescription)
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    completion(true, "Connected successfully to \(host)!")
                } else {
                    completion(false, "Server returned HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            }
        }.resume()
    }
    
    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let crashReport = "[CRASH] Uncaught Exception: \(exception.name.rawValue): \(exception.reason ?? "none")\nCall Stack:\n\(symbols)"
            RemoteLogger.shared.send(crashReport, level: "CRASH")
        }
        // Do NOT install POSIX signal handlers (SIGSEGV/SIGBUS/SIGILL) here:
        // Wine and FEX on iOS require full ownership of signals and Mach exception ports
        // for SEH, write watch, JIT pool access, and page virtualization.
    }
}

// MARK: - Notifications for Remote Control
extension Notification.Name {
    static let mythicLaunch3DTest = Notification.Name("mythicLaunch3DTest")
    static let mythicStopWine = Notification.Name("mythicStopWine")
}

// MARK: - Dynamic OTA Hot-Patching & Remote Command Manager
public final class HotPatchManager: ObservableObject {
    public static let shared = HotPatchManager()

    @Published public var isSyncing: Bool = false
    @Published public var lastSyncStatus: String = "Ready"
    @Published public var patchedFilesCount: Int = 0
    @Published public var lastSyncTime: Date? = nil
    @Published public var remoteControlActive: Bool = true

    private var pollTimer: Timer?

    private init() {
        // Auto-check patches disabled to protect system32 binary integrity
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startRemoteCommandPolling()
        }
    }

    private var serverBaseURL: String {
        let saved = UserDefaults.standard.string(forKey: "remote_log_server") ?? ""
        if !saved.isEmpty {
            var base = saved
            if base.hasSuffix("/log") {
                base = String(base.dropLast(4))
            }
            while base.hasSuffix("/") {
                base = String(base.dropLast(1))
            }
            return base
        }
        return "https://colleague-biographies-shut-enterprises.trycloudflare.com"
    }

    // MARK: - Remote Control Loop
    public func startRemoteCommandPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollRemoteCommand()
        }
    }

    private func pollRemoteCommand() {
        guard let url = URL(string: "\(serverBaseURL)/api/command/poll") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self = self, let data = data, err == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cmd = json["cmd"] as? String, cmd != "none" else { return }

            DispatchQueue.main.async {
                self.executeRemoteCommand(cmd: cmd, payload: json)
            }
        }.resume()
    }

    private func executeRemoteCommand(cmd: String, payload: [String: Any]) {
        let target = (payload["target"] as? String) ?? "cube.exe"
        LogStore.shared.log("Remote Command received: \(cmd) (target=\(target))", level: .info)

        switch cmd {
        case "launch_3d":
            NotificationCenter.default.post(name: .mythicLaunch3DTest, object: target)
            sendAck(cmd: cmd, status: "launched", target: target)

        case "stop_wine":
            NotificationCenter.default.post(name: .mythicStopWine, object: nil)
            sendAck(cmd: cmd, status: "stopped", target: target)

        case "sync_patches":
            syncHotPatches { success, msg in
                self.sendAck(cmd: cmd, status: success ? "synced" : "failed", target: msg)
            }

        case "sync_and_launch":
            NotificationCenter.default.post(name: .mythicStopWine, object: nil)
            syncHotPatches { success, msg in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(name: .mythicLaunch3DTest, object: target)
                    self.sendAck(cmd: cmd, status: "synced_and_launched", target: target)
                }
            }

        default:
            sendAck(cmd: cmd, status: "unknown_command", target: target)
        }
    }

    private func sendAck(cmd: String, status: String, target: String) {
        guard let url = URL(string: "\(serverBaseURL)/api/command/ack") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "ack": cmd,
            "status": status,
            "target": target,
            "time": Date().timeIntervalSince1970
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - OTA Hot Patch Sync
    public func syncHotPatches(silent: Bool = false, completion: ((Bool, String) -> Void)? = nil) {
        guard !isSyncing else {
            completion?(false, "Sync already in progress")
            return
        }

        isSyncing = true
        if !silent {
            lastSyncStatus = "Checking server for patches..."
        }
        LogStore.shared.log("OTA: Checking patch manifest from \(serverBaseURL)...", level: .info)

        guard let manifestURL = URL(string: "\(serverBaseURL)/api/patch/manifest") else {
            isSyncing = false
            let err = "Invalid manifest URL"
            lastSyncStatus = err
            LogStore.shared.log("OTA Error: \(err)", level: .error)
            completion?(false, err)
            return
        }

        var req = URLRequest(url: manifestURL)
        req.timeoutInterval = 8.0

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    let err = "Manifest fetch failed: \(error.localizedDescription)"
                    self.lastSyncStatus = err
                    LogStore.shared.log("OTA Error: \(err)", level: .error)
                    completion?(false, err)
                }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let files = json["files"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    let err = "Invalid manifest JSON response"
                    self.lastSyncStatus = err
                    LogStore.shared.log("OTA Error: \(err)", level: .error)
                    completion?(false, err)
                }
                return
            }

            if files.isEmpty {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.lastSyncStatus = "Up to date (no patches pending)"
                    self.lastSyncTime = Date()
                    LogStore.shared.log("OTA: App is fully up-to-date with server.", level: .success)
                    completion?(true, "No new patches on server")
                }
                return
            }

            self.downloadPatchFiles(files: files, index: 0, updatedCount: 0, completion: completion)
        }.resume()
    }

    private func downloadPatchFiles(files: [[String: Any]], index: Int, updatedCount: Int, completion: ((Bool, String) -> Void)?) {
        guard index < files.count else {
            DispatchQueue.main.async {
                self.isSyncing = false
                self.patchedFilesCount += updatedCount
                self.lastSyncTime = Date()
                let status = updatedCount > 0 ? "Successfully synced \(updatedCount) patch file(s)!" : "All patches up to date"
                self.lastSyncStatus = status
                LogStore.shared.log("OTA: \(status)", level: .success)
                completion?(true, status)
            }
            return
        }

        let fileInfo = files[index]
        guard let name = fileInfo["name"] as? String,
              let size = fileInfo["size"] as? Int else {
            downloadPatchFiles(files: files, index: index + 1, updatedCount: updatedCount, completion: completion)
            return
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let patchDir = docs.appendingPathComponent("hot_patches", isDirectory: true)
        let targetURL = patchDir.appendingPathComponent(name)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
           let localSize = attrs[.size] as? Int,
           localSize == size {
            downloadPatchFiles(files: files, index: index + 1, updatedCount: updatedCount, completion: completion)
            return
        }

        DispatchQueue.main.async {
            self.lastSyncStatus = "Downloading patch [\(index + 1)/\(files.count)]: \(name)..."
        }

        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let dlURL = URL(string: "\(serverBaseURL)/api/patch/download/\(encodedName)") else {
            downloadPatchFiles(files: files, index: index + 1, updatedCount: updatedCount, completion: completion)
            return
        }

        var dlReq = URLRequest(url: dlURL)
        dlReq.timeoutInterval = 15.0

        URLSession.shared.dataTask(with: dlReq) { [weak self] fileData, _, err in
            guard let self = self else { return }
            if let fileData = fileData, err == nil {
                try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileData.write(to: targetURL, options: .atomic)

                self.applyPatchToPrefix(name: name, fileData: fileData)
                LogStore.shared.log("OTA: Hot-patched \(name) (\(fileData.count) bytes)", level: .info)
                self.downloadPatchFiles(files: files, index: index + 1, updatedCount: updatedCount + 1, completion: completion)
            } else {
                LogStore.shared.log("OTA Error: Failed to download \(name)", level: .error)
                self.downloadPatchFiles(files: files, index: index + 1, updatedCount: updatedCount, completion: completion)
            }
        }.resume()
    }

    private func applyPatchToPrefix(name: String, fileData: Data) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let wineRoot = docs.appendingPathComponent("wine/dosdevices/c:", isDirectory: true)

        let targetPrefixURL: URL
        if name.hasPrefix("system32/") || name.hasPrefix("system32\\") {
            let filename = URL(fileURLWithPath: name).lastPathComponent
            targetPrefixURL = wineRoot.appendingPathComponent("windows/system32/\(filename)")
        } else {
            targetPrefixURL = wineRoot.appendingPathComponent(name)
        }

        try? FileManager.default.createDirectory(at: targetPrefixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: targetPrefixURL)
        try? fileData.write(to: targetPrefixURL, options: .atomic)
    }
}
