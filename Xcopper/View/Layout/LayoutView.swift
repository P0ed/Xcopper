import RealityKit
import SwiftUI

@MainActor
struct LayoutView: View {
	@Binding var design: Design
	@Binding var state: LayoutState
	var claimKeyboard: () -> Void = ø

	@Environment(\.undoManager) var undoManager

	@State private var scene = LayoutScene()
	@State private var rightPan: LayoutViewport?
	@State private var hoverLocation: CGPoint?
	@GestureState private var pinch: CGFloat?

	var board: Board {
		get { design.board }
		nonmutating set { design.board = newValue }
	}

	var body: some View {
		GeometryReader { geo in
			RealityView { content in
				content.camera = .virtual
				content.add(scene.root)
				var effects = content.renderingEffects
				effects.antialiasing = .none
				effects.motionBlur = .disabled
				effects.depthOfField = .disabled
				content.renderingEffects = effects
				scene.show(design, state: state)
			} update: { _ in
				scene.show(design, state: state)
			}
			.background(Palette.background)
			.contentShape(Rectangle())
			.gesture(editingController)
			.simultaneousGesture(magnifier)
			.modifier(RightMouseDrag(
				started: {
					claimKeyboard()
					rightPan = state.viewport
				},
				moved: { translation in
					guard var viewport = rightPan else { return }
					viewport.pan(by: translation)
					state.viewport = viewport
				},
				ended: { rightPan = nil }
			))
			.modifier(ScrollWheel(
				action: { delta in state.viewport.pan(by: delta) },
				ended: ø
			))
			.onContinuousHover { phase in
				switch phase {
				case let .active(location):
					hoverLocation = location
					hover(at: location)
				case .ended:
					hoverLocation = nil
				}
			}
			.onChange(of: geo.size, initial: true) { _, size in
				state.viewport.resize(to: size, content: board.size)
			}
		}
		.onChange(of: board.size) { _, size in
			if state.viewport.fitting { state.viewport.fit(size) }
		}
		.onChange(of: state.viewport.center) { _, _ in refreshHover() }
		.onChange(of: state.viewport.magnification) { _, _ in refreshHover() }
		.onChange(of: state.viewport.size) { _, _ in refreshHover() }
		.onChange(of: state.traceSession?.start) { _, _ in refreshHover() }
	}

	private func refreshHover() {
		if let hoverLocation { hover(at: hoverLocation) }
	}

	private var magnifier: some Gesture {
		MagnifyGesture(minimumScaleDelta: 0.0)
			.updating($pinch) { gesture, initial, _ in
				if initial == nil { initial = state.viewport.magnification }
				guard let initial else { return }
				state.viewport.setScale(initial * gesture.magnification)
			}
	}
}
