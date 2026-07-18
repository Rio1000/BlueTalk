import AVFoundation
import Foundation

final class AudioManager: ObservableObject {

    enum RecordingState {
        case idle, recording, failed(String)
    }

    @Published private(set) var state: RecordingState = .idle

    private var engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var recordingURL: URL?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            state = .failed("Audio session error")
            return
        }

        let inputNode = engine.inputNode
        try? inputNode.setVoiceProcessingEnabled(true)

        let format = inputNode.outputFormat(forBus: 0)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            outputFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        } catch {
            state = .failed("Cannot create audio file")
            return
        }

        recordingURL = fileURL

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.outputFile?.write(from: buffer)
        }

        do {
            try engine.start()
            state = .recording
        } catch {
            state = .failed("Engine start failed")
        }
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
        state = .idle
        return recordingURL
    }
}
