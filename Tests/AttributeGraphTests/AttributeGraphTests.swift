import Testing
@testable import AttributeGraph

@Test func example() async throws {
    let graph = AttributeGraph()
    let a = graph.input(name: "A", 10)
    let b = graph.input(name: "B", 20)
    let c = graph.rule(name: "C") { a.wrappedValue + b.wrappedValue }
    let d = graph.rule(name: "D") { c.wrappedValue * 2 }
    let e = graph.rule(name: "E") { a.wrappedValue * 2 }
    #expect(d.wrappedValue == 60)
    #expect(e.wrappedValue == 20)

    let str = """
    digraph {
    A
    B
    C
    D
    E
    A -> C
    A -> E
    B -> C
    C -> D
    }
    """
    #expect(str == graph.graphViz())

    a.wrappedValue = 40

    let str2 = """
    digraph {
    A
    B
    C [style=dashed]
    D [style=dashed]
    E [style=dashed]
    A -> C [style=dashed]
    A -> E [style=dashed]
    B -> C
    C -> D
    }
    """
    #expect(str2 == graph.graphViz())

    #expect(d.wrappedValue == 120)

    let str3 = """
    digraph {
    A
    B
    C
    D
    E [style=dashed]
    A -> E [style=dashed]
    A -> C
    B -> C
    C -> D
    }
    """
    #expect(str3 == graph.graphViz())
}
