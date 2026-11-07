// RAW → 보정 없는 JPG (셀렉 내보내기 '원본'용)
// 사용: rawjpg <RAW 파일> <출력.jpg>
// macOS 기본 RAW 현상(촬영 화이트밸런스, 회전 반영), 캡쳐원 조정은 안 들어감. sRGB · 품질 100 · 원본 크기
// 컴파일: swiftc -O rawjpg.swift -o ~/Library/Application\ Support/cc/rawjpg
import Foundation
import CoreImage

let a = CommandLine.arguments
func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
guard a.count == 3 else { fail("사용: rawjpg <RAW> <출력.jpg>") }
guard let f = CIRAWFilter(imageURL: URL(fileURLWithPath: a[1])), let img = f.outputImage else { fail("RAW를 읽지 못했어요: \(a[1])") }
let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
let q = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
do { try ctx.writeJPEGRepresentation(of: img, to: URL(fileURLWithPath: a[2]), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [q: 1.0]) }
catch { fail("저장하지 못했어요: \(error)") }
