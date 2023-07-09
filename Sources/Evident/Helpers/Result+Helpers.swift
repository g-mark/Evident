//
//  Result+Helpers.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

extension Result {
    
    var error: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}

extension Result where Failure == Error {

    /// Creates a new result by evaluating a throwing closure, capturing the
    /// returned value as a success, or any thrown error as a failure.
    ///
    /// - Parameter body: A throwing closure to evaluate.
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        }
        catch {
            self = .failure(error)
        }
    }
}
