// ocrheadings DIR (swiftc -O ocrheadings.swift -o ocrheadings): reads each PNG with Vision and prints frames where a
// "Section N" heading (the soak reply's) appears twice. Session 7 used it to check F17 frame by frame.
import Foundation
import Vision
import ImageIO
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var bad = 0
for f in files {
    guard let src = CGImageSourceCreateWithURL(f as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: img).perform([req])
    var counts: [String: Int] = [:]
    for o in req.results ?? [] {
        guard let s = o.topCandidates(1).first?.string else { continue }
        if let r = s.range(of: #"^Section \d+$"#, options: .regularExpression) { counts[String(s[r]), default: 0] += 1 }
    }
    let dups = counts.filter { $0.value > 1 }.map(\.key).sorted()
    if !dups.isEmpty { bad += 1; print(f.lastPathComponent, "DOUBLE:", dups.joined(separator: ", "), "| all:", counts.keys.sorted().joined(separator: ",")) }
}
print("frames \(files.count), with a doubled heading \(bad)")
