import Foundation
import AVFoundation
import UIKit
internal import Combine

/// AVFoundationでカメラのライブプレビュー + フレームストリームを提供する。
/// フレームは ~4 fps にスロットリングして送る（OCR の負荷を抑えるため）。
@MainActor
final class CameraCaptureService: NSObject, ObservableObject {
  enum SessionState {
    case idle
    case running
    case denied
    case failed(String)
  }

  @Published private(set) var state: SessionState = .idle
  /// ライブ認識用のフレームストリーム（最新1フレームのみバッファ）
  let frameSubject = PassthroughSubject<UIImage, Never>()

  let session = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "nightreign.camera.session")
  private let videoQueue = DispatchQueue(label: "nightreign.camera.video")
  /// フレーム配信間隔の下限。これより速いと OCR が追いつかないので意味がないが、
  /// 短くしておくと OCR がスナッピーに次のフレームを処理できる。
  private let frameInterval: CFTimeInterval = 0.12  // ~8fps
  nonisolated(unsafe) private var lastDeliveredAt: CFTimeInterval = 0

  func start() {
#if targetEnvironment(simulator)
    state = .running
    startStubFrames()
    return
#else
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndRun()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        Task { @MainActor in
          if granted {
            self?.configureAndRun()
          } else {
            self?.state = .denied
          }
        }
      }
    case .denied, .restricted:
      state = .denied
    @unknown default:
      state = .denied
    }
#endif
  }

  func stop() {
#if targetEnvironment(simulator)
    stopStubFrames()
#else
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
#endif
  }

#if targetEnvironment(simulator)
  static let stubImage: UIImage? = {
    guard let url = Bundle.main.url(forResource: "stub", withExtension: "png") else { return nil }
    return UIImage(contentsOfFile: url.path)
  }()

  private var stubTimer: Timer?

  private func startStubFrames() {
    guard let image = Self.stubImage else { return }
    stubTimer?.invalidate()
    stubTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.frameSubject.send(image) }
    }
  }

  private func stopStubFrames() {
    stubTimer?.invalidate()
    stubTimer = nil
  }
#endif

  private func configureAndRun() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      self.session.beginConfiguration()
      // 「昏景」と「景色」のような近い字形を確実に区別したいので解像度は落とさない。
      // matcher 側の高速化で OCR 律速になるため、ここを下げる必要は無い。
      self.session.sessionPreset = .high

      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            self.session.canAddInput(input) else {
        self.session.commitConfiguration()
        Task { @MainActor in self.state = .failed(String(localized: "Failed to initialize camera")) }
        return
      }
      self.session.inputs.forEach { self.session.removeInput($0) }
      self.session.addInput(input)

      self.session.outputs.forEach { self.session.removeOutput($0) }
      self.videoOutput.alwaysDiscardsLateVideoFrames = true
      self.videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
      guard self.session.canAddOutput(self.videoOutput) else {
        self.session.commitConfiguration()
        Task { @MainActor in self.state = .failed(String(localized: "Failed to add video output")) }
        return
      }
      self.session.addOutput(self.videoOutput)

      if let connection = self.videoOutput.connection(with: .video) {
        if connection.isVideoRotationAngleSupported(90) {
          connection.videoRotationAngle = 90
        }
      }
      self.session.commitConfiguration()

      self.session.startRunning()
      Task { @MainActor in self.state = .running }
    }
  }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = CACurrentMediaTime()
    guard now - lastDeliveredAt >= frameInterval else { return }
    lastDeliveredAt = now

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: nil)
    guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = UIImage(cgImage: cg, scale: 1, orientation: .up)

    Task { @MainActor in
      self.frameSubject.send(image)
    }
  }
}
