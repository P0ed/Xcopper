import AppKit
import RealityKit

/// The board as RealityKit holds it: one entity carrying the whole model, a
/// camera to look at it from, and the light that rides on that camera, so that
/// whichever side of the board is turned towards you is the side that is lit.
@MainActor
final class PreviewScene {
	let root = Entity()

	private let stage = ModelEntity()
	private let eye = PerspectiveCamera()
	private var standing: (board: Board, finish: Finish)?
	private var moving: Bool?
	private var fieldOfView: Double?
	/// What each surface of the board standing there is painted in, in the order
	/// the mesh carries them, so that a change of finish can repaint it
	private var shades: [Shade] = []

	init() {
		root.addChild(stage)
		root.addChild(eye)

		// A key light over the viewer's shoulder and two weaker ones filling in
		// from the other side, so that nothing turned away from the key goes to
		// black. All three hang off the camera and turn with it.
		for (travel, intensity) in PreviewScene.lighting {
			let light = DirectionalLight()
			light.light.intensity = intensity
			eye.addChild(light)
			light.look(at: travel, from: .zero, relativeTo: eye)
		}
	}

	/// Which way each light shines, in the camera's own axes, and how brightly
	private static let lighting: [(SIMD3<Float>, Float)] = [
		(SIMD3(0.35, -0.45, -1.0), 2_600.0),
		(SIMD3(-0.6, 0.3, -1.0), 900.0),
		(SIMD3(0.1, 0.9, 0.4), 600.0),
	]

	/// Builds the board, unless it is already the one standing there. Every turn
	/// of the view comes back through here, and cutting the same board into
	/// triangles again would be the whole of the work for none of it.
	///
	/// A mask or a plating picked in the sidebar changes what the board is
	/// painted in and not one corner of what it is made of, so it hands the
	/// triangles already cut a new set of materials and leaves them where they
	/// stand.
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
		// A surface with nothing in it is nothing to draw, and dropping it here
		// is what keeps a shade lined up with the material painting it
		let drawn = board.model(finish.shape).surfaces.filter { $0.corners.count >= 3 }
		shades = drawn.map(\.shade)
		stage.model = component(of: drawn, finish: finish)
	}

	/// Stands the eye where the camera says, looking the way it is turned
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

	/// Whether the RealityView's render targets need switching between the
	/// cheaper moving frame and the fully antialiased still one
	func rendering(changedToMoving moving: Bool, force: Bool = false) -> Bool {
		guard force || self.moving != moving else { return false }
		self.moving = moving
		return true
	}

	/// The surfaces as one mesh, each with the material its shade asks for
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

	/// The corners of each triangle, in the order the scene wants them. Board
	/// space is the mirror of scene space, so a face wound towards the eye on
	/// the board is wound away from it here until its corners are turned round.
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
		// Mask, laminate and moulding are all matt enough to read as themselves
		// under a light that moves with the eye; nothing on a board is a mirror
		material.roughness = 0.45
		material.metallic = 0.0
		if color.a < 1.0 {
			material.blending = .transparent(opacity: .init(scale: Float(color.a)))
		}
		return material
	}
}
