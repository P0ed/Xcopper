struct PackageAppearance: Equatable {

	enum Shell: Equatable {
		case none
		case block
		case can(Nm)
		case dome(Nm)
	}

	var shell: Shell = .block
	var height: Nm = .mm(1.0)
	var standoff: Nm = 0
	var inset: Nm = 0
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
		let across = Double(min(body.width, body.height)).mm
		switch footprint.package {
		case .chip:
			self.init(chip: footprint.device, across: across)
		case .soic, .sot23, .ssop10, .sod123, .sot457:
			self.init(surfaceMountAcross: across)
		case .dip:
			self.init(height: .mm(3.3))
		case .header:
			self.init(height: .mm(2.5), posts: true)
		case .sip:
			self.init(height: .mm(9.0))
		case .led5mm:
			self.init(shell: .dome(.mm(5.0)), height: .mm(8.6), color: Palette.lens)
		case .bourns51, .nkkMNPC, .mta156, .pomona1581:
			self.init(shell: .none, height: 0)
		case .custom:
			let through = footprint.pads.contains(where: \.isThrough)
			let shrouded = footprint.pads.allSatisfy { footprint.body.contains($0.at) }
			switch (through, footprint.pads.count) {
			case (false, 2): self.init(chip: footprint.device, across: across)
			case (false, _): self.init(surfaceMountAcross: across)
			case (true, _) where shrouded: self.init(height: .mm(2.5), posts: true)
			case (true, _): self.init(height: .mm(3.3))
			}
		}
	}

	private init(chip device: Device, across: Double) {
		let capacitor = device == .capacitor
		let element = min(max(across * 0.42, 0.3), 1.1)
		self.init(
			height: .mm(capacitor ? element * 2.0 : element),
			inset: .mm(0.05),
			color: capacitor ? Palette.ceramic : (device == .resistor ? Palette.chip : Palette.moulding),
			leads: true
		)
	}

	private init(surfaceMountAcross across: Double) {
		self.init(
			height: .mm(min(max(across * 0.45, 0.6), 2.2)),
			standoff: .mm(0.08),
			leads: true
		)
	}
}

extension Pad {
	var leg: Figure {
		figure.outset(-min(.mm(0.1), min(size.width, size.height) / 4))
	}
}
