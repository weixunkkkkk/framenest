import Foundation

public struct WorkProgress: Sendable {
    public enum Phase: Sendable { case scanning, recognizing, organizing }
    public let phase: Phase
    public let completed: Int
    public let total: Int?
    public let message: String
}

/// Cancellation and throttling are shared across the worker and GUI actor.
public final class OperationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var lastUpdate: TimeInterval = -.infinity
    private var lastPhase: WorkProgress.Phase?
    private let callback: @Sendable (WorkProgress) -> Void

    public init(onProgress: @escaping @Sendable (WorkProgress) -> Void = { _ in }) { callback = onProgress }
    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
    public func checkpoint() throws { if isCancelled { throw CancellationError() } }

    public func report(_ phase: WorkProgress.Phase, completed: Int, total: Int?, message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let deliver = lock.withLock {
            guard !cancelled else { return false }
            guard lastPhase != phase || now - lastUpdate >= 0.15 || (total != nil && completed == total) else { return false }
            lastUpdate = now; lastPhase = phase
            return true
        }
        if deliver { callback(WorkProgress(phase: phase, completed: completed, total: total, message: message)) }
    }
}
