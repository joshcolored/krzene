import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvasWidth = 2064
let canvasHeight = 2752

guard CommandLine.arguments.count == 5 else {
  fputs("Usage: ipad_app_store_mockup <input.png> <output.png> <headline> <subtitle>\n", stderr)
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

guard
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
  let bitmapContext = CGContext(
    data: nil,
    width: canvasWidth,
    height: canvasHeight,
    bitsPerComponent: 8,
    bytesPerRow: canvasWidth * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  )
else {
  fputs("Could not create output canvas.\n", stderr)
  exit(70)
}

let graphics = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
  NSRect(x: x, y: CGFloat(canvasHeight) - y - height, width: width, height: height)
}

func fittedFont(for text: String, maximumSize: CGFloat, width: CGFloat) -> NSFont {
  var size = maximumSize
  while size > 64 {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    if (text as NSString).size(withAttributes: [.font: font]).width <= width {
      return font
    }
    size -= 2
  }
  return NSFont.systemFont(ofSize: size, weight: .bold)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

let canvas = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
NSColor(calibratedWhite: 0.012, alpha: 1).setFill()
canvas.fill()

let sideGlow = NSGradient(
  colors: [
    NSColor(red: 0.34, green: 0.015, blue: 0.025, alpha: 1),
    NSColor(red: 0.055, green: 0.008, blue: 0.012, alpha: 1),
    NSColor(calibratedWhite: 0.012, alpha: 1),
    NSColor(red: 0.004, green: 0.07, blue: 0.052, alpha: 1),
    NSColor(red: 0.008, green: 0.19, blue: 0.125, alpha: 1),
  ],
  atLocations: [0, 0.22, 0.5, 0.80, 1],
  colorSpace: .deviceRGB
)
sideGlow?.draw(in: canvas, angle: 0)

let verticalShade = NSGradient(
  starting: NSColor(calibratedWhite: 0.015, alpha: 0.10),
  ending: NSColor(calibratedWhite: 0.0, alpha: 0.82)
)
verticalShade?.draw(in: canvas, angle: -90)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineBreakMode = .byClipping

let headlineFont = fittedFont(for: headline, maximumSize: 102, width: 1900)
(headline as NSString).draw(
  in: topRect(82, 62, 1900, 126),
  withAttributes: [
    .font: headlineFont,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -1.5,
  ]
)

(subtitle as NSString).draw(
  in: topRect(100, 184, 1864, 65),
  withAttributes: [
    .font: NSFont.systemFont(ofSize: 43, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.74, alpha: 1),
    .paragraphStyle: paragraph,
  ]
)

let accent = NSBezierPath(roundedRect: topRect(982, 258, 100, 8), xRadius: 4, yRadius: 4)
NSColor(red: 0.94, green: 0.07, blue: 0.12, alpha: 1).setFill()
accent.fill()

let deviceRect = topRect(130, 300, 1804, 2405)
let devicePath = NSBezierPath(roundedRect: deviceRect, xRadius: 96, yRadius: 96)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.92)
shadow.shadowBlurRadius = 72
shadow.shadowOffset = NSSize(width: 0, height: -18)

NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
devicePath.fill()
NSGraphicsContext.restoreGraphicsState()

let frameGradient = NSGradient(
  colors: [
    NSColor(calibratedWhite: 0.58, alpha: 1),
    NSColor(calibratedWhite: 0.09, alpha: 1),
    NSColor(calibratedWhite: 0.42, alpha: 1),
  ]
)
frameGradient?.draw(in: devicePath, angle: 0)

let frameInset = NSBezierPath(
  roundedRect: deviceRect.insetBy(dx: 10, dy: 10),
  xRadius: 88,
  yRadius: 88
)
NSColor.black.setFill()
frameInset.fill()

let screenRect = topRect(158, 328, 1748, 2330.67)
let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 68, yRadius: 68)
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
NSGraphicsContext.restoreGraphicsState()

NSColor(calibratedWhite: 0.62, alpha: 0.42).setStroke()
screenPath.lineWidth = 2
screenPath.stroke()

let camera = NSBezierPath(ovalIn: topRect(1024, 310, 16, 16))
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
camera.fill()

NSGraphicsContext.restoreGraphicsState()

guard let outputImage = bitmapContext.makeImage() else {
  fputs("Could not encode PNG.\n", stderr)
  exit(70)
}

let outputURL = URL(fileURLWithPath: outputPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(
  outputURL,
  UTType.png.identifier as CFString,
  1,
  nil
) else {
  fputs("Could not create PNG destination.\n", stderr)
  exit(73)
}
CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
  fputs("Could not write PNG.\n", stderr)
  exit(73)
}
