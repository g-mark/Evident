//
//  MessageQueueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Testing
@testable import Evident

@Suite(.serialized)
struct MessageQueueTests {

    private enum Message: Equatable, Sendable {
        case one
        case two(Int)
    }

    private actor Receiver {
        var received: [Message] = []
        func receive(_ message: Message) async {
            received.append(message)
        }
    }

    @Test func observations() async throws {
        let queue = MessageQueue<Message>()
        let receiver = Receiver()
        var cancellables: [AnyCancellableAsync] = []

        cancellables.append(
            await queue.observe { message in
                await receiver.receive(message)
            }
        )

        // when
        queue.dispatch(.one)
        try await Task.sleep(nanoseconds: 5_000)
        queue.dispatch(.two(3))

        try await eventually { await receiver.received.count == 2 }

        // then
        let received = await receiver.received
        #expect(received == [.one, .two(3)])
        _ = cancellables
    }

    @Test func cancellableObservations() async throws {
        let queue = MessageQueue<Message>()
        let receiver1 = Receiver()
        let receiver2 = Receiver()
        var cancellables: [AnyCancellableAsync] = []

        let cancellable1 = await queue.observe { message in
            await receiver1.receive(message)
        }
        cancellables.append(contentsOf: [
            cancellable1,
            await queue.observe { message in
                await receiver2.receive(message)
            }
        ])

        // when
        queue.dispatch(.one)
        try await eventually { await receiver1.received.count == 1 }
        try await eventually { await receiver2.received.count == 1 }

        // then
        var received1 = await receiver1.received
        #expect(received1 == [.one])
        var received2 = await receiver2.received
        #expect(received2 == [.one])

        // when
        await cancellable1.cancel()
        try await eventually { await queue.handlerCount() == 1 }

        queue.dispatch(.two(3))
        try await eventually { await receiver2.received.count == 2 }

        // then
        received1 = await receiver1.received
        #expect(received1 == [.one])
        received2 = await receiver2.received
        #expect(received2 == [.one, .two(3)])
        _ = cancellables
    }

    @Test func observeNonCancellable() async throws {
        print("--- testing")
        let queue = MessageQueue<Message>()
        let receiver = Receiver()

        func setUpObservation() {
            // calling .observe() outside of an async context to force the use of the non-cancellable version.
            queue.observe { message in
                print("Received: \(message)")
                await receiver.receive(message)
            }
        }
        setUpObservation()

        // wait for the non-cancellable observation to be registered
        try await eventually { await queue.handlerCount() == 1 }

        // when
        queue.dispatch(.one)
        try await eventually { await receiver.received.count == 1 }
        
        queue.dispatch(.two(3))
        try await eventually { await receiver.received.count == 2 }

        // then
        let received = await receiver.received
        #expect(received == [.one, .two(3)])
    }

    @Test func noReferenceCycles() async throws {
        var queue: MessageQueue<Message>? = MessageQueue<Message>()
        let receiver = Receiver()
        var cancellables: [AnyCancellableAsync] = []

        if let tempQueue = queue {
            cancellables.append(
                await tempQueue.observe { message in
                    await receiver.receive(message)
                }
            )
        }

        // when
        queue?.dispatch(.one)
        try await eventually { await receiver.received.count == 1 }

        let task = Task.detached { [weak queue] in
            queue?.dispatch(.two(3))
        }
        queue = nil
        await task.value

        // then
        let received = await receiver.received
        #expect(received == [.one])
        _ = cancellables
    }
}
