func id<A>(_ x: A) -> A { x }
func ø<each A>(_ x: repeat each A) {}

func modify<A>(_ value: inout A, _ transform: (inout A) -> Void) {
	transform(&value)
}

func modifying<A>(_ value: A, _ transform: (inout A) -> Void) -> A {
	var value = value
	transform(&value)
	return value
}

extension Optional {

	func throwing(_ fallback: @autoclosure () -> Error) throws -> Wrapped {
		if let self {
			self
		} else {
			throw fallback()
		}
	}

	func throwing(_ fallback: @autoclosure () -> String) throws -> Wrapped {
		try throwing(Err(fallback()))
	}
}

struct Err: Error {
	var description: String

	init(_ description: String) {
		self.description = description
	}
}

extension Array {

	mutating func modifyEach(_ transform: (inout Element) -> Void) {
		for i in indices {
			transform(&self[i])
		}
	}

	mutating func remove(at indices: some Sequence<Int>) {
		for index in indices.sorted(by: >) where self.indices.contains(index) {
			remove(at: index)
		}
	}
}
