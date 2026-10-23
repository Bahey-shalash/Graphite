import CoreGraphics

/// The rectangle an entity relationship diagram's drawing covers: its boxes, its lines with their curves' control
/// points, its marks and its labels with the patches behind them.
enum EntityRelationshipLayoutBounds {
    static func union(entities: [EntityRelationshipLayoutEntity], relationships: [EntityRelationshipLayoutRelationship]) -> CGRect {
        var bounds = CGRect.null
        for entity in entities { bounds = bounds.union(entity.frame) }
        for relationship in relationships {
            bounds = bounds.union(CGRect(origin: relationship.path.start, size: .zero))
            for segment in relationship.path.segments {
                switch segment {
                case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
                case .curve(let end, let firstControl, let secondControl):
                    bounds = bounds.union(CGRect(origin: end, size: .zero)).union(CGRect(origin: firstControl, size: .zero))
                        .union(CGRect(origin: secondControl, size: .zero))
                }
            }
            for mark in [relationship.firstEntityMark, relationship.secondEntityMark] {
                let reach = EntityRelationshipCardinalityMark.length
                bounds = bounds.union(CGRect(origin: mark.tip, size: .zero).insetBy(dx: -reach, dy: -reach))
            }
            if let label = relationship.label {
                let room = EntityRelationshipLayoutEngine.labelRoom
                bounds = bounds.union(label.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
            }
        }
        return bounds.isNull ? .zero : bounds
    }
}
