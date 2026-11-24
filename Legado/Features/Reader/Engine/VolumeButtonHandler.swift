import AVFoundation
import MediaPlayer
import UIKit

/// 实体音量键翻页控制器（基于 AVAudioSession outputVolume KVO 与隐藏 MPVolumeView，支持不中断背景音乐）
@MainActor
public final class VolumeButtonHandler: NSObject {
    nonisolated(unsafe) private var observation: NSKeyValueObservation?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    private weak var hiddenVolumeView: MPVolumeView?
    private weak var volumeSlider: UISlider?
    private var baselineVolume: Float = 0.5
    private var originalUserVolume: Float?
    private var isResetting = false
    private var isActive = false

    private var onVolumeUp: (() -> Void)?
    private var onVolumeDown: (() -> Void)?

    override public init() {
        super.init()
    }

    deinit {
        observation?.invalidate()
        observation = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    public func start(
        onVolumeUp: @escaping () -> Void,
        onVolumeDown: @escaping () -> Void) {
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
        guard !isActive else { return }
        isActive = true

        activateAudioSession()
        installHiddenVolumeView()

        let current = AVAudioSession.sharedInstance().outputVolume
        originalUserVolume = current
        // 尽量保留用户当前媒体音量，仅在贴边 0.0 / 1.0 时微调 0.0625 以便检测双向按键
        let safeBaseline: Float
        if current <= 0.01 {
            safeBaseline = 0.0625
        } else if current >= 0.99 {
            safeBaseline = 0.9375
        } else {
            safeBaseline = current
        }
        baselineVolume = safeBaseline

        if abs(current - safeBaseline) > 0.005 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.locateVolumeSliderIfNeeded()
                self.applySliderVolume(safeBaseline)
            }
        }

        let session = AVAudioSession.sharedInstance()
        observation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            let newVol = change.newValue ?? 0.5
            Task { @MainActor [weak self] in
                self?.handleVolumeChanged(newVolume: newVol)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let interrupted = typeRaw == AVAudioSession.InterruptionType.ended.rawValue
            if interrupted {
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    self.activateAudioSession()
                }
            }
        }
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        observation?.invalidate()
        observation = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        if let originalUserVolume, abs(originalUserVolume - baselineVolume) > 0.005 {
            applySliderVolume(originalUserVolume)
        }
        originalUserVolume = nil

        hiddenVolumeView?.removeFromSuperview()
        hiddenVolumeView = nil
        volumeSlider = nil
        onVolumeUp = nil
        onVolumeDown = nil
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 模拟器或无音频硬件环境下忽略会话激活异常
        }
    }

    private func handleVolumeChanged(newVolume: Float) {
        guard isActive, !isResetting else { return }
        let delta = newVolume - baselineVolume
        guard abs(delta) >= 0.005 else { return }

        if delta > 0 {
            onVolumeUp?()
        } else {
            onVolumeDown?()
        }

        applySliderVolume(baselineVolume)
    }

    private func installHiddenVolumeView() {
        guard hiddenVolumeView == nil,
              let windowScene = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .first(where: { $0.activationState == .foregroundActive })
              ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let keyWindow = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first else {
            return
        }

        // MPVolumeView 必须位于 keyWindow 边界内才能抑制 iOS 系统音量条弹窗
        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        volumeView.alpha = 0.001
        volumeView.clipsToBounds = true
        volumeView.showsRouteButton = false
        volumeView.isUserInteractionEnabled = false
        keyWindow.addSubview(volumeView)
        volumeView.layoutIfNeeded()
        hiddenVolumeView = volumeView
        locateVolumeSliderIfNeeded()
    }

    private func locateVolumeSliderIfNeeded() {
        guard volumeSlider == nil, let hiddenVolumeView else { return }
        volumeSlider = hiddenVolumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private func applySliderVolume(_ value: Float) {
        locateVolumeSliderIfNeeded()
        guard let slider = volumeSlider else { return }
        isResetting = true
        slider.setValue(value, animated: false)
        slider.sendActions(for: .touchUpInside)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.isResetting = false
        }
    }
}
