import Foundation

import Testing
@testable import ColorCore
@Test func colorGrammar() throws {
    #expect(try ColorParser.parse("#abc").hex == "#AABBCC")
    #expect(try ColorParser.parse("abcd").hex == "#AABBCCDD")
    #expect(try ColorParser.parse("rgb(255 0 0 / 50%)").hex == "#FF000080")
    #expect(try ColorParser.parse("hsl(-30deg 100% 50%)").hex == "#FF0080")
    #expect(try ColorParser.parse("hsl(0.5turn,100%,50%)").hex == "#00FFFF")
    #expect(try ColorParser.parse("hsl(200grad 100% 50%)").hex == "#00FFFF")
    #expect(try ColorParser.parse("transparent").a == 0)
    for s in ["rgb(256 0 0)","rgb(2,4%,5)","rgb(1,2,3 / 0.5)","hsl(0 1 1)","#12345","red","rgb(NaN 0 0)","rgb(1 2 3 / 2)","rgb(1e309 0 0)"] {#expect(throws:ColorInputError.self){try ColorParser.parse(s)}}
}
@Test func colorRoundTrip() throws {
    for r in stride(from:0.0,through:1.0,by:0.1){for g in stride(from:0.0,through:1.0,by:0.1){let c=try SRGBA(r,g,0.73,0.42),h=c.hsl,back=try SRGBA.hsl(h.h,h.s,h.l,c.a);#expect(abs(c.r-back.r)<1e-12);#expect(abs(c.g-back.g)<1e-12);#expect(abs(c.b-back.b)<1e-12)}}
}
@Test func contrastUnroundedAndAlpha() throws {
    #expect(try ContrastCalculator.evaluate(foreground:.black,background:.white).ratio == 21)
    #expect(try ContrastCalculator.evaluate(foreground:SRGBA(0,0,0,0),background:.white).ratio == 1)
    let l=(1.05/4.499)-0.05,c=try SRGBA(pow(l,1/2.4)*1.055-0.055,pow(l,1/2.4)*1.055-0.055,pow(l,1/2.4)*1.055-0.055)
    #expect(try !ContrastCalculator.evaluate(foreground:c,background:.white).checks[0].1)
    #expect(throws:ColorInputError.self){try ContrastCalculator.evaluate(foreground:.black,background:.white,backdrop:SRGBA(1,1,1,0.5))}
}
