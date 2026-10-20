import Foundation

// The body layouts of the page elements (`Docs/Goodnotes-format.md`, "Page elements"). A case named `unknownField…`
// is a field the samples carry and the format notes do not explain: it is accepted without a report and never read.

/// The header record that precedes each element's body in a layer file.
enum GoodnotesElementHeaderField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    case versionClock = 2
    /// 1 when the element was deleted; an erased stroke stays in the file.
    case isDeleted = 3
    /// The attachment of a picture.
    case attachment = 4
    /// The identifier the layer's member list uses when the element has one.
    case orderIdentifier = 6
    /// A second identifier; its meaning is not known.
    case secondIdentifier = 7
    case replica = 8
    case counter = 9
    /// 1 on the one text element of kind 12.
    case isTextElement = 10
    /// Always 5381 in the samples; its meaning is not known.
    case unknownField14 = 14
    case schema = 16
}

/// The field every element body starts with, whatever its kind, even a kind this reader does not know.
enum GoodnotesElementBodyField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
}

/// A stroke, body field 7.
enum GoodnotesStrokeField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    /// The path: LZ4, then tpl, in one of four layouts.
    case path = 2
    /// Absent for ball pen and highlighter; 1 fountain pen, brush pen and tape; 4 older varying width; 5 pencil.
    case ink = 3
    case color = 4
    /// 1 for the highlighter.
    case isHighlighter = 5
    /// The offset added to every point: a lasso move.
    case offset = 6
    case drawingPosition = 7
    /// The shape, when the stroke was drawn as one.
    case shape = 9
    /// A group identifier, the same on every stroke of a saved drawing put on the page.
    case groupIdentifier = 10
    /// 1 when erased; the path is then empty.
    case isErased = 14
    case versionClock = 15
    /// `{1: ""}` on tape, empty otherwise.
    case tape = 20
    case schema = 21
}

/// A shape inside a stroke (stroke field 9): the first geometry present in field order, a line style and a width.
enum GoodnotesShapeField: Int, GoodnotesFieldNumber {
    case polyline = 1
    case arcThroughThreePoints = 2
    case rectangle = 3
    case ellipse = 4
    /// The dash pattern and a flag; not read.
    case lineStyle = 5
    case width = 15
}

/// A picture, body field 1.
enum GoodnotesPictureField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    /// The bounding box of the picture as drawn.
    case boundingBox = 2
    /// The placement: centre, size before turning, angle.
    case placement = 3
    case attachment = 4
    case drawingPosition = 5
    /// 2 a JPEG 2000 sticker, 5 an animated GIF, 1 on the turned picture; absent on photos.
    case kind = 6
    /// An identifier found among no attachment; not read.
    case unmatchedIdentifier = 7
    case isDeleted = 14
    /// Accepted by the reference reader; the format notes do not describe it for pictures.
    case versionClock = 15
    case unknownField18 = 18
}

/// A shape's fill, body field 9.
enum GoodnotesShapeFillField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    /// NaN when erased; not read.
    case boundingBox = 2
    case drawingPosition = 3
    /// The geometry, as in a shape.
    case geometry = 4
    /// The outline stroke's identifier, repeated when the fill belongs to several.
    case outlineStrokeIdentifier = 5
    case offset = 6
    case color = 7
    case isErased = 14
    /// Accepted by the reference reader; the format notes do not describe it for fills.
    case versionClock = 15
    case unknownField18 = 18
}

/// An older text box with its text as RTF, body field 8.
enum GoodnotesRTFTextBoxField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    case frame = 2
    /// The box inset by 10 on each side.
    case textFrame = 3
    case unknownField4 = 4
    case drawingPosition = 5
    /// The only copy of the text, as Cocoa RTF.
    case rtf = 6
    case firstColor = 7
    case secondColor = 9
    case inset = 10
    case isDeleted = 14
    /// Accepted by the reference reader; the format notes do not describe it for older text boxes.
    case versionClock = 15
    case shadowFirstField = 18
    case shadowSecondField = 19
    case unknownField20 = 20
    case unknownField21 = 21
    case unknownField27 = 27
}

/// The text element in RTF with no frame, body field 12; one sample, empty and bold.
enum GoodnotesRTFTextElementField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    case unknownField2 = 2
    case rtf = 3
    case drawingPosition = 13
    case versionClock = 15
    case unknownField25 = 25
    case unknownField26 = 26
    case unknownField27 = 27
    case unknownField28 = 28
}

/// A sticky note, body field 20.
enum GoodnotesStickyNoteField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    case unknownField2 = 2
    case versionClock = 3
    case drawingPosition = 7
    /// `{1: origin}`.
    case placement = 20
    /// `{2: {1: width, 2: height}}`.
    case dimensions = 21
    case paperColor = 30
    /// The rich text, as in a text box.
    case richTextLayout = 31
    case authorAccountIdentifier = 32
    case authorName = 33
    case unknownField40 = 40
    case unknownField41 = 41
}

/// A text box of schema 35, body field 21.
enum GoodnotesTextBoxField: Int, GoodnotesFieldNumber {
    case elementIdentifier = 1
    case unknownField2 = 2
    case versionClock = 3
    case drawingPosition = 7
    case unknownField9 = 9
    /// `{1: origin, 2: angle in radians, 3: scale}`.
    case placement = 20
    /// Probably the minimum and maximum width and height; not read.
    case sizeLimits = 21
    case unknownField22 = 22
    case backgroundColor = 30
    case borderColor = 31
    /// The layout and text: the content, the size, the default attributes and the insets.
    case layoutAndText = 32
    case shadow = 33
}
