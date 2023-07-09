//
//  MessageQueue.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Combine

/// General purpose message queue, supporting cancellable observations.
public actor MessageQueue<Value> {
    
    public typealias Handler = @Sendable (Value) async -> Void
    
    public init() {
    }
    
    /// Dispatch a message to all registered consumers.
    nonisolated public func dispatch(_ value: Value) {
        Task {
            await self.emit(value)
        }
    }
    
    /// Subscribe to messages on this `MessageQueue`.
    ///
    /// Registering a consumer in this way is _not_ unsubscribeable.
    ///
    /// Use this when the `MessageQueue` instance lifetime is shorter or the same as your consumer's.
    nonisolated public func observe(_ handler: @escaping Handler) {
        Task {
            await self.addHandler(handler)
        }
    }
    
    /// Subscribe to messages on this `MessageQueue`.
    ///
    /// The observation is cancellable using the returned `AnyCancellable` object.
    ///
    /// Use this when the `MessageQueue` instance is long lived, and your consumer's lifetime is short.
    ///
    /// - Returns: An `AnyCancellable` which can be used to cancel the observation.
    public func observe(_ handler: @escaping Handler) async -> AnyCancellable {
        let id = self.addHandler(handler)
        return AnyCancellable { [weak self] in
            guard let self else { return }
            Task.detached {
                await self.removeHandler(id)
            }
        }
    }
    
    // MARK: - Implementation details
    
    private typealias ObservationId = UUID
    
    private var handlers: [ObservationId: Handler] = [:]
    
    private func emit(_ value: Value) async {
        Task.detached { [handlers] in
            for handler in handlers.values {
                await handler(value)
            }
        }
    }
    
    @discardableResult
    private func addHandler(_ handler: @escaping Handler) -> ObservationId {
        let id = ObservationId()
        handlers[id] = handler
        return id
    }
    
    private func removeHandler(_ id: ObservationId) async {
        handlers.removeValue(forKey: id)
    }
    
    #if DEBUG
    // For unit test support
    func handlerCount() async -> Int {
        handlers.count
    }
    #endif
}

