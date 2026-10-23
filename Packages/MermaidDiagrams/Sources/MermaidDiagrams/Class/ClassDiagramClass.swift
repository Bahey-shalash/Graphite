/// A class of a class diagram: the name relations call it by, the text its box shows, and its compartments.
public struct ClassDiagramClass: Equatable, Sendable {
    /// The name as written, without its generic type: `Square` for `Square~Shape~`, `Animal Class!` for a name in
    /// backticks.
    public let identifier: String
    /// The text of the class's title: its name, or the label of `class Name["Label"]`.
    public internal(set) var label: DiagramLabel
    /// The generic type written between tildes after the name the first time the class is named (`Shape` for
    /// `Square~Shape~`, `K, V` for `Pair~K, V~`), or nil. It holds no tilde: the first one after it ends it.
    public internal(set) var genericType: String?
    /// `<<interface>>`, `<<abstract>>` and the like, without the angle brackets, in the order they are written.
    public internal(set) var annotations: [String]
    /// The members without parentheses, in the order they are written.
    public internal(set) var attributes: [ClassDiagramMember]
    /// The members with parentheses, in the order they are written.
    public internal(set) var methods: [ClassDiagramMember]

    init(identifier: String, label: DiagramLabel, genericType: String? = nil, annotations: [String] = [], attributes: [ClassDiagramMember] = [],
         methods: [ClassDiagramMember] = []) {
        self.identifier = identifier
        self.label = label
        self.genericType = genericType
        self.annotations = annotations
        self.attributes = attributes
        self.methods = methods
    }

    /// The title as it is drawn: the label, with the generic type in angle brackets after its last line
    /// (`Square<Shape>`).
    public var displayedName: DiagramLabel {
        var lines = label.lines
        guard let genericType, let last = lines.popLast() else { return label }
        return DiagramLabel(lines: lines + [last + "<" + genericType + ">"])
    }
}

/// An attribute or a method as its compartment shows it.
public struct ClassDiagramMember: Equatable, Sendable {
    /// The text drawn, as Mermaid shows it: the visibility mark (`+`, `-`, `#`, `~`) kept, generic types in angle
    /// brackets (`List<int>` for `List~int~`), a method's return type after a colon (`getTime() : DateTime`), the
    /// classifier mark removed, and entity codes read.
    public let text: String
    public let classifier: ClassDiagramMemberClassifier

    init(text: String, classifier: ClassDiagramMemberClassifier = .plain) {
        self.text = text
        self.classifier = classifier
    }
}

/// What the mark at the end of a member says of it.
public enum ClassDiagramMemberClassifier: Equatable, Sendable, CaseIterable {
    case plain
    /// `$`: drawn underlined.
    case `static`
    /// `*`: drawn in italics.
    case abstract
}
