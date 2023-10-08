//
//  DebouncedWorkTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import XCTest
import Evident

final class DebouncedWorkTests: XCTestCase {
    
    func test_debounce() async throws {
        let dbounce = DebouncedWork(threshold: 0.1)
        let observer = Observer()
        
        let workIsDone = expectation(description: "wait for work")
        
        for _ in 0..<4 {
            await dbounce.enqueue {
                await observer.increment()
                workIsDone.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        try await XCTAssertEqualAsync(await observer.num, 1)
    }
    
    private actor Observer {
        var num: Int = 0
        
        func increment() async { num += 1 }
    }
}
