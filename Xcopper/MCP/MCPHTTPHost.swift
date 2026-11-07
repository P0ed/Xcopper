import Foundation
import MCP
import Synchronization
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

final class MCPSessionPermit: Sendable {
	private let valid = Mutex(true)
	var isValid: Bool { valid.withLock { $0 } }
	func revoke() { valid.withLock { $0 = false } }
}

actor MCPHTTPHost {
	private struct Session {
		let server: MCP.Server
		let transport: StatefulHTTPServerTransport
		let permit: MCPSessionPermit
		var lastUsed: Date
	}

	private struct SessionID: SessionIDGenerator {
		let value: String
		func generateSessionID() -> String { value }
	}

	private let port: Int
	private let token: String
	private let serverID: UUID
	private var group: MultiThreadedEventLoopGroup?
	private var channel: Channel?
	private var connections: [ObjectIdentifier: Channel] = [:]
	private var sessions: [String: Session] = [:]
	private var cleanup: Task<Void, Never>?
	private var running = false

	init(port: Int, token: String, serverID: UUID) {
		self.port = port
		self.token = token
		self.serverID = serverID
	}

	func start() async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
		self.group = group
		do {
			channel = try await ServerBootstrap(group: group)
				.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
				.childChannelInitializer { channel in
					channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
						channel.pipeline.addHandler(MCPHTTPHandler(host: self))
					}
				}
				.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
				.bind(host: "127.0.0.1", port: port).get()
			running = true
			cleanup = Task { [weak self] in
				while !Task.isCancelled {
					do { try await Task.sleep(for: .seconds(30)) } catch { return }
					await self?.expireSessions()
				}
			}
		} catch {
			try? await group.shutdownGracefully()
			self.group = nil
			throw error
		}
	}

	func stop() async {
		running = false
		cleanup?.cancel()
		cleanup = nil
		try? await channel?.close()
		channel = nil
		let active = sessions.values
		sessions.removeAll()
		for session in active { session.permit.revoke(); await session.transport.disconnect(); await session.server.stop() }
		for connection in connections.values { try? await connection.close() }
		connections.removeAll()
		try? await group?.shutdownGracefully()
		group = nil
	}

	func connected(_ channel: Channel) async {
		guard running else { try? await channel.close(); return }
		connections[ObjectIdentifier(channel)] = channel
	}

	func disconnected(_ channel: Channel) {
		connections.removeValue(forKey: ObjectIdentifier(channel))
	}

	private func expireSessions() async {
		let expired = sessions.filter { Date().timeIntervalSince($0.value.lastUsed) > 3600 }.map(\.key)
		for id in expired {
			if let session = sessions.removeValue(forKey: id) { session.permit.revoke(); await session.transport.disconnect(); await session.server.stop() }
		}
	}

	func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
		guard running else { return .error(statusCode: 503, .internalError("MCP server is stopped")) }
		guard request.path == "/mcp" else { return .error(statusCode: 404, .invalidRequest("Use /mcp")) }
		let hosts = ["127.0.0.1:\(port)", "localhost:\(port)"]
		guard let host = request.header("Host"), hosts.contains(host.lowercased()) else {
			return .error(statusCode: 421, .invalidRequest("Host must identify the local MCP endpoint"))
		}
		if let origin = request.header("Origin"), !hosts.map({ "http://" + $0 }).contains(origin.lowercased()) {
			return .error(statusCode: 403, .invalidRequest("Origin is not allowed"))
		}
		guard let auth = request.header("Authorization"), auth.prefix(7).lowercased() == "bearer ",
			Self.equalToken(String(auth.dropFirst(7)), token) else {
			return .error(statusCode: 401, .invalidRequest("A valid bearer token from AI Access settings is required"), extraHeaders: ["WWW-Authenticate": "Bearer realm=\"Xcopper\""])
		}
		if let id = request.header(HTTPHeaderName.sessionID) {
			guard var session = sessions[id] else { return .error(statusCode: 404, .invalidRequest("Session expired. Initialize a new session.")) }
			session.lastUsed = Date()
			sessions[id] = session
			let response = await session.transport.handleRequest(request)
			if request.method == "DELETE", response.statusCode == 200 {
				sessions.removeValue(forKey: id)
				session.permit.revoke()
				await session.server.stop()
			}
			return response
		}
		guard request.method == "POST", let body = request.body,
			let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
			json["method"] as? String == "initialize" else {
			return .error(statusCode: 400, .invalidRequest("Initialize a session, then send its MCP-Session-Id header."))
		}
		guard sessions.count < 32 else { return .error(statusCode: 503, .internalError("Too many MCP sessions. Close an existing session and retry.")) }
		let id = UUID().uuidString
		let permit = MCPSessionPermit()
		let transport = StatefulHTTPServerTransport(sessionIDGenerator: SessionID(value: id))
		let server = MCP.Server(
			name: "Xcopper", version: "1.0", instructions: "Edit the running Xcopper app. Geometry is integer micrometres, rotations are 0/90/180/270 degrees and copper layers are zero based. Inspect a document before editing; pass its current expectedRevision and revision-scoped object handles. Imported module internals are read only. File access requires a workspace selected in AI Access settings.",
			capabilities: .init(tools: .init(listChanged: false))
		)
		sessions[id] = Session(server: server, transport: transport, permit: permit, lastUsed: Date())
		await server.withMethodHandler(ListTools.self) { _ in .init(tools: MCPTools.catalog) }
		let serverID = serverID
		await server.withMethodHandler(CallTool.self) { params in await MCPTools.call(params, serverID: serverID, permit: permit) }
		do {
			try await server.start(transport: transport)
			guard running, sessions[id] != nil else {
				await transport.disconnect()
				await server.stop()
				return .error(statusCode: 503, .internalError("MCP server stopped during initialization"))
			}
			let response = await transport.handleRequest(request)
			if response.statusCode != 200 {
				sessions.removeValue(forKey: id)
				permit.revoke()
				await transport.disconnect()
				await server.stop()
			}
			return response
		} catch {
			sessions.removeValue(forKey: id)
			permit.revoke()
			await transport.disconnect()
			await server.stop()
			return .error(statusCode: 500, .internalError("Could not initialize the MCP session"))
		}
	}

	private static func equalToken(_ one: String, _ other: String) -> Bool {
		let a = Array(one.utf8), b = Array(other.utf8)
		guard a.count == b.count else { return false }
		return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
	}
}

private final class MCPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
	typealias InboundIn = HTTPServerRequestPart
	typealias OutboundOut = HTTPServerResponsePart
	private let host: MCPHTTPHost
	private var head: HTTPRequestHead?
	private var body = Data()
	private var task: Task<Void, Never>?
	private var received = false

	init(host: MCPHTTPHost) { self.host = host }

	func channelActive(context: ChannelHandlerContext) {
		let channel = context.channel
		Task { await host.connected(channel) }
		context.fireChannelActive()
	}

	func channelInactive(context: ChannelHandlerContext) {
		task?.cancel()
		let channel = context.channel
		Task { await host.disconnected(channel) }
		context.fireChannelInactive()
	}

	func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }

	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		guard !received else { return }
		switch unwrapInboundIn(data) {
		case .head(let head):
			self.head = head
		case .body(let buffer):
			guard body.count + buffer.readableBytes <= 4 * 1024 * 1024 else {
				received = true
				nonisolated(unsafe) let ctx = context
				task = Task { await self.write(.error(statusCode: 413, .invalidRequest("Request exceeds 4 MiB")), context: ctx) }
				return
			}
			body.append(contentsOf: buffer.readableBytesView)
		case .end:
			guard let head else { context.close(promise: nil); return }
			received = true
			var headers: [String: String] = [:]
			for (key, value) in head.headers {
				let name = key.lowercased()
				headers[name] = headers[name].map { $0 + ", " + value } ?? value
			}
			let request = MCP.HTTPRequest(method: head.method.rawValue, headers: headers, body: body.isEmpty ? nil : body, path: head.uri)
			nonisolated(unsafe) let ctx = context
			task = Task { await self.write(await self.host.handle(request), context: ctx) }
		}
	}

	private func write(_ response: MCP.HTTPResponse, context: ChannelHandlerContext) async {
		nonisolated(unsafe) let ctx = context
		let eventLoop = ctx.eventLoop
		await eventLoop.submit {
			var headers = HTTPHeaders(response.headers.map { ($0.key, $0.value) })
			headers.replaceOrAdd(name: "Connection", value: "close")
			if let data = response.bodyData { headers.replaceOrAdd(name: "Content-Length", value: String(data.count)) }
			let head = HTTPResponseHead(version: .http1_1, status: .init(statusCode: response.statusCode), headers: headers)
			ctx.writeAndFlush(self.wrapOutboundOut(.head(head)), promise: nil)
		}.getIgnoringFailure()
		if case let .stream(stream, _) = response {
			do {
				for try await chunk in stream {
					try Task.checkCancellation()
					try await eventLoop.flatSubmit {
						var buffer = ctx.channel.allocator.buffer(capacity: chunk.count)
						buffer.writeBytes(chunk)
						return ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
					}.get()
				}
			} catch { }
		} else if let data = response.bodyData {
			await eventLoop.submit {
				var buffer = ctx.channel.allocator.buffer(capacity: data.count)
				buffer.writeBytes(data)
				ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
			}.getIgnoringFailure()
		}
		await eventLoop.submit {
			ctx.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in ctx.close(promise: nil) }
		}.getIgnoringFailure()
	}
}

private extension EventLoopFuture where Value == Void {
	func getIgnoringFailure() async { _ = try? await get() }
}
