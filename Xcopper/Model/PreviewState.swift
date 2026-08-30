import SwiftUI

/// Where the board is being looked at from and what it is being shown as.
/// None of it belongs to the document: it is how the board is read, not what
/// the board is.
struct PreviewState: Equatable {
	var camera: Camera = .init()
	var finish: Finish = .init()
	/// The distance that frames the whole board, which zooming works out from
	var reach: Double = 120.0
	var canvas: CGSize = .zero
	var framed = false
}

extension PreviewState {

	/// Zoom on the scale the two flat canvases use, so the zoom commands can
	/// drive the camera without having to know that it is one
	var magnification: CGFloat {
		get { CGFloat(reach / max(camera.distance, 0.001)) * 4.0 }
		set { camera.zoom(to: reach * 4.0 / Double(max(newValue, 0.05)), reach: reach) }
	}

	/// Turns the view onto the whole of `board`, tall parts and all, and
	/// remembers what that took so zooming afterwards stays relative to it
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

	/// How far back the eye has to be for the whole of `box` to fit the canvas
	/// the way the camera is turned now. Fitting the box rather than the ball
	/// around it is what keeps a flat board from sitting in a sea of margin.
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

	/// Turns to a named standpoint and frames the board from it. How far back
	/// the whole board needs the eye to be depends on which way it is turned,
	/// so a standpoint that did not reframe would cut the board off.
	mutating func look(from stand: Standpoint, at board: Board) {
		camera.aim(at: stand)
		frame(board)
	}
}

extension Double {
	/// Radians as whole degrees, for the readout
	var degrees: Int { Int((self * 180.0 / .pi).rounded()) }
}
