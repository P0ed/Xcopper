import Foundation

func ø<each A>(_ x: repeat each A) {}

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

struct Err: LocalizedError {
	var description: String
	var errorDescription: String? { description }

	init(_ description: String) {
		self.description = description
	}
}

extension Array where Element: Equatable {

	var shared: Element? {
		guard let first, allSatisfy({ $0 == first }) else { return nil }
		return first
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

func nextReference(like reference: String, used: Set<String>) -> String {
	let prefix = String(reference.prefix { !$0.isNumber })
	var index = 1
	while used.contains("\(prefix)\(index)") { index += 1 }
	return "\(prefix)\(index)"
}

extension String {
	var trimmingWhitespace: String {
		var text = Substring(self)
		while let first = text.first, first.isWhitespace { text = text.dropFirst() }
		while let last = text.last, last.isWhitespace { text = text.dropLast() }
		return String(text)
	}
}

struct UnionFind<Element: Hashable> {
	private var parent: [Element: Element] = [:]

	mutating func find(_ element: Element) -> Element {
		var root = element
		while let up = parent[root], up != root { root = up }
		parent[root] = root
		var walk = element
		while let up = parent[walk], up != root {
			parent[walk] = root
			walk = up
		}
		return root
	}

	mutating func union(_ a: Element, _ b: Element) {
		let (ra, rb) = (find(a), find(b))
		guard ra != rb else { return }
		parent[ra] = rb
	}
}
