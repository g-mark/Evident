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
/// Initialization from cache / defaultValue is lazy, meaning iinitialization occurs when an observation is created.
public actor ManagedValue<Value> {
    
    /// Creates a `ManagedValue` (read-only) instance, and a `ManagedValue.Setter` instance for updating values.
    public static func create(
        cache: (any SingleValueCache<Value>)? = nil,
        defaultValue: @escaping @autoclosure @Sendable () -> Value
    ) -> (ManagedValue<Value>, ManagedValue<Value>.Setter) {
        let managedValue = ManagedValue(cache: cache, defaultValue: defaultValue)
        return (managedValue, Setter(managedValue))
    }
    
    /// Provides write access to the `ManagedValue`.
    public actor Setter {
        
        /// Set the value.
        public func set(value: Value) async {
            await managedValue.set(value: value)
        }
        
        /// Set a part of the value.
        public func set<T>(_ keyPath: WritableKeyPath<Value, T>, value: T) async {
            await managedValue.set(keyPath, value: value)
        }
        
        /// End _all_ observations, resturn to an uninitialized state.
        public func detach() async {
            await managedValue.detach()
        }
        
        private let managedValue: ManagedValue
        
        fileprivate init(_ managedValue: ManagedValue) {
            self.managedValue = managedValue
        }
    }
    
    public typealias Handler<T> = @Sendable (T) async -> Void
    
    public var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                queue { data in
                    continuation.resume(returning: await data.value)
                }
            }
        }
    }
    
    public func observe(handler: @escaping Handler<Value>) async -> AnyCancellable {
        await withCheckedContinuation { continuation in
            queue { data in
                let cancellable = await data.observe(handler: handler)
                continuation.resume(returning: cancellable)
            }
        }
    }
    
    public func observe(handler: @escaping Handler<Value>) async -> AnyCancellable where Value: Equatable {
        await withCheckedContinuation { continuation in
            queue { data in
                let cancellable = await data.observe(handler: handler)
                continuation.resume(returning: cancellable)
            }
        }
    }
    
    public func observe<T>(_ keyPath: KeyPath<Value, T>, handler: @escaping Handler<T>) async -> AnyCancellable {
        await withCheckedContinuation { continuation in
            queue { data in
                let cancellable = await data.observe(keyPath, handler: handler)
                continuation.resume(returning: cancellable)
            }
        }
    }
    
    public func observe<T: Equatable>(_ keyPath: KeyPath<Value, T>, handler: @escaping Handler<T>) async -> AnyCancellable {
        await withCheckedContinuation { continuation in
            queue { data in
                let cancellable = await data.observe(keyPath, handler: handler)
                continuation.resume(returning: cancellable)
            }
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
    
    /// End _all_ observations, resturn to an uninitialized state.
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
            // TODO: revalidate
        }
    }
    
    private func handleInitialValue(_ value: Value) async {
        let data = ObservableValue<Value>(initialValue: value)
        var cancellable: AnyCancellable?
        if cache != nil {
            cancellable = await data.observe { [weak self] value in
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
