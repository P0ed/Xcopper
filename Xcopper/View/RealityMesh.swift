import RealityKit

@MainActor
enum RealityMesh {
	static func component(of surfaces: [Surface], materials: [any Material]) -> ModelComponent? {
		guard !surfaces.isEmpty else { return nil }
		let descriptors = surfaces.enumerated().map { index, surface in
			var descriptor = MeshDescriptor(name: "surface \(index)")
			descriptor.positions = MeshBuffers.Positions(surface.corners.map(\.placed))
			descriptor.normals = MeshBuffers.Normals(surface.normals.map(\.turned))
			descriptor.primitives = .triangles(winding(of: surface))
			descriptor.materials = .allFaces(UInt32(index))
			return descriptor
		}
		guard let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
		return ModelComponent(mesh: mesh, materials: materials)
	}

	private static func winding(of surface: Surface) -> [UInt32] {
		var indices: [UInt32] = []
		indices.reserveCapacity(surface.corners.count)
		for corner in stride(from: 0, to: surface.corners.count - 2, by: 3) {
			indices.append(contentsOf: [UInt32(corner + 2), UInt32(corner + 1), UInt32(corner)])
		}
		return indices
	}
}
