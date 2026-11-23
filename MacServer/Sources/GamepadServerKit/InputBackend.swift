import SharedProtocol

/// All calls happen on the main queue.
public protocol InputBackend: AnyObject {
    /// Latest accepted (in-order) packet.
    func apply(_ packet: GamepadPacket)
    /// Release every key and zero the sticks (client lost, Ctrl+C).
    func reset()
}
