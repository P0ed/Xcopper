import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
	var hasModuleSelection: Bool {
		switch mode {
		case .layout: layout.selection.hasModules
		case .schematic: schematic.selection.hasModules
		case .preview: false
		}
	}

	func moduleAlert(_ title: String, _ message: String) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.runModal()
	}

	func importModule() {
		guard let documentURL else {
			moduleAlert("Save this design before importing", "Save this design beside its .xcb module sources, then use Import Module again.")
			return
		}
		let panel = NSOpenPanel()
		panel.title = "Import Module"
		panel.allowedContentTypes = [.xcb]
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
			guard let instance = next.modules.first(where: { $0.id == id }),
				let content = next.moduleCache.contents[id] else { return }
			let placement = ModulePlacement(instance: instance, content: content)
			layout.resetTransientInteractions()
			schematic.resetTransientInteractions()
			editor.editing = nil
			if mode == .schematic {
				schematic.tool = .select
				schematic.modulePlacement = placement
			} else {
				layout.tool = .select
				layout.modulePlacement = placement
				editor.mode = .layout
			}
		} catch { moduleAlert("Could not import module", error.localizedDescription) }
	}

	func selectModuleSource(_ id: UUID) {
		guard design.modules.contains(where: { $0.id == id }) else { return }
		guard let documentURL else {
			moduleAlert("Save this design before selecting a source", "Module sources are resolved in the saved document's folder.")
			return
		}
		let folder = documentURL.deletingLastPathComponent()
		let panel = NSOpenPanel()
		panel.title = "Select Module Source"
		panel.prompt = "Select"
		panel.allowedContentTypes = [.xcb]
		panel.directoryURL = folder
		guard panel.runModal() == .OK, let source = panel.url else { return }
		do {
			var next = design
			let notices = try ModuleFolderAccess.withAccess(to: folder) {
				guard try ModuleResolver(folder: folder).url(for: source.lastPathComponent)
					== source.resolvingSymlinksInPath().standardizedFileURL else {
					throw Err("Move the module and its dependencies into the parent document's folder before selecting it.")
				}
				return try next.replaceModuleSource(id, filename: source.lastPathComponent, documentURL: documentURL)
			}
			design = next
			layout.cancelSessions()
			schematic.cancelSessions()
			if !notices.isEmpty { moduleAlert("Module Source Changed", notices.joined(separator: "\n\n")) }
		} catch { moduleAlert("Could not change module source", error.localizedDescription) }
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
			for module in next.modules { next.moduleCache.errors[module.id] = error.localizedDescription }
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
		} catch { moduleAlert("Could not open module source", error.localizedDescription) }
	}

	func pasteModules() -> Set<UUID>? {
		guard !clipboard.modules.isEmpty else { return [] }
		guard let documentURL else {
			moduleAlert("Save this design before pasting modules", "Place the module sources in the destination document's folder, save the document, and paste again.")
			return nil
		}
		var next = design
		do {
			let ids = try ModuleFolderAccess.withAccess(to: documentURL.deletingLastPathComponent()) {
				try next.pasteModules(clipboard.modules, by: pasteOffset, documentURL: documentURL)
			}
			design = next
			return ids
		} catch {
			moduleAlert("Could not paste modules", error.localizedDescription)
			return nil
		}
	}
}

@MainActor
struct ParametersPanel: View {
	@Binding var design: Design
	@FocusState.Binding var focus: Property?

	var body: some View {
		Panel(title: "Parameters") {
			if design.parameters.isEmpty {
				Text("Use #NAME as a schematic value to add a parameter.")
					.font(.caption).foregroundStyle(.secondary)
			} else {
				PropertyRow(title: "Name") {
					Text("Default").foregroundStyle(.secondary)
				}
				.font(.caption)
				ForEach(design.parameters) { parameter in
					TextRow(
						title: parameter.name, text: defaultValue(for: parameter.name),
						property: .moduleParameter(parameter.name), focus: $focus
					)
				}
			}
		}
	}

	private func defaultValue(for name: String) -> Binding<String> {
		Binding(
			get: { design.parameters.first { $0.name == name }?.defaultValue ?? "" },
			set: { value in
				guard let index = design.parameters.firstIndex(where: { $0.name == name }) else { return }
				design.parameters[index].defaultValue = value
			}
		)
	}
}

@MainActor
struct ModulePlacementInspector: View {
	var placement: ModulePlacement
	var cancel: () -> Void

	var body: some View {
		ValueRow(title: "Source", value: placement.instance.filename)
		ValueRow(title: "Ref", value: placement.instance.reference)
		Text("Move the pointer and click to place. Press Esc to cancel.")
			.font(.caption).foregroundStyle(.secondary)
		Button("Cancel", action: cancel).buttonStyle(.borderless)
	}
}

@MainActor
struct ModuleInspector: View {
	@Binding var design: Design
	var id: UUID
	var layout: Bool
	@FocusState.Binding var focus: Property?
	var selectSource: (() -> Void)? = nil
	@Environment(\.undoManager) private var undoManager

	private var module: ModuleInstance? { design.modules.first { $0.id == id } }
	var body: some View {
		if let module {
			if let selectSource {
				PropertyRow(title: "Source") {
					Button {
						focus = nil
						undoManager.undoGroup("Change module source", selectSource)
					} label: {
						Text(module.filename).lineLimit(1).truncationMode(.middle)
					}
					.help("Select a replacement module source")
				}
			} else {
				ValueRow(title: "Source", value: module.filename)
			}
			TextRow(title: "Ref", text: $design.reference(of: Ref.module(id)), property: .reference, focus: $focus)
			PositionRows(at: position, focus: $focus)
			ValuePicker(rotation: Binding(rotation))
			let status = design.moduleStatus(id)
			Text(status ?? "Resolved · \(module.interface.count) IO pins · \(module.layerCount) layers")
				.font(.caption).foregroundStyle(status == nil ? Color.secondary : Color.red)
			if !module.parameters.isEmpty {
				Text("Parameters").font(.caption).foregroundStyle(.secondary)
				ForEach(module.parameters) { parameter in
					HStack(spacing: 4.0) {
						TextRow(
							title: parameter.name, text: value(for: parameter),
							property: .moduleParameter(parameter.name), focus: $focus
						)
						Button("Use source value", systemImage: "arrow.uturn.backward") {
							setValue(nil, for: parameter)
						}
						.buttonStyle(.borderless)
						.labelStyle(.iconOnly)
						.disabled(module.parameterValues[parameter.name] == nil)
						.help("Use source value: \(parameter.defaultValue)")
					}
				}
			}
			if !layout { PinNetsInspector(pins: pins, focus: $focus) }
		}
	}

	private func value(for parameter: ModuleParameter) -> Binding<String> {
		Binding(
			get: { module?.value(for: parameter) ?? parameter.defaultValue },
			set: { setValue($0, for: parameter) }
		)
	}

	private func setValue(_ value: String?, for parameter: ModuleParameter) {
		guard let index = design.modules.firstIndex(where: { $0.id == id }) else { return }
		design.modules[index].parameterValues[parameter.name] = value
	}

	var pins: Binding<[Pin]> {
		Binding(
			get: { module?.symbol.pins ?? [] },
			set: { pins in
				guard let index = design.modules.firstIndex(where: { $0.id == id }) else { return }
				var module = design.modules[index]
				for pin in pins { module[netLabel: pin.number] = pin.netLabel }
				design.modules[index] = module
			}
		)
	}

	var position: Binding<Point> {
		Binding(get: { (layout ? module?.layoutAt : module?.schematicAt) ?? .zero },
			set: { design.positionModule(id, at: $0, layout: layout) })
	}

	var rotation: Binding<Rotation> {
		Binding(get: { (layout ? module?.layoutRotation : module?.schematicRotation) ?? .r0 },
			set: { design.turnModule(id, to: $0, layout: layout) })
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
			}
		}
	}
}
