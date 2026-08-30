import SwiftUI

extension PreviewView {

	func render(_ model: Model, in context: GraphicsContext, size: CGSize) {
		let projector = Projector(camera: state.camera, size: size)
		let pieces = model.pieces
		let depths = pieces.map { piece in projector.view(piece.at).z }

		// Back to front: level by level from the far face of the board towards
		// the eye, and by distance within a level, which only ever holds parts.
		// The board itself is opaque, so ordering what is on one side of it
		// against what is on the other never comes up.
		let sign = projector.overTop ? 1 : -1
		let order = pieces.indices.sorted { a, b in
			let levels = (pieces[a].level * sign, pieces[b].level * sign)
			return levels.0 != levels.1 ? levels.0 < levels.1 : depths[a] > depths[b]
		}
		for index in order {
			draw(pieces[index], in: context, with: projector)
		}
	}

	private func draw(_ piece: Piece, in context: GraphicsContext, with projector: Projector) {
		guard projector.faces(piece.normal, at: piece.at) else { return }
		guard let path = path(piece.loop, holes: piece.holes, with: projector) else { return }

		context.fill(
			path,
			with: .color(projector.shade(piece.color, normal: piece.normal)),
			style: FillStyle(eoFill: true)
		)
	}

	/// The outline and whatever is punched out of it, as one path filled odd
	/// even so that a hole reads through to what was painted under it
	private func path(_ loop: [V3], holes: [[V3]], with projector: Projector) -> Path? {
		var path = Path()
		guard add(loop, to: &path, with: projector) else { return nil }
		for hole in holes {
			_ = add(hole, to: &path, with: projector)
		}
		return path
	}

	private func add(_ loop: [V3], to path: inout Path, with projector: Projector) -> Bool {
		let visible = clippedToNear(loop.map(projector.view))
		guard visible.count >= 3 else { return false }

		path.move(to: projector.point(visible[0]))
		for point in visible.dropFirst() {
			path.addLine(to: projector.point(point))
		}
		path.closeSubpath()
		return true
	}
}
