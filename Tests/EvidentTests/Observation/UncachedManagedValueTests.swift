//
//  UncachedManagedValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Testing
import Evident

@Suite(.serialized)
struct UncachedManagedValueTests {

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

    private let managedValue: ManagedValue<Thing>
    private let setter: ManagedValue<Thing>.Setter

    init() {
        (managedValue, setter) = ManagedValue.create(defaultValue: Thing(name: "", number: 0))
    }

    @Test func manager() async throws {
        let observer = Observer<String>()
        var cancellables: [AnyCancellableAsync] = []

        // when
        managedValue.observe(\.name) { name in
            await observer.collect(name)
        }.store(in: &cancellables)

        // then
        let name = try await eventually { await observer.values.first }
        #expect(name == "")

        // when
        await observer.reset()
        await setter.set(\.name, value: "pat")
        await setter.set(value: Thing(name: "pat", number: 1))
        await setter.set(value: Thing(name: "billie", number: 1))
        await setter.set(\.number, value: 2)

        // then
        try await eventually { await observer.values.count == 2 }
        let names = await observer.values
        #expect(names == ["pat", "billie"])

        let value = await managedValue.value
        #expect(value == Thing(name: "billie", number: 2))

        // when
        await observer.reset()
        await setter.detach()
        await setter.set(\.name, value: "nom")

        // then
        try await Task.sleep(for: .milliseconds(10))
        #expect(await observer.values == [])
        _ = cancellables
    }

    @Test func observationTypes() async throws {
        let things = Observer<Thing>()
        let thingChanges = Observer<(Thing?, Thing)>()
        let names = Observer<String>()
        let others = Observer<NotEquatable>()
        var cancellables: [AnyCancellableAsync] = []

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
        #expect(change.0 == nil)
        #expect(change.1 == Thing(name: "", number: 0))

        // when
        await setter.set(value: Thing(name: "", number: 0))

        // then
        try await eventually { await others.values.count == 2 }
        try await Task.sleep(for: .milliseconds(5))

        #expect(await things.values == [Thing(name: "", number: 0)])
        #expect(await names.values == [""])
        var otherValues = await others.values
        #expect(otherValues.count == 2)
        #expect(otherValues[0].id == 0)
        #expect(otherValues[1].id == 0)

        var changes = try await eventually { await thingChanges.values }
        #expect(changes.count == 1)
        #expect(changes[0].0 == nil)
        #expect(changes[0].1 == Thing(name: "", number: 0))

        // when
        await setter.set(value: Thing(name: "Nom", number: 0))

        // then
        try await eventually { await others.values.count == 3 }
        try await Task.sleep(for: .milliseconds(5))

        #expect(await things.values == [Thing(name: "", number: 0), Thing(name: "Nom", number: 0)])
        #expect(await names.values == ["", "Nom"])
        otherValues = await others.values
        #expect(otherValues.count == 3)
        #expect(otherValues[0].id == 0)
        #expect(otherValues[1].id == 0)
        #expect(otherValues[2].id == 0)

        changes = try await eventually { await thingChanges.values }
        #expect(changes.count == 2)
        #expect(changes[0].0 == nil)
        #expect(changes[0].1 == Thing(name: "", number: 0))
        #expect(changes[1].0 == Thing(name: "", number: 0))
        #expect(changes[1].1 == Thing(name: "Nom", number: 0))

        // when
        await thingChanges.reset()
        await things.reset()
        await names.reset()
        await others.reset()
        await setter.detach()
        await setter.set(value: Thing(name: "qwerty", number: 99))

        // then
        try await Task.sleep(for: .milliseconds(10))
        #expect(await things.values == [])
        #expect(await names.values == [])
        changes = await thingChanges.values
        otherValues = await others.values
        #expect(changes.isEmpty)
        #expect(otherValues.isEmpty)
        _ = cancellables
    }

    @Test func cancellableObservations() async throws {
        let observer1 = Observer<Int>()
        let observer2 = Observer<Int>()
        let observer3 = Observer<Int>()
        var cancellables: [AnyCancellableAsync] = []

        // when
        managedValue.observe(\.number) { num in await observer1.collect(num) }.store(in: &cancellables)
        let cancellable2 = managedValue.observe(\.number) { num in await observer2.collect(num) }
        _ = managedValue.observe(\.number) { num in await observer3.collect(num) }
        try await Task.sleep(for: .milliseconds(5))

        // then
        let value1 = try await eventually { await observer1.values.first }
        let value2 = try await eventually { await observer1.values.first }
        let value3 = try await eventually { await observer1.values.first }
        #expect(value1 == 0)
        #expect(value2 == 0)
        #expect(value3 == 0)

        // when
        await setter.set(\.number, value: 1)
        try await eventually { await observer1.values.last == 1 }
        try await eventually { await observer2.values.last == 1 }
        try await Task.sleep(for: .milliseconds(5))

        // then
        #expect(await observer1.values == [0, 1])
        #expect(await observer2.values == [0, 1])
        #expect(await observer3.values == [0])

        // when
        await cancellable2.cancel()
        try await Task.sleep(for: .milliseconds(5))

        await setter.set(\.number, value: 2)
        try await eventually { await observer1.values.last == 2 }
        try await Task.sleep(for: .milliseconds(5))

        // then
        #expect(await observer1.values == [0, 1, 2])
        #expect(await observer2.values == [0, 1])
        #expect(await observer3.values == [0])

        // when
        await observer1.reset()
        await observer2.reset()
        await observer3.reset()
        await setter.detach()
        await setter.set(\.number, value: 9999)

        // then
        try await Task.sleep(for: .milliseconds(10))
        #expect(await observer1.values == [])
        #expect(await observer2.values == [])
        #expect(await observer3.values == [])
        _ = cancellables
    }
}
