#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum FigletError: Error, CustomStringConvertible, Sendable {
  case fontNotFound(String)
  case invalidFont(String)
  case characterDoesNotFit(Character, width: Int)
  case invalidConfiguration(String)

  public var description: String {
    switch self {
    case .fontNotFound(let font):
      return "requested font '\(font)' not found"
    case .invalidFont(let message):
      return message
    case .characterDoesNotFit(let character, let width):
      return "width \(width) is not enough to print character '\(character)'"
    case .invalidConfiguration(let message):
      return message
    }
  }
}

public enum FigletDirection: String, CaseIterable, Sendable {
  case automatic = "auto"
  case leftToRight = "left-to-right"
  case rightToLeft = "right-to-left"
}

public enum FigletJustification: String, CaseIterable, Sendable {
  case automatic = "auto"
  case left
  case center
  case right
}

public struct FigletConfiguration: Sendable {
  public var width: Int
  public var direction: FigletDirection
  public var justification: FigletJustification

  public init(
    width: Int = 80,
    direction: FigletDirection = .automatic,
    justification: FigletJustification = .automatic
  ) {
    self.width = width
    self.direction = direction
    self.justification = justification
  }
}

public struct FigletFontLibrary: Sendable {
  public let name: String?

  private let fonts: [String: [UInt8]]

  public init(name: String? = nil, fonts: [String: [UInt8]]) {
    self.name = name
    self.fonts = fonts.reduce(into: [:]) { result, entry in
      result[Self.normalizedFontName(for: entry.key)] = entry.value
    }
  }

  public init(name: String? = nil, fontData: [String: String]) {
    self.init(name: name, fonts: fontData.mapValues { Array($0.utf8) })
  }

  public var fontNames: [String] {
    fonts.keys.sorted()
  }

  public func font(named identifier: String) throws -> FigletFont? {
    guard let entry = fontEntry(named: identifier) else {
      return nil
    }

    return try FigletFont.parse(
      data: entry.data,
      name: entry.name
    )
  }

  private func fontEntry(named identifier: String) -> (name: String, data: [UInt8])? {
    guard !identifier.contains("/") else {
      return nil
    }

    let normalizedIdentifier = Self.normalizedFontName(for: identifier)
    guard let data = fonts[normalizedIdentifier] else {
      return nil
    }

    return (normalizedIdentifier, data)
  }

  private static func normalizedFontName(for identifier: String) -> String {
    if identifier.hasSupportedFontExtension {
      return identifier.lastPathComponentWithoutExtension
    }

    return identifier
  }
}

public struct FigletText: CustomStringConvertible, Equatable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }

  public func reversed() -> FigletText {
    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    let reversedRows = rows.map { row in
      String(row.map(Self.reverseMap).reversed())
    }
    return FigletText(reversedRows.joined(separator: "\n"))
  }

  public func flipped() -> FigletText {
    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    let flippedRows = rows.reversed().map { row in
      String(row.map(Self.flipMap))
    }
    return FigletText(flippedRows.joined(separator: "\n"))
  }

  public func strippingSurroundingNewlines() -> String {
    let rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    var output: [Substring] = []
    var sawContent = false

    for row in rows {
      if row.containsNonWhitespace || sawContent {
        sawContent = true
        output.append(row)
      }
    }

    return output.joined(separator: "\n").trimmingTrailingWhitespaceAndNewlines()
  }

  public func normalizingSurroundingNewlines() -> String {
    "\n\(strippingSurroundingNewlines())\n"
  }

  private static func reverseMap(_ character: Character) -> Character {
    switch character {
    case "(": return ")"
    case ")": return "("
    case "/": return "\\"
    case "\\": return "/"
    case "[": return "]"
    case "]": return "["
    case "{": return "}"
    case "}": return "{"
    case "<": return ">"
    case ">": return "<"
    default: return character
    }
  }

  private static func flipMap(_ character: Character) -> Character {
    switch character {
    case "/": return "\\"
    case "\\": return "/"
    case "_": return " "
    case "^": return "v"
    case "v": return "^"
    case "M": return "W"
    case "W": return "M"
    default: return character
    }
  }
}

public struct FigletSize: Equatable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }
}

public struct FigletLayoutMetrics: Equatable, Sendable {
  public let minimumWidth: Int
  public let idealSize: FigletSize

  public init(minimumWidth: Int, idealSize: FigletSize) {
    self.minimumWidth = max(0, minimumWidth)
    self.idealSize = idealSize
  }
}

public struct FigletFont: Sendable {
  public static let defaultFontName = "standard"

  public let name: String
  public let height: Int
  public let baseline: Int
  public let hardBlank: Character
  public let printDirection: Int?
  public let smushMode: Int
  public let comment: String

  let characters: [Int: [String]]
  let widths: [Int: Int]

  public init(named name: String) throws {
    self = try Self.load(identifier: name)
  }

  public init(named name: String, fontLibrary: FigletFontLibrary) throws {
    self = try Self.load(identifier: name, fontLibraries: [fontLibrary])
  }

  public init(named name: String, fontLibraries: [FigletFontLibrary]) throws {
    self = try Self.load(identifier: name, fontLibraries: fontLibraries)
  }

  public init(named name: String, searchDirectories: [String]) throws {
    self = try Self.load(identifier: name, searchDirectories: searchDirectories)
  }

  public init(named name: String, fontLibrary: FigletFontLibrary, searchDirectories: [String])
    throws
  {
    self = try Self.load(
      identifier: name,
      fontLibraries: [fontLibrary],
      searchDirectories: searchDirectories
    )
  }

  public init(named name: String, fontLibraries: [FigletFontLibrary], searchDirectories: [String])
    throws
  {
    self = try Self.load(
      identifier: name,
      fontLibraries: fontLibraries,
      searchDirectories: searchDirectories
    )
  }

  public init(filePath: String) throws {
    self = try Self.load(
      filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
  }

  public var info: String {
    comment
  }

  public static func bundledFontNames() -> [String] {
    availableFontNames()
  }

  public static func availableFontNames() -> [String] {
    availableFontNames(in: defaultFontSearchDirectories())
  }

  public static func availableFontNames(fontLibraries: [FigletFontLibrary]) -> [String] {
    availableFontNames(in: defaultFontSearchDirectories(), libraries: fontLibraries)
  }

  public static func availableFontNames(in searchDirectories: [String]) -> [String] {
    availableFontNames(in: searchDirectories, libraries: [])
  }

  public static func availableFontNames(
    in searchDirectories: [String],
    libraries: [FigletFontLibrary]
  ) -> [String] {
    uniquePaths(searchDirectories)
      .flatMap { directory in
        directoryEntries(at: directory)
          .filter { $0.hasSupportedFontExtension }
          .map(\.lastPathComponentWithoutExtension)
      }
      .reduce(into: Set(libraries.flatMap(\.fontNames))) { result, name in
        result.insert(name)
      }
      .sorted()
  }

  static func load(identifier: String) throws -> FigletFont {
    try load(
      identifier: identifier,
      fontLibraries: [],
      searchDirectories: defaultFontSearchDirectories()
    )
  }

  static func load(identifier: String, fontLibraries: [FigletFontLibrary]) throws -> FigletFont {
    try load(
      identifier: identifier,
      fontLibraries: fontLibraries,
      searchDirectories: defaultFontSearchDirectories()
    )
  }

  static func load(identifier: String, searchDirectories: [String]) throws -> FigletFont {
    try load(identifier: identifier, fontLibraries: [], searchDirectories: searchDirectories)
  }

  static func load(
    identifier: String,
    fontLibraries: [FigletFontLibrary],
    searchDirectories: [String]
  ) throws -> FigletFont {
    if let filePath = resolveExternalFontPath(for: identifier) {
      return try load(filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
    }

    for fontLibrary in fontLibraries {
      if let font = try fontLibrary.font(named: identifier) {
        return font
      }
    }

    for directory in uniquePaths(searchDirectories) {
      if let filePath = resolveFontPath(named: identifier, in: directory) {
        return try load(
          filePath: filePath, fallbackName: filePath.lastPathComponentWithoutExtension)
      }
    }

    throw FigletError.fontNotFound(identifier)
  }

  private static func load(filePath: String, fallbackName: String) throws -> FigletFont {
    let data = try readFile(at: filePath)
    return try parse(data: data, name: fallbackName)
  }

  private static func resolveExternalFontPath(for identifier: String) -> String? {
    if fileExists(at: identifier) {
      return identifier
    }

    for ext in supportedFontExtensions {
      let candidate = "\(identifier).\(ext)"
      if fileExists(at: candidate) {
        return candidate
      }
    }

    return nil
  }

  private static func resolveFontPath(named identifier: String, in directory: String) -> String? {
    if identifier.hasSupportedFontExtension {
      let directPath = pathByAppending(directory, identifier)
      return fileExists(at: directPath) ? directPath : nil
    }

    for ext in supportedFontExtensions {
      let candidate = pathByAppending(directory, "\(identifier).\(ext)")
      if fileExists(at: candidate) {
        return candidate
      }
    }

    return nil
  }

  private static func defaultFontSearchDirectories() -> [String] {
    var directories: [String] = []

    if let envValue = environmentValue(named: "SWIFT_FIGLET_FONT_DIRS") {
      directories.append(contentsOf: envValue.split(separator: ":").map(String.init))
    }

    if let envValue = environmentValue(named: "SWIFT_FIGLET_FONT_DIR") {
      directories.append(envValue)
    }

    if let homeDirectory = environmentValue(named: "HOME") {
      directories.append(pathByAppending(homeDirectory, ".figfonts"))
    }

    directories.append("figfonts")

    return uniquePaths(directories).filter(isDirectory(at:))
  }

  fileprivate static func parse(data: [UInt8], name: String) throws -> FigletFont {
    if data.starts(with: theDrawMagic) {
      return try parseTheDrawFont(data: data, name: name)
    }

    return try parseFigletFont(data: String(decoding: data, as: UTF8.self), name: name)
  }

  private static func parseFigletFont(data: String, name: String) throws -> FigletFont {
    let sanitized = data.sanitizedFontData()

    let lines = sanitized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lineIndex = 0

    let headerLine = try consumeLine(from: lines, index: &lineIndex)
    guard headerLine.hasPrefix("flf2") || headerLine.hasPrefix("tlf2") else {
      throw FigletError.invalidFont("\(name) is not a valid figlet font")
    }
    guard headerLine.count >= 6 else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    let headerRemainder = String(headerLine.dropFirst(5))
    let headerParts = headerRemainder.split(whereSeparator: \.isWhitespace).map(String.init)
    guard headerParts.count >= 6 else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    guard let hardBlank = headerParts[0].first,
      let height = Int(headerParts[1]),
      let baseline = Int(headerParts[2]),
      Int(headerParts[3]) != nil,
      let oldLayout = Int(headerParts[4]),
      let commentLines = Int(headerParts[5])
    else {
      throw FigletError.invalidFont("malformed header for \(name)")
    }

    let printDirection = headerParts.count > 6 ? Int(headerParts[6]) : nil
    let fullLayout = headerParts.count > 7 ? Int(headerParts[7]) : nil
    let smushMode: Int
    if let fullLayout {
      smushMode = fullLayout
    } else if oldLayout == 0 {
      smushMode = 64
    } else if oldLayout < 0 {
      smushMode = 0
    } else {
      smushMode = (oldLayout & 31) | 128
    }

    var commentLinesBuffer: [String] = []
    for _ in 0..<commentLines {
      commentLinesBuffer.append(try consumeLine(from: lines, index: &lineIndex))
    }

    var characters: [Int: [String]] = [:]
    var widths: [Int: Int] = [:]

    for codePoint in 32..<127 {
      let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
      if codePoint == 32 || !glyph.rows.joined().isEmpty {
        characters[codePoint] = glyph.rows
        widths[codePoint] = glyph.width
      }
    }

    do {
      for character in ["Ä", "Ö", "Ü", "ä", "ö", "ü", "ß"] {
        guard lineIndex < lines.count, glyphIdentifier(in: lines[lineIndex]) == nil else {
          break
        }

        let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
        if !glyph.rows.joined().isEmpty, let scalar = character.unicodeScalars.first {
          characters[Int(scalar.value)] = glyph.rows
          widths[Int(scalar.value)] = glyph.width
        }
      }

      while lineIndex < lines.count {
        let definition = try consumeLine(from: lines, index: &lineIndex).trimmingFigletWhitespace()
        guard !definition.isEmpty else {
          continue
        }

        guard let codePoint = glyphIdentifier(in: definition) else {
          continue
        }

        let glyph = try consumeGlyph(from: lines, index: &lineIndex, height: height)
        if !glyph.rows.joined().isEmpty {
          characters[codePoint] = glyph.rows
          widths[codePoint] = glyph.width
        }
      }
    } catch {
      // Extended glyph tables are optional; keep the ASCII core usable even if
      // a font's supplementary section is truncated or uses an unsupported layout.
    }

    return FigletFont(
      name: name,
      height: height,
      baseline: baseline,
      hardBlank: hardBlank,
      printDirection: printDirection,
      smushMode: smushMode,
      comment: commentLinesBuffer.joined(separator: "\n"),
      characters: characters,
      widths: widths
    )
  }

  private init(
    name: String,
    height: Int,
    baseline: Int,
    hardBlank: Character,
    printDirection: Int?,
    smushMode: Int,
    comment: String,
    characters: [Int: [String]],
    widths: [Int: Int]
  ) {
    self.name = name
    self.height = height
    self.baseline = baseline
    self.hardBlank = hardBlank
    self.printDirection = printDirection
    self.smushMode = smushMode
    self.comment = comment
    self.characters = characters
    self.widths = widths
  }

  private static let theDrawMagic = Array("\u{0013}TheDraw FONTS file\u{001A}".utf8)
  private static let theDrawCharacters = Array(
    "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
      .unicodeScalars
      .map { Int($0.value) })

  private static func parseTheDrawFont(data: [UInt8], name: String) throws -> FigletFont {
    let dataStart = 233
    guard data.count >= dataStart else {
      throw FigletError.invalidFont("\(name) is not a valid TheDraw font")
    }
    guard data[41] == 2 else {
      throw FigletError.invalidFont("\(name) uses an unsupported TheDraw font type")
    }

    let spacing = Int(data[42])
    let offsets = (0..<theDrawCharacters.count).map { index in
      readLittleEndianUInt16(from: data, at: 45 + index * 2)
    }

    var fontHeight = 0
    for offset in offsets where offset != 0xFFFF {
      let glyphStart = dataStart + Int(offset)
      guard glyphStart + 1 < data.count else {
        throw FigletError.invalidFont("\(name) contains an invalid TheDraw glyph offset")
      }
      fontHeight = max(fontHeight, Int(data[glyphStart + 1]))
    }

    var characters: [Int: [String]] = [:]
    var widths: [Int: Int] = [:]

    for (index, offset) in offsets.enumerated() where offset != 0xFFFF {
      let glyph = try parseTheDrawGlyph(
        data: data,
        dataStart: dataStart,
        offset: Int(offset),
        fontHeight: fontHeight,
        spacing: spacing,
        fontName: name
      )
      let codePoint = theDrawCharacters[index]
      characters[codePoint] = glyph.rows
      widths[codePoint] = glyph.width
    }

    return FigletFont(
      name: name,
      height: fontHeight,
      baseline: fontHeight,
      hardBlank: " ",
      printDirection: 0,
      smushMode: 0,
      comment: theDrawFontName(from: data) ?? "",
      characters: characters,
      widths: widths
    )
  }

  private static func parseTheDrawGlyph(
    data: [UInt8],
    dataStart: Int,
    offset: Int,
    fontHeight: Int,
    spacing: Int,
    fontName: String
  ) throws -> (width: Int, rows: [String]) {
    let glyphStart = dataStart + offset
    guard glyphStart + 1 < data.count else {
      throw FigletError.invalidFont("\(fontName) contains an invalid TheDraw glyph offset")
    }

    let glyphWidth = Int(data[glyphStart])
    let glyphHeight = Int(data[glyphStart + 1])
    let renderedWidth = glyphWidth + spacing
    var cells = Array(
      repeating: Array(repeating: Character(" "), count: renderedWidth),
      count: fontHeight
    )

    var row = 0
    var column = 0
    var index = glyphStart + 2

    while index < data.count {
      let byte = data[index]
      index += 1

      if byte == 0 {
        break
      }

      if byte == 13 {
        row += 1
        column = 0
        continue
      }

      guard index < data.count else {
        throw FigletError.invalidFont("\(fontName) contains a truncated TheDraw glyph")
      }
      index += 1

      if row < min(glyphHeight, fontHeight), column < glyphWidth {
        cells[row][column] = theDrawCharacter(for: byte)
      }
      column += 1
    }

    return (renderedWidth, cells.map { String($0) })
  }

  private static func readLittleEndianUInt16(from data: [UInt8], at index: Int) -> Int {
    Int(data[index]) | (Int(data[index + 1]) << 8)
  }

  private static func theDrawFontName(from data: [UInt8]) -> String? {
    let nameLength = Int(data[24])
    guard nameLength > 0 else {
      return nil
    }

    let upperBound = min(25 + nameLength, 41, data.count)
    let bytes = data[25..<upperBound].prefix { $0 != 0 }
    let characters = bytes.map(theDrawCharacter)
    return characters.isEmpty ? nil : String(characters)
  }

  private static func theDrawCharacter(for byte: UInt8) -> Character {
    if byte < 0x20 {
      return " "
    }

    if byte < 0x7F {
      return Character(UnicodeScalar(Int(byte))!)
    }

    return Character(cp437Scalars[Int(byte) - 0x7F])
  }
}

private let supportedFontExtensions = ["flf", "tlf", "tdf"]

private let cp437Scalars: [UnicodeScalar] = [
  "\u{2302}", "\u{00C7}", "\u{00FC}", "\u{00E9}", "\u{00E2}", "\u{00E4}", "\u{00E0}",
  "\u{00E5}", "\u{00E7}", "\u{00EA}", "\u{00EB}", "\u{00E8}", "\u{00EF}", "\u{00EE}",
  "\u{00EC}", "\u{00C4}", "\u{00C5}", "\u{00C9}", "\u{00E6}", "\u{00C6}", "\u{00F4}",
  "\u{00F6}", "\u{00F2}", "\u{00FB}", "\u{00F9}", "\u{00FF}", "\u{00D6}", "\u{00DC}",
  "\u{00A2}", "\u{00A3}", "\u{00A5}", "\u{20A7}", "\u{0192}", "\u{00E1}", "\u{00ED}",
  "\u{00F3}", "\u{00FA}", "\u{00F1}", "\u{00D1}", "\u{00AA}", "\u{00BA}", "\u{00BF}",
  "\u{2310}", "\u{00AC}", "\u{00BD}", "\u{00BC}", "\u{00A1}", "\u{00AB}", "\u{00BB}",
  "\u{2591}", "\u{2592}", "\u{2593}", "\u{2502}", "\u{2524}", "\u{2561}", "\u{2562}",
  "\u{2556}", "\u{2555}", "\u{2563}", "\u{2551}", "\u{2557}", "\u{255D}", "\u{255C}",
  "\u{255B}", "\u{2510}", "\u{2514}", "\u{2534}", "\u{252C}", "\u{251C}", "\u{2500}",
  "\u{253C}", "\u{255E}", "\u{255F}", "\u{255A}", "\u{2554}", "\u{2569}", "\u{2566}",
  "\u{2560}", "\u{2550}", "\u{256C}", "\u{2567}", "\u{2568}", "\u{2564}", "\u{2565}",
  "\u{2559}", "\u{2558}", "\u{2552}", "\u{2553}", "\u{256B}", "\u{256A}", "\u{2518}",
  "\u{250C}", "\u{2588}", "\u{2584}", "\u{258C}", "\u{2590}", "\u{2580}", "\u{03B1}",
  "\u{00DF}", "\u{0393}", "\u{03C0}", "\u{03A3}", "\u{03C3}", "\u{00B5}", "\u{03C4}",
  "\u{03A6}", "\u{0398}", "\u{03A9}", "\u{03B4}", "\u{221E}", "\u{03C6}", "\u{03B5}",
  "\u{2229}", "\u{2261}", "\u{00B1}", "\u{2265}", "\u{2264}", "\u{2320}", "\u{2321}",
  "\u{00F7}", "\u{2248}", "\u{00B0}", "\u{2219}", "\u{00B7}", "\u{221A}", "\u{207F}",
  "\u{00B2}", "\u{25A0}", "\u{00A0}",
]

private func parseGlyphIdentifier(_ token: String) -> Int? {
  if token.lowercased().hasPrefix("0x") {
    return Int(token.dropFirst(2), radix: 16)
  }

  return Int(token)
}

private func glyphIdentifier(in definition: String) -> Int? {
  guard
    let identifier =
      definition
      .trimmingFigletWhitespace()
      .split(separator: " ", maxSplits: 1)
      .first
  else {
    return nil
  }

  return parseGlyphIdentifier(String(identifier))
}

public struct Figlet: Sendable {
  public let font: FigletFont
  public let configuration: FigletConfiguration

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration()
  ) throws {
    self.font = try FigletFont(named: name)
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibrary: FigletFontLibrary
  ) throws {
    try self.init(fontNamed: name, configuration: configuration, fontLibraries: [fontLibrary])
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibraries: [FigletFontLibrary]
  ) throws {
    self.font = try FigletFont(named: name, fontLibraries: fontLibraries)
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    searchDirectories: [String]
  ) throws {
    self.font = try FigletFont(named: name, searchDirectories: searchDirectories)
    self.configuration = configuration
  }

  public init(font: FigletFont, configuration: FigletConfiguration = FigletConfiguration()) {
    self.font = font
    self.configuration = configuration
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibrary: FigletFontLibrary,
    searchDirectories: [String]
  ) throws {
    try self.init(
      fontNamed: name,
      configuration: configuration,
      fontLibraries: [fontLibrary],
      searchDirectories: searchDirectories
    )
  }

  public init(
    fontNamed name: String = FigletFont.defaultFontName,
    configuration: FigletConfiguration = FigletConfiguration(),
    fontLibraries: [FigletFontLibrary],
    searchDirectories: [String]
  ) throws {
    self.font = try FigletFont(
      named: name,
      fontLibraries: fontLibraries,
      searchDirectories: searchDirectories
    )
    self.configuration = configuration
  }

  public func render(_ text: String) throws -> FigletText {
    guard configuration.width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    var builder = FigletBuilder(
      text: text,
      font: font,
      direction: resolvedDirection,
      width: configuration.width,
      justification: resolvedJustification
    )
    return try builder.render()
  }

  public func layoutMetrics(for text: String) throws -> FigletLayoutMetrics {
    guard configuration.width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    guard !text.isEmpty else {
      return FigletLayoutMetrics(
        minimumWidth: 0,
        idealSize: FigletSize(width: 0, height: 0)
      )
    }

    let minimumWidth = minimumRenderableWidth(for: text)
    let idealWidth = max(1, nonWrappingWidthUpperBound(for: text))
    var builder = FigletBuilder(
      text: text,
      font: font,
      direction: resolvedDirection,
      width: idealWidth,
      justification: resolvedJustification
    )
    let rows = try builder.renderRows()

    return FigletLayoutMetrics(
      minimumWidth: minimumWidth,
      idealSize: measureRows(rows)
    )
  }

  public func measure(_ text: String, forWidth width: Int) throws -> FigletSize {
    guard width > 0 else {
      throw FigletError.invalidConfiguration("width must be greater than zero")
    }

    let figlet = Figlet(
      font: font,
      configuration: FigletConfiguration(
        width: width,
        direction: configuration.direction,
        justification: configuration.justification
      )
    )
    return measureRenderedText(try figlet.render(text))
  }

  public static func availableFonts() -> [String] {
    FigletFont.bundledFontNames()
  }

  public static func availableFonts(fontLibraries: [FigletFontLibrary]) -> [String] {
    FigletFont.availableFontNames(fontLibraries: fontLibraries)
  }

  public static func availableFonts(
    searchDirectories: [String],
    fontLibraries: [FigletFontLibrary]
  ) -> [String] {
    FigletFont.availableFontNames(in: searchDirectories, libraries: fontLibraries)
  }

  private var resolvedDirection: ResolvedDirection {
    switch configuration.direction {
    case .leftToRight:
      return .leftToRight
    case .rightToLeft:
      return .rightToLeft
    case .automatic:
      return font.printDirection == 1 ? .rightToLeft : .leftToRight
    }
  }

  private var resolvedJustification: ResolvedJustification {
    switch configuration.justification {
    case .left:
      return .left
    case .center:
      return .center
    case .right:
      return .right
    case .automatic:
      return resolvedDirection == .leftToRight ? .left : .right
    }
  }

  private func minimumRenderableWidth(for text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { currentMaximum, scalar in
      currentMaximum = max(currentMaximum, font.widths[Int(scalar.value)] ?? 0)
    }
  }

  private func nonWrappingWidthUpperBound(for text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { total, scalar in
      total += font.widths[Int(scalar.value)] ?? 0
    }
  }
}

private enum ResolvedDirection: Sendable {
  case leftToRight
  case rightToLeft
}

private enum ResolvedJustification: Sendable {
  case left
  case center
  case right
}

private struct FigletBuilder {
  private let text: [Int]
  private let font: FigletFont
  private let direction: ResolvedDirection
  private let width: Int
  private let justification: ResolvedJustification

  private var iterator = 0
  private var maxSmush = 0
  private var currentCharacterWidth = 0
  private var previousCharacterWidth = 0
  private var blankMarkers: [([String], Int)] = []
  private var productQueue: [[String]] = []
  private var buffer: [String]

  init(
    text: String,
    font: FigletFont,
    direction: ResolvedDirection,
    width: Int,
    justification: ResolvedJustification
  ) {
    self.text = text.unicodeScalars.map { Int($0.value) }
    self.font = font
    self.direction = direction
    self.width = width
    self.justification = justification
    self.buffer = Array(repeating: "", count: font.height)
  }

  mutating func render() throws -> FigletText {
    FigletText(formatProduct(try renderRows()))
  }

  mutating func renderRows() throws -> [String] {
    while iterator < text.count {
      try addCurrentCharacterToProduct()
      iterator += 1
    }

    if buffer.first?.isEmpty == false {
      productQueue.append(buffer)
    }

    return formatRows()
  }

  private mutating func addCurrentCharacterToProduct() throws {
    let currentCode = text[iterator]

    if currentCode == 10 {
      blankMarkers.append((buffer, iterator))
      handleNewline()
      return
    }

    guard let glyph = glyph(at: iterator) else {
      return
    }

    guard let glyphWidth = glyphWidth(at: iterator) else {
      return
    }

    if width < glyphWidth, let scalar = UnicodeScalar(currentCode) {
      throw FigletError.characterDoesNotFit(Character(scalar), width: width)
    }

    currentCharacterWidth = glyphWidth
    maxSmush = smushAmount(buffer: buffer, glyph: glyph)
    let nextWidth = buffer[0].count + currentCharacterWidth - maxSmush

    if currentCode == 32 {
      blankMarkers.append((buffer, iterator))
    }

    if nextWidth > width {
      handleNewline()
    } else {
      for row in 0..<font.height {
        addGlyphRow(glyph, row: row)
      }
    }

    previousCharacterWidth = currentCharacterWidth
  }

  private func formatProduct(_ rows: [String]) -> String {
    rows.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
  }

  private func formatRows() -> [String] {
    productQueue.flatMap { replaceHardBlanks(in: justify($0)) }
  }

  private func glyph(at index: Int) -> [String]? {
    guard index >= 0, index < text.count else {
      return nil
    }
    return font.characters[text[index]]
  }

  private func glyphWidth(at index: Int) -> Int? {
    guard index >= 0, index < text.count else {
      return nil
    }
    return font.widths[text[index]]
  }

  private func smushedLeftCharacter(at position: Int, in left: String) -> (Character, Int)? {
    let index = left.count - maxSmush + position
    let characters = Array(left)
    guard index >= 0, index < characters.count else {
      return nil
    }
    return (characters[index], index)
  }

  private mutating func addGlyphRow(_ glyph: [String], row: Int) {
    var left = buffer[row]
    var right = glyph[row]

    if direction == .rightToLeft {
      swap(&left, &right)
    }

    for position in 0..<maxSmush {
      let leftEntry = smushedLeftCharacter(at: position, in: left)
      let rightCharacters = Array(right)
      let rightCharacter = rightCharacters[position]
      let merged = smush(left: leftEntry?.0, right: rightCharacter)

      if let merged, let leftIndex = leftEntry?.1 {
        left = left.replacingCharacter(at: leftIndex, with: merged)
      }
    }

    buffer[row] = left + String(Array(right).dropFirst(maxSmush))
  }

  private mutating func handleNewline() {
    if let (savedBuffer, savedIterator) = blankMarkers.popLast() {
      productQueue.append(savedBuffer)
      iterator = savedIterator
      resetBuffer()
    } else {
      productQueue.append(buffer)
      iterator -= 1
      resetBuffer()
    }
  }

  private mutating func resetBuffer() {
    buffer = Array(repeating: "", count: font.height)
    blankMarkers.removeAll(keepingCapacity: true)
    previousCharacterWidth = 0
    currentCharacterWidth = 0
    maxSmush = 0
  }

  private func justify(_ buffer: [String]) -> [String] {
    switch justification {
    case .left:
      return buffer
    case .right:
      return buffer.map { row in
        String(repeating: " ", count: max(0, width - row.count - 1)) + row
      }
    case .center:
      return buffer.map { row in
        String(repeating: " ", count: max(0, (width - row.count) / 2)) + row
      }
    }
  }

  private func replaceHardBlanks(in buffer: [String]) -> [String] {
    buffer.map { row in
      row.replacingCharacters(matching: font.hardBlank, with: " ")
    }
  }

  private func smushAmount(buffer: [String], glyph: [String]) -> Int {
    let smushOrKern = smushMode(.smush) || smushMode(.kern)
    guard smushOrKern else {
      return 0
    }

    var maxSmush = currentCharacterWidth

    for row in 0..<font.height {
      var leftLine = buffer[row]
      var rightLine = glyph[row]
      if direction == .rightToLeft {
        swap(&leftLine, &rightLine)
      }

      let leftCharacters = Array(leftLine)
      let rightCharacters = Array(rightLine)

      let lastNonSpaceIndex = leftCharacters.lastIndex(where: { $0 != " " }) ?? 0
      let leftCharacter =
        leftCharacters.indices.contains(lastNonSpaceIndex) ? leftCharacters[lastNonSpaceIndex] : nil

      let firstNonSpaceIndex =
        rightCharacters.firstIndex(where: { $0 != " " }) ?? rightCharacters.count
      let rightCharacter =
        rightCharacters.indices.contains(firstNonSpaceIndex)
        ? rightCharacters[firstNonSpaceIndex] : nil

      var amount = firstNonSpaceIndex + leftCharacters.count - 1 - lastNonSpaceIndex

      if leftCharacter == nil || leftCharacter == " " {
        amount += 1
      } else if let rightCharacter, smush(left: leftCharacter, right: rightCharacter) != nil {
        amount += 1
      }

      if amount < maxSmush {
        maxSmush = amount
      }
    }

    return maxSmush
  }

  private func smush(left: Character?, right: Character?) -> Character? {
    guard let right else {
      return left
    }

    if left == " " || left == nil {
      return right
    }

    guard let left else {
      return right
    }

    if right == " " {
      return left
    }

    if previousCharacterWidth < 2 || currentCharacterWidth < 2 {
      return nil
    }

    guard smushMode(.smush) else {
      return nil
    }

    if (font.smushMode & 63) == 0 {
      if left == font.hardBlank {
        return right
      }
      if right == font.hardBlank {
        return left
      }
      return direction == .rightToLeft ? left : right
    }

    if smushMode(.hardBlank), left == font.hardBlank, right == font.hardBlank {
      return left
    }

    if left == font.hardBlank || right == font.hardBlank {
      return nil
    }

    if smushMode(.equal), left == right {
      return left
    }

    if smushMode(.lowLine), left == "_", "|/\\[]{}()<>".contains(right) {
      return right
    }
    if smushMode(.lowLine), right == "_", "|/\\[]{}()<>".contains(left) {
      return left
    }

    let hierarchies: [(String, String)] = [
      ("|", "/\\[]{}()<>"),
      ("/\\", "[]{}()<>"),
      ("[]", "{}()<>"),
      ("{}", "()<>"),
      ("()", "<>"),
    ]
    if smushMode(.hierarchy) {
      for (dominant, recessive) in hierarchies {
        if dominant.contains(left), recessive.contains(right) {
          return right
        }
        if dominant.contains(right), recessive.contains(left) {
          return left
        }
      }
    }

    if smushMode(.pair) {
      let pair = String([left, right])
      let reversePair = String([right, left])
      if ["[]", "{}", "()"].contains(pair) || ["[]", "{}", "()"].contains(reversePair) {
        return "|"
      }
    }

    if smushMode(.bigX) {
      if left == "/", right == "\\" {
        return "|"
      }
      if left == "\\", right == "/" {
        return "Y"
      }
      if left == ">", right == "<" {
        return "X"
      }
    }

    return nil
  }

  private func smushMode(_ mode: SmushMode) -> Bool {
    (font.smushMode & mode.rawValue) != 0
  }

  private enum SmushMode: Int {
    case equal = 1
    case lowLine = 2
    case hierarchy = 4
    case pair = 8
    case bigX = 16
    case hardBlank = 32
    case kern = 64
    case smush = 128
  }
}

private func measureRenderedText(_ text: FigletText) -> FigletSize {
  measureRows(renderedRows(from: text.rawValue))
}

private func renderedRows(from rawValue: String) -> [String] {
  var rows = rawValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  if rows.last == "" {
    rows.removeLast()
  }
  return rows
}

private func measureRows(_ rows: [String]) -> FigletSize {
  FigletSize(
    width: rows.map(\.count).max() ?? 0,
    height: rows.count
  )
}

private func consumeLine(from lines: [String], index: inout Int) throws -> String {
  guard index < lines.count else {
    throw FigletError.invalidFont("unexpected end of font data")
  }
  defer { index += 1 }
  return lines[index]
}

private func consumeGlyph(from lines: [String], index: inout Int, height: Int) throws -> (
  width: Int, rows: [String]
) {
  var rows: [String] = []
  var width = 0
  var endMarker: Character?

  for _ in 0..<height {
    let rawLine = try consumeLine(from: lines, index: &index)
    if endMarker == nil {
      endMarker = rawLine.trimmingTrailingWhitespace().last
    }

    let stripped = stripEndMarker(from: rawLine, marker: endMarker ?? "@")
    rows.append(stripped)
    width = max(width, stripped.count)
  }

  return (width, rows)
}

private func stripEndMarker(from line: String, marker: Character) -> String {
  var characters = Array(line.trimmingTrailingWhitespace())

  if characters.last == marker {
    characters.removeLast()
  }
  if characters.last == marker {
    characters.removeLast()
  }

  return String(characters)
}

#if canImport(WASILibc)
  private let wasiExternalFontAccessError =
    "external font files are unavailable in WASI builds; use FigletFontLibrary or EmbeddedFonts"

  private func fileExists(at path: String) -> Bool {
    false
  }

  private func isDirectory(at path: String) -> Bool {
    false
  }

  private func directoryEntries(at path: String) -> [String] {
    []
  }

  private func readFile(at path: String) throws -> [UInt8] {
    throw FigletError.invalidConfiguration(wasiExternalFontAccessError)
  }

  private func environmentValue(named name: String) -> String? {
    nil
  }
#else
  private func fileExists(at path: String) -> Bool {
    unsafe path.withCString { unsafe access($0, F_OK) == 0 }
  }

  private func isDirectory(at path: String) -> Bool {
    guard let directory = unsafe opendir(path) else {
      return false
    }
    unsafe closedir(directory)
    return true
  }

  private func directoryEntries(at path: String) -> [String] {
    guard let directory = unsafe opendir(path) else {
      return []
    }
    defer { unsafe closedir(directory) }

    var entries: [String] = []
    while let entryPointer = unsafe readdir(directory) {
      let name = unsafe withUnsafePointer(to: &entryPointer.pointee.d_name) { pointer in
        unsafe pointer.withMemoryRebound(
          to: CChar.self, capacity: MemoryLayout.size(ofValue: entryPointer.pointee.d_name)
        ) {
          unsafe String(cString: $0)
        }
      }

      if name != "." && name != ".." {
        entries.append(name)
      }
    }

    return entries
  }

  private func readFile(at path: String) throws -> [UInt8] {
    guard let file = unsafe fopen(path, "rb") else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }
    defer { unsafe fclose(file) }

    guard unsafe fseek(file, 0, SEEK_END) == 0 else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }

    let size = unsafe ftell(file)
    guard size >= 0 else {
      throw FigletError.invalidFont("unable to read font at \(path)")
    }

    unsafe rewind(file)

    var buffer = [UInt8](repeating: 0, count: Int(size))
    let bufferCount = buffer.count
    let bytesRead = unsafe buffer.withUnsafeMutableBytes { bytes in
      unsafe fread(bytes.baseAddress, 1, bufferCount, file)
    }

    return Array(buffer.prefix(bytesRead))
  }

  private func environmentValue(named name: String) -> String? {
    guard let value = unsafe getenv(name) else {
      return nil
    }
    return unsafe String(cString: value)
  }
#endif

private func pathByAppending(_ base: String, _ component: String) -> String {
  if component.hasPrefix("/") {
    return component
  }
  if base.isEmpty || base == "." {
    return component
  }
  if component == ".." {
    return base.deletingLastPathComponent
  }
  if component.hasPrefix("../") {
    return pathByAppending(base.deletingLastPathComponent, String(component.dropFirst(3)))
  }
  if base.hasSuffix("/") {
    return base + component
  }
  return base + "/" + component
}

private func uniquePaths(_ paths: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []

  for path in paths where !path.isEmpty {
    let normalized = path.normalizedPath
    if seen.insert(normalized).inserted {
      result.append(normalized)
    }
  }

  return result
}

extension String {
  fileprivate func sanitizedFontData() -> String {
    var characters: [Character] = []
    let source = Array(self)
    var index = 0

    while index < source.count {
      let character = source[index]

      switch character {
      case "\r":
        if index + 1 < source.count, source[index + 1] == "\n" {
          index += 1
        }
        characters.append("\n")
      case "\u{0085}", "\u{2028}", "\u{2029}":
        characters.append(" ")
      default:
        characters.append(character)
      }

      index += 1
    }

    return String(characters)
  }

  fileprivate func trimmingTrailingWhitespace() -> String {
    var characters = Array(self)
    while let last = characters.last, last == " " || last == "\t" {
      characters.removeLast()
    }
    return String(characters)
  }

  fileprivate func trimmingFigletWhitespace() -> String {
    let characters = Array(self)
    var start = 0
    var end = characters.count

    while start < end, characters[start].isFigletWhitespace {
      start += 1
    }

    while end > start, characters[end - 1].isFigletWhitespace {
      end -= 1
    }

    return String(characters[start..<end])
  }

  fileprivate func replacingCharacter(at index: Int, with replacement: Character) -> String {
    var characters = Array(self)
    guard characters.indices.contains(index) else {
      return self
    }
    characters[index] = replacement
    return String(characters)
  }

  fileprivate func trimmingTrailingWhitespaceAndNewlines() -> String {
    var value = self
    while let last = value.last, last.isFigletWhitespaceOrNewline {
      value.removeLast()
    }
    return value
  }

  fileprivate func replacingCharacters(matching target: Character, with replacement: Character)
    -> String
  {
    String(map { $0 == target ? replacement : $0 })
  }

  fileprivate var lastPathComponentWithoutExtension: String {
    let lastComponent = split(separator: "/").last.map(String.init) ?? self
    guard let dotIndex = lastComponent.lastIndex(of: ".") else {
      return lastComponent
    }
    return String(lastComponent[..<dotIndex])
  }

  fileprivate var deletingLastPathComponent: String {
    guard let slashIndex = lastIndex(of: "/") else {
      return "."
    }
    if slashIndex == startIndex {
      return "/"
    }
    return String(self[..<slashIndex])
  }

  fileprivate var normalizedPath: String {
    let absolute = hasPrefix("/")
    var components: [Substring] = []

    for component in split(separator: "/", omittingEmptySubsequences: true) {
      if component == "." {
        continue
      }
      if component == ".." {
        if !components.isEmpty {
          components.removeLast()
        }
        continue
      }
      components.append(component)
    }

    let joined = components.joined(separator: "/")
    if absolute {
      return "/" + joined
    }
    return joined.isEmpty ? (absolute ? "/" : ".") : joined
  }

  fileprivate var hasSupportedFontExtension: Bool {
    supportedFontExtensions.contains { hasSuffix(".\($0)") }
  }
}

extension Substring {
  fileprivate var containsNonWhitespace: Bool {
    contains { !$0.isFigletWhitespace }
  }
}

extension Character {
  fileprivate var isFigletWhitespace: Bool {
    self == " " || self == "\t"
  }

  fileprivate var isFigletWhitespaceOrNewline: Bool {
    isFigletWhitespace || self == "\n" || self == "\r"
  }
}
