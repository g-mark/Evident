//
//  Optional+unwrap.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

extension Optional {
    
    func unwrap(throwing error: @autoclosure () -> Error = UnwrapError.nilValue ) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
    
    enum UnwrapError: Error {
        case nilValue
    }
}
