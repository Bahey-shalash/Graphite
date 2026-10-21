/// The symbols a folder can carry, in titled sections as Finder's folder popover lists them.
/// Every name exists on iOS 27 and macOS 27 (`FolderSymbolCatalogTests` checks the Mac's).
enum FolderSymbolCatalog {
    struct Section: Identifiable {
        let title: String
        let symbolNames: [String]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "People", symbolNames: [
            "person.fill", "person.2.fill", "person.3.fill", "figure.walk", "figure.run", "figure.wave",
            "figure.and.child.holdinghands", "figure.mind.and.body", "brain.head.profile", "hand.raised.fill",
            "hand.thumbsup.fill", "hands.clap.fill", "eye.fill", "ear.fill", "mouth.fill", "face.smiling",
            "graduationcap.fill", "person.crop.circle.fill"
        ]),
        Section(title: "Animals & Nature", symbolNames: [
            "pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "fish.fill", "tortoise.fill", "hare.fill",
            "ant.fill", "ladybug.fill", "lizard.fill", "leaf.fill", "tree.fill", "camera.macro", "sun.max.fill",
            "moon.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "flame.fill", "drop.fill",
            "bolt.fill", "mountain.2.fill", "globe.europe.africa.fill"
        ]),
        Section(title: "Food & Drink", symbolNames: [
            "fork.knife", "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "birthday.cake.fill", "carrot.fill",
            "takeoutbag.and.cup.and.straw.fill", "waterbottle.fill", "frying.pan.fill", "popcorn.fill",
            "refrigerator.fill", "cart.fill"
        ]),
        Section(title: "Activity", symbolNames: [
            "sportscourt.fill", "soccerball", "basketball.fill", "football.fill", "tennisball.fill", "baseball.fill",
            "volleyball.fill", "figure.skiing.downhill", "figure.pool.swim", "dumbbell.fill", "trophy.fill", "medal.fill",
            "flag.checkered", "gamecontroller.fill", "music.note", "guitars.fill", "pianokeys", "paintpalette.fill",
            "theatermasks.fill", "puzzlepiece.fill", "dice.fill"
        ]),
        Section(title: "Travel & Places", symbolNames: [
            "airplane", "car.fill", "bus.fill", "tram.fill", "ferry.fill", "sailboat.fill", "bicycle", "house.fill",
            "building.2.fill", "building.columns.fill", "tent.fill", "map.fill", "mappin.and.ellipse", "globe",
            "beach.umbrella.fill", "suitcase.fill", "fuelpump.fill", "signpost.right.fill"
        ]),
        Section(title: "Objects", symbolNames: [
            "book.fill", "books.vertical.fill", "bookmark.fill", "newspaper.fill", "doc.text.fill", "pencil",
            "paintbrush.fill", "ruler.fill", "scissors", "paperclip", "briefcase.fill", "laptopcomputer",
            "desktopcomputer", "ipad", "iphone", "keyboard.fill", "headphones", "camera.fill", "photo.fill", "film.fill",
            "tv.fill", "lightbulb.fill", "lock.fill", "key.fill", "hammer.fill", "wrench.and.screwdriver.fill",
            "gearshape.fill", "flask.fill", "testtube.2", "stethoscope", "pills.fill", "cross.case.fill", "gift.fill",
            "bag.fill", "creditcard.fill", "archivebox.fill", "tray.full.fill", "calendar", "clock.fill",
            "compass.drawing", "atom", "function", "sum", "x.squareroot", "cpu.fill", "memorychip.fill"
        ]),
        Section(title: "Symbols", symbolNames: [
            "heart.fill", "star.fill", "sparkles", "checkmark.circle.fill", "xmark.circle.fill",
            "exclamationmark.triangle.fill", "questionmark.circle.fill", "info.circle.fill", "plus.circle.fill",
            "flag.fill", "tag.fill", "bell.fill", "pin.fill", "location.fill", "link", "paperplane.fill",
            "envelope.fill", "bubble.left.fill", "phone.fill", "icloud.fill", "tray.and.arrow.down.fill", "number",
            "at", "dollarsign.circle.fill", "eurosign.circle.fill", "chart.bar.fill", "chart.pie.fill", "percent",
            "infinity", "seal.fill", "shield.fill", "crown.fill"
        ])
    ]

    /// A symbol's name as VoiceOver reads it, from its SF Symbols name: "books vertical"
    /// for `books.vertical.fill`.
    static func spokenName(of symbolName: String) -> String {
        symbolName.split(separator: ".")
            .filter { part in part != "fill" }
            .joined(separator: " ")
    }
}
