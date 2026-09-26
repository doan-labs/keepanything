import Foundation
import GRDB
import KAModel

/// One embedding row with its vector decoded.
public struct EmbeddingRow: Sendable, Equatable {
  public var itemId: String
  public var chunkIndex: Int
  public var role: EmbeddingRole
  public var content: String
  public var model: String
  public var dims: Int
  public var vector: [Float]
  public init(itemId: String = "", chunkIndex: Int = 0, role: EmbeddingRole = .summary,
              content: String = "", model: String = "", dims: Int = 0, vector: [Float] = []) {
    self.itemId = itemId
    self.chunkIndex = chunkIndex
    self.role = role
    self.content = content
    self.model = model
    self.dims = dims
    self.vector = vector
  }
}

/// Encode a `[Float]` as the little-endian BLOB stored in `embeddings.vector`
/// (host-endianness-independent; the file format is little-endian float32).
public func vectorToBlob(_ vector: [Float]) -> Data {
  var data = Data(capacity: vector.count * 4)
  for v in vector {
    var le = v.bitPattern.littleEndian
    withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
  }
  return data
}

/// Decode a BLOB into `[Float]`. The BLOB length is the source of truth; `dims` only caps it.
public func blobToVector(_ blob: Data, dims: Int) -> [Float] {
  let stored = blob.count / 4
  let n = dims > 0 ? min(dims, stored) : stored
  var out = [Float](repeating: 0, count: n)
  out.withUnsafeMutableBufferPointer { dst in
    for i in 0..<n {
      var bits: UInt32 = 0
      withUnsafeMutableBytes(of: &bits) { dst8 in
        dst8.copyBytes(from: blob[(i * 4) ..< (i * 4 + 4)])
      }
      dst[i] = Float(bitPattern: UInt32(littleEndian: bits))
    }
  }
  return out
}

private func rowToEmbedding(_ row: Row) throws -> EmbeddingRow {
  let dims = Int(numOr(row["dims"], 0))
  let blob = (try? Data.fromDatabaseValue(row["vector"])) ?? Data()
  return EmbeddingRow(
    itemId: try requireText(row["item_id"], "item_id"),
    chunkIndex: Int(numOr(row["chunk_index"], 0)),
    role: EmbeddingRole(rawValue: try requireText(row["role"], "role")) ?? .summary,
    content: try requireText(row["content"], "content"),
    model: try requireText(row["model"], "model"),
    dims: dims,
    vector: blobToVector(blob, dims: dims)
  )
}

/// Embedding repository.
public struct EmbeddingRepo: Sendable {
  let db: Db
  public init(db: Db) { self.db = db }

  private let upsertSql = """
    INSERT INTO embeddings (item_id, chunk_index, role, content, vector, model, dims) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (item_id, chunk_index) DO UPDATE SET role = excluded.role, content = excluded.content,
    vector = excluded.vector, model = excluded.model, dims = excluded.dims
    """

  /// Replace only the given chunk indexes (e.g. chunk 0 after re-indexing).
  public func upsert(_ rows: [EmbeddingRow]) throws {
    try db.run { d in
      for r in rows {
        try d.execute(sql: upsertSql, arguments: [
          r.itemId, r.chunkIndex, r.role.rawValue, r.content, vectorToBlob(r.vector), r.model, r.dims
        ])
      }
    }
  }

  /// Delete every chunk of the item, then insert `rows` (one transaction by the caller).
  public func replaceForItem(_ itemId: String, rows: [EmbeddingRow]) throws {
    try db.run { d in
      try d.execute(sql: "DELETE FROM embeddings WHERE item_id = ?", arguments: [itemId])
    }
    try upsert(rows)
  }

  public func forItem(_ itemId: String) throws -> [EmbeddingRow] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: "SELECT * FROM embeddings WHERE item_id = ? ORDER BY chunk_index",
                       arguments: [itemId]).map(rowToEmbedding)
    }
  }

  /// All rows for one model (vector matrix load at startup).
  public func allForModel(_ model: String) throws -> [EmbeddingRow] {
    try db.readOnly { d in
      try Row.fetchAll(d, sql: """
        SELECT e.* FROM embeddings e JOIN items i ON i.id = e.item_id
        WHERE e.model = ? AND i.deleted_at IS NULL ORDER BY e.item_id, e.chunk_index
        """, arguments: [model]).map(rowToEmbedding)
    }
  }

  public func deleteForItem(_ itemId: String) throws {
    try db.run { d in
      try d.execute(sql: "DELETE FROM embeddings WHERE item_id = ?", arguments: [itemId])
    }
  }

  public func countForModel(_ model: String) throws -> Int {
    let row = try db.readOnly { d in
      try Row.fetchOne(d, sql: "SELECT count(*) AS n FROM embeddings WHERE model = ?", arguments: [model])
    }
    return Int(numOr(row?["n"], 0))
  }
}
