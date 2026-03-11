//
//  DebouncedWork.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Foundation

/// Coalesces rapid async work requests, executing only after a period of inactivity.
///
/// When multiple pieces of work are enqueued in quick succession, only the last one
/// is executed — after the threshold has elapsed with no new work.
///
/// ```swift
/// let debouncer = DebouncedWork(threshold: 1.0)
/// await debouncer.enqueue { await save(data) }
/// // If enqueue is called again within 1 second, the previous work is replaced.
/// ```
///
/// > Note: When a `DebouncedWork` is released, pending work will _still_ execute.
/// > If you want to also cancel any pending work, call `cancel()` before releasing the instance.
public actor DebouncedWork {

    /// Creates a debouncer with the specified inactivity threshold.
    ///
    /// - Parameter threshold: The number of seconds to wait after the last enqueue before executing the work.
    ///   A value of `0` executes work immediately without debouncing.
    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }
    
    /// Enqueues work to be executed after the debounce threshold.
    ///
    /// If work is already pending, it is replaced with the new work and the timer resets.
    ///
    /// - Parameter work: The async closure to execute after the threshold elapses.
    public func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        guard self.threshold > 0 else {
            await work()
            return
        }
        timer?.cancel()
        timer = nil
        timedWork = work
        createTimer()
    }
    
    /// Immediately executes any pending work, bypassing the debounce timer.
    public func flushPendingWork() async {
        guard let timedWork else { return }
        
        timer?.cancel()
        timer = nil
        
        self.timedWork = nil
        await timedWork()
    }
    
    /// Cancels any pending work and stops the debounce timer.
    public func cancel() async {
        timedWork = nil
        timer?.cancel()
        timer = nil
    }
    
    // MARK: - Implementation details
    
    private let threshold: TimeInterval
    private var timer: Task<Void, Error>?
    private var timedWork: (@Sendable () async -> Void)?
    
    private func createTimer() {
        timer = Task.detached { [threshold] in
            try await Task.sleep(for: .seconds(threshold))
            await self.flushPendingWork()
        }
    }
    
    deinit {
        timer?.cancel()
    }
}
