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
    
    private var cancellables: [AnyCancellable] = []
    
    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async {
            values.append(value)
        }
    }
    
    override func tearDown() {
        cancellables = []
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
        let transitions = Observer<(Thing?, Thing)>()
        
        // when (set up observation)
        data.observe { value in
            await observer.collect(value)
        }.store(in: &cancellables)
        data.observe { old, new in
            await transitions.collect((old, new))
        }.store(in: &cancellables)
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue, Thing(name: "Pat", number: 42))
        
        var (old, new) = try await eventually { await transitions.values.first }
        XCTAssertNil(old)
        XCTAssertEqual(new, Thing(name: "Pat", number: 42))
        
        // when
        await data.set(\.name, value: "Pat") // update w/same value - no notification
        await data.set(\.name, value: "Billie") // update w/new value - notification
        try await eventually { await observer.values.last?.name == "Billie" }
        
        try await eventually { await transitions.values.last?.1.name == "Billie" }
        (old, new) = try await eventually { await transitions.values.last }
        XCTAssertEqual(old, Thing(name: "Pat", number: 42))
        XCTAssertEqual(new, Thing(name: "Billie", number: 42))
        
        await data.set(\.number, value: 42) // update w/same value - no notification
        await data.set(\.number, value: 37) // update w/new value - notification
        try await eventually { await observer.values.last?.number == 37 }
        
        try await eventually { await transitions.values.last?.1.number == 37 }
        (old, new) = try await eventually { await transitions.values.last }
        XCTAssertEqual(old, Thing(name: "Billie", number: 42))
        XCTAssertEqual(new, Thing(name: "Billie", number: 37))
        
        await data.set(value: Thing(name: "Billie", number: 37)) // update w/same value - no notification
        await data.set(value: Thing(name: "Billie", number: 1)) // update w/different value - no notification
        try await eventually { await observer.values.last?.number == 1 }
        
        try await eventually { await transitions.values.last?.1.number == 1 }
        (old, new) = try await eventually { await transitions.values.last }
        XCTAssertEqual(old, Thing(name: "Billie", number: 37))
        XCTAssertEqual(new, Thing(name: "Billie", number: 1))
        
        // then (should receive updated value)
        let values = await observer.values
        let expected = [
            Thing(name: "Pat", number: 42),
            Thing(name: "Billie", number: 42),
            Thing(name: "Billie", number: 37),
            Thing(name: "Billie", number: 1)
        ]
        XCTAssertEqual(values, expected)
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
        data.observe { value in
            await observer.collect(value)
        }.store(in: &cancellables)
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        XCTAssertEqual(initialValue.name, "Pat")
        XCTAssertEqual(initialValue.number, 42)
        
        // when
        await data.set(\.name, value: "Pat")
        try await eventually { await observer.values.count == 2 }
        await data.set(\.name, value: "Billie")
        try await eventually { await observer.values.count == 3 }
        await data.set(\.number, value: 42)
        try await eventually { await observer.values.count == 4 }
        await data.set(\.number, value: 37)
        try await eventually { await observer.values.count == 5 }
        
        await data.set(value: Thing(name: "Billie", number: 37))
        try await eventually { await observer.values.count == 6 }
        await data.set(value: Thing(name: "Billie", number: 1))
        try await eventually { await observer.values.count == 7 }
        
        // then (should receive updated value)
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
        data.observe(\.name) { value in
            await observer.collect(value)
        }.store(in: &cancellables)
        
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
        try await XCTAssertEqualAsync(await data.value, Thing(name: "Billie", number: 1))
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
        data.observe(\.name) { value in
            await observer.collect(value.string)
        }.store(in: &cancellables)
        
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
        let observer3 = Observer<String>()
        
        // when (set up observation)
        let cancellable = data.observe { value in
            await observer1.collect(value)
        }
        data.observe { value in
            await observer2.collect(value)
        }.store(in: &cancellables)
        
        // expected to immediately cancel the observation due to the cancellable being discarded via anonymous var
        _ = data.observe { value in
            await observer3.collect(value)
        }
        
        // then (should receive initial value)
        let initialValue1 = try await eventually { await observer1.values.first }
        let initialValue2 = try await eventually { await observer2.values.first }
        let initialValue3 = try await eventually { await observer3.values.first }
        XCTAssertEqual(initialValue1, "A")
        XCTAssertEqual(initialValue2, "A")
        XCTAssertEqual(initialValue3, "A")
        
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
        cancellable.cancel()
        try await Task.sleep(for: .milliseconds(10))
        
        await data.set(value: "C")
        try await eventually { await observer2.values.count == 3 }
        try await Task.sleep(for: .milliseconds(10))
        
        // then
        values1 = await observer1.values
        values2 = await observer2.values
        let values3 = await observer3.values
        XCTAssertEqual(values1, ["A", "B"])
        XCTAssertEqual(values2, ["A", "B", "C"])
        XCTAssertEqual(values3, ["A"])
    }
}

