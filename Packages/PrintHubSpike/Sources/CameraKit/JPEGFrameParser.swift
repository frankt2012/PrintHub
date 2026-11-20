import Foundation

/// Extracts JPEG frames from an MJPEG byte stream.
///
/// MJPEG is a multipart stream, but real printers vary in their headers and
/// chunking. Scanning for JPEG SOI/EOI markers is more tolerant than trusting
/// `Content-Length`, and it handles frames split across TCP packets.
public struct JPEGFrameParser: Sendable {
    private var buffer = Data()
    private static let soi = Data([0xFF, 0xD8])
    private static let eoi = Data([0xFF, 0xD9])

    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)

        var frames: [Data] = []

        while true {
            guard let start = buffer.range(of: Self.soi)?.lowerBound else {
                // Keep the last byte: it could be the first half of an SOI
                // marker split across two reads.
                if buffer.count > 1 {
                    buffer = Data(buffer.suffix(1))
                }
                break
            }

            if start > 0 {
                buffer.removeSubrange(0..<start)
            }

            guard buffer.count > 2 else { break }

            guard let end = buffer.range(of: Self.eoi, in: 2..<buffer.count)?.upperBound else {
                // A runaway buffer means we lost sync. Drop it rather than
                // growing without bound.
                if buffer.count > 16 * 1024 * 1024 {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            frames.append(buffer.subdata(in: 0..<end))
            buffer.removeSubrange(0..<end)
        }

        return frames
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
