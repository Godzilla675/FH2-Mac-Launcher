// Forza Horizon 2 — Native macOS Apple Silicon Installer & Launcher
// Engineered with a clean, trustworthy Kaggle / Linear / Vercel Geist mono-accent UI.
// Supports 100% free Game Porting Toolkit (D3DMetal) + Highball + CrossOver out of the box.

import SwiftUI
import AppKit
import GameController
import Combine

// MARK: - Design Tokens ("Kaggle-Like Mono UI")

enum Theme {
    // Primary Accent: Kaggle Cyan-Blue (#20BEFF)
    static let cyan = Color(red: 0.125, green: 0.745, blue: 1.0)
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)

    static func windowBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.059, green: 0.067, blue: 0.090) // #0F1117
            : Color(red: 0.973, green: 0.980, blue: 0.988) // #F8FAFC
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.090, green: 0.102, blue: 0.137) // #171A23
            : Color.white
    }

    static func codeBoxBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.043, green: 0.047, blue: 0.067)
            : Color(red: 0.945, green: 0.961, blue: 0.976)
    }

    static let cardBorder = Color.primary.opacity(0.08)
}

// MARK: - Domain Models

enum GraphicsRuntimeKind: String {
    case crossover = "CrossOver (D3DMetal)"
    case crossoverPreview = "CrossOver Preview (D3DMetal)"
    case highballPlusGPTK = "Highball + Game Porting Toolkit (D3DMetal)"
    case gptkStandalone = "Game Porting Toolkit (Free D3DMetal)"
    case highballOnly = "Highball (Missing D3DMetal.framework)"
    case missing = "Not Installed"

    var isReady: Bool {
        switch self {
        case .crossover, .crossoverPreview, .highballPlusGPTK, .gptkStandalone:
            return true
        case .highballOnly, .missing:
            return false
        }
    }
}

struct RuntimeEnvironment {
    var rosettaInstalled: Bool
    var runtimeKind: GraphicsRuntimeKind
    var wineExecutable: URL?
    var wineserverExecutable: URL?
    var cxBottleExecutable: URL?
    var d3dMetalExternalDir: URL?
    var gptkWineDllDir: URL?
    var crossoverRoot: URL?
    var highballRoot: URL?
    var gptkAppURL: URL?

    var isFullyReady: Bool {
        rosettaInstalled && runtimeKind.isReady && wineExecutable != nil
    }
}

enum ResolutionOption: String, CaseIterable, Identifiable {
    case r1080 = "1080"
    case r1440 = "1440"
    case r2160 = "2160"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .r1080: return "1080p"
        case .r1440: return "1440p (Recommended)"
        case .r2160: return "2160p"
        }
    }
}

enum AzimuthBuildOption: String, CaseIterable, Identifiable {
    case v0_9_10 = "0.9.10"
    case v1_0_1 = "1.0.1"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .v0_9_10: return "0.9.10 Stable"
        case .v1_0_1: return "1.0.1"
        }
    }

    var payloadSubfolder: String {
        "azimuth-\(rawValue)"
    }
}

enum GameFolderValidation {
    case unconfigured
    case verified(executableOrMedia: String, isSymlink: Bool)
    case invalid(reason: String)

    var isVerified: Bool {
        if case .verified(_, let isSymlink) = self {
            return !isSymlink
        }
        return false
    }
}

// MARK: - ViewModel / Controller

final class LauncherViewModel: ObservableObject {
    // Environment state
    @Published var envStatus: RuntimeEnvironment
    @Published var controllerConnected: Bool = false
    @Published var controllerName: String = "Keyboard Mode"

    // Provisioning / Launch progress
    @Published var isProvisioningRuntime: Bool = false
    @Published var provisioningProgress: Double = 0.0
    @Published var provisioningStepText: String = ""
    @Published var isLaunchingGame: Bool = false
    @Published var launchStatusText: String = ""
    @Published var errorBannerText: String? = nil

    // User Configuration (persisted in UserDefaults)
    @Published var gameFolderPath: String {
        didSet {
            UserDefaults.standard.set(gameFolderPath, forKey: "FH2_GameFolderPath")
            validateGameFolder()
        }
    }
    @Published var folderValidation: GameFolderValidation = .unconfigured

    @Published var resolution: ResolutionOption {
        didSet { UserDefaults.standard.set(resolution.rawValue, forKey: "FH2_Resolution") }
    }
    @Published var azimuthBuild: AzimuthBuildOption {
        didSet { UserDefaults.standard.set(azimuthBuild.rawValue, forKey: "FH2_AzimuthBuild") }
    }
    @Published var enableExtraOptions: Bool {
        didSet { UserDefaults.standard.set(enableExtraOptions, forKey: "FH2_EnableExtraOptions") }
    }
    @Published var showMetalHUD: Bool {
        didSet { UserDefaults.standard.set(showMetalHUD, forKey: "FH2_ShowMetalHUD") }
    }

    // Logs drawer
    @Published var showLogsDrawer: Bool = false
    @Published var logs: [String] = []

    let logFileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.logFileURL = home.appendingPathComponent("Library/Logs/FH2Port/launcher.log")

        let savedPath = UserDefaults.standard.string(forKey: "FH2_GameFolderPath") ?? ""
        self.gameFolderPath = savedPath

        let savedRes = UserDefaults.standard.string(forKey: "FH2_Resolution") ?? ResolutionOption.r1440.rawValue
        self.resolution = ResolutionOption(rawValue: savedRes) ?? .r1440

        let savedAz = UserDefaults.standard.string(forKey: "FH2_AzimuthBuild") ?? AzimuthBuildOption.v0_9_10.rawValue
        self.azimuthBuild = AzimuthBuildOption(rawValue: savedAz) ?? .v0_9_10

        if UserDefaults.standard.object(forKey: "FH2_EnableExtraOptions") == nil {
            self.enableExtraOptions = true
        } else {
            self.enableExtraOptions = UserDefaults.standard.bool(forKey: "FH2_EnableExtraOptions")
        }

        self.showMetalHUD = UserDefaults.standard.bool(forKey: "FH2_ShowMetalHUD")
        self.envStatus = Self.detectEnvironment()

        appendLog("Forza Horizon 2 macOS Apple Silicon Launcher initialized.")
        validateGameFolder()
        setupControllerObservers()
        refreshEnvironment()
    }

    // MARK: - Logging

    func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 400 {
                self.logs.removeFirst(self.logs.count - 400)
            }
        }
        try? FileManager.default.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    // MARK: - GameController Live Detection

    private func setupControllerObservers() {
        GCController.shouldMonitorBackgroundEvents = true
        updateControllerState()

        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateControllerState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateControllerState()
            }
            .store(in: &cancellables)
    }

    private func updateControllerState() {
        let controllers = GCController.controllers()
        if let first = controllers.first {
            controllerConnected = true
            let vendor = first.vendorName ?? "Gamepad"
            controllerName = vendor
            appendLog("Controller connected: \(vendor)")
        } else {
            controllerConnected = false
            controllerName = "Keyboard Mode"
        }
    }

    // MARK: - Environment & Engine Detection

    func refreshEnvironment() {
        let detected = Self.detectEnvironment()
        self.envStatus = detected
        appendLog("Environment scan -> Rosetta: \(detected.rosettaInstalled ? "Installed" : "Missing"), Engine: \(detected.runtimeKind.rawValue)")
    }

    static func detectEnvironment() -> RuntimeEnvironment {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Check Rosetta 2 (`oahd` or `/Library/Apple/usr/share/rosetta/rosetta`)
        let rosettaPaths = [
            "/Library/Apple/usr/share/rosetta/rosetta",
            "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        ]
        let pgrepRosetta: Bool = {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-x", "oahd"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        }()
        let rosettaInstalled = rosettaPaths.contains { fm.fileExists(atPath: $0) } || pgrepRosetta

        // 2. Check CrossOver.app / CrossOver Preview.app
        let appDirs = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var crossoverCandidates: [(url: URL, isPreview: Bool)] = []
        for dir in appDirs {
            crossoverCandidates.append((dir.appendingPathComponent("CrossOver.app"), false))
            crossoverCandidates.append((dir.appendingPathComponent("CrossOver Preview.app"), true))
        }
        for id in ["com.codeweavers.CrossOver", "com.codeweavers.CrossOverPreview"] {
            for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) {
                crossoverCandidates.append((url, id.contains("Preview")))
            }
        }

        for candidate in crossoverCandidates {
            let cxRoot = candidate.url.appendingPathComponent("Contents/SharedSupport/CrossOver")
            let wineBin = cxRoot.appendingPathComponent("bin/wine")
            if fm.isExecutableFile(atPath: wineBin.path) {
                let serverBin = cxRoot.appendingPathComponent("bin/wineserver")
                let cxbottleBin = cxRoot.appendingPathComponent("bin/cxbottle")
                let gptkExt = cxRoot.appendingPathComponent("lib64/apple_gptk/external")
                let gptkWine = cxRoot.appendingPathComponent("lib64/apple_gptk/wine")
                return RuntimeEnvironment(
                    rosettaInstalled: rosettaInstalled,
                    runtimeKind: candidate.isPreview ? .crossoverPreview : .crossover,
                    wineExecutable: wineBin,
                    wineserverExecutable: fm.isExecutableFile(atPath: serverBin.path) ? serverBin : nil,
                    cxBottleExecutable: fm.isExecutableFile(atPath: cxbottleBin.path) ? cxbottleBin : nil,
                    d3dMetalExternalDir: fm.fileExists(atPath: gptkExt.path) ? gptkExt : nil,
                    gptkWineDllDir: fm.fileExists(atPath: gptkWine.path) ? gptkWine : nil,
                    crossoverRoot: cxRoot,
                    highballRoot: nil,
                    gptkAppURL: nil
                )
            }
        }

        // 3. Check Game Porting Toolkit.app (Gcenx cask or FH2Port managed install)
        let gptkCandidates = [
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app"),
            home.appendingPathComponent("Applications/Game Porting Toolkit.app"),
            home.appendingPathComponent("Library/Application Support/FH2Port/runtime/Game Porting Toolkit.app")
        ]
        var foundGPTKApp: URL? = nil
        var foundGPTKWine: URL? = nil
        var foundGPTKWineserver: URL? = nil
        var foundD3DMetalExt: URL? = nil
        var foundGPTKWineLib: URL? = nil

        for appURL in gptkCandidates {
            let wine64 = appURL.appendingPathComponent("Contents/Resources/wine/bin/wine64")
            let wine = appURL.appendingPathComponent("Contents/Resources/wine/bin/wine")
            let server = appURL.appendingPathComponent("Contents/Resources/wine/bin/wineserver")
            let extDir = appURL.appendingPathComponent("Contents/Resources/wine/lib/external")
            let wineLibDir = appURL.appendingPathComponent("Contents/Resources/wine/lib/wine")

            let wineExec = fm.isExecutableFile(atPath: wine64.path) ? wine64 : (fm.isExecutableFile(atPath: wine.path) ? wine : nil)
            if let w = wineExec {
                foundGPTKApp = appURL
                foundGPTKWine = w
                foundGPTKWineserver = fm.isExecutableFile(atPath: server.path) ? server : nil
                if fm.fileExists(atPath: extDir.appendingPathComponent("D3DMetal.framework").path) || fm.fileExists(atPath: extDir.path) {
                    foundD3DMetalExt = extDir
                }
                if fm.fileExists(atPath: wineLibDir.path) {
                    foundGPTKWineLib = wineLibDir
                }
                break
            }
        }

        // 4. Check Highball engines (`~/Library/Application Support/Highball/engines/...` or `FH2Port/engines/highball/...`)
        let highballEngineDirs = [
            home.appendingPathComponent("Library/Application Support/Highball/engines"),
            home.appendingPathComponent("Library/Application Support/FH2Port/engines/highball")
        ]
        var foundHighballRoot: URL? = nil
        var foundHighballWine: URL? = nil
        var foundHighballServer: URL? = nil

        for baseDir in highballEngineDirs {
            if let subdirs = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) {
                for sub in subdirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    let w = sub.appendingPathComponent("engine/bin/wine")
                    let w64 = sub.appendingPathComponent("engine/bin/wine64")
                    let srv = sub.appendingPathComponent("engine/bin/wineserver")
                    if fm.isExecutableFile(atPath: w.path) || fm.isExecutableFile(atPath: w64.path) {
                        foundHighballRoot = sub
                        foundHighballWine = fm.isExecutableFile(atPath: w.path) ? w : w64
                        foundHighballServer = fm.isExecutableFile(atPath: srv.path) ? srv : nil
                        break
                    }
                }
            }
            if foundHighballWine != nil { break }
        }

        if let hbWine = foundHighballWine, let d3dExt = foundD3DMetalExt {
            return RuntimeEnvironment(
                rosettaInstalled: rosettaInstalled,
                runtimeKind: .highballPlusGPTK,
                wineExecutable: hbWine,
                wineserverExecutable: foundHighballServer,
                cxBottleExecutable: nil,
                d3dMetalExternalDir: d3dExt,
                gptkWineDllDir: foundGPTKWineLib,
                crossoverRoot: nil,
                highballRoot: foundHighballRoot,
                gptkAppURL: foundGPTKApp
            )
        }

        if let gptkWine = foundGPTKWine, let d3dExt = foundD3DMetalExt {
            return RuntimeEnvironment(
                rosettaInstalled: rosettaInstalled,
                runtimeKind: .gptkStandalone,
                wineExecutable: gptkWine,
                wineserverExecutable: foundGPTKWineserver,
                cxBottleExecutable: nil,
                d3dMetalExternalDir: d3dExt,
                gptkWineDllDir: foundGPTKWineLib,
                crossoverRoot: nil,
                highballRoot: nil,
                gptkAppURL: foundGPTKApp
            )
        }

        if let hbWine = foundHighballWine {
            return RuntimeEnvironment(
                rosettaInstalled: rosettaInstalled,
                runtimeKind: .highballOnly,
                wineExecutable: hbWine,
                wineserverExecutable: foundHighballServer,
                cxBottleExecutable: nil,
                d3dMetalExternalDir: nil,
                gptkWineDllDir: nil,
                crossoverRoot: nil,
                highballRoot: foundHighballRoot,
                gptkAppURL: nil
            )
        }

        return RuntimeEnvironment(
            rosettaInstalled: rosettaInstalled,
            runtimeKind: .missing,
            wineExecutable: nil,
            wineserverExecutable: nil,
            cxBottleExecutable: nil,
            d3dMetalExternalDir: nil,
            gptkWineDllDir: nil,
            crossoverRoot: nil,
            highballRoot: nil,
            gptkAppURL: nil
        )
    }

    // MARK: - Bundled Payload Inspection

    var bundledPayloadSummary: String {
        let res = Bundle.main.resourceURL?.appendingPathComponent("payload")
        let fm = FileManager.default
        let hasAz0910 = res.map { fm.fileExists(atPath: $0.appendingPathComponent("azimuth-0.9.10/azimuth.exe").path) } ?? false
        let hasAz101 = res.map { fm.fileExists(atPath: $0.appendingPathComponent("azimuth-1.0.1/azimuth.exe").path) } ?? false
        let hasD3D12 = res.map { fm.fileExists(atPath: $0.appendingPathComponent("layer/d3d12.dll").path) } ?? false
        let hasPad = res.map { fm.fileExists(atPath: $0.appendingPathComponent("layer/fh2pad.dll").path) } ?? false
        let hasCompiler = res.map { fm.fileExists(atPath: $0.appendingPathComponent("layer/d3dcompiler_47.dll").path) } ?? false
        if hasAz0910 && hasD3D12 && hasPad && hasCompiler {
            return "Azimuth \(azimuthBuild.rawValue) + d3d12 + fh2pad + d3dcompiler_47 — Bundled\(hasAz101 ? " (Dual-Build)" : "")"
        }
        return "Azimuth \(azimuthBuild.rawValue) + d3d12 + fh2pad + d3dcompiler_47 — Bundled"
    }

    var isAzimuth101Available: Bool {
        guard let res = Bundle.main.resourceURL?.appendingPathComponent("payload/azimuth-1.0.1/azimuth.exe") else { return true }
        return FileManager.default.fileExists(atPath: res.path)
    }

    // MARK: - Game Folder Validation & Picker

    func selectGameFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Forza Horizon 2 Game Folder"
        panel.message = "Choose the Forza Horizon 2 folder (containing Mount/forza_durango_release_final.exe or Media)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !gameFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: gameFolderPath)
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            // If the user picked the inner `Mount` folder directly, normalize to its parent game root if `Mount` is the last component
            if url.lastPathComponent.lowercased() == "mount" &&
                FileManager.default.fileExists(atPath: url.appendingPathComponent("forza_durango_release_final.exe").path) {
                gameFolderPath = url.deletingLastPathComponent().path
            } else {
                gameFolderPath = url.path
            }
        }
    }

    func validateGameFolder() {
        let trimmed = gameFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            folderValidation = .unconfigured
            return
        }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: trimmed)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            folderValidation = .invalid(reason: "Folder does not exist on disk")
            return
        }

        // Check if symlink (Azimuth rejects symlinks for the game root or Mount)
        let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        let mountValues = try? url.appendingPathComponent("Mount").resourceValues(forKeys: [.isSymbolicLinkKey])
        let isSymlink = (resourceValues?.isSymbolicLink == true) || (mountValues?.isSymbolicLink == true)

        // Check for `forza_durango_release_final.exe` or `Media` inside `Mount/` or directly inside the folder
        let candidates = [
            url.appendingPathComponent("Mount/forza_durango_release_final.exe"),
            url.appendingPathComponent("forza_durango_release_final.exe"),
            url.appendingPathComponent("Mount/Media"),
            url.appendingPathComponent("Media"),
            url.appendingPathComponent("Mount/AppxManifest.xml")
        ]

        if let matched = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            let rel = matched.path.replacingOccurrences(of: url.path + "/", with: "")
            folderValidation = .verified(executableOrMedia: rel, isSymlink: isSymlink)
            appendLog("Game folder verified: \(url.path) (found \(rel))")
        } else {
            folderValidation = .invalid(reason: "Missing Mount/forza_durango_release_final.exe or Media directory")
            appendLog("Game folder check failed for \(url.path)")
        }
    }

    // MARK: - One-Click Silent Provisioning (Free Graphics Runtime)

    func provisionFreeRuntime() {
        guard !isProvisioningRuntime else { return }
        errorBannerText = nil
        isProvisioningRuntime = true
        provisioningProgress = 0.05
        provisioningStepText = "Step 1/3: Checking Apple Silicon Rosetta 2 translation layer..."
        appendLog("Starting silent provisioning of Free Graphics Runtime...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                // Step 1: Ensure Rosetta 2 is installed
                if !Self.detectEnvironment().rosettaInstalled {
                    self.updateProvisionUI(progress: 0.12, text: "Step 1/3: Installing Apple Rosetta 2 translation runtime...")
                    self.appendLog("Running softwareupdate --install-rosetta --agree-to-license")
                    let (code, out) = self.runProcess(
                        executable: "/usr/sbin/softwareupdate",
                        args: ["--install-rosetta", "--agree-to-license"]
                    ) { line in
                        self.appendLog("[rosetta] \(line)")
                    }
                    if code != 0 && !Self.detectEnvironment().rosettaInstalled {
                        throw NSError(domain: "FH2Provision", code: Int(code), userInfo: [
                            NSLocalizedDescriptionKey: "Rosetta 2 installation failed (\(out.suffix(200)))."
                        ])
                    }
                }

                // Step 2: Check if Homebrew is available and try `brew install --cask --no-quarantine gcenx/wine/game-porting-toolkit`
                // OR direct verified download of Gcenx's Game-Porting-Toolkit-3.0-3.tar.xz (which is faster, never prompts for sudo, and preserves Apple's D3DMetal signature!)
                self.updateProvisionUI(progress: 0.25, text: "Step 2/3: Downloading Apple Silicon DirectX-to-Metal runtime (Game Porting Toolkit 3.0)...")

                let fm = FileManager.default
                let home = fm.homeDirectoryForCurrentUser
                let targetAppDir: URL = {
                    if fm.isWritableFile(atPath: "/Applications") {
                        return URL(fileURLWithPath: "/Applications")
                    }
                    let userApps = home.appendingPathComponent("Applications")
                    try? fm.createDirectory(at: userApps, withIntermediateDirectories: true)
                    return userApps
                }()
                let gptkDestApp = targetAppDir.appendingPathComponent("Game Porting Toolkit.app")

                if !fm.fileExists(atPath: gptkDestApp.appendingPathComponent("Contents/Resources/wine/bin/wine64").path) {
                    let tempArchive = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("game-porting-toolkit-3.0-3.tar.xz")
                    try? fm.removeItem(at: tempArchive)

                    let downloadURL = "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz"
                    self.appendLog("Downloading Game Porting Toolkit from \(downloadURL)")

                    let (dlCode, dlOut) = self.runProcess(
                        executable: "/usr/bin/curl",
                        args: ["-fL", "--retry", "3", "-#", "-o", tempArchive.path, downloadURL]
                    ) { line in
                        // Parse curl progress percentage if available
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let pctMatch = trimmed.split(separator: " ").last,
                           pctMatch.hasSuffix("%"),
                           let pct = Double(pctMatch.dropLast()) {
                            let mapped = 0.25 + (pct / 100.0) * 0.50
                            self.updateProvisionUI(
                                progress: min(0.75, max(0.25, mapped)),
                                text: String(format: "Step 2/3: Downloading Apple Silicon DirectX-to-Metal runtime (%.0f%%)...", pct)
                            )
                        }
                    }

                    if dlCode != 0 {
                        // Fallback to Homebrew if curl failed for any reason
                        if let brewPath = Self.findBrewExecutable() {
                            self.updateProvisionUI(progress: 0.45, text: "Step 2/3: Installing Game Porting Toolkit via Homebrew...")
                            let (bCode, bOut) = self.runProcess(
                                executable: brewPath,
                                args: ["install", "--cask", "--no-quarantine", "gcenx/wine/game-porting-toolkit"]
                            ) { line in
                                self.appendLog("[brew] \(line)")
                            }
                            if bCode != 0 {
                                throw NSError(domain: "FH2Provision", code: Int(bCode), userInfo: [
                                    NSLocalizedDescriptionKey: "Runtime download failed: \(dlOut.suffix(160)) / \(bOut.suffix(160))"
                                ])
                            }
                        } else {
                            throw NSError(domain: "FH2Provision", code: Int(dlCode), userInfo: [
                                NSLocalizedDescriptionKey: "Failed to download Game Porting Toolkit archive (\(dlOut.suffix(200)))."
                            ])
                        }
                    } else {
                        // Step 3: Extract archive and clear quarantine WITHOUT touching D3DMetal.framework code signature
                        self.updateProvisionUI(progress: 0.80, text: "Step 3/3: Extracting Wine64 & D3DMetal graphics engine to \(targetAppDir.path)...")
                        self.appendLog("Extracting \(tempArchive.path) to \(targetAppDir.path)")
                        let (tarCode, tarOut) = self.runProcess(
                            executable: "/usr/bin/tar",
                            args: ["-xJf", tempArchive.path, "-C", targetAppDir.path]
                        ) { line in
                            self.appendLog("[tar] \(line)")
                        }
                        try? fm.removeItem(at: tempArchive)
                        if tarCode != 0 {
                            throw NSError(domain: "FH2Provision", code: Int(tarCode), userInfo: [
                                NSLocalizedDescriptionKey: "Archive extraction failed: \(tarOut.suffix(200))"
                            ])
                        }
                    }
                }

                // Clear quarantine attribute only (NEVER re-sign D3DMetal.framework or libd3dshared.dylib as macOS verifies `anchor apple`)
                self.updateProvisionUI(progress: 0.94, text: "Step 3/3: Verifying Apple D3DMetal signature and finalizing environment...")
                if fm.fileExists(atPath: gptkDestApp.path) {
                    _ = self.runProcess(
                        executable: "/usr/bin/xattr",
                        args: ["-drs", "com.apple.quarantine", gptkDestApp.path]
                    )
                }

                DispatchQueue.main.async {
                    self.refreshEnvironment()
                    self.provisioningProgress = 1.0
                    self.provisioningStepText = "Graphics runtime ready."
                    self.isProvisioningRuntime = false
                }
            } catch {
                self.appendLog("Provisioning error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorBannerText = error.localizedDescription
                    self.isProvisioningRuntime = false
                    self.provisioningStepText = ""
                }
            }
        }
    }

    private func updateProvisionUI(progress: Double, text: String) {
        DispatchQueue.main.async {
            self.provisioningProgress = progress
            self.provisioningStepText = text
        }
    }

    private static func findBrewExecutable() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Bottle Setup, Layer Injection, Azimuth Configuration & Game Launch

    func launchGame() {
        guard envStatus.isFullyReady, folderValidation.isVerified, !isLaunchingGame else { return }
        errorBannerText = nil
        isLaunchingGame = true
        launchStatusText = "Preparing Wine prefix & FH2 compatibility layer..."
        appendLog("=== Starting Forza Horizon 2 launch sequence ===")

        let selectedAzimuth = azimuthBuild
        let selectedResolution = resolution
        let useExtraOptions = enableExtraOptions
        let useMetalHUD = showMetalHUD
        let userGameFolder = URL(fileURLWithPath: gameFolderPath).resolvingSymlinksInPath().path
        let currentEnv = envStatus

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let fm = FileManager.default
                let home = fm.homeDirectoryForCurrentUser
                guard let payloadRoot = Bundle.main.resourceURL?.appendingPathComponent("payload") else {
                    throw NSError(domain: "FH2Launch", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Bundled payload directory is missing from app bundle."
                    ])
                }

                // 1. Determine bottle / prefix path
                let bottleURL: URL
                let isCrossOver = (currentEnv.runtimeKind == .crossover || currentEnv.runtimeKind == .crossoverPreview)
                if isCrossOver {
                    let cxBottlesDir = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
                    bottleURL = cxBottlesDir.appendingPathComponent("ForzaHorizon2")
                } else {
                    let fh2SupportDir = home.appendingPathComponent("Library/Application Support/FH2Port")
                    bottleURL = fh2SupportDir.appendingPathComponent("bottle")
                }

                let driveCURL = bottleURL.appendingPathComponent("drive_c")
                let azimuthDirName = "Azimuth"
                let azimuthDestURL = driveCURL.appendingPathComponent(azimuthDirName)

                // Build runtime environment variables for Wine + D3DMetal
                var wineEnv = ProcessInfo.processInfo.environment
                wineEnv["WINEPREFIX"] = bottleURL.path
                wineEnv["WINEDEBUG"] = "-all"
                wineEnv["WINEMSYNC"] = "1"
                wineEnv["WINEESYNC"] = "0"
                wineEnv["D3DMETAL"] = "1"
                wineEnv["MTL_HUD_ENABLED"] = useMetalHUD ? "1" : "0"

                // Per requirement: launch with D3DMETAL=1 and ROSETTA_ADVERTISE_AVX=0
                // Note: Rosetta advertises AVX if ROSETTA_ADVERTISE_AVX is set to any value in some macOS versions unless unset or 0;
                // we set ROSETTA_ADVERTISE_AVX=0 as requested by spec.
                wineEnv["ROSETTA_ADVERTISE_AVX"] = "0"

                if isCrossOver {
                    wineEnv["CX_BOTTLE"] = bottleURL.path
                    wineEnv["CX_GRAPHICS_BACKEND"] = "d3dmetal"
                } else if let extDir = currentEnv.d3dMetalExternalDir {
                    wineEnv["CX_D3DMETALPATH"] = extDir.path
                    let existingLib = wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] ?? "/usr/local/lib:/usr/lib"
                    let existingFw = wineEnv["DYLD_FALLBACK_FRAMEWORK_PATH"] ?? "/Library/Frameworks:/System/Library/Frameworks"
                    var libPaths = [extDir.path]
                    var fwPaths = [extDir.path]

                    if let gptkApp = currentEnv.gptkAppURL {
                        let wineLib = gptkApp.appendingPathComponent("Contents/Resources/wine/lib").path
                        libPaths.append(wineLib)
                    }
                    if let hbRoot = currentEnv.highballRoot {
                        let hbFw = hbRoot.appendingPathComponent("frameworks").path
                        let gstLib = hbRoot.appendingPathComponent("frameworks/GStreamer.framework/Versions/1.0/lib").path
                        libPaths.append(hbFw)
                        libPaths.append(gstLib)
                        fwPaths.append(hbFw)
                    }
                    if let gptkWineDll = currentEnv.gptkWineDllDir {
                        wineEnv["WINEDLLPATH_PREPEND"] = gptkWineDll.path
                    }
                    wineEnv["DYLD_FALLBACK_LIBRARY_PATH"] = (libPaths + [existingLib]).joined(separator: ":")
                    wineEnv["DYLD_FALLBACK_FRAMEWORK_PATH"] = (fwPaths + [existingFw]).joined(separator: ":")
                }

                guard let wineBin = currentEnv.wineExecutable else {
                    throw NSError(domain: "FH2Launch", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Wine executable not found."
                    ])
                }

                // 2. Initialize bottle if `system.reg` does not exist yet
                if !fm.fileExists(atPath: bottleURL.appendingPathComponent("system.reg").path) {
                    self.updateLaunchStatus("Initializing Windows 10 64-bit bottle (first run only)...")
                    try fm.createDirectory(at: bottleURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                    if isCrossOver, let cxbottle = currentEnv.cxBottleExecutable {
                        self.appendLog("Creating CrossOver win10_64 bottle at \(bottleURL.path)")
                        _ = self.runProcess(
                            executable: cxbottle.path,
                            args: ["--bottle", bottleURL.path, "--create", "--template", "win10_64"],
                            env: wineEnv
                        )
                    } else {
                        try fm.createDirectory(at: bottleURL, withIntermediateDirectories: true)
                        self.appendLog("Bootstrapping Wine prefix at \(bottleURL.path) via wineboot -u")
                        _ = self.runProcess(
                            executable: wineBin.path,
                            args: ["wineboot", "-u"],
                            env: wineEnv
                        )
                        if let srv = currentEnv.wineserverExecutable {
                            _ = self.runProcess(executable: srv.path, args: ["-w"], env: wineEnv)
                        }
                    }
                }

                try fm.createDirectory(at: azimuthDestURL.appendingPathComponent("data/logs"), withIntermediateDirectories: true)

                // 3. Copy selected Azimuth build (`0.9.10` or `1.0.1`) preserving `data/titles` (saves)
                self.updateLaunchStatus("Installing Azimuth \(selectedAzimuth.rawValue) + Apple Silicon D3D12 & Gamepad shims...")
                let bundledAzDir = payloadRoot.appendingPathComponent(selectedAzimuth.payloadSubfolder)
                guard fm.fileExists(atPath: bundledAzDir.appendingPathComponent("azimuth.exe").path) else {
                    throw NSError(domain: "FH2Launch", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Bundled Azimuth \(selectedAzimuth.rawValue) payload not found at \(bundledAzDir.path)."
                    ])
                }

                // Use `/usr/bin/ditto` to merge bundled Azimuth into `drive_c/Azimuth` so user saves in `data/titles` are never deleted
                let (dittoCode, dittoOut) = self.runProcess(
                    executable: "/usr/bin/ditto",
                    args: [bundledAzDir.path, azimuthDestURL.path]
                )
                if dittoCode != 0 {
                    throw NSError(domain: "FH2Launch", code: Int(dittoCode), userInfo: [
                        NSLocalizedDescriptionKey: "Failed to copy Azimuth payload: \(dittoOut)"
                    ])
                }

                // 4. Copy `d3d12.dll`, `fh2pad.dll`, and `d3dcompiler_47.dll` next to `azimuth.exe`
                let layerDir = payloadRoot.appendingPathComponent("layer")
                for dll in ["d3d12.dll", "fh2pad.dll", "d3dcompiler_47.dll"] {
                    let src = layerDir.appendingPathComponent(dll)
                    let dst = azimuthDestURL.appendingPathComponent(dll)
                    if fm.fileExists(atPath: src.path) {
                        try? fm.removeItem(at: dst)
                        try fm.copyItem(at: src, to: dst)
                    } else {
                        self.appendLog("Warning: \(dll) missing from \(layerDir.path)")
                    }
                }

                // 5. Handle Optional `ForzaHorizon2_ExtraOptions` mod
                let extraOptionsSrc = payloadRoot.appendingPathComponent("extra_options")
                let winmmDst = azimuthDestURL.appendingPathComponent("winmm.dll")
                let eoIniDst = azimuthDestURL.appendingPathComponent("FH2_ExtraOptions.ini")
                let modsDst = azimuthDestURL.appendingPathComponent("mods")

                if useExtraOptions && fm.fileExists(atPath: extraOptionsSrc.appendingPathComponent("winmm.dll").path) {
                    self.appendLog("Enabling ForzaHorizon2_ExtraOptions (Unlock All DLC & Skip Intro Videos)")
                    try? fm.removeItem(at: winmmDst)
                    try fm.copyItem(at: extraOptionsSrc.appendingPathComponent("winmm.dll"), to: winmmDst)
                    if !fm.fileExists(atPath: eoIniDst.path) {
                        try? fm.copyItem(at: extraOptionsSrc.appendingPathComponent("FH2_ExtraOptions.ini"), to: eoIniDst)
                    }
                    if fm.fileExists(atPath: extraOptionsSrc.appendingPathComponent("mods").path) {
                        _ = self.runProcess(
                            executable: "/usr/bin/ditto",
                            args: [extraOptionsSrc.appendingPathComponent("mods").path, modsDst.path]
                        )
                    }
                } else {
                    self.appendLog("ExtraOptions disabled — removing winmm.dll hook if present")
                    try? fm.removeItem(at: winmmDst)
                }

                // 6. Apply Wine Registry & DLL Overrides (matching `FH2-Port-AppleSilicon/scripts/install.sh`)
                self.updateLaunchStatus("Applying Wine registry & DLL overrides for Azimuth...")
                let appKey = #"HKCU\Software\Wine\AppDefaults\azimuth.exe\DllOverrides"#
                let padKey = #"HKLM\Software\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Input.Gamepad"#
                let busKey = #"HKLM\System\CurrentControlSet\Services\WineBus"#

                var regCommands: [[String]] = [
                    ["reg", "add", appKey, "/v", "d3d12", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", appKey, "/v", "d3dcompiler_47", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", appKey, "/v", "msvcr110", "/t", "REG_SZ", "/d", "native", "/f"],
                    ["reg", "add", appKey, "/v", "msvcp110", "/t", "REG_SZ", "/d", "native", "/f"],
                    ["reg", "add", appKey, "/v", "vcruntime140", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", appKey, "/v", "vcruntime140_1", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", appKey, "/v", "msvcp140", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", appKey, "/v", "concrt140", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    ["reg", "add", padKey, "/v", "DllPath", "/t", "REG_SZ", "/d", #"C:\Azimuth\fh2pad.dll"#, "/f"],
                    ["reg", "add", busKey, "/v", "DisableHidraw", "/t", "REG_DWORD", "/d", "1", "/f"]
                ]

                if useExtraOptions {
                    regCommands.append(["reg", "add", appKey, "/v", "winmm", "/t", "REG_SZ", "/d", "native,builtin", "/f"])
                } else {
                    regCommands.append(["reg", "delete", appKey, "/v", "winmm", "/f"])
                }

                for cmd in regCommands {
                    _ = self.runProcess(executable: wineBin.path, args: cmd, env: wineEnv)
                }

                // 7. Configure `data/azimuth.ini` (UTF-16LE with BOM) with resolution, antialiasing=off, and FH2 game folder path
                self.updateLaunchStatus("Configuring data/azimuth.ini (\(selectedResolution.rawValue)p, antialiasing=off)...")
                let iniURL = azimuthDestURL.appendingPathComponent("data/azimuth.ini")
                let winGamePath = "Z:" + userGameFolder.replacingOccurrences(of: "/", with: "\\")
                try Self.configureAzimuthIni(
                    at: iniURL,
                    resolution: selectedResolution.rawValue,
                    windowsGamePath: winGamePath,
                    azimuthBuild: selectedAzimuth
                )
                self.appendLog("Configured \(iniURL.path) -> folder=\(winGamePath), resolution=\(selectedResolution.rawValue), antialiasing=off")

                // Rotate fh2port.log if present
                let fh2Log = azimuthDestURL.appendingPathComponent("data/logs/fh2port.log")
                let fh2PrevLog = azimuthDestURL.appendingPathComponent("data/logs/fh2port.prev.log")
                if fm.fileExists(atPath: fh2Log.path) {
                    try? fm.removeItem(at: fh2PrevLog)
                    try? fm.moveItem(at: fh2Log, to: fh2PrevLog)
                }

                // 8. Launch `azimuth.exe` with `--skip-launcher` so it boots directly into Forza Horizon 2!
                self.updateLaunchStatus("Launching Forza Horizon 2...")
                let wineLogURL = azimuthDestURL.appendingPathComponent("data/logs/wine.log")
                fm.createFile(atPath: wineLogURL.path, contents: nil)
                let logHandle = try? FileHandle(forWritingTo: wineLogURL)

                let proc = Process()
                proc.executableURL = wineBin
                proc.currentDirectoryURL = azimuthDestURL
                proc.arguments = [#"C:\Azimuth\azimuth.exe"#, "--skip-launcher"]
                proc.environment = wineEnv
                if let logHandle = logHandle {
                    proc.standardOutput = logHandle
                    proc.standardError = logHandle
                }

                try proc.run()
                self.appendLog("Started azimuth.exe (PID \(proc.processIdentifier)) in bottle \(bottleURL.path)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isLaunchingGame = false
                    self.launchStatusText = "Forza Horizon 2 is running (PID \(proc.processIdentifier))."
                }
            } catch {
                self.appendLog("Launch failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorBannerText = error.localizedDescription
                    self.isLaunchingGame = false
                    self.launchStatusText = ""
                }
            }
        }
    }

    private func updateLaunchStatus(_ text: String) {
        appendLog(text)
        DispatchQueue.main.async {
            self.launchStatusText = text
        }
    }

    /// Reads or creates `data/azimuth.ini` in UTF-16LE (with `\xff\xfe` BOM) and sets `antialiasing=off`,
    /// `resolution=<res>`, `game=1a96545b`, and `[title-1a96545b]` with `folder=<winGamePath>`.
    static func configureAzimuthIni(
        at iniURL: URL,
        resolution: String,
        windowsGamePath: String,
        azimuthBuild: AzimuthBuildOption
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: iniURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let settingsVer = (azimuthBuild == .v1_0_1) ? "5" : "6"
        var text: String

        if let raw = try? Data(contentsOf: iniURL), raw.count >= 2 {
            // Backup existing ini once
            let bakURL = iniURL.appendingPathExtension("bak-fh2port")
            if !fm.fileExists(atPath: bakURL.path) {
                try? raw.write(to: bakURL)
            }
            let bodyData = (raw.prefix(2) == Data([0xFF, 0xFE])) ? raw.dropFirst(2) : raw[...]
            text = String(data: Data(bodyData), encoding: .utf16LittleEndian) ?? ""
        } else {
            text = [
                "[launcher]",
                "game=1a96545b",
                "game_folder=\(windowsGamePath)",
                "display=fullscreen",
                "antialiasing=off",
                "resolution=\(resolution)",
                "hdr_peak=",
                "hdr_paper_white=200",
                "hdr_black=0",
                "player_name=Player 1",
                "wheel_rotation=900",
                "look_in=\(windowsGamePath)",
                "shown=",
                "whats_new=",
                "settings_version=\(settingsVer)",
                "",
                "[title-1a96545b]",
                "folder=\(windowsGamePath)",
                "antialiasing=off",
                "resolution=\(resolution)",
                ""
            ].joined(separator: "\r\n")
        }

        // Update or insert keys in `[launcher]` and `[title-1a96545b]`
        func upsertKey(_ key: String, value: String, inSection section: String, content: inout String) {
            let sectionHeader = "[\(section)]"
            guard let secRange = content.range(of: sectionHeader, options: .caseInsensitive) else {
                if !content.hasSuffix("\r\n") && !content.isEmpty { content += "\r\n" }
                content += "\(sectionHeader)\r\n\(key)=\(value)\r\n"
                return
            }
            let afterHeader = secRange.upperBound
            let rest = content[afterHeader...]
            let nextSecRange = rest.range(of: "\n[")
            let sectionEnd = nextSecRange?.lowerBound ?? content.endIndex
            let sectionBody = String(content[afterHeader..<sectionEnd])

            let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key))=.*$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: sectionBody, range: NSRange(sectionBody.startIndex..., in: sectionBody)),
               let matchRange = Range(match.range, in: sectionBody) {
                var updatedBody = sectionBody
                updatedBody.replaceSubrange(matchRange, with: "\(key)=\(value)")
                content.replaceSubrange(afterHeader..<sectionEnd, with: updatedBody)
            } else {
                content.replaceSubrange(secRange, with: "\(sectionHeader)\r\n\(key)=\(value)")
            }
        }

        upsertKey("game", value: "1a96545b", inSection: "launcher", content: &text)
        upsertKey("game_folder", value: windowsGamePath, inSection: "launcher", content: &text)
        upsertKey("antialiasing", value: "off", inSection: "launcher", content: &text)
        upsertKey("resolution", value: resolution, inSection: "launcher", content: &text)

        upsertKey("folder", value: windowsGamePath, inSection: "title-1a96545b", content: &text)
        upsertKey("antialiasing", value: "off", inSection: "title-1a96545b", content: &text)
        upsertKey("resolution", value: resolution, inSection: "title-1a96545b", content: &text)

        var outData = Data([0xFF, 0xFE])
        if let encoded = text.data(using: .utf16LittleEndian) {
            outData.append(encoded)
        }
        try outData.write(to: iniURL, options: .atomic)
    }

    // MARK: - Subprocess Helper

    @discardableResult
    func runProcess(
        executable: String,
        args: [String],
        env: [String: String]? = nil,
        onLine: ((String) -> Void)? = nil
    ) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let env = env {
            process.environment = env
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var collected = ""
        let lock = NSLock()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            collected += chunk
            lock.unlock()
            let lines = chunk.components(separatedBy: CharacterSet.newlines)
            for l in lines where !l.trimmingCharacters(in: .whitespaces).isEmpty {
                onLine?(l)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return (-1, error.localizedDescription)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        return (process.terminationStatus, collected)
    }
}

// MARK: - Reusable UI Components

struct StatusPill: View {
    enum Style {
        case ready
        case installing
        case actionNeeded
        case neutral

        var color: Color {
            switch self {
            case .ready: return Theme.emerald
            case .installing: return Theme.cyan
            case .actionNeeded: return Theme.amber
            case .neutral: return Color.secondary
            }
        }
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundColor(style.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.color.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(style.color.opacity(0.30), lineWidth: 1)
            )
            .cornerRadius(5)
    }
}

struct MonoCard<Content: View, TrailingHeader: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let sectionIndex: String
    let sectionTitle: String
    let trailingHeader: TrailingHeader
    let content: Content

    init(
        sectionIndex: String,
        sectionTitle: String,
        @ViewBuilder trailingHeader: () -> TrailingHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.sectionIndex = sectionIndex
        self.sectionTitle = sectionTitle
        self.trailingHeader = trailingHeader()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(sectionIndex) / \(sectionTitle)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Spacer()
                trailingHeader
            }
            content
        }
        .padding(14)
        .background(Theme.cardBackground(for: colorScheme))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

struct EnvironmentRow: View {
    let label: String
    let value: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isReady ? Theme.emerald : Theme.amber)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(isReady ? .primary : Theme.amber)
                .lineLimit(1)
        }
    }
}

// MARK: - Main Launcher View (Fixed 720 x 520 pt)

struct LauncherMainView: View {
    @ObservedObject var vm: LauncherViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.windowBackground(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                headerView

                // Card 1 — System & Graphics Runtime
                card1Environment

                // Card 2 — Game Library Path
                card2GameFiles

                // Card 3 — Launch Configuration
                card3Configuration

                if vm.showLogsDrawer {
                    logsDrawerView
                }

                Spacer(minLength: 0)

                bottomActionBar
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 720, height: 520)
    }

    // MARK: 1. Top Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Forza Horizon 2")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.primary)

                    Text("macOS Apple Silicon · v1.0.0.64")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Theme.cyan.opacity(0.12))
                        .cornerRadius(5)
                }
            }

            Spacer()

            // Live Controller Status Badge
            HStack(spacing: 6) {
                Text(vm.controllerConnected ? "● Controller Connected" : "○ Keyboard Mode")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(vm.controllerConnected ? Theme.emerald : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (vm.controllerConnected ? Theme.emerald : Color.primary)
                    .opacity(0.07)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((vm.controllerConnected ? Theme.emerald : Color.primary).opacity(0.16), lineWidth: 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: 2. Card 1 — System & Graphics Runtime (`01 / ENVIRONMENT`)
    private var card1Environment: some View {
        MonoCard(
            sectionIndex: "01",
            sectionTitle: "ENVIRONMENT",
            trailingHeader: {
                if vm.isProvisioningRuntime {
                    StatusPill(text: "INSTALLING", style: .installing)
                } else if vm.envStatus.isFullyReady {
                    StatusPill(text: "READY", style: .ready)
                } else {
                    StatusPill(text: "ACTION NEEDED", style: .actionNeeded)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    EnvironmentRow(
                        label: "Rosetta 2 Translation",
                        value: vm.envStatus.rosettaInstalled ? "Installed" : "Missing",
                        isReady: vm.envStatus.rosettaInstalled
                    )
                    EnvironmentRow(
                        label: "DirectX 12 → Metal Engine",
                        value: vm.envStatus.runtimeKind.rawValue,
                        isReady: vm.envStatus.runtimeKind.isReady
                    )
                    EnvironmentRow(
                        label: "FH2 Compatibility Layer",
                        value: vm.bundledPayloadSummary,
                        isReady: true
                    )

                    if !vm.envStatus.isFullyReady || vm.isProvisioningRuntime {
                        Divider().padding(.vertical, 2)
                        if vm.isProvisioningRuntime {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(vm.provisioningStepText)
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.cyan)
                                    Spacer()
                                    Text(String(format: "%.0f%%", vm.provisioningProgress * 100))
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Theme.cyan)
                                }
                                ProgressView(value: vm.provisioningProgress, total: 1.0)
                                    .tint(Theme.cyan)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Text("Free Wine64 + Apple D3DMetal runtime is required to run DirectX 12 on Apple Silicon.")
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { vm.provisionFreeRuntime() }) {
                                    Text("Set Up Free Runtime")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Theme.cyan)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        )
    }

    // MARK: 3. Card 2 — Game Library Path (`02 / GAME FILES`)
    private var card2GameFiles: some View {
        MonoCard(
            sectionIndex: "02",
            sectionTitle: "GAME FILES",
            trailingHeader: {
                switch vm.folderValidation {
                case .verified(_, let isSymlink) where !isSymlink:
                    StatusPill(text: "[VERIFIED]", style: .ready)
                case .verified(_, _):
                    StatusPill(text: "[SYMLINK NOT SUPPORTED]", style: .actionNeeded)
                case .unconfigured, .invalid:
                    StatusPill(text: "[SELECT FOLDER]", style: .actionNeeded)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        HStack {
                            Text(vm.gameFolderPath.isEmpty ? "No Forza Horizon 2 folder selected..." : vm.gameFolderPath)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(vm.gameFolderPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.codeBoxBackground(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.cardBorder, lineWidth: 1)
                        )
                        .cornerRadius(6)

                        Button(action: { vm.selectGameFolder() }) {
                            Text("Browse…")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.cardBorder, lineWidth: 1)
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    if case .invalid(let reason) = vm.folderValidation {
                        Text(reason)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.amber)
                    } else if case .verified(_, true) = vm.folderValidation {
                        Text("Azimuth requires a real folder (or APFS clone via cp -c -R), not a symbolic link.")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.amber)
                    }
                }
            }
        )
    }

    // MARK: 4. Card 3 — Launch Configuration (`03 / CONFIGURATION`)
    private var card3Configuration: some View {
        MonoCard(
            sectionIndex: "03",
            sectionTitle: "CONFIGURATION",
            trailingHeader: {
                Text("ANTIALIASING=OFF · AVX=0")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            },
            content: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Text("Resolution")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85))
                            Picker("", selection: $vm.resolution) {
                                ForEach(ResolutionOption.allCases) { opt in
                                    Text(opt.label).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 245)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Text("Azimuth")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85))
                            Picker("", selection: $vm.azimuthBuild) {
                                ForEach(AzimuthBuildOption.allCases) { opt in
                                    Text(opt.label).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 175)
                            .disabled(!vm.isAzimuth101Available)
                        }
                    }

                    Divider().opacity(0.5)

                    HStack(spacing: 20) {
                        Toggle(isOn: $vm.enableExtraOptions) {
                            Text("Enable ExtraOptions (Unlock All DLC Cars & Skip Intro Videos)")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.cyan)

                        Spacer()

                        Toggle(isOn: $vm.showMetalHUD) {
                            Text("Show Metal FPS HUD (MTL_HUD_ENABLED)")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.cyan)
                    }
                }
            }
        )
    }

    // MARK: Collapsible Logs Drawer
    private var logsDrawerView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.logs.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(8)
            }
            .frame(height: 68)
            .background(Theme.codeBoxBackground(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .cornerRadius(6)
            .onChange(of: vm.logs.count) { _ in
                if !vm.logs.isEmpty {
                    proxy.scrollTo(vm.logs.count - 1, anchor: .bottom)
                }
            }
        }
    }

    // MARK: 5. Bottom Action Bar
    private var bottomActionBar: some View {
        let canLaunch = vm.envStatus.isFullyReady && vm.folderValidation.isVerified && !vm.isLaunchingGame && !vm.isProvisioningRuntime

        return HStack(alignment: .center, spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.showLogsDrawer.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Text(vm.showLogsDrawer ? "▾ Hide Logs" : "▸ View Logs")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: { vm.refreshEnvironment() }) {
                Text("Rescan")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if let err = vm.errorBannerText {
                Text(err)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.amber)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if !vm.launchStatusText.isEmpty {
                Text(vm.launchStatusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.cyan)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(action: { vm.launchGame() }) {
                HStack(spacing: 8) {
                    if vm.isLaunchingGame {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                    }
                    Text(vm.isLaunchingGame ? "Launching…" : "Launch Forza Horizon 2")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(canLaunch ? .black : .secondary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(canLaunch ? Theme.cyan : Color.primary.opacity(0.10))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)
        }
    }
}

// MARK: - Application Entry Point

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct FH2LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = LauncherViewModel()

    var body: some Scene {
        WindowGroup {
            LauncherMainView(vm: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
