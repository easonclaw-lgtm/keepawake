import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "ActivitySimulator")

@MainActor
final class ActivitySimulator {

    private var timer: Timer?
    private var triggerCount: Int = 0
    private var isAnimating = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        logger.info("ActivitySimulator started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        triggerCount = 0
        isAnimating = false
        logger.info("ActivitySimulator stopped")
    }

    // MARK: - Poll

    private func poll() {
        let prefs = PreferencesManager.shared
        guard prefs.isEnabled, !isAnimating else { return }

        if prefs.scheduleEnabled && !prefs.isWithinSchedule() { return }

        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        guard idle >= prefs.idleThreshold else { return }

        logger.info("Idle \(idle, privacy: .public)s — simulating activity")

        triggerCount += 1
        let doCmdTab = (triggerCount % 4 == 0)

        isAnimating = true
        Task { @MainActor [weak self] in
            await self?.runMouseAnimation()
            self?.isAnimating = false
            if doCmdTab {
                self?.simulateCmdTab()
            }
        }
    }

    // MARK: - Human-like mouse animation

    private func runMouseAnimation() async {
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let W = screen.width
        let H = screen.height
        let margin: CGFloat = 80

        // Current position, converted from AppKit (Y-up) to CG (Y-down)
        let loc = NSEvent.mouseLocation
        let start = CGPoint(x: loc.x, y: H - loc.y)

        // Pick a target 80–220px away in a random direction, clamped to screen
        let dist  = CGFloat.random(in: 80...220)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let target = CGPoint(
            x: (start.x + cos(angle) * dist).clamped(to: margin...(W - margin)),
            y: (start.y + sin(angle) * dist).clamped(to: margin...(H - margin))
        )

        // Bezier control point: bow perpendicular to the line
        let dx  = target.x - start.x
        let dy  = target.y - start.y
        let len = max(hypot(dx, dy), 1)
        let bow = CGFloat.random(in: -0.35...0.35) * len   // ±35% of travel distance
        let control = CGPoint(
            x: (start.x + target.x) / 2 + (-dy / len) * bow,
            y: (start.y + target.y) / 2 + ( dx / len) * bow
        )

        let steps = Int.random(in: 30...55)

        for step in 0...steps {
            let t      = CGFloat(step) / CGFloat(steps)
            let eased  = (1 - cos(t * .pi)) / 2   // sine ease-in/out

            // Quadratic bezier position
            let mt = 1 - eased
            let x  = mt*mt*start.x   + 2*mt*eased*control.x   + eased*eased*target.x
            let y  = mt*mt*start.y   + 2*mt*eased*control.y   + eased*eased*target.y

            // Micro-jitter: peaks in the middle, zero at endpoints
            let jitterAmp = sin(t * .pi) * CGFloat.random(in: 0...1.8)
            let point = CGPoint(x: x + jitterAmp * CGFloat.random(in: -1...1),
                                y: y + jitterAmp * CGFloat.random(in: -1...1))

            let result = CGWarpMouseCursorPosition(point)
            if result != .success {
                logger.warning("CGWarpMouseCursorPosition failed: \(result.rawValue)")
                return
            }

            // Step delay: longer at start/end (ease), shorter in the middle
            // Base ~11ms, ±30% random variation, ×1.5 near endpoints
            let speedCurve = 1.0 + 0.6 * (1.0 - sin(t * .pi))  // 1.6 at ends → 1.0 at middle
            let delayMs    = 0.011 * speedCurve * Double.random(in: 0.7...1.3)
            try? await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000_000))
        }
    }

    // MARK: - Cmd+Tab

    private func simulateCmdTab() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for Cmd+Tab")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Brief hold before releasing, like a real keypress
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            logger.info("Cmd+Tab posted")
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
