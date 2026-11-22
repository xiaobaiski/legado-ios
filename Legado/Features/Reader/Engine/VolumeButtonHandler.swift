import AVFoundation
import MediaPlayer
import UIKit

/// 实体音量键翻页控制器（基于 AVAudioSession outputVolume KVO 与隐藏 MPVolumeView，支持不中断背景音乐）
@MainActor
public final class VolumeButtonHandler: NSObject {
    nonisolated(unsafe) private var observation: NSKeyValueObservation?
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
    }

    public func start(
        onVolumeUp: @escaping () -> Void,
        onVolumeDown: @escaping () -> Void) {
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
        guard !isActive else { return }
        isActive = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 模拟器或无音频硬件环境下忽略会话激活异常
        }

        let current = session.outputVolume
        originalUserVolume = current
        // 避免贴边 0.0 / 1.0 导致无法检测到继续按减小或增大键
        let safeBaseline = min(max(current, 0.15), 0.85)
        baselineVolume = safeBaseline

        installHiddenVolumeView()
        if abs(current - safeBaseline) > 0.01 {
            applySliderVolume(safeBaseline)
        }

        observation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            let newVol = change.newValue ?? 0.5
            Task { @MainActor [weak self] in
                self?.handleVolumeChanged(newVolume: newVol)
            }
        }
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        observation?.invalidate()
        observation = nil

        if let originalUserVolume {
            applySliderVolume(originalUserVolume)
        }
        originalUserVolume = nil

        hiddenVolumeView?.removeFromSuperview()
        hiddenVolumeView = nil
        volumeSlider = nil
        onVolumeUp = nil
        onVolumeDown = nil
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

        let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        keyWindow.addSubview(volumeView)
        hiddenVolumeView = volumeView
        volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private func applySliderVolume(_ value: Float) {
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
