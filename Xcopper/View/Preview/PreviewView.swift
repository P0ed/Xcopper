import AppKit
import RealityKit
import SwiftUI

/// The board as it will come back from the fab: substrate, mask, copper and
/// the parts standing on it, handed to RealityKit as a scene to render.
@MainActor
struct PreviewView: View {
	var board: Board
	@Binding var state: PreviewState

	@State private var scene = PreviewScene()
	/// Camera motion stays local while a gesture is live. Publishing every
	/// pointer sample through the editor's preview state would invalidate the
	/// sidebar and toolbar as well as the one transform that actually moved.
	@State private var camera: Camera
	@State private var scrolling = false
	@State private var rightPan: Camera?
	@GestureState private var grab: Grab?
	@GestureState private var pinch: Double?

	init(board: Board, state: Binding<PreviewState>) {
		self.board = board
		_state = state
		_camera = State(initialValue: state.wrappedValue.camera)
	}

	var body: some View {
		GeometryReader { geo in
			RealityView { content in
				// The board is looked at from a camera of its own rather than
				// from wherever a scene would otherwise be read
				content.camera = .virtual
				content.add(scene.root)
				configure(&content, force: true)
				show()
			} update: { content in
				configure(&content)
				show()
			}
			.background(Palette.backdrop)
			.gesture(controller)
			.gesture(magnifier)
			.modifier(RightMouseDrag(
				started: { rightPan = camera },
				moved: { translation in
					guard var camera = rightPan else { return }
					camera.pan(by: translation, over: Double(state.canvas.height))
					self.camera = camera
				},
				ended: {
					guard rightPan != nil else { return }
					rightPan = nil
					state.camera = camera
				}
			))
			.modifier(ScrollWheel(
				action: { delta in
					scrolling = true
					camera.zoom(by: exp(Double(delta) * 0.004), reach: state.reach)
				},
				ended: {
					scrolling = false
					state.camera = camera
				}
			))
			.onChange(of: geo.size, initial: true) { _, new in
				guard new.width > 0.0, new.height > 0.0 else { return }
				state.canvas = new
				if !state.framed { state.frame(board) }
			}
		}
		.overlay(alignment: .bottomLeading) { readout }
		.onChange(of: state.camera) { _, new in
			// Toolbar buttons, keyboard commands and framing still own the
			// durable camera and can move it while no gesture is under way.
			if camera != new { camera = new }
		}
	}

	/// The scene knows the board it is already showing, so this is the turn of
	/// the camera that a drag asks for and nothing more
	private func show() {
		scene.show(board, finish: state.finish)
		scene.aim(camera)
	}

	/// Four-sample antialiasing is useful once the board is still, but keeps
	/// four samples per pixel while the view is moving. Drop it only for the live
	/// motion, and leave the finished frame at full quality.
	private func configure(_ content: inout RealityViewCameraContent, force: Bool = false) {
		let moving = grab != nil || pinch != nil || rightPan != nil || scrolling
		guard scene.rendering(changedToMoving: moving, force: force) else { return }

		var effects = content.renderingEffects
		effects.antialiasing = moving ? .none : .multisample4X
		effects.motionBlur = .disabled
		effects.depthOfField = .disabled
		content.renderingEffects = effects
	}

	private var readout: some View {
		Readout {
			Text(camera.overTop ? "Top" : "Bottom")
				.foregroundStyle(Palette.color(of: camera.overTop ? 0 : 5, in: board.stack))
			Text("\(camera.azimuth.degrees)°, \(camera.elevation.degrees)° up")
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
						camera: camera,
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
				self.camera = camera
			}
			.onEnded { _ in state.camera = camera }
	}

	private var magnifier: some Gesture {
		MagnifyGesture(minimumScaleDelta: 0.0)
			.updating($pinch) { gesture, initial, _ in
				if initial == nil { initial = camera.distance }
				guard let initial else { return }
				camera.zoom(to: initial / gesture.magnification, reach: state.reach)
			}
			.onEnded { _ in state.camera = camera }
	}
}

/// SwiftUI's drag gesture follows the primary button. The secondary button is
/// watched alongside it so a right drag can pan the preview without asking for
/// a modifier key. Once begun over the view, the drag stays caught until the
/// button comes up even if the pointer leaves the view on the way.
@MainActor
struct RightMouseDrag: ViewModifier {
	var started: () -> Void
	var moved: (CGSize) -> Void
	var ended: () -> Void

	@State private var drag = Drag()

	func body(content: Content) -> some View {
		content
			.onContinuousHover { phase in
				if case .active = phase { drag.over = true } else { drag.over = false }
			}
			.onAppear {
				drag.started = started
				drag.moved = moved
				drag.ended = ended
				drag.listen()
			}
			.onDisappear { drag.stop() }
	}

	@MainActor
	final class Drag {
		var over = false
		var started: () -> Void = ø
		var moved: (CGSize) -> Void = ø
		var ended: () -> Void = ø
		private var origin: CGPoint?
		private var monitor: Any?

		func listen() {
			guard monitor == nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(
				matching: [.rightMouseDown, .rightMouseDragged, .rightMouseUp]
			) { [self] event in
				let taken = MainActor.assumeIsolated { handle(event) }
				return taken ? nil : event
			}
		}

		private func handle(_ event: NSEvent) -> Bool {
			switch event.type {
			case .rightMouseDown:
				guard over else { return false }
				origin = event.locationInWindow
				started()
				return true
			case .rightMouseDragged:
				guard let origin else { return false }
				let point = event.locationInWindow
				moved(CGSize(width: point.x - origin.x, height: origin.y - point.y))
				return true
			case .rightMouseUp:
				guard origin != nil else { return false }
				finish()
				return true
			default:
				return false
			}
		}

		private func finish() {
			guard origin != nil else { return }
			origin = nil
			ended()
		}

		func stop() {
			finish()
			monitor.map(NSEvent.removeMonitor)
			monitor = nil
		}
	}
}

/// Scroll wheel and two finger scroll, which SwiftUI offers only inside a
/// scroll view. The monitor lives exactly as long as the view it is put on,
/// and answers only while the pointer is over it.
@MainActor
struct ScrollWheel: ViewModifier {
	var action: (CGFloat) -> Void
	var ended: () -> Void

	@State private var wheel = Wheel()

	func body(content: Content) -> some View {
		content
			.onContinuousHover { phase in
				if case .active = phase { wheel.over = true } else { wheel.over = false }
			}
			.onAppear {
				wheel.action = action
				wheel.ended = ended
				wheel.listen()
			}
			.onDisappear { wheel.stop() }
	}

	@MainActor
	final class Wheel {
		var over = false
		var action: (CGFloat) -> Void = ø
		var ended: () -> Void = ø
		private var monitor: Any?
		private var settling: Task<Void, Never>?
		private var active = false

		func listen() {
			guard monitor == nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
				// A wheel reports whole notches where a trackpad reports pixels
				let delta = event.hasPreciseScrollingDeltas
					? event.scrollingDeltaY
					: event.deltaY * 6.0
				let taken = MainActor.assumeIsolated {
					guard over else { return false }
					move(delta)
					return true
				}
				return taken ? nil : event
			}
		}

		/// A trackpad announces the end of its physical gesture before its
		/// momentum has finished, while a mouse wheel announces no end at all.
		/// A short quiet period settles either kind exactly once.
		private func move(_ delta: CGFloat) {
			active = true
			action(delta)
			settling?.cancel()
			settling = Task { [weak self] in
				try? await Task.sleep(for: .milliseconds(120))
				guard !Task.isCancelled else { return }
				self?.finish()
			}
		}

		private func finish() {
			guard active else { return }
			active = false
			settling = nil
			ended()
		}

		func stop() {
			settling?.cancel()
			finish()
			monitor.map(NSEvent.removeMonitor)
			monitor = nil
		}
	}
}
