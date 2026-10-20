import CoreGraphics
import CryptoKit
import XCTest
import GraphiteCore
@testable import GraphiteApple

/// Pins the page content `PDFTemplateGenerator` draws for every paper template, at every size and orientation the New
/// Notebook sheet offers, in the default colours and two others: a change to the paper system must leave these bytes
/// as they are. Each digest covers, for every size, the page's media box, its decoded content stream and the decoded
/// streams of its resources (the dot pattern's cell).
final class PDFTemplateGeneratorGoldenTests: XCTestCase {
    private struct ColorVariant {
        let name: String
        let paperColorHex: String?
        let lineColor: DrawingPaperLineColor
        let lineStrength: DrawingPaperLineStrength
    }

    private static let variants = [
        ColorVariant(name: "default", paperColorHex: nil, lineColor: .gray, lineStrength: .standard),
        ColorVariant(name: "blue strong on cream", paperColorHex: "#FFF8E7", lineColor: .blue, lineStrength: .strong),
        ColorVariant(name: "red light", paperColorHex: nil, lineColor: .red, lineStrength: .light),
    ]

    /// SHA-256 of each template and colour variant over every New Notebook size, recorded from the paper system before
    /// the optional ruling fields were added.
    private static let expectedDigests: [String: String] = [
        "blank blue strong on cream": "d6f92868ca8674c57e96118ce9f23a328c56e2ac534fd3a5705240506aa16505",
        "blank default": "b3ecc05f1a77e2ed8f6613be2ec6ac6f4b3a695476e71026045071cdd24cee39",
        "blank red light": "b3ecc05f1a77e2ed8f6613be2ec6ac6f4b3a695476e71026045071cdd24cee39",
        "cornell blue strong on cream": "3ee558bb57b12f02375def73de6a65f79f8ba1081d0d587df368f125f3667c49",
        "cornell default": "c4cc28619444f0a7e3bf5fa7018f43cac40c071bdb73442b3c0a95ad172d0ed3",
        "cornell red light": "6ed07863ee82750e4e4e5b6ad3f133018d2830ed3239918468fb7cf0a18fa95e",
        "dotted blue strong on cream": "4d8e4e1bbeb8ea07d245ccdb92b06ccb5cf2f7f3433869324c30397d5b2b9110",
        "dotted default": "b8a58eab50db41a3b86dddcd772b2923987278afad93a5f19d4d677e448938f6",
        "dotted red light": "1dd8cd55b39b94674b548d5b8f50c7f3decbaee0f8472a05b6eb9d5fbbf7ae61",
        "engineering blue strong on cream": "4378f6d8fa8773b5f8061d53f98bc209c07487ef2deb1c0dd3bd57426b8d270d",
        "engineering default": "9610ff00528fd5bf2d0b322b58168fd8e3c3fc3f67d000d6bd39e3f9a763bcd3",
        "engineering red light": "81bfdc66e4cd6b5c8d9c898e7b64507d9e7fb34cee7eb7f8fedfdcb41cf24b9b",
        "grid blue strong on cream": "54210806d15cfee312c2d113a80034d6cb6dcc4d22faa010858245737cee3db5",
        "grid default": "05e5857cb692cc9e1ae474ed16a0ccb482237f5da1e2f8e0a49da60fd224c968",
        "grid red light": "aa3098f5d1e1ec0d797a133f23e543b91337ba05c6e6573af8bf0e560b86c226",
        "isometric blue strong on cream": "bca8c7b444613f31e7a6882758da989298f6829ccfe68f074a8f4274ac4cfafc",
        "isometric default": "f7be61da55b39ebaf4d4b255ef1b2f49c1ec8592368d9cad52d149183fb585c4",
        "isometric red light": "d6bef5a05928781ca0361a4d735fdc4cb0eb88ae9fc7be00f0677aeaf082437a",
        "music blue strong on cream": "d9a37717fb5406cc0b5158d9cbde7ee56f57cee0609fa5721d792b36b9fd8a77",
        "music default": "01c8402767a1cb2b5d52f3e5490f3e5041184789de35649930d7c7885df6227c",
        "music red light": "07ccc5376265a4ac555bfa454e42114f90a9cbad83f86a5a03ed128dbd5412f4",
        "ruled blue strong on cream": "30c2512924cde105ce7641245a5c4eb3d0f4bd544ed68cb0ceb27f10d511870b",
        "ruled default": "cf2eab5c1f1e47113b2bd4c64093cbec6a8874f876f3f7bd76ead99856ea0870",
        "ruled red light": "483ee95631e190043fdde2baf2ea1b449bf64f407e7ab1a82514ca5c46b48796",
    ]

    func testEveryTemplateDrawsTheSamePageContentAtEveryNotebookSize() throws {
        var digests: [String: String] = [:]
        for template in PaperTemplate.allCases {
            for variant in Self.variants {
                var hash = SHA256()
                for pageSize in NotebookPageSize.allCases {
                    for orientation in PageOrientation.allCases {
                        let size = pageSize.pointSize(in: orientation)
                        let paper = PaperSpecification(template: template, width: size.width, height: size.height,
                                                       spacing: PaperSpecification.standardSpacing, paperColorHex: variant.paperColorHex,
                                                       lineColor: variant.lineColor, lineStrength: variant.lineStrength)
                        hash.update(data: try Self.pageContent(of: PDFTemplateGenerator.documentData(paper: paper)))
                    }
                }
                digests["\(template.rawValue) \(variant.name)"] = hash.finalize().map { byte in String(format: "%02x", byte) }.joined()
            }
        }
        XCTAssertEqual(digests, Self.expectedDigests)
    }

    /// The first page's media box, decoded content stream and decoded resource streams, in a fixed order.
    private static func pageContent(of documentData: Data) throws -> Data {
        let provider = try XCTUnwrap(CGDataProvider(data: documentData as CFData))
        let page = try XCTUnwrap(CGPDFDocument(provider)?.page(at: 1))
        var content = Data("\(page.getBoxRect(.mediaBox))".utf8)
        let pageDictionary = try XCTUnwrap(page.dictionary)
        var contentStream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(pageDictionary, "Contents", &contentStream), let contentStream {
            content.append(streamData(contentStream))
        }
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources {
            for category in ["Pattern", "XObject"] {
                var entries: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(resources, category, &entries), let entries else { continue }
                content.append(streams(in: entries))
            }
        }
        return content
    }

    private static func streams(in dictionary: CGPDFDictionaryRef) -> Data {
        final class Collected { var streamsByKey: [String: Data] = [:] }
        let collected = Collected()
        CGPDFDictionaryApplyBlock(dictionary, { key, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream { collected.streamsByKey[String(cString: key)] = streamData(stream) }
            return true
        }, nil)
        return collected.streamsByKey.keys.sorted().reduce(into: Data()) { data, key in data.append(collected.streamsByKey[key] ?? Data()) }
    }

    private static func streamData(_ stream: CGPDFStreamRef) -> Data {
        var format = CGPDFDataFormat.raw
        return (CGPDFStreamCopyData(stream, &format) as Data?) ?? Data()
    }
}
