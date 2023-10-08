//
//  DebouncedWork.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Foundation

public actor DebouncedWork {
    
    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }
    
    public func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        timer?.invalidate()
        timer = await makeTimer(for: work).timer
    }
    
    // MARK: - Implementation details
    
    private let threshold: TimeInterval
    private var timer: Timer?
    
    @MainActor
    private func makeTimer(for work: @escaping @Sendable () async -> Void) -> WrappedTimer {
        WrappedTimer(
            timer: Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { _ in
                Task { await work() }
            }
        )
    }
    
    /// Timer isn't Sendable, so need to wrap it
    private struct WrappedTimer {
        let timer: Timer
    }
}
