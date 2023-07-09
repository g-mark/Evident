//
//  MessageQueueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import XCTest
import Combine
@testable import Evident

final class MessageQueueTests: XCTestCase {
    
    private enum Message: Equatable {
        case one
        case two(Int)
    }
    
    private actor Receiver {
        var received: [Message] = []
        func receive(_ message: Message) async {
            received.append(message)
        }
    }
    
    private var cancellables: [AnyCancellable] = []
    
    override func tearDown() {
        cancellables = []
        super.tearDown()
    }
    
    func test_observations() async throws {
        let queue = MessageQueue<Message>()
        let receiver = Receiver()
        
        cancellables.append(
            await queue.observe { message in
                await receiver.receive(message)
            }
        )
        
        // when
        queue.dispatch(.one)
        try await Task.sleep(nanoseconds: 5_000)
        queue.dispatch(.two(3))
        
        try await eventually(timeout: 1) { await receiver.received.count == 2 }
        
        // then
        let received = await receiver.received
        XCTAssertEqual(received, [.one, .two(3)])
    }
    
    func test_cancellableObservations() async throws {
        let queue = MessageQueue<Message>()
        let receiver1 = Receiver()
        let receiver2 = Receiver()
        
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
        try await eventually(timeout: 1) { await receiver1.received.count == 1 }
        try await eventually(timeout: 1) { await receiver2.received.count == 1 }
        
        // then
        var received1 = await receiver1.received
        XCTAssertEqual(received1, [.one])
        var received2 = await receiver2.received
        XCTAssertEqual(received2, [.one])
        
        // when
        cancellable1.cancel()
        try await eventually(timeout: 1) { await queue.handlerCount() == 1 }
        
        queue.dispatch(.two(3))
        try await eventually(timeout: 1) { await receiver2.received.count == 2 }
        
        // then
        received1 = await receiver1.received
        XCTAssertEqual(received1, [.one])
        received2 = await receiver2.received
        XCTAssertEqual(received2, [.one, .two(3)])
    }
    
    func test_observe_nonCancellable() async throws {
        let queue = MessageQueue<Message>()
        let receiver = Receiver()
        
        func setUpObservation() {
            queue.observe { message in
                await receiver.receive(message)
            }
        }
        setUpObservation()
        
        // when
        queue.dispatch(.one)
        try await Task.sleep(nanoseconds: 5_000)
        queue.dispatch(.two(3))
        
        try await eventually(timeout: 1) { await receiver.received.count == 2 }
        
        // then
        let received = await receiver.received
        XCTAssertEqual(received, [.one, .two(3)])
    }
    
    func test_noReferenceCycles() async throws {
        var queue: MessageQueue<Message>? = MessageQueue<Message>()
        let receiver = Receiver()
        
        if let tempQueue = queue {
            cancellables.append(
                await tempQueue.observe { message in
                    await receiver.receive(message)
                }
            )
        }
        
        // when
        queue?.dispatch(.one)
        try await eventually(timeout: 1) { await receiver.received.count == 1 }
        
        let task = Task.detached { [weak queue] in
            queue?.dispatch(.two(3))
        }
        queue = nil
        await task.value
        
        // then
        let received = await receiver.received
        XCTAssertEqual(received, [.one])
    }
}
