//
//  ManagedValue.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Foundation
import Combine

/// Read-only, optionally cached observable value, with controlled mutability via special "setter" object.
///
/// Initialization from cache / defaultValue is lazy, meaning initialization occurs when an observation is created.
public actor ManagedValue<Value> {
    
    /// Creates a `ManagedValue` (read-only) instance, and a `ManagedValue.Setter` instance for updating values.
    public static func create(
        cache: (any SingleValueCache<Value>)? = nil,
        defaultValue: @escaping @autoclosure @Sendable () -> Value
    ) -> (ManagedValue<Value>, ManagedValue<Value>.Setter) {
        let managedValue = ManagedValue(cache: cache, defaultValue: defaultValue)
        return (managedValue, Setter(managedValue))
    }
    
    public var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                queue { data in
                    continuation.resume(returning: await data.value)
                }
            }
        }
    }
    
    /// Observe the (non-`Equatable`) value using a closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _is set_.
    ///
    /// - Returns: An `AnyCancellable` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellable`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value) async -> Void
    ) -> AnyCancellable {
        AnyCancellable(Registration(self) { data in
            data.observe(handler: handler)
        })
    }
    
    /// Observe the (`Equatable`) value using a closure.
    ///
    /// The `handler` will be called with the current value right away.
    /// The `handler` will be called whenever the value _changes_.
    ///
    /// - Returns: An `AnyCancellable` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellable`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe(
        handler: @escaping @Sendable (Value) async -> Void
    ) -> AnyCancellable where Value: Equatable {
        AnyCancellable(Registration(self) { data in
            data.observe(handler: handler)
        })
    }
    
    /// Observe a non-`Equatable` part of the value using a closure.
    ///
    /// The `handler` will be called with the current property value right away.
    /// The `handler` will be called whenever the **value or the property** _is set_.
    ///
    /// - Returns: An `AnyCancellable` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellable`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe<T>(
        _ keyPath: KeyPath<Value, T>,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable {
        AnyCancellable(Registration(self) { data in
            data.observe(keyPath, handler: handler)
        })
    }
    
    /// Observe an `Equatable` part of the value using a closure.
    ///
    /// The `handler` will be called with the current property value right away.
    /// The `handler` will be called whenever the property value _changes_.
    ///
    /// - Returns: An `AnyCancellable` object used to cancel the observation.
    ///            The observation must be cancelled when no longer needed,
    ///            either implicitly by releasing the `AnyCancellable`, or explicitly by calling   `cancel()` on it.
    public nonisolated func observe<T: Equatable>(
        _ keyPath: KeyPath<Value, T>,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable {
        AnyCancellable(Registration(self) { data in
            data.observe(keyPath, handler: handler)
        })
    }
    
    /// Provides write access to the `ManagedValue`.
    ///
    /// Only available when instantiating a `ManagedValue` through the static `create` function.
    public actor Setter {
        
        /// Set the value.
        public func set(value: Value) async {
            await managedValue.set(value: value)
        }
        
        /// Set a part of the value.
        public func set<T>(_ keyPath: WritableKeyPath<Value, T>, value: T) async {
            await managedValue.set(keyPath, value: value)
        }
        
        /// End _all_ observations; return to an uninitialized state.
        public func detach() async {
            await managedValue.detach()
        }
        
        private let managedValue: ManagedValue
        
        fileprivate init(_ managedValue: ManagedValue) {
            self.managedValue = managedValue
        }
    }
    
    // MARK: Implementation details
    
    private var state: State
    private let cache: (any SingleValueCache<Value>)?
    private let defaultValue: @Sendable () -> Value
    
    private typealias Operation = @Sendable (ObservableValue<Value>) async -> Void
    
    private enum State {
        case uninitialized
        case initializing([Operation])
        case initialized(ObservableValue<Value>, AnyCancellable?)
    }
    
    /// Helper to allow for `nonisolated` value observations
    private final class Registration: Cancellable {
        var cancellable: AnyCancellable?
        var _cancel: (() -> Void)?
        func cancel() { _cancel?() }
        
        init(_ managed: ManagedValue<Value>, _ op: @escaping (ObservableValue<Value>) -> AnyCancellable) {
            _cancel = { self.cancellable?.cancel() }
            Task.detached {
                await managed.queue { data in
                    self.cancellable = op(data)
                }
            }
        }
    }
    
    private init(cache: (any SingleValueCache<Value>)?, defaultValue: @escaping @autoclosure @Sendable () -> Value) {
        self.cache = cache
        self.defaultValue = defaultValue
        state = .uninitialized
    }
    
    private init(cache: (any SingleValueCache<Value>)?, defaultValue: @escaping @Sendable () -> Value) {
        self.cache = cache
        self.defaultValue = defaultValue
        state = .uninitialized
    }
    
    /// Set the value.
    private func set(value: Value) async {
        if case .uninitialized = state {
            state = .initializing([])
            await self.handleInitialValue(value)
            return
        }
        await withCheckedContinuation { continuation in
            queue { data in
                await data.set(value: value)
                continuation.resume()
            }
        }
    }
    
    /// Set a part of the value.
    private func set<T>(_ keyPath: WritableKeyPath<Value, T>, value: T) async {
        await withCheckedContinuation { continuation in
            queue { data in
                await data.set(keyPath, value: value)
                continuation.resume()
            }
        }
    }
    
    /// End _all_ observations; return to an uninitialized state.
    private func detach() async {
        let oldState = state
        state = .uninitialized
        await cache?.flushPendingWork()
        
        // Let all pending operations run, so as not to create leaks
        if case let .initializing(operations) = oldState {
            let data = ObservableValue<Value>(initialValue: defaultValue())
            for operation in operations {
                await operation(data)
            }
        }
    }
    
    private func queue(operation: @escaping Operation) {
        switch state {
            
        case .uninitialized:
            state = .initializing([operation])
            getInitialValue()
            
        case .initializing(let operations):
            state = .initializing(operations + [operation])
            
        case .initialized(let data, _):
            Task.detached {
                await operation(data)
            }
        }
    }
    
    private func getInitialValue() {
        Task.detached {
            if let cache = self.cache, let (value, _) = await cache.retrieve() {
                await self.handleInitialValue(value)
            }
            else {
                await self.handleInitialValue(self.defaultValue())
            }
        }
    }
    
    private func handleInitialValue(_ value: Value) async {
        let data = ObservableValue<Value>(initialValue: value)
        var cancellable: AnyCancellable?
        if cache != nil {
            cancellable = data.observe { [weak self] value in
                await self?.cache?.store(value)
            }
        }
        
        guard case let .initializing(operations) = state else { return }
        
        state = .initialized(data, cancellable)
        for operation in operations {
            await operation(data)
        }
    }
}
