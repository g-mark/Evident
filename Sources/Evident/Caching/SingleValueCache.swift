//
//  SingleValueCache.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Foundation

public protocol SingleValueCache<Value>: Actor {
    associatedtype Value
    
    func retrieve() async -> (value: Value, isStale: Bool)?
    func store(_ value: Value) async
    func flushPendingWork() async
}
