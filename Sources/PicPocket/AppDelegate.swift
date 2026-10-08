import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let line = Line()
    private let pocketStats = PocketStats()
    private var panel: LinePanel!
    private var watcher: ScreenshotWatcher!
    /// In inbox mode, a second watcher on the Desktop. If a macOS version
    /// ignores the screenshot settings (macOS 27 renamed one), captures keep
    /// landing on the Desktop, and they still hang on the line.
    private var safetyWatcher: ScreenshotWatcher?
    private var signalSources: [DispatchSourceSignal] = []
    private var hotKey: HotKey?
    private var mouseTimer: Timer?

    /// Whether the panel is ordered in.
    private var isPresent = false
    /// Whether the pocket is visible.
    private var isRevealed = false
    /// Opened on purpose with the shortcut or the menu: it stays down until
    /// the cursor has visited it and left, or the shortcut is pressed again.
    private var pinned = false
    private var hotZoneSince: Date?
    private var awaySince: Date?
    private var peekUntil = Date.distantPast
    private var wanted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: LineView(line: line, pocketStats: pocketStats, onSettings: { [weak self] in
            self?.showSettings()
        }))
        host.sizingOptions = []
        panel = LinePanel(content: host)
        panel.placeOnScreen()
        updateCapacity()

        if Inbox.isEnabled { Inbox.apply() }
        restoreSettingsOnTermination()
        startWatcher()

        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            self?.toggle()
        }

        startMouseTracking()

        Markup.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        line.onFall = { [weak self] item, completion in
            guard let self else { completion(); return }
            self.pickpocket(item, completion: completion)
        }

        // Entering or leaving full screen switches Space. Check again once the
        // switch animation has settled.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.refresh() }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.placeOnScreen()
                self?.updateCapacity()
            }
        }

        if !Inbox.wasOffered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.offerInbox() }
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            wanted = true
            refresh()
            reveal(pinned: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.line.liveCount == 0 else { return }
                self.wanted = false
                self.refresh()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
    }

    // MARK: Inbox mode

    private func startWatcher() {
        watcher?.stop()
        safetyWatcher?.stop()
        safetyWatcher = nil
        watcher = ScreenshotWatcher(
            onNew: { [weak self] url in self?.hangCapture(url) ?? false },
            onChange: { [weak self] in self?.line.prune() })
        watcher.start()
        if Inbox.isEnabled, watcher.folder.standardizedFileURL != ScreenshotWatcher.desktop.standardizedFileURL {
            let safety = ScreenshotWatcher(
                folder: ScreenshotWatcher.desktop,
                onNew: { [weak self] url in
                    log.notice("Screenshot landed on the Desktop despite inbox mode: \(url.lastPathComponent, privacy: .public)")
                    return self?.hangCapture(url) ?? false
                },
                onChange: { [weak self] in self?.line.prune() })
            safety.start()
            safetyWatcher = safety
        }
    }

    private func setInbox(_ on: Bool) {
        Inbox.isEnabled = on
        if on { Inbox.apply() } else { Inbox.restore() }
        startWatcher()
    }

    /// Asked once. Changing system settings is the user's call, never ours.
    private func offerInbox() {
        Inbox.wasOffered = true
        let alert = NSAlert()
        alert.messageText = L("Let PicPocket handle your screenshots?",
                              "¿Quieres que PicPocket se encargue de tus capturas?")
        alert.informativeText = L(
            "Screenshots will appear in your pocket the instant you take them, without the floating thumbnail, and will not pile up on your Desktop. Drag one to a folder to keep it, or discard it with the cross. You can turn this off from the pocket settings, and your settings come back when PicPocket quits.",
            "Las capturas aparecerán en tu bolsillo al instante, sin la miniatura flotante, y no se acumularán en el Escritorio. Arrastra una a una carpeta para guardarla, o descártala con la cruz. Puedes desactivarlo desde los ajustes del bolsillo, y tus ajustes vuelven a ser los de antes al salir de PicPocket.")
        alert.addButton(withTitle: L("Turn on", "Activar"))
        alert.addButton(withTitle: L("Not now", "Ahora no"))
        if let icon = NSImage(named: "PicPocket") ?? NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { setInbox(true) }
    }

    /// Quitting from the menu or logging out runs applicationWillTerminate.
    /// A plain kill does not, so settings are also restored on those signals.
    private func restoreSettingsOnTermination() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                if Inbox.isEnabled { Inbox.restore() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Showing and hiding

    private func hangCapture(_ url: URL) -> Bool {
        if line.items.contains(where: { $0.url == url && !$0.falling }) { return true }
        guard line.hang(url) != nil else { return false }
        pocketStats.recordCapture()
        // Keep the pocket in place if a screenshot arrives during an interaction.
        if !isRevealed || (!GrabView.isDragging && !GrabView.isMenuTracking && line.pressedID == nil) {
            let screen = captureRect(of: url).flatMap { rect in
                NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
            }
            panel.placeOnScreen(screen)
        }
        wanted = true
        refresh()
        peekUntil = Date().addingTimeInterval(2.5)
        reveal()
        return true
    }

    /// A hand carries the dismissed screenshot out of the pocket.
    private func pickpocket(_ item: Pegged, completion: @escaping () -> Void) {
        guard isPresent, isRevealed, !item.flying, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion()
            return
        }
        CaptureFlight.steal(image: image, card: card, on: screen,
                            direction: card.midX < panel.frame.midX ? -1 : 1,
                            completion: completion)
        peekUntil = max(peekUntil, Date().addingTimeInterval(CaptureFlight.duration))
    }

    /// Where a card will hang, in screen coordinates, using the same layout
    /// as the line view.
    private func cardFrame(for id: UUID) -> CGRect? {
        let items = line.items.reversed()
        guard let index = Array(items).firstIndex(where: { $0.id == id }),
              let item = items.first(where: { $0.id == id }) else { return nil }
        let center = Layout.cardCenter(index: index)
        let size = PeggedView.cardSize(for: item.thumb.size)
        return CGRect(x: panel.frame.minX + center.x - size.width / 2,
                      y: panel.frame.maxY - center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func refresh() {
        if wanted { present() } else { dismiss() }
    }

    private func present() {
        guard !isPresent else { return }
        isPresent = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func dismiss() {
        guard isPresent else { return }
        isPresent = false
        setRevealed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isPresent else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reveal(pinned: Bool = false) {
        guard isPresent else { return }
        if pinned { self.pinned = true }
        awaySince = nil
        setRevealed(true)
    }

    private func setRevealed(_ on: Bool) {
        guard on != isRevealed else { return }
        isRevealed = on
        line.revealed = on
        if !on { line.hoveredID = nil }
        if !on {
            pinned = false
            peekUntil = .distantPast
            panel.ignoresMouseEvents = true
        }
    }

    @objc private func toggle() {
        if isRevealed {
            setRevealed(false)
            if line.liveCount == 0 {
                wanted = false
                refresh()
            }
        } else {
            wanted = true
            panel.placeOnScreen()
            updateCapacity()
            refresh()
            reveal(pinned: true)
        }
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    /// A brief dwell avoids opening the pocket when just passing the corner.
    private static let revealDelay: TimeInterval = 0.1

    /// How long the cursor is away before the pocket hides.
    private static let retractDelay: TimeInterval = 0.5

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()

        let screenUnderPointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inCorner = screenUnderPointer.map { Layout.hotZone(in: $0.frame).contains(mouse) } ?? false

        guard isRevealed else {
            if let screen = screenUnderPointer, inCorner {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    panel.placeOnScreen(screen)
                    updateCapacity()
                    wanted = true
                    refresh()
                    reveal()
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        let hovered = Layout.hoveredID(in: line.items, at:
            CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y))
        if line.hoveredID != hovered { line.hoveredID = hovered }
        updateMousePassThrough(mouse)

        // Include the path between the physical corner and the pocket,
        // even when the Dock reserves space along the bottom or right edge.
        var zone = panel.frame
        if let screen = panel.screen {
            zone = CGRect(x: zone.minX, y: screen.frame.minY,
                          width: screen.frame.maxX - zone.minX,
                          height: zone.maxY - screen.frame.minY)
        }
        let inside = NSMouseInRect(mouse, zone, false)
        if inside && pinned { pinned = false }

        let busy = pinned || GrabView.isDragging || GrabView.isMenuTracking || line.pressedID != nil || now < peekUntil
        if inside || busy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                setRevealed(false)
            }
        }
    }

    /// Only accept clicks over the pocket, including gaps between cards.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard !GrabView.isDragging else { return }
        panel.ignoresMouseEvents = !panel.frame.contains(mouse)
    }

    private func updateCapacity() {
        line.maxItems = Layout.capacity
    }

    // MARK: Pocket settings

    private func showSettings() {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        let previousLevel = panel.level
        GrabView.isMenuTracking = true
        panel.level = .floating
        defer {
            panel.level = previousLevel
            GrabView.isMenuTracking = false
            awaySince = nil
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: panel.frame.maxX - 32, y: panel.frame.maxY - 42),
                   in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleItem = ClosureMenuItem(isRevealed ? L("Hide pocket", "Ocultar bolsillo")
                                                 : L("Show pocket", "Mostrar bolsillo")) { [weak self] in
            self?.toggle()
        }
        toggleItem.keyEquivalent = "t"
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleItem)

        let clearItem = ClosureMenuItem(L("Empty pocket", "Vaciar bolsillo")) { [weak self] in
            self?.line.clear()
        }
        clearItem.isEnabled = line.liveCount > 0
        menu.addItem(clearItem)

        let inbox = ClosureMenuItem(L("Handle screenshots", "Encargarse de las capturas")) { [weak self] in
            self?.setInbox(!Inbox.isEnabled)
        }
        inbox.state = Inbox.isEnabled ? .on : .off
        inbox.toolTip = L("Screenshots go straight into your pocket instead of the Desktop",
                          "Las capturas van directamente al bolsillo en vez del Escritorio")
        menu.addItem(inbox)

        menu.addItem(ClosureMenuItem(L("Open screenshots folder", "Abrir carpeta de capturas")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.watcher.folder)
        })

        menu.addItem(.separator())

        let sound = ClosureMenuItem(L("Sounds", "Sonidos")) { [weak self] in
            guard let self else { return }
            self.line.soundOn.toggle()
        }
        sound.state = line.soundOn ? .on : .off
        menu.addItem(sound)

        let login = ClosureMenuItem(L("Open at login", "Abrir al iniciar sesión")) {
            AppDelegate.toggleLaunchAtLogin()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit PicPocket", "Salir de PicPocket"), key: "q") {
            NSApp.terminate(nil)
        })
    }

    private static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change the login setting", "No se pudo cambiar el inicio de sesión")
            alert.informativeText = L("Move PicPocket to the Applications folder and try again.",
                                      "Mueve PicPocket a la carpeta Aplicaciones y vuelve a intentarlo.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
