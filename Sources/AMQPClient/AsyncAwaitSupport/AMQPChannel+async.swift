//===----------------------------------------------------------------------===//
//
// This source file is part of the RabbitMQNIO project
//
// Copyright (c) 2023 RabbitMQNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5) && canImport(_Concurrency)

import NIOCore
import AMQPProtocol

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public extension AMQPChannel {
    /// Close the channel.
    /// - Parameters:
    ///     - reason: Any message - might be logged by the server.
    ///     - code: Any number - might be logged by the server.
    func close(reason: String = "", code: UInt16 = 200) async throws {
        return try await self.close(reason: reason, code: code).get()
    }

    /// Publish a ByteBuffer message to exchange or queue.
    /// - Parameters:
    ///     - body: Message payload that can be read from ByteBuffer.
    ///     - exchange: Name of exchange on which the message is published. Can be empty.
    ///     - routingKey: Name of routingKey that will be attached to the message.
    ///         An exchange looks at the routingKey while deciding how the message has to be routed.
    ///         When exchange parameter is empty routingKey is used as queueName.
    ///     - mandatory: When a published message cannot be routed to any queue and mendatory is true, the message will be returned to publisher.
    ///         Returned message must be handled with returnListner or returnConsumer.
    ///         When a published message cannot be routed to any queue and mendatory is false, the message is discarded or republished to an alternate exchange, if any.
    ///     - immediate: When matching queue has a least one or more consumers and immediate is set to true, message is delivered to them immediately.
    ///         When mathing queue has zero active consumers and immediate is set to true, message is returned to publisher.
    ///         When mathing queue has zero active consumers and immediate is set to false, message will be delivered to the queue.
    ///     - properties: Additional message properties (check amqp documentation).
    /// - Returns: DeliveryTag waiting for message write to the server.
    ///     DeliveryTag is 0 when channel is not in confirm mode.
    ///     DeliveryTag is > 0 (monotonically increasing) when channel is in confirm mode.
    @discardableResult
    func basicPublish(
        from body: ByteBuffer,
        exchange: String,
        routingKey: String,
        mandatory: Bool = false,
        immediate: Bool = false,
        properties: Properties = Properties()
    ) async throws -> AMQPResponse.Channel.Basic.Published {
        return try await self.basicPublish(from: body,
                                           exchange: exchange,
                                           routingKey: routingKey,
                                           mandatory: mandatory,
                                           immediate: immediate,
                                           properties: properties).get()
    }

    /// Consume publish confirm messages.
    /// When channel is in confirm mode broker sends whether published message was accepted.
    /// - Parameters:
    ///     - name: Name of the consumer.
    /// - Returns: Async stream of publish confirm messages.
    func publishConsume(named name: String) async throws -> AMQPSequence<AMQPResponse.Channel.Basic.PublishConfirm> {
        return AMQPStream(channel: self, named: name).makeAsyncSequence()
    }

    /// Consume publish return messages.
    /// When broker cannot route message to any queue it sends a return message.
    /// - Parameters:
    ///     - name: Name of the consumer.
    /// - Returns: Async stream of publish return messages.
    func returnConsume(named name: String) async throws -> AMQPSequence<AMQPResponse.Channel.Message.Return> {
        return AMQPStream(channel: self, named: name).makeAsyncSequence()
    }

    /// Get a single message from a queue.
    /// - Parameters:
    ///     - queue: Name of the queue.
    ///     - noAck: Controls whether message will be acked or nacked automatically (true) or manually (false).
    /// - Returns: Message when queue is not empty.
    func basicGet(queue: String, noAck: Bool = false) async throws -> AMQPResponse.Channel.Message.Get? {
        return try await self.basicGet(queue: queue, noAck: noAck).get()
    }

    /// Consumes message from a queue by sending them to registered consumeListeners.
    /// - Parameters:
    ///     - queue: name of the queue.
    ///     - consumerTag: name of consumer if empty will be generated by broker.
    ///     - noAck: controls whether message will be acked or nacked automatically (true) or manually (false).
    ///     - exclusive: Flag ensures that queue can only be consumed by single consumer.
    ///     - arguments: Additional arguments (check rabbitmq documentation).
    /// - Returns: ConsumerTag confirming that broker has accepted a new consumer.
    @discardableResult
    func basicConsume(
        queue: String,
        consumerTag: String = "",
        noAck: Bool = false,
        exclusive: Bool = false,
        args arguments: Table = Table(),
        listener: @escaping @Sendable (Result<AMQPResponse.Channel.Message.Delivery, Error>) -> Void
    ) async throws -> AMQPResponse.Channel.Basic.ConsumeOk {
        return try await self.basicConsume(queue: queue, consumerTag: consumerTag, noAck: noAck, exclusive:exclusive, args: arguments, listener: listener).get()
    }

    /// Consume delivery messages from a queue.
    /// When basic consume has started broker sends delivery messages to consumer.
    /// - Parameters:
    ///     - queue: Name of the queue.
    ///     - consumerTag: Name of the consumer if empty will be generated by the broker.
    ///     - noAck: Controls whether message will be acked or nacked automatically (true) or manually (false).
    ///     - exclusive: Flag ensures that queue can only be consumed by single consumer.
    ///     - args: Additional arguments (check rabbitmq documentation).
    /// - Returns: Async stream of delivery messages.
    func basicConsume(
        queue: String,
        consumerTag: String = "",
        noAck: Bool = false,
        exclusive: Bool = false,
        args arguments: Table = Table()
    ) async throws -> AMQPSequence<AMQPResponse.Channel.Message.Delivery> {
        return try await self.basicConsume(queue: queue, consumerTag: consumerTag, noAck: noAck, exclusive: exclusive, args: arguments).map { response in
            AMQPStream(
                channel: self,
                named: response.consumerTag,
                onCancelled: { listener in
                    do {
                        try listener.channel.basicCancelNoWait(consumerTag: listener.name)
                    } catch AMQPConnectionError.consumerAlreadyCancelled {}
                },
                onThrowSkip: { err in
                    if let err = err as? AMQPConnectionError, case .consumerCancelled = err {
                        return true
                    }
                    return false
                }
            ).makeAsyncSequence()
        }.get()
    }

    /// Cancel sending messages from server to consumer.
    /// - Parameters:
    ///     - consumerTag: Identifer of the consumer.
    func basicCancel(consumerTag: String) async throws { 
        return try await self.basicCancel(consumerTag: consumerTag).get()
    }

    /// Acknowledge a message.
    /// - Parameters:
    ///     - deliveryTag: Number (identifier) of the message.
    ///     - multiple: Controls whether only this message is acked (false) or additionally all other up to it (true).
    func basicAck(deliveryTag: UInt64, multiple: Bool = false) async throws {
        return try await self.basicAck(deliveryTag: deliveryTag, multiple: multiple).get()
    }

    /// Acknowledge a message.
    /// - Parameters:
    ///     - message: Received Message.
    ///     - multiple: Controls whether only this message is acked (false) or additionally all other up to it (true).
    func basicAck(message: AMQPResponse.Channel.Message.Delivery,  multiple: Bool = false) async throws {
        return try await self.basicAck(message: message, multiple: multiple).get()
    }

    /// Reject a message.
    /// - Parameters:
    ///     - deliveryTag: Number (identifier) of the message.
    ///     - multiple: Controls whether only this message is rejected (false) or additionally all other up to it (true).
    ///     - requeue: Controls whether to requeue message after reject.
    func basicNack(deliveryTag: UInt64, multiple: Bool = false, requeue: Bool = false) async throws {
        return try await self.basicNack(deliveryTag: deliveryTag, multiple: multiple, requeue: requeue).get()
    }

    /// Reject a message.
    /// - Parameters:
    ///     - message: Received Message.
    ///     - multiple: Controls whether only this message is rejected (false) or additionally all other up to it (true).
    ///     - requeue: Controls whether to requeue message after reject.
    func basicNack(message: AMQPResponse.Channel.Message.Delivery, multiple: Bool = false, requeue: Bool = false) async throws  {
        return try await self.basicNack(message: message, multiple: multiple, requeue: requeue).get()
    }

    /// Reject a message.
    /// - Parameters:
    ///     - deliveryTag: Number (identifier) of the message.
    ///     - requeue: Controls whether to requeue message after reject.
    func basicReject(deliveryTag: UInt64, requeue: Bool = false) async throws {
        return try await self.basicReject(deliveryTag: deliveryTag, requeue: requeue).get()
    }

    /// Reject a message.
    /// - Parameters:
    ///     - message: Received Message.
    ///     - requeue: Controls whether to requeue message after reject.
    func basicReject(message: AMQPResponse.Channel.Message.Delivery, requeue: Bool = false) async throws {
        return try await self.basicReject(message: message, requeue: requeue).get()
    }

    /// Tell the broker what to do with all unacknowledge messages.
    /// Unacknowledged messages retrieved by `basicGet` are requeued regardless.
    /// - Parameters:
    func basicRecover(requeue: Bool) async throws {
        return try await self.basicRecover(requeue: requeue).get()
    }

    /// Set a prefetch limit when consuming messages.
    /// No more messages will be delivered to the consumer until one or more message have been acknowledged or rejected.
    /// - Parameters:
    ///     - count: Size of the limit.
    ///     - global: Whether the limit will be shared across all consumers on the channel.
    func basicQos(count: UInt16, global: Bool = false) async throws {
        return try await self.basicQos(count: count, global: global).get()
    }

    /// Send a flow message to broker to start or stop sending message to consumers.
    /// Warning: Not supported by all brokers.
    /// - Parameters:
    ///     - active: Flow enabled or disabled.
    /// - Returns: Response confirming that broker has accepted a flow request.
    @discardableResult
    func flow(active: Bool) async throws -> AMQPResponse.Channel.Flowed { 
        return try await self.flow(active: active).get()
    }

    /// Consume flow messages.
    /// When broker cannot keep up with amount of published messages it sends a flow (false) message.
    /// When broker is again ready to handle new messages it sends a flow (true) message.
    /// - Parameters:
    ///     - name: Name of consumer.
    /// - Returns: Async stream of flow messages.
    func flowConsume(named name: String) async throws -> AMQPSequence<Bool> {
        return AMQPStream(channel: self, named: name).makeAsyncSequence()
    }

    /// Declare a queue.
    /// - Parameters:
    ///     - name: Name of the queue.
    ///     - passive: If enabled broker will raise exception if queue already exists.
    ///     - durable: If enabled creates a queue stored on disk otherwise transient.
    ///     - exclusive: If enabled queue will be deleted when the channel is closed.
    ///     - auto_delete: If enabled queue will be deleted when the last consumer has stopped consuming.
    ///     - arguments: Additional arguments (check rabbitmq documentation).
    /// - Returns: Response confirming that broker has accepted a declare request.
    @discardableResult
    func queueDeclare(
        name: String,
        passive: Bool = false,
        durable: Bool = false,
        exclusive: Bool = false,
        autoDelete: Bool = false,
        args arguments: Table =  Table()
    ) async throws -> AMQPResponse.Channel.Queue.Declared {
        return try await self.queueDeclare(name: name, passive: passive, durable: durable, exclusive: exclusive, autoDelete: autoDelete, args: arguments).get()
    }

    /// Delete a queue.
    /// - Parameters:
    ///     - name: Name of the queue.
    ///     - ifUnused: If enabled queue will be deleted only when there is no consumers subscribed to it.
    ///     - ifEmpty: If enabled queue will be deleted only when it's empty.
    /// - Returns: Response confirming that broker has accepted a delete request.
    @discardableResult
    func queueDelete(name: String, ifUnused: Bool = false, ifEmpty: Bool = false) async throws -> AMQPResponse.Channel.Queue.Deleted {
        return try await self.queueDelete(name: name, ifUnused: ifUnused, ifEmpty: ifEmpty).get()
    }

    /// Delete all message from a queue.
    /// - Parameters:
    ///     - name: Name of the queue.
    /// - Returns: Response confirming that broker has accepted a delete request.
    @discardableResult
    func queuePurge(name: String) async throws -> AMQPResponse.Channel.Queue.Purged {
        return try await self.queuePurge(name: name).get()
    }

    /// Bind a queue to an exchange.
    /// - Parameters:
    ///     - queue: Name of the queue.
    ///     - exchange: Name of the exchange.
    ///     - routingKey: Bind only to messages matching routingKey.
    ///     - arguments: Bind only to message matching given options.
    func queueBind(queue: String, exchange: String, routingKey: String = "", args arguments: Table =  Table()) async throws {
        return try await self.queueBind(queue: queue, exchange: exchange, routingKey: routingKey, args: arguments).get()
    }

    /// Unbind a queue from an exchange.
    /// - Parameters:
    ///     - queue: Name of the queue.
    ///     - exchange: Name of the exchange.
    ///     - routingKey: Unbind only from messages matching routingKey.
    ///     - arguments: Unbind only from messages matching given options.
    func queueUnbind(queue: String, exchange: String, routingKey: String = "", args arguments: Table =  Table()) async throws {
        return try await self.queueUnbind(queue: queue, exchange: exchange, routingKey: routingKey, args: arguments).get()
    }

    /// Declare an exchange.
    /// - Parameters:
    ///     - name: Name of the exchange.
    ///     - passive: If enabled broker will raise exception if exchange already exists.
    ///     - durable: If enabled creates a exchange stored on disk otherwise transient.
    ///     - auto_delete: If enabled exchange will be deleted when the last consumer has stopped consuming.
    ///     - internal: Whether the exchange cannot be directly published to client.
    ///     - arguments: Additional arguments (check rabbitmq documentation).
    func exchangeDeclare(
        name: String,
        type: String,
        passive: Bool = false,
        durable: Bool = false,
        autoDelete: Bool = false,
        internal: Bool = false,
        args arguments: Table = Table()
    ) async throws {
        return try await self.exchangeDeclare(name: name,
                                              type: type,
                                              passive: passive,
                                              durable: durable,
                                              autoDelete: autoDelete,
                                              internal: `internal`, args: arguments).get()
    }

    /// Delete an exchange.
    /// - Parameters:
    ///     - name: Name of the queue.
    ///     - ifUnused: If enabled exchange will be deleted only when it's not used.
    func exchangeDelete(name: String, ifUnused: Bool = false) async throws {
        return try await self.exchangeDelete(name: name, ifUnused: ifUnused).get()
    }

    /// Bind an exchange to another exchange.
    /// - Parameters:
    ///     - destination: Output exchange.
    ///     - source: Input exchange.
    ///     - routingKey: Bind only to messages matching routingKey.
    ///     - arguments: Bind only to message matching given options.
    func exchangeBind(destination: String, source: String, routingKey: String, args arguments: Table = Table()) async throws {
        return try await self.exchangeBind(destination: destination, source: source, routingKey: routingKey, args: arguments).get()
    }

    /// Unbind an exchange from another exchange.
    /// - Parameters:
    ///     - destination: Output exchange.
    ///     - source: Input exchange.
    ///     - routingKey: Unbind only from messages matching routingKey.
    ///     - arguments: Unbind only from message matching given options.
    func exchangeUnbind(destination: String, source: String, routingKey: String, args arguments: Table = Table()) async throws {
        return try await self.exchangeUnbind(destination: destination, source: source, routingKey: routingKey, args: arguments).get()
    }

    /// Set channel in publish confirm mode, each published message will be acked or nacked.
    func confirmSelect() async throws {
        return try await self.confirmSelect().get()
    }

    /// Set channel in transaction mode.
    func txSelect() async throws {
        return try await self.txSelect().get()
    }

    /// Commit a transaction.
    func txCommit() async throws {
        return try await self.txCommit().get()
    }

    /// Rollback a transaction.
    func txRollback() async throws {
        return try await self.txRollback().get()
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct AMQPSequence<Element>: AsyncSequence {
    public typealias BackingStream = AsyncThrowingStream<Element, Error>

    let backing: BackingStream
    public let name: String
    
    init(_ backing: BackingStream, name: String) {
        self.backing = backing
        self.name = name
    }

    public __consuming func makeAsyncIterator() -> BackingStream.AsyncIterator {
        return self.backing.makeAsyncIterator()
    }
}

final class AMQPStream<Element> {
    typealias CancelledCallback = (AMQPStream) throws -> Void
    typealias ThrowSkipCallback = (Error) -> Bool
    
    let channel: AMQPChannel
    let name: String
    let onCancelled: CancelledCallback?
    let onThrowSkip: ThrowSkipCallback?

    init(channel: AMQPChannel, named name: String, onCancelled: CancelledCallback? = nil, onThrowSkip: ThrowSkipCallback? = nil) {
        self.channel = channel
        self.name = name
        self.onCancelled = onCancelled
        self.onThrowSkip = onThrowSkip
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public func makeAsyncSequence() -> AMQPSequence<Element> {
        let stream = AsyncThrowingStream<Element, Error> { cont in
            do {
                try self.channel.addCloseListener(named: name) { result in
                    switch result {
                    case .success:
                        cont.finish()
                    case .failure(let error):
                        if let callback = self.onThrowSkip {
                            if callback(error) {
                                return cont.finish()
                            }
                        }

                        return cont.finish(throwing: error)
                    }
                }
            } catch {
                cont.finish(throwing: error)
            }

            do {
                try self.channel.addListener(type: Element.self, named: name) { result in
                    switch result {
                    case .success(let value):
                        cont.yield(value)
                    case .failure(let error):
                        if let callback = self.onThrowSkip {
                            if callback(error) {
                                return cont.finish()
                            }
                        }
                        return cont.finish(throwing: error)
                    }
                }
            } catch {
                cont.finish(throwing: error)
            }

            cont.onTermination = { result in
                if case .cancelled = result {
                    if let callback = self.onCancelled {
                        do {
                            try callback(self)
                        } catch {
                            //TODO: add debugg logging
                        }
                    }
                }

                self.channel.removeListener(type: Element.self, named: self.name)
                self.channel.removeCloseListener(named: self.name)
            }
        }

        return AMQPSequence(stream, name: self.name)
    }
}

#endif // compiler(>=5.5)
