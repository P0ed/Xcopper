import AppKit
import RealityKit
import simd

@MainActor
final class LayoutScene {
	let root = Entity()

	private let eye = Entity()
	private let copper = LayoutGroup()
	private let highlights = LayoutGroup()
	private let silkscreen = LayoutGroup()
	private let connections = LayoutGroup()
	private let outline = LayoutGroup()
	private let faults = LayoutGroup()
	private let grid = LayoutGroup()
	private let sessions = LayoutGroup()
	private let sorting = ModelSortGroup(depthPass: .postPass)
	private var renderer: LayoutRenderer?
	private var selection: Set<Ref> = []
	private var shown: (design: Design, state: LayoutState)?

	init() {
		root.addChild(eye)
		for group in [copper, highlights, silkscreen, connections, outline, faults, grid, sessions] {
			root.addChild(group.root)
		}
	}

	func show(_ design: Design, state: LayoutState) {
		let previous = shown?.state
		let changed = shown?.design != design
			|| previous?.moveDelta != state.moveDelta
			|| (state.moveDelta != nil && (previous?.selection != state.selection || previous?.routingGrid != state.routingGrid))
			|| previous?.modulePlacement != state.modulePlacement
			|| previous?.placementPoint != state.placementPoint
			|| (state.modulePlacement != nil && previous?.placementGrid != state.placementGrid)
		let previousBounds = renderer?.board.bounds
		if changed { renderer = LayoutRenderer(design: design, state: state) }
		guard let renderer else { return }
		let bounds = previousBounds != renderer.board.bounds
		let selected = changed || previous?.selection != state.selection
		if selected { selection = renderer.selection(state.selection) }
		let layers = previous?.layer != state.layer || previous?.hiddenLayers != state.hiddenLayers || previous?.stack != state.stack
		let scale = previous?.viewport.magnification != state.viewport.magnification
		if changed || layers { replace(copper, with: renderer.copper(state)) }
		if selected || layers || scale {
			replace(highlights, with: renderer.highlights(state, selection: selection))
		}
		if selected || scale || previous?.silkscreen != state.silkscreen {
			replace(silkscreen, with: renderer.silkscreen(state, selection: selection))
		}
		if changed || scale || previous?.ratsnest != state.ratsnest {
			replace(connections, with: renderer.connections(state))
		}
		if bounds || scale { replace(outline, with: renderer.outline(state)) }
		if changed || scale { replace(faults, with: renderer.faults(state)) }
		if bounds || scale || previous?.grid != state.grid {
			replace(grid, with: renderer.grid(state))
		}
		if changed || scale || previous?.tool != state.tool || previous?.traceWidth != state.traceWidth
			|| previous?.traceSession != state.traceSession || previous?.selectSession != state.selectSession
			|| previous?.cursorPoint != state.cursorPoint {
			replace(sessions, with: renderer.sessions(state))
		}
		if scale || previous?.viewport.center != state.viewport.center || previous?.viewport.size != state.viewport.size {
			aim(state.viewport)
		}
		shown = (design, state)
	}

	private func aim(_ viewport: LayoutViewport) {
		guard viewport.size.width > 0, viewport.size.height > 0 else { return }
		var camera = Camera()
		camera.aim(at: .top)
		camera.target = V3(x: viewport.center.x, y: viewport.center.y, z: 0.0)
		eye.transform = Transform(matrix: camera.pose)
		let width = Float(viewport.size.width / viewport.magnification) * Float(V3.metre)
		let height = Float(viewport.size.height / viewport.magnification) * Float(V3.metre)
		let near = Float(Camera.near * V3.metre)
		let far = Float(Camera.far * V3.metre)
		let projection = simd_float4x4(columns: (
			SIMD4(2.0 / width, 0.0, 0.0, 0.0),
			SIMD4(0.0, 2.0 / height, 0.0, 0.0),
			SIMD4(0.0, 0.0, 1.0 / (far - near), 0.0),
			SIMD4(0.0, 0.0, far / (far - near), 1.0)
		))
		eye.components.set(ProjectiveTransformCameraComponent(projectionMatrix: projection))
	}

	private func replace(_ group: LayoutGroup, with model: Model) {
		let levels = Dictionary(grouping: model.pieces, by: \.level)
		for level in group.levels.keys.filter({ levels[$0] == nil }) {
			group.levels.removeValue(forKey: level)?.removeFromParent()
		}
		for level in levels.keys.sorted() {
			let surfaces = Model(pieces: levels[level] ?? []).surfaces.filter { $0.corners.count >= 3 }
			guard let component = RealityMesh.component(of: surfaces, materials: surfaces.map { material($0.shade) }) else {
				group.levels.removeValue(forKey: level)?.removeFromParent()
				continue
			}
			let layer = group.levels[level] ?? ModelEntity()
			layer.model = component
			if group.levels[level] == nil {
				layer.components.set(ModelSortGroupComponent(group: sorting, order: Int32(level)))
				group.levels[level] = layer
				group.root.addChild(layer)
			}
		}
	}

	private func material(_ shade: Shade) -> UnlitMaterial {
		let color = shade.rgb(Finish())
		var material = UnlitMaterial(applyPostProcessToneMap: false)
		material.color = .init(tint: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1.0))
		if color.a < 1.0 {
			material.blending = .transparent(opacity: .init(scale: Float(color.a)))
		}
		return material
	}
}

@MainActor
private final class LayoutGroup {
	let root = Entity()
	var levels: [Int: ModelEntity] = [:]
}

private extension LayoutState {

	var moveDelta: Point? {
		guard let moveSession, moveSession.didMove else { return nil }
		return moveSession.delta
	}

	var placementPoint: Point? {
		modulePlacement == nil ? nil : viewport.cursor.snapped(to: placementGrid)
	}

	var cursorPoint: Point? {
		if let placementPoint { return placementPoint }
		return tool == .select ? nil : viewport.cursor
	}
}
