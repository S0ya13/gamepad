import CoreHaptics
import Foundation

/// Plays a game's controller vibration on the Taptic Engine. Main thread only.
final class RumblePlayer {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var expiry: DispatchWorkItem?

    /// Heavy and light motor levels (0...255). The Mac repeats them every 100 ms while they run;
    /// without a repeat the vibration stops by itself, so a lost "stop" can't buzz forever.
    func play(low: UInt8, high: UInt8) {
        expiry?.cancel()
        let total = Float(low) + Float(high)
        guard total > 0, CHHapticEngine.capabilitiesForHardware().supportsHaptics, let player = start() else {
            stop()
            return
        }
        // The heavy motor feels dull, the light one buzzy: mix sharpness by their share.
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(max(low, high)) / 255, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(high) / total - 0.5, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
        let item = DispatchWorkItem { [weak self] in self?.stop() }
        expiry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func stop() {
        expiry?.cancel()
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// A looping full-strength buzz whose strength the dynamic parameters scale down.
    private func start() -> CHHapticAdvancedPatternPlayer? {
        if let player { return player }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                // iOS stops the engine in the background or on audio interruptions; start over next time.
                engine.stoppedHandler = { [weak self] _ in DispatchQueue.main.async { self?.reset() } }
                engine.resetHandler = { [weak self] in DispatchQueue.main.async { self?.reset() } }
                self.engine = engine
            }
            try engine?.start()
            let buzz = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ], relativeTime: 0, duration: 30)
            let player = try engine?.makeAdvancedPlayer(with: CHHapticPattern(events: [buzz], parameters: []))
            player?.loopEnabled = true
            try player?.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return player
        } catch {
            reset()
            return nil
        }
    }

    private func reset() {
        player = nil
        engine = nil
    }
}
