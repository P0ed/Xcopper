import AppKit
import SwiftUI

@MainActor
private final class ModuleFolderAccess {
	private var scopes: [URL] = []
	private var folders: Set<URL> = []

	func allow(_ folder: URL) throws {
		let folder = folder.standardizedFileURL
		guard !folders.contains(where: { folder.pathComponents.starts(with: $0.pathComponents) }) else { return }
		if let scoped = try Self.acquire(to: folder) {
			scopes.append(scoped)
			folders.insert(scoped.standardizedFileURL)
		}
		folders.insert(folder)
	}

	func close() {
		for scoped in scopes { scoped.stopAccessingSecurityScopedResource() }
		scopes.removeAll()
		folders.removeAll()
	}

	static func acquire(to folder: URL) throws -> URL? {
		var candidate = folder.standardizedFileURL
		while true {
			let key = "moduleFolder." + candidate.path
			if let data = UserDefaults.standard.data(forKey: key) {
				var stale = false
				if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale),
					url.standardizedFileURL == candidate, url.startAccessingSecurityScopedResource() {
					if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) { UserDefaults.standard.set(fresh, forKey: key) }
					return url
				}
			}
			let parent = candidate.deletingLastPathComponent()
			if parent == candidate { break }
			candidate = parent
		}
		var scoped: URL?
		if (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) == nil {
			let panel = NSOpenPanel()
			panel.title = "Allow Access to Module Folder"
			panel.message = "Xcopper needs access to \(folder.lastPathComponent) to read modules. Select this folder or a parent folder containing your module library to retain access for reopening and reloads."
			panel.directoryURL = folder
			panel.canChooseDirectories = true
			panel.canChooseFiles = false
			panel.prompt = "Allow Access"
			guard panel.runModal() == .OK, let url = panel.url,
				folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
					.starts(with: url.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
			else { throw Err("Folder access was not granted. Use Reload Modules and select the source's containing folder or a parent folder.") }
			if url.startAccessingSecurityScopedResource() { scoped = url }
			do {
				let bookmark = try url.bookmarkData(options: [.withSecurityScope])
				UserDefaults.standard.set(bookmark, forKey: "moduleFolder." + url.standardizedFileURL.path)
			} catch {
				scoped?.stopAccessingSecurityScopedResource()
				throw error
			}
		}
		return scoped
	}
}

@MainActor
private final class ModulePickerController: NSWindowController, NSWindowDelegate {
	private var selection: String?

	init(names: [String], title: String, action: String, selected: String?) {
		let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
		panel.title = title
		panel.isReleasedWhenClosed = false
		super.init(window: panel)
		panel.delegate = self
		panel.contentView = NSHostingView(rootView: ModulePicker(names: names, action: action, selection: selected, confirm: { [weak self] name in
			self?.selection = name
			NSApp.stopModal()
		}, cancel: { NSApp.abortModal() }))
	}

	required init?(coder: NSCoder) { nil }

	func run() -> String? {
		guard let window else { return nil }
		window.center()
		NSApp.runModal(for: window)
		window.close()
		return selection
	}

	func windowWillClose(_ notification: Notification) {
		if NSApp.modalWindow === window { NSApp.abortModal() }
	}
}

@MainActor
private struct ModulePicker: View {
	var names: [String]
	var action: String
	@State var selection: String?
	var confirm: (String) -> Void
	var cancel: () -> Void
	@State private var query = ""
	@FocusState private var searchFocused: Bool

	private var filtered: [String] {
		names.filter { query.isEmpty || $0.localizedStandardContains(query) }
	}

	var body: some View {
		VStack(spacing: 12.0) {
			TextField("Search modules", text: $query)
				.textFieldStyle(.roundedBorder)
				.focused($searchFocused)
			List(filtered, id: \.self, selection: $selection) { name in
				Text(name).tag(name)
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(Rectangle())
					.onTapGesture(count: 2) { confirm(name) }
			}
			.overlay {
				if filtered.isEmpty { Text("No matching modules").foregroundStyle(.secondary) }
			}
			HStack {
				Spacer()
				Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
				Button(action) { if let selection { confirm(selection) } }
					.keyboardShortcut(.defaultAction)
					.disabled(selection == nil || !filtered.contains(selection ?? ""))
			}
		}
		.padding(16.0)
		.frame(width: 380, height: 460)
		.onAppear {
			if selection == nil || !names.contains(selection ?? "") { selection = names.first }
			searchFocused = true
		}
		.onChange(of: query) { _, _ in
			if !filtered.contains(selection ?? "") { selection = filtered.first }
		}
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

	private func pickModule(in library: ModuleLibrary, documentURL: URL, title: String, action: String, selected: String? = nil) throws -> String? {
		let documentURL = documentURL.resolvingSymlinksInPath().standardizedFileURL
		let names = library.urls.filter { $0 != documentURL }.map { ModuleLibrary.name(of: $0.lastPathComponent) }
			.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
		guard !names.isEmpty else { throw Err("No modules found. Add module sources to this folder or a subfolder, or add an alias to a module folder.") }
		return ModulePickerController(names: names, title: title, action: action, selected: selected).run()
	}

	func importModule() {
		guard let documentURL else {
			moduleAlert("Save this design before importing", "Save this design so Xcopper can search its folder for modules, then use Place Module again.")
			return
		}
		let access = ModuleFolderAccess()
		defer { access.close() }
		do {
			let library = try ModuleLibrary(folder: documentURL.deletingLastPathComponent(), access: access.allow)
			guard let name = try pickModule(in: library, documentURL: documentURL, title: "Place Module", action: "Place") else { return }
			var next = design
			let id = try next.importModule(filename: name, documentURL: documentURL, library: library)
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
		guard let module = design.modules.first(where: { $0.id == id }) else { return }
		guard let documentURL else {
			moduleAlert("Save this design before selecting a source", "Xcopper searches the saved document's folder and subfolders for modules.")
			return
		}
		let access = ModuleFolderAccess()
		defer { access.close() }
		do {
			let library = try ModuleLibrary(folder: documentURL.deletingLastPathComponent(), access: access.allow)
			guard let name = try pickModule(in: library, documentURL: documentURL, title: "Select Module Source", action: "Select", selected: module.name) else { return }
			var next = design
			let notices = try next.replaceModuleSource(id, filename: name, documentURL: documentURL, library: library)
			design = next
			layout.cancelSessions()
			schematic.cancelSessions()
			if !notices.isEmpty { moduleAlert("Module Source Changed", notices.joined(separator: "\n\n")) }
		} catch { moduleAlert("Could not change module source", error.localizedDescription) }
	}

	func reloadModules(automatic: Bool = false) {
		guard !design.modules.isEmpty else { return }
		guard let documentURL else {
			if !automatic { moduleAlert("Save this design before reloading", "Xcopper searches the saved document's folder and subfolders for modules.") }
			return
		}
		var next = design
		let access = ModuleFolderAccess()
		defer { access.close() }
		do {
			let folder = documentURL.deletingLastPathComponent()
			let library = try ModuleLibrary(folder: folder, access: access.allow)
			var resolver = ModuleResolver(folder: folder, library: library)
			resolver.reload(&next, documentURL: documentURL)
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
		let access = ModuleFolderAccess()
		do {
			let folder = documentURL.deletingLastPathComponent()
			let library = try ModuleLibrary(folder: folder, access: access.allow)
			let url = try library.url(for: module.name)
			NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
				Task { @MainActor in
					access.close()
					if error != nil { moduleAlert("Could not open module source", "Could not open module “\(module.name)”. Check its source and folder access.") }
				}
			}
		} catch {
			access.close()
			moduleAlert("Could not open module source", error.localizedDescription)
		}
	}

	func pasteModules() -> Set<UUID>? {
		guard !clipboard.modules.isEmpty else { return [] }
		guard let documentURL else {
			moduleAlert("Save this design before pasting modules", "Save the document so Xcopper can search its folder for modules, then paste again.")
			return nil
		}
		var next = design
		let access = ModuleFolderAccess()
		defer { access.close() }
		do {
			let library = try ModuleLibrary(folder: documentURL.deletingLastPathComponent(), access: access.allow)
			let ids = try next.pasteModules(clipboard.modules, by: pasteOffset, documentURL: documentURL, library: library)
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
		ValueRow(title: "Source", value: placement.instance.name)
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
						Text(module.name).lineLimit(1).truncationMode(.middle)
					}
					.help("Select a replacement module source")
				}
			} else {
				ValueRow(title: "Source", value: module.name)
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
						Button("\(module.reference) · \(module.name)") { operations.openModuleSource(module.id) }
							.buttonStyle(.borderless)
						if let error = operations.design.moduleStatus(module.id) { Text(error).foregroundStyle(.red).font(.caption) }
					}
				}
				ForEach(operations.design.moduleCache.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
			}
		}
	}
}
