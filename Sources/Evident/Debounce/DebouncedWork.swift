//
//  DebouncedWork.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Foundation

public actor DebouncedWork {
    
    public typealias Work = @Sendable () async -> Void
    
    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }
    
    public func enqueue(_ work: @escaping Work) async {
        timer?.invalidate()
        timer = nil
        timedWork = work
        timer = await createTimer().timer
    }
    
    public func flushPendingWork() async {
        guard let timedWork else { return }
        
        timer?.invalidate()
        timer = nil
        
        self.timedWork = nil
        await timedWork()
    }
    
    // MARK: - Implementation details
    
    private let threshold: TimeInterval
    private var timer: Timer?
    private var timedWork: Work?
    
    private struct WrappedTimer { let timer: Timer }
    
    @MainActor
    private func createTimer() -> WrappedTimer {
        WrappedTimer(
            timer: Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { _ in
                Task.detached { await self.flushPendingWork() }
            }
        )
    }
}
