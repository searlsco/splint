import Testing

@testable import Splint

@MainActor
@Suite("Selection")
struct SelectionTests {
  @Test func currentIsNilByDefault() {
    let sel = Selection<Int>()
    #expect(sel.current == nil)
  }

  @Test func currentIsSettableToValue() {
    let sel = Selection<Int>()
    sel.current = 7
    #expect(sel.current == 7)
  }

  @Test func initWithInitialValueSetsCurrent() {
    let sel = Selection<String>("abc")
    #expect(sel.current == "abc")
  }

  @Test func currentIsSettableBackToNil() {
    let sel = Selection<Int>(1)
    sel.current = nil
    #expect(sel.current == nil)
  }
}
