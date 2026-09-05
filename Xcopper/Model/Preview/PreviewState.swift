import SwiftUI

struct PreviewState: Equatable {
	var camera: Camera = .init()
	var finish: Finish = .init()
	var reach: Double = 120.0
	var canvas: CGSize = .zero
	var framed = false
}

extension PreviewState {

	var magnification: CGFloat {
		get { CGFloat(reach / max(camera.distance, 0.001)) * 4.0 }
		set { camera.zoom(to: reach * 4.0 / Double(max(newValue, 0.05)), reach: reach) }
	}

	mutating func frame(_ board: Board) {
		let width = Double(board.size.width).mm
		let height = Double(board.size.height).mm
		let thickness = Double(finish.thickness).mm
		let above = finish.components ? board.standing(on: false) : 0.0
		let below = finish.components ? board.standing(on: true) : 0.0

		camera.target = V3(x: width / 2.0, y: height / 2.0, z: -thickness / 2.0)
		reach = distance(covering: V3.box(
			x: 0.0 ... width,
			y: 0.0 ... height,
			z: (-thickness - below) ... above
		))
		camera.distance = reach
		framed = true
	}

	private func distance(covering box: [V3]) -> Double {
		let vertical = tan(camera.fov / 2.0)
		let aspect = canvas.height > 0.0 ? Double(canvas.width / canvas.height) : 1.0
		let horizontal = vertical * max(aspect, 0.05)
		let (right, up, forward) = (camera.right, camera.up, camera.forward)

		var reach = 1.0
		for corner in box {
			let offset = corner - camera.target
			let depth = offset.dot(forward)
			reach = max(reach, abs(offset.dot(right)) / horizontal - depth)
			reach = max(reach, abs(offset.dot(up)) / vertical - depth)
		}
		return reach * 1.06
	}

	mutating func look(from stand: Standpoint, at board: Board) {
		camera.aim(at: stand)
		frame(board)
	}
}

extension Double {
	var degrees: Int { Int((self * 180.0 / .pi).rounded()) }
}
