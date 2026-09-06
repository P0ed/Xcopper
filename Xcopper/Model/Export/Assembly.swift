import Foundation

extension Fabrication {

	struct Part: Hashable {
		var comment: String
		var footprint: String
		var designators: [String]
	}

	static func csv(_ rows: [[String]]) -> String {
		rows.map { row in row.map(field).joined(separator: ",") }.joined(separator: "\n") + "\n"
	}

	private static func field(_ value: String) -> String {
		guard value.contains(where: { ",\"\n".contains($0) }) else { return value }
		return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
	}
}

extension Design {

	var fitted: [Footprint] {
		board.footprints
			.filter(\.inBOM)
			.sorted { designatorOrder($0.reference) < designatorOrder($1.reference) }
	}

	var bom: [Fabrication.Part] {
		var parts: [Fabrication.Part] = []
		for footprint in fitted {
			let comment = footprint.comment
			let package = footprint.package.name
			if let index = parts.firstIndex(where: {
				$0.comment == comment && $0.footprint == package
			}) {
				parts[index].designators.append(footprint.reference)
			} else {
				parts.append(
					Fabrication.Part(
						comment: comment,
						footprint: package,
						designators: [footprint.reference]
					)
				)
			}
		}
		return parts
	}

	func bill(named name: String) -> Fabrication.File {
		let rows = [["Comment", "Designator", "Footprint", "Quantity"]]
			+ bom.map { part in
				[
					part.comment,
					part.designators.joined(separator: ","),
					part.footprint,
					"\(part.designators.count)",
				]
			}
		return Fabrication.File(name: "\(name)-BOM.csv", text: Fabrication.csv(rows))
	}

	func placement(named name: String) -> Fabrication.File {
		let rows = [["Designator", "Mid X", "Mid Y", "Layer", "Rotation"]]
			+ fitted.map { footprint in
				[
					footprint.reference,
					millimetres(footprint.at.x),
					millimetres(board.size.height - footprint.at.y),
					footprint.flipped ? "bottom" : "top",
					"\(footprint.placementRotation)",
				]
			}
		return Fabrication.File(name: "\(name)-CPL.csv", text: Fabrication.csv(rows))
	}
}

private func millimetres(_ value: Nm) -> String { "\(millimeters(value, decimals: 4))mm" }

extension Footprint {

	var comment: String {
		let named = value.trimmingWhitespace
		if !named.isEmpty { return named }
		return component?.name ?? device.name
	}

	var placementRotation: Int {
		flipped ? rotation.degrees : (360 - rotation.degrees) % 360
	}
}

func designatorOrder(_ reference: String) -> (String, Int, String) {
	let prefix = reference.prefix { !$0.isNumber }
	let digits = reference.dropFirst(prefix.count).prefix(while: \.isNumber)
	return (String(prefix), Int(digits) ?? 0, reference)
}
