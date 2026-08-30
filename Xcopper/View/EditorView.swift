import SwiftUI

struct EditorView: View {
	@State var state: EditorState = .init()
	@Binding var board: Board
	@Binding var clipboard: Clipboard

	@GestureState var magnifyGestureState: CGFloat?
	@FocusState private(set) var focused: Bool
	@Environment(\.undoManager) var undoManager

	var body: some View {
		NavigationSplitView(
			sidebar: { sidebar },
			detail: { canvas }
		)
		.toolbar { toolbar }
		.focusable()
		.focused($focused)
		.focusEffectDisabled()
		.focusedSceneValue(\.operations, operations)
		.onAppear { focused = true }
		.onKeyPress(action: keyboardController)
		.sheet(isPresented: $state.boardDialogPresented) { boardDialog }
		.sheet(isPresented: $state.footprintDialogPresented) { footprintDialog }
		.sheet(isPresented: $state.netDialogPresented) { netDialog }
	}

	var operations: Operations {
		Operations(state: $state, board: $board, clipboard: $clipboard)
	}

	var boardDialog: some View {
		BoardDialog(size: board.size, stack: board.stack, loss: board.restackLoss) { size, stack in
			operations.resize(size: size, stack: stack)
		}
	}

	var footprintDialog: some View {
		FootprintDialog(spec: $state.spec) {
			state.tool = .footprint
		}
	}

	var netDialog: some View {
		NetDialog { name in operations.addNet(name: name) }
	}

	private var canvas: some View {
		ScrollView([.horizontal, .vertical]) {
			GeometryReader { geo in
				Canvas { ctx, size in
					render(in: ctx, size: size)
				}
				.gesture(editingController)
				.onContinuousHover { phase in
					if case let .active(location) = phase { hover(at: location) }
				}
				.onChange(of: geo.frame(in: .scrollView)) { _, new in
					state.frame = new
				}
			}
			.frame(
				width: Layout.contentSize(board, scale: state.magnification).width,
				height: Layout.contentSize(board, scale: state.magnification).height
			)
		}
		.scrollPosition($state.scrollPosition)
		.gesture(magnificationController)
		.background { background }
		.overlay(alignment: .bottomLeading) { readout }
	}

	private var readout: some View {
		HStack(spacing: 10.0) {
			Text(board.stack.name(of: state.layer))
				.foregroundStyle(Palette.color(of: state.layer, in: board.stack))
			Text("\(Nm(clamping: state.cursor.x).coordinate), \(Nm(clamping: state.cursor.y).coordinate) mm")
			Text("grid \(state.grid.label)")
			if state.tool == .trace {
				Text("width \(state.traceWidth.label)")
			}
		}
		.font(.caption.monospacedDigit())
		.foregroundStyle(.secondary)
		.padding(.horizontal, 10.0)
		.padding(.vertical, 5.0)
		.background(.regularMaterial, in: .rect(cornerRadius: 6.0))
		.padding(8.0)
	}

	private var background: some View {
		GeometryReader { geo in
			Color(nsColor: .underPageBackgroundColor)
				.onChange(of: geo.size) { _, new in
					guard new.width != 0.0, new.height != 0.0 else { return }

					let old = state.size
					state.size = new
					if old == .zero {
						state.setScale(board.size.zoomToFit(new, margin: Layout.margin))
					}
				}
		}
	}

	private var magnificationController: some Gesture {
		MagnifyGesture(minimumScaleDelta: 0.0)
			.updating($magnifyGestureState) { gesture, initial, _ in
				if initial == .none { initial = state.magnification }
				let initial = initial ?? state.magnification
				state.setScale(initial * gesture.magnification)
			}
	}
}
