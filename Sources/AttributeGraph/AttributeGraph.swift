// Based on https://www.semanticscholar.org/paper/A-System-for-Efficient-and-Flexible-One-Way-in-C%2B%2B-Hudson/9609985dbef43633f4deb88c949a9776e0cd766b
// https://repository.gatech.edu/server/api/core/bitstreams/3117139f-5de2-4f1f-9662-8723bae97a6d/content

public final class AttributeGraph {
    var nodes: [AnyNode] = []
    var evalNodesStack: [AnyNode] = []

    var onChange: (String, AttributeGraph) -> Void

    public init(onChange: @escaping (String, AttributeGraph) -> Void) {
        self.onChange = onChange
    }

    public func input<A>(name: String, _ value: A) -> Node<A> {
        transaction {
            let n = Node(name: name, in: self, wrappedValue: value)
            nodes.append(n)
            return n
        }
    }

    public func rule<A>(name: String, _ rule: @escaping () -> A) -> Node<A> {
        transaction {
            let n = Node(name: name, in: self, rule: rule)
            nodes.append(n)
            return n
        }
    }

    func transaction<T>(_ note: String = #function, _ block: () -> T) -> T {
        defer { onChange(note, self) }
        return block()
    }

    public func snapshot() -> GraphValue {
        GraphValue(
            nodes: nodes
                .map { node in
                    NodeValue(
                        id: node.id,
                        name: node.name,
                        potentiallyDirty: node.potentiallyDirty,
                        value: node.debugValue,
                        isRule: node.hasRule,
                        isCurrent: evalNodesStack.contains { node === $0 }
                    )
                },
            edges: nodes.flatMap { node in
                node.outgoingEdges.map {
                    EdgeValue(from: $0.from.id, to: $0.to.id, pending: $0.pending)
                }
            }
        )
    }
}

protocol AnyNode: AnyObject {
    var name: String { get }
    var outgoingEdges: [Edge] { get set }
    var incomingEdges: [Edge] { get set }
    var potentiallyDirty: Bool { get set }
    var id: NodeID { get }
    var debugValue: String { get }

    var hasRule: Bool { get }
    func recomputeIfNeeded()
}

public final class Edge {
    unowned var from: AnyNode
    unowned var to: AnyNode
    var pending = false

    init(from: AnyNode, to: AnyNode) {
        self.from = from
        self.to = to
    }

    static func ~=(lhs: Edge, rhs: Edge) -> Bool {
        lhs.from === rhs.from && lhs.to === rhs.to
    }
}

public typealias NodeID = ObjectIdentifier

public final class Node<A>: AnyNode, Identifiable {
    unowned public private(set) var graph: AttributeGraph
    public var name: String
    var rule: (() -> A)?
    var incomingEdges: [Edge] = []
    var outgoingEdges: [Edge] = []
    public var id: NodeID { ObjectIdentifier(self) }

    var hasRule: Bool { rule != nil }

    public var _potentiallyDirty: Bool = false
    public var potentiallyDirty: Bool {
        get { _potentiallyDirty }
        set {
            guard newValue != _potentiallyDirty else {
                return
            }

            if newValue {
                graph.transaction("\(name) set dirty") {
                    _potentiallyDirty = newValue
                }
                for e in outgoingEdges {
                    e.to.potentiallyDirty = true
                }
            } else {
                _potentiallyDirty = newValue
            }
        }
    }

    var debugValue: String {
        _cachedValue.map { "\($0)" } ?? "<nil>"
    }

    private var _cachedValue: A?

    public var wrappedValue: A {
        get {
            recomputeIfNeeded()
            return _cachedValue!
        }
        set {
            assert(rule == nil)
            _cachedValue = newValue
            for e in outgoingEdges {
                graph.transaction("\(name) wrappedValue: set") {
                    e.pending = true
                    e.to.potentiallyDirty = true
                }
            }
        }
    }

    func recomputeIfNeeded() {
        // record dependency
        if let c = graph.evalNodesStack.last {
            let edge = Edge(from: self, to: c)

            if
                let outE = outgoingEdges.first(where: { $0 ~= edge} ),
                let inE = c.incomingEdges.first(where: { $0 ~= edge } )
            {
                graph.transaction("\(name) rec: resetting edge") {
                    assert(outE === inE)
                    outE.pending = false
                }
            } else {
                graph.transaction("\(name) rec: adding edge") {
                    outgoingEdges.append(edge)
                    c.incomingEdges.append(edge)
                }
            }

        }

        guard let rule else { return }

        if !potentiallyDirty && _cachedValue != nil { return }

        for edge in incomingEdges {
            edge.from.recomputeIfNeeded()
        }

        let hasPendingIncomingEdge = incomingEdges.contains(where: \.pending)
        potentiallyDirty = false

        if hasPendingIncomingEdge || _cachedValue == nil {
            defer {
                graph.transaction("\(name) rec: pop") {
                    assert(graph.evalNodesStack.last === self)
                    graph.evalNodesStack.removeLast()
                }
            }
            graph.transaction("\(name) rec: push") {
                graph.evalNodesStack.append(self)
            }

            let isInitial = _cachedValue == nil

            graph.transaction("\(name) rec: evaluate rule") {
                _cachedValue = rule()
            }
            // TODO only if _cachedValue has changed
            if !isInitial {
                for o in outgoingEdges {
                    graph.transaction("\(name) rec: no-pending") {
                        o.pending = true
                    }
                }
            }
        }
    }

    init(name: String, in graph: AttributeGraph, wrappedValue: A) {
        self.name = name
        self.graph = graph
        self._cachedValue = wrappedValue
    }

    init(name: String, in graph: AttributeGraph, rule: @escaping () -> A) {
        self.name = name
        self.graph = graph
        self.rule = rule
    }
}
