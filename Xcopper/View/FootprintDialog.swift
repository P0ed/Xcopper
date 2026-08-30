import SwiftUI

@MainActor
struct FootprintDialog: View {
	@Binding var spec: Footprint.Spec
	var confirm: () -> Void

	@State var draft: Footprint.Spec?

	private var current: Footprint.Spec { draft ?? spec }

	private var binding: Binding<Footprint.Spec> {
		Binding(get: { current }, set: { draft = $0 })
	}

	var body: some View {
		Dialog(
			action: "Place",
			confirm: {
				spec = current
				confirm()
			}
		) {
			VStack(alignment: .leading, spacing: 10.0) {
				Picker("Kind", selection: binding.kind) {
					ForEach(Footprint.Kind.allCases) { kind in
						Text(kind.name).tag(kind)
					}
				}
				if current.kind.hasChip {
					Picker("Size", selection: binding.chip) {
						ForEach(Footprint.Chip.allCases) { chip in
							Text(chip.name).tag(chip)
						}
					}
				}
				if current.kind.hasPins {
					Stepper(
						"Pins: \(current.pins)",
						value: binding.pins,
						in: pinRange,
						step: pinStep
					)
				}
				if current.kind.hasRows {
					Picker("Rows", selection: binding.rows) {
						Text("1").tag(1)
						Text("2").tag(2)
					}
					.pickerStyle(.segmented)
				}
				if current.kind.hasPitch {
					Picker("Pitch", selection: binding.pitch) {
						Text("0.4 mm").tag(Nm.mm(0.4))
						Text("0.5 mm").tag(Nm.mm(0.5))
						Text("0.65 mm").tag(Nm.mm(0.65))
						Text("0.8 mm").tag(Nm.mm(0.8))
					}
				}
			}
			.frame(width: 240.0)
		}
	}

	private var pinRange: ClosedRange<Int> {
		switch current.kind {
		case .qfp: 8 ... 128
		case .header: 1 ... 40
		default: 2 ... 64
		}
	}

	private var pinStep: Int {
		switch current.kind {
		case .qfp: 4
		case .header: 1
		default: 2
		}
	}
}

@MainActor
struct NetDialog: View {
	var confirm: (String) -> Void

	@State var name: String = ""

	var body: some View {
		Dialog(
			action: "Add",
			isValid: !name.trimmingCharacters(in: .whitespaces).isEmpty,
			confirm: { confirm(name.trimmingCharacters(in: .whitespaces)) }
		) {
			TextField("Net name", text: $name)
				.frame(width: 180.0)
		}
	}
}
