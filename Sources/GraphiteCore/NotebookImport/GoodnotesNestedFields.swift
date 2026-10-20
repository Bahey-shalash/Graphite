import Foundation

// The layouts nested inside element bodies and records.

/// `{1: x, 2: y}`, also a width and height.
enum GoodnotesPointField: Int, GoodnotesFieldNumber {
    case horizontal = 1
    case vertical = 2
}

/// `{1: origin, 2: size}`.
enum GoodnotesRectangleField: Int, GoodnotesFieldNumber {
    case origin = 1
    case size = 2
}

/// `{1: red, 2: green, 3: blue, 4: alpha}`, each 0 to 1.
enum GoodnotesColorField: Int, GoodnotesFieldNumber {
    case red = 1
    case green = 2
    case blue = 3
    case alpha = 4
}

/// A version clock, `{1: counter, 2: replica}`.
enum GoodnotesClockField: Int, GoodnotesFieldNumber {
    case counter = 1
    case replica = 2
}

/// A last-writer-wins register, `{1: value, 2: clock}`.
enum GoodnotesRegisterField: Int, GoodnotesFieldNumber {
    case value = 1
    case clock = 2
}

/// A polyline, `{1: point, 1: point, …}`.
enum GoodnotesPolylineField: Int, GoodnotesFieldNumber {
    case point = 1
}

/// An arc of a circle from the first point through the second to the third.
enum GoodnotesArcField: Int, GoodnotesFieldNumber {
    case start = 1
    case middle = 2
    case end = 3
}

/// A shape's rectangle, `{1: center, 2: width and height, 3: angle in radians}`.
enum GoodnotesShapeRectangleField: Int, GoodnotesFieldNumber {
    case center = 1
    case size = 2
    case angleRadians = 3
}

/// A shape's ellipse, `{1: center, 2: radii, 3: angle in radians}`.
enum GoodnotesShapeEllipseField: Int, GoodnotesFieldNumber {
    case center = 1
    case radii = 2
    case angleRadians = 3
}

/// A picture's placement, `{1: center, 2: size before turning, 3: angle in radians}`.
enum GoodnotesPicturePlacementField: Int, GoodnotesFieldNumber {
    case center = 1
    case sizeBeforeTurning = 2
    case rotationRadians = 3
}

/// A text box's placement; the angle is absent when 0 and the scale when 1.
enum GoodnotesTextBoxPlacementField: Int, GoodnotesFieldNumber {
    case origin = 1
    case rotationRadians = 2
    case scale = 3
}

/// A sticky note's placement, `{1: origin}`.
enum GoodnotesStickyNotePlacementField: Int, GoodnotesFieldNumber {
    case origin = 1
}

/// A sticky note's dimensions, `{2: {1: width, 2: height}}`.
enum GoodnotesStickyNoteDimensionsField: Int, GoodnotesFieldNumber {
    case size = 2
}

/// The layout and text of a text box or sticky note: `{1: content, 2: size, 5: defaults, 10: insets}`.
enum GoodnotesTextLayoutField: Int, GoodnotesFieldNumber {
    case content = 1
    case size = 2
    case defaults = 5
    case insets = 10
}

/// The content of a text layout, `{2: rich text (LZ4), 3: hash}`.
enum GoodnotesTextContentField: Int, GoodnotesFieldNumber {
    case compressedRichText = 2
    case hash = 3
}

/// The default attributes of a text layout, `{1: attributes, 2: paragraph}`.
enum GoodnotesTextDefaultsField: Int, GoodnotesFieldNumber {
    case attributes = 1
    case paragraph = 2
}

/// A decompressed rich text, `{1: body}`.
enum GoodnotesRichTextFileField: Int, GoodnotesFieldNumber {
    case body = 1
}

/// The body of a decompressed rich text, `{1: text, 2: attributes, 3: paragraph}`.
enum GoodnotesRichTextBodyField: Int, GoodnotesFieldNumber {
    case text = 1
    case attributes = 2
    case paragraph = 3
}

/// Text attributes, shared by a run and the defaults. A size of −404 means "not set, use the default".
enum GoodnotesTextAttributeField: Int, GoodnotesFieldNumber {
    case color = 3
    case link = 4
    case fontName = 30
    case sizeInUnits = 40
}

/// The insets of a text box, in the order `GoodnotesTextBox.insets` holds them.
enum GoodnotesInsetField: Int, GoodnotesFieldNumber {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4
}
