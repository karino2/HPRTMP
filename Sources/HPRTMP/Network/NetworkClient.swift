import Foundation
import NIO
import os

protocol NetworkConnectable {
  func connect(host: String, port: Int) async throws
  func sendData(_ data: Data) async throws
  func receiveData() async throws -> Data
  func close() async throws
}

final class RTMPClientHandler: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer
  private let responseCallback: (Data) -> Void
  
  init(responseCallback: @escaping (Data) -> Void) {
    self.responseCallback = responseCallback
  }
  
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = self.unwrapInboundIn(data)
    
    var data = Data()
    buffer.readWithUnsafeReadableBytes { ptr in
      data.append(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), count: ptr.count)
      return ptr.count
    }
    
    guard !data.isEmpty else { return }
    responseCallback(data)
  }
  
  func errorCaught(context: ChannelHandlerContext, error: Error) {
    print("error: ", error)
    context.close(promise: nil)
  }
}

class NetworkClient: NetworkConnectable {
  private let group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  private var channel: Channel?
  private var host: String?
  private var port: Int?
  
  private var cachedReceivedData: Data = .init()
  private var dataPromise: EventLoopPromise<Data>?
  
  private let logger = Logger(subsystem: "HPRTMP", category: "NetworkClient")

  
  init() {
  }
  
  deinit {
    let group = group
    Task {
      try? await group.shutdownGracefully()
    }
  }
  
  func connect(host: String, port: Int) async throws {
    self.host = host
    self.port = port
        
    let bootstrap = ClientBootstrap(group: group)
      .channelInitializer { channel in
        channel.pipeline.addHandlers([
          RTMPClientHandler(responseCallback: self.responseReceived)
        ])
      }
    
    do {
      self.channel = try await bootstrap.connect(host: host, port: Int(port)).get()
      logger.info("[HPRTMP] Connected to \(host):\(port)")
    } catch {
      logger.error("[HPRTMP]  Failed to connect: \(error)")
      throw error
    }
  }
  
  func sendData(_ data: Data) async throws {
    guard let channel = self.channel else {
      throw NSError(domain: "RTMPClientError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection not established"])
    }
    
    let buffer = channel.allocator.buffer(bytes: data)
    try await channel.writeAndFlush(buffer)
  }
  
  func receiveData() async throws -> Data {
    guard let channel = self.channel else {
      throw NSError(domain: "RTMPClientError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection not established"])
    }
    if !cachedReceivedData.isEmpty {
      logger.debug("[HPRTMP] use cachedReceivedData")
      let data = cachedReceivedData
      cachedReceivedData = Data()
      return data
    }

    /*
    let promise = channel.eventLoop.makePromise(of: Data.self)
    self.dataPromise = promise
    return try await promise.futureResult.get()
     */
    
    /*
    self.dataPromise = channel.eventLoop.makePromise(of: Data.self)
    return try await dataPromise!.futureResult.get()
     */
    self.dataPromise = channel.eventLoop.makePromise(of: Data.self)
    // --- dataPromise might be cleard in responseReceived between above line and below line. ----
    logger.debug("[HPRTMP] before future get")
    let ret = try await dataPromise?.futureResult.get()
    guard let ret else {
      print("DEBUG!!!!! race condition happens!")
      print("!!!!!!!!!!!!!!!!!!!!!!!")
      print("!!!!!!!!!!!!!!!!!!!!!!!")
      print("!!!!!!!!!!!!!!!!!!!!!!!")
      throw NSError(domain: "RTMPClientError", code: -1, userInfo: [NSLocalizedDescriptionKey: "dataPromise becomes nil: race condition!"])
    }
    logger.debug("[HPRTMP] after future get")
    return ret
  }
  
  private func responseReceived(data: Data) {
    logger.debug("[HPRTMP] responseReceived")
    cachedReceivedData.append(data)
    if let dataPromise {
      logger.debug("[HPRTMP] before dataPromise.succeed")
      dataPromise.succeed(cachedReceivedData)
      logger.debug("[HPRTMP] after dataPromise.succeed")
      cachedReceivedData = Data()
      logger.debug("[HPRTMP] cachedReceivedData cleard")
      self.dataPromise = nil
      logger.debug("[HPRTMP] dataPromise cleared")
    } else {
      logger.debug("[HPRTMP] dataPromise is nil")
    }
  }
  
  func close() async throws {
    dataPromise?.fail(NSError(domain: "RTMPClientError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection invalidated"]))
    let channel = self.channel
    dataPromise = nil
    self.channel = nil
    try await channel?.close()
  }
}
