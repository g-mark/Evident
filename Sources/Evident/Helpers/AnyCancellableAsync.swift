//
//  AnyCancellableAsync.swift
//  Evident
//
//  Created by Steven Grosmark on 12/10/24.
//

import Foundation

public final class AnyCancellableAsync: Sendable {
    
    public let cancel: @Sendable () async -> Void
    
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
    
    public final func store<C>(
        in collection: inout C
    ) where C : RangeReplaceableCollection, C.Element == AnyCancellableAsync {
        collection.append(self)
    }
}
