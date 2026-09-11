/// A surface that could not be read says why; unavailable never renders like empty.
public enum Surface<Value> {
    case available(Value)
    case unavailable(String)

    public var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }

    public var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

extension Surface: Equatable where Value: Equatable {}
extension Surface: Hashable where Value: Hashable {}
