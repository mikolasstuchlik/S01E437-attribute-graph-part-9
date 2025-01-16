import AppKit
import SwiftUI

func graphViz(dot: String) -> NSImage {
    let p = Process()
    let stdIn = Pipe()
    let stdOut = Pipe()
    let stdErr = Pipe()
    p.standardInput = stdIn
    p.standardOutput = stdOut
    p.standardError = stdErr
    p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/dot")
    p.arguments = ["-Tpdf"]
    stdIn.fileHandleForWriting.write(dot.data(using: .utf8)!)
    stdIn.fileHandleForWriting.closeFile()
    try! p.run()
    let data = stdOut.fileHandleForReading.readDataToEndOfFile()
    let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
    if !errData.isEmpty {
        print(String(decoding: errData, as: UTF8.self))
    }

    guard let image = NSImage(data: data) else {
        print("Error", dot)
        fatalError()
    }
    return image
}

struct Graphviz: View {
    var dot: String
    var body: some View {
        Image(nsImage: graphViz(dot: dot))
    }
}
