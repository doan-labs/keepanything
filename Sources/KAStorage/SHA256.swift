import Foundation

/// Pure-Swift SHA-256 (no CryptoKit on Linux; verified against CryptoKit in tests on macOS).
enum Sha256 {
  private static let k: [UInt32] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]

  static func hash(_ data: Data) -> [UInt8] {
    var msg = [UInt8](data)
    let bitLen = UInt64(data.count) * 8
    msg.append(0x80)
    while msg.count % 64 != 56 { msg.append(0) }
    for i in (0..<8).reversed() { msg.append(UInt8((bitLen >> UInt64(i * 8)) & 0xff)) }

    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var w = [UInt32](repeating: 0, count: 64)

    for blockStart in stride(from: 0, to: msg.count, by: 64) {
      for i in 0..<16 {
        w[i] = msg.withUnsafeBytes { $0.load(fromByteOffset: blockStart + i * 4, as: UInt32.self).bigEndian }
      }
      for i in 16..<64 {
        let s0 = w[i - 15].rotateRight(7) ^ w[i - 15].rotateRight(18) ^ (w[i - 15] >> 3)
        let s1 = w[i - 2].rotateRight(17) ^ w[i - 2].rotateRight(19) ^ (w[i - 2] >> 10)
        w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
      for i in 0..<64 {
        let s1 = e.rotateRight(6) ^ e.rotateRight(11) ^ e.rotateRight(25)
        let ch = (e & f) ^ (~e & g)
        let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
        let s0 = a.rotateRight(2) ^ a.rotateRight(13) ^ a.rotateRight(22)
        let maj = (a & b) ^ (a & c) ^ (b & c)
        let t2 = s0 &+ maj
        hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
      }
      h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
    }
    return h.flatMap { word -> [UInt8] in
      [UInt8((word >> 24) & 0xff), UInt8((word >> 16) & 0xff), UInt8((word >> 8) & 0xff), UInt8(word & 0xff)]
    }
  }

  static func hex(_ data: Data) -> String {
    hash(data).map { String(format: "%02x", $0) }.joined()
  }
}

private extension UInt32 {
  func rotateRight(_ n: Int) -> UInt32 { (self >> n) | (self << (32 - n)) }
}

/// sha256 hex of in-memory bytes.
func sha256Bytes(_ data: Data) -> String { Sha256.hex(data) }

/// Streaming sha256 hex of a file.
func sha256File(_ path: String) throws -> String {
  // Files here are bounded library objects; a single read keeps this simple and total.
  sha256Bytes(try Data(contentsOf: URL(fileURLWithPath: path)))
}
