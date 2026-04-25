import Foundation
import EmbeddedFonts
import SwiftFiglet
import Testing

private let repositoryRoot =
  "/" + #filePath.split(separator: "/").dropLast(3).joined(separator: "/")
private let testDirectory = "/" + #filePath.split(separator: "/").dropLast().joined(separator: "/")
private let bundledFontsDirectory = repositoryRoot + "/Sources/swift-figlet/Resources/Fonts"
private let fontsDirectory = repositoryRoot + "/Fonts"
private let testOnlyFontData = #"""
  flf2a$ 1 1 1 0 0
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  0@@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  @@
  """# + "\n"
private let asciiTheDrawOutput = #"""
         _
  __ _  | |___    ___
 / _  | | `_  \  / __|
| (_) | | (_) | | (__
 \__,_| |_,___/  \___|
"""#

@Test func loadsExternalFontFiles() throws {
  let font = try FigletFont(filePath: testDirectory + "/Fixtures/TestOnly.flf")
  let figlet = Figlet(font: font)
  let output = try figlet.render("0").strippingSurroundingNewlines()

  #expect(output == "0")
}

@Test func loadsExternalTheDrawFontFiles() throws {
  let figlet = try Figlet(fontNamed: "ascii", searchDirectories: [fontsDirectory])
  let output = try figlet.render("ABC").trimmingTrailingWhitespaceByLine()

  #expect(output == asciiTheDrawOutput)
}

@Test func preservesTheDrawColorAttributesAsANSI() throws {
  let figlet = try Figlet(fontNamed: "208", searchDirectories: [fontsDirectory])
  let rendered = try figlet.render("x")
  let ansiOutput = rendered.ansiDescription

  #expect(rendered.containsANSIStyles)
  #expect(ansiOutput.contains("\u{001B}[31;40m"))
  #expect(ansiOutput.contains("\u{001B}[91;41m"))
  #expect(ansiOutput.strippingANSISequences() == rendered.description)
}

@Test func rendersPublicSurfaceEquivalentToFigletText() throws {
  let figlet = try Figlet(embeddedFont: .standard)
  let text = try figlet.render("Hi")
  let surface = try figlet.renderSurface("Hi")

  #expect(surface.render() == text.description)
  #expect(surface.description == text.description)
  #expect(surface.size == .init(width: 9, height: 6))
  #expect(!surface.containsStyles)
  #expect(surface.rows.count == 6)
}

@Test func appliesSurfaceStyleFiltersWithoutChangingGlyphs() throws {
  let figlet = try Figlet(embeddedFont: .standard)
  let surface = try figlet.renderSurface("Hi")
  let styled = surface.applying(.fillStyle(.init(foreground: .green)))
  let ansiOutput = styled.render(.ansi)

  #expect(styled.render() == surface.render())
  #expect(styled.containsStyles)
  #expect(ansiOutput.contains("\u{001B}[32m"))
  #expect(ansiOutput.strippingANSISequences() == surface.render())

  let stripped = styled.applying(.stripStyles)
  #expect(!stripped.containsStyles)
  #expect(stripped.render(.ansi) == surface.render())
}

@Test func surfaceFiltersCanOverrideTheDrawAuthoredStyles() throws {
  let figlet = try Figlet(fontNamed: "208", searchDirectories: [fontsDirectory])
  let surface = try figlet.renderSurface("x")
  let overridden = surface
    .applying(.stripStyles)
    .applying(.overrideStyle(.init(foreground: .cyan)))
  let ansiOutput = overridden.render(.ansi)

  #expect(surface.containsStyles)
  #expect(overridden.render() == surface.render())
  #expect(ansiOutput.contains("\u{001B}[36m"))
  #expect(!ansiOutput.contains("\u{001B}[31;40m"))
  #expect(ansiOutput.strippingANSISequences() == surface.render())
}

@Test func loadsFontsFromFontLibraryObjects() throws {
  let fontLibrary = FigletFontLibrary(
    name: "Test Fixtures",
    fontData: ["TestOnly": testOnlyFontData]
  )

  let figlet = try Figlet(fontNamed: "TestOnly", fontLibrary: fontLibrary)
  let output = try figlet.render("0").strippingSurroundingNewlines()

  #expect(output == "0")
}

@Test func loadsTheDrawFontsFromFontLibraryObjects() throws {
  let fontData = try Data(contentsOf: URL(fileURLWithPath: fontsDirectory + "/ascii.tdf"))
  let fontLibrary = FigletFontLibrary(
    name: "TheDraw Fixtures",
    fonts: ["ascii.tdf": Array(fontData)]
  )

  let figlet = try Figlet(fontNamed: "ascii.tdf", fontLibrary: fontLibrary)
  let output = try figlet.render("ABC").trimmingTrailingWhitespaceByLine()

  #expect(figlet.font.info == "ASCII")
  #expect(output == asciiTheDrawOutput)
}

@Test func rendersEmbeddedStandardFontLibrary() throws {
  let figlet = try Figlet(embeddedFont: .standard)
  let output = try figlet.render("Hi").description

  #expect(output == " _   _ _ \n| | | (_)\n| |_| | |\n|  _  | |\n|_| |_|_|\n         \n")
}

@Test func rendersEmbeddedTheDrawFontLibrary() throws {
  let figlet = try Figlet(embeddedFont: .font208)
  let rendered = try figlet.render("x")

  #expect(figlet.font.info == "208")
  #expect(rendered.containsANSIStyles)
  #expect(rendered.ansiDescription.strippingANSISequences() == rendered.description)
}

@Test func rendersCuratedEmbeddedTheDrawFonts() throws {
  for embeddedFont in [EmbeddedFigletFont.font208, .bloodyx, .cnerip] {
    let figlet = try Figlet(embeddedFont: embeddedFont)
    let rendered = try figlet.render("x")

    #expect(rendered.containsANSIStyles)
    #expect(!rendered.description.isEmpty)
  }
}

@Test func reportsLayoutMetricsForEmbeddedFonts() throws {
  let figlet = try Figlet(embeddedFont: .standard)
  let metrics = try figlet.layoutMetrics(for: "Hi")

  #expect(metrics.minimumWidth == 8)
  #expect(metrics.idealSize == .init(width: 9, height: 6))
}

@Test func measuresRenderedSizeAtConcreteWidths() throws {
  let figlet = try Figlet(embeddedFont: .standard)

  #expect(try figlet.measure("Hi", forWidth: 80) == .init(width: 9, height: 6))
  #expect(try figlet.measure("Hi", forWidth: 8) == .init(width: 7, height: 12))
  #expect(try figlet.measure("hello world", forWidth: 20) == .init(width: 20, height: 24))
}

@Test func listsEmbeddedFonts() {
  #expect(
    EmbeddedFigletFont.allCases.map(\.rawValue) == [
      "208",
      "3d",
      "ansi-shadow",
      "bloodyx",
      "calvin-sm",
      "cnerip",
      "doom",
      "pagga",
      "slant",
      "sm-block",
      "small",
      "standard",
    ])
}

@Test func embeddedFontEnumMatchesTheGeneratedLibrary() {
  #expect(
    EmbeddedFigletFont.allCases.map(\.rawValue) == EmbeddedFigletFont.library.fontNames)
}

extension FigletText {
  fileprivate func trimmingTrailingWhitespaceByLine() -> String {
    rawValue
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0).trimmingTrailingFigletWhitespace() }
      .joined(separator: "\n")
      .trimmingTrailingFigletWhitespaceAndNewlines()
  }
}

extension String {
  fileprivate func trimmingTrailingFigletWhitespace() -> String {
    var value = self
    while let last = value.last, last == " " || last == "\t" {
      value.removeLast()
    }
    return value
  }

  fileprivate func trimmingTrailingFigletWhitespaceAndNewlines() -> String {
    var value = self
    while let last = value.last, last == " " || last == "\t" || last == "\n" || last == "\r" {
      value.removeLast()
    }
    return value
  }

  fileprivate func strippingANSISequences() -> String {
    var output = ""
    var iterator = makeIterator()

    while let character = iterator.next() {
      guard character == "\u{001B}" else {
        output.append(character)
        continue
      }

      guard iterator.next() == "[" else {
        continue
      }

      while let escapeCharacter = iterator.next(), escapeCharacter != "m" {}
    }

    return output
  }
}
