//
//  AnyCancellableAsync.swift
//  Evident
//
//  Created by Steven Grosmark on 12/10/24.
//

import Foundation

/// A type-erased, sendable cancellation token for managing async observation lifetimes.
///
/// When the `AnyCancellableAsync` is released (or ``cancel`` is called),
/// the associated observation is automatically cancelled.
///
/// Store the token for as long as the observation should remain active:
/// ```swift
/// let cancellable = await observable.observe { value in
///     print(value)
/// }
/// // observation is active while `cancellable` is retained
/// ```
public final class AnyCancellableAsync: Sendable {

    /// Cancel the observation associated with this token.
    public let cancel: @Sendable () async -> Void
    
    // MARK: Implementation details

    init(cancel: @escaping @Sendable () async -> Void) {
        self.cancel = cancel
    }
    
    deinit {
        Task { [cancel] in
            await cancel()
        }
    }
    
}

// MARK: - Internal helpers

protocol Cancellable: Sendable {
    func cancel()
}

extension AnyCancellableAsync {
    
    convenience init(_ cancellable: Cancellable) {
        self.init { cancellable.cancel() }
    }
    
    /// Stores this cancellable in the specified collection.
    ///
    /// A convenience for collecting multiple cancellables:
    /// ```swift
    /// var cancellables: [AnyCancellableAsync] = []
    /// observable.observe { value in
    ///     print(value)
    /// }.store(in: &cancellables)
    /// ```
    ///
    /// - Parameter collection: The collection in which to store this cancellable.
    public final func store<C>(
        in collection: inout C
    ) where C : RangeReplaceableCollection, C.Element == AnyCancellableAsync {
        collection.append(self)
    }
}
