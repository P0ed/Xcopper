import Foundation
import SwiftUI

@propertyWrapper
struct UserDefault<Value: Codable>: DynamicProperty {
	@AppStorage
	private var data: Data?
	private var defaultValue: () -> Value

	init(
		wrappedValue: Value? = .none,
		key: String = "\(Value.self)",
		store: UserDefaults = .standard,
		default: @escaping @autoclosure () -> Value
	) {
		_data = .init(key, store: store)
		defaultValue = `default`
		wrappedValue.map { self.wrappedValue = $0 }
	}

	private var codedValue: Value? {
		get { try? data.map(dtoa) }
		nonmutating set { data = try? newValue.map(atod) }
	}

	public var wrappedValue: Value {
		get { codedValue ?? defaultValue() }
		nonmutating set { codedValue = newValue }
	}

	public var projectedValue: Binding<Value> {
		Binding(
			get: { wrappedValue },
			set: { value in wrappedValue = value }
		)
	}
}

private func atod<A: Encodable>(_ value: A) throws -> Data {
	try JSONEncoder().encode(value)
}

private func dtoa<A: Decodable>(_ data: Data) throws -> A {
	try JSONDecoder().decode(A.self, from: data)
}
