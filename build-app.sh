#!/bin/bash
set -e

APP_NAME="ClaudeMonitorBar"
APP_DIR="$APP_NAME.app"
BUILD_DIR=".build/arm64-apple-macosx/debug"

echo "Building..."
swift build

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

# Generate app icon from claude-color.svg
echo "Generating app icon..."
ICONSET_DIR="/tmp/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Use Swift to render icon at multiple sizes
swift /dev/stdin "$ICONSET_DIR" << 'SWIFT'
import AppKit

let outputDir = CommandLine.arguments[1]

let svgPath = "M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z"

func parseSVGPath(_ d: String, into path: NSBezierPath) {
    let chars = Array(d)
    var i = 0
    var currentX: Double = 0, currentY: Double = 0
    var lastCommand: Character = "M"

    func skip() { while i < chars.count && " ,\n\r\t".contains(chars[i]) { i += 1 } }
    func peekNum() -> Bool { skip(); guard i < chars.count else { return false }; return "-+.".contains(chars[i]) || chars[i].isNumber }
    func readNum() -> Double? {
        skip(); guard i < chars.count else { return nil }
        var s = ""; if "-+".contains(chars[i]) { s.append(chars[i]); i += 1 }
        var dot = false
        while i < chars.count { let c = chars[i]; if c.isNumber { s.append(c); i += 1 } else if c == "." && !dot { dot = true; s.append(c); i += 1 } else { break } }
        if i < chars.count && "eE".contains(chars[i]) { s.append(chars[i]); i += 1; if i < chars.count && "-+".contains(chars[i]) { s.append(chars[i]); i += 1 }; while i < chars.count && chars[i].isNumber { s.append(chars[i]); i += 1 } }
        return Double(s)
    }

    while i < chars.count {
        skip(); guard i < chars.count else { break }
        var cmd = chars[i]
        if cmd.isLetter && !"eE".contains(cmd) { lastCommand = cmd; i += 1 } else { cmd = lastCommand }
        switch cmd {
        case "M": guard let x = readNum(), let y = readNum() else { break }; currentX = x; currentY = y; path.move(to: NSPoint(x: x, y: y)); lastCommand = "L"
        case "m": guard let dx = readNum(), let dy = readNum() else { break }; currentX += dx; currentY += dy; path.move(to: NSPoint(x: currentX, y: currentY)); lastCommand = "l"
        case "L": guard let x = readNum(), let y = readNum() else { break }; currentX = x; currentY = y; path.line(to: NSPoint(x: x, y: y))
        case "l": guard let dx = readNum(), let dy = readNum() else { break }; currentX += dx; currentY += dy; path.line(to: NSPoint(x: currentX, y: currentY))
        case "H": guard let x = readNum() else { break }; currentX = x; path.line(to: NSPoint(x: currentX, y: currentY))
        case "h": guard let dx = readNum() else { break }; currentX += dx; path.line(to: NSPoint(x: currentX, y: currentY))
        case "V": guard let y = readNum() else { break }; currentY = y; path.line(to: NSPoint(x: currentX, y: currentY))
        case "v": guard let dy = readNum() else { break }; currentY += dy; path.line(to: NSPoint(x: currentX, y: currentY))
        case "C": guard let x1 = readNum(), let y1 = readNum(), let x2 = readNum(), let y2 = readNum(), let x = readNum(), let y = readNum() else { break }
            path.curve(to: NSPoint(x: x, y: y), controlPoint1: NSPoint(x: x1, y: y1), controlPoint2: NSPoint(x: x2, y: y2)); currentX = x; currentY = y
        case "c": guard let dx1 = readNum(), let dy1 = readNum(), let dx2 = readNum(), let dy2 = readNum(), let dx = readNum(), let dy = readNum() else { break }
            path.curve(to: NSPoint(x: currentX+dx, y: currentY+dy), controlPoint1: NSPoint(x: currentX+dx1, y: currentY+dy1), controlPoint2: NSPoint(x: currentX+dx2, y: currentY+dy2)); currentX += dx; currentY += dy
        case "a": let _ = readNum(); let _ = readNum(); let _ = readNum(); let _ = readNum(); let _ = readNum(); guard let dx = readNum(), let dy = readNum() else { break }; currentX += dx; currentY += dy; path.line(to: NSPoint(x: currentX, y: currentY))
        case "A": let _ = readNum(); let _ = readNum(); let _ = readNum(); let _ = readNum(); let _ = readNum(); guard let x = readNum(), let y = readNum() else { break }; currentX = x; currentY = y; path.line(to: NSPoint(x: x, y: y))
        case "Z", "z": path.close()
        default: i += 1
        }
    }
}

func render(size: Int, name: String) {
    let padding: CGFloat = CGFloat(size) * 0.1
    let scale = (CGFloat(size) - padding * 2) / 24.0
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    // White rounded-rect background
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: CGFloat(size)*0.2, yRadius: CGFloat(size)*0.2)
    NSColor.white.setFill()
    bgPath.fill()
    // Draw Claude logo
    ctx.translateBy(x: padding, y: CGFloat(size) - padding)
    ctx.scaleBy(x: scale, y: -scale)
    let bezier = NSBezierPath()
    parseSVGPath(svgPath, into: bezier)
    NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1.0).setFill()
    bezier.fill()
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff), let png = bmp.representation(using: .png, properties: [:]) else { return }
    do { try png.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png")) } catch { print("Failed to write \(name): \(error)"); return }
}

let sizes = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (sz, name) in sizes { render(size: sz, name: name) }
print("Icon PNGs generated")
SWIFT

# Convert to icns
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc sign
codesign --force --sign - "$APP_DIR"

echo ""
echo "Done! App created at: $(pwd)/$APP_DIR"
echo "You can move it to /Applications or double-click to run."
