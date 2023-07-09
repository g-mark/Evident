//
//  RefreshableTokenService.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

public protocol RefreshableTokenService: Actor {
    
    associatedtype Token: AuthorizationToken
    
    func refresh(_ token: Token) async throws -> Token
}
