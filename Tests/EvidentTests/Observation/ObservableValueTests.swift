//
//  ObservableValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/8/23.
//

import Testing
@testable import Evident

@Suite(.serialized)
struct ObservableValueTests {

    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async {
            values.append(value)
        }
    }

    @Test func observeEquatableType() async throws {
        // given
        struct Thing: Equatable {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<Thing>()
        let transitions = Observer<(Thing?, Thing)>()
        var cancellables: [AnyCancellableAsync] = []

        // when (set up observation)
        data.observe { value in
            await observer.collect(value)
        }.store(in: &cancellables)
        data.observe { old, new in
            await transitions.collect((old, new))
        }.store(in: &cancellables)

        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        #expect(initialValue == Thing(name: "Pat", number: 42))

        var (old, new) = try await eventually { await transitions.values.first }
        #expect(old == nil)
        #expect(new == Thing(name: "Pat", number: 42))

        // when
        await data.set(\.name, value: "Pat") // update w/same value - no notification
        await data.set(\.name, value: "Billie") // update w/new value - notification
        try await eventually { await observer.values.last?.name == "Billie" }

        try await eventually { await transitions.values.last?.1.name == "Billie" }
        (old, new) = try await eventually { await transitions.values.last }
        #expect(old == Thing(name: "Pat", number: 42))
        #expect(new == Thing(name: "Billie", number: 42))

        await data.set(\.number, value: 42) // update w/same value - no notification
        await data.set(\.number, value: 37) // update w/new value - notification
        try await eventually { await observer.values.last?.number == 37 }

        try await eventually { await transitions.values.last?.1.number == 37 }
        (old, new) = try await eventually { await transitions.values.last }
        #expect(old == Thing(name: "Billie", number: 42))
        #expect(new == Thing(name: "Billie", number: 37))

        await data.set(value: Thing(name: "Billie", number: 37)) // update w/same value - no notification
        await data.set(value: Thing(name: "Billie", number: 1)) // update w/different value - notification
        try await eventually { await observer.values.last?.number == 1 }

        try await eventually { await transitions.values.last?.1.number == 1 }
        (old, new) = try await eventually { await transitions.values.last }
        #expect(old == Thing(name: "Billie", number: 37))
        #expect(new == Thing(name: "Billie", number: 1))

        // then (should receive updated value)
        let values = await observer.values
        let expected = [
            Thing(name: "Pat", number: 42),
            Thing(name: "Billie", number: 42),
            Thing(name: "Billie", number: 37),
            Thing(name: "Billie", number: 1)
        ]
        #expect(values == expected)
        _ = cancellables
    }

    @Test func observeNonEquatableType() async throws {
        // given
        struct Thing {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<Thing>()
        var cancellables: [AnyCancellableAsync] = []

        // when (set up observation)
        data.observe { value in
            await observer.collect(value)
        }.store(in: &cancellables)

        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        #expect(initialValue.name == "Pat")
        #expect(initialValue.number == 42)

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
        #expect(
            values.map { "\($0)" } ==
            expected.map { "\($0)" }
        )
        _ = cancellables
    }

    @Test func observeEquatableProperty() async throws {
        // given
        struct Thing: Equatable {
            var name: String
            var number: Int
        }
        let data = ObservableValue(initialValue: Thing(name: "Pat", number: 42))
        let observer = Observer<String>()
        var cancellables: [AnyCancellableAsync] = []

        // when (set up observation)
        data.observe(\.name) { value in
            await observer.collect(value)
        }.store(in: &cancellables)

        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        #expect(initialValue == "Pat")

        // when
        await data.set(\.name, value: "Pat") // update property w/same value - no notification
        await data.set(\.number, value: 37) // update different property w/new value - no notification
        await data.set(value: Thing(name: "Pat", number: 1)) // update property w/same value - no notification
        await data.set(value: Thing(name: "Billie", number: 1)) // update property w/new value - notification

        // then (should receive updated value)
        try await eventually { await observer.values.count == 2 }
        try await Task.sleep(for: .milliseconds(10))

        let values = await observer.values
        #expect(values == ["Pat", "Billie"])
        #expect(await data.value == Thing(name: "Billie", number: 1))
        _ = cancellables
    }

    @Test func observeNonEquatableProperty() async throws {
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
        var cancellables: [AnyCancellableAsync] = []

        // when (set up observation)
        data.observe(\.name) { value in
            await observer.collect(value.string)
        }.store(in: &cancellables)

        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        #expect(initialValue == "Pat")

        // when
        await data.set(\.name, value: "Pat")
        await data.set(\.number, value: 37)
        await data.set(value: Thing(name: "Pat", number: 1))
        await data.set(value: Thing(name: "Billie", number: 1))

        // then (should receive updated value)
        try await eventually { await observer.values.count == 5 }
        try await Task.sleep(for: .milliseconds(10))

        let values = await observer.values
        #expect(values == ["Pat", "Pat", "Pat", "Pat", "Billie"])
        _ = cancellables
    }

    @Test func cancellableObservations() async throws {
        // given
        let data = ObservableValue(initialValue: "A")
        let observer1 = Observer<String>()
        let observer2 = Observer<String>()
        var cancellables: [AnyCancellableAsync] = []

        // when (set up observation)
        let cancellable = data.observe { value in
            await observer1.collect(value)
        }
        data.observe { value in
            await observer2.collect(value)
        }.store(in: &cancellables)

        // then (should receive initial value)
        let initialValue1 = try await eventually { await observer1.values.first }
        let initialValue2 = try await eventually { await observer2.values.first }
        #expect(initialValue1 == "A")
        #expect(initialValue2 == "A")

        // when
        await data.set(value: "A") // update w/same value - no notification
        await data.set(value: "B") // update w/new value - notification

        // then (should receive updated value)
        try await eventually { await observer1.values == ["A", "B"] }
        try await eventually { await observer2.values == ["A", "B"] }
        try await Task.sleep(for: .milliseconds(10))

        var values1 = await observer1.values
        var values2 = await observer2.values
        #expect(values1 == ["A", "B"])
        #expect(values2 == ["A", "B"])

        // when
        await cancellable.cancel()
        try await Task.sleep(for: .milliseconds(10))

        await data.set(value: "C")
        try await eventually { await observer2.values.count == 3 }
        try await Task.sleep(for: .milliseconds(10))

        // then
        values1 = await observer1.values
        values2 = await observer2.values
        #expect(values1 == ["A", "B"])
        #expect(values2 == ["A", "B", "C"])
        _ = cancellables
    }
    
    @Test func valuesAreOrdered() async throws {
        // given
        let data = ObservableValue(initialValue: 1)
        let observer = Observer<Int>()
        var cancellables: [AnyCancellableAsync] = []
        
        // when (set up observation)
        data.observe { value in
            await observer.collect(value)
        }.store(in: &cancellables)
        
        // then (should receive initial value)
        let initialValue = try await eventually { await observer.values.first }
        #expect(initialValue == 1)
        
        // when
        for i in 2..<100 {
            await data.set(value: i)
        }
        
        // then (should receive final updated value)
        try await eventually { await observer.values.last == 99 }
        try await Task.sleep(for: .milliseconds(10))
        
        // then (all values should be monotonically increasing)
        var previousValue = 0
        let values = await observer.values
        for value in values {
            #expect(value > previousValue)
            previousValue = value
        }
        
        _ = cancellables
    }
}
