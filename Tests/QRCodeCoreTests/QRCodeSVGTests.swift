#if os(macOS)
import AppKit
import Testing
import Foundation
@testable import QRCodeCore

@MainActor struct QRCodeSVGTests {
    @Test func independentSVGRasterization() throws {
        for style in QRModuleStyle.allCases {
            for hasLogo in [false,true] {
                var p = QRPreferences(); p.style = style; p.opacity = 0.75; p.logoBackgroundOpacity = hasLogo ? 0.35 : 1
                let a = try QRCodeProcessor.generate(source:"https://example.com/svg?emoji=🌍",preferences:p,logo:hasLogo ? QRCodeTests.logo() : nil)
                let data = try QRCodeRenderer.svg(a.geometry,logo:a.logo)
                let ns = try #require(NSImage(data:data), "AppKit should read the serialized SVG")
                var rect = CGRect(x:0,y:0,width:a.side,height:a.side)
                let image = try #require(ns.cgImage(forProposedRect:&rect,context:nil,hints:nil))
                #expect(try QRCodeVerifier.verify(image,matrix:a.matrix,preferences:p,reference:a.reference).passed)
            }
        }
    }
}
#endif
