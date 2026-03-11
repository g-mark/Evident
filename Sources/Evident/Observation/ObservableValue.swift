//
//  ObservableValue.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Foundation

/// A value that can be observed for changes - in whole or in part.
///
/// An `ObservableValue` is optimized for `Equatable` conformance.
/// If observing an `Equatable` value, notifications will only be sent when the value _changes_.
/// Otherwise, notifications will be sent any time the value _is set_.
///
/// Usage:
/// ```swift
/// struct User: Equatable {
///     let name: String = ""
///     let number: Int = 0
/// }
///
/// let user = ObservableValue(initialValue: User())
///
/// let cancellable = await user.observe(\.name) { name in
///     print("got name: \(name)")
/// }
///
/// await user.set(\.name, value: "Pat")
/// ```
public actor ObservableValue<Value: Sendable> {
    
    public private(set) var value: Value {
        didSet { sendNotifications(oldValue, value) }
    }
    
    public init(initialValue: Value) {
        value = initialValue
    }
    
    /// Set the value.
    public func set(value: Value) async {
        self.value = value
    }
    
    /// Set a part of the value.
    public func set<T>(_ keyPath: WritableKeyPath<Value, T>, value: T) async {
        self.value[keyPath: keyPath] = value
    }
    
    /// Observe the (non-`Equatable`) value using an async closure that receives the old and new values.
    ///
    /// The `handler` will be called with the current value right away (`oldValue` will be `nil`).
    /// The `handler` will be called whenever the value _is set_.
    ///
    /// ```swift
    /// let heldValue = ObservableValue(initialValue: "Hello")
    ///
    /// let cancellable = heldValue.observe { oldValue, newValue in
    ///     // this is an async closure
    ///     print("Got value: \(newValue) (was \(oldValue))")
    /// }     
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value?, Value) async -> Void
    ) -> AnyCancellableAsync {
        register(\.self, isDifferent: { _, _ in true }) { old, new in
            await handler(old, new)
        }
    }
    
    /// Observe the (`Equatable`) value using an async closure that receives the old and new values.
    ///
    /// The `handler` will be called with the current value right away (`oldValue` will be `nil`).
    /// The `handler` will be called whenever the value _changes_.
    ///
    /// ```swift
    /// let heldValue = ObservableValue(initialValue: "Hello")
    ///
    /// let cancellable = heldValue.observe { oldValue, newValue in
    ///     // this is an async closure
    ///     print("Got value: \(newValue) (was \(oldValue))")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value?, Value) async -> Void
    ) -> AnyCancellableAsync where Value: Equatable {
        register(\.self, isDifferent: { a, b in a != b }) { old, new in
            await handler(old, new)
        }
    }
    
    /// Observe the (non-`Equatable`) value using an async closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _is set_.
    ///
    /// ```swift
    /// let heldValue = ObservableValue(initialValue: "Hello")
    ///
    /// let cancellable = heldValue.observe { value in
    ///     // this is an async closure
    ///     print("Got value: \(value)")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value) async -> Void
    ) -> AnyCancellableAsync {
        register(\.self, isDifferent: { _, _ in true }) { _, new in
            await handler(new)
        }
    }
    
    /// Observe the (`Equatable`) value using an async closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _changes_.
    ///
    /// ```swift
    /// let heldValue = ObservableValue(initialValue: "Hello")
    ///
    /// let cancellable = heldValue.observe { value in
    ///     // this is an async closure
    ///     print("Got value: \(value)")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value) async -> Void
    ) -> AnyCancellableAsync where Value: Equatable {
        register(\.self, isDifferent: { a, b in a != b }) { _, new in
            await handler(new)
        }
    }
    
    /// Observe a non-`Equatable` part of the value using an async closure.
    ///
    /// The `handler` will be called with the current property value right away.
    /// The `handler` will be called whenever the **value or the property** _is set_.
    ///
    /// ```swift
    /// struct Something { ... } // <- not Equatable>
    /// struct Person {
    ///     var thing: Something = Something()
    ///     var number: Int = 0
    /// }
    ///
    /// let heldValue = ObservableValue(initialValue: Person())
    ///
    /// let cancellable = heldValue.observe(\.thing) { thing in
    ///     // this is an async closure
    ///     print("Got thing: \(thing)")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe<T: Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellableAsync {
        register(keyPath, isDifferent: { _, _ in true }) { _, new in
            await handler(new)
        }
    }
    
    /// Observe an `Equatable` part of the value using an async closure.
    ///
    /// The `handler` will be called with the current property value right away.
    /// The `handler` will be called whenever the property value _changes_.
    ///
    /// ```swift
    /// struct Person {
    ///     var name: String = ""
    ///     var number: Int = 0
    /// }
    ///
    /// let heldValue = ObservableValue(initialValue: Person())
    ///
    /// let cancellable = heldValue.observe(\.name) { name in
    ///     // this is an async closure
    ///     print("Got name: \(name)")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe<T: Equatable & Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellableAsync {
        register(keyPath, isDifferent: { a, b in a != b }) { _, new in
            await handler(new)
        }
    }
    
    // MARK: - Implementation details
    
    // Observations are grouped by KeyPath for efficiency in calculating & checking values.
    private var keyedObservations: [PartialKeyPath<Value>: any Notifiable<Value>] = [:]
    
    private typealias Handler<T> = @Sendable (T?, T) async -> Void
    
    /// Holds a collection of observations for a single key path.
    private struct KeyObservations<ObservedValue: Sendable>: Notifiable {
        private let keyPath: KeyPath<Value, ObservedValue> & Sendable
        private let isDifferent: @Sendable (ObservedValue, ObservedValue) -> Bool
        
        var handlers: [UUID: Handler<ObservedValue>] = [:]
        
        init(
            _ keyPath: KeyPath<Value, ObservedValue> & Sendable,
            _ isDifferent: @escaping @Sendable (ObservedValue, ObservedValue) -> Bool
        ) {
            self.keyPath = keyPath
            self.isDifferent = isDifferent
        }
        
        func notify(_ oldValue: Value, _ newValue: Value) async {
            let oldPart = oldValue[keyPath: keyPath]
            let newPart = newValue[keyPath: keyPath]
            guard isDifferent(oldPart, newPart) else { return }
            for handler in handlers.values {
                await handler(oldPart, newPart)
            }
        }
    }
    
    /// Helper to allow for `nonisolated` value observations
    private struct Registration<T: Sendable>: Cancellable {
        private let _cancel: @Sendable () -> Void
        
        init(
            _ observable: ObservableValue<Value>,
            for keyPath: KeyPath<Value, T> & Sendable,
            isDifferent: @escaping @Sendable (T, T) -> Bool,
            _ handler: @escaping Handler<T>
        ) {
            let id = UUID()
            let task = Task.detached {
                await observable.addHandler(id: id, for: keyPath, isDifferent: isDifferent, handler)
            }
            _cancel = {
                Task.detached {
                    _ = await task.result
                    await observable.release(id, at: keyPath)
                }
            }
        }
        
        func cancel() { _cancel() }
    }
    
    private nonisolated func register<T: Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        isDifferent: @escaping @Sendable (T, T) -> Bool,
        handler: @escaping @Sendable (T?, T) async -> Void
    ) -> AnyCancellableAsync {
        AnyCancellableAsync(
            Registration(self, for: keyPath, isDifferent: isDifferent, handler)
        )
    }
    
    /// Add a single observation for the specified `keyPath`.
    ///
    /// Calls the `handler` with the current value.
    ///
    /// - Returns: An `AnyCancellableAsync` object for managing the observation.
    private func addHandler<T: Sendable>(
        id: UUID,
        for keyPath: KeyPath<Value, T> & Sendable,
        isDifferent: @escaping @Sendable (T, T) -> Bool,
        _ handler: @escaping Handler<T>
    ) {
        var observations = (keyedObservations[keyPath] as? KeyObservations<T>) ?? KeyObservations(keyPath, isDifferent)
        observations.handlers[id] = handler
        keyedObservations[keyPath] = observations
        Task.detached { [keyPath, value] in
            await handler(nil, value[keyPath: keyPath])
        }
    }
    
    /// Remove an observation.
    private func release<T: Sendable>(_ id: UUID, at keyPath: KeyPath<Value, T>) async {
        guard var observations = keyedObservations[keyPath] as? KeyObservations<T> else {
            return
        }
        observations.handlers.removeValue(forKey: id)
        if observations.handlers.isEmpty {
            keyedObservations.removeValue(forKey: keyPath)
        }
        else {
            keyedObservations[keyPath] = observations
        }
    }
    
    /// The stored value has changed, send notifications to all affected observations.
    private func sendNotifications(_ oldValue: Value, _ newValue: Value) {
        let observations = keyedObservations.values.map { $0 }
        Task {
            for keyObservations in observations {
                await keyObservations.notify(oldValue, newValue)
            }
        }
    }
}

/// Something that can notify observers of new values.
private protocol Notifiable<Value>: Sendable {
    associatedtype Value: Sendable
    func notify(_ oldValue: Value, _ newValue: Value) async
}
