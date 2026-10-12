import Foundation

/// A mono 16-bit PCM WAVE file, the plainest audio file every player opens.
public enum PCMWaveFile {
    /// Encodes samples in the range -1...1; louder samples are clipped rather than wrapped.
    public static func encode(samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataByteCount = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataByteCount)
        func appendLittleEndian<Number: FixedWidthInteger>(_ number: Number) {
            withUnsafeBytes(of: number.littleEndian) { bytes in data.append(contentsOf: bytes) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(UInt32(36 + dataByteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(UInt32(16))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt32(sampleRate))
        appendLittleEndian(UInt32(sampleRate * bytesPerSample))
        appendLittleEndian(UInt16(bytesPerSample))
        appendLittleEndian(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(UInt32(dataByteCount))
        for sample in samples {
            let clipped = max(-1, min(1, sample.isFinite ? sample : 0))
            appendLittleEndian(Int16(clipped * Float(Int16.max)))
        }
        return data
    }
}
