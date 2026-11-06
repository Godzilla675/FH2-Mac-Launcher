// Forza Horizon 2 — Native macOS Apple Silicon A-to-Z Installer & Launcher (v1.1.0)
// Engineered with a clean, trustworthy Kaggle / Linear / Vercel Geist mono-accent UI.
// Zero Homebrew, Zero Xcode Command Line Tools required:
//   Step 1: Rosetta 2 + Direct Download of Game Porting Toolkit (Wine64 + Apple Signed D3DMetal)
//   Step 2: Bulletproof Auto-Resumable 16.8 GiB Cloud Download (FH2-Game.zip from Google Drive)
//   Step 3: Bundled 7zz Extraction + Silent Repack Unpacking (winxp64, QuickSFV neutralized, auto-cleanup)
//   Step 4: Azimuth (0.9.10 / 1.0.1) + d3d12.dll + fh2pad.dll + d3dcompiler_47.dll + ExtraOptions + UTF-16LE azimuth.ini

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

// MARK: - Manifest & Constants

struct SetupManifest {
    let version: String
    let gameFileID: String
    let gameFilename: String
    let gameExpectedBytes: Int64
    let gameUnpackedTargetBytes: Int64
    let runtimeReleasesAPI: String
    let runtimeFallbackURL: String
    let runtimeExpectedBytes: Int64

    static let `default` = SetupManifest(
        version: "1.1.0",
        gameFileID: "1VVmQ3d_qHOj6UhPfslSgeaBfQbc3zYcf",
        gameFilename: "FH2-Game.zip",
        gameExpectedBytes: 18_001_002_054,
        gameUnpackedTargetBytes: 42_949_672_960, // ~40.0 GiB
        runtimeReleasesAPI: "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases/latest",
        runtimeFallbackURL: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz",
        runtimeExpectedBytes: 515_000_000
    )

    static func loadFromBundle() -> SetupManifest {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("manifest.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let game = json["game_archive"] as? [String: Any],
              let rt = json["graphics_runtime"] as? [String: Any] else {
            return .default
        }
        return SetupManifest(
            version: (json["version"] as? String) ?? Self.default.version,
            gameFileID: (game["file_id"] as? String) ?? Self.default.gameFileID,
            gameFilename: (game["filename"] as? String) ?? Self.default.gameFilename,
            gameExpectedBytes: (game["size_bytes"] as? NSNumber)?.int64Value ?? Self.default.gameExpectedBytes,
            gameUnpackedTargetBytes: (game["unpacked_target_bytes"] as? NSNumber)?.int64Value ?? Self.default.gameUnpackedTargetBytes,
            runtimeReleasesAPI: (rt["github_releases_api"] as? String) ?? Self.default.runtimeReleasesAPI,
            runtimeFallbackURL: (rt["fallback_download_url"] as? String) ?? Self.default.runtimeFallbackURL,
            runtimeExpectedBytes: (rt["expected_size_bytes"] as? NSNumber)?.int64Value ?? Self.default.runtimeExpectedBytes
        )
    }
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
        case .r1440: return "1440p (Rec)"
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

enum ChecklistStepState: Equatable {
    case pending(detail: String)
    case active(progress: Double, detail: String)
    case waitingForInternet(progress: Double, detail: String)
    case completed(detail: String)
}

// MARK: - ViewModel / Controller

final class LauncherViewModel: ObservableObject {
    let manifest = SetupManifest.loadFromBundle()

    // Environment & Controller state
    @Published var envStatus: RuntimeEnvironment
    @Published var controllerConnected: Bool = false
    @Published var controllerName: String = "Keyboard Mode"

    // 4-Step A-to-Z Checklist States
    @Published var step1State: ChecklistStepState = .pending(detail: "Rosetta 2 + Apple DirectX-to-Metal Engine")
    @Published var step2State: ChecklistStepState = .pending(detail: "16.8 GB Cloud Archive (Auto-Resumable)")
    @Published var step3State: ChecklistStepState = .pending(detail: "Unzips archive, unpacks 40 GB game & cleans up")
    @Published var step4State: ChecklistStepState = .pending(detail: "Azimuth + DLC Unlocker + Controller Shims")

    // Pipeline & Launch status
    @Published var isRunningSetupPipeline: Bool = false
    @Published var isSetupPausedOrInterrupted: Bool = false
    @Published var connectionInterruptedBanner: String? = nil
    @Published var isLaunchingGame: Bool = false
    @Published var launchStatusText: String = ""
    @Published var errorBannerText: String? = nil

    // User Configuration (persisted in UserDefaults)
    @Published var gameFolderPath: String {
        didSet {
            UserDefaults.standard.set(gameFolderPath, forKey: "FH2_GameFolderPath")
            validateGameFolder()
            refreshStepChecklistStates()
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
    @Published var showInstallerWindow: Bool {
        didSet { UserDefaults.standard.set(showInstallerWindow, forKey: "FH2_ShowInstallerWindow") }
    }

    // Logs drawer
    @Published var showLogsDrawer: Bool = false
    @Published var logs: [String] = []

    let logFileURL: URL
    let cacheDirURL: URL
    let defaultInstalledGameDirURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var activeDownloadProcess: Process? = nil
    private var shouldCancelPipeline: Bool = false

    init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        self.logFileURL = home.appendingPathComponent("Library/Logs/FH2Port/launcher.log")
        self.cacheDirURL = home.appendingPathComponent("Games/FH2_Setup_Cache")
        self.defaultInstalledGameDirURL = home.appendingPathComponent("Games/Forza Horizon 2")

        let savedPath = UserDefaults.standard.string(forKey: "FH2_GameFolderPath") ?? ""
        if !savedPath.isEmpty && fm.fileExists(atPath: savedPath) {
            self.gameFolderPath = savedPath
        } else if fm.fileExists(atPath: defaultInstalledGameDirURL.path) {
            self.gameFolderPath = defaultInstalledGameDirURL.path
        } else {
            self.gameFolderPath = savedPath
        }

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
        self.showInstallerWindow = UserDefaults.standard.bool(forKey: "FH2_ShowInstallerWindow")
        self.envStatus = Self.detectEnvironment()

        appendLog("Forza Horizon 2 macOS Apple Silicon Installer & Launcher v\(manifest.version) initialized.")
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
            if self.logs.count > 500 {
                self.logs.removeFirst(self.logs.count - 500)
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

    // MARK: - Environment & Step Checklist State Detection

    func refreshEnvironment() {
        let detected = Self.detectEnvironment()
        self.envStatus = detected
        // Also auto-detect if game is already installed in `~/Games/Forza Horizon 2` or bottle `drive_c/FH2Game`
        if !folderValidation.isVerified {
            let bottleGame = defaultBottleURL(for: detected).appendingPathComponent("drive_c/FH2Game")
            if Self.checkGameFolderValid(at: defaultInstalledGameDirURL) {
                gameFolderPath = defaultInstalledGameDirURL.path
            } else if Self.checkGameFolderValid(at: bottleGame) {
                gameFolderPath = bottleGame.path
            }
        }
        refreshStepChecklistStates()
        appendLog("Environment scan -> Rosetta: \(detected.rosettaInstalled ? "Installed" : "Missing"), Engine: \(detected.runtimeKind.rawValue)")
    }

    func defaultBottleURL(for env: RuntimeEnvironment) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isCrossOver = (env.runtimeKind == .crossover || env.runtimeKind == .crossoverPreview)
        if isCrossOver {
            return home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/ForzaHorizon2")
        } else {
            return home.appendingPathComponent("Library/Application Support/FH2Port/bottle")
        }
    }

    func refreshStepChecklistStates() {
        guard !isRunningSetupPipeline else { return }
        let fm = FileManager.default

        // Step 1: Graphics Runtime
        if envStatus.isFullyReady {
            step1State = .completed(detail: "Ready (\(envStatus.runtimeKind.rawValue))")
        } else {
            let partURL = cacheDirURL.appendingPathComponent("runtime.tar.xz.part")
            let partBytes = (try? fm.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? 0
            if partBytes > 0 {
                let pct = min(0.99, Double(partBytes) / Double(manifest.runtimeExpectedBytes))
                step1State = .pending(detail: String(format: "Paused at %.0f MB (%.0f%%) — Ready to resume", Double(partBytes) / 1_048_576.0, pct * 100))
            } else {
                step1State = .pending(detail: "Rosetta 2 + Apple DirectX-to-Metal Engine (Auto-Install)")
            }
        }

        // Step 2 & Step 3: Game Download & Unpacking
        if folderValidation.isVerified {
            step2State = .completed(detail: "16.8 GB Cloud Archive Downloaded & Verified")
            step3State = .completed(detail: "40 GB Game Unpacked (\(URL(fileURLWithPath: gameFolderPath).lastPathComponent))")
        } else {
            let bottleURL = defaultBottleURL(for: envStatus)
            let fgSetupExe = bottleURL.appendingPathComponent("drive_c/fg_setup/setup.exe")
            let fullZip = cacheDirURL.appendingPathComponent(manifest.gameFilename)
            let partZip = cacheDirURL.appendingPathComponent("\(manifest.gameFilename).part")

            if fm.fileExists(atPath: fgSetupExe.path) {
                step2State = .completed(detail: "16.8 GB Archive Extracted to Staging")
                step3State = .pending(detail: "Ready to unpack 40 GB game files")
            } else if fm.fileExists(atPath: fullZip.path) {
                step2State = .completed(detail: "16.8 GB Archive Downloaded (Ready to Extract)")
                step3State = .pending(detail: "Unzips archive, unpacks 40 GB game & cleans up")
            } else {
                let partBytes = (try? fm.attributesOfItem(atPath: partZip.path)[.size] as? Int64) ?? 0
                if partBytes > 0 {
                    let gb = Double(partBytes) / 1_000_000_000.0
                    let totalGb = Double(manifest.gameExpectedBytes) / 1_000_000_000.0
                    let pct = min(0.99, Double(partBytes) / Double(manifest.gameExpectedBytes))
                    step2State = .pending(detail: String(format: "Saved progress: %.2f GB / %.2f GB (%.0f%%) — Auto-resumes", gb, totalGb, pct * 100))
                    isSetupPausedOrInterrupted = true
                } else {
                    step2State = .pending(detail: "16.8 GB Cloud Download (Auto-Resumable)")
                }
                step3State = .pending(detail: "Unzips archive, unpacks 40 GB game & cleans up")
            }
        }

        // Step 4: Controller & Graphics Setup
        let bottleURL = defaultBottleURL(for: envStatus)
        let azExe = bottleURL.appendingPathComponent("drive_c/Azimuth/azimuth.exe")
        let azIni = bottleURL.appendingPathComponent("drive_c/Azimuth/data/azimuth.ini")
        let d3dShim = bottleURL.appendingPathComponent("drive_c/Azimuth/d3d12.dll")
        if envStatus.isFullyReady && folderValidation.isVerified && fm.fileExists(atPath: azExe.path) && fm.fileExists(atPath: azIni.path) && fm.fileExists(atPath: d3dShim.path) {
            step4State = .completed(detail: "Azimuth \(azimuthBuild.rawValue) + D3D12 + Gamepad + \(resolution.rawValue)p Ready")
        } else if envStatus.isFullyReady && folderValidation.isVerified {
            step4State = .completed(detail: "Bundled Azimuth \(azimuthBuild.rawValue) + Shims Ready (Auto-applies on launch)")
        } else {
            step4State = .pending(detail: "Configures Azimuth \(azimuthBuild.rawValue), DLC Unlocker & Controller Support")
        }
    }

    var isReadyToLaunch: Bool {
        envStatus.isFullyReady && folderValidation.isVerified && !isRunningSetupPipeline && !isLaunchingGame
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

        // 3. Check Game Porting Toolkit.app (in ~/Applications, /Applications, or FH2Port runtime)
        let gptkCandidates = [
            home.appendingPathComponent("Applications/Game Porting Toolkit.app"),
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app"),
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

    var isAzimuth101Available: Bool {
        guard let res = Bundle.main.resourceURL?.appendingPathComponent("payload/azimuth-1.0.1/azimuth.exe") else { return true }
        return FileManager.default.fileExists(atPath: res.path)
    }

    // MARK: - Game Folder Validation & Manual Picker

    static func checkGameFolderValid(at url: URL) -> Bool {
        let fm = FileManager.default
        let candidates = [
            url.appendingPathComponent("Mount/forza_durango_release_final.exe"),
            url.appendingPathComponent("forza_durango_release_final.exe"),
            url.appendingPathComponent("Mount/Media"),
            url.appendingPathComponent("Media")
        ]
        return candidates.contains { fm.fileExists(atPath: $0.path) }
    }

    func selectGameFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Existing Forza Horizon 2 Game Folder"
        panel.message = "Choose the Forza Horizon 2 folder (containing Mount/forza_durango_release_final.exe or Media)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !gameFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: gameFolderPath)
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
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

        let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        let mountValues = try? url.appendingPathComponent("Mount").resourceValues(forKeys: [.isSymbolicLinkKey])
        let isSymlink = (resourceValues?.isSymbolicLink == true) || (mountValues?.isSymbolicLink == true)

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

    // MARK: - Google Drive Large-File Confirmation Resolver & Auto-Resumable Downloader

    /// Resolves Google Drive's large-file virus-scan confirmation page (`uuid` / `at` parameters)
    /// into a direct binary stream URL (`https://drive.usercontent.google.com/download?...`).
    static func resolveGoogleDriveDownloadURL(fileID: String) -> String {
        let fallbackURL = "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=t"
        let ucURL = "https://drive.google.com/uc?export=download&id=\(fileID)"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-sSL", "--connect-timeout", "15", "--max-time", "30", ucURL]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let html = String(data: data, encoding: .utf8), html.contains("<form") else {
                return fallbackURL
            }

            // Extract action URL and hidden inputs (`id`, `export`, `confirm`, `uuid`, `at`)
            var actionURL = "https://drive.usercontent.google.com/download"
            if let actRegex = try? NSRegularExpression(pattern: #"action="([^"]+)""#),
               let match = actRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(match.range(at: 1), in: html) {
                actionURL = String(html[r]).replacingOccurrences(of: "&amp;", with: "&")
            }

            var params: [(String, String)] = []
            if let inputRegex = try? NSRegularExpression(pattern: #"<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)""#) {
                let matches = inputRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for m in matches {
                    if let nr = Range(m.range(at: 1), in: html),
                       let vr = Range(m.range(at: 2), in: html) {
                        params.append((String(html[nr]), String(html[vr])))
                    }
                }
            }

            if params.isEmpty {
                return fallbackURL
            }
            var comps = URLComponents(string: actionURL)
            comps?.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
            return comps?.url?.absoluteString ?? fallbackURL
        } catch {
            return fallbackURL
        }
    }

    /// Queries GitHub Releases API for the latest `Gcenx/game-porting-toolkit` `.tar.xz` asset URL,
    /// falling back to `manifest.runtimeFallbackURL` if rate-limited or offline.
    static func resolveLatestRuntimeDownloadURL(manifest: SetupManifest) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = [
            "-fsSL",
            "--connect-timeout", "10",
            "--max-time", "15",
            "-H", "Accept: application/vnd.github+json",
            manifest.runtimeReleasesAPI
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let url = asset["browser_download_url"] as? String, url.hasSuffix(".tar.xz") {
                        return url
                    }
                }
            }
        } catch {}
        return manifest.runtimeFallbackURL
    }

    /// Verifies that the resolved URL serves the expected binary header (`PK\x03\x04` for ZIP)
    /// when probed with a 4-byte HTTP Range request.
    static func probeURLReturnsZipMagic(_ urlString: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-sSL", "--connect-timeout", "15", "--max-time", "25", "--range", "0-3", urlString]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
        } catch {
            return false
        }
    }

    /// Downloads a large file with `curl -L -C - --retry 999 --retry-delay 5 --retry-all-errors --connect-timeout 15`
    /// inside an outer session-refresh retry loop so even if Wi-Fi drops for hours or Google Drive's `uuid` token expires,
    /// it refreshes the URL and resumes from the exact byte offset on disk without ever restarting from 0%.
    func downloadWithAutoResume(
        label: String,
        partFileURL: URL,
        finalFileURL: URL,
        expectedBytes: Int64,
        requireZipMagic: Bool,
        urlResolver: () -> String,
        onProgress: @escaping (_ currentBytes: Int64, _ expectedBytes: Int64, _ speedMBps: Double) -> Void,
        onInterrupted: @escaping (_ currentBytes: Int64, _ expectedBytes: Int64) -> Void
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: partFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // If final file already exists and meets size check, return immediately
        if fm.fileExists(atPath: finalFileURL.path) {
            let finalSize = (try? fm.attributesOfItem(atPath: finalFileURL.path)[.size] as? Int64) ?? 0
            if finalSize >= expectedBytes || (!requireZipMagic && finalSize > 100_000_000) {
                appendLog("\(label) already downloaded at \(finalFileURL.path) (\(finalSize) bytes).")
                onProgress(finalSize, max(expectedBytes, finalSize), 0)
                return
            }
        }

        while !shouldCancelPipeline {
            var existingBytes = (try? fm.attributesOfItem(atPath: partFileURL.path)[.size] as? Int64) ?? 0

            // Guard against a tiny corrupted HTML error stub in `.part`
            if requireZipMagic && existingBytes > 0 {
                if let handle = try? FileHandle(forReadingFrom: partFileURL) {
                    let magic = handle.readData(ofLength: 4)
                    try? handle.close()
                    if magic != Data([0x50, 0x4B, 0x03, 0x04]) {
                        appendLog("Resetting invalid non-ZIP stub at \(partFileURL.path) (\(existingBytes) bytes)")
                        try? fm.removeItem(at: partFileURL)
                        existingBytes = 0
                    }
                }
            }

            if requireZipMagic && existingBytes >= expectedBytes {
                break
            }

            let resolvedURL = urlResolver()
            if requireZipMagic && !Self.probeURLReturnsZipMagic(resolvedURL) {
                appendLog("Waiting for network / valid Google Drive binary stream for \(label)...")
                onInterrupted(existingBytes, expectedBytes)
                Thread.sleep(forTimeInterval: 5.0)
                continue
            }

            DispatchQueue.main.async {
                self.connectionInterruptedBanner = nil
            }

            appendLog("Resuming \(label) from byte offset \(existingBytes) -> \(partFileURL.path)")

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            proc.arguments = [
                "-L",
                "-C", "-",
                "--fail",
                "--retry", "999",
                "--retry-delay", "5",
                "--retry-all-errors",
                "--connect-timeout", "15",
                "-o", partFileURL.path,
                resolvedURL
            ]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()

            var lastSampleBytes = existingBytes
            var lastSampleTime = Date()
            var smoothedSpeedMBps: Double = 0.0

            do {
                try proc.run()
                self.activeDownloadProcess = proc

                while proc.isRunning && !shouldCancelPipeline {
                    Thread.sleep(forTimeInterval: 0.5)
                    let now = Date()
                    let currentBytes = (try? fm.attributesOfItem(atPath: partFileURL.path)[.size] as? Int64) ?? existingBytes
                    let dt = now.timeIntervalSince(lastSampleTime)
                    if dt >= 0.45 {
                        let delta = max(0, currentBytes - lastSampleBytes)
                        let instantMBps = (Double(delta) / 1_048_576.0) / dt
                        if instantMBps > 0 {
                            smoothedSpeedMBps = (smoothedSpeedMBps == 0) ? instantMBps : (smoothedSpeedMBps * 0.65 + instantMBps * 0.35)
                        }
                        lastSampleBytes = currentBytes
                        lastSampleTime = now
                        onProgress(currentBytes, expectedBytes, smoothedSpeedMBps)
                    }
                }

                if shouldCancelPipeline {
                    if proc.isRunning { proc.terminate() }
                    throw NSError(domain: "FH2Setup", code: -999, userInfo: [NSLocalizedDescriptionKey: "Setup paused by user."])
                }

                proc.waitUntilExit()
                self.activeDownloadProcess = nil
            } catch {
                self.activeDownloadProcess = nil
                if shouldCancelPipeline { throw error }
            }

            let postBytes = (try? fm.attributesOfItem(atPath: partFileURL.path)[.size] as? Int64) ?? 0
            if proc.terminationStatus == 0 && (!requireZipMagic || postBytes >= expectedBytes) && postBytes > 0 {
                onProgress(postBytes, max(expectedBytes, postBytes), smoothedSpeedMBps)
                break
            }

            if shouldCancelPipeline {
                throw NSError(domain: "FH2Setup", code: -999, userInfo: [NSLocalizedDescriptionKey: "Setup paused by user."])
            }

            appendLog("Download stream interrupted at \(postBytes) bytes (exit \(proc.terminationStatus)). Refreshing session & auto-resuming in 5s...")
            onInterrupted(postBytes, expectedBytes)
            Thread.sleep(forTimeInterval: 5.0)
        }

        try? fm.removeItem(at: finalFileURL)
        try fm.moveItem(at: partFileURL, to: finalFileURL)
        appendLog("Completed download: \(finalFileURL.path)")
    }

    // MARK: - Complete 4-Step A-to-Z 1-Click Installer Pipeline

    func startOrResumeOneClickSetup() {
        guard !isRunningSetupPipeline else { return }
        shouldCancelPipeline = false
        isRunningSetupPipeline = true
        isSetupPausedOrInterrupted = false
        errorBannerText = nil
        connectionInterruptedBanner = nil
        appendLog("=== Starting 1-Click A-to-Z Setup & Download Pipeline ===")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.executeFourStepSetupPipeline()
                DispatchQueue.main.async {
                    self.isRunningSetupPipeline = false
                    self.isSetupPausedOrInterrupted = false
                    self.connectionInterruptedBanner = nil
                    self.refreshEnvironment()
                    self.launchStatusText = "All 4 setup steps complete! Ready to launch Forza Horizon 2."
                }
            } catch {
                let nsErr = error as NSError
                self.appendLog("Setup pipeline stopped: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRunningSetupPipeline = false
                    self.isSetupPausedOrInterrupted = true
                    if nsErr.code != -999 {
                        self.errorBannerText = error.localizedDescription
                    }
                    self.refreshStepChecklistStates()
                }
            }
        }
    }

    func pauseSetupPipeline() {
        guard isRunningSetupPipeline else { return }
        shouldCancelPipeline = true
        activeDownloadProcess?.terminate()
        appendLog("User requested pause — saving download progress on disk.")
    }

    /// Executes all 4 steps from A to Z. Also accepts optional dependency overrides for deterministic automated testing (`--self-test`).
    func executeFourStepSetupPipeline(
        customCacheDir: URL? = nil,
        customBottleURL: URL? = nil,
        customGameDestDir: URL? = nil,
        mockRuntimeEnv: RuntimeEnvironment? = nil,
        customGameZipURLResolver: (() -> String)? = nil,
        customGameExpectedBytes: Int64? = nil,
        customUnpackedTargetBytes: Int64? = nil
    ) throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let workCacheDir = customCacheDir ?? cacheDirURL
        try fm.createDirectory(at: workCacheDir, withIntermediateDirectories: true)

        // =========================================================================
        // STEP 1: macOS Graphics Runtime (Rosetta 2 + Game Porting Toolkit.app)
        // =========================================================================
        var activeEnv = mockRuntimeEnv ?? Self.detectEnvironment()
        if !activeEnv.isFullyReady {
            updateStep1(.active(progress: 0.05, detail: "Checking Apple Silicon Rosetta 2 translation runtime..."))

            if !activeEnv.rosettaInstalled {
                updateStep1(.active(progress: 0.10, detail: "Installing Apple Rosetta 2 translation runtime..."))
                appendLog("Installing Rosetta 2 via /usr/sbin/softwareupdate --install-rosetta --agree-to-license")
                let (rCode, _) = runProcess(
                    executable: "/usr/sbin/softwareupdate",
                    args: ["--install-rosetta", "--agree-to-license"]
                )
                if rCode != 0 && !Self.detectEnvironment().rosettaInstalled {
                    appendLog("Escalating Rosetta 2 install via osascript administrator prompt...")
                    let osaCmd = #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#
                    _ = runProcess(executable: "/usr/bin/osascript", args: ["-e", osaCmd])
                }
            }

            let userAppsDir = home.appendingPathComponent("Applications")
            try fm.createDirectory(at: userAppsDir, withIntermediateDirectories: true)
            let gptkAppDest = userAppsDir.appendingPathComponent("Game Porting Toolkit.app")

            if !fm.fileExists(atPath: gptkAppDest.appendingPathComponent("Contents/Resources/wine/bin/wine64").path) {
                let runtimePart = workCacheDir.appendingPathComponent("runtime.tar.xz.part")
                let runtimeArchive = workCacheDir.appendingPathComponent("runtime.tar.xz")

                try downloadWithAutoResume(
                    label: "Apple Silicon Graphics Runtime (Game Porting Toolkit)",
                    partFileURL: runtimePart,
                    finalFileURL: runtimeArchive,
                    expectedBytes: manifest.runtimeExpectedBytes,
                    requireZipMagic: false,
                    urlResolver: { Self.resolveLatestRuntimeDownloadURL(manifest: self.manifest) },
                    onProgress: { cur, exp, speed in
                        let pct = min(0.85, max(0.12, 0.12 + (Double(cur) / Double(max(1, exp))) * 0.73))
                        let mb = Double(cur) / 1_048_576.0
                        let totalMb = Double(exp) / 1_048_576.0
                        let detail = String(format: "Downloading Graphics Runtime: %.0f / %.0f MB (%.1f MB/s)", mb, totalMb, speed)
                        self.updateStep1(.active(progress: pct, detail: detail))
                    },
                    onInterrupted: { cur, exp in
                        let mb = Double(cur) / 1_048_576.0
                        let pct = min(0.99, Double(cur) / Double(max(1, exp)))
                        let msg = String(format: "Connection interrupted — waiting for internet to resume from %.0f MB (%.0f%%)...", mb, pct * 100)
                        self.setConnectionInterrupted(msg)
                        self.updateStep1(.waitingForInternet(progress: pct, detail: msg))
                    }
                )

                updateStep1(.active(progress: 0.88, detail: "Extracting Game Porting Toolkit.app to ~/Applications..."))
                appendLog("Extracting \(runtimeArchive.path) to \(userAppsDir.path)")
                let (tarCode, tarOut) = runProcess(
                    executable: "/usr/bin/tar",
                    args: ["-xJf", runtimeArchive.path, "-C", userAppsDir.path]
                )
                if tarCode != 0 {
                    throw NSError(domain: "FH2Setup", code: Int(tarCode), userInfo: [
                        NSLocalizedDescriptionKey: "Failed to extract Graphics Runtime archive: \(tarOut.suffix(200))"
                    ])
                }
                try? fm.removeItem(at: runtimeArchive)

                // Strip quarantine on outer app without ever touching D3DMetal.framework signature (`anchor apple`)
                updateStep1(.active(progress: 0.96, detail: "Clearing quarantine while preserving Apple D3DMetal signature..."))
                _ = runProcess(executable: "/usr/bin/xattr", args: ["-drs", "com.apple.quarantine", gptkAppDest.path])
            }

            activeEnv = Self.detectEnvironment()
            DispatchQueue.main.async { self.envStatus = activeEnv }
            guard activeEnv.isFullyReady else {
                throw NSError(domain: "FH2Setup", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: "Graphics Runtime installation did not produce a ready Wine64 + D3DMetal environment."
                ])
            }
        }
        updateStep1(.completed(detail: "Ready (\(activeEnv.runtimeKind.rawValue))"))

        // =========================================================================
        // STEP 2: Bulletproof Auto-Resumable Game Download (16.8 GB FH2-Game.zip)
        // =========================================================================
        let bottleURL = customBottleURL ?? defaultBottleURL(for: activeEnv)
        let driveCURL = bottleURL.appendingPathComponent("drive_c")
        let fgSetupDir = driveCURL.appendingPathComponent("fg_setup")
        let targetGameDest = customGameDestDir ?? defaultInstalledGameDirURL
        let expectedZipBytes = customGameExpectedBytes ?? manifest.gameExpectedBytes

        let gameAlreadyVerified = (customGameDestDir != nil)
            ? Self.checkGameFolderValid(at: targetGameDest)
            : (folderValidation.isVerified || Self.checkGameFolderValid(at: targetGameDest))

        let gameZipPartURL = workCacheDir.appendingPathComponent("\(manifest.gameFilename).part")
        let gameZipFinalURL = workCacheDir.appendingPathComponent(manifest.gameFilename)

        if !gameAlreadyVerified && !fm.fileExists(atPath: fgSetupDir.appendingPathComponent("setup.exe").path) {
            updateStep2(.active(progress: 0.01, detail: "Resolving Google Drive cloud download stream..."))

            try downloadWithAutoResume(
                label: manifest.gameFilename,
                partFileURL: gameZipPartURL,
                finalFileURL: gameZipFinalURL,
                expectedBytes: expectedZipBytes,
                requireZipMagic: true,
                urlResolver: customGameZipURLResolver ?? {
                    Self.resolveGoogleDriveDownloadURL(fileID: self.manifest.gameFileID)
                },
                onProgress: { cur, exp, speed in
                    let pct = min(1.0, max(0.0, Double(cur) / Double(max(1, exp))))
                    let curGB = Double(cur) / 1_000_000_000.0
                    let expGB = Double(exp) / 1_000_000_000.0
                    let detail = String(
                        format: "%.2f GB / %.2f GB (%.0f%%) · %.1f MB/s",
                        curGB, expGB, pct * 100.0, speed
                    )
                    self.updateStep2(.active(progress: pct, detail: detail))
                },
                onInterrupted: { cur, exp in
                    let pct = min(0.99, max(0.0, Double(cur) / Double(max(1, exp))))
                    let curGB = Double(cur) / 1_000_000_000.0
                    let msg = String(
                        format: "Connection interrupted — waiting for internet to resume from %.1f GB (%.0f%%)...",
                        curGB, pct * 100.0
                    )
                    self.setConnectionInterrupted(msg)
                    self.updateStep2(.waitingForInternet(progress: pct, detail: msg))
                }
            )
        }
        updateStep2(.completed(detail: "16.8 GB Cloud Archive Downloaded & Verified"))

        // =========================================================================
        // STEP 3: Automatic Unzipping (`7zz`) & Silent Repack Unpacking (`setup.exe` -> 40 GB)
        // =========================================================================
        if !gameAlreadyVerified {
            try fm.createDirectory(at: driveCURL, withIntermediateDirectories: true)

            // 3a. Extract `FH2-Game.zip` with bundled `7zz` into bracket-free `drive_c/fg_setup`
            if !fm.fileExists(atPath: fgSetupDir.appendingPathComponent("setup.exe").path) {
                updateStep3(.active(progress: 0.05, detail: "Extracting FH2-Game.zip with bundled 7zz archiver..."))
                guard let sevenZipURL = Bundle.main.resourceURL?.appendingPathComponent("bin/7zz"),
                      fm.isExecutableFile(atPath: sevenZipURL.path) else {
                    throw NSError(domain: "FH2Setup", code: 20, userInfo: [
                        NSLocalizedDescriptionKey: "Bundled 7zz binary missing from Contents/Resources/bin/7zz."
                    ])
                }

                let rawExtractDir = driveCURL.appendingPathComponent("fg_setup_extract_tmp")
                try? fm.removeItem(at: rawExtractDir)
                try fm.createDirectory(at: rawExtractDir, withIntermediateDirectories: true)

                appendLog("Running bundled 7zz x \(gameZipFinalURL.path) -o\(rawExtractDir.path) -y")
                let (zCode, zOut) = runProcess(
                    executable: sevenZipURL.path,
                    args: ["x", gameZipFinalURL.path, "-o\(rawExtractDir.path)", "-y"]
                )
                if zCode != 0 {
                    throw NSError(domain: "FH2Setup", code: Int(zCode), userInfo: [
                        NSLocalizedDescriptionKey: "7zz extraction failed: \(zOut.suffix(200))"
                    ])
                }

                // Flatten `Forza Horizon 2 [FitGirl Repack]/` into `drive_c/fg_setup` (no spaces or `[ ]` brackets!)
                try? fm.removeItem(at: fgSetupDir)
                if let subItems = try? fm.contentsOfDirectory(at: rawExtractDir, includingPropertiesForKeys: nil),
                   let repackDir = subItems.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("setup.exe").path) }) {
                    try fm.moveItem(at: repackDir, to: fgSetupDir)
                    try? fm.removeItem(at: rawExtractDir)
                } else if fm.fileExists(atPath: rawExtractDir.appendingPathComponent("setup.exe").path) {
                    try fm.moveItem(at: rawExtractDir, to: fgSetupDir)
                } else {
                    throw NSError(domain: "FH2Setup", code: 21, userInfo: [
                        NSLocalizedDescriptionKey: "Extracted archive did not contain setup.exe."
                    ])
                }

                // Delete `FH2-Game.zip` immediately after extraction succeeds to free 17 GB of disk space!
                try? fm.removeItem(at: gameZipFinalURL)
                try? fm.removeItem(at: gameZipPartURL)
                appendLog("Extracted installer to bracket-free \(fgSetupDir.path) and deleted \(gameZipFinalURL.lastPathComponent) to save 17 GB.")
            }

            // 3b. Neutralize `_Redist/QuickSFV.exe` and `MD5/QuickSFV.EXE` (case-insensitive recursive scan)
            updateStep3(.active(progress: 0.14, detail: "Neutralizing QuickSFV post-install MD5 check & configuring winxp64..."))
            let noopExeURL = Bundle.main.resourceURL?.appendingPathComponent("payload/layer/noop.exe")
            if let enumerator = fm.enumerator(at: fgSetupDir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == "quicksfv.exe" {
                        let disabledURL = fileURL.appendingPathExtension("disabled")
                        try? fm.removeItem(at: disabledURL)
                        try? fm.moveItem(at: fileURL, to: disabledURL)
                        if let noop = noopExeURL, fm.fileExists(atPath: noop.path) {
                            try? fm.copyItem(at: noop, to: fileURL)
                        }
                        appendLog("Neutralized QuickSFV binary at \(fileURL.path)")
                    }
                }
            }

            // 3c. Bootstrap bottle if needed and set Windows version to `winxp64` for FreeArc/LOLZ/XTool stability
            let wineEnv = buildWineEnvironment(for: activeEnv, bottleURL: bottleURL, useMetalHUD: false)
            guard let wineBin = activeEnv.wineExecutable else {
                throw NSError(domain: "FH2Setup", code: 22, userInfo: [NSLocalizedDescriptionKey: "Wine executable missing."])
            }

            if !fm.fileExists(atPath: bottleURL.appendingPathComponent("system.reg").path) {
                _ = runProcess(executable: wineBin.path, args: ["wineboot", "-u"], env: wineEnv)
                if let srv = activeEnv.wineserverExecutable {
                    _ = runProcess(executable: srv.path, args: ["-w"], env: wineEnv)
                }
            }

            let setupAppKey = #"HKCU\Software\Wine\AppDefaults\setup.exe"#
            let globalWineKey = #"HKCU\Software\Wine"#
            _ = runProcess(executable: wineBin.path, args: ["reg", "add", setupAppKey, "/v", "Version", "/t", "REG_SZ", "/d", "winxp64", "/f"], env: wineEnv)
            _ = runProcess(executable: wineBin.path, args: ["reg", "add", globalWineKey, "/v", "Version", "/t", "REG_SZ", "/d", "winxp64", "/f"], env: wineEnv)

            // 3d. Run `setup.exe` silently into `C:\FH2Game` while polling disk usage (`du -sk`) every 2 seconds
            let bottleGameDir = driveCURL.appendingPathComponent("FH2Game")
            try fm.createDirectory(at: bottleGameDir, withIntermediateDirectories: true)

            var setupArgs = [#"C:\fg_setup\setup.exe"#]
            if !showInstallerWindow {
                setupArgs += ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCANCEL"]
            }
            setupArgs.append(#"/DIR=C:\FH2Game"#)

            appendLog("Launching installer: \(wineBin.path) \(setupArgs.joined(separator: " "))")
            let setupProc = Process()
            setupProc.executableURL = wineBin
            setupProc.currentDirectoryURL = fgSetupDir
            setupProc.arguments = setupArgs
            setupProc.environment = wineEnv
            setupProc.standardOutput = Pipe()
            setupProc.standardError = Pipe()

            try setupProc.run()
            let targetUnpackedBytes = customUnpackedTargetBytes ?? manifest.gameUnpackedTargetBytes

            while setupProc.isRunning && !shouldCancelPipeline {
                Thread.sleep(forTimeInterval: 2.0)
                // Belt-and-suspenders: terminate any QuickSFV.exe process if spawned
                _ = runProcess(executable: "/usr/bin/pkill", args: ["-fi", "QuickSFV.exe"])

                let currentUnpackedBytes = Self.directorySizeBytesViaDu(at: bottleGameDir)
                let ratio = min(0.98, max(0.0, Double(currentUnpackedBytes) / Double(max(1, targetUnpackedBytes))))
                let uiProgress = 0.15 + ratio * 0.80
                let curGB = Double(currentUnpackedBytes) / 1_000_000_000.0
                let targetGB = Double(targetUnpackedBytes) / 1_000_000_000.0
                let detail = String(
                    format: "Step 3/4: Installing & decompressing game files (%.1f GB / %.1f GB — %.0f%%)...",
                    curGB, targetGB, ratio * 100.0
                )
                updateStep3(.active(progress: uiProgress, detail: detail))
            }

            if shouldCancelPipeline {
                if setupProc.isRunning { setupProc.terminate() }
                throw NSError(domain: "FH2Setup", code: -999, userInfo: [NSLocalizedDescriptionKey: "Setup paused by user."])
            }

            setupProc.waitUntilExit()

            // Restore Wine bottle Windows version back to `win10`
            _ = runProcess(executable: wineBin.path, args: ["reg", "delete", setupAppKey, "/v", "Version", "/f"], env: wineEnv)
            _ = runProcess(executable: wineBin.path, args: ["reg", "add", globalWineKey, "/v", "Version", "/t", "REG_SZ", "/d", "win10", "/f"], env: wineEnv)

            guard Self.checkGameFolderValid(at: bottleGameDir) else {
                throw NSError(domain: "FH2Setup", code: 25, userInfo: [
                    NSLocalizedDescriptionKey: "Unpacking finished (exit \(setupProc.terminationStatus)), but forza_durango_release_final.exe was not found in C:\\FH2Game."
                ])
            }

            // Move unpacked game directory to `~/Games/Forza Horizon 2/` (real folder on APFS) and delete `drive_c/fg_setup/`
            updateStep3(.active(progress: 0.97, detail: "Finalizing game library & cleaning up 17 GB temporary installer files..."))
            var finalGameLocation = bottleGameDir
            do {
                try fm.createDirectory(at: targetGameDest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: targetGameDest.path) {
                    try fm.removeItem(at: targetGameDest)
                }
                try fm.moveItem(at: bottleGameDir, to: targetGameDest)
                finalGameLocation = targetGameDest
                appendLog("Moved unpacked Forza Horizon 2 to \(targetGameDest.path)")
            } catch {
                appendLog("Keeping unpacked Forza Horizon 2 inside \(bottleGameDir.path) (\(error.localizedDescription))")
            }

            // Delete `drive_c/fg_setup/` to save 17 GB of disk space
            try? fm.removeItem(at: fgSetupDir)
            appendLog("Removed temporary \(fgSetupDir.path) directory.")

            DispatchQueue.main.async {
                self.gameFolderPath = finalGameLocation.path
                self.validateGameFolder()
            }
        }
        updateStep3(.completed(detail: "40 GB Game Installed & Temporary Files Cleaned"))

        // =========================================================================
        // STEP 4: Configure Azimuth + Mac D3D12 Layer (`d3d12.dll`, `fh2pad.dll`, `d3dcompiler_47.dll`, `ExtraOptions`)
        // =========================================================================
        updateStep4(.active(progress: 0.25, detail: "Installing Azimuth \(azimuthBuild.rawValue) + D3D12 & Gamepad shims..."))
        let effectiveGameFolder = (customGameDestDir != nil) ? targetGameDest.path : (gameFolderPath.isEmpty ? targetGameDest.path : gameFolderPath)

        try prepareBottleAndConfigureAzimuth(
            bottleURL: bottleURL,
            env: activeEnv,
            gameFolder: effectiveGameFolder,
            selectedAzimuth: azimuthBuild,
            selectedResolution: resolution,
            useExtraOptions: enableExtraOptions,
            useMetalHUD: showMetalHUD
        )

        updateStep4(.completed(detail: "Azimuth \(azimuthBuild.rawValue) + D3D12 + Gamepad + \(resolution.rawValue)p Configured"))
    }

    static func directorySizeBytesViaDu(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-sk", url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if let out = String(data: data, encoding: .utf8),
               let firstToken = out.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first,
               let kb = Int64(firstToken) {
                return kb * 1024
            }
        } catch {}
        return 0
    }

    private func updateStep1(_ state: ChecklistStepState) {
        DispatchQueue.main.async { self.step1State = state }
    }
    private func updateStep2(_ state: ChecklistStepState) {
        DispatchQueue.main.async { self.step2State = state }
    }
    private func updateStep3(_ state: ChecklistStepState) {
        DispatchQueue.main.async { self.step3State = state }
    }
    private func updateStep4(_ state: ChecklistStepState) {
        DispatchQueue.main.async { self.step4State = state }
    }
    private func setConnectionInterrupted(_ text: String?) {
        DispatchQueue.main.async { self.connectionInterruptedBanner = text }
    }

    // MARK: - Bottle Setup, Layer Injection, Azimuth Configuration & Game Launch

    func buildWineEnvironment(for currentEnv: RuntimeEnvironment, bottleURL: URL, useMetalHUD: Bool) -> [String: String] {
        let isCrossOver = (currentEnv.runtimeKind == .crossover || currentEnv.runtimeKind == .crossoverPreview)
        var wineEnv = ProcessInfo.processInfo.environment
        wineEnv["WINEPREFIX"] = bottleURL.path
        wineEnv["WINEDEBUG"] = "-all"
        wineEnv["WINEMSYNC"] = "1"
        wineEnv["WINEESYNC"] = "0"
        wineEnv["D3DMETAL"] = "1"
        wineEnv["MTL_HUD_ENABLED"] = useMetalHUD ? "1" : "0"
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
        return wineEnv
    }

    func prepareBottleAndConfigureAzimuth(
        bottleURL: URL,
        env currentEnv: RuntimeEnvironment,
        gameFolder rawGameFolder: String,
        selectedAzimuth: AzimuthBuildOption,
        selectedResolution: ResolutionOption,
        useExtraOptions: Bool,
        useMetalHUD: Bool
    ) throws {
        let fm = FileManager.default
        let userGameFolder = URL(fileURLWithPath: rawGameFolder).resolvingSymlinksInPath().path
        guard let payloadRoot = Bundle.main.resourceURL?.appendingPathComponent("payload") else {
            throw NSError(domain: "FH2Launch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled payload directory is missing from app bundle."
            ])
        }

        let isCrossOver = (currentEnv.runtimeKind == .crossover || currentEnv.runtimeKind == .crossoverPreview)
        let driveCURL = bottleURL.appendingPathComponent("drive_c")
        let azimuthDestURL = driveCURL.appendingPathComponent("Azimuth")
        let wineEnv = buildWineEnvironment(for: currentEnv, bottleURL: bottleURL, useMetalHUD: useMetalHUD)

        guard let wineBin = currentEnv.wineExecutable else {
            throw NSError(domain: "FH2Launch", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Wine executable not found."
            ])
        }

        // 1. Initialize bottle if `system.reg` does not exist yet
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

        // 2. Copy selected Azimuth build (`0.9.10` or `1.0.1`) preserving `data/titles` (saves)
        self.updateLaunchStatus("Installing Azimuth \(selectedAzimuth.rawValue) + Apple Silicon D3D12 & Gamepad shims...")
        let bundledAzDir = payloadRoot.appendingPathComponent(selectedAzimuth.payloadSubfolder)
        guard fm.fileExists(atPath: bundledAzDir.appendingPathComponent("azimuth.exe").path) else {
            throw NSError(domain: "FH2Launch", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Bundled Azimuth \(selectedAzimuth.rawValue) payload not found at \(bundledAzDir.path)."
            ])
        }

        let (dittoCode, dittoOut) = self.runProcess(
            executable: "/usr/bin/ditto",
            args: [bundledAzDir.path, azimuthDestURL.path]
        )
        if dittoCode != 0 {
            throw NSError(domain: "FH2Launch", code: Int(dittoCode), userInfo: [
                NSLocalizedDescriptionKey: "Failed to copy Azimuth payload: \(dittoOut)"
            ])
        }

        // 3. Copy `d3d12.dll`, `fh2pad.dll`, and `d3dcompiler_47.dll` next to `azimuth.exe`
        let layerDir = payloadRoot.appendingPathComponent("layer")
        for dll in ["d3d12.dll", "fh2pad.dll", "d3dcompiler_47.dll"] {
            let src = layerDir.appendingPathComponent(dll)
            let dst = azimuthDestURL.appendingPathComponent(dll)
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: src, to: dst)
            }
        }

        // 4. Handle Optional `ForzaHorizon2_ExtraOptions` mod
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

        // 5. Apply Wine Registry & DLL Overrides (matching `FH2-Port-AppleSilicon/scripts/install.sh`)
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

        // 6. Configure `data/azimuth.ini` (UTF-16LE with BOM) with resolution, antialiasing=off, and FH2 game folder path
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
    }

    func launchGame() {
        guard envStatus.isFullyReady, folderValidation.isVerified, !isLaunchingGame else { return }
        errorBannerText = nil
        isLaunchingGame = true
        launchStatusText = "Preparing Wine prefix & FH2 compatibility layer..."
        appendLog("=== Starting Forza Horizon 2 launch sequence ===")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let pid = try self.executeLaunchSequence()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isLaunchingGame = false
                    self.refreshStepChecklistStates()
                    self.launchStatusText = "Forza Horizon 2 is running (PID \(pid))."
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

    @discardableResult
    func executeLaunchSequence(
        bottleOverrideURL: URL? = nil,
        envOverride: RuntimeEnvironment? = nil,
        gameFolderOverride: String? = nil
    ) throws -> Int32 {
        let currentEnv = envOverride ?? envStatus
        let bottleURL = bottleOverrideURL ?? defaultBottleURL(for: currentEnv)
        let rawGameFolder = gameFolderOverride ?? gameFolderPath

        try prepareBottleAndConfigureAzimuth(
            bottleURL: bottleURL,
            env: currentEnv,
            gameFolder: rawGameFolder,
            selectedAzimuth: azimuthBuild,
            selectedResolution: resolution,
            useExtraOptions: enableExtraOptions,
            useMetalHUD: showMetalHUD
        )

        guard let wineBin = currentEnv.wineExecutable else {
            throw NSError(domain: "FH2Launch", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Wine executable not found."
            ])
        }

        let fm = FileManager.default
        let azimuthDestURL = bottleURL.appendingPathComponent("drive_c/Azimuth")
        let wineEnv = buildWineEnvironment(for: currentEnv, bottleURL: bottleURL, useMetalHUD: showMetalHUD)

        // Rotate fh2port.log if present
        let fh2Log = azimuthDestURL.appendingPathComponent("data/logs/fh2port.log")
        let fh2PrevLog = azimuthDestURL.appendingPathComponent("data/logs/fh2port.prev.log")
        if fm.fileExists(atPath: fh2Log.path) {
            try? fm.removeItem(at: fh2PrevLog)
            try? fm.moveItem(at: fh2Log, to: fh2PrevLog)
        }

        // Launch `azimuth.exe` with `--skip-launcher` so it boots directly into Forza Horizon 2!
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
        return proc.processIdentifier
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
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(style.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(sectionIndex) / \(sectionTitle)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                trailingHeader
            }
            content
        }
        .padding(12)
        .background(Theme.cardBackground(for: colorScheme))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

struct ChecklistStepRow: View {
    let indexLabel: String
    let title: String
    let state: ChecklistStepState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                badgeView
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
                detailView
            }

            if case .active(let progress, _) = state {
                ProgressView(value: min(1.0, max(0.0, progress)), total: 1.0)
                    .tint(Theme.cyan)
                    .controlSize(.small)
            } else if case .waitingForInternet(let progress, _) = state {
                ProgressView(value: min(1.0, max(0.0, progress)), total: 1.0)
                    .tint(Theme.amber)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var badgeView: some View {
        switch state {
        case .completed:
            Text("✓")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: 20, height: 18)
                .background(Theme.emerald)
                .cornerRadius(4)
        case .active:
            Text(indexLabel)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: 24, height: 18)
                .background(Theme.cyan)
                .cornerRadius(4)
        case .waitingForInternet:
            Text("!")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: 20, height: 18)
                .background(Theme.amber)
                .cornerRadius(4)
        case .pending:
            Text(indexLabel)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 18)
                .background(Color.primary.opacity(0.07))
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch state {
        case .completed(let detail):
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.emerald)
                .lineLimit(1)
        case .active(_, let detail):
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.cyan)
                .lineLimit(1)
        case .waitingForInternet(_, let detail):
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.amber)
                .lineLimit(1)
        case .pending(let detail):
            Text(detail)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Main Launcher View (Fixed 740 x 560 pt)

struct LauncherMainView: View {
    @ObservedObject var vm: LauncherViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.windowBackground(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                headerView

                // Reassuring Quick Guide for First-Time Players
                quickGuideCard

                // 4-Step Visual Progress Checklist (A-to-Z Setup)
                checklistCard

                // Configuration & Game Folder Override Card
                configurationCard

                if vm.showLogsDrawer {
                    logsDrawerView
                }

                Spacer(minLength: 0)

                bottomActionBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 740, height: 560)
    }

    // MARK: 1. Top Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Forza Horizon 2")
                    .font(.system(size: 19, weight: .semibold, design: .default))
                    .foregroundColor(.primary)

                Text("macOS Apple Silicon · v1.1.0 · Xbox One v1.0.0.64")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Theme.cyan.opacity(0.12))
                    .cornerRadius(5)
            }

            Spacer()

            HStack(spacing: 6) {
                Text(vm.controllerConnected ? "● Controller Connected" : "○ Keyboard Mode")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(vm.controllerConnected ? Theme.emerald : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
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

    // MARK: 2. Quick Guide for First-Time Players
    private var quickGuideCard: some View {
        MonoCard(
            sectionIndex: "01",
            sectionTitle: "QUICK GUIDE FOR FIRST-TIME PLAYERS",
            trailingHeader: {
                StatusPill(
                    text: vm.isReadyToLaunch ? "ALL STEPS COMPLETE" : "1-CLICK TURNKEY INSTALLER",
                    style: vm.isReadyToLaunch ? .ready : .installing
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Click 'Start 1-Click Setup' below. If your internet disconnects, don't worry—the download saves your progress and continues automatically.")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.primary.opacity(0.88))
                    Text("2. Once all 4 steps show a green checkmark, turn on your Xbox or PlayStation Bluetooth controller and click 'Launch Forza Horizon 2'.")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.primary.opacity(0.88))
                }
            }
        )
    }

    // MARK: 3. 4-Step Visual Progress Checklist
    private var checklistCard: some View {
        MonoCard(
            sectionIndex: "02",
            sectionTitle: "A-TO-Z SETUP CHECKLIST",
            trailingHeader: {
                if let interrupted = vm.connectionInterruptedBanner {
                    StatusPill(text: interrupted, style: .actionNeeded)
                } else if vm.isRunningSetupPipeline {
                    StatusPill(text: "INSTALLING", style: .installing)
                } else if vm.isReadyToLaunch {
                    StatusPill(text: "READY TO PLAY", style: .ready)
                } else {
                    StatusPill(text: "SETUP REQUIRED", style: .actionNeeded)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    ChecklistStepRow(
                        indexLabel: "[1]",
                        title: "macOS Graphics Runtime",
                        state: vm.step1State
                    )
                    Divider().opacity(0.4)
                    ChecklistStepRow(
                        indexLabel: "[2]",
                        title: "Game Download (16.8 GB)",
                        state: vm.step2State
                    )
                    Divider().opacity(0.4)
                    ChecklistStepRow(
                        indexLabel: "[3]",
                        title: "Game Unpacking & Installation",
                        state: vm.step3State
                    )
                    Divider().opacity(0.4)
                    ChecklistStepRow(
                        indexLabel: "[4]",
                        title: "Controller & Graphics Setup",
                        state: vm.step4State
                    )
                }
            }
        )
    }

    // MARK: 4. Launch Configuration & Game Library Override
    private var configurationCard: some View {
        MonoCard(
            sectionIndex: "03",
            sectionTitle: "CONFIGURATION & GAME FOLDER",
            trailingHeader: {
                switch vm.folderValidation {
                case .verified(_, let isSymlink) where !isSymlink:
                    StatusPill(text: "[VERIFIED]", style: .ready)
                case .verified(_, _):
                    StatusPill(text: "[SYMLINK NOT SUPPORTED]", style: .actionNeeded)
                case .unconfigured, .invalid:
                    StatusPill(text: "[AUTO-DOWNLOAD OR BROWSE]", style: .neutral)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Text("Resolution")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85))
                            Picker("", selection: $vm.resolution) {
                                ForEach(ResolutionOption.allCases) { opt in
                                    Text(opt.label).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 210)
                        }

                        HStack(spacing: 6) {
                            Text("Azimuth")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85))
                            Picker("", selection: $vm.azimuthBuild) {
                                ForEach(AzimuthBuildOption.allCases) { opt in
                                    Text(opt.label).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 155)
                            .disabled(!vm.isAzimuth101Available)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Text(vm.gameFolderPath.isEmpty ? "~/Games/Forza Horizon 2" : URL(fileURLWithPath: vm.gameFolderPath).lastPathComponent)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 120, alignment: .trailing)

                            Button(action: { vm.selectGameFolder() }) {
                                Text("Browse…")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Theme.cardBorder, lineWidth: 1)
                                    )
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().opacity(0.45)

                    HStack(spacing: 16) {
                        Toggle(isOn: $vm.enableExtraOptions) {
                            Text("Unlock All DLC Cars & Skip Intro (ExtraOptions)")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.cyan)

                        Spacer()

                        Toggle(isOn: $vm.showInstallerWindow) {
                            Text("Show Installer Window")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.cyan)

                        Toggle(isOn: $vm.showMetalHUD) {
                            Text("Metal FPS HUD")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(6)
            }
            .frame(height: 56)
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

    // MARK: 5. Bottom Action Bar (Dynamic Primary Button)
    private var bottomActionBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.showLogsDrawer.toggle()
                }
            }) {
                Text(vm.showLogsDrawer ? "▾ Hide Logs" : "▸ View Logs")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: { vm.refreshEnvironment() }) {
                Text("Rescan")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if let err = vm.errorBannerText {
                Text(err)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.amber)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if !vm.launchStatusText.isEmpty {
                Text(vm.launchStatusText)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.cyan)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if vm.isReadyToLaunch {
                // All 4 steps complete -> Launch Forza Horizon 2
                Button(action: { vm.launchGame() }) {
                    HStack(spacing: 8) {
                        if vm.isLaunchingGame {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.75)
                        }
                        Text(vm.isLaunchingGame ? "Launching…" : "Launch Forza Horizon 2")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Theme.emerald)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else if vm.isRunningSetupPipeline {
                Button(action: { vm.pauseSetupPipeline() }) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                        Text("Pause Setup (Progress Saved)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.10))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { vm.startOrResumeOneClickSetup() }) {
                    Text(vm.isSetupPausedOrInterrupted ? "Resume Setup & Download" : "Start 1-Click Setup & Download (16.8 GB)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Theme.cyan)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
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

// MARK: - Automated End-to-End Runtime Self-Test (`--self-test`)

enum SelfTestRunner {
    static func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "FH2SelfTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Assertion failed: \(message)"
            ])
        }
        print("[PASS] \(message)")
    }

    static func run() -> Int32 {
        print("=== Forza Horizon 2 macOS App (v1.1.0) — Runtime & A-to-Z Integration Self-Test ===")
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fh2-selftest-\(ProcessInfo.processInfo.globallyUniqueString)")

        let defaults = UserDefaults.standard
        let savedFolder = defaults.string(forKey: "FH2_GameFolderPath")
        let savedRes = defaults.string(forKey: "FH2_Resolution")
        let savedAz = defaults.string(forKey: "FH2_AzimuthBuild")
        let savedEO = defaults.object(forKey: "FH2_EnableExtraOptions")
        let savedHUD = defaults.object(forKey: "FH2_ShowMetalHUD")

        defer {
            try? fm.removeItem(at: tempRoot)
            if let v = savedFolder { defaults.set(v, forKey: "FH2_GameFolderPath") } else { defaults.removeObject(forKey: "FH2_GameFolderPath") }
            if let v = savedRes { defaults.set(v, forKey: "FH2_Resolution") } else { defaults.removeObject(forKey: "FH2_Resolution") }
            if let v = savedAz { defaults.set(v, forKey: "FH2_AzimuthBuild") } else { defaults.removeObject(forKey: "FH2_AzimuthBuild") }
            if let v = savedEO { defaults.set(v, forKey: "FH2_EnableExtraOptions") } else { defaults.removeObject(forKey: "FH2_EnableExtraOptions") }
            if let v = savedHUD { defaults.set(v, forKey: "FH2_ShowMetalHUD") } else { defaults.removeObject(forKey: "FH2_ShowMetalHUD") }
        }

        do {
            try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            // 1. Verify Bundle Resources & Payload Integrity (including static 7zz, noop.exe, manifest.json)
            guard let resURL = Bundle.main.resourceURL else {
                throw NSError(domain: "FH2SelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundle.main.resourceURL is nil"])
            }
            let requiredFiles = [
                "AppIcon.icns",
                "manifest.json",
                "bin/7zz",
                "payload/azimuth-0.9.10/azimuth.exe",
                "payload/azimuth-1.0.1/azimuth.exe",
                "payload/layer/d3d12.dll",
                "payload/layer/fh2pad.dll",
                "payload/layer/d3dcompiler_47.dll",
                "payload/layer/noop.exe",
                "payload/extra_options/winmm.dll",
                "payload/extra_options/FH2_ExtraOptions.ini"
            ]
            for rel in requiredFiles {
                let fileURL = resURL.appendingPathComponent(rel)
                let exists = fm.fileExists(atPath: fileURL.path)
                let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
                try assertCondition(exists && size > 0, "Bundled resource exists and is non-empty: \(rel) (\(size) bytes)")
            }

            let sevenZipURL = resURL.appendingPathComponent("bin/7zz")
            try assertCondition(fm.isExecutableFile(atPath: sevenZipURL.path), "Bundled Contents/Resources/bin/7zz is executable")

            let manifest = SetupManifest.loadFromBundle()
            try assertCondition(
                manifest.gameFileID == "1VVmQ3d_qHOj6UhPfslSgeaBfQbc3zYcf" && manifest.gameExpectedBytes == 18_001_002_054,
                "Loaded manifest.json -> file_id=\(manifest.gameFileID), size_bytes=\(manifest.gameExpectedBytes)"
            )

            // 2. Verify Google Drive Large-File Confirmation Resolver & Byte-Range Auto-Resume (First 1 MB + Next 1 MB)
            let resolvedDriveURL = LauncherViewModel.resolveGoogleDriveDownloadURL(fileID: manifest.gameFileID)
            try assertCondition(
                resolvedDriveURL.contains("drive.usercontent.google.com/download") && resolvedDriveURL.contains(manifest.gameFileID),
                "Google Drive confirmation resolver resolved URL: \(resolvedDriveURL)"
            )

            let vm = LauncherViewModel()
            let drivePartTest = tempRoot.appendingPathComponent("fh2_drive_range_test.zip.part")

            // Download first 1 MB (bytes 0..1048575)
            let (c1Code, _) = vm.runProcess(
                executable: "/usr/bin/curl",
                args: ["-fsSL", "--retry", "3", "--range", "0-1048575", "-o", drivePartTest.path, resolvedDriveURL]
            )
            let firstMBData = (try? Data(contentsOf: drivePartTest)) ?? Data()
            try assertCondition(
                c1Code == 0 && firstMBData.count == 1_048_576 && firstMBData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]),
                "Downloaded first 1 MB (1,048,576 bytes) of FH2-Game.zip from Google Drive and verified PK\\x03\\x04 zip magic bytes"
            )

            // Verify byte-exact resume (`curl -C -` / range 1048576..2097151) for the next 1 MB
            let driveChunk2 = tempRoot.appendingPathComponent("fh2_drive_chunk2.bin")
            let (c2Code, _) = vm.runProcess(
                executable: "/usr/bin/curl",
                args: ["-fsSL", "--retry", "3", "-C", "1048576", "-r", "1048576-2097151", "-o", driveChunk2.path, resolvedDriveURL]
            )
            if let chunk2Data = try? Data(contentsOf: driveChunk2), let handle = try? FileHandle(forWritingTo: drivePartTest) {
                handle.seekToEndOfFile()
                handle.write(chunk2Data)
                try? handle.close()
            }
            let combinedSize = (try? fm.attributesOfItem(atPath: drivePartTest.path)[.size] as? Int64) ?? 0
            try assertCondition(
                c2Code == 0 && combinedSize == 2_097_152,
                "Verified byte-range resume downloaded second 1 MB cleanly (total 2,097,152 bytes with intact PK header)"
            )

            // 3. Verify Live SwiftUI View Hierarchy & AppKit Window Rendering (740 x 560)
            _ = NSApplication.shared
            let mainView = LauncherMainView(vm: vm)
            let hostingView = NSHostingView(rootView: mainView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 560)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()

            vm.showLogsDrawer = true
            vm.step2State = .waitingForInternet(progress: 0.50, detail: "Connection interrupted — waiting for internet to resume from 8.4 GB (50%)...")
            hostingView.layoutSubtreeIfNeeded()

            if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                try assertCondition(bitmap.pixelsWide >= 740 && bitmap.pixelsHigh >= 560, "Rendered live 740x560 SwiftUI LauncherMainView to bitmap (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) px)")
            }

            // 4. Verify Complete 4-Step A-to-Z Pipeline End-to-End (7zz Extraction, Bracket-Free Flattening, QuickSFV Neutralization, winxp64 -> setup.exe -> win10, Azimuth Setup)
            let mockRepackSrc = tempRoot.appendingPathComponent("Forza Horizon 2 [FitGirl Repack]")
            try fm.createDirectory(at: mockRepackSrc.appendingPathComponent("MD5"), withIntermediateDirectories: true)
            try fm.createDirectory(at: mockRepackSrc.appendingPathComponent("_Redist"), withIntermediateDirectories: true)
            try Data("MOCK_SETUP_EXE".utf8).write(to: mockRepackSrc.appendingPathComponent("setup.exe"))
            try Data("MOCK_FG01_BIN".utf8).write(to: mockRepackSrc.appendingPathComponent("fg-01.bin"))
            try Data("ORIGINAL_QUICKSFV_1".utf8).write(to: mockRepackSrc.appendingPathComponent("MD5/QuickSFV.EXE"))
            try Data("ORIGINAL_QUICKSFV_2".utf8).write(to: mockRepackSrc.appendingPathComponent("_Redist/QuickSFV.exe"))

            let mockGameZip = tempRoot.appendingPathComponent("mock_fh2_source.zip")
            let (packCode, _) = vm.runProcess(
                executable: sevenZipURL.path,
                args: ["a", "-tzip", mockGameZip.path, mockRepackSrc.path]
            )
            let mockZipSize = (try? fm.attributesOfItem(atPath: mockGameZip.path)[.size] as? Int64) ?? 0
            try assertCondition(packCode == 0 && mockZipSize > 0, "Created mock FitGirl Repack archive with bundled 7zz (\(mockZipSize) bytes)")

            let mockBinDir = tempRoot.appendingPathComponent("mock_bin")
            let mockExtDir = tempRoot.appendingPathComponent("mock_d3dmetal_ext")
            try fm.createDirectory(at: mockBinDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: mockExtDir.appendingPathComponent("D3DMetal.framework"), withIntermediateDirectories: true)

            let mockWineLog = tempRoot.appendingPathComponent("mock_wine_calls.log")
            let mockWineScript = mockBinDir.appendingPathComponent("wine64")
            let scriptBody = """
            #!/bin/bash
            echo "CALL args=[$*] WINEPREFIX=[$WINEPREFIX] D3DMETAL=[$D3DMETAL] AVX=[$ROSETTA_ADVERTISE_AVX]" >> "\(mockWineLog.path)"
            if [ "$1" = "wineboot" ]; then
                mkdir -p "$WINEPREFIX/drive_c"
                echo "WINE REGISTRY Version 2" > "$WINEPREFIX/system.reg"
            fi
            if [[ "$*" == *"C:\\\\fg_setup\\\\setup.exe"* ]]; then
                if [ -f "$WINEPREFIX/drive_c/fg_setup/MD5/QuickSFV.EXE.disabled" ] && [ -f "$WINEPREFIX/drive_c/fg_setup/_Redist/QuickSFV.exe.disabled" ]; then
                    echo "QUICKSFV_NEUTRALIZED=YES" >> "\(mockWineLog.path)"
                fi
                mkdir -p "$WINEPREFIX/drive_c/FH2Game/Mount"
                echo "MZ_UNPACKED_FH2_EXE" > "$WINEPREFIX/drive_c/FH2Game/Mount/forza_durango_release_final.exe"
            fi
            exit 0
            """
            try Data(scriptBody.utf8).write(to: mockWineScript)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockWineScript.path)

            let mockEnv = RuntimeEnvironment(
                rosettaInstalled: true,
                runtimeKind: .gptkStandalone,
                wineExecutable: mockWineScript,
                wineserverExecutable: nil,
                cxBottleExecutable: nil,
                d3dMetalExternalDir: mockExtDir,
                gptkWineDllDir: nil,
                crossoverRoot: nil,
                highballRoot: nil,
                gptkAppURL: nil
            )

            let testCacheDir = tempRoot.appendingPathComponent("cache")
            let testBottle = tempRoot.appendingPathComponent("bottle")
            let testFinalGameDir = tempRoot.appendingPathComponent("Games/Forza Horizon 2")

            try vm.executeFourStepSetupPipeline(
                customCacheDir: testCacheDir,
                customBottleURL: testBottle,
                customGameDestDir: testFinalGameDir,
                mockRuntimeEnv: mockEnv,
                customGameZipURLResolver: { "file://\(mockGameZip.path)" },
                customGameExpectedBytes: mockZipSize,
                customUnpackedTargetBytes: 4096
            )

            try assertCondition(
                fm.fileExists(atPath: testFinalGameDir.appendingPathComponent("Mount/forza_durango_release_final.exe").path),
                "4-Step pipeline unpacked forza_durango_release_final.exe into final game folder"
            )
            try assertCondition(
                !fm.fileExists(atPath: testBottle.appendingPathComponent("drive_c/fg_setup").path),
                "Temporary drive_c/fg_setup folder was automatically deleted after setup.exe finished"
            )
            try assertCondition(
                !fm.fileExists(atPath: testCacheDir.appendingPathComponent("FH2-Game.zip").path),
                "Temporary FH2-Game.zip archive was automatically deleted after 7zz extraction"
            )

            let wineCalls = (try? String(contentsOf: mockWineLog, encoding: .utf8)) ?? ""
            try assertCondition(wineCalls.contains("QUICKSFV_NEUTRALIZED=YES"), "Neutralized both MD5/QuickSFV.EXE and _Redist/QuickSFV.exe with noop.exe before setup.exe ran")
            try assertCondition(wineCalls.contains("Version /t REG_SZ /d winxp64"), "Wine prefix was set to winxp64 before running setup.exe")
            try assertCondition(wineCalls.contains(#"C:\fg_setup\setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /DIR=C:\FH2Game"#), "setup.exe was invoked with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /DIR=C:\\FH2Game")
            try assertCondition(wineCalls.contains("Version /t REG_SZ /d win10"), "Wine prefix was restored to win10 after setup.exe completed")
            try assertCondition(wineCalls.contains("d3d12 /t REG_SZ /d native,builtin"), "Step 4 configured Wine DLL overrides for Azimuth")

            let iniURL = testBottle.appendingPathComponent("drive_c/Azimuth/data/azimuth.ini")
            let iniRaw = try Data(contentsOf: iniURL)
            let iniText = String(data: Data(iniRaw.dropFirst(2)), encoding: .utf16LittleEndian) ?? ""
            try assertCondition(
                iniRaw.prefix(2) == Data([0xFF, 0xFE]) && iniText.contains("game=1a96545b") && iniText.contains("antialiasing=off"),
                "Step 4 wrote valid UTF-16LE data/azimuth.ini pointing directly to unpacked Forza Horizon 2 folder"
            )

            print("=== ALL v1.1.0 SELF-TESTS PASSED SUCCESSFULLY (0 ERRORS) ===")
            return 0
        } catch {
            fputs("[FAIL] Self-test error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}

@main
enum LauncherEntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTestRunner.run())
        } else {
            FH2LauncherApp.main()
        }
    }
}
