//
//  AuthorizationToken.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

public protocol AuthorizationToken {
    
    var authorizationHeaderValue: String { get }
    var isExpired: Bool { get }
    
    mutating func setExpired()
}
