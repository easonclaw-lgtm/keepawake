import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "ActivitySimulator")

@MainActor
final class ActivitySimulator {

    private var timer: Timer?
    private var isAnimating        = false
    private var lastBurstTime:     Date? = nil
    private var nextBurstDelay:    Double = 0
    private var burstsSinceSwitch: Int   = 0
    private var activityToken:     NSObjectProtocol?

    // Track the last time a REAL user input event was seen.
    // Using CGEventSource.secondsSinceLastEventType is unreliable here because
    // our own synthetic CGEvent posts reset that counter, causing the poll to
    // think the user returned active and wiping the simulation state every cycle.
    private var lastUserActivity: Date = Date()
    private var animationEndTime: Date = .distantPast   // cooldown after our own events
    private var eventMonitor: Any?

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }

        // Monitor real user input across all apps.
        // Guard: skip updates during animations AND for 0.5s after each animation
        // ends — synthetic CGEvents may still be in flight at that moment.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown,
                       .keyDown, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isAnimating,
                      Date().timeIntervalSince(self.animationEndTime) > 0.5
                else { return }
                self.lastUserActivity = Date()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        logger.info("ActivitySimulator started")
    }

    func stop() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        timer?.invalidate()
        timer = nil
        resetBurstState()
        releaseActivity()
        isAnimating = false
        logger.info("ActivitySimulator stopped")
    }

    // MARK: - Sleep prevention

    private func acquireActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "SyncAgent"
        )
        logger.info("Display sleep prevention acquired")
    }

    private func releaseActivity() {
        guard let token = activityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        activityToken = nil
        logger.info("Display sleep prevention released")
    }

    // MARK: - Poll

    private func poll() {
        let prefs = PreferencesManager.shared
        guard prefs.isEnabled, !isAnimating else { return }

        if prefs.scheduleEnabled && !prefs.isWithinSchedule() {
            releaseActivity()
            return
        }

        // Use our own activity timestamp — immune to our synthetic events
        let idle = Date().timeIntervalSince(lastUserActivity)

        guard idle >= prefs.idleThreshold else {
            releaseActivity()
            if lastBurstTime != nil { resetBurstState() }
            return
        }

        acquireActivity()

        if lastBurstTime == nil {
            lastBurstTime  = Date()
            nextBurstDelay = Double.random(in: 3...8)
            logger.info("Idle \(idle, privacy: .public)s — first burst in \(self.nextBurstDelay, privacy: .public)s")
            return
        }

        guard let last = lastBurstTime,
              Date().timeIntervalSince(last) >= nextBurstDelay else { return }

        guard prefs.mouseMovementEnabled || prefs.windowSwitchEnabled else {
            scheduleNextBurst(); return
        }

        performBurst(prefs: prefs)
    }

    private func resetBurstState() {
        lastBurstTime     = nil
        nextBurstDelay    = 0
        burstsSinceSwitch = 0
    }

    private func scheduleNextBurst() {
        lastBurstTime = Date()
        nextBurstDelay = Double.random(in: 0...1) < 0.10
            ? Double.random(in: 60...180)
            : Double.random(in: 15...50)
        logger.debug("Next burst in \(self.nextBurstDelay, privacy: .public)s")
    }

    // MARK: - Burst

    private func performBurst(prefs: PreferencesManager) {
        let r = Double.random(in: 0...1)
        let moveType: MoveType
        if      r < 0.40 { moveType = .smallTwitch }
        else if r < 0.80 { moveType = .normalSweep }
        else if r < 0.95 { moveType = .largeSweep  }
        else             { moveType = .doubleMove   }

        burstsSinceSwitch += 1
        let doSwitch = prefs.windowSwitchEnabled
            && burstsSinceSwitch >= 2
            && Double.random(in: 0...1) < 0.20
        if doSwitch { burstsSinceSwitch = 0 }

        logger.info("Burst: \(moveType.logName, privacy: .public)\(doSwitch ? " + CmdTab" : "")")
        scheduleNextBurst()

        isAnimating = true
        Task { @MainActor [weak self] in
            if prefs.mouseMovementEnabled {
                await self?.runMouseAnimation(type: moveType)
            }
            self?.isAnimating = false
            self?.animationEndTime = Date()   // start cooldown so our events don't self-trigger
            if doSwitch {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.35...0.90) * 1_000_000_000))
                self?.simulateCmdTab()
            }
        }
    }

    // MARK: - Move types

    private enum MoveType {
        case smallTwitch, normalSweep, largeSweep, doubleMove
        var logName: String {
            switch self {
            case .smallTwitch: return "smallTwitch"
            case .normalSweep: return "normalSweep"
            case .largeSweep:  return "largeSweep"
            case .doubleMove:  return "doubleMove"
            }
        }
    }

    private struct MoveSpec {
        var dist:      ClosedRange<CGFloat>
        var steps:     ClosedRange<Int>
        var bowFactor: ClosedRange<CGFloat>
        var jitter:    CGFloat
        var baseMs:    Double
    }

    private func spec(for type: MoveType) -> MoveSpec {
        switch type {
        case .smallTwitch: return MoveSpec(dist: 15...45,   steps: 12...22, bowFactor: 0.05...0.15, jitter: 2.5, baseMs: 0.017)
        case .normalSweep: return MoveSpec(dist: 80...180,  steps: 30...50, bowFactor: 0.10...0.35, jitter: 1.5, baseMs: 0.011)
        case .largeSweep:  return MoveSpec(dist: 180...350, steps: 40...60, bowFactor: 0.10...0.45, jitter: 1.0, baseMs: 0.009)
        case .doubleMove:  return MoveSpec(dist: 80...160,  steps: 28...45, bowFactor: 0.10...0.30, jitter: 1.5, baseMs: 0.011)
        }
    }

    // MARK: - Animation

    private func runMouseAnimation(type: MoveType) async {
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let W = screen.width, H = screen.height
        let margin: CGFloat = 80
        let s     = spec(for: type)
        let loc   = NSEvent.mouseLocation
        let start = CGPoint(x: loc.x, y: H - loc.y)

        await sweep(to: target(from: start, spec: s, W: W, H: H, margin: margin),
                    from: start, spec: s, W: W, H: H)

        if type == .doubleMove {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.4...1.2) * 1_000_000_000))
            let loc2  = NSEvent.mouseLocation
            let mid   = CGPoint(x: loc2.x, y: H - loc2.y)
            let s2    = spec(for: .smallTwitch)
            await sweep(to: target(from: mid, spec: s2, W: W, H: H, margin: margin),
                        from: mid, spec: s2, W: W, H: H)
        }
    }

    private func target(from start: CGPoint, spec s: MoveSpec,
                        W: CGFloat, H: CGFloat, margin: CGFloat) -> CGPoint {
        let d = CGFloat.random(in: s.dist)
        let a = CGFloat.random(in: 0...(2 * .pi))
        return CGPoint(
            x: (start.x + cos(a) * d).clamped(to: margin...(W - margin)),
            y: (start.y + sin(a) * d).clamped(to: margin...(H - margin))
        )
    }

    private func sweep(to target: CGPoint, from start: CGPoint,
                       spec s: MoveSpec, W: CGFloat, H: CGFloat) async {
        let dx   = target.x - start.x
        let dy   = target.y - start.y
        let len  = max(hypot(dx, dy), 1)
        let sign: CGFloat = Double.random(in: 0...1) < 0.5 ? 1 : -1
        let bow  = CGFloat.random(in: s.bowFactor) * len * sign
        let ctrl = CGPoint(
            x: (start.x + target.x) / 2 + (-dy / len) * bow,
            y: (start.y + target.y) / 2 + ( dx / len) * bow
        )
        let steps = Int.random(in: s.steps)
        let src   = CGEventSource(stateID: .hidSystemState)

        for step in 0...steps {
            let t     = CGFloat(step) / CGFloat(steps)
            let eased = (1 - cos(t * .pi)) / 2
            let mt    = 1 - eased
            let x     = mt*mt*start.x + 2*mt*eased*ctrl.x + eased*eased*target.x
            let y     = mt*mt*start.y + 2*mt*eased*ctrl.y + eased*eased*target.y
            let jAmp  = sin(t * .pi) * s.jitter * CGFloat.random(in: 0...1)
            let point = CGPoint(
                x: (x + jAmp * CGFloat.random(in: -1...1)).clamped(to: 0...W),
                y: (y + jAmp * CGFloat.random(in: -1...1)).clamped(to: 0...H)
            )
            guard let evt = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                                    mouseCursorPosition: point, mouseButton: .left) else { return }
            evt.post(tap: .cghidEventTap)

            let speedCurve = 1.0 + 0.6 * (1.0 - sin(t * .pi))
            let delay      = s.baseMs * speedCurve * Double.random(in: 0.7...1.3)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    // MARK: - Cmd+Tab

    private func simulateCmdTab() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true),
            let tabDown = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true),
            let tabUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false),
            let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        else {
            logger.error("Failed to create CGEvents for Cmd+Tab")
            return
        }

        cmdDown.flags = .maskCommand
        tabDown.flags = .maskCommand
        tabUp.flags   = .maskCommand
        cmdUp.flags   = []

        cmdDown.post(tap: .cghidEventTap)
        tabDown.post(tap: .cghidEventTap)

        Task { @MainActor in
            // Hold briefly like a real keystroke, then release
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.08...0.15) * 1_000_000_000))
            tabUp.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 50_000_000)   // 50ms
            cmdUp.post(tap: .cghidEventTap)
            logger.info("Cmd+Tab posted")
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
