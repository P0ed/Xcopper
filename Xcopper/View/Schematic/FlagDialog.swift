import SwiftUI

@MainActor
struct FlagDialog: View {
	@Binding var spec: Flag.Spec
	var confirm: () -> Void

	@State var draft: Flag.Spec?

	private var current: Flag.Spec { draft ?? spec }

	private var binding: Binding<Flag.Spec> {
		Binding(get: { current }, set: { draft = $0 })
	}

	var body: some View {
		Dialog(
			action: "Place",
			confirm: {
				spec = modifying(current) { $0.net = $0.net.trimmingWhitespace }
				confirm()
			}
		) {
			VStack(alignment: .leading, spacing: 10.0) {
				Picker("Kind", selection: binding.kind) {
					ForEach(Flag.Kind.allCases, id: \.self) { kind in
						Text(kind.name).tag(kind)
					}
				}
				HStack {
					Text("Net")
						.foregroundStyle(.secondary)
					TextField(current.kind.defaultNet, text: binding.net)
				}
			}
			.frame(width: 240.0)
		}
	}
}
