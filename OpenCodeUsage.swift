import Cocoa
import Security

// MARK: - Models

struct WindowUsage: Decodable {
    let status: String
    let percent: Int
    let resetsAt: String
}

struct GoUsage: Decodable {
    let rolling: WindowUsage
    let weekly: WindowUsage
    let monthly: WindowUsage
}

struct UsageResponse: Decodable {
    let usage: GoUsage
}

// MARK: - Keychain

struct KeychainStore {
    let service: String
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ value: String) throws {
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain error \(status)"]
            )
        }
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Settings

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "es.duque.opencodeusage", account: "api-key")
    private let legacyKeyPath = NSString(string: "~/.config/opencode-usage/key").expandingTildeInPath

    private enum Keys {
        static let language = "language"
        static let refreshMinutes = "refreshMinutes"
    }

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.language) }
    }

    var refreshMinutes: Int {
        get {
            let value = defaults.integer(forKey: Keys.refreshMinutes)
            return value > 0 ? value : 5
        }
        set { defaults.set(newValue, forKey: Keys.refreshMinutes) }
    }

    func apiKey() -> String? {
        if let key = keychain.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return legacyApiKey()
    }

    func legacyApiKey() -> String? {
        guard let data = FileManager.default.contents(atPath: legacyKeyPath),
              let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    func saveApiKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychain.delete()
        } else {
            try keychain.save(trimmed)
        }
    }
}

// MARK: - Localization

struct Strings {
    let isSpanish: Bool

    init() {
        switch Settings.shared.language {
        case "es":
            isSpanish = true
        case "en":
            isSpanish = false
        default:
            isSpanish = (Locale.preferredLanguages.first ?? "en").hasPrefix("es")
        }
    }

    var weekly: String { isSpanish ? "Semanal" : "Weekly" }
    var monthly: String { isSpanish ? "Mensual" : "Monthly" }
    var refreshNow: String { isSpanish ? "Actualizar ahora" : "Refresh now" }
    var openConsole: String { isSpanish ? "Abrir Console" : "Open Console" }
    var settings: String { isSpanish ? "Configuración…" : "Settings…" }
    var quit: String { isSpanish ? "Salir" : "Quit" }
    var noKey: String { isSpanish ? "Configura tu API key" : "Set up your API key" }
    var noData: String { isSpanish ? "Sin datos" : "No data" }
    var apiKey: String { isSpanish ? "API key" : "API key" }
    var language: String { isSpanish ? "Idioma" : "Language" }
    var refreshEvery: String { isSpanish ? "Actualizar cada" : "Refresh every" }
    var minutes: String { isSpanish ? "minutos" : "minutes" }
    var test: String { isSpanish ? "Probar" : "Test" }
    var save: String { isSpanish ? "Guardar" : "Save" }
    var cancel: String { isSpanish ? "Cancelar" : "Cancel" }
    var settingsTitle: String { isSpanish ? "Configuración" : "Settings" }
    var keyHelp: String { isSpanish ? "Se guarda en el Llavero de macOS." : "Stored in the macOS Keychain." }
    var testOk: String { isSpanish ? "Conexión correcta" : "Connection OK" }
    var testEmpty: String { isSpanish ? "Introduce una API key" : "Enter an API key" }
    var languageSystem: String { isSpanish ? "Sistema" : "System" }
    var languageSpanish: String { "Español" }
    var languageEnglish: String { "English" }
}

// MARK: - API client

final class UsageClient {
    func fetch(completion: @escaping (Result<GoUsage, Error>) -> Void) {
        guard let key = Settings.shared.apiKey() else {
            completion(.failure(NSError(
                domain: "OpenCodeUsage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: Strings().noKey]
            )))
            return
        }
        fetch(key: key, completion: completion)
    }

    func fetch(key: String, completion: @escaping (Result<GoUsage, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://opencode.ai/inference/go/v1/usage")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(
                    domain: "OpenCodeUsage",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                )))
                return
            }
            guard (200..<300).contains(http.statusCode), let data = data else {
                completion(.failure(NSError(
                    domain: "OpenCodeUsage",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                )))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                completion(.success(decoded.usage))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSSecureTextField()
    private let languagePopup = NSPopUpButton()
    private let refreshPopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")

    var onSave: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        buildContent()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let window = window else { return }
        let s = Strings()
        window.title = s.settingsTitle

        apiKeyField.placeholderString = "oc_sk_…"
        apiKeyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.stringValue = Settings.shared.apiKey() ?? ""

        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [s.languageSystem, s.languageSpanish, s.languageEnglish])
        switch Settings.shared.language {
        case "es": languagePopup.selectItem(at: 1)
        case "en": languagePopup.selectItem(at: 2)
        default: languagePopup.selectItem(at: 0)
        }

        let intervals = [1, 5, 15, 30, 60]
        refreshPopup.removeAllItems()
        refreshPopup.addItems(withTitles: intervals.map { "\($0) \(s.minutes)" })
        refreshPopup.selectItem(at: intervals.firstIndex(of: Settings.shared.refreshMinutes) ?? 1)

        let apiLabel = NSTextField(labelWithString: s.apiKey)
        apiLabel.font = .boldSystemFont(ofSize: 12)
        let languageLabel = NSTextField(labelWithString: s.language)
        let refreshLabel = NSTextField(labelWithString: s.refreshEvery)

        let help = NSTextField(wrappingLabelWithString: s.keyHelp)
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""

        let testButton = NSButton(title: s.test, target: self, action: #selector(testConnection))
        let cancelButton = NSButton(title: s.cancel, target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: s.save, target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let buttons = NSStackView(views: [testButton, spacer, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fill

        let grid = NSGridView(views: [
            [apiLabel, apiKeyField],
            [languageLabel, languagePopup],
            [refreshLabel, refreshPopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 120
        grid.column(at: 1).xPlacement = .fill

        let stack = NSStackView(views: [grid, help, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])

        window.contentView = content
    }

    @objc private func testConnection() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus(Strings().testEmpty, color: .systemOrange)
            return
        }

        setStatus("…", color: .secondaryLabelColor)
        UsageClient().fetch(key: key) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.setStatus(Strings().testOk, color: .systemGreen)
                case .failure(let error):
                    self.setStatus(error.localizedDescription, color: .systemRed)
                }
            }
        }
    }

    @objc private func save() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try Settings.shared.saveApiKey(key)
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
            return
        }

        switch languagePopup.indexOfSelectedItem {
        case 1: Settings.shared.language = "es"
        case 2: Settings.shared.language = "en"
        default: Settings.shared.language = "system"
        }

        let intervals = [1, 5, 15, 30, 60]
        let index = max(0, min(refreshPopup.indexOfSelectedItem, intervals.count - 1))
        Settings.shared.refreshMinutes = intervals[index]

        onSave?()
        window?.close()
    }

    @objc private func cancel() {
        window?.close()
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let client = UsageClient()
    private var timer: Timer?
    private var usage: GoUsage?
    private var lastError: String?
    private var isFetching = false
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "OpenCode Go"
            button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        restartTimer()
        refresh()

        if Settings.shared.apiKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        rebuildMenu()
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func openConsole() {
        NSWorkspace.shared.open(URL(string: "https://opencode.ai/console")!)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController()
            controller.onSave = { [weak self] in
                self?.restartTimer()
                self?.refresh()
                self?.rebuildMenu()
            }
            settingsWindow = controller
        }
        settingsWindow?.present()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, Settings.shared.refreshMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard !isFetching else { return }
        guard Settings.shared.apiKey() != nil else {
            usage = nil
            lastError = nil
            updateStatusItem()
            rebuildMenu()
            return
        }

        isFetching = true
        client.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false
                switch result {
                case .success(let usage):
                    self.usage = usage
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
                self.updateStatusItem()
                self.rebuildMenu()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let s = Strings()

        if let usage = usage {
            let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            let labelFont = NSFont.systemFont(ofSize: 12, weight: .bold)
            let title = NSMutableAttributedString()

            title.append(NSAttributedString(
                string: "OpenCode Go: ",
                attributes: [.foregroundColor: NSColor.white, .font: labelFont]
            ))
            appendWindow(title, label: "5h", percent: usage.rolling.percent, font: valueFont)
            appendSeparator(title, font: labelFont)
            appendWindow(title, label: s.weekly, percent: usage.weekly.percent, font: valueFont)
            appendSeparator(title, font: labelFont)
            appendWindow(title, label: s.monthly, percent: usage.monthly.percent, font: valueFont)

            button.attributedTitle = title
            button.toolTip = "5h \(usage.rolling.percent)% (reset \(formatReset(usage.rolling.resetsAt))) · "
                + "\(s.weekly) \(usage.weekly.percent)% (reset \(formatReset(usage.weekly.resetsAt))) · "
                + "\(s.monthly) \(usage.monthly.percent)% (reset \(formatReset(usage.monthly.resetsAt)))"
        } else if Settings.shared.apiKey() == nil {
            button.attributedTitle = NSAttributedString(
                string: "OpenCode Go: —",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                ]
            )
            button.toolTip = s.noKey
        } else {
            button.attributedTitle = NSAttributedString(
                string: "OpenCode Go: !",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                ]
            )
            button.toolTip = lastError ?? s.noData
        }
    }

    private func appendWindow(_ target: NSMutableAttributedString, label: String, percent: Int, font: NSFont) {
        target.append(NSAttributedString(
            string: "\(label) ",
            attributes: [.foregroundColor: NSColor.white, .font: font]
        ))
        target.append(NSAttributedString(
            string: "\(percent)%",
            attributes: [.foregroundColor: color(for: percent), .font: font]
        ))
    }

    private func appendSeparator(_ target: NSMutableAttributedString, font: NSFont) {
        target.append(NSAttributedString(
            string: " · ",
            attributes: [.foregroundColor: NSColor.white, .font: font]
        ))
    }

    private func color(for percent: Int) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 70 { return .systemOrange }
        return .systemGreen
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        let s = Strings()
        menu.removeAllItems()

        if let usage = usage {
            menu.addItem(info("5h", "\(usage.rolling.percent)%", reset: usage.rolling.resetsAt))
            menu.addItem(info(s.weekly, "\(usage.weekly.percent)%", reset: usage.weekly.resetsAt))
            menu.addItem(info(s.monthly, "\(usage.monthly.percent)%", reset: usage.monthly.resetsAt))
        } else if Settings.shared.apiKey() == nil {
            let item = NSMenuItem(title: s.noKey, action: #selector(openSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: lastError ?? s.noData, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: s.refreshNow, action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: s.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let consoleItem = NSMenuItem(title: s.openConsole, action: #selector(openConsole), keyEquivalent: "")
        consoleItem.target = self
        menu.addItem(consoleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: s.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String, _ percent: String, reset: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(percent) · reset \(formatReset(reset))", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatReset(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date = date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "dd/MM HH:mm"
        return out.string(from: date)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
