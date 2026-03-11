//
//  SingleValueCache.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Foundation

/// A cache that stores and retrieves a single value, with support for staleness detection.
///
/// Conforming types must be actors to ensure thread-safe access. Used by ``ManagedValue``
/// to persist and restore observed values.
public protocol SingleValueCache<Value>: Actor {

    /// The type of value stored in the cache.
    associatedtype Value

    /// Retrieves the cached value, if available.
    ///
    /// - Returns: A tuple of the cached value and whether it is stale, or `nil` if no value is cached.
    func retrieve() async -> (value: Value, isStale: Bool)?

    /// Stores a value in the cache.
    ///
    /// - Parameter value: The value to cache.
    func store(_ value: Value) async

    /// Immediately persists any pending write operations.
    func flushPendingWork() async

    /// Clears the cache, removing any stored value and cancelling pending writes.
    func clear() async
}
