import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Folder grants belong to this installation, never to a portable design file.
@MainActor
private enum ModuleFolderAccess {
	static func withAccess<T>(to folder: URL, _ body: () throws -> T) throws -> T {
		let scoped = try acquire(to: folder)
		defer { scoped?.stopAccessingSecurityScopedResource() }
		return try body()
	}

	static func acquire(to folder: URL) throws -> URL? {
		let key = "moduleFolder." + folder.standardizedFileURL.path
		var scoped: URL?
		if let data = UserDefaults.standard.data(forKey: key) {
			var stale = false
			if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale),
				url.standardizedFileURL == folder.standardizedFileURL, url.startAccessingSecurityScopedResource() {
				scoped = url
				if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) { UserDefaults.standard.set(fresh, forKey: key) }
			}
		}
		if scoped == nil, (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) == nil {
			let panel = NSOpenPanel()
			panel.title = "Allow Access to Module Folder"
			panel.message = "Xcopper needs access to \(folder.lastPathComponent) to read sibling modules. Select this folder to retain access for reopening and reloads."
			panel.directoryURL = folder
			panel.canChooseDirectories = true
			panel.canChooseFiles = false
			panel.prompt = "Allow Access"
			guard panel.runModal() == .OK, let url = panel.url,
				url.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath()
			else { throw Err("Folder access was not granted. Use Reload Modules and select the document's containing folder.") }
			if url.startAccessingSecurityScopedResource() { scoped = url }
			do {
				let bookmark = try url.bookmarkData(options: [.withSecurityScope])
				UserDefaults.standard.set(bookmark, forKey: key)
			} catch {
				scoped?.stopAccessingSecurityScopedResource()
				throw error
			}
		}
		return scoped
	}
}

extension Operations {
	var selectedModuleIDs: Set<UUID> {
		switch mode {
		case .layout: layout.selection.moduleIDs
		case .schematic: schematic.selection.moduleIDs
		case .preview: []
		}
	}
	var pastedModuleIDs: Set<UUID> { editor.pastedModuleIDs }
	var hasModuleSelection: Bool { !selectedModuleIDs.isEmpty }

	func moduleAlert(_ title: String, _ message: String) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.runModal()
	}

	func importModule() {
		guard let documentURL else {
			moduleAlert("Save this design before importing", "Save the parent board or module beside its .xcm sources, then use Import Module again.")
			return
		}
		let panel = NSOpenPanel()
		panel.title = "Import Module"
		panel.allowedContentTypes = [.xcm]
		panel.directoryURL = documentURL.deletingLastPathComponent()
		guard panel.runModal() == .OK, let source = panel.url else { return }
		do {
			let folder = documentURL.deletingLastPathComponent()
			let resolver = ModuleResolver(folder: folder)
			guard try resolver.url(for: source.lastPathComponent) == source.resolvingSymlinksInPath().standardizedFileURL else {
				throw Err("Move the module and its dependencies into the parent document's folder before importing.")
			}
			var next = design
			let id = try ModuleFolderAccess.withAccess(to: folder) {
				try next.importModule(filename: source.lastPathComponent, documentURL: documentURL)
			}
			design = next
			layout.selection = [.module(id)]
			schematic.selection = [.module(id)]
		} catch { moduleAlert("Could not import module", (error as? Err)?.description ?? error.localizedDescription) }
	}

	func reloadModules(automatic: Bool = false) {
		guard !design.modules.isEmpty else { return }
		guard let documentURL else {
			if !automatic { moduleAlert("Save this design before reloading", "Module sources are resolved in the saved document's folder.") }
			return
		}
		var next = design
		do {
			try ModuleFolderAccess.withAccess(to: documentURL.deletingLastPathComponent()) {
				var resolver = ModuleResolver(folder: documentURL.deletingLastPathComponent())
				resolver.reload(&next, documentURL: documentURL)
			}
		} catch {
			next.moduleCache = ModuleCache()
			for module in next.modules { next.moduleCache.errors[module.id] = (error as? Err)?.description ?? error.localizedDescription }
		}
		design = next
		layout.cancelSessions()
		schematic.cancelSessions()
		if !automatic {
			let messages = next.moduleErrors + next.moduleCache.notices
			if !messages.isEmpty { moduleAlert("Reload Modules", messages.joined(separator: "\n\n")) }
		}
	}

	func openModuleSource(_ id: UUID? = nil) {
		guard let id = id ?? selectedModuleIDs.first,
			let module = design.modules.first(where: { $0.id == id }), let documentURL else { return }
		do {
			let folder = documentURL.deletingLastPathComponent()
			let scoped = try ModuleFolderAccess.acquire(to: folder)
			do {
				let url = try ModuleResolver(folder: folder).url(for: module.filename)
				NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
					scoped?.stopAccessingSecurityScopedResource()
					if let error { Task { @MainActor in moduleAlert("Could not open module source", error.localizedDescription) } }
				}
			} catch {
				scoped?.stopAccessingSecurityScopedResource()
				throw error
			}
		} catch { moduleAlert("Could not open module source", (error as? Err)?.description ?? error.localizedDescription) }
	}

	func pasteModules() -> Bool {
		editor.pastedModuleIDs = []
		guard !clipboard.modules.isEmpty else { return true }
		guard let documentURL else {
			moduleAlert("Save this design before pasting modules", "Place the module sources in the destination document's folder, save the document, and paste again.")
			return false
		}
		var next = design
		do {
			let ids = try ModuleFolderAccess.withAccess(to: documentURL.deletingLastPathComponent()) {
				try next.pasteModules(clipboard.modules, by: Pt(x: Int(snap) * 4, y: Int(snap) * 4), documentURL: documentURL)
			}
			design = next
			editor.pastedModuleIDs = ids
			return true
		} catch {
			moduleAlert("Could not paste modules", (error as? Err)?.description ?? error.localizedDescription)
			return false
		}
	}
}

@MainActor
struct ModuleInspector: View {
	@Binding var design: Design
	var id: UUID
	var layout: Bool
	@FocusState.Binding var focus: Property?

	private var index: Int? { design.modules.firstIndex { $0.id == id } }
	var body: some View {
		if let index {
			let module = design.modules[index]
			ValueRow(title: "Source", value: module.filename)
			TextRow(title: "Ref", text: Binding(get: { module.reference }, set: { value in
				guard !value.trimmingWhitespace.isEmpty,
					!design.modules.contains(where: { $0.id != id && $0.reference == value }),
					!design.board.footprints.contains(where: { $0.reference == value }),
					!design.schematic.symbols.contains(where: { $0.reference == value }) else { return }
				design.modules[index].reference = value
			}), property: .reference, focus: $focus)
			PositionRows(at: Binding(get: { layout ? module.layoutAt : module.schematicAt }, set: { point in
				var next = design
				if layout {
					guard next.moveLayout([.module(id)], by: point - module.layoutAt, grid: .mm(0.5)) != nil else { return }
				} else { next.moveSchematic([.module(id)], by: point - module.schematicAt) }
				design = next
			}), focus: $focus)
			RotationChoice(rotation: Binding(get: { layout ? module.layoutRotation : module.schematicRotation }, set: { rotation in
				if layout { design.modules[index].layoutRotation = rotation }
				else { design.modules[index].schematicRotation = rotation }
			}))
			Text(design.moduleStatus(id) ?? "Resolved · \(module.interface.count) IO pins · \(module.layerCount) layers")
				.font(.caption).foregroundStyle(design.moduleStatus(id) == nil ? Color.secondary : Color.red)
		}
	}
}

@MainActor
struct ModulePanel: View {
	var operations: Operations
	var body: some View {
		if !operations.design.modules.isEmpty {
			Panel(title: "Modules") {
				ForEach(operations.design.modules) { module in
					VStack(alignment: .leading) {
						Button("\(module.reference) · \(module.filename)") { operations.openModuleSource(module.id) }
							.buttonStyle(.borderless)
						if let error = operations.design.moduleStatus(module.id) { Text(error).foregroundStyle(.red).font(.caption) }
					}
				}
				ForEach(operations.design.moduleCache.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
				Button("Reload Modules") { operations.reloadModules() }.buttonStyle(.borderless)
			}
		}
	}
}
