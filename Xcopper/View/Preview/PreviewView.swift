import AppKit
import SwiftUI

/// The board as it will come back from the fab: substrate, mask, copper and
/// the parts standing on it, painted back to front.
@MainActor
struct PreviewView: View {
	var board: Board
	@Binding var state: PreviewState

	@State private var model = Model()
	@GestureState private var grab: Grab?
	@GestureState private var pinch: Double?

	var body: some View {
		GeometryReader { geo in
			Canvas { context, size in
				render(model, in: context, size: size)
			}
			.background(Palette.backdrop)
			.gesture(controller)
			.gesture(magnifier)
			.modifier(ScrollWheel { delta in
				state.camera.zoom(by: exp(Double(delta) * 0.004), reach: state.reach)
			})
			.onChange(of: geo.size, initial: true) { _, new in
				guard new.width > 0.0, new.height > 0.0 else { return }
				state.canvas = new
				if !state.framed { state.frame(board) }
			}
		}
		.onChange(of: board, initial: true) { _, _ in rebuild() }
		.onChange(of: state.finish) { _, _ in rebuild() }
		.overlay(alignment: .bottomLeading) { readout }
	}

	private func rebuild() {
		model = board.model(finish: state.finish)
	}

	private var readout: some View {
		Readout {
			Text(state.camera.overTop ? "Top" : "Bottom")
				.foregroundStyle(Palette.color(of: state.camera.overTop ? 0 : 5, in: board.stack))
			Text("\(state.camera.azimuth.degrees)°, \(state.camera.elevation.degrees)° up")
			Text("\(state.finish.mask.name.lowercased()) \(state.finish.thickness.label) mm")
			Text("\(board.footprints.count) parts")
		}
	}

	/// What a drag was started as, so that it stays that until it is let go
	private struct Grab: Equatable {
		var camera: Camera
		var panning: Bool
	}

	/// Drag turns the board over, and holding shift slides it instead
	private var controller: some Gesture {
		DragGesture(minimumDistance: 0.0)
			.updating($grab) { gesture, grab, _ in
				if grab == nil {
					grab = Grab(
						camera: state.camera,
						panning: NSEvent.modifierFlags.contains(.shift)
					)
				}
				guard let start = grab else { return }

				var camera = start.camera
				if start.panning {
					camera.pan(by: gesture.translation, over: Double(state.canvas.height))
				} else {
					camera.orbit(by: gesture.translation)
				}
				state.camera = camera
			}
	}

	private var magnifier: some Gesture {
		MagnifyGesture(minimumScaleDelta: 0.0)
			.updating($pinch) { gesture, initial, _ in
				if initial == nil { initial = state.camera.distance }
				guard let initial else { return }
				state.camera.zoom(to: initial / gesture.magnification, reach: state.reach)
			}
	}
}

/// Scroll wheel and two finger scroll, which SwiftUI offers only inside a
/// scroll view. The monitor lives exactly as long as the view it is put on,
/// and answers only while the pointer is over it.
@MainActor
struct ScrollWheel: ViewModifier {
	var action: (CGFloat) -> Void

	@State private var wheel = Wheel()

	func body(content: Content) -> some View {
		content
			.onContinuousHover { phase in
				if case .active = phase { wheel.over = true } else { wheel.over = false }
			}
			.onAppear {
				wheel.action = action
				wheel.listen()
			}
			.onDisappear { wheel.stop() }
	}

	@MainActor
	final class Wheel {
		var over = false
		var action: (CGFloat) -> Void = ø
		private var monitor: Any?

		func listen() {
			guard monitor == nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
				// A wheel reports whole notches where a trackpad reports pixels
				let delta = event.hasPreciseScrollingDeltas
					? event.scrollingDeltaY
					: event.deltaY * 6.0
				let taken = MainActor.assumeIsolated {
					guard over else { return false }
					action(delta)
					return true
				}
				return taken ? nil : event
			}
		}

		func stop() {
			monitor.map(NSEvent.removeMonitor)
			monitor = nil
		}
	}
}
