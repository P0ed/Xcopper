import Foundation
import XCTest
@testable import Xcopper

final class FolderAccessTests: XCTestCase {
	func testBridgedFolderAncestryStopsAtTheFilesystemRoot() {
		let folder = NSURL(fileURLWithPath: "/Users/Example/Modules/Base", isDirectory: true) as URL
		let ancestors = folder.ancestorDirectories
		XCTAssertEqual(ancestors.map(\.path), ["/Users/Example/Modules/Base", "/Users/Example/Modules", "/Users/Example", "/Users", "/"])
		XCTAssertFalse(ancestors.contains { $0.pathComponents.contains("..") })
	}

	func testBridgedRootAppearsExactlyOnce() {
		let root = NSURL(fileURLWithPath: "/", isDirectory: true) as URL
		XCTAssertEqual(root.ancestorDirectories.map(\.path), ["/"])
	}

	func testRelativeFolderAncestryIsNormalizedAndIncludesEachParent() {
		let base = URL(fileURLWithPath: "/Users/Example/Modules/Function", isDirectory: true)
		let folder = URL(fileURLWithPath: "../Base/./Nested", relativeTo: base)
		let ancestors = folder.ancestorDirectories
		XCTAssertEqual(ancestors.map(\.path), ["/Users/Example/Modules/Base/Nested", "/Users/Example/Modules/Base", "/Users/Example/Modules", "/Users/Example", "/Users", "/"])
		XCTAssertTrue(ancestors.allSatisfy { $0.baseURL == nil })
	}

	@MainActor
	func testAutomaticModuleReloadAcceptsBridgedDocumentURLsWithoutInteraction() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		var source = Design()
		source.place(Symbol.Spec(kind: .resistor), at: Point(x: 10000, y: 10000))
		try Document(design: source).encoded().write(to: directory.appendingPathComponent("Base.pcb"))
		var design = Design()
		design.modules = [ModuleInstance(reference: "M1", filename: "Base")]
		let harness = EditorHarness(design: design)
		harness.url = NSURL(fileURLWithPath: directory.appendingPathComponent("Parent.pcb").path) as URL
		harness.undo.disableUndoRegistration()
		defer { harness.undo.enableUndoRegistration() }
		harness.operations.reloadModules(automatic: true)
		XCTAssertTrue(harness.design.moduleErrors.isEmpty)
		XCTAssertEqual(harness.design.resolved.board.footprints.map(\.reference), ["M1.R1"])
		XCTAssertFalse(harness.undo.canUndo)
	}

	@MainActor
	func testMCPModuleAccessWithoutAGrantReturnsAnErrorForBridgedURLs() {
		let folder = NSURL(fileURLWithPath: "/xcopper-no-grant-" + UUID().uuidString, isDirectory: true) as URL
		let access = MCPModuleAccess(folder: folder, workspace: nil)
		defer { access.close() }
		XCTAssertThrowsError(try access.library()) { XCTAssertEqual(($0 as? MCPFailure)?.code, "access_required") }
	}
}
