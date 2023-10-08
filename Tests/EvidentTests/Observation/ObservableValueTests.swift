//
//  ObservableValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import XCTest
import Combine
@testable import Evident

final class ObservableValueTests: XCTestCase {
    
    private var cancellable: AnyCancellable?
    
    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async {
            values.append(value)
        }
    }
    
    override func tearDown() {
        cancellable = nil
        super.tearDown()
    }
    
    func test_observeEquatableType() async throws {
        // given
        struct Thing: Equatable {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<Thing>()
        
        // when (set up observation)
        cancellable = await data.observe { value in
            await observer.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue, Thing(name: "Pat", number: 42))
        
        // when
        await data.set(\.name, value: "Pat") // update w/same value - no notification
        await data.set(\.name, value: "Billie") // update w/new value - notification
        await data.set(\.number, value: 42) // update w/same value - no notification
        await data.set(\.number, value: 37) // update w/new value - notification
        
        await data.set(value: Thing(name: "Billie", number: 37)) // update w/same value - no notification
        await data.set(value: Thing(name: "Billie", number: 1)) // update w/different value - no notification
        
        // then (should receive updated value)
        try await eventually { await observer.values.count == 4 }
        try await Task.sleep(for: .milliseconds(10))
        
        let values = await observer.values
        XCTAssertEqual(
            values,
            [Thing(name: "Pat", number: 42),
             Thing(name: "Billie", number: 42),
             Thing(name: "Billie", number: 37),
             Thing(name: "Billie", number: 1)
            ]
        )
    }
    
    func test_observeNonEquatableType() async throws {
        // given
        struct Thing {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<Thing>()
        
        // when (set up observation)
        cancellable = await data.observe { value in
            await observer.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue.name, "Pat")
        XCTAssertEqual(initialValue.number, 42)
        
        // when
        await data.set(\.name, value: "Pat")
        await data.set(\.name, value: "Billie")
        await data.set(\.number, value: 42)
        await data.set(\.number, value: 37)
        
        await data.set(value: Thing(name: "Billie", number: 37))
        await data.set(value: Thing(name: "Billie", number: 1))
        
        // then (should receive updated value)
        try await eventually { await observer.values.count == 7 }
        try await Task.sleep(for: .milliseconds(10))
        
        let values = await observer.values
        let expected = [
            Thing(name: "Pat", number: 42),
            Thing(name: "Pat", number: 42),
            Thing(name: "Billie", number: 42),
            Thing(name: "Billie", number: 42),
            Thing(name: "Billie", number: 37),
            Thing(name: "Billie", number: 37),
            Thing(name: "Billie", number: 1)
        ]
        XCTAssertEqual(
            values.map { "\($0)" },
            expected.map { "\($0)" }
        )
    }
    
    func test_observeEquatableProperty() async throws {
        // given
        struct Thing: Equatable {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<String>()
        
        // when (set up observation)
        cancellable = await data.observe(\.name) { value in
            await observer.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue, "Pat")
        
        // when
        await data.set(\.name, value: "Pat") // update property w/same value - no notification
        await data.set(\.number, value: 37) // update different property w/new value - no notification
        await data.set(value: Thing(name: "Pat", number: 1)) // update property w/same value - no notification
        await data.set(value: Thing(name: "Billie", number: 1)) // update property w/new value - notification
        
        // then (should receive updated value)
        try await eventually { await observer.values.count == 2 }
        try await Task.sleep(for: .milliseconds(10))
        
        let values = await observer.values
        XCTAssertEqual(values, ["Pat", "Billie"])
    }
    
    func test_observeNonEquatableProperty() async throws {
        // given
        struct Wrapped: ExpressibleByStringLiteral {
            let string: String
            init(stringLiteral value: StringLiteralType) {
                string = value
            }
        }
        struct Thing {
            var name: Wrapped
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<String>()
        
        // when (set up observation)
        cancellable = await data.observe(\.name) { value in
            await observer.collect(value.string)
        }
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue, "Pat")
        
        // when
        await data.set(\.name, value: "Pat")
        await data.set(\.number, value: 37)
        await data.set(value: Thing(name: "Pat", number: 1))
        await data.set(value: Thing(name: "Billie", number: 1))
        
        // then (should receive updated value)
        try await eventually { await observer.values.count == 5 }
        try await Task.sleep(for: .milliseconds(10))
        
        let values = await observer.values
        XCTAssertEqual(values, ["Pat", "Pat", "Pat", "Pat", "Billie"])
    }
    
    func test_cancellableObservations() async throws {
        // given
        let data = ObservableValue(initialValue: "A")
        let observer1 = Observer<String>()
        let observer2 = Observer<String>()
        
        // when (set up observation)
        cancellable = await data.observe { value in
            await observer1.collect(value)
        }
        let cancellable2 = await data.observe { value in
            await observer2.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue1 = try await eventually { await observer1.values.first }
        let initialValue2 = try await eventually { await observer2.values.first }
        XCTAssertEqual(initialValue1, "A")
        XCTAssertEqual(initialValue2, "A")
        
        // when
        await data.set(value: "A") // update w/same value - no notification
        await data.set(value: "B") // update w/new value - notification
        
        // then (should receive updated value)
        try await eventually { await observer1.values.count == 2 }
        try await eventually { await observer2.values.count == 2 }
        try await Task.sleep(for: .milliseconds(10))
        
        var values1 = await observer1.values
        var values2 = await observer2.values
        XCTAssertEqual(values1, ["A", "B"])
        XCTAssertEqual(values2, ["A", "B"])
        
        // when
        cancellable = nil
        try await Task.sleep(for: .milliseconds(10))
        
        await data.set(value: "C")
        try await eventually { await observer2.values.count == 3 }
        try await Task.sleep(for: .milliseconds(10))
        
        // then
        values1 = await observer1.values
        values2 = await observer2.values
        XCTAssertEqual(values1, ["A", "B"])
        XCTAssertEqual(values2, ["A", "B", "C"])
        
        // not strictly needed, but silences "unused" warning:
        cancellable2.cancel()
    }
    
    func test_deterministicOrdering() async throws {
        // given
        let data = ObservableValue(initialValue: 0)
        let observer = Observer<Int>()
        
        // when (set up observation)
        cancellable = await data.observe { value in
            await observer.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue, 0)
        
        // when
        for num in 1...100 {
            await data.set(value: num)
        }
        
        // then
        try await eventually { await observer.values.count == 101 }
        
        let values = await observer.values
        XCTAssertEqual(
            values,
            (0...100).map { $0 }
        )
    }
}

