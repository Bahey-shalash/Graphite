import Foundation
import GraphiteCore

/// The welcome tour's screenshots, downloaded the first time the tour needs them rather than
/// carried in the app (`AddOnPack`). iPad and iPhone get the iPad pictures
/// (3142 KB), the Mac its own (1680 KB). The files are `AddOns/WelcomeTour` of the repository at
/// `revision`; `scripts/check-add-on-packs.py` checks that this list matches them.
enum WelcomeTourScreenshotPack {
    static let revision = "d10be4ca83e7dbc2bf74a0aa5528d549f83bd5e7"
    private static let baseAddress = URL(string: "https://raw.githubusercontent.com/Graphite-Note/Graphite/\(revision)/AddOns/WelcomeTour")

    /// The pack this platform uses, or nil if its address could not be formed.
    static var forThisPlatform: AddOnPack? {
        guard let baseAddress else { return nil }
        #if os(macOS)
        return AddOnPack(id: "welcome-tour-screenshots-mac", title: "Welcome Tour Pictures", revision: revision,
                          baseAddress: baseAddress, files: macFiles)
        #else
        return AddOnPack(id: "welcome-tour-screenshots", title: "Welcome Tour Pictures", revision: revision,
                          baseAddress: baseAddress, files: touchFiles)
        #endif
    }

    /// The file of `assetName` in the light or the dark appearance, as this platform names it.
    static func fileName(of assetName: String, isDark: Bool) -> String {
        #if os(macOS)
        "\(assetName)-mac-\(isDark ? "dark" : "light").jpg"
        #else
        "\(assetName)-\(isDark ? "dark" : "light").jpg"
        #endif
    }

    private static let touchFiles: [AddOnFile] = [
        AddOnFile(name: "WelcomeTourBasesGallery-dark.jpg", byteCount: 190769,
                  sha256: "ebd9563413c1cfee8c2206fea63ddc81a6beadf26f7fd357f99fd07c31e0c010"),
        AddOnFile(name: "WelcomeTourBasesGallery-light.jpg", byteCount: 182331,
                  sha256: "d330279c90de6697fe40f6cc557647b7fcd4ee26c750b108b9c74a6cb233511a"),
        AddOnFile(name: "WelcomeTourCorePlugins-dark.jpg", byteCount: 128205,
                  sha256: "0d801662ef105be3fef994fde6e2927dc7634b0daeb87c7d925051a491d45e68"),
        AddOnFile(name: "WelcomeTourCorePlugins-light.jpg", byteCount: 140055,
                  sha256: "2932065257aec793e83aee51a5290501f156f0f8817f8e4bd53bd0b939ba2981"),
        AddOnFile(name: "WelcomeTourDrawingCanvas-dark.jpg", byteCount: 72878,
                  sha256: "2004ab21b98ec3f8b9b1e2449549f78488c35623ab1315f3839571629f889ee6"),
        AddOnFile(name: "WelcomeTourDrawingCanvas-light.jpg", byteCount: 72532,
                  sha256: "64a88c2356d27760fb7d718a36b15ac4968b6455bcd799c25fb5bda39212d1ae"),
        AddOnFile(name: "WelcomeTourDrawingInNote-dark.jpg", byteCount: 112898,
                  sha256: "9d5ebb64a273d1493f8312bec6696445525322b789bf5ca80c237b148644488f"),
        AddOnFile(name: "WelcomeTourDrawingInNote-light.jpg", byteCount: 101978,
                  sha256: "f82640cd144497f626a331625978043a24e38119f473baa5c361225f0fe6946c"),
        AddOnFile(name: "WelcomeTourEmbeddedNote-dark.jpg", byteCount: 134929,
                  sha256: "17a6311e0971b3d89a54e606c2e22bb687b0a2e4c8859819af0305afefd85918"),
        AddOnFile(name: "WelcomeTourEmbeddedNote-light.jpg", byteCount: 130989,
                  sha256: "9bc338ef4871d6731b98ceaecf1bdec3a689be4b9c2c9f10f33b90d80b7196a2"),
        AddOnFile(name: "WelcomeTourEmbeddedPDF-dark.jpg", byteCount: 103785,
                  sha256: "0b476f8d25b3f13ef440a3595e485446be8a2334a4eecc44bdb1cb008e06bbfd"),
        AddOnFile(name: "WelcomeTourEmbeddedPDF-light.jpg", byteCount: 99736,
                  sha256: "1eb57d48422feecde9d2b69d70325f598306631c3237bde423a2fba383d344fe"),
        AddOnFile(name: "WelcomeTourLibrary-dark.jpg", byteCount: 50145,
                  sha256: "b8b251f0348c2ff81b1fa24feb8c15adde61bf120d0576f18e2797265f2d70c0"),
        AddOnFile(name: "WelcomeTourLibrary-light.jpg", byteCount: 49232,
                  sha256: "58f982784a140bc5f3fbd925ecfb1bf612bee69eba3be5127baa45e9d3dbc0e0"),
        AddOnFile(name: "WelcomeTourMarkdown-dark.jpg", byteCount: 117847,
                  sha256: "3510074bbae97f1cca6e184a26c339a4e65b67907ec05b48bf54a9ddba7e0411"),
        AddOnFile(name: "WelcomeTourMarkdown-light.jpg", byteCount: 113710,
                  sha256: "d5df82a5b303c11bd1a441755b406fd38e7cb54888751a4000c659e68a1f894e"),
        AddOnFile(name: "WelcomeTourNewItem-dark.jpg", byteCount: 60127,
                  sha256: "b98c28cad7b8b9338dbf931fa1e56d295f78f23c1b135cccc63cccaebaf93071"),
        AddOnFile(name: "WelcomeTourNewItem-light.jpg", byteCount: 62810,
                  sha256: "d56d5d03768ab50fd45762edbb9150f2b8c062c23381f844987e3aea7362b06a"),
        AddOnFile(name: "WelcomeTourNewNotebook-dark.jpg", byteCount: 79609,
                  sha256: "ce0e4bc39ffb9117927d697b9a258c5ea3eb08211923ea3cdeeef660c738b25f"),
        AddOnFile(name: "WelcomeTourNewNotebook-light.jpg", byteCount: 76508,
                  sha256: "204c0be1e24bfc587e1f94d46228183909299f47c5cfd392ca50e829fc312bd9"),
        AddOnFile(name: "WelcomeTourNote-dark.jpg", byteCount: 127692,
                  sha256: "bf8a4165dd8f5879b3079b2ef5bbc979d3b688594fe7e1f3f49b1ca7d858c81b"),
        AddOnFile(name: "WelcomeTourNote-light.jpg", byteCount: 126845,
                  sha256: "e65d3a6ebe25b6d37df2394517af6d53f18e875f39c1bd03e1ffd420d9120344"),
        AddOnFile(name: "WelcomeTourPDFFixedBar-dark.jpg", byteCount: 123145,
                  sha256: "0e1b158122c271a676f04bf0290ec096085e81b0a6620fe1afcb460be43d96e4"),
        AddOnFile(name: "WelcomeTourPDFFixedBar-light.jpg", byteCount: 121974,
                  sha256: "03b22414c5bed2f7f6c97a5d1eefc4240a6b7e8b3113737d9211d0d6888be526"),
        AddOnFile(name: "WelcomeTourPDFFloatingPalette-dark.jpg", byteCount: 127777,
                  sha256: "e61b6c895e004e495e29c8d6919b9eea5d52d795c016633b4417fa3f48691441"),
        AddOnFile(name: "WelcomeTourPDFFloatingPalette-light.jpg", byteCount: 123200,
                  sha256: "3d08471bf5fc94d171455ffaea115c0a4448769e773af8c255e2b3bf417291d8"),
        AddOnFile(name: "WelcomeTourPencilSettings-dark.jpg", byteCount: 155655,
                  sha256: "e0dcf42f9ab0752bea4a2c511fbba8edc22aa6ac4d5b890f7a0a0347436687cb"),
        AddOnFile(name: "WelcomeTourPencilSettings-light.jpg", byteCount: 155089,
                  sha256: "f7546193cb6bc5338e632bfe2c4ed7b25d6363b53dddfb42fa8bbc6c46b12873")
    ]

    private static let macFiles: [AddOnFile] = [
        AddOnFile(name: "WelcomeTourBasesGallery-mac-dark.jpg", byteCount: 166343,
                  sha256: "f08e360ec39999fa1e2c00973b15cce19175dad713c24312ad62177737295c77"),
        AddOnFile(name: "WelcomeTourBasesGallery-mac-light.jpg", byteCount: 159809,
                  sha256: "04a1ed23a7dcec889e6a6d2d4361ea04bb035d4bea7becde1bd96ba897120036"),
        AddOnFile(name: "WelcomeTourCorePlugins-mac-dark.jpg", byteCount: 131875,
                  sha256: "c9255e7e09c09d3abd022e1c85b91b4ca6dcd6e06eba2e5e118147b4a1971e2c"),
        AddOnFile(name: "WelcomeTourCorePlugins-mac-light.jpg", byteCount: 142657,
                  sha256: "507a3fd86cfc5eed700ab2ab5b64be97f10d1015771a79731777753226b27bee"),
        AddOnFile(name: "WelcomeTourEmbeddedNote-mac-dark.jpg", byteCount: 125892,
                  sha256: "1d6b04153f8dab97d79d535f464eddab3274e485f8d1c3b85507734754c2170d"),
        AddOnFile(name: "WelcomeTourEmbeddedNote-mac-light.jpg", byteCount: 134719,
                  sha256: "efd87335d7ec494848e22951e7e3395b6d36005caf059584e705c4e86e1bb3d2"),
        AddOnFile(name: "WelcomeTourEmbeddedPDF-mac-dark.jpg", byteCount: 113132,
                  sha256: "ef9268298c3b933751a3db9fcf860018ad9c7df383db8094d6f4efa4e0e2b8c4"),
        AddOnFile(name: "WelcomeTourEmbeddedPDF-mac-light.jpg", byteCount: 108431,
                  sha256: "844f08bcaf0986d45aab41e41ce66ca8241e4c9d52715f5a563f95bd4b2999a7"),
        AddOnFile(name: "WelcomeTourLibrary-mac-dark.jpg", byteCount: 52491,
                  sha256: "5e58ed9908348e3373a03beeda200c4c41f1678251c80e8701d63e06c2bdbc28"),
        AddOnFile(name: "WelcomeTourLibrary-mac-light.jpg", byteCount: 53067,
                  sha256: "0d890f2836a1e0543915f2135fb2e35b952e1d649a4a94466678ffe8642b2813"),
        AddOnFile(name: "WelcomeTourMarkdown-mac-dark.jpg", byteCount: 123983,
                  sha256: "b46031dee4e4f3fa521092a846f56f49bd0b7dd84344ce59f2282c75676b267a"),
        AddOnFile(name: "WelcomeTourMarkdown-mac-light.jpg", byteCount: 126757,
                  sha256: "4e579ffc0e406607a89cfd93c28f6b92e25f5d255f6f13dd87d9c47204041d34"),
        AddOnFile(name: "WelcomeTourNote-mac-dark.jpg", byteCount: 119313,
                  sha256: "8de8aa54e7dee719c6832a65ee584673ab0adfd22e938de388d657e0b93c7304"),
        AddOnFile(name: "WelcomeTourNote-mac-light.jpg", byteCount: 121734,
                  sha256: "697adaf56cce2565572620d1d568a6c366b12216878e1a7993719e74323a5f75")
    ]
}
