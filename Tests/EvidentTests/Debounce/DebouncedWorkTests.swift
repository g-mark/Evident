//
//  DebouncedWorkTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Testing
import Evident

struct DebouncedWorkTests {

    @Test func debounce() async throws {
        let dbounce = DebouncedWork(threshold: 0.1)
        let observer = Observer()

        for _ in 0..<4 {
            await dbounce.enqueue {
                await observer.increment()
            }
        }

        try await eventually { await observer.num >= 1 }
        #expect(await observer.num == 1)
    }

    private actor Observer {
        var num: Int = 0

        func increment() async { num += 1 }
    }
}
