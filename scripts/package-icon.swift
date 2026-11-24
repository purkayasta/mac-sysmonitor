import Foundation

// Pack existing PNG representations into ICNS without re-encoding their pixels.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift package-icon.swift ICONSET OUTPUT.icns")
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let entries = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]

func chunk(_ type: String, body: Data) -> Data {
    var result = Data(type.utf8)
    var length = UInt32(body.count + 8).bigEndian
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    result.append(body)
    return result
}

var body = Data()
for (type, filename) in entries {
    body.append(chunk(type, body: try Data(contentsOf: iconset.appendingPathComponent(filename))))
}
try chunk("icns", body: body).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
