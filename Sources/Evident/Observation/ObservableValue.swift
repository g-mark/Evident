//
//  ObservableValue.swift
//  Evident
//

import Foundation

/// A read-only view of an `ObservableValueStore` - supports observation but not mutation.
public protocol ObservableValue<Value>: Sendable {

    associatedtype Value: Sendable


    /// Observe a non-`Equatable` part of the value using an async closure that receives the old and new values..
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
    /// let heldValue = ObservableValueStore(initialValue: Person())
    ///
    /// let cancellable = heldValue.observe(\.thing) { oldThing, thing in
    ///     // this is an async closure
    ///     print("Got thing: \(thing) (was \(oldThing))")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    nonisolated func observe<T: Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T?, T) async -> Void
    ) -> AnyCancellableAsync


    /// Observe an `Equatable` part of the value using an async closure that receives the old and new values..
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
    /// let heldValue = ObservableValueStore(initialValue: Person())
    ///
    /// let cancellable = heldValue.observe(\.name) { oldName, newName in
    ///     // this is an async closure
    ///     print("Got name: \(oldName) -> \(newName)")
    /// }
    /// ```
    ///
    /// - Returns: An `AnyCancellableAsync` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellableAsync`, or explicitly by calling   `cancel()` on it.
    nonisolated func observe<T: Equatable & Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T?, T) async -> Void
    ) -> AnyCancellableAsync
}

extension ObservableValue {

    /// Observe a non-`Equatable` part of the value using an async closure..
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
    /// let heldValue = ObservableValueStore(initialValue: Person())
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
    nonisolated func observe<T: Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellableAsync {
        observe(keyPath) { _, new in await handler(new) }
    }

    /// Observe an `Equatable` part of the value using an async closure..
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
    /// let heldValue = ObservableValueStore(initialValue: Person())
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
    nonisolated func observe<T: Equatable & Sendable>(
        _ keyPath: KeyPath<Value, T> & Sendable,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellableAsync {
        observe(keyPath) { _, new in await handler(new) }
    }

    /// Observe the (non-`Equatable`) value using an async closure that receives the old and new values.
    ///
    /// The `handler` will be called with the current value right away (`oldValue` will be `nil`).
    /// The `handler` will be called whenever the value _is set_.
    ///
    /// ```swift
    /// let heldValue = ObservableValueStore(initialValue: "Hello")
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
        observe(\.self, handler: handler)
    }

    /// Observe the (non-`Equatable`) value using an async closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _is set_.
    ///
    /// ```swift
    /// let heldValue = ObservableValueStore(initialValue: "Hello")
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
        observe(\.self, handler: handler)
    }
}

extension ObservableValue where Value: Equatable {

    /// Observe the (`Equatable`) value using an async closure that receives the old and new values.
    ///
    /// The `handler` will be called with the current value right away (`oldValue` will be `nil`).
    /// The `handler` will be called whenever the value _changes_.
    ///
    /// ```swift
    /// let heldValue = ObservableValueStore(initialValue: "Hello")
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
        observe(\.self, handler: handler)
    }

    /// Observe the (`Equatable`) value using an async closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _changes_.
    ///
    /// ```swift
    /// let heldValue = ObservableValueStore(initialValue: "Hello")
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
        observe(\.self, handler: handler)
    }
}
