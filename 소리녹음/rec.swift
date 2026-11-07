// 컴퓨터에서 나는 소리(시스템 소리)만 녹음 — ScreenCaptureKit
// 사용: rec 출력.m4a 초
import Foundation
import ScreenCaptureKit
import AVFoundation

final class Rec: NSObject, SCStreamOutput {
    let writer: AVAssetWriter, input: AVAssetWriterInput
    var started = false
    init(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        writer = try! AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000])
        input.expectsMediaDataInRealTime = true; writer.add(input)
    }
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid else { return }
        if !started { writer.startWriting(); writer.startSession(atSourceTime: sb.presentationTimeStamp); started = true }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }
}
let args = CommandLine.arguments, url = URL(fileURLWithPath: args[1]), secs = Double(args[2]) ?? 10
let rec = Rec(url)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let disp = content.displays.first else { print("화면 없음"); exit(1) }
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true; cfg.sampleRate = 48000; cfg.channelCount = 2; cfg.excludesCurrentProcessAudio = true
        cfg.width = 2; cfg.height = 2; cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let st = SCStream(filter: SCContentFilter(display: disp, excludingWindows: []), configuration: cfg, delegate: nil)
        try st.addStreamOutput(rec, type: .audio, sampleHandlerQueue: DispatchQueue(label: "a"))
        try await st.startCapture()
        print("녹음 시작"); fflush(stdout)
        try await Task.sleep(nanoseconds: UInt64(secs * 1e9))
        try await st.stopCapture()
        rec.input.markAsFinished()
        await rec.writer.finishWriting()
        print("저장:", url.path, rec.started ? "" : "(소리 없음)")
    } catch { print("오류:", error) }
    sem.signal()
}
sem.wait()
