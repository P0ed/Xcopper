import AppKit
import MCP
import SwiftUI

@MainActor
final class MCPDocumentEntry {
	struct Context {
		var design: Binding<Design>
		var operations: Operations
		var undoManager: UndoManager?
	}

	let id: UUID
	weak var native: NSDocument?
	var contexts: [ObjectIdentifier: Context] = [:]
	private(set) var revision = 1
	private var snapshot: Design
	private var historyObservers: [NSObjectProtocol] = []
	private weak var observedUndo: UndoManager?
	var fileOperation = false
	var proposals: [UUID: MCPConnectionProposal] = [:]

	init(id: UUID, native: NSDocument, design: Design) {
		self.id = id
		self.native = native
		snapshot = design
	}

	func observeHistory(_ manager: UndoManager?) {
		guard observedUndo !== manager else { return }
		for observer in historyObservers { NotificationCenter.default.removeObserver(observer) }
		historyObservers.removeAll()
		observedUndo = manager
		guard let manager else { return }
		for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
			historyObservers.append(NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
				Task { @MainActor in
					guard let self, !self.contexts.isEmpty else { return }
					self.refresh()
				}
			})
		}
	}

	func dispose() {
		proposals.removeAll()
		for observer in historyObservers { NotificationCenter.default.removeObserver(observer) }
		historyObservers.removeAll()
		contexts.removeAll()
	}

	var context: Context { contexts.values.first! }
	var design: Design { context.design.wrappedValue }
	var url: URL? { native?.fileURL }
	var history: UndoManager? { context.undoManager ?? native?.undoManager }

	func refresh() {
		let current = design
		if current != snapshot { revision += 1; snapshot = current; proposals.removeAll() }
	}

	func requireRevision(_ args: MCPArguments) throws {
		refresh()
		guard try args.int("expectedRevision") == revision else {
			throw MCPFailure("stale_revision", "The document changed. Call xcopper_get_design and retry with revision \(revision) and new object handles.")
		}
	}

	func requireIdle() throws {
		guard !fileOperation, NSApp.modalWindow == nil, contexts.values.allSatisfy({ context in
			let op = context.operations
			return op.editor.keysAvailable && !op.layout.gestureActive && !op.schematic.gestureActive
				&& op.layout.traceSession == nil && op.layout.selectSession == nil && op.layout.moveSession == nil && op.layout.modulePlacement == nil
				&& op.schematic.wireSession == nil && op.schematic.selectSession == nil && op.schematic.moveSession == nil && op.schematic.modulePlacement == nil
		}) else { throw MCPFailure("busy", "Finish or cancel the current gesture, route, placement or editing dialog, then retry.") }
	}

	func commit(_ candidate: Design, name: String) throws {
		guard let native, !native.isInViewingMode else { throw MCPFailure("read_only", "This document is open for viewing. Open an editable copy first.") }
		guard let undo = history else { throw MCPFailure("history_unavailable", "Document history is not available yet. Retry after its window opens.") }
		if candidate != design {
			undo.undoGroup(name) { context.design.wrappedValue = candidate }
			refresh()
		}
		for context in contexts.values {
			context.operations.layout.resetTransientInteractions()
			context.operations.schematic.resetTransientInteractions()
		}
	}

	func handle(_ kind: String, _ key: String) -> String { "\(id.uuidString):\(revision):\(kind):\(key)" }
	func handle(_ ref: Ref) -> String {
		switch ref {
		case let .footprint(i): handle("part", String(i))
		case let .pad(i, p): handle("pad", "\(i)/\(p)")
		case let .trace(i): handle("trace", String(i))
		case let .via(i): handle("via", String(i))
		case let .hole(i): handle("hole", String(i))
		case let .module(id): handle("module", id.uuidString)
		}
	}

	func object(_ handle: String, in design: Design, editable: Bool = true) throws -> (kind: String, key: String) {
		let prefix = "\(id.uuidString):\(revision):"
		guard handle.hasPrefix(prefix) else { throw MCPFailure("stale_revision", "Object handles belong to one document revision. Inspect the design again.") }
		let components = handle.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
		guard components.count == 2 else { throw MCPFailure("invalid_object", "Malformed object handle.") }
		let kind = String(components[0]), key = String(components[1])
		let board = design.resolved.board
		let i = Int(key) ?? -1
		let native = design.board
		var valid = false
		var readOnly = false
		switch kind {
		case "part": valid = board.footprints.indices.contains(i); readOnly = !native.footprints.indices.contains(i)
		case "trace": valid = board.traces.indices.contains(i); readOnly = !native.traces.indices.contains(i)
		case "via": valid = board.vias.indices.contains(i); readOnly = !native.vias.indices.contains(i)
		case "hole": valid = board.holes.indices.contains(i); readOnly = !native.holes.indices.contains(i)
		case "wire": valid = native.wires.indices.contains(i)
		case "module": valid = design.modules.contains { $0.id.uuidString == key }
		case "pad":
			let components = key.split(separator: "/", omittingEmptySubsequences: false)
			let indices = components.compactMap { Int($0) }
			valid = components.count == 2 && indices.count == 2 && board.footprints.indices.contains(indices[0]) && board.footprints[indices[0]].pads.indices.contains(indices[1])
			readOnly = true
		default: break
		}
		guard valid else { throw MCPFailure("invalid_object", "The object does not exist in this revision.") }
		guard !editable || !readOnly else { throw MCPFailure("read_only", "Pads and imported module internals are read only. Edit the part's pin labels or open the module source document.") }
		return (kind, key)
	}

	func layoutRefs(_ handles: [String], in design: Design, editable: Bool = true) throws -> Set<Ref> {
		try Set(handles.map {
			let object = try object($0, in: design, editable: editable)
			switch object.kind {
			case "part": return .footprint(Int(object.key)!)
			case "trace": return .trace(Int(object.key)!)
			case "via": return .via(Int(object.key)!)
			case "hole": return .hole(Int(object.key)!)
			case "module": return .module(UUID(uuidString: object.key)!)
			case "pad":
				let indices = object.key.split(separator: "/").map { Int($0)! }
				return .pad(indices[0], indices[1])
			default: throw MCPFailure("wrong_view", "Wire handles require view schematic.")
			}
		})
	}

	func schematicRefs(_ handles: [String], in design: Design) throws -> Set<SchematicRef> {
		try Set(handles.map {
			let object = try object($0, in: design)
			switch object.kind {
			case "part": return .symbol(Int(object.key)!)
			case "wire": return .wire(Int(object.key)!)
			case "module": return .module(UUID(uuidString: object.key)!)
			default: throw MCPFailure("wrong_view", "Schematic selections accept parts, wires and modules.")
			}
		})
	}

	func summary() -> MCP.Value {
		refresh()
		return .object([
			"documentId": .string(id.uuidString), "revision": .int(revision),
			"name": .string(native?.displayName ?? "Untitled"), "path": url.map { .string($0.path) } ?? .null,
			"dirty": .bool(native?.isDocumentEdited ?? false), "busy": .bool((try? requireIdle()) == nil),
			"readOnly": .bool(native?.isInViewingMode ?? true), "canUndo": .bool(history?.canUndo ?? false), "canRedo": .bool(history?.canRedo ?? false)
		])
	}
}

@MainActor
final class MCPDocuments {
	static let shared = MCPDocuments()
	private var entries: [UUID: MCPDocumentEntry] = [:]
	private var aliases: [UUID: UUID] = [:]
	private var destinations: Set<URL> = []

	func reserve(_ url: URL) throws {
		guard destinations.insert(url.resolvingSymlinksInPath().standardizedFileURL).inserted else { throw MCPFailure("busy", "Another file operation is using this destination. Retry shortly.") }
	}

	func release(_ url: URL) { destinations.remove(url.resolvingSymlinksInPath().standardizedFileURL) }

	func remove(_ id: UUID) {
		entries.removeValue(forKey: id)?.dispose()
		aliases = aliases.filter { $0.value != id }
	}

	func observing(_ binding: Binding<Design>, id: UUID) -> Binding<Design> {
		Binding(get: { binding.wrappedValue }, set: { value, transaction in
			binding.transaction(transaction).wrappedValue = value
			if let entry = self.entries[self.aliases[id] ?? id], !entry.contexts.isEmpty { entry.refresh() }
		})
	}

	func register(id: UUID, window: NSWindow, design: Binding<Design>, operations: Operations, undoManager: UndoManager?) {
		guard let native = window.windowController?.document as? NSDocument,
			NSDocumentController.shared.documents.contains(where: { $0 === native }) else { return }
		let entry = entries.values.first(where: { $0.native === native }) ?? MCPDocumentEntry(id: entries[id] == nil ? id : UUID(), native: native, design: design.wrappedValue)
		entry.native = native
		entry.contexts[ObjectIdentifier(window)] = .init(design: design, operations: operations, undoManager: undoManager)
		entry.observeHistory(undoManager ?? native.undoManager)
		entries[entry.id] = entry
		aliases[id] = entry.id
		entry.refresh()
	}

	func detach(id: UUID, window: NSWindow) {
		guard let entry = entries[aliases[id] ?? id] else { return }
		entry.contexts.removeValue(forKey: ObjectIdentifier(window))
		if entry.contexts.isEmpty, !NSDocumentController.shared.documents.contains(where: { $0 === entry.native }) { remove(entry.id) }
	}

	var documents: [MCPDocumentEntry] {
		let live = NSDocumentController.shared.documents
		for (id, entry) in entries where !live.contains(where: { $0 === entry.native }) { remove(id) }
		return entries.values.filter { !$0.contexts.isEmpty }.sorted { $0.id.uuidString < $1.id.uuidString }
	}

	func entry(_ args: MCPArguments) throws -> MCPDocumentEntry {
		let id = try args.string("documentId")
		guard let entry = documents.first(where: { $0.id.uuidString == id }) else { throw MCPFailure("document_not_found", "This document is closed or unknown. Call xcopper_list_documents.") }
		entry.refresh()
		return entry
	}

	func open(_ url: URL) async throws -> MCPDocumentEntry {
		if let existing = documents.first(where: { $0.url?.resolvingSymlinksInPath().standardizedFileURL == url }) { return existing }
		let native: NSDocument = try await withCheckedThrowingContinuation { continuation in
			NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
				if let error { continuation.resume(throwing: error) }
				else if let document { continuation.resume(returning: document) }
				else { continuation.resume(throwing: MCPFailure("open_failed", "The native document could not be opened.")) }
			}
		}
		return try await registered(native)
	}

	func registered(_ native: NSDocument) async throws -> MCPDocumentEntry {
		for _ in 0 ..< 250 {
			if let entry = documents.first(where: { $0.native === native }) { return entry }
			try await Task.sleep(for: .milliseconds(20))
		}
		throw MCPFailure("busy", "The document window is still opening. Retry xcopper_list_documents shortly.")
	}

	func create(at url: URL) async throws -> MCPDocumentEntry {
		let native = try NSDocumentController.shared.makeUntitledDocument(ofType: "p0.xcopper.pcb")
		NSDocumentController.shared.addDocument(native)
		do { try await save(native, to: url) }
		catch { native.close(); throw error }
		native.makeWindowControllers()
		native.showWindows()
		return try await registered(native)
	}

	func save(_ native: NSDocument, to url: URL) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			native.save(to: url, ofType: native.fileType ?? "p0.xcopper.pcb", for: native.fileURL == url ? .saveOperation : .saveAsOperation) { error in
				if let error { continuation.resume(throwing: error) }
				else { continuation.resume() }
			}
		}
	}
}

@MainActor
struct MCPDocumentAttachment: NSViewRepresentable {
	let id: UUID
	let design: Binding<Design>
	let operations: Operations
	let undoManager: UndoManager?

	func makeNSView(context: Context) -> MCPDocumentProbe { MCPDocumentProbe() }

	func updateNSView(_ view: MCPDocumentProbe, context: Context) {
		view.attach = { window in MCPDocuments.shared.register(id: id, window: window, design: design, operations: operations, undoManager: undoManager) }
		view.detach = { window in MCPDocuments.shared.detach(id: id, window: window) }
		view.refresh()
	}

	static func dismantleNSView(_ view: MCPDocumentProbe, coordinator: ()) { view.release() }
}

@MainActor
final class MCPDocumentProbe: NSView {
	var attach: ((NSWindow) -> Void)?
	var detach: ((NSWindow) -> Void)?
	private weak var attachedWindow: NSWindow?
	private var observer: NSObjectProtocol?
	private var retry: Task<Void, Never>?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		refresh()
	}

	func refresh() {
		guard let window else { return }
		if attachedWindow !== window {
			release()
			attachedWindow = window
			observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.release() }
			}
		}
		if window.windowController?.document is NSDocument { attach?(window) }
		else if retry == nil {
			retry = Task { @MainActor [weak self] in
				do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
				self?.retry = nil
				self?.refresh()
			}
		}
	}

	func release() {
		retry?.cancel()
		retry = nil
		if let window = attachedWindow { detach?(window) }
		attachedWindow = nil
		if let observer { NotificationCenter.default.removeObserver(observer) }
		observer = nil
	}
}
