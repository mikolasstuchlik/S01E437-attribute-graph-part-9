public struct GraphValue {
    public var nodes: [NodeValue]
    public var edges: [EdgeValue]
}

public struct NodeValue {
    public var id: NodeID
    public var name: String
    public var potentiallyDirty: Bool
    public var value: String
}

public struct EdgeValue {
    public var from: NodeID
    public var to: NodeID
    public var pending: Bool
}

extension ObjectIdentifier {
    var dotID: String {
        "\(self)".filter { $0.isLetter || $0.isNumber}
    }
}

extension String {
    var escaped: String {
        replacing("\"", with: "\\\"")
    }
}

extension NodeValue {
    public var dot: String {
        "\(id.dotID) [label=\"\(name) (\(value.escaped))\", style=\(potentiallyDirty ? "filled" : "solid"), shape=rect]"
    }
}

extension EdgeValue {
    public var dot: String {
        "\(from.dotID) -> \(to.dotID) [style=\(pending ? "dashed" : "solid")]"
    }
}

extension GraphValue {
    public var dot: String {
        """
        digraph {
        \(nodes.map(\.dot).joined(separator: "\n"))
        \(edges.map(\.dot).joined(separator: "\n"))
        }
        """
    }
}
