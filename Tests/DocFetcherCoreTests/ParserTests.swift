import XCTest
@testable import DocFetcherCore

final class ParserTests: TempDirTestCase {
    let registry = ParserRegistry()

    func testTextEncodings() throws {
        let latin = dir.appendingPathComponent("l.txt")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: latin)
        XCTAssertEqual(try registry.parse(url: latin).text, "café")
        let utf16 = dir.appendingPathComponent("u.txt")
        try "héllo".data(using: .utf16)!.write(to: utf16)
        XCTAssertEqual(try registry.parse(url: utf16).text, "héllo")
    }

    func testHTML() throws {
        let url = try write("p.html", """
            <html><head><title>My &amp; Title</title><meta name="author" content="Ann"><style>p{}</style></head>
            <body><h1>Heading</h1><script>var x=1;</script><p>Para&nbsp;one &#233; &lt;b&gt;</p></body></html>
            """)
        let p = try registry.parse(url: url)
        XCTAssertEqual(p.metadata.title, "My & Title")
        XCTAssertEqual(p.metadata.author, "Ann")
        XCTAssertTrue(p.text.contains("Heading"))
        XCTAssertTrue(p.text.contains("Para one é <b>"))
        XCTAssertFalse(p.text.contains("var x"))
        XCTAssertFalse(p.text.contains("p{}"))
    }

    func testRTF() throws {
        let url = try write("a.rtf", #"{\rtf1\ansi{\fonttbl{\f0 Arial;}}{\*\generator Foo;}\f0 Hello \b world\b0\par Caf\'e9 \u8364? done}"#)
        let t = try registry.parse(url: url).text
        XCTAssertTrue(t.contains("Hello world"), t)
        XCTAssertTrue(t.contains("Café"), t)
        XCTAssertTrue(t.contains("€ done"), t)
        XCTAssertFalse(t.contains("Arial"))
        XCTAssertFalse(t.contains("Foo"))
    }

    func testDOCX() throws {
        let url = try zip("a.docx", files: [
            "word/document.xml": #"<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>First paragraph</w:t></w:r></w:p><w:p><w:r><w:t>Second</w:t></w:r></w:p></w:body></w:document>"#,
            "docProps/core.xml": #"<cp:coreProperties xmlns:cp="a" xmlns:dc="b" xmlns:dcterms="c"><dc:title>Doc Title</dc:title><dc:creator>Bob</dc:creator><dcterms:created>2020-05-01T10:00:00Z</dcterms:created></cp:coreProperties>"#,
        ])
        let p = try registry.parse(url: url)
        XCTAssertEqual(p.text, "First paragraph\nSecond")
        XCTAssertEqual(p.metadata.title, "Doc Title")
        XCTAssertEqual(p.metadata.author, "Bob")
        XCTAssertNotNil(p.metadata.created)
    }

    func testXLSXAndPPTX() throws {
        let x = try zip("a.xlsx", files: ["xl/sharedStrings.xml": "<sst><si><t>Revenue</t></si><si><t>Costs</t></si></sst>",
                                           "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row><c><v>0</v></c></row></sheetData></worksheet>"])
        XCTAssertEqual(try registry.parse(url: x).text, "Revenue\nCosts")
        let p = try zip("a.pptx", files: ["ppt/slides/slide2.xml": "<p:sld><a:p><a:t>Two</a:t></a:p></p:sld>",
                                           "ppt/slides/slide10.xml": "<p:sld><a:p><a:t>Ten</a:t></a:p></p:sld>",
                                           "ppt/slides/slide1.xml": "<p:sld><a:p><a:t>One</a:t></a:p></p:sld>"])
        let parsed = try registry.parse(url: p)
        XCTAssertEqual(parsed.text, "One\nTwo\nTen")
        XCTAssertEqual(parsed.metadata.pageCount, 3)
    }

    func testODT() throws {
        let url = try zip("a.odt", files: [
            "content.xml": #"<office:document-content xmlns:office="o" xmlns:text="t"><office:body><office:text><text:h>Title here</text:h><text:p>Body <text:span>styled</text:span> text</text:p></office:text></office:body></office:document-content>"#,
            "meta.xml": #"<office:document-meta xmlns:office="o" xmlns:dc="d" xmlns:meta="m"><office:meta><dc:title>ODT Title</dc:title><meta:initial-creator>Cy</meta:initial-creator></office:meta></office:document-meta>"#,
        ])
        let p = try registry.parse(url: url)
        XCTAssertEqual(p.text, "Title here\nBody styled text")
        XCTAssertEqual(p.metadata.title, "ODT Title")
        XCTAssertEqual(p.metadata.author, "Cy")
    }

    func testEPUBAndSVG() throws {
        let e = try zip("b.epub", files: ["OEBPS/content.opf": "<package><metadata><dc:title>Book</dc:title><dc:creator>Dee</dc:creator></metadata></package>",
                                          "OEBPS/ch1.xhtml": "<html><body><p>Chapter one text</p></body></html>"])
        let p = try registry.parse(url: e)
        XCTAssertEqual(p.metadata.title, "Book")
        XCTAssertTrue(p.text.contains("Chapter one text"))
        let s = try write("a.svg", #"<svg xmlns="http://www.w3.org/2000/svg"><title>Logo</title><text>Hello <tspan>SVG</tspan></text></svg>"#)
        XCTAssertTrue(try registry.parse(url: s).text.contains("Hello SVG"))
    }

    func testArchives() throws {
        let z = try zip("a.zip", files: ["inner/doc.txt": "zipped needle", "inner/skip.bin": "ignored"])
        XCTAssertTrue(try registry.parse(url: z).text.contains("zipped needle"))

        try write("tarsrc/t.txt", "tarred needle")
        let tar = dir.appendingPathComponent("a.tar.gz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["tar", "-czf", tar.path, "-C", dir.appendingPathComponent("tarsrc").path, "t.txt"]
        try p.run(); p.waitUntilExit()
        XCTAssertTrue(try registry.parse(url: tar).text.contains("tarred needle"))

        let gz = dir.appendingPathComponent("note.txt.gz")
        let g = Process()
        g.executableURL = URL(fileURLWithPath: "/bin/sh")
        g.arguments = ["-c", "echo 'gzipped needle' | gzip -c > '\(gz.path)'"]
        try g.run(); g.waitUntilExit()
        XCTAssertTrue(try registry.parse(url: gz).text.contains("gzipped needle"))
    }

    func testCorruptedInputsThrow() throws {
        for name in ["x.docx", "x.xlsx", "x.odt", "x.epub", "x.zip", "x.doc", "x.rtf", "x.mp3", "x.flac"] {
            let u = try write(name, "garbage that is not a valid file")
            XCTAssertThrowsError(try registry.parse(url: u), name)
        }
    }

    func testLegacyOfficeStrings() throws {
        var d = Data([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0, 1, 2, 3])
        d.append(Data("legacy visible text".utf8))
        d.append(contentsOf: [0, 1])
        d.append(Data("wide".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } + "string".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))
        let u = dir.appendingPathComponent("x.xls")
        try d.write(to: u)
        let t = try registry.parse(url: u).text
        XCTAssertTrue(t.contains("legacy visible text"))
        XCTAssertTrue(t.contains("widestring"))
    }

    func testID3AndFLAC() {
        func frame(_ id: String, _ text: String) -> [UInt8] {
            let body: [UInt8] = [0] + Array(text.utf8)
            return Array(id.utf8) + [0, 0, 0, UInt8(body.count), 0, 0] + body
        }
        let frames = frame("TIT2", "Song") + frame("TPE1", "Artist")
        let header: [UInt8] = Array("ID3".utf8) + [3, 0, 0, 0, 0, 0, UInt8(frames.count)]
        let tags = MediaMetadataParser.id3Tags(header + frames)
        XCTAssertEqual(tags["title"], "Song")
        XCTAssertEqual(tags["artist"], "Artist")

        func le32(_ n: Int) -> [UInt8] { [UInt8(n & 255), UInt8((n >> 8) & 255), 0, 0] }
        let vendor = Array("v".utf8)
        let c1 = Array("TITLE=Flac Song".utf8)
        let block = le32(vendor.count) + vendor + le32(1) + le32(c1.count) + c1
        let flac: [UInt8] = Array("fLaC".utf8) + [0x84, 0, UInt8(block.count >> 8), UInt8(block.count & 255)] + block
        XCTAssertEqual(MediaMetadataParser.flacTags(flac)["title"], "Flac Song")
    }

    func testMIMEDetection() throws {
        let u = dir.appendingPathComponent("noext")
        try Data("%PDF-1.4".utf8).write(to: u)
        XCTAssertEqual(MIMETypeDetector.detect(url: u), "application/pdf")
        let d = try zip("a.docx", files: ["word/document.xml": "<a/>"])
        XCTAssertTrue(MIMETypeDetector.detect(url: d).contains("wordprocessingml"))
    }

    func testRegistryCoversRequiredFormats() {
        let exts = registry.supportedExtensions
        for e in ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "odg", "pdf", "rtf", "html", "txt",
                  "svg", "epub", "chm", "mp3", "flac", "jpg", "zip", "tar", "gz"] {
            XCTAssertTrue(exts.contains(e), e)
        }
    }

    func testScannedPDFDetection() {
        XCTAssertTrue(PDFParser.looksScanned(pageTexts: ["", " \n", "x"]))
        XCTAssertFalse(PDFParser.looksScanned(pageTexts: [String(repeating: "word ", count: 50)]))
    }
}
