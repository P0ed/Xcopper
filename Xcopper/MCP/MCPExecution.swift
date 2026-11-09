import AppKit
import Foundation
import MCPS

@MainActor
extension MCPTools {
	static func execute(_ name: String, _ args: MCPArguments) async throws -> MCPJSON {
		let documents = MCPDocuments.shared
		switch name {
		case "list_documents": return ["documents": .array(documents.documents.map { $0.summary() })]
		case "search_library": return try library(args.values["query"]?.stringValue ?? "")
		case "create_document":
			let path = try args.string("path")
			guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw MCPFailure("invalid_path", "Creation requires a workspace-relative .pcb path.") }
			let url = try MCPAccess.shared.workspacePath(path)
			try documents.reserve(url)
			defer { documents.release(url) }
			try checkDocumentDestination(url, args: args)
			guard !documents.documents.contains(where: { $0.url?.resolvingSymlinksInPath().standardizedFileURL == url }) else { throw MCPFailure("destination_open", "The destination is already open. Edit that document or choose another path.") }
			return try documentResponse(await documents.create(at: url), args)
		case "open_document":
			let path = try args.string("path")
			if path.hasPrefix("/"), let entry = documents.documents.first(where: { $0.url?.resolvingSymlinksInPath().standardizedFileURL == URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL }) { return try documentResponse(entry, args) }
			let url = try MCPAccess.shared.workspacePath(path)
			guard url.pathExtension.lowercased() == "pcb" else { throw MCPFailure("invalid_path", "Open a .pcb document.") }
			return try documentResponse(await documents.open(url), args)
		default: break
		}
		let entry = try documents.entry(args)
		switch name {
		case "get_design": return filterInspection(try entry.inspection(), args)
		case "check_design": return try entry.diagnostics()
		case "get_netlist": return try entry.netlist()
		case "render_design": return try renderDesign(args, entry: entry)
		case "plan_connection": return try await planConnection(args, entry: entry)
		case "list_module_sources": return try moduleSources(entry)
		case "save_document", "close_document":
			try entry.requireIdle()
			guard let native = entry.native else { throw MCPFailure("document_not_found", "Document closed.") }
			guard !native.isInViewingMode else { throw MCPFailure("read_only", "This document is open for viewing.") }
			let destination: URL
			if let path = args.values["path"]?.stringValue {
				if path.hasPrefix("/"), let current = entry.url,
					URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL == current.resolvingSymlinksInPath().standardizedFileURL {
					destination = current
				} else { destination = try MCPAccess.shared.workspacePath(path) }
				try checkDocumentDestination(destination, args: args, current: entry.url)
				guard !documents.documents.contains(where: { $0 !== entry && $0.url?.resolvingSymlinksInPath().standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL }) else { throw MCPFailure("destination_open", "The destination is open in another document.") }
			} else if let url = entry.url { destination = url }
			else { throw MCPFailure("destination_required", "Saving or closing an untitled document requires path to a .pcb file in the AI workspace.") }
			try documents.reserve(destination)
			defer { documents.release(destination) }
			entry.fileOperation = true
			defer { entry.fileOperation = false }
			try await documents.save(native, to: destination)
			guard documents.documents.contains(where: { $0 === entry }) else { throw MCPFailure("document_not_found", "The document was closed while saving.") }
			entry.fileOperation = false
			if name == "close_document" {
				guard !native.isDocumentEdited else { throw MCPFailure("busy", "The document changed while saving. Retry close_document.") }
				let summary = entry.summary().objectValue!
				native.close()
				documents.remove(entry.id)
				var result = summary
				result["closed"] = true
				return .object(result)
			}
			return try documentResponse(entry, args)
		case "export_fabrication":
			try entry.requireIdle()
			let design = entry.design
			let diagnostics = try entry.diagnostics()
			if !design.moduleErrors.isEmpty {
				var result = diagnostics.objectValue!
				result["error"] = ["code": "unresolved_modules", "message": "Resolve module sources before exporting. Inspect moduleErrors and reload_modules."]
				throw MCPExportFailure(result: .object(result))
			}
			guard args.values["allowViolations"] == true || diagnostics.objectValue?["violations"]?.arrayValue?.isEmpty == true else {
				var result = diagnostics.objectValue!
				result["error"] = ["code": "design_violations", "message": "DRC found violations. Inspect check_design, fix them or explicitly set allowViolations=true."]
				throw MCPExportFailure(result: .object(result))
			}
			let url = try MCPAccess.shared.workspacePath(args.string("path"))
			guard url != MCPAccess.shared.workspaceURL else { throw MCPFailure("invalid_path", "Export into a new subfolder of the workspace.") }
			guard !FileManager.default.fileExists(atPath: url.path) || args.values["overwrite"] == true else { throw MCPFailure("overwrite_required", "The export destination exists. Set overwrite=true to replace fabrication files, or choose a new destination.") }
			let stem = Fabrication.stem(entry.url?.deletingPathExtension().lastPathComponent ?? "Board")
			let files = design.fabrication(named: stem)
			try writeFabrication(files, to: url)
			var result = diagnostics.objectValue!
			result["path"] = .string(url.path)
			result["files"] = .array(files.map { .string(url.appendingPathComponent($0.name).path) })
			return .object(result)
		default: break
		}
		try entry.requireIdle()
		try entry.requireRevision(args)
		if name == "apply_connection" { return try applyConnection(args, entry: entry) }
		if name == "undo" || name == "redo" {
			let before = try entry.inspection()
			guard let native = entry.native, !native.isInViewingMode else { throw MCPFailure("read_only", "The document cannot be edited.") }
			guard let undo = entry.history, name == "undo" ? undo.canUndo : undo.canRedo else { throw MCPFailure("history_empty", "No \(name) step is available.") }
			if name == "undo" { undo.undo() } else { undo.redo() }
			entry.refresh()
			return try mutationResponse(entry, before: before, objects: nil, compact: args.values["response"] == "compact")
		}
		if name == "fit_view" {
			let op = entry.context.operations
			if try args.string("view") == "layout" { op.editor.mode = .layout; op.layout.viewport.fit(entry.design.board.size) }
			else { op.editor.mode = .schematic; op.schematic.viewport.fit(entry.design.board.sheetSize) }
			return entry.summary()
		}
		if name == "reveal_objects" {
			let handles = try args.strings("objects")
			let op = entry.context.operations
			if try args.string("view") == "layout" {
				let refs = try entry.layoutRefs(handles, in: entry.design, editable: false)
				op.editor.mode = .layout
				op.layout.selection = refs
				for ref in refs {
					if case let .trace(index) = ref { op.layout[visible: entry.design.resolved.board.traces[index].layer] = true }
				}
				if let point = entry.design.layoutBounds(refs)?.center { op.layout.viewport.reveal(point) }
			} else {
				let refs = try entry.schematicRefs(handles, in: entry.design)
				op.editor.mode = .schematic
				op.schematic.selection = refs
				if let point = entry.design.schematicBounds(refs)?.center { op.schematic.viewport.reveal(point) }
			}
			entry.native?.showWindows()
			return entry.summary()
		}
		return try performEdits(name, args, entry: entry)
	}

	private static func checkDocumentDestination(_ url: URL, args: MCPArguments, current: URL? = nil) throws {
		guard url.pathExtension.lowercased() == "pcb" else { throw MCPFailure("invalid_path", "The document destination must end in .pcb.") }
		if current?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL { return }
		guard !FileManager.default.fileExists(atPath: url.path) || args.values["overwrite"] == true else { throw MCPFailure("overwrite_required", "The destination exists. Set overwrite=true or choose a new path.") }
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue else { throw MCPFailure("invalid_path", "The destination's parent folder must exist inside the workspace.") }
		if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { throw MCPFailure("invalid_path", "The destination is a folder. Choose a .pcb file path.") }
	}

	private static func writeFabrication(_ files: [Fabrication.File], to url: URL) throws {
		let parent = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
		var directory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
		guard !exists || directory.boolValue else { throw MCPFailure("invalid_path", "The export destination must be a folder.") }
		for file in files {
			let destination = url.appendingPathComponent(file.name)
			_ = try MCPAccess.shared.workspacePath(destination.path)
			if FileManager.default.fileExists(atPath: destination.path, isDirectory: &directory), directory.boolValue {
				throw MCPFailure("invalid_path", "A folder conflicts with fabrication file \(file.name). Choose another export destination.")
			}
		}
		let stage = parent.appendingPathComponent(".xcopper-export-" + UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: stage) }
		try Fabrication.write(files, to: stage)
		if exists {
			for file in files {
				let destination = url.appendingPathComponent(file.name)
				let source = stage.appendingPathComponent(file.name)
				if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: source) }
				else { try FileManager.default.moveItem(at: source, to: destination) }
			}
		} else { try FileManager.default.moveItem(at: stage, to: url) }
	}
}

struct MCPExportFailure: LocalizedError {
	var result: MCPJSON
	var errorDescription: String? { "DRC violations require allowViolations=true." }
}
