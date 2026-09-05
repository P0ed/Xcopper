import AppKit
import RealityKit

@MainActor
final class PreviewScene {
	let root = Entity()

	private let stage = ModelEntity()
	private let eye = PerspectiveCamera()
	private var standing: (board: Board, finish: Finish)?
	private var moving: Bool?
	private var fieldOfView: Double?
	private var shades: [Shade] = []

	init() {
		root.addChild(stage)
		root.addChild(eye)

		for (travel, intensity) in PreviewScene.lighting {
			let light = DirectionalLight()
			light.light.intensity = intensity
			eye.addChild(light)
			light.look(at: travel, from: .zero, relativeTo: eye)
		}
	}

	private static let lighting: [(SIMD3<Float>, Float)] = [
		(SIMD3(0.35, -0.45, -1.0), 2_600.0),
		(SIMD3(-0.6, 0.3, -1.0), 900.0),
		(SIMD3(0.1, 0.9, 0.4), 600.0),
	]

	func show(_ board: Board, finish: Finish) {
		guard standing?.board != board || standing?.finish != finish else { return }
		let rebuilding = standing?.board != board || standing?.finish.shape != finish.shape
		standing = (board, finish)

		guard rebuilding else {
			stage.model?.materials = shades.map { shade in
				PreviewScene.material(shade.rgb(finish))
			}
			return
		}
		let drawn = board.model(finish.shape).surfaces.filter { $0.corners.count >= 3 }
		shades = drawn.map(\.shade)
		stage.model = component(of: drawn, finish: finish)
	}

	func aim(_ camera: Camera) {
		eye.transform = Transform(matrix: camera.pose)
		guard fieldOfView != camera.fov else { return }
		fieldOfView = camera.fov
		eye.camera = PerspectiveCameraComponent(
			near: Float(Camera.near * V3.metre),
			far: Float(Camera.far * V3.metre),
			fieldOfViewInDegrees: Float(camera.fov * 180.0 / .pi),
			fieldOfViewOrientation: .vertical
		)
	}

	func rendering(changedToMoving moving: Bool, force: Bool = false) -> Bool {
		guard force || self.moving != moving else { return false }
		self.moving = moving
		return true
	}

	private func component(of drawn: [Surface], finish: Finish) -> ModelComponent? {
		guard !drawn.isEmpty else { return nil }

		let descriptors = drawn.enumerated().map { index, surface in
			var descriptor = MeshDescriptor(name: "surface \(index)")
			descriptor.positions = MeshBuffers.Positions(surface.corners.map(\.placed))
			descriptor.normals = MeshBuffers.Normals(surface.normals.map(\.turned))
			descriptor.primitives = .triangles(PreviewScene.winding(of: surface))
			descriptor.materials = .allFaces(UInt32(index))
			return descriptor
		}
		guard let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
		return ModelComponent(
			mesh: mesh,
			materials: drawn.map { surface in PreviewScene.material(surface.shade.rgb(finish)) }
		)
	}

	private static func winding(of surface: Surface) -> [UInt32] {
		var indices: [UInt32] = []
		indices.reserveCapacity(surface.corners.count)
		for corner in stride(from: 0, to: surface.corners.count - 2, by: 3) {
			indices.append(contentsOf: [UInt32(corner + 2), UInt32(corner + 1), UInt32(corner)])
		}
		return indices
	}

	private static func material(_ color: RGBA) -> PhysicallyBasedMaterial {
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(tint: NSColor(
			srgbRed: color.r,
			green: color.g,
			blue: color.b,
			alpha: 1.0
		))
		material.roughness = 0.45
		material.metallic = 0.0
		if color.a < 1.0 {
			material.blending = .transparent(opacity: .init(scale: Float(color.a)))
		}
		return material
	}
}
