#!/bin/bash
set -e

APP_NAME="ClaudeMonitorBar"
APP_DIR="$APP_NAME.app"
CONFIG="${1:-release}"
BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Copy resource bundle
cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_DIR/Contents/Resources/"

# Copy Info.plist
cp "Sources/$APP_NAME/Info.plist" "$APP_DIR/Contents/"

# Generate app icon (terminal prompt + progress ring)
echo "Generating app icon..."
ICONSET_DIR="/tmp/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift /dev/stdin "$ICONSET_DIR" << 'SWIFT'
import AppKit

let outputDir = CommandLine.arguments[1]

func renderAppIcon(size: Int, name: String) {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return }

    let claudeOrange = NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1.0)

    // Rounded rect background
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                               xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0).setFill()
    bgPath.fill()

    // Background ring
    let center = CGPoint(x: s/2, y: s/2)
    let radius = s * 0.32
    let lineWidth = s * 0.06

    ctx.setStrokeColor(NSColor(white: 0.3, alpha: 0.6).cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Progress arc (~66%)
    ctx.setStrokeColor(claudeOrange.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    let startAngle = CGFloat.pi / 2
    let endAngle = startAngle - CGFloat.pi * 2 * 0.66
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    ctx.strokePath()

    // Terminal prompt ">_"
    let fontSize = s * 0.22
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: claudeOrange]
    let text = ">_"
    let textSize = text.size(withAttributes: attrs)
    let textRect = NSRect(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2,
                          width: textSize.width, height: textSize.height)
    text.draw(in: textRect, withAttributes: attrs)

    img.unlockFocus()
    guard let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let png = bmp.representation(using: .png, properties: [:]) else { return }
    do { try png.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png")) }
    catch { print("Failed to write \(name): \(error)") }
}

let sizes = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (sz, name) in sizes { renderAppIcon(size: sz, name: name) }
print("Icon PNGs generated")
SWIFT

# Convert to icns
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc sign
codesign --force --sign - "$APP_DIR"

echo ""
echo "Done! App created at: $(pwd)/$APP_DIR"
echo "You can move it to /Applications or double-click to run."
