import AppKit

let canvasWidth = 1242
let canvasHeight = 2688

guard CommandLine.arguments.count == 5 else {
  fputs("Usage: app_store_mockup <input.png> <output.png> <headline> <subtitle>\n", stderr)
  exit(64)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let headline = CommandLine.arguments[3]
let subtitle = CommandLine.arguments[4]

guard let screenshot = NSImage(contentsOfFile: inputPath) else {
  fputs("Could not open input image: \(inputPath)\n", stderr)
  exit(66)
}

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: canvasWidth,
  pixelsHigh: canvasHeight,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Could not create output canvas.\n", stderr)
  exit(70)
}

func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
  NSRect(x: x, y: CGFloat(canvasHeight) - y - height, width: width, height: height)
}

func fittedFont(for text: String, maximumSize: CGFloat, width: CGFloat) -> NSFont {
  var size = maximumSize
  while size > 54 {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let measured = (text as NSString).size(withAttributes: [.font: font]).width
    if measured <= width { return font }
    size -= 2
  }
  return NSFont.systemFont(ofSize: size, weight: .bold)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

let canvas = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
NSColor(calibratedWhite: 0.015, alpha: 1).setFill()
canvas.fill()

let sideGlow = NSGradient(
  colors: [
    NSColor(red: 0.34, green: 0.015, blue: 0.025, alpha: 1),
    NSColor(red: 0.06, green: 0.01, blue: 0.012, alpha: 1),
    NSColor(calibratedWhite: 0.012, alpha: 1),
    NSColor(red: 0.005, green: 0.08, blue: 0.06, alpha: 1),
    NSColor(red: 0.008, green: 0.20, blue: 0.13, alpha: 1),
  ],
  atLocations: [0, 0.22, 0.5, 0.80, 1],
  colorSpace: .deviceRGB
)
sideGlow?.draw(in: canvas, angle: 0)

let verticalShade = NSGradient(
  starting: NSColor(calibratedWhite: 0.015, alpha: 0.15),
  ending: NSColor(calibratedWhite: 0.0, alpha: 0.82)
)
verticalShade?.draw(in: canvas, angle: -90)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineBreakMode = .byClipping

let headlineFont = fittedFont(for: headline, maximumSize: 94, width: 1110)
(headline as NSString).draw(
  in: topRect(66, 96, 1110, 126),
  withAttributes: [
    .font: headlineFont,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -1.5,
  ]
)

(subtitle as NSString).draw(
  in: topRect(70, 230, 1102, 70),
  withAttributes: [
    .font: NSFont.systemFont(ofSize: 42, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
    .paragraphStyle: paragraph,
  ]
)

let accent = NSBezierPath(roundedRect: topRect(571, 316, 100, 8), xRadius: 4, yRadius: 4)
NSColor(red: 0.94, green: 0.07, blue: 0.12, alpha: 1).setFill()
accent.fill()

let deviceRect = topRect(76, 350, 1090, 2280)
let devicePath = NSBezierPath(roundedRect: deviceRect, xRadius: 150, yRadius: 150)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.92)
shadow.shadowBlurRadius = 70
shadow.shadowOffset = NSSize(width: 0, height: -18)

NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
devicePath.fill()
NSGraphicsContext.restoreGraphicsState()

let frameGradient = NSGradient(
  colors: [
    NSColor(calibratedWhite: 0.55, alpha: 1),
    NSColor(calibratedWhite: 0.10, alpha: 1),
    NSColor(calibratedWhite: 0.38, alpha: 1),
  ]
)
frameGradient?.draw(in: devicePath, angle: 0)

let frameInset = NSBezierPath(
  roundedRect: deviceRect.insetBy(dx: 10, dy: 10),
  xRadius: 140,
  yRadius: 140
)
NSColor.black.setFill()
frameInset.fill()

let screenRect = topRect(104, 380, 1034, 2220)
let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 116, yRadius: 116)
NSGraphicsContext.saveGraphicsState()
screenPath.addClip()
screenshot.draw(
  in: screenRect,
  from: NSRect(origin: .zero, size: screenshot.size),
  operation: .copy,
  fraction: 1,
  respectFlipped: false,
  hints: [.interpolation: NSImageInterpolation.high]
)

// The captured profile screen contains a mojibake separator from the source
// build ("Â·"). Repair only that small label for the App Store artwork.
if inputPath.contains("3.16.15") {
  let labelPatch = topRect(338, 1224, 320, 54)
  NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1).setFill()
  labelPatch.fill()
  ("CURRENT · KIDS" as NSString).draw(
    in: topRect(350, 1233, 295, 40),
    withAttributes: [
      .font: NSFont.systemFont(ofSize: 25, weight: .medium),
      .foregroundColor: NSColor(red: 0.29, green: 0.80, blue: 0.59, alpha: 1),
      .kern: 1.2,
    ]
  )
}
NSGraphicsContext.restoreGraphicsState()

NSColor(calibratedWhite: 0.63, alpha: 0.45).setStroke()
screenPath.lineWidth = 2
screenPath.stroke()

let islandRect = topRect(474, 399, 294, 82)
let island = NSBezierPath(roundedRect: islandRect, xRadius: 41, yRadius: 41)
NSColor.black.setFill()
island.fill()

let camera = NSBezierPath(ovalIn: topRect(720, 428, 18, 18))
NSColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1).setFill()
camera.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode PNG.\n", stderr)
  exit(70)
}

do {
  try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
  fputs("Could not write output: \(error)\n", stderr)
  exit(73)
}
