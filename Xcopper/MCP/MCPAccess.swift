import AppKit
import MCP
import Observation
import Security
import SwiftUI

struct MCPFailure: LocalizedError {
	var code: String
	var message: String
	var details: [String: MCPJSON]
	var errorDescription: String? { message }

	init(_ code: String, _ message: String, details: [String: MCPJSON] = [:]) {
		self.code = code
		self.message = message
		self.details = details
	}
}

@MainActor
@Observable
final class MCPAccess {
	static let shared = MCPAccess()
	var port: Int {
		didSet { UserDefaults.standard.set(port, forKey: "mcp.port") }
	}
	private(set) var workspaceURL: URL?
	private(set) var isRunning = false
	private(set) var transitioning = false
	private(set) var serverID = UUID()
	var error: String?
	private var host: MCPHTTPHost?
	private var scopedWorkspace: URL?

	var endpoint: String { "http://127.0.0.1:\(port)/mcp" }
	var status: String { transitioning ? "Changing server state…" : isRunning ? "Running" : "Stopped" }

	private init() {
		let saved = UserDefaults.standard.integer(forKey: "mcp.port")
		port = (1024 ... 65535).contains(saved) ? saved : 8765
		if let data = UserDefaults.standard.data(forKey: "mcp.workspace") {
			do {
				var stale = false
				let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
				guard url.startAccessingSecurityScopedResource() else { throw MCPFailure("access_denied", "Select the workspace folder again in AI Access settings.") }
				scopedWorkspace = url
				workspaceURL = url.resolvingSymlinksInPath().standardizedFileURL
				if stale { UserDefaults.standard.set(try url.bookmarkData(options: [.withSecurityScope]), forKey: "mcp.workspace") }
			} catch { self.error = error.localizedDescription }
		}
	}

	func start() async {
		guard !isRunning, !transitioning else { return }
		transitioning = true
		defer { transitioning = false }
		do {
			guard (1024 ... 65535).contains(port) else { throw MCPFailure("invalid_port", "Choose a port from 1024 to 65535.") }
			serverID = UUID()
			let host = MCPHTTPHost(port: port, token: try MCPToken.readOrCreate(), serverID: serverID)
			try await host.start()
			self.host = host
			isRunning = true
			error = nil
		} catch { self.error = error.localizedDescription }
	}

	func stop() async {
		guard !transitioning else { return }
		transitioning = true
		defer { transitioning = false }
		isRunning = false
		await host?.stop()
		host = nil
		isRunning = false
	}

	func regenerateToken() async {
		await stop()
		do { try MCPToken.replace(); error = nil }
		catch { self.error = error.localizedDescription }
	}

	func copyToken() {
		do {
			let token = try MCPToken.readOrCreate()
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(token, forType: .string)
			error = nil
		} catch { self.error = error.localizedDescription }
	}

	func copyConnection() {
		do {
			let config = ["mcpServers": ["xcopper": ["type": "http", "url": endpoint, "headers": ["Authorization": "Bearer \(try MCPToken.readOrCreate())"]]]] as [String: Any]
			let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
			error = nil
		} catch { self.error = error.localizedDescription }
	}

	func selectWorkspace() {
		let panel = NSOpenPanel()
		panel.title = "Choose AI Workspace"
		panel.message = "Agents can open, create and export files inside this folder."
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.directoryURL = workspaceURL
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			let bookmark = try url.bookmarkData(options: [.withSecurityScope])
			guard url.startAccessingSecurityScopedResource() else { throw MCPFailure("access_denied", "Could not access the selected folder. Select it again.") }
			scopedWorkspace?.stopAccessingSecurityScopedResource()
			scopedWorkspace = url
			workspaceURL = url.resolvingSymlinksInPath().standardizedFileURL
			UserDefaults.standard.set(bookmark, forKey: "mcp.workspace")
			error = nil
		} catch { self.error = error.localizedDescription }
	}

	func workspacePath(_ path: String) throws -> URL {
		guard let workspaceURL else { throw MCPFailure("access_required", "Choose a workspace folder in Xcopper Settings → AI Access, then retry.") }
		guard !path.isEmpty, !path.contains("\0") else { throw MCPFailure("invalid_path", "Provide a file path inside the workspace.") }
		let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : workspaceURL.appendingPathComponent(path)
		let resolved = url.resolvingSymlinksInPath().standardizedFileURL
		guard resolved.pathComponents.starts(with: workspaceURL.pathComponents) else {
			throw MCPFailure("access_required", "The path leaves the AI workspace. Select a workspace containing that destination in AI Access settings.")
		}
		return resolved
	}

	func moduleAccess(for documentURL: URL?) throws -> MCPModuleAccess {
		guard let documentURL else { throw MCPFailure("destination_required", "Save the document in the AI workspace before loading modules.") }
		return MCPModuleAccess(folder: documentURL.deletingLastPathComponent(), workspace: workspaceURL)
	}
}

@MainActor
final class MCPModuleAccess {
	private let folder: URL
	private var scopes: [URL] = []
	private var allowed: [URL]

	init(folder: URL, workspace: URL?) {
		self.folder = folder
		allowed = workspace.map { [$0] } ?? []
	}

	func close() {
		for scope in scopes { scope.stopAccessingSecurityScopedResource() }
		scopes.removeAll()
	}

	func library() throws -> ModuleLibrary { try ModuleLibrary(folder: folder, access: allow) }

	func read(_ url: URL) throws -> Data {
		try allow(url)
		return try Data(contentsOf: url)
	}

	private func allow(_ url: URL) throws {
		let resolved = url.resolvingSymlinksInPath().standardizedFileURL
		if allowed.contains(where: { resolved.pathComponents.starts(with: $0.pathComponents) }) { return }
		var candidate = url.standardizedFileURL
		while true {
			let key = "moduleFolder." + candidate.path
			if let data = UserDefaults.standard.data(forKey: key) {
				var stale = false
				if let scope = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale),
					resolved.pathComponents.starts(with: scope.resolvingSymlinksInPath().standardizedFileURL.pathComponents), scope.startAccessingSecurityScopedResource() {
					scopes.append(scope)
					allowed.append(scope.resolvingSymlinksInPath().standardizedFileURL)
					if stale, let fresh = try? scope.bookmarkData(options: [.withSecurityScope]) { UserDefaults.standard.set(fresh, forKey: key) }
					return
				}
			}
			let parent = candidate.deletingLastPathComponent()
			if parent == candidate { break }
			candidate = parent
		}
		throw MCPFailure("access_required", "Module access is missing for \(resolved.path). Choose a containing AI workspace, or grant this folder through Reload Modules in Xcopper, then retry.")
	}
}

@MainActor
enum MCPToken {
	private static let query: [String: Any] = [
		kSecClass as String: kSecClassGenericPassword,
		kSecAttrService as String: "p0.xcopper.mcp",
		kSecAttrAccount as String: "bearer-token"
	]

	static func readOrCreate() throws -> String {
		var lookup = query
		lookup[kSecReturnData as String] = true
		lookup[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: CFTypeRef?
		let status = SecItemCopyMatching(lookup as CFDictionary, &result)
		if status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty { return token }
		guard status == errSecItemNotFound else { throw failure(status) }
		let token = try generate()
		var item = query
		item[kSecValueData as String] = Data(token.utf8)
		item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		let added = SecItemAdd(item as CFDictionary, nil)
		guard added == errSecSuccess else { throw failure(added) }
		return token
	}

	static func replace() throws {
		let token = try generate()
		let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
		if updated == errSecItemNotFound { _ = try readOrCreate(); return }
		guard updated == errSecSuccess else { throw failure(updated) }
	}

	private static func generate() throws -> String {
		var bytes = [UInt8](repeating: 0, count: 32)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else { throw failure(status) }
		return bytes.map { String(format: "%02x", $0) }.joined()
	}

	private static func failure(_ status: OSStatus) -> MCPFailure {
		MCPFailure("keychain_error", "Could not access the MCP token in Keychain (\(status)). Unlock your login Keychain and retry.")
	}
}

@MainActor
struct MCPServerCommands: View {
	@State private var access = MCPAccess.shared

	var body: some View {
		Button(access.isRunning ? "Stop MCP Server" : "Start MCP Server") {
			Task { if access.isRunning { await access.stop() } else { await access.start() } }
		}
		.disabled(access.transitioning)
		SettingsLink { Text("AI Access Settings…") }
	}
}

@MainActor
struct AIAccessSettings: View {
	@State private var access = MCPAccess.shared

	var body: some View {
		Form {
			LabeledContent("MCP server", value: access.status)
			HStack {
				Button(access.isRunning ? "Stop MCP Server" : "Start MCP Server") {
					Task { if access.isRunning { await access.stop() } else { await access.start() } }
				}
				.disabled(access.transitioning)
				Text("Starts stopped on every app launch.").foregroundStyle(.secondary)
			}
			TextField("Port", value: $access.port, format: .number.grouping(.never))
				.disabled(access.isRunning || access.transitioning)
			LabeledContent("Endpoint") { Text(access.endpoint).textSelection(.enabled) }
			LabeledContent("Workspace") {
				Text(access.workspaceURL?.path ?? "No folder selected").lineLimit(2).textSelection(.enabled)
				Button("Choose…") { access.selectWorkspace() }
			}
			Text("Agents can edit open documents and access files inside the workspace. Connect with Streamable HTTP and an Authorization: Bearer token header.")
				.foregroundStyle(.secondary)
			HStack {
				Button("Copy Token") { access.copyToken() }
				Button("Copy Connection JSON") { access.copyConnection() }
				Button("Regenerate Token") { Task { await access.regenerateToken() } }
					.disabled(access.transitioning)
			}
			Text("Regenerating the token stops the server and disconnects clients.").foregroundStyle(.secondary)
			if let error = access.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
		}
		.formStyle(.grouped)
		.padding()
		.frame(width: 620)
	}
}
