//
//  TestHelpers.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Testing

func eventually<T>(
    timeout: TimeInterval = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    check: () async throws -> T?
) async throws -> T {
    let start = Date(timeInterval: timeout, since: Date())
    while true {
        await Task.yield()
        if let val = try await check() {
            return val
        }
        if Date() >= start {
            Issue.record("eventually exceeded timeout of \(timeout) seconds", sourceLocation: sourceLocation)
            throw EventuallyTimedOut()
        }
        await Task.yield()
    }
}

func eventually(
    timeout: TimeInterval = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    check: () async throws -> Bool
) async throws {
    let start = Date(timeInterval: timeout, since: Date())
    while true {
        await Task.yield()
        if try await check() {
            return
        }
        if Date() >= start {
            Issue.record("eventually exceeded timeout of \(timeout) seconds", sourceLocation: sourceLocation)
            throw EventuallyTimedOut()
        }
        await Task.yield()
    }
}

private struct EventuallyTimedOut: Error { }
