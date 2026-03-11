//
//  MessageQueue.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

/// General purpose message queue, supporting cancellable observations.
///
/// Thread safe, one-to-many messaging.
///
/// Dispatch from anywhere:
/// ```swift
/// messageQueue.dispatch("hello")
/// ```
///
/// Set up a forever observation:
/// ```swift
/// messageQueue.observe { message in
///     print(message)
/// }
/// ```
///
/// Set up a cancellable observation:
/// ```swift
/// class Thingy {
///     private var cancellable: AnyCancellableAsync
///
///     init() {
///         cancellable = messageQueue.observe {
///             print(messaage)
///         }
///     }
/// }
/// ```
public final class MessageQueue<Message: Sendable>: Sendable {
    
    /// The type of closure used to handle dispatched messages.
    public typealias Handler = @Sendable (Message) async -> Void

    /// Creates a new, empty message queue with no observers.
    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Message.self)
        self.continuation = continuation
        self.observations = Observers(stream: stream)
    }
    
    /// Dispatch a message to all registered consumers.
    public func dispatch(_ message: Message) {
        continuation.yield(message)
    }
    
    /// Subscribe to messages on this `MessageQueue`.
    ///
    /// Registering a consumer in this way is _not_ unsubscribeable.
    ///
    /// Use this when the `MessageQueue` instance lifetime is shorter or the same as your consumer's.
    ///
    /// > Ordering is _not_ guaranteed when calling this version of `observe` immediately followed by `dispatch`,
    /// > like this:
    /// > ```swift
    /// > messageQueue.observe { print($0) }
    /// > messageQueue.dispatch("hello")
    /// > ```
    /// > Because this version of `observe` is `nonisolated` and can be called from any context, it necessarily
    /// > needs to make an async hop, and since `dispatch` needs to do the same, the observation _may_ actually
    /// > occur _after_ the message is dispatched.
    public func observe(_ handler: @escaping Handler) {
        Task {
            await observations.addHandler(handler)
        }
    }
    
    /// Subscribe to messages on this `MessageQueue`.
    ///
    /// The observation is cancellable using the returned `AnyCancellableAsync` object.
    ///
    /// Use this when the `MessageQueue` instance is long lived, and your consumer's lifetime is short.
    ///
    /// - Returns: An `AnyCancellableAsync` which can be used to cancel the observation.
    public func observe(_ handler: @escaping Handler) async -> AnyCancellableAsync {
        let id = await observations.addHandler(handler)
        return AnyCancellableAsync { [weak self] in
            guard let self else { return }
            Task.detached {
                await self.observations.removeHandler(id)
            }
        }
    }
    
    // MARK: - Implementation details
    
    private let continuation: AsyncStream<Message>.Continuation
    
    private let observations: Observers
    
    private actor Observers {
        
        var handlers: [UUID: Handler] = [:]
        private var task: Task<Void, Never>?
        private let stream: AsyncStream<Message>
        
        init(stream: AsyncStream<Message>) {
            self.stream = stream
        }
        
        deinit {
            task?.cancel()
        }
        
        private func emit(_ message: Message) async {
            await withTaskGroup { group in
                for handler in handlers.values {
                    group.addTask {
                        await handler(message)
                    }
                }
            }
        }
        
        @discardableResult
        func addHandler(_ handler: @escaping Handler) -> UUID {
            setUpTask()
            let id = UUID()
            handlers[id] = handler
            return id
        }
        
        func removeHandler(_ id: UUID) async {
            handlers.removeValue(forKey: id)
        }
        
        func setUpTask() {
            guard task == nil else { return }
            self.task = Task {
                for await message in stream {
                    await emit(message)
                }
            }
        }
    }
    
#if DEBUG
    // For unit test support
    func handlerCount() async -> Int {
        await observations.handlers.count
    }
#endif
}
