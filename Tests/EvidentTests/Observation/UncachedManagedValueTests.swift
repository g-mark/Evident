//
//  UncachedManagedValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import XCTest
import Combine
import Evident

final class UncachedManagedValueTests: XCTestCase {
    
    private struct Thing: Equatable {
        var name: String
        var number: Int
        var other: NotEquatable = NotEquatable(id: 0)
        
        static func == (lhs: Thing, rhs: Thing) -> Bool {
            lhs.name == rhs.name && lhs.number == rhs.number
        }
    }
    
    private struct NotEquatable {
        var id: Int
    }
    
    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async { values.append(value) }
        func reset() async { values = [] }
    }
    
    private var managedValue: ManagedValue<Thing>!
    private var setter: ManagedValue<Thing>.Setter!
    private var cancellables: [AnyCancellable] = []
    
    override func setUp() async throws {
        try await super.setUp()
        (managedValue, setter) = ManagedValue.create(defaultValue: Thing(name: "", number: 0))
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        managedValue = nil
        setter = nil
        cancellables = []
    }
    
    func test_manager() async throws {
        let observer = Observer<String>()
        
        // when
        managedValue.observe(\.name) { name in
            await observer.collect(name)
        }.store(in: &cancellables)
        
        // then
        let name = try await eventually { await observer.values.first }
        XCTAssertEqual(name, "")
        
        // when
        await observer.reset()
        await setter.set(\.name, value: "pat")
        await setter.set(value: Thing(name: "pat", number: 1))
        await setter.set(value: Thing(name: "billie", number: 1))
        await setter.set(\.number, value: 2)
        
        // then
        try await eventually { await observer.values.count == 2 }
        let names = await observer.values
        XCTAssertEqual(names, ["pat", "billie"])
        
        let value = await managedValue.value
        XCTAssertEqual(value, Thing(name: "billie", number: 2))
        
        // when
        await observer.reset()
        await setter.detach()
        await setter.set(\.name, value: "nom")
        
        // then
        try await Task.sleep(for: .milliseconds(10))
        try await XCTAssertEqualAsync(await observer.values, [])
    }
    
    func test_observationTypes() async throws {
        let things = Observer<Thing>()
        let thingChanges = Observer<(Thing?, Thing)>()
        let names = Observer<String>()
        let others = Observer<NotEquatable>()
        
        // when
        managedValue.observe { old, new in
            await thingChanges.collect((old, new))
        }.store(in: &cancellables)
        managedValue.observe { thing in
            await things.collect(thing)
        }.store(in: &cancellables)
        managedValue.observe(\.name) { name in
            await names.collect(name)
        }.store(in: &cancellables)
        managedValue.observe(\.other) { other in
            await others.collect(other)
        }.store(in: &cancellables)
        
        // then
        try await eventually { await things.values == [Thing(name: "", number: 0)] }
        try await eventually { await names.values == [""] }
        try await eventually { await others.values.first?.id == 0 }
        let change = try await eventually { await thingChanges.values.first }
        XCTAssertNil(change.0)
        XCTAssertEqual(change.1, Thing(name: "", number: 0))
        
        // when
        await setter.set(value: Thing(name: "", number: 0))
        
        // then
        try await eventually { await others.values.count == 2 }
        try await Task.sleep(for: .milliseconds(5))
        
        try await XCTAssertEqualAsync(await things.values, [Thing(name: "", number: 0)])
        try await XCTAssertEqualAsync( await names.values, [""])
        var otherValues = await others.values
        XCTAssertEqual(otherValues.count, 2)
        XCTAssertEqual(otherValues[0].id, 0)
        XCTAssertEqual(otherValues[1].id, 0)
        
        var changes = try await eventually { await thingChanges.values }
        XCTAssertEqual(changes.count, 1)
        XCTAssertNil(changes[0].0)
        XCTAssertEqual(changes[0].1, Thing(name: "", number: 0))
        
        // when
        await setter.set(value: Thing(name: "Nom", number: 0))
        
        // then
        try await eventually { await others.values.count == 3 }
        try await Task.sleep(for: .milliseconds(5))
        
        try await XCTAssertEqualAsync(await things.values, [Thing(name: "", number: 0), Thing(name: "Nom", number: 0)])
        try await XCTAssertEqualAsync( await names.values, ["", "Nom"])
        otherValues = await others.values
        XCTAssertEqual(otherValues.count, 3)
        XCTAssertEqual(otherValues[0].id, 0)
        XCTAssertEqual(otherValues[1].id, 0)
        XCTAssertEqual(otherValues[2].id, 0)
        
        changes = try await eventually { await thingChanges.values }
        XCTAssertEqual(changes.count, 2)
        XCTAssertNil(changes[0].0)
        XCTAssertEqual(changes[0].1, Thing(name: "", number: 0))
        XCTAssertEqual(changes[1].0, Thing(name: "", number: 0))
        XCTAssertEqual(changes[1].1, Thing(name: "Nom", number: 0))
        
        // when
        await thingChanges.reset()
        await things.reset()
        await names.reset()
        await others.reset()
        await setter.detach()
        await setter.set(value: Thing(name: "qwerty", number: 99))
        
        // then
        try await Task.sleep(for: .milliseconds(10))
        try await XCTAssertEqualAsync(await things.values, [])
        try await XCTAssertEqualAsync(await names.values, [])
        changes = await thingChanges.values
        otherValues = await others.values
        XCTAssertTrue(changes.isEmpty)
        XCTAssertTrue(otherValues.isEmpty)
    }
    
    func test_cancellableObservations() async throws {
        let observer1 = Observer<Int>()
        let observer2 = Observer<Int>()
        let observer3 = Observer<Int>()

        // when
        managedValue.observe(\.number) { num in await observer1.collect(num) }.store(in: &cancellables)
        let cancellable2 = managedValue.observe(\.number) { num in await observer2.collect(num) }
        _ = managedValue.observe(\.number) { num in await observer3.collect(num) }
        try await Task.sleep(for: .milliseconds(5))

        // then
        let value1 = try await eventually { await observer1.values.first }
        let value2 = try await eventually { await observer1.values.first }
        let value3 = try await eventually { await observer1.values.first }
        XCTAssertEqual(value1, 0)
        XCTAssertEqual(value2, 0)
        XCTAssertEqual(value3, 0)

        // when
        await setter.set(\.number, value: 1)
        try await eventually { await observer1.values.last == 1 }
        try await eventually { await observer2.values.last == 1 }
        try await Task.sleep(for: .milliseconds(5))

        // then
        try await XCTAssertEqualAsync(await observer1.values, [0, 1])
        try await XCTAssertEqualAsync(await observer2.values, [0, 1])
        try await XCTAssertEqualAsync(await observer3.values, [0])

        // when
        cancellable2.cancel()
        try await Task.sleep(for: .milliseconds(5))

        await setter.set(\.number, value: 2)
        try await eventually { await observer1.values.last == 2 }
        try await Task.sleep(for: .milliseconds(5))

        // then
        try await XCTAssertEqualAsync(await observer1.values, [0, 1, 2])
        try await XCTAssertEqualAsync(await observer2.values, [0, 1])
        try await XCTAssertEqualAsync(await observer3.values, [0])
        
        // when
        await observer1.reset()
        await observer2.reset()
        await observer3.reset()
        await setter.detach()
        await setter.set(\.number, value: 9999)
        
        // then
        try await Task.sleep(for: .milliseconds(10))
        try await XCTAssertEqualAsync(await observer1.values, [])
        try await XCTAssertEqualAsync(await observer2.values, [])
        try await XCTAssertEqualAsync(await observer3.values, [])
    }
}
