struct Package: Equatable {

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

	var package: Package {
		Component(rawValue: value).flatMap(Package.init) ?? Package(landing: self)
	}
}

extension Package {

	init(landing footprint: Footprint) {
		let body = footprint.body.size
		let across = Double(min(body.width, body.height)).mm
		let through = footprint.pads.contains(where: \.isThrough)
		let shrouded = footprint.pads.allSatisfy { footprint.body.contains($0.at) }

		switch (through, footprint.pads.count) {
		case (false, 2):
			let capacitor = footprint.part == .capacitor
			let element = min(max(across * 0.42, 0.3), 1.1)
			self.init(
				shell: .block,
				height: .mm(capacitor ? element * 2.0 : element),
				inset: .mm(0.05),
				color: capacitor ? Palette.ceramic : Palette.chip,
				leads: true
			)
		case (false, _):
			self.init(
				shell: .block,
				height: .mm(min(max(across * 0.45, 0.6), 2.2)),
				standoff: .mm(0.08),
				color: Palette.moulding,
				leads: true
			)
		case (true, _) where shrouded:
			self.init(shell: .block, height: .mm(2.5), posts: true)
		case (true, _):
			self.init(shell: .block, height: .mm(3.3))
		}
	}

	init?(_ component: Component) {
		switch component {
		case .hlmpWL02:
			self.init(shell: .dome(.mm(5.0)), height: .mm(8.6), color: Palette.lens)
		case .bourns51:
			self.init(shell: .block, height: .mm(6.5), inset: .mm(0.2), color: Palette.trimmer)
		case .nkkMN12, .nkkMN15:
			self.init(shell: .block, height: .mm(10.0), inset: .mm(0.1), color: Palette.metal)
		case .mta1563, .mta1564:
			self.init(shell: .block, height: .mm(9.4), color: Palette.nylon)
		case .that2180:
			self.init(shell: .block, height: .mm(9.0))
		case .pomona1581:
			self.init(shell: .none, height: 0)
		default:
			return nil
		}
	}
}

extension Pad {

	var leg: Figure {
		figure.outset(-min(.mm(0.1), min(size.width, size.height) / 4))
	}
}
