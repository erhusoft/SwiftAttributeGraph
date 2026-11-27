import Testing
@testable import SwiftAttributeGraph

/// The bits of `AttributeTypeFlags` and the defaults of `flags` and `comparisonMode` of each kind of body. Native values measured on
/// macOS 15.8.3 by oracle scenarios `f1` to `f9` (in the comments) and the bits from `AGAttributeTypeFlags.h`.
@Suite struct AttributeTypeFlagsTests {
    struct BareBody: _AttributeBody {}
    struct PlainRule: Rule { var value: Int { 1 } }
    struct PlainStateful: StatefulRule {
        typealias Value = Int
        mutating func updateValue(_ context: inout RuleContext<Int>) { context.value = 1 }
    }
    struct Watched: ObservedAttribute { mutating func destroy() {} }
    struct FlagsOverride: _AttributeBody { static var flags: AttributeTypeFlags { [.hasDestroySelf] } }
    struct MainThreadOverride: _AttributeBody { static var flags: AttributeTypeFlags { [.mainThread] } }
    struct ModeOverride: _AttributeBody { static var comparisonMode: ComparisonMode { .equatableAlways } }

    @Test func theBitsAreTheNativeOnes() { // f9 named
        #expect(AttributeTypeFlags.comparisonModeIndirect.rawValue == 1)
        #expect(AttributeTypeFlags.comparisonModeEquatableUnlessPOD.rawValue == 2)
        #expect(AttributeTypeFlags.comparisonModeEquatableAlways.rawValue == 3)
        #expect(AttributeTypeFlags.comparisonModeMask.rawValue == 3)
        #expect(AttributeTypeFlags.hasDestroySelf.rawValue == 4)
        #expect(AttributeTypeFlags.mainThread.rawValue == 8)
        #expect(AttributeTypeFlags.external.rawValue == 16)
        #expect(AttributeTypeFlags.asyncThread.rawValue == 32)
    }

    @Test func theNativeNameIsAnAlias() {
        #expect(ObjectIdentifier(_AttributeType.Flags.self) == ObjectIdentifier(AttributeTypeFlags.self))
        #expect(ObjectIdentifier(PlainRule.Flags.self) == ObjectIdentifier(AttributeTypeFlags.self))
    }

    @Test func aFlagValueIsDescribedWithTheNativeTypeName() { // f9 raw
        #expect(String(describing: AttributeTypeFlags(rawValue: 8)) == "AGAttributeTypeFlags(rawValue: 8)")
        #expect(String(describing: AttributeTypeFlags(rawValue: 63)) == "AGAttributeTypeFlags(rawValue: 63)")
    }

    @Test func aBareBodyARuleAndAStatefulRuleAreMainThreadWithModeTwo() { // f1, f2, f3 flags=8 cmp=2
        for (flags, mode, destroy) in [
            (BareBody.flags, BareBody.comparisonMode, BareBody._hasDestroySelf),
            (PlainRule.flags, PlainRule.comparisonMode, PlainRule._hasDestroySelf),
            (PlainStateful.flags, PlainStateful.comparisonMode, PlainStateful._hasDestroySelf),
        ] {
            #expect(flags.rawValue == 8)
            #expect(mode.rawValue == 2)
            #expect(destroy == false)
        }
    }

    @Test func anExternalIsNotMainThreadAndComparesEquatableAlways() { // f4 flags=0 cmp=3
        #expect(External<Int>.flags.rawValue == 0)
        #expect(External<Int>.comparisonMode.rawValue == 3)
        #expect(External<Int>._hasDestroySelf == false)
    }

    @Test func mapAndFocusAreNotMainThread() { // f5 [0, 2, false]
        #expect(Map<Int, Int>.flags.rawValue == 0)
        #expect(Map<Int, Int>.comparisonMode.rawValue == 2)
        #expect(Map<Int, Int>._hasDestroySelf == false)
        #expect(Focus<Int, Int>.flags.rawValue == 0)
        #expect(Focus<Int, Int>.comparisonMode.rawValue == 2)
        #expect(Focus<Int, Int>._hasDestroySelf == false)
    }

    @Test func anObservedAttributeHasDestroySelfButItsFlagsDoNotCarryTheBit() { // f6 flags=8 cmp=2 hasDestroySelf=true
        #expect(Watched.flags.rawValue == 8)
        #expect(Watched.comparisonMode.rawValue == 2)
        #expect(Watched._hasDestroySelf == true)
    }

    @Test func anOverrideOfTheFlagsIsReturnedAsIsAndLeavesTheModeAlone() { // f7 [4, 2, false], [8, 2, false]
        #expect(FlagsOverride.flags.rawValue == 4)
        #expect(FlagsOverride.comparisonMode.rawValue == 2)
        #expect(FlagsOverride._hasDestroySelf == false)
        #expect(MainThreadOverride.flags.rawValue == 8)
        #expect(MainThreadOverride.comparisonMode.rawValue == 2)
    }

    @Test func anOverrideOfTheModeLeavesTheFlagsAlone() { // f8 (native measured with the default mode: flags 8, cmp 2)
        #expect(ModeOverride.comparisonMode.rawValue == 3)
        #expect(ModeOverride.flags.rawValue == 8)
    }
}
