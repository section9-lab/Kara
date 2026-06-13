import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Kara/Supporting/IconSources/KaraIcon-1024.png")
let outputRoot = root.appendingPathComponent("Kara/Assets.xcassets")
let appIconSet = outputRoot.appendingPathComponent("AppIcon.appiconset")
let iconset = root.appendingPathComponent("build/Kara.iconset")
let sources = root.appendingPathComponent("Kara/Supporting/IconSources")
let iconComposerDocument = root.appendingPathComponent("Kara/Supporting/AppIcon.icon")

try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconComposerDocument, withIntermediateDirectories: true)

guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("Could not load source image at \(sourceURL.path)")
}

func image(pixels: Int, actions: (NSRect) -> Void) -> NSImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap context")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    actions(NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

func savePNG(_ img: NSImage, to url: URL) throws {
    guard
        let tiff = img.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
    else {
        fatalError("Could not encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
}

let master = image(pixels: 1024) { rect in
    NSColor.clear.setFill()
    rect.fill()

    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}

let overlayed = image(pixels: 1024) { rect in
    master.draw(in: rect)
}

let masterPNG = sources.appendingPathComponent("KaraIcon-1024.png")
try savePNG(overlayed, to: masterPNG)
try? FileManager.default.removeItem(at: iconComposerDocument.appendingPathComponent("KaraIcon-1024.png"))
try FileManager.default.copyItem(at: masterPNG, to: iconComposerDocument.appendingPathComponent("KaraIcon-1024.png"))

let slots: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in slots {
    let resized = image(pixels: pixels) { rect in
        overlayed.draw(in: rect, from: NSRect(x: 0, y: 0, width: 1024, height: 1024), operation: .sourceOver, fraction: 1.0)
    }
    try savePNG(resized, to: appIconSet.appendingPathComponent(name))
    try savePNG(resized, to: iconset.appendingPathComponent(name))
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try contents.write(to: appIconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try """
{
  "fill" : "system-dark",
  "groups" : [
    {
      "layers" : [
        {
          "hidden" : false,
          "image-name" : "KaraIcon-1024.png",
          "name" : "KaraIcon",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "translucency" : {
        "enabled" : true,
        "value" : 0.5
      }
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "supported-platforms" : {
    "circles" : [
      "watchOS"
    ],
    "squares" : "shared"
  }
}
""".write(to: iconComposerDocument.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)

try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(to: outputRoot.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
