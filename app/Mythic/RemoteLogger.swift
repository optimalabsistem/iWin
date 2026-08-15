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
            UserDefaults.standard.string(forKey: "remote_log_server") ?? "http://3.1.51.240:8080/log"
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
        
        var ip = "3.1.51.240"
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
        
        // Fast UDP dispatch
        if udpSocket >= 0, var addr = serverAddr {
            let data = Array(text.utf8)
            data.withUnsafeBytes { ptr in
                withUnsafePointer(to: &addr) { addrPtr in
                    let rawAddrPtr = UnsafeRawPointer(addrPtr).assumingMemoryBound(to: sockaddr.self)
                    sendto(udpSocket, ptr.baseAddress, data.count, 0, rawAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        // HTTP async dispatch
        guard let url = URL(string: serverURLString) else { return }
        queue.async {
            var req = URLRequest(url: url, timeoutInterval: 3.0)
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
        
        // Signal crash handler
        signal(SIGSEGV) { sig in
            RemoteLogger.shared.send("[CRASH] Received SIGSEGV (\(sig)) - Segmentation Fault", level: "FATAL")
            exit(128 + sig)
        }
        signal(SIGBUS) { sig in
            RemoteLogger.shared.send("[CRASH] Received SIGBUS (\(sig)) - Bus Error / Bad Memory Access", level: "FATAL")
            exit(128 + sig)
        }
        signal(SIGILL) { sig in
            RemoteLogger.shared.send("[CRASH] Received SIGILL (\(sig)) - Illegal CPU Instruction", level: "FATAL")
            exit(128 + sig)
        }
        signal(SIGABRT) { sig in
            RemoteLogger.shared.send("[CRASH] Received SIGABRT (\(sig)) - Abort Signal", level: "FATAL")
            exit(128 + sig)
        }
    }
}
