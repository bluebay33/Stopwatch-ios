import AVFAudio
import Foundation

/// A short in-memory tick that shares the app's existing audio session.
final class Metronome {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let tickBuffer: AVAudioPCMBuffer

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        tickBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_100)!
        tickBuffer.frameLength = tickBuffer.frameCapacity

        if let samples = tickBuffer.floatChannelData?[0] {
            let rate = Float(format.sampleRate)
            for frame in 0..<Int(tickBuffer.frameLength) {
                let time = Float(frame) / rate
                let envelope = expf(-time * 90)
                samples[frame] = sinf(2 * .pi * 1_050 * time) * envelope * 0.18
            }
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func tick() {
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            player.scheduleBuffer(tickBuffer, completionHandler: nil)
            if !player.isPlaying { player.play() }
        } catch {
            // A tick is optional feedback; preserve stopwatch operation if audio is unavailable.
        }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
