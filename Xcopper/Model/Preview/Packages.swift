struct PackageAppearance: Equatable {

	enum Shell: Equatable {
		case none
		case block
		case can(µm)
		case dome(µm)
	}

	var shell: Shell = .block
	var height: µm = 1 * .mm
	var standoff: µm = 0
	var inset: µm = 0
	var color: RGBA = Palette.moulding
	var posts = false
	var leads: Bool = false
	var stands: Bool { shell != .none }
}

extension Footprint {
	var appearance: PackageAppearance { PackageAppearance(self) }
}

extension PackageAppearance {
	init(_ footprint: Footprint) {
		let body = footprint.body.size
		let across = min(body.width, body.height)
		switch footprint.package {
		case .chip:
			self.init(chip: footprint.device, across: across)
		case .soic, .sot23, .ssop10, .sod123, .sot457:
			self.init(surfaceMountAcross: across)
		case .dip:
			self.init(height: 3_300)
		case .header:
			self.init(height: 2_500, posts: true)
		case .sip:
			self.init(height: 9 * .mm)
		case .led5mm, .bourns51, .nkkMNPC, .mta156, .pomona1581:
			self.init(shell: .none, height: 0)
		case .custom:
			let through = footprint.pads.contains(where: \.isThrough)
			let shrouded = footprint.pads.allSatisfy { footprint.body.contains($0.at) }
			switch (through, footprint.pads.count) {
			case (false, 2): self.init(chip: footprint.device, across: across)
			case (false, _): self.init(surfaceMountAcross: across)
			case (true, _) where shrouded: self.init(height: 2_500, posts: true)
			case (true, _): self.init(height: 3_300)
			}
		}
	}

	private init(chip device: Device, across: µm) {
		let capacitor = device == .capacitor
		let scale = capacitor ? 2 : 1
		let height = (across * 42 * scale + 50) / 100
		self.init(
			height: min(max(height, 300 * scale), 1_100 * scale),
			inset: 50,
			color: capacitor ? Palette.ceramic : (device == .resistor ? Palette.chip : Palette.moulding),
			leads: true
		)
	}

	private init(surfaceMountAcross across: µm) {
		self.init(
			height: min(max((across * 45 + 50) / 100, 600), 2_200),
			standoff: 80,
			leads: true
		)
	}
}

extension Pad {
	var leg: Figure {
		figure.outset(-min(100, min(size.width, size.height) / 4))
	}
}
