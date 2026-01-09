import Cocoa

enum TimerState {
    case idle
    case running
    case paused
    case finished
}

struct SoundOption {
    let title: String
    let url: URL?
}

final class DigitsOnlyFormatter: NumberFormatter, @unchecked Sendable {
    private let maxValue: Int

    init(maxValue: Int, minimumDigits: Int = 1) {
        self.maxValue = maxValue
        super.init()
        allowsFloats = false
        minimum = 0
        maximum = NSNumber(value: maxValue)
        minimumIntegerDigits = minimumDigits
        maximumFractionDigits = 0
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        if partialString.isEmpty {
            return true
        }
        if partialString.range(of: "^[0-9]+$", options: .regularExpression) == nil {
            return false
        }
        if let value = Int(partialString), value > maxValue {
            return false
        }
        return true
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let rect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let y = rect.origin.y + (rect.size.height - textSize.height) / 2.0
        return NSRect(x: rect.origin.x, y: y, width: rect.size.width, height: textSize.height)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        return drawingRect(forBounds: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: start, length: length)
    }
}

final class TimeInputField: NSTextField {
    var minValue: Int = 0
    var maxValue: Int = 59

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCell()
    }

    private func configureCell() {
        let centeredCell = VerticallyCenteredTextFieldCell(textCell: "")
        centeredCell.usesSingleLineMode = true
        centeredCell.lineBreakMode = .byClipping
        centeredCell.isEditable = true
        centeredCell.isSelectable = true
        centeredCell.isBezeled = false
        centeredCell.isBordered = false
        centeredCell.drawsBackground = false
        cell = centeredCell
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            step(by: 1)
        case 125:
            step(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    func step(by delta: Int) {
        let nextValue = clampValue(from: stringValue, delta: delta)
        applyValue(nextValue)
    }

    private func clampValue(from string: String, delta: Int = 0) -> Int {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = Int(trimmed) ?? 0
        let adjusted = rawValue + delta
        return min(max(adjusted, minValue), maxValue)
    }

    func applyValue(_ value: Int) {
        if let formatter = formatter as? NumberFormatter,
           let formatted = formatter.string(for: value) {
            stringValue = formatted
            currentEditor()?.string = formatted
        } else {
            let fallback = "\(value)"
            stringValue = fallback
            currentEditor()?.string = fallback
        }
    }
}

final class TimerViewController: NSViewController, NSTextFieldDelegate {
    var onStart: ((TimeInterval) -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onSoundSelection: ((URL?) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Timed")
    private let hoursField = TimeInputField()
    private let minutesField = TimeInputField()
    private let secondsField = TimeInputField()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let primaryButton = NSButton(title: "Start", target: nil, action: nil)
    private let finishedStopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let restartButton = NSButton(title: "Restart", target: nil, action: nil)
    private let soundLabel = NSTextField(labelWithString: "Sound")
    private let soundPopup = NSPopUpButton()
    private var soundOptions: [SoundOption] = []

    private let inputRow = NSStackView()
    private let controlsStack = NSStackView()
    private let finishedStack = NSStackView()
    private let soundRow = NSStackView()
    private var currentState: TimerState = .idle

    override func loadView() {
        let containerSize = NSSize(width: 320, height: 200)
        let container = NSView(frame: NSRect(origin: .zero, size: containerSize))
        preferredContentSize = containerSize

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        configureTimeInputs()
        configureSoundPicker()

        cancelButton.target = self
        cancelButton.action = #selector(cancelTimer)
        cancelButton.isEnabled = false
        cancelButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cancelButton.bezelStyle = .regularSquare
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .white
        cancelButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 18
        cancelButton.layer?.masksToBounds = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        cancelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateCancelButtonAppearance()

        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)
        primaryButton.bezelStyle = .regularSquare
        primaryButton.isBordered = false
        primaryButton.contentTintColor = .white
        primaryButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        primaryButton.wantsLayer = true
        primaryButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        primaryButton.layer?.cornerRadius = 18
        primaryButton.layer?.masksToBounds = true
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        primaryButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        primaryButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        finishedStopButton.target = self
        finishedStopButton.action = #selector(stopTimer)
        finishedStopButton.bezelStyle = .regularSquare
        finishedStopButton.isBordered = false
        finishedStopButton.contentTintColor = .white
        finishedStopButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        finishedStopButton.wantsLayer = true
        finishedStopButton.layer?.backgroundColor = NSColor.systemGray.cgColor
        finishedStopButton.layer?.cornerRadius = 18
        finishedStopButton.layer?.masksToBounds = true
        finishedStopButton.translatesAutoresizingMaskIntoConstraints = false
        finishedStopButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        finishedStopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        finishedStopButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        restartButton.target = self
        restartButton.action = #selector(restartTimer)
        restartButton.bezelStyle = .regularSquare
        restartButton.isBordered = false
        restartButton.contentTintColor = .white
        restartButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        restartButton.wantsLayer = true
        restartButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        restartButton.layer?.cornerRadius = 18
        restartButton.layer?.masksToBounds = true
        restartButton.translatesAutoresizingMaskIntoConstraints = false
        restartButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        restartButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        restartButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        soundLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        soundLabel.textColor = .secondaryLabelColor
        soundLabel.alignment = .right
        soundLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        soundPopup.font = NSFont.systemFont(ofSize: 12, weight: .regular)

        let hoursLabel = NSTextField(labelWithString: "Hours")
        hoursLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hoursLabel.textColor = .secondaryLabelColor
        hoursLabel.alignment = .center
        let minutesLabel = NSTextField(labelWithString: "Minutes")
        minutesLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        minutesLabel.textColor = .secondaryLabelColor
        minutesLabel.alignment = .center

        let secondsLabel = NSTextField(labelWithString: "Seconds")
        secondsLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        secondsLabel.textColor = .secondaryLabelColor
        secondsLabel.alignment = .center

        let hoursStack = NSStackView(views: [hoursLabel, hoursField])
        hoursStack.orientation = .vertical
        hoursStack.spacing = 6
        hoursStack.alignment = .centerX

        let minutesStack = NSStackView(views: [minutesLabel, minutesField])
        minutesStack.orientation = .vertical
        minutesStack.spacing = 6
        minutesStack.alignment = .centerX

        let secondsStack = NSStackView(views: [secondsLabel, secondsField])
        secondsStack.orientation = .vertical
        secondsStack.spacing = 6
        secondsStack.alignment = .centerX

        hoursField.widthAnchor.constraint(equalTo: hoursStack.widthAnchor).isActive = true
        minutesField.widthAnchor.constraint(equalTo: minutesStack.widthAnchor).isActive = true
        secondsField.widthAnchor.constraint(equalTo: secondsStack.widthAnchor).isActive = true

        inputRow.orientation = .horizontal
        inputRow.spacing = 12
        inputRow.alignment = .centerY
        inputRow.distribution = .fillEqually
        inputRow.addArrangedSubview(hoursStack)
        inputRow.addArrangedSubview(minutesStack)
        inputRow.addArrangedSubview(secondsStack)

        controlsStack.orientation = .horizontal
        controlsStack.spacing = 10
        controlsStack.alignment = .centerY
        controlsStack.addArrangedSubview(cancelButton)
        controlsStack.addArrangedSubview(primaryButton)

        soundRow.orientation = .horizontal
        soundRow.spacing = 8
        soundRow.alignment = .centerY
        soundRow.addArrangedSubview(soundLabel)
        soundRow.addArrangedSubview(soundPopup)

        let finishedButtons = NSStackView(views: [finishedStopButton, restartButton])
        finishedButtons.orientation = .horizontal
        finishedButtons.spacing = 8
        finishedButtons.alignment = .centerY

        finishedStack.orientation = .vertical
        finishedStack.spacing = 12
        finishedStack.alignment = .centerX
        finishedStack.addArrangedSubview(finishedButtons)

        let mainStack = NSStackView(views: [titleLabel, inputRow, controlsStack, finishedStack, soundRow])
        mainStack.orientation = .vertical
        mainStack.spacing = 16
        mainStack.alignment = .centerX
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        inputRow.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
            inputRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        setState(.idle)
        view = container
    }

    func update(state: TimerState, remaining: TimeInterval?) {
        setState(state)
        if let remaining {
            updateTimeFields(with: remaining)
        }
    }

    private func setState(_ state: TimerState) {
        currentState = state
        controlsStack.isHidden = state == .finished
        finishedStack.isHidden = state != .finished
        setInputsEditable(state == .idle)

        switch state {
        case .idle:
            cancelButton.isEnabled = false
            updateCancelButtonAppearance()
            updatePrimaryButton(title: "Start", color: .systemBlue)
        case .running:
            cancelButton.isEnabled = true
            updateCancelButtonAppearance()
            updatePrimaryButton(title: "Pause", color: .systemOrange)
        case .paused:
            cancelButton.isEnabled = true
            updateCancelButtonAppearance()
            updatePrimaryButton(title: "Resume", color: .systemGreen)
        case .finished:
            cancelButton.isEnabled = false
            updateCancelButtonAppearance()
        }
        updateSoundPickerState()
    }

    func setDuration(_ duration: TimeInterval) {
        updateTimeFields(with: duration)
    }

    private func updateTimeFields(with duration: TimeInterval) {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        hoursField.applyValue(hours)
        minutesField.applyValue(minutes)
        secondsField.applyValue(seconds)
    }

    private func setInputsEditable(_ isEditable: Bool) {
        let fields = [hoursField, minutesField, secondsField]
        for field in fields {
            field.isEditable = isEditable
            field.isSelectable = isEditable
        }
    }

    private func updatePrimaryButton(title: String, color: NSColor) {
        primaryButton.title = title
        primaryButton.layer?.backgroundColor = color.cgColor
    }

    private func updateCancelButtonAppearance() {
        let color: NSColor = cancelButton.isEnabled ? .systemGray : .systemGray.withAlphaComponent(0.45)
        cancelButton.layer?.backgroundColor = color.cgColor
    }

    private func updateSoundPickerState() {
        let isActive = currentState == .idle
        soundPopup.isEnabled = isActive
        soundLabel.alphaValue = isActive ? 1.0 : 0.45
        soundPopup.alphaValue = isActive ? 1.0 : 0.45
    }

    private func configureTimeInputs() {
        configureField(hoursField, maxValue: 23, initialValue: 0)
        configureField(minutesField, maxValue: 59, initialValue: 5)
        configureField(secondsField, maxValue: 59, initialValue: 0)
    }

    private func configureSoundPicker() {
        soundOptions = loadSoundOptions()
        soundPopup.removeAllItems()
        for option in soundOptions {
            soundPopup.addItem(withTitle: option.title)
        }
        soundPopup.selectItem(at: 0)
        soundPopup.target = self
        soundPopup.action = #selector(soundSelectionChanged)
        soundPopup.translatesAutoresizingMaskIntoConstraints = false
        soundPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        soundSelectionChanged()
    }

    private func configureField(_ field: TimeInputField, maxValue: Int, initialValue: Int) {
        field.delegate = self
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        field.alignment = .center
        field.formatter = DigitsOnlyFormatter(maxValue: maxValue, minimumDigits: 2)
        field.minValue = 0
        field.maxValue = maxValue
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 52).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.applyValue(initialValue)
    }

    private func loadSoundOptions() -> [SoundOption] {
        var options = [SoundOption(title: "No Sound", url: nil)]
        guard let directory = soundDirectoryURL() else { return options }
        let allowedExtensions = ["aiff", "wav", "caf", "mp3", "m4a"]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return options }
        let soundFiles = files.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        let mapped = soundFiles.map { SoundOption(title: $0.deletingPathExtension().lastPathComponent, url: $0) }
        let sorted = mapped.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        options.append(contentsOf: sorted)
        return options
    }

    private func soundDirectoryURL() -> URL? {
        let fileManager = FileManager.default
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("sounds"),
           fileManager.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        let cwdURL = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("sounds")
        if fileManager.fileExists(atPath: cwdURL.path) {
            return cwdURL
        }
        return nil
    }

    private func selectedDuration() -> TimeInterval {
        let hours = Double(value(for: hoursField))
        let minutes = Double(value(for: minutesField))
        let seconds = Double(value(for: secondsField))
        return hours * 3600 + minutes * 60 + seconds
    }

    private func formatCountdown(_ remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(remaining.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @objc private func primaryButtonPressed() {
        switch currentState {
        case .idle:
            startTimer()
        case .running:
            onPause?()
        case .paused:
            onResume?()
        case .finished:
            break
        }
    }

    @objc private func cancelTimer() {
        onStop?()
    }

    @objc private func soundSelectionChanged() {
        let index = soundPopup.indexOfSelectedItem
        guard index >= 0, index < soundOptions.count else {
            onSoundSelection?(nil)
            return
        }
        onSoundSelection?(soundOptions[index].url)
    }

    private func startTimer() {
        let duration = selectedDuration()
        guard duration > 0 else {
            NSSound.beep()
            return
        }
        onStart?(duration)
    }

    @objc private func stopTimer() {
        onStop?()
    }

    @objc private func restartTimer() {
        onRestart?()
    }

    private func commitFieldValue(for field: TimeInputField) {
        let value = value(for: field)
        field.applyValue(value)
    }

    private func value(for field: TimeInputField) -> Int {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue = Int(trimmed) else {
            return 0
        }
        return min(max(rawValue, field.minValue), field.maxValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? TimeInputField else { return }
        commitFieldValue(for: field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? TimeInputField else { return false }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            field.step(by: 1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            field.step(by: -1)
            return true
        }
        return false
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? TimeInputField else { return }
        guard let textView = field.window?.fieldEditor(true, for: field) as? NSTextView else { return }
        textView.insertionPointColor = .clear
        let length = (field.stringValue as NSString).length
        textView.setSelectedRange(NSRange(location: 0, length: length))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let statusItemFixedLength: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let sample = "23:59"
        let size = (sample as NSString).size(withAttributes: [.font: font])
        return ceil(size.width + 18)
    }()
    private var statusItem: NSStatusItem?
    private var statusImage: NSImage?
    private let popover = NSPopover()
    private let timerController = TimerViewController()
    private var timer: Timer?
    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var lastDuration: TimeInterval = 0
    private var state: TimerState = .idle
    private var closeMonitor: Any?
    private var resignObserver: Any?
    private var selectedSoundURL: URL?
    private var alertSound: NSSound?
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        timerController.onStart = { [weak self] duration in
            self?.startTimer(duration: duration)
        }
        timerController.onPause = { [weak self] in
            self?.pauseTimer()
        }
        timerController.onResume = { [weak self] in
            self?.resumeTimer()
        }
        timerController.onStop = { [weak self] in
            self?.stopTimer()
        }
        timerController.onRestart = { [weak self] in
            self?.restartTimer()
        }
        timerController.onSoundSelection = { [weak self] url in
            self?.selectedSoundURL = url
            guard let self else { return }
            if self.state == .finished {
                if url == nil {
                    self.stopAlertSound()
                } else {
                    self.playAlertSoundIfNeeded()
                }
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: AppDelegate.statusItemFixedLength)
        if let image = NSImage(named: "MenuBarTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
            statusImage = image
        } else {
            item.button?.title = "timed"
        }
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            stopCloseMonitoring()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        updatePopoverContent()
        popover.contentSize = popover.contentViewController?.preferredContentSize ?? NSSize(width: 320, height: 200)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.startCloseMonitoring()
        }
    }

    private func updatePopoverContent() {
        popover.contentViewController = timerController
        timerController.update(state: state, remaining: remainingTime())
    }

    private func startTimer(duration: TimeInterval) {
        stopAlertSound()
        lastDuration = duration
        endDate = Date().addingTimeInterval(duration)
        pausedRemaining = nil
        state = .running
        scheduleTimer()
        tick()
    }

    private func pauseTimer() {
        guard state == .running else { return }
        pausedRemaining = remainingTime()
        timer?.invalidate()
        timer = nil
        endDate = nil
        state = .paused
        timerController.update(state: .paused, remaining: pausedRemaining)
        updateStatusItem(remaining: pausedRemaining)
    }

    private func resumeTimer() {
        guard state == .paused, let remaining = pausedRemaining, remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        pausedRemaining = nil
        state = .running
        scheduleTimer()
        tick()
    }

    private func stopTimer() {
        stopAlertSound()
        timer?.invalidate()
        timer = nil
        endDate = nil
        pausedRemaining = nil
        state = .idle
        timerController.update(state: .idle, remaining: nil)
        if lastDuration > 0 {
            timerController.setDuration(lastDuration)
        }
        updateStatusItem(remaining: nil)
    }

    private func restartTimer() {
        stopAlertSound()
        guard lastDuration > 0 else { return }
        startTimer(duration: lastDuration)
    }

    private func finishTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        pausedRemaining = nil
        state = .finished
        timerController.update(state: .finished, remaining: 0)
        updateStatusItem(remaining: nil)
        playAlertSoundIfNeeded()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard state == .running else { return }
        let remaining = remainingTime() ?? 0
        if remaining <= 0 {
            finishTimer()
            return
        }
        timerController.update(state: .running, remaining: remaining)
        updateStatusItem(remaining: remaining)
    }

    private func remainingTime() -> TimeInterval? {
        if state == .paused {
            return pausedRemaining
        }
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    private func updateStatusItem(remaining: TimeInterval?) {
        guard let button = statusItem?.button else { return }
        if let remaining, state == .running || state == .paused {
            let title = formatStatusTime(remaining)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            button.image = nil
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            if let statusImage {
                button.image = statusImage
                button.imagePosition = .imageOnly
            } else {
                button.title = "timed"
            }
        }
    }

    private func playAlertSoundIfNeeded() {
        stopAlertSound()
        guard let url = selectedSoundURL else { return }
        guard let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.loops = true
        sound.play()
        alertSound = sound
    }

    private func stopAlertSound() {
        alertSound?.stop()
        alertSound = nil
    }

    private func formatStatusTime(_ remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(remaining.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Timed")
        let quitItem = NSMenuItem(title: "Quit Timed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func popoverWillClose(_ notification: Notification) {
        stopCloseMonitoring()
    }

    private func startCloseMonitoring() {
        stopCloseMonitoring()
        closeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            guard let window = self.popover.contentViewController?.view.window else { return }
            let point = event.locationInWindow
            if !window.frame.contains(point) {
                self.popover.performClose(nil)
                self.stopCloseMonitoring()
            }
        }
    }

    private func stopCloseMonitoring() {
        if let monitor = closeMonitor {
            NSEvent.removeMonitor(monitor)
            closeMonitor = nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
