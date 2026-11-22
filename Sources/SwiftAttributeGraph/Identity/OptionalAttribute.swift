/// An optional reference to a typed attribute (matching native `AttributeGraph.OptionalAttribute`).
///
/// Unlike ``WeakAttribute``, reading a non-nil `OptionalAttribute` requires its target attribute to be alive (calling
/// ``Graph/value(of:)-(OptionalAttribute<Value>)`` on a freed target triggers a `precondition`, just like reading a
/// direct ``Attribute``). When initialized empty (`nil`), reading returns `nil` without recording any dependency.
@propertyWrapper
public struct OptionalAttribute<Value>: Hashable, Sendable {
    /// The underlying attribute handle, or `nil` if empty.
    public var attribute: Attribute<Value>?

    /// Creates an empty optional attribute that resolves to `nil`.
    public init() {
        self.attribute = nil
    }

    /// Creates an optional attribute wrapping `attribute`.
    public init(_ attribute: Attribute<Value>) {
        self.attribute = attribute
    }

    /// Creates an optional attribute wrapping an optional `attribute`.
    public init(_ attribute: Attribute<Value>?) {
        self.attribute = attribute
    }

    /// Creates an optional attribute wrapping a weak reference.
    public init(_ weak: WeakAttribute<Value>) {
        self.attribute = weak.attribute
    }

    /// Creates an optional attribute from an untyped ``AnyOptionalAttribute``.
    public init(base: AnyOptionalAttribute) {
        if let attr = base.attribute {
            self.attribute = Attribute<Value>(id: attr.id)
        } else {
            self.attribute = nil
        }
    }

    /// The underlying ``AnyOptionalAttribute`` representation.
    public var base: AnyOptionalAttribute {
        get {
            AnyOptionalAttribute(self)
        }
        set {
            if let attr = newValue.attribute {
                self.attribute = Attribute<Value>(id: attr.id)
            } else {
                self.attribute = nil
            }
        }
    }

    /// The value of the referenced attribute read from the graph whose rule is running on this thread, or `nil` if
    /// `attribute` is `nil`.
    public var value: Value? {
        guard let attribute else { return nil }
        return attribute.value
    }

    /// The value of the referenced attribute when used as `@OptionalAttribute` inside a rule, or `nil` if empty.
    public var wrappedValue: Value? { value }

    /// The underlying optional `Attribute<Value>?` handle (`$property` when used as `@OptionalAttribute`).
    public var projectedValue: Attribute<Value>? {
        get { attribute }
        set { attribute = newValue }
    }

    /// Transforms the wrapped `Attribute<Value>` if present, or returns `nil` if empty.
    public func map<V>(_ body: (Attribute<Value>) -> V) -> V? {
        attribute.map(body)
    }

    /// Textual description matching Apple's formatting.
    public var description: String {
        if let attribute {
            return "OptionalAttribute<\(Value.self)>(\(attribute))"
        }
        return "nil"
    }
}

extension OptionalAttribute: CustomStringConvertible {}

extension Graph {
    /// Returns the wrapped `Attribute` handle if present, or `nil` if empty.
    public func attribute<Value>(of optionalAttribute: OptionalAttribute<Value>) -> Attribute<Value>? {
        assertOwnThread()
        return optionalAttribute.attribute
    }

    /// Reads the value of `optionalAttribute` if non-nil (bringing it up to date and recording a dependency when inside
    /// a rule), or returns `nil` if empty.
    public func value<Value>(of optionalAttribute: OptionalAttribute<Value>) -> Value? {
        assertOwnThread()
        guard let attribute = optionalAttribute.attribute else { return nil }
        return value(of: attribute)
    }

    /// Reads the value of `optionalAttribute` and reports whether it changed since the running rule's previous
    /// evaluation, or returns `nil` if empty.
    public func changedValue<Value>(of optionalAttribute: OptionalAttribute<Value>) -> (value: Value, changed: Bool)? {
        assertOwnThread()
        guard let attribute = optionalAttribute.attribute else { return nil }
        let node = evaluatingNode
        let val = read(attribute)
        if node != Graph.noNode {
            return (val, inputChanged(of: node, attribute: attribute))
        }
        return (val, false)
    }
}

extension RuleContext {
    /// Reads `optionalAttribute` if non-nil (recording a dependency) and reports whether it changed since the previous
    /// run, or returns `nil` if empty.
    public func changedValue<T>(of optionalAttribute: OptionalAttribute<T>) -> (value: T, changed: Bool)? {
        guard let attribute = optionalAttribute.attribute else { return nil }
        return changedValue(of: attribute)
    }
}
