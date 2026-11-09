import Foundation
import MCPS

actor MCPHTTPHost {
	private let server: HTTPServer

	init(port: Int, token: String, serverID: UUID) {
		server = HTTPServer(
			port: port, token: token, name: "Xcopper", version: "1.0",
			instructions: "Edit the running Xcopper app. Geometry is integer micrometres, rotations are 0/90/180/270 degrees and copper layers are zero based. Inspect a document before editing; pass its current expectedRevision and revision-scoped object handles. Imported module internals are read only. File access requires a workspace selected in AI Access settings.",
			tools: MCPTools.catalog
		) { params, permit in
			await MCPTools.call(params, serverID: serverID, permit: permit)
		}
	}

	func start() async throws { try await server.start() }
	func stop() async { await server.stop() }
}
