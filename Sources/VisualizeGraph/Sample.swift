import AttributeGraph
import SwiftUI

struct Sample: View {
    @State var snapshots: [(String, GraphValue)] = []
    @State var index: Int = 0

    var body: some View {
        VStack {
            if index >= 0, index < snapshots.count {
                Graphviz(dot: snapshots[index].1.dot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(snapshots[index].0)
            }
            Stepper(value: $index, label: {
                Text("Step \(index + 1)/\(snapshots.count)")
            })
        }
        .padding()
        .onAppear {
            snapshots = sample()
        }
    }
}

struct LayoutComputer: CustomStringConvertible {
    let sizeThatFits: (ProposedViewSize) -> CGSize
    let childGeometries: (CGRect) -> [CGRect]

    var description: String = ""
}

struct LayoutProxy: CustomStringConvertible {
    let computer: LayoutComputer
    let place: (CGRect) -> ()

    func sizeThatFits(proposedSize: ProposedViewSize) -> CGSize {
        computer.sizeThatFits(proposedSize)
    }

    var description: String = ""
}


struct DisplayList: CustomStringConvertible {
    var items: [Item]

    struct Item: CustomStringConvertible {
        var name: String //
        var frame: CGRect

        var description: String {
            "\(name): \(frame)"
        }
    }

    var description: String {
        items.map { "\($0) "}.joined(separator: ", ")
    }
}

protocol MyLayout {
    func sizeThatFits(proposedSize: ProposedViewSize, subviews: [LayoutProxy]) -> CGSize
    func place(in rect: CGRect, subviews: [LayoutProxy])

    static var name: String { get }
}

extension MyLayout {
    func layoutComputer(_ subviews: [LayoutComputer]) -> LayoutComputer {
        var storage: [CGRect] = Array(repeating: CGRect.zero, count: subviews.count)
        let proxies: [LayoutProxy] = subviews.enumerated().map { (ix, subview) in
            LayoutProxy(computer: subview, place: {
                storage[ix] = $0
            })
        }
        return LayoutComputer { proposal in
            self.sizeThatFits(proposedSize: proposal, subviews: proxies)
        } childGeometries: { rect in
            place(in: rect, subviews: proxies)
            return subviews.enumerated().flatMap { (ix, subview) in
                subview.childGeometries(storage[ix])
            }
        }
    }
}


struct HStackLayout: MyLayout {
    static let name = "HStack"

    func frames(proposedSize: ProposedViewSize, subviews: [LayoutProxy]) -> [CGRect] {
        let flexibilites = subviews.map { s in
            let max = s.sizeThatFits(proposedSize: .init(width: .infinity, height: proposedSize.height)).width
            let min = s.sizeThatFits(proposedSize: .init(width: 0, height: proposedSize.height)).width
            return max - min
        }
        var sorted = flexibilites.enumerated().sorted {
            $0.element < $1.element
        }
        var remainingWidth = proposedSize.width
        var result: [CGRect] = Array(repeating: .zero, count: subviews.count)
        while let (index, _) = sorted.first {
            defer { sorted.removeFirst() }
            let proposedWidth = remainingWidth.map { $0 / .init(sorted.count) }
            let subview = subviews[index]
            let size = subview.sizeThatFits(proposedSize: .init(width: proposedWidth, height: proposedSize.height))
            result[index].size = size
            remainingWidth = remainingWidth.map { $0 - size.width }
        }
        var currentX: Double = 0
        for (index, rect) in result.enumerated() {
            result[index].origin.x = currentX
            currentX += rect.width
        }
        return result
    }

    func sizeThatFits(proposedSize: ProposedViewSize, subviews: [LayoutProxy]) -> CGSize {
        return frames(proposedSize: proposedSize, subviews: subviews).reduce(CGRect.null) { $0.union($1) }.size
    }

    func place(in rect: CGRect, subviews: [LayoutProxy]) {
        let result = frames(proposedSize: .init(rect.size), subviews: subviews)
        for (index, frame) in result.enumerated() {
            subviews[index].place(frame.offsetBy(dx: rect.minX, dy: rect.minY))
        }
    }
}

struct ViewInputs {
    let frame: Node<CGRect>
}

struct ViewOutputs {
    let layoutComputer: Node<LayoutComputer>
    let displayList: Node<DisplayList>
}

protocol MyView {
    static func makeView(node: Node<Self>, inputs: ViewInputs) -> ViewOutputs
}

struct MyColor {
    var name: String
}

extension MyColor: MyView {
    static func makeView(node: Node<MyColor>, inputs: ViewInputs) -> ViewOutputs {
        let graph = node.graph
        let layoutComputer = graph.rule(name: "layout computer") {
            LayoutComputer { proposal in
                proposal.replacingUnspecifiedDimensions()
            } childGeometries: {
                [$0]
            }
        }
        let displayList = graph.rule(name: "display list") {
            DisplayList(items: [.init(name: node.wrappedValue.name, frame: inputs.frame.wrappedValue)])
        }
        return ViewOutputs(layoutComputer: layoutComputer, displayList: displayList)
    }
}

struct FixedFrameLayout: MyLayout {
    static let name: String = "frame"
    var width, height: CGFloat?
    func sizeThatFits(proposedSize: ProposedViewSize, subviews: [LayoutProxy]) -> CGSize {
        assert(subviews.count == 1, "TODO")
        var childProposal = proposedSize
        childProposal.width = width ?? childProposal.width
        childProposal.height = height ?? childProposal.height

        var result = subviews[0].sizeThatFits(proposedSize: childProposal)
        result.width = width ?? result.width
        result.height = height ?? result.height
        return result
    }

    func place(in rect: CGRect, subviews: [LayoutProxy]) {
        let childProposal = ProposedViewSize(width: width ?? rect.width, height: height ?? rect.height)
        let childSize = subviews[0].sizeThatFits(proposedSize: childProposal)
        let origin = CGPoint(x: (rect.width-childSize.width)/2, y: (rect.height-childSize.height)/2)
        subviews[0].place(.init(origin: origin, size: childSize))
    }
}

extension MyView {
    func frame(width: CGFloat? = nil, height: CGFloat? = nil) -> some MyView {
        LayoutModifier(layout: FixedFrameLayout(width: width, height: height), content: self)
    }
}

struct LayoutModifier<L: MyLayout, Content: MyView>: MyView {
    let layout: L
    let content: Content
    
    static func makeView(node: Node<LayoutModifier>, inputs: ViewInputs) -> ViewOutputs {
        let graph = node.graph
        let contentNode = graph.rule(name: "content") {
            node.wrappedValue.content
        }
        var layoutComputer: Node<LayoutComputer>!
        let childFrame = graph.rule(name: "child geometry") {
            let geometries = layoutComputer.wrappedValue.childGeometries(inputs.frame.wrappedValue)
            return geometries[0]
        }
        let inputs = ViewInputs(frame: childFrame)
        let outputs = Content.makeView(node: contentNode, inputs: inputs)
        layoutComputer = graph.rule(name: "layout computer (\(L.name))") {
            let layout = node.wrappedValue.layout
            let lc = outputs.layoutComputer.wrappedValue
            return layout.layoutComputer([lc])
        }
        let displayList = outputs.displayList
        return ViewOutputs(layoutComputer: layoutComputer, displayList: displayList)
    }
}

func run<V: MyView>(_ view: V, inputSize: Node<CGSize>) -> ViewOutputs {
    let graph = inputSize.graph
    let rootNode = graph.rule(name: "root node") { view }
    let rootInputs = ViewInputs(frame: graph.rule(name: "root frame", {
        CGRect(origin: .zero, size: inputSize.wrappedValue)
    }))
    return V.makeView(node: rootNode, inputs: rootInputs)
}

func sample() -> [(String, GraphValue)] {
    /*
     struct Nested: View {
     @State var toggle = false
     var body: some View {
         Color.blue.frame(width: toggle ? 50 : 100)
     }

     struct ContentView: View {
         var body: some View {
             Color.blue
                .frame(width: 80, height: 80)
         }
     }
     */

    var result: [(String, GraphValue)] = []

    let graph = AttributeGraph {
        result.append(($0, $1.snapshot()))
    }
    let rootSize = graph.input(name: "inputSize", CGSize(width: 200, height: 100))
    let colorValue = MyColor(name: "blue")
        .frame(width: 60, height: 60)
    let outputs = run(colorValue, inputSize: rootSize)
    let displayList = outputs.displayList


    let _ = displayList.wrappedValue

    rootSize.wrappedValue.width = 300

    let _ = displayList.wrappedValue

    return result
}
