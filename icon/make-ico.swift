// Assembles a .ico (Windows) with PNG payloads (Vista+ format), from already-
// rendered PNGs. This way the Windows icon uses EXACTLY the same pixels as macOS.
// Usage: ./make-ico output.ico 16:a.png 32:b.png 48:c.png ...
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("uso: make-ico out.ico size:png …\n".data(using: .utf8)!); exit(1) }
let out = args[1]

func u16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
func u32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }

var imgs: [(size: Int, data: Data)] = []
for arg in args.dropFirst(2) {
    let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let size = Int(parts[0]),
          let data = try? Data(contentsOf: URL(fileURLWithPath: parts[1])) else {
        FileHandle.standardError.write("no pude leer \(arg)\n".data(using: .utf8)!); exit(1)
    }
    imgs.append((size, data))
}

var header = Data()
header.append(u16(0))            // reserved
header.append(u16(1))            // type = icon
header.append(u16(imgs.count))   // count

var dir = Data()
var blob = Data()
var offset = 6 + imgs.count * 16
for img in imgs {
    dir.append(UInt8(img.size >= 256 ? 0 : img.size))   // width  (0 = 256)
    dir.append(UInt8(img.size >= 256 ? 0 : img.size))   // height (0 = 256)
    dir.append(0)                                       // num colors
    dir.append(0)                                       // reserved
    dir.append(u16(1))                                  // color planes
    dir.append(u16(32))                                 // bits per pixel
    dir.append(u32(img.data.count))                     // size of data
    dir.append(u32(offset))                             // offset
    offset += img.data.count
    blob.append(img.data)
}

var ico = Data()
ico.append(header); ico.append(dir); ico.append(blob)
do { try ico.write(to: URL(fileURLWithPath: out)); print("✅ \(out) (\(imgs.count) tamaños)") }
catch { FileHandle.standardError.write("no pude escribir \(out)\n".data(using: .utf8)!); exit(1) }
