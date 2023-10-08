//
//  XCTestCase+Helpers.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import XCTest

extension XCTestCase {
    
    func XCTAssertEqualAsync<T>(
        _ expression1: @autoclosure () async throws -> T,
        _ expression2: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws where T : Equatable {
        let value1 = try await expression1()
        let value2 = try await expression2()
        XCTAssertEqual(value1, value2, message(), file: file, line: line)
    }
    
    func XCTAssertNilAsync(
        _ expression: @autoclosure () async throws -> Any?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let any = try await expression()
        switch any {
        case .some: XCTFail(message(), file: file, line: line)
        case .none: break
        }
    }
    
    func XCTAssertNotNilAsync(
        _ expression: @autoclosure () async throws -> Any?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let any = try await expression()
        switch any {
        case .some: break
        case .none: XCTFail(message(), file: file, line: line)
        }
    }
    
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            let _: T = try await expression()
        }
        catch {
            errorHandler(error)
            return
        }
        XCTFail(message(), file: file, line: line)
    }
    
    func eventually<T>(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        check: () async throws -> T?
    ) async throws -> T {
        let start = Date(timeInterval: timeout, since: Date())
        while true {
            await Task.yield()
            if let val = try await check() {
                return val
            }
            if Date() >= start {
                XCTFail("eventually exceeded timeout of \(timeout) seconds", file: file, line: line)
                throw EventuallyTimedOut()
            }
            await Task.yield()
        }
    }
    
    func eventually(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        check: () async throws -> Bool
    ) async throws {
        let start = Date(timeInterval: timeout, since: Date())
        while true {
            await Task.yield()
            if try await check() {
                return
            }
            if Date() >= start {
                XCTFail("eventually exceeded timeout of \(timeout) seconds", file: file, line: line)
                throw EventuallyTimedOut()
            }
            await Task.yield()
        }
    }
    
    private struct EventuallyTimedOut: Error { }
}
