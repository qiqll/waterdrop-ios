import Foundation
import Speech
import AVFoundation
import os.log

@Observable
final class SpeechRecognitionManager {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case processing
        case finished
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var recognizedText: String = ""
    private(set) var partialText: String = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "SpeechRecognition")

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micAuthorized: Bool
        if #available(iOS 17.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechAuthorized && micAuthorized
    }

    // MARK: - Start Listening

    func startListening() {
        guard speechRecognizer?.isAvailable == true else {
            state = .error("语音识别不可用")
            return
        }

        // Cancel any existing task
        cancel()

        state = .preparing

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else {
                state = .error("无法创建识别请求")
                return
            }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.recognizedText = text
                        self.partialText = ""
                        self.state = .finished
                        self.stopAudioEngine()
                    } else {
                        self.partialText = text
                    }
                }

                if let error {
                    // Ignore cancellation errors
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        return // User cancelled
                    }
                    self.logger.error("Recognition error: \(error.localizedDescription)")
                    if self.recognizedText.isEmpty && self.partialText.isEmpty {
                        self.state = .error("没听清楚，可以再说一次吗？")
                    }
                    self.stopAudioEngine()
                }
            }

            state = .listening
            recognizedText = ""
            partialText = ""

        } catch {
            logger.error("Audio engine start failed: \(error.localizedDescription)")
            state = .error("麦克风启动失败")
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        recognitionRequest?.endAudio()
        state = .processing
    }

    // MARK: - Cancel

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioEngine()
        state = .idle
        recognizedText = ""
        partialText = ""
    }

    // MARK: - Private

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
