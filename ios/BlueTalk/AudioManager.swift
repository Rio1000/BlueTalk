import AVFoundation
import Foundation

class AudioManager: ObservableObject {
    private var engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var recordingURL: URL?

    func setupSession() {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat mode combined with .allowBluetooth forces the OS to use headset mics
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try? session.setActive(true)
    }

    func startRecording() {
        setupSession()
        let inputNode = engine.inputNode
        
        // This is the magic flag that enables background noise filtering & voice isolation
        try? inputNode.setVoiceProcessingEnabled(true)

        let format = inputNode.outputFormat(forBus: 0)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")
        self.recordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        outputFile = try? AVAudioFile(forWriting: fileURL, settings: settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.outputFile?.write(from: buffer)
        }

        try? engine.start()
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
        completion(recordingURL)
    }
}
