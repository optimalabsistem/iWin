// HotPatchManager.swift — Dynamic OTA Hot-Patching Engine for iWin iOS.
// Enables instantaneous server-to-iPad DLL, shader, binary, and asset hot-patching
// without rebuilding or reinstalling the IPA.

import Foundation
import Combine

public final class HotPatchManager: ObservableObject {
    public static let shared = HotPatchManager()

    @Published public var isSyncing: Bool = false
    @Published public var lastSyncStatus: String = "Ready"
    @Published public var patchedFilesCount: Int = 0
    @Published public var lastSyncTime: Date? = nil

    private init() {
        // Auto-check on launch after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.syncHotPatches(silent: true)
        }
    }

    private var serverBaseURL: String {
        let saved = UserDefaults.standard.string(forKey: "remote_log_server") ?? ""
        if !saved.isEmpty {
            // Strip trailing /log or /
            var base = saved
            if base.hasSuffix("/log") {
                base = String(base.dropLast(4))
            }
            while base.hasSuffix("/") {
                base = String(base.dropLast(1))
            }
            return base
        }
        return "https://participation-disciplinary-que-carbon.trycloudflare.com"
    }

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

            // Download each file in manifest
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

        // Check local file size to avoid redundant downloads
        if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
           let localSize = attrs[.size] as? Int,
           localSize == size {
            // Already matches, skip download and move to next
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

                // Also copy directly into wine prefix system32 if applicable
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
