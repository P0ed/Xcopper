import AppKit
import RealityKit
import simd

@MainActor
final class LayoutScene {
	let root = Entity()

	private let eye = Entity()
	private let copper = Entity()
	private let guides = Entity()
	private let grid = Entity()
	private let sessions = Entity()
	private let sorting = ModelSortGroup(depthPass: .postPass)
	private var renderer: LayoutRenderer?
	private var shown: (design: Design, state: LayoutState)?

	init() {
		for entity in [eye, copper, guides, grid, sessions] { root.addChild(entity) }
	}

	func show(_ design: Design, state: LayoutState) {
		let previous = shown?.state
		let changed = shown?.design != design
			|| previous?.moveSession != state.moveSession
			|| previous?.selection != state.selection
			|| previous?.routingGrid != state.routingGrid
		if changed { renderer = LayoutRenderer(design: design, state: state) }
		guard let renderer else { return }
		let layers = previous?.layer != state.layer || previous?.hiddenLayers != state.hiddenLayers
		let scale = previous?.viewport.magnification != state.viewport.magnification
		if changed || layers { replace(copper, with: renderer.copper(state)) }
		if changed || layers || scale || previous?.silkscreen != state.silkscreen {
			replace(guides, with: renderer.guides(state))
		}
		if changed || scale || previous?.grid != state.grid
			|| previous?.viewport.center != state.viewport.center || previous?.viewport.size != state.viewport.size {
			replace(grid, with: renderer.grid(state))
		}
		if changed || scale || previous?.tool != state.tool || previous?.traceWidth != state.traceWidth
			|| previous?.traceSession != state.traceSession || previous?.selectSession != state.selectSession
			|| previous?.viewport.cursor != state.viewport.cursor {
			replace(sessions, with: renderer.sessions(state))
		}
		aim(state.viewport)
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

	private func replace(_ entity: Entity, with model: Model) {
		entity.children.removeAll()
		let levels = Dictionary(grouping: model.pieces, by: \.level)
		for level in levels.keys.sorted() {
			let surfaces = Model(pieces: levels[level] ?? []).surfaces.filter { $0.corners.count >= 3 }
			let layer = ModelEntity()
			layer.model = RealityMesh.component(of: surfaces, materials: surfaces.map { material($0.shade) })
			layer.components.set(ModelSortGroupComponent(group: sorting, order: Int32(level)))
			entity.addChild(layer)
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
