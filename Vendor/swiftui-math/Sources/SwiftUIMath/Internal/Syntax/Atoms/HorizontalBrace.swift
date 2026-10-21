import Foundation

extension Math {
  /// Graphite patch: `\underbrace{…}` or `\overbrace{…}`. Its subscript (under) or
  /// superscript (over) is the brace's label, set below or above it as TeX sets the
  /// limits of an operator.
  final class HorizontalBrace: Atom {
    var innerList: AtomList?
    let isOver: Bool

    override var finalized: Math.Atom {
      let finalized = super.finalized

      if let brace = finalized as? HorizontalBrace {
        brace.innerList = brace.innerList?.finalized
      }

      return finalized
    }

    init(_ brace: HorizontalBrace) {
      self.innerList = brace.innerList.map { AtomList($0) }
      self.isOver = brace.isOver
      super.init(brace)
    }

    init(innerList: AtomList? = nil, isOver: Bool = false) {
      self.innerList = innerList
      self.isOver = isOver
      super.init(type: .horizontalBrace)
    }
  }
}
