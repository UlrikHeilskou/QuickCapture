import Cocoa
import Foundation
import Combine

private struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [GitHubReleaseAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Codable {
    let name: String
    let url: String
    let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadUrl = "browser_download_url"
    }
}

public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()
    
    private let tokenKey = "QuickCapture_GitHub_Token"
    
    @Published public var githubToken: String = "" {
        didSet {
            UserDefaults.standard.set(githubToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tokenKey)
        }
    }
    
    @Published public var isChecking: Bool = false
    @Published public var isUpdateAvailable: Bool = false
    @Published public var latestVersion: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var downloadURL: URL? = nil
    @Published public var isPrivateAssetURL: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var statusMessage: String? = nil
    @Published public var showUpdateSheet: Bool = false
    
    private init() {
        self.githubToken = UserDefaults.standard.string(forKey: tokenKey) ?? ""
    }
    
    public var activeToken: String {
        return githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Checks GitHub Releases API for a newer version
    public func checkForUpdates(silent: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = nil
        
        guard let url = URL(string: AppConfig.githubReleasesAPI) else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url, timeoutInterval: 12.0)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("QuickCapture-Mac-Updater", forHTTPHeaderField: "User-Agent")
        
        let token = activeToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 404 {
                        if !silent {
                            self.statusMessage = "No releases found on GitHub yet."
                            self.showUpdateSheet = true
                        }
                        return
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        if !silent {
                            self.statusMessage = "GitHub access error (\(httpResponse.statusCode)). Please check token."
                            self.showUpdateSheet = true
                        }
                        return
                    }
                }
                
                if let error = error {
                    if !silent {
                        self.statusMessage = "Network error: \(error.localizedDescription)"
                        self.showUpdateSheet = true
                    }
                    return
                }
                
                guard let data = data else {
                    if !silent {
                        self.statusMessage = "Empty response received from GitHub."
                        self.showUpdateSheet = true
                    }
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let release = try decoder.decode(GitHubRelease.self, from: data)
                    
                    let remoteVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                    let currentVersion = AppConfig.appVersion
                    
                    if self.isVersionNewer(remoteVersion, than: currentVersion) {
                        self.latestVersion = remoteVersion
                        self.releaseNotes = release.body ?? "General improvements and fixes."
                        
                        // Find .zip asset
                        if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                            if !token.isEmpty {
                                self.downloadURL = URL(string: asset.url)
                                self.isPrivateAssetURL = true
                            } else {
                                self.downloadURL = URL(string: asset.browserDownloadUrl)
                                self.isPrivateAssetURL = false
                            }
                        }
                        
                        self.isUpdateAvailable = true
                        self.statusMessage = "New version v\(remoteVersion) is available!"
                        self.showUpdateSheet = true
                    } else {
                        self.isUpdateAvailable = false
                        self.statusMessage = "QuickCapture is up to date (v\(currentVersion))."
                        if !silent {
                            self.showUpdateSheet = true
                        }
                    }
                } catch {
                    if !silent {
                        self.statusMessage = "Error parsing release info: \(error.localizedDescription)"
                        self.showUpdateSheet = true
                    }
                }
            }
        }.resume()
    }
    
    /// Downloads the zip archive, extracts, replaces /Applications/QuickCapture.app and restarts
    public func downloadAndInstallUpdate() {
        guard let downloadURL = downloadURL, !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.1
        statusMessage = "Downloading update..."
        
        var request = URLRequest(url: downloadURL, timeoutInterval: 60.0)
        request.setValue("QuickCapture-Mac-Updater", forHTTPHeaderField: "User-Agent")
        
        let token = activeToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if isPrivateAssetURL {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }
        
        let session = URLSession.shared
        let downloadTask = session.downloadTask(with: request) { [weak self] localURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                }
                return
            }
            
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.statusMessage = "Download failed: File missing."
                }
                return
            }
            
            DispatchQueue.main.async {
                self.downloadProgress = 0.7
                self.statusMessage = "Installing update to /Applications..."
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                
                do {
                    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let zipTarget = tempDir.appendingPathComponent("update.zip")
                    try fileManager.moveItem(at: localURL, to: zipTarget)
                    
                    // Unzip archive via Process
                    let unzipProcess = Process()
                    unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    unzipProcess.arguments = ["-q", zipTarget.path, "-d", tempDir.path]
                    try unzipProcess.run()
                    unzipProcess.waitUntilExit()
                    
                    // Find QuickCapture.app in extracted folder
                    let extractedContents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    guard let newAppURL = extractedContents.first(where: { $0.lastPathComponent.hasSuffix(".app") }) else {
                        throw NSError(domain: "Updater", code: 404, userInfo: [NSLocalizedDescriptionKey: "No .app bundle found inside update zip package."])
                    }
                    
                    let targetAppURL = URL(fileURLWithPath: "/Applications/QuickCapture.app")
                    
                    if fileManager.fileExists(atPath: targetAppURL.path) {
                        try fileManager.removeItem(at: targetAppURL)
                    }
                    
                    try fileManager.copyItem(at: newAppURL, to: targetAppURL)
                    
                    // Re-codesign ad-hoc
                    let signProcess = Process()
                    signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                    signProcess.arguments = ["--force", "--deep", "--sign", "-", targetAppURL.path]
                    try? signProcess.run()
                    signProcess.waitUntilExit()
                    
                    DispatchQueue.main.async {
                        self.downloadProgress = 1.0
                        self.statusMessage = "Update installed! Restarting..."
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.relaunch(at: targetAppURL)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        self.statusMessage = "Installation error: \(error.localizedDescription)"
                    }
                }
            }
        }
        
        downloadTask.resume()
    }
    
    private func relaunch(at appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; sleep 0.2; open \"\(appURL.path)\""
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        
        DispatchQueue.main.async {
            NSApp.terminate(nil)
            exit(0)
        }
    }
    
    /// Compares two semantic version strings (e.g., 1.1.1001 vs 1.1.1000)
    public func isVersionNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, currentParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
