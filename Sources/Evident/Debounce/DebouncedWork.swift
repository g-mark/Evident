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
        timer?.cancel()
        timer = nil
        timedWork = work
        createTimer()
    }
    
    public func flushPendingWork() async {
        guard let timedWork else { return }
        
        timer?.cancel()
        timer = nil
        
        self.timedWork = nil
        await timedWork()
    }
    
    public func cancel() async {
        timedWork = nil
        timer?.cancel()
        timer = nil
    }
    
    // MARK: - Implementation details
    
    private let threshold: TimeInterval
    private var timer: Task<Void, Error>?
    private var timedWork: Work?
    
    private func createTimer() {
        timer = Task.detached { [threshold] in
            try await Task.sleep(for: .seconds(threshold))
            await self.flushPendingWork()
        }
    }
}
