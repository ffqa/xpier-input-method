//
//  XpierApplicationDelegate.swift
//  Xpier
//
//  Created by Leo Liu on 5/6/24.
//

import UserNotifications
import Sparkle
import AppKit
import CoreText
import ObjectiveC
import InputMethodKit

final class XpierApplicationDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
  static let rimeWikiURL = URL(string: "https://github.com/rime/home/wiki")!
  static let updateNotificationIdentifier = "XpierUpdateNotification"
  static let notificationIdentifier = "XpierNotification"

  let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  var config: XpierConfig?
  var panel: XpierPanel?
  var enableNotifications = false
  var showStatusIcon: Bool = true
  var statusItem: NSStatusItem?
  let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    NSApp.setActivationPolicy(.regular)
    if !state.userInitiated {
      NSApp.dockTile.badgeLabel = "1"
      let content = UNMutableNotificationContent()
      content.title = NSLocalizedString("A new update is available", comment: "Update")
      content.body = NSLocalizedString("Version [version] is now available", comment: "Update").replacingOccurrences(of: "[version]", with: update.displayVersionString)
      let request = UNNotificationRequest(identifier: Self.updateNotificationIdentifier, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    NSApp.dockTile.badgeLabel = ""
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier == Self.updateNotificationIdentifier && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      updateController.updater.checkForUpdates()
    }

    completionHandler()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    panel = XpierPanel(position: .zero)
    refreshStatusItem()
    addObservers()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // swiftlint:disable:next notification_center_detachment
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    panel?.hide()
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  func updateStatusIcon(asciiMode: Bool, schemaLabel: String?) {
    DispatchQueue.main.async { [weak self] in
      self?.applyStatusIcon(asciiMode: asciiMode, schemaLabel: schemaLabel)
    }
  }

  func deploy() {
    print("Start maintenance...")
    self.shutdownRime()
    self.startRime(fullCheck: true)
    self.loadSettings()
  }

  func syncUserData() {
    print("Sync user data")
    _ = rimeAPI.sync_user_data()
  }

  func openLogFolder() {
    NSWorkspace.shared.open(XpierApp.logDir)
  }

  func openRimeFolder() {
    NSWorkspace.shared.open(XpierApp.userDir)
  }

  func checkForUpdates() {
    if updateController.updater.canCheckForUpdates {
      print("Checking for updates")
      updateController.updater.checkForUpdates()
    } else {
      print("Cannot check for updates")
    }
  }

  func openWiki() {
    NSWorkspace.shared.open(Self.rimeWikiURL)
  }

  static func showMessage(msgText: String?) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .provisional]) { _, error in
      if let error = error {
        print("User notification authorization error: \(error.localizedDescription)")
      }
    }
    center.getNotificationSettings { settings in
      if (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && settings.alertSetting == .enabled {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Xpier", comment: "")
        if let msgText = msgText {
          content.subtitle = msgText
        }
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
        center.add(request) { error in
          if let error = error {
            print("User notification request error: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  func setupRime() {
    createDirIfNotExist(path: XpierApp.userDir)
    createDirIfNotExist(path: XpierApp.logDir)
    // Expose the log directory to librime plugins.
    setenv("RIME_LOG_DIR", XpierApp.logDir.path(), 1)
    // swiftlint:disable identifier_name
    let notification_handler: @convention(c) (UnsafeMutableRawPointer?, RimeSessionId, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = notificationHandler
    let context_object = Unmanaged.passUnretained(self).toOpaque()
    // swiftlint:enable identifier_name
    rimeAPI.set_notification_handler(notification_handler, context_object)

    var squirrelTraits = RimeTraits.rimeStructInit()
    squirrelTraits.setCString(Bundle.main.sharedSupportPath!, to: \.shared_data_dir)
    squirrelTraits.setCString(XpierApp.userDir.path(), to: \.user_data_dir)
    squirrelTraits.setCString(XpierApp.logDir.path(), to: \.log_dir)
    squirrelTraits.setCString("Xpier", to: \.distribution_code_name)
    squirrelTraits.setCString("鼠鬚管", to: \.distribution_name)
    squirrelTraits.setCString(Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String, to: \.distribution_version)
    squirrelTraits.setCString("rime.xpier", to: \.app_name)
    rimeAPI.setup(&squirrelTraits)
  }

  func startRime(fullCheck: Bool) {
    print("Initializing la rime...")
    rimeAPI.initialize(nil)
    if rimeAPI.start_maintenance(fullCheck) {
      _ = rimeAPI.deploy_config_file("squirrel.yaml", "config_version")
    }
  }

  func loadSettings() {
    config = XpierConfig()
    if !config!.openBaseConfig() {
      return
    }

    enableNotifications = config!.getString("show_notifications_when") != "never"
    showStatusIcon = config!.getBool("status_icon/show") ?? true
    refreshStatusItem()
    if let panel = panel, let config = self.config {
      panel.load(config: config, forDarkMode: false)
      panel.load(config: config, forDarkMode: true)
    }
  }

  func loadSettings(for schemaID: String) {
    if schemaID.count == 0 || schemaID.first == "." {
      return
    }
    let schema = XpierConfig()
    if let panel = panel, let config = self.config {
      if schema.open(schemaID: schemaID, baseConfig: config) && schema.has(section: "style") {
        panel.load(config: schema, forDarkMode: false)
        panel.load(config: schema, forDarkMode: true)
      } else {
        panel.load(config: config, forDarkMode: false)
        panel.load(config: config, forDarkMode: true)
      }
    }
    schema.close()
  }

  // Detect repeated launches that may indicate a bad configuration loop.
  func problematicLaunchDetected() -> Bool {
    var detected = false
    let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("xpier_launch.json", conformingTo: .json)
    do {
      let archive = try Data(contentsOf: logFile, options: [.uncached])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .millisecondsSince1970
      let previousLaunch = try decoder.decode(Date.self, from: archive)
      if previousLaunch.timeIntervalSinceNow >= -2 {
        detected = true
      }
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {

    } catch {
      print("Error occurred during processing launch time archive: \(error.localizedDescription)")
      return detected
    }
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970
      let record = try encoder.encode(Date.now)
      try record.write(to: logFile)
    } catch {
      print("Error occurred during saving launch time to archive: \(error.localizedDescription)")
    }
    return detected
  }

  func addObservers() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil, using: workspaceWillPowerOff)

    let notifCenter = DistributedNotificationCenter.default()
    notifCenter.addObserver(forName: .init("XpierReloadNotification"), object: nil, queue: nil, using: rimeNeedsReload)
    notifCenter.addObserver(forName: .init("XpierSyncNotification"), object: nil, queue: nil, using: rimeNeedsSync)
    notifCenter.addObserver(forName: .init("XpierToggleASCIIModeNotification"), object: nil, queue: nil, using: rimeToggleASCIIMode)
    notifCenter.addObserver(forName: .init("XpierGetASCIIModeNotification"), object: nil, queue: nil, using: rimeGetASCIIMode)
    // Suspension behavior matters: the default coalescing holds notifications
    // back while the process is inactive, which is exactly the state Xpier
    // enters when the user switches away — the icon would fail to hide until
    // the next activation. Deliver immediately instead.
    notifCenter.addObserver(self, selector: #selector(inputSourceChanged(_:)),
                            name: .init(kTISNotifySelectedKeyboardInputSourceChanged as String),
                            object: nil, suspensionBehavior: .deliverImmediately)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    print("Xpier is quitting.")
    rimeAPI.cleanup_all_sessions()
    return .terminateNow
  }

}

extension RimeStringSlice {
  /// Bridge the slice's pointer + length to a Swift String, honoring `.length`.
  /// librime clips `.length` to the first Unicode character for abbreviated labels
  /// when no explicit `abbrev:` field is defined, so reading past `.length` (e.g. with
  /// `String(cString:)`) would incorrectly return the full `states:` value.
  var asString: String? {
    guard let ptr = str else { return nil }
    let data = Data(bytes: UnsafeRawPointer(ptr), count: Int(length))
    return String(data: data, encoding: .utf8)
  }
}

// swiftlint:disable:next cyclomatic_complexity
private func notificationHandler(contextObject: UnsafeMutableRawPointer?, sessionId: RimeSessionId, messageTypeC: UnsafePointer<CChar>?, messageValueC: UnsafePointer<CChar>?) {
  let delegate: XpierApplicationDelegate = Unmanaged<XpierApplicationDelegate>.fromOpaque(contextObject!).takeUnretainedValue()

  let messageType = messageTypeC.map { String(cString: $0) }
  let messageValue = messageValueC.map { String(cString: $0) }

  if messageType == "deploy" {
    switch messageValue {
    case "start":
      XpierApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_start", comment: ""))
    case "success":
      XpierApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_success", comment: ""))
    case "failure":
      XpierApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_failure", comment: ""))
    default:
      break
    }
    return
  } else if messageType == "option" {
    let state = messageValue?.first != "!"
    let optionName: String?
    if state {
      optionName = messageValue
    } else if let value = messageValue {
      optionName = String(value[value.index(after: value.startIndex)...])
    } else {
      optionName = nil
    }
    if let optionName = optionName {
      optionName.withCString { name in
        func shortLabel() -> String? {
          let stateLabelShort = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, true)
          return stateLabelShort.asString
        }
        func longLabel() -> String? {
          let stateLabelLong = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, false)
          return stateLabelLong.asString
        }
        if optionName == "ascii_mode" {
          delegate.updateStatusIcon(asciiMode: state, schemaLabel: shortLabel())
        }
        if delegate.enableNotifications {
          delegate.showStatusMessage(msgTextLong: longLabel(), msgTextShort: shortLabel())
        }
      }
    }
    return
  } else if messageType == "property", let messageValue = messageValue,
            let eqIndex = messageValue.firstIndex(of: "="), messageValue.first == "_" {
    let key = String(messageValue[..<eqIndex])
    let value = String(messageValue[messageValue.index(after: eqIndex)...])
    Task.detached { @MainActor in
      do {
        try delegate.panel?.inputController?.handleReservedProperty(key: key, value: value, for: sessionId)
      } catch {
        print("Error processing handleReservedProperty: \(error)")
      }
    }
    return
  }

  if delegate.enableNotifications {
    if messageType == "schema", let messageValue = messageValue, let schemaName = try? /^[^\/]*\/(.*)$/.firstMatch(in: messageValue)?.output.1 {
      delegate.showStatusMessage(msgTextLong: String(schemaName), msgTextShort: String(schemaName))
      return
    }
  }
}

private extension XpierApplicationDelegate {
  func showStatusMessage(msgTextLong: String?, msgTextShort: String?) {
    if !(msgTextLong ?? "").isEmpty || !(msgTextShort ?? "").isEmpty {
      panel?.updateStatus(long: msgTextLong ?? "", short: msgTextShort ?? "")
    }
  }

  func refreshStatusItem() {
    if showStatusIcon {
      if statusItem == nil {
        setupStatusItem()
      }
    } else if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
      button.toolTip = NSLocalizedString("Xpier", comment: "")
    }
    statusItem = item
    applyStatusIcon(asciiMode: false, schemaLabel: nil)
    updateStatusItemVisibility()
  }

  @objc func inputSourceChanged(_: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.updateStatusItemVisibility()
      self?.finalizeStrandedComposition()
    }
  }

  func updateStatusItemVisibility() {
    guard let statusItem = statusItem else { return }
    let currentInputSourceID = XpierInstaller.currentInputSourceID() ?? ""
    statusItem.isVisible = currentInputSourceID.hasPrefix("com.xpier.inputmethod.Xpier")
  }

  // macOS 26 does not call deactivateServer when the input source is switched
  // away by another process via TISSelectInputSource() (e.g. macism, Input
  // Source Pro): the pending composition is stranded and the candidate panel
  // is left orphaned on screen (#1140). The input-source-changed notification
  // is still delivered, so finalize the composition here as a fallback.
  // Switching via the menu bar calls deactivateServer first, making this a
  // no-op.
  func finalizeStrandedComposition() {
    let currentInputSourceID = XpierInstaller.currentInputSourceID() ?? ""
    guard !currentInputSourceID.hasPrefix("com.xpier.inputmethod.Xpier") else { return }
    if let inputController = panel?.inputController {
      inputController.deactivateServer(inputController.client())
    }
  }

  func applyStatusIcon(asciiMode: Bool, schemaLabel: String?) {
    guard let button = statusItem?.button else { return }
    if let schemaLabel = schemaLabel, !schemaLabel.isEmpty {
      button.title = schemaLabel
    } else {
      button.title = asciiMode ? "Ａ" : "中"
    }
  }

  func shutdownRime() {
    config?.close()
    rimeAPI.finalize()
  }

  func workspaceWillPowerOff(_: Notification) {
    print("Finalizing before logging out.")
    self.shutdownRime()
  }

  func rimeNeedsReload(_: Notification) {
    print("Reloading rime on demand.")
    self.deploy()
  }

  func rimeNeedsSync(_: Notification) {
    print("Sync rime on demand.")
    self.syncUserData()
  }

  func rimeToggleASCIIMode(_ notification: Notification) {
    guard let mode = notification.object as? String else { return }
    let enableASCII = mode == "ascii"

    if enableASCII {
      NotificationCenter.default.post(name: .init("XpierSetASCIIModeNotification"), object: true)
    } else {
      NotificationCenter.default.post(name: .init("XpierSetASCIIModeNotification"), object: false)
    }
  }

  func rimeGetASCIIMode(_: Notification) {
    NotificationCenter.default.post(name: .init("XpierReportASCIIModeNotification"), object: nil)
  }

  func createDirIfNotExist(path: URL) {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: path.path()) {
      do {
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
      } catch {
        print("Error creating user data directory: \(path.path())")
      }
    }
  }
}

extension NSApplication {
  var xpierAppDelegate: XpierApplicationDelegate {
    self.delegate as! XpierApplicationDelegate
  }
}

// MARK: - FR-3 设置窗口（Shurufa v1 seed）
// 说明：squirrel.custom.yaml 的用户定制在「部署」时由 librime 合并编译，
// 故保存后调用 owner.deploy() 生效（外观含字号/跟随/主题）。
// “保存后不部署即即时生效”的增强路径（改写 build/ 合并产物并重载）留待有 Xcode 环境验证。

extension XpierApplicationDelegate {
  @objc func showSettingsWindow() {
    // 直接开「全部配置项」窗口：设置入口 = 完整设置（所有分组一目了然）。
    // 曾有段时间这里开的是精简版（V6），完整版藏在里面的二级按钮后面，
    // 结果「所有配置都能编辑」在界面上等于不可见。
    XpierSettingsV10.shared.show(owner: self)
  }
}

// MARK: - Xpier v2.0 设置：动态枚举全部配置项

/// 滚动文档视图：以左上角为原点，内容自顶部开始排列（NSView 默认原点在左下）。
final class XpierFlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// 分组卡片：边框和标题都自己画。
///
/// 原先用的是 NSBox(.primary) + titlePosition = .atTop，期望得到 fieldset 那种
/// 「标题嵌在上边框线里」的样子。实际在现行 macOS 上它**根本不画边框** ——
/// 把截图放大到像素级看过，卡片区域除了一行标题之外什么都没有。
/// 所以「标题不在边框中」的真正原因不是位置不对，是压根没有那条线。
///
/// 顺带解决高度问题：内部网格四边都钉死，fittingSize 就是真实高度。
/// 以前是「行数 × 30 + 36」估出来的，比真实值大 30pt 左右，
/// 卡片底部因此空出整整一行 —— 也就是「内容贴着顶、下面很空」的来源。
final class XpierFieldsetView: NSView {
  static let padH: CGFloat = 14        // 左右内边距
  static let padTop: CGFloat = 24      // 标题占的高度，边框线从标题中线穿过
  static let padBottom: CGFloat = 10
  static let titleFontSize: CGFloat = 11

  private let titleText: String?
  private let content: NSView

  init(title: String?, content: NSView, width: CGFloat) {
    self.titleText = title
    self.content = content
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: 40))
    addSubview(content)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padH),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padH),
      content.topAnchor.constraint(equalTo: topAnchor,
                                   constant: title == nil ? 4 : Self.padTop),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padBottom),
    ])
  }
  required init?(coder: NSCoder) { fatalError("不支持归档") }

  override var isFlipped: Bool { true }

  private var titleAttrs: [NSAttributedString.Key: Any] {
    [.font: NSFont.systemFont(ofSize: Self.titleFontSize, weight: .semibold),
     .foregroundColor: NSColor.secondaryLabelColor]
  }

  /// 页面底色。卡片**不填底色**，页面和卡片同色，卡片只靠一圈描边界定。
  ///
  /// 曾经给卡片单独刷过白底、页面刷成浅灰（想做出「卡片浮起来」的效果）。
  /// 结果是三种灰叠在一起：浅灰页面 + 白卡片 + 控件自带的浅灰底
  /// （下拉框、分段按钮的底实测是 236，和我调的页面灰 239 几乎一样），
  /// 看上去就是一块块颜色摞着。所以退回平的：全部同色，只留描边。
  static let pageColor = NSColor.windowBackgroundColor

  override func draw(_ dirtyRect: NSRect) {
    let lw: CGFloat = 1
    // 没有标题的块没有「让位」的高度，线就贴在最上面
    let lineY: CGFloat = titleText == nil ? lw / 2 : Self.padTop / 2
    let rect = NSRect(x: lw / 2, y: lineY,
                      width: bounds.width - lw,
                      height: bounds.height - lineY - lw / 2)
    guard rect.height > 4 else { return }
    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
    NSColor.separatorColor.setStroke()
    path.lineWidth = lw
    path.stroke()

    guard let title = titleText else { return }
    let str = title as NSString
    let size = str.size(withAttributes: titleAttrs)
    let x0 = Self.padH + 2

    // 把标题处的上边线断开，让标题「压」在线上。
    // 卡片不填底色，所以整段断口用同一个页面色盖掉就够了 ——
    // 不必像之前那样分成上下两半各用各的底色。
    Self.pageColor.setFill()
    NSRect(x: x0 - 5, y: lineY - 1.5, width: size.width + 10, height: 3).fill()

    str.draw(at: NSPoint(x: x0, y: lineY - size.height / 2), withAttributes: titleAttrs)
  }
}

/// 数值控件之一：滑杆 + 实时数值。
/// 用于取值范围已知的项（字号、圆角、行距…）。isContinuous = true 才能一边拖
/// 一边看到数值跳，否则要松手才刷新 —— 所谓「没有实时反馈」就是这个问题。
final class XpierKeySlider: NSView {
  private let slider = NSSlider()
  private let readout = NSTextField(labelWithString: "")

  init(value: Int, range: ClosedRange<Int>) {
    super.init(frame: .zero)
    let lo = Double(range.lowerBound), hi = Double(range.upperBound)
    slider.minValue = lo
    slider.maxValue = hi
    slider.doubleValue = Double(min(max(value, range.lowerBound), range.upperBound))
    slider.isContinuous = true
    slider.controlSize = .small
    slider.target = self
    slider.action = #selector(sliderMoved)
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

    readout.stringValue = String(value)
    readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    readout.textColor = .secondaryLabelColor
    readout.alignment = .right
    readout.translatesAutoresizingMaskIntoConstraints = false
    readout.widthAnchor.constraint(equalToConstant: 34).isActive = true
    // 滑杆不限宽会撑满整列（半宽卡片里近 200pt），视觉上巨大。
    // 取 120 定宽 + 小号样式，左边对齐，多余空间留白。
    slider.widthAnchor.constraint(equalToConstant: 120).isActive = true

    let stack = NSStackView(views: [slider, readout])
    stack.orientation = .horizontal
    stack.spacing = 8
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  @objc private func sliderMoved() {
    readout.stringValue = String(intValue)
  }

  /// 告诉网格该拿哪条线去和左边的标签对齐。
  ///
  /// NSGridView 按 firstBaseline 对齐时，对不认识的自定义视图只能退化到用底边，
  /// 结果滑杆整块比标签低 7pt 左右（实测：字号标签在 0.855，它右边的读数在 0.833）。
  /// 这里把读数文本的基线报上去，网格才知道对齐哪儿。
  override var firstBaselineOffsetFromTop: CGFloat {
    guard let sup = readout.superview else { return bounds.height }
    let r = convert(readout.frame, from: sup)
    let f = readout.font ?? NSFont.systemFont(ofSize: 12)
    return r.midY + (f.ascender + f.descender) / 2
  }

  var intValue: Int { Int(slider.doubleValue.rounded()) }
}

/// 数值控件之二：− [数值] ＋。用于范围不确定的项。
/// 原来的实现是 NSStepper + 一个文本框，但步进器根本没接 target/action ——
/// 点它既不更新文本框，保存时又只读文本框，等于完全无效。这里自带回写。
final class XpierKeyStepper: NSView {
  let field = NSTextField()
  private let minus = NSButton()
  private let plus = NSButton()

  init(value: Int) {
    super.init(frame: .zero)
    configure(minus, symbol: "minus", fallback: "−", action: #selector(decrement))
    configure(plus, symbol: "plus", fallback: "＋", action: #selector(increment))

    field.stringValue = String(value)
    field.alignment = .center
    field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(equalToConstant: 58).isActive = true

    let stack = NSStackView(views: [minus, field, plus])
    stack.orientation = .horizontal
    stack.spacing = 4
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  /// 同 XpierKeySlider：自定义视图要自己报基线，否则网格对不齐。
  override var firstBaselineOffsetFromTop: CGFloat {
    guard let sup = field.superview else { return bounds.height }
    let r = convert(field.frame, from: sup)
    let f = field.font ?? NSFont.systemFont(ofSize: 12)
    return r.midY + (f.ascender + f.descender) / 2
  }

  private func configure(_ b: NSButton, symbol: String, fallback: String, action: Selector) {
    b.isBordered = false                 // 无边框：比系统步进器轻得多
    b.bezelStyle = .regularSquare
    b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    b.imagePosition = .imageOnly
    b.contentTintColor = .secondaryLabelColor
    b.title = fallback                   // 取不到符号时退化为文字
    b.target = self
    b.action = action
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 24).isActive = true
    b.heightAnchor.constraint(equalToConstant: 22).isActive = true
  }

  @objc private func decrement() { bump(-1) }
  @objc private func increment() { bump(1) }

  private func bump(_ d: Int) {
    let v = (Int(field.stringValue) ?? 0) + d
    field.stringValue = String(v)        // 立即回写，才有实时反馈
  }

  var stringValue: String { field.stringValue }
}

/// Rime 配色值的解析与写回。
/// Rime 用 0xAABBGGRR（ABGR，和 Windows COLORREF 同序），不是 ARGB！
/// 证据：谷歌主题高亮 0xCE7539 = Google 蓝 (57,117,206)；Solarized 品红
/// 0x8236d3 = (211,54,130)、青 0x98a12a = (42,161,152) —— 全都只在 ABGR 下对得上。
/// 上游 XpierConfig 也是按 ABGR 解析的（alpha,blue,green,red），打字窗一直是对的；
/// 是本文件以前按 ARGB 解析，设置预览和 xpier 自家主题值才跟活见鬼一样对不上
/// （0xffb8aaff 按规范就是粉 (255,170,184)，要淡紫得写 0xffffaab8）。
/// 写回时保留原值的 alpha：取色器只让用户改 RGB，避免把半透明主题改成实心。
enum XpierColor {
  private static func parts(_ hex: String) -> (alpha: UInt32, red: UInt32, green: UInt32, blue: UInt32)? {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
    guard !s.isEmpty, s.count <= 8, let v = UInt32(s, radix: 16) else { return nil }
    // 6 位（无 alpha）与 8 位统一按 BBGGRR 读低 24 位。
    if s.count <= 6 { return (0xff, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff) }
    return ((v >> 24) & 0xff, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff)
  }

  static func fromRime(_ hex: String) -> NSColor {
    guard let p = parts(hex) else { return .labelColor }
    return NSColor(srgbRed: CGFloat(p.red) / 255,
                   green: CGFloat(p.green) / 255,
                   blue: CGFloat(p.blue) / 255,
                   alpha: CGFloat(p.alpha) / 255)
  }

  static func toRime(_ color: NSColor, keepingAlphaOf original: String) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    let alpha = parts(original)?.alpha ?? 0xff
    let r = UInt32(max(0, min(255, (c.redComponent * 255).rounded())))
    let g = UInt32(max(0, min(255, (c.greenComponent * 255).rounded())))
    let b = UInt32(max(0, min(255, (c.blueComponent * 255).rounded())))
    return String(format: "0x%02x%02x%02x%02x", alpha, b, g, r)
  }
}

struct XpierRowSpec {
  let file: String        // squirrel | schema
  let path: String        // 点路径
  let section: String     // 分组
  var type: String        // bool | number | text | theme
  var value: String
}

final class XpierSettingsV10 {
  static let shared = XpierSettingsV10()
  private var wc: XpierSettingsWindowV10?
  func show(owner: XpierApplicationDelegate) {
    if wc == nil { wc = XpierSettingsWindowV10(owner: owner) }
    wc?.show()
  }
}

final class XpierSettingsWindowV10: NSObject, NSWindowDelegate {
  private weak var owner: XpierApplicationDelegate?
  private var window: NSWindow?
  private var tab: NSTabView!
  private var status: NSTextField!
  private var specs: [XpierRowSpec] = []
  private var controls: [String: NSView] = [:]   // key = file|path
  private var themes: [String] = []
  private var themeNames: [String: String] = [:]  // 主题 id → 中文显示名（各预设的 name:）
  private var formatKey: String?   // 候选行模板输入框在 controls 里的键（点插按钮要找它）
  private var themePreviewID: String? = nil   // 主题页当前编辑的主题（nil=当前浅色主题）
  private var builtinThemes: Set<String> = []   // 随包内置主题：name/author 锁定
  private var freshThemeIDs: Set<String> = []   // 新复制的主题 id：整组强制落盘

  /// 候选行模板的合法占位符（见 XpierTheme.candidateFormat，旧写法 %c/%@ 会被自动转写）。
  /// 让用户手打方括号迟早打错（全角括号、中英文混输），所以做成按钮点插。
  private static let formatTokens: [(title: String, token: String, tip: String)] = [
    ("序号", "[label]", "候选前面的编号，如 1. 2. 3."),
    ("候选字", "[candidate]", "候选项本身的文字"),
    ("注释", "[comment]", "候选后面的提示，如五笔编码"),
  ]
  private var builtKeys: [String] = []   // 建窗时的行键集，变化则重建

  init(owner: XpierApplicationDelegate) {
    self.owner = owner
    super.init()
  }

  func show() {
    do {
      // 必须先枚举生效配置：buildWindow() 依赖 specs 才有行可建。
      // 顺序颠倒会得到「零个标签页」的空窗口（即曾经的「一片空白」），
      // 且因 window != nil 而永不自愈。
      loadEffective()
      let keys = specs.map { key($0) }
      if window == nil || keys != builtKeys {
        try buildWindow()
        builtKeys = keys
      }
      applyValues()
      window?.center()
      window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    } catch {
      let a = NSAlert()
      a.messageText = "设置窗口打开失败"
      a.informativeText = "\(error)"
      a.runModal()
    }
  }

  /// 把「当前生效的全部配置项」按标签页导出成 TSV 打印到标准输出。
  ///
  /// 存在的理由：分组表（subGroups）是手写的，而真实条目是解析出来的，
  /// 两者一旦不一致，界面上就会冒出一个装满原始路径的「其他」块 ——
  /// 而且只有肉眼去看才发现得了。tools/gen_settings_doc.py 本来想干这件事，
  /// 但它是另写的一套解析器，早就和 app 走岔了（它数出 371 项，app 实际 425 项）。
  /// 与其维护两份解析器，不如让 app 自己吐数据，分组表对着这份数据核对。
  func dumpRows() {
    loadEffective()
    for s in specs.sorted(by: { ($0.section, $0.path) < ($1.section, $1.path) }) {
      print([s.section, s.file, s.path, s.type, s.value].joined(separator: "\t"))
    }
  }

  /// 把每个标签页离屏渲染成 PNG。
  ///
  /// 存在的理由：这个界面改了很多轮，每一轮我都只能用「推演一遍布局代码」
  /// 的方式自证，看不到真实渲染结果 —— 于是反复出现「你说没变、我说改了」
  /// 的死循环，最后还得靠你截图。有了这个开关，改完之后我自己就能看图，
  /// 布局有没有挤爆、控件有没有被裁掉，一眼就知道。
  ///
  /// 仅供开发用：不进交互流程，靠 --settings-shot 触发。
  func exportScreenshots(to dir: URL) throws {
    loadEffective()
    try buildWindow()
    builtKeys = specs.map { key($0) }
    applyValues()

    guard let win = window else { return }
    // 必须真的把窗口显示出来。试过挪到屏幕外(x=-30000)再 orderFront：
    // AppKit 会跳过「整窗不可见」时的绘制，截出来只有边框和零星文字，
    // 底色全是透明的 —— 看着像布局坏了，其实只是没画。
    // 代价是屏幕上会闪一下设置窗口，这是开发用的开关，可以接受。
    win.setFrameOrigin(NSPoint(x: 40, y: 40))
    win.orderFront(nil)
    defer { win.orderOut(nil) }

    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    // 固定用浅色外观出图：不然在深色模式下截出来是一片黑，
    // 既没法看也没法 OCR，「这一版到底长什么样」又变成玄学。
    win.appearance = NSAppearance(named: .aqua)

    func dump(_ v: NSView, _ name: String) throws {
      v.layoutSubtreeIfNeeded()
      let b = v.bounds
      guard b.width >= 1, b.height >= 1,
            let rep = v.bitmapImageRepForCachingDisplay(in: b) else { return }
      rep.size = b.size
      v.cacheDisplay(in: b, to: rep)

      // cacheDisplay 出来的是透明底（窗口自身的背景不参与绘制），
      // 需要自己合成到不透明白底上，否则文字等于画在虚空里。
      // 用纯 CoreGraphics 做：先前用 NSGraphicsContext.current + NSRect.fill()
      // 合成的版本在离屏场景下静默无效，输出的 PNG 跟没合成一模一样。
      guard let cg = rep.cgImage else { return }
      let pw = cg.width, ph = cg.height
      guard let ctx = CGContext(data: nil, width: pw, height: ph,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
      ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
      guard let flat = ctx.makeImage() else { return }
      let out = NSBitmapImageRep(cgImage: flat)
      guard let png = out.representation(using: .png, properties: [:]) else { return }
      try png.write(to: dir.appendingPathComponent(name))
      print(String(format: "  %@  %.0f×%.0f  %dpx", name, b.width, b.height, out.pixelsWide))
    }

    // 整窗一张（含标签条，用来核对页数/页名），每页各一张。
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    if let content = win.contentView { try dump(content, "00-整窗.png") }

    for i in 0..<tab.numberOfTabViewItems {
      let item = tab.tabViewItem(at: i)
      tab.selectTabViewItem(item)
      RunLoop.current.run(until: Date().addingTimeInterval(0.08))
      let label = item.label.replacingOccurrences(of: " ", with: "")
      try dump(item.view ?? tab, String(format: "%02d-%@.png", i + 1, label))
    }
  }

  // ---------- 枚举当前生效配置 ----------
  private func loadEffective() {
    specs.removeAll()
    themes.removeAll()
    themeNames.removeAll()
    freshThemeIDs.removeAll()
    let buildDir = XpierApp.userDir.appendingPathComponent("build")

    // 内置主题 id（随包 squirrel.yaml）：name/author 锁定的依据。
    var bundleIDs: [String] = []
    var bundleNames: [String: String] = [:]
    if let sp = Bundle.main.sharedSupportPath {
      parseThemeIDs(URL(fileURLWithPath: sp).appendingPathComponent("squirrel.yaml"),
                    into: &bundleIDs, names: &bundleNames)
    }
    builtinThemes = Set(bundleIDs)
    // 显示列表：已部署的优先（含用户复制的自定义主题），没有退回随包。
    var depIDs: [String] = []
    var depNames: [String: String] = [:]
    let depURL = buildDir.appendingPathComponent("squirrel.yaml")
    if FileManager.default.fileExists(atPath: depURL.path) {
      parseThemeIDs(depURL, into: &depIDs, names: &depNames)
    }
    if depIDs.isEmpty {
      themes = bundleIDs.isEmpty ? ["xpier_default", "xpier_dark"] : bundleIDs
      themeNames = bundleNames
    } else {
      themes = depIDs
      themeNames = depNames
    }

    // 三层全列：外观/常规(squirrel) + 方案(wubi86_jidian) + 通用(default)
    parseFile(buildDir.appendingPathComponent("squirrel.yaml"), file: "squirrel")
    parseFile(buildDir.appendingPathComponent("wubi86_jidian.schema.yaml"), file: "schema")
    parseFile(buildDir.appendingPathComponent("default.yaml"), file: "default")

    // 覆盖 custom 中的已保存值。
    // 顺序很重要：先覆盖、再按层去重。反过来的话，被去重丢掉的那一层里
    // 用户存过的值就找不回对应行了，界面会显示成「没改过」。
    overlayCustom(XpierApp.userDir.appendingPathComponent("squirrel.custom.yaml"), file: "squirrel")
    overlayCustom(XpierApp.userDir.appendingPathComponent("wubi86_jidian.custom.yaml"), file: "schema")
    overlayCustom(XpierApp.userDir.appendingPathComponent("default.custom.yaml"), file: "default")

    dedupeCrossLayer()
  }

  /// 同一个键在多层里各有一份时只留一份。
  ///
  /// 部署后的 default.yaml 与 wubi86_jidian.schema.yaml 里，punctuator 和
  /// recognizer/patterns 是重复的（方案层那份是部署时从 default 继承并解析出来的），
  /// 值目前完全相同。界面会并排显示两条一模一样的行，用户没法知道该改哪一条；
  /// 而且白占一倍空间 —— 标点那页 47 行，其实只有 24 个不同的键。
  /// 保留真正生效的那一层：打字时用的是方案，所以 schema 优先。
  private func dedupeCrossLayer() {
    let rank: [String: Int] = ["schema": 0, "squirrel": 1, "default": 2]
    var best: [String: XpierRowSpec] = [:]
    var order: [String] = []
    for s in specs {
      guard let cur = best[s.path] else {
        best[s.path] = s
        order.append(s.path)
        continue
      }
      if (rank[s.file] ?? 9) < (rank[cur.file] ?? 9) { best[s.path] = s }
    }
    specs = order.compactMap { best[$0] }
  }

  private func parseFile(_ url: URL, file: String) {
    guard let t = try? String(contentsOf: url, encoding: .utf8) else { return }
    var section = ""
    // 容器栈：记录形如 `switch_key:` 这种「只起个名字、自己没有值」的中间层。
    //
    // 这里原来是「一个 sub 字符串 + 缩进判断」，而且 schema 层还无视缩进、
    // 只要 sub 非空就往上拼。后果在部署后的方案文件里暴露得很彻底：
    //   translator:
    //     comment_format:      <- sub 被设成 comment_format
    //       - "xform/.+//"
    //     dictionary: wubi86_jidian   <- sub 没被清掉，于是路径成了
    //                                    translator/comment_format/dictionary
    // 一整个 translator 段的 7 个键全被挂上了不存在的 comment_format/ 前缀。
    // reverse_lookup 的 prefix/suffix、key_binder 的 import_preset 同病。
    // 写回配置时这些键在 Rime 看来根本不存在，改了自然「没反应」。
    // 用栈 + 按缩进出栈，才能正确表达任意深度的嵌套。
    var containers: [(indent: Int, name: String)] = []
    var seqIndent = -1   // 当前列表项的缩进：其内部的键属于列表元素，不是配置项
    // 只挡两类：编译期指令（__build_info）与方案身份元数据（schema_id/name 等，
    // 改了会让方案直接失效）。其余一律放开，保证「所有配置都能编辑」。
    let skipSections: Set<String> = ["__build_info", "schema"]
    for raw in t.components(separatedBy: "\n") {
      let tr = raw.trimmingCharacters(in: .whitespaces)
      if tr.isEmpty || tr.hasPrefix("#") { continue }
      let ind = raw.count - tr.count
      // 列表项本身不是配置项；它内部缩进更深的键（如 switches 下的 reset/states）
      // 只是该元素的字段，必须跳过，否则会产出「switches/reset」这种假配置项。
      if tr.hasPrefix("-") { seqIndent = ind; continue }
      if seqIndent >= 0 {
        if ind > seqIndent { continue }
        seqIndent = -1   // 缩进退回，列表结束
      }
      guard let c = tr.firstIndex(of: ":") else { continue }
      let key = yamlUnquote(String(tr[..<c]).trimmingCharacters(in: .whitespaces))
      var val = String(tr[tr.index(after: c)...]).trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else { continue }

      // 顶格的行分两种：新的段落名，或者顶格的标量。
      // 后者（squirrel.yaml 里的 keyboard_layout / chord_duration /
      // show_notifications_when）以前不会重置 section，被挂到上一个段落名下，
      // 产出 ascii_composer/config_version 这种并不存在的设置项。
      let isTop = (ind == 0)
      if isTop {
        containers.removeAll()
      } else {
        // 缩进不比自己深的容器都已经结束 —— 出栈是路径对不对的关键。
        while let last = containers.last, last.indent >= ind { containers.removeLast() }
      }

      if val.isEmpty {
        if isTop { section = key } else { containers.append((ind, key)) }
        continue
      }
      // 顶格标量确实是设置，只是不属于任何段落：路径就是键本身，分组用本层名字。
      // config_version 是版本标记，不是用户设置，跳过。
      if isTop {
        if key == "config_version" { continue }
        section = ""
      } else if section.isEmpty {
        continue
      }

      // 引号必须在解码前判断：recognizer 的 uppercase 值是 "[A-Z][-_.0-9A-Za-z]*"，
      // 解码后以 "[" 开头，会被下面的流式集合判断误当成结构而整条丢掉。
      // 之前这里就是先解码后判断，于是 uppercase 从来没在界面上出现过。
      let quoted = val.hasPrefix("\"") || val.hasPrefix("'")
      // 去掉行尾注释；值为纯注释时（如 `preedit_format:   # 说明`）整行丢弃，
      // 否则会把注释文字当成可编辑的值写回配置。
      if !quoted {
        if val.hasPrefix("#") { continue }
        if let hash = val.range(of: " #") {
          val = String(val[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if val.isEmpty { continue }
        // 流式映射/序列（如 {a: b, c: d}）：是结构而非叶子设置，
        // 当文本编辑会写出坏 YAML。
        if val.hasPrefix("{") || val.hasPrefix("[") { continue }
      }
      let decoded = yamlUnquote(val)
      if skipSections.contains(section) { continue }
      // __build_info / __patch / __include 是编译期指令，不是用户设置。
      if section.hasPrefix("__") || key.hasPrefix("__") { continue }
      if containers.contains(where: { $0.name.hasPrefix("__") }) { continue }
      // 键里含 "/" 的项无法用点路径寻址：Rime 的 patch 路径就以 "/" 作分隔符，
      // 且没有转义写法。例如标点映射里键本身是 "/" 的那两条，写成
      // "punctuator/full_shape//" 会被解析成多一层空键，改不到目标。
      // 这类项只能在 schema 里直接改，不能进界面，否则保存即写坏。
      if key.contains("/") { continue }
      // 顶格标量时 section 为空，过滤掉空段，路径才不会变成 "/keyboard_layout"
      let path = ([section] + containers.map(\.name) + [key])
        .filter { !$0.isEmpty }.joined(separator: "/")
      let type = inferType(path: path, value: decoded)
      // 顶格标量的归属只能靠键名点名（见 topLevelGroups）
      let group = isTop
        ? (Self.topLevelGroups[key] ?? groupTitle(file: file, section: ""))
        : groupTitle(file: file, section: section)
      specs.append(XpierRowSpec(file: file, path: path, section: group,
                                type: type, value: decoded))
    }
  }

  /// YAML 标量解码（双引号转义 + 单引号脱去）。
  /// 必须解码后再展示/写回：像 punctuator 的 `"\\"` 键若带着反斜杠进到路径里，
  /// 写回时再转义一次就变成两个反斜杠，配置直接写坏。
  private func yamlUnquote(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard t.count >= 2, let f = t.first, let l = t.last, f == l else { return t }
    if f == "'" { return String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
    guard f == "\"" else { return t }
    var out = ""
    var escaped = false
    for ch in t.dropFirst().dropLast() {
      if escaped {
        switch ch {
        case "n": out.append("\n")
        case "t": out.append("\t")
        case "r": out.append("\r")
        case "\\": out.append("\\")
        case "\"": out.append("\"")
        default: out.append(ch)
        }
        escaped = false
      } else if ch == "\\" {
        escaped = true
      } else {
        out.append(ch)
      }
    }
    return out
  }

  /// YAML 双引号标量编码，与 yamlUnquote 严格成对，防止键值转义错乱。
  private func yamlQuote(_ s: String) -> String {
    var out = "\""
    for ch in s {
      switch ch {
      case "\\": out += "\\\\"
      case "\"": out += "\\\""
      case "\n": out += "\\n"
      case "\t": out += "\\t"
      case "\r": out += "\\r"
      default: out.append(ch)
      }
    }
    return out + "\""
  }

  /// 标签页归并表。
  /// 标签页归并表。
  /// 原始 YAML 段落很碎（status_icon / menu / key_binder / recognizer 各自只有 1~3 项），
  /// 一段一页就会得到一堆「只有 1 个选项」的标签页。这里按「用户想干什么」归并，
  /// 并且允许跨层合并：selector 只在通用层、recognizer 方案层与通用层都有，
  /// 并到一起后正好顺带消掉了重名标签。
  /// 顶格标量（不属于任何段落）该归到哪一页。
  /// 它们没有段落名可依据，只能逐个点名 —— 注意：决定一项属于哪个标签页的是
  /// 这里，不是 subGroups。往 subGroups 里写一个不属于本页的键是没用的，
  /// 那一项仍然留在原来的页，界面上表现为「分组里明明写了却没有」。
  private static let topLevelGroups: [String: String] = [
    "keyboard_layout": "输入 · 按键 · 方案",
    "chord_duration": "输入 · 按键 · 方案",
    "show_notifications_when": "外观",
  ]

  private func groupTitle(file: String, section: String) -> String {
    // 顶格标量不属于任何段落，归到本层默认页。
    if section.isEmpty {
      return file == "schema" ? "输入 · 按键 · 方案" : "外观"
    }
    switch section {
    case "style", "status_icon":                       return "外观"
    case "speller", "translator", "menu",
         "ascii_composer", "key_binder", "selector",
         "switcher":                                   return "输入 · 按键 · 方案"
    case "punctuator", "tradition":                    return "标点与简繁"
    // wubi_code 是构建期补丁给五笔方案加的编码提示过滤器命名空间
    // （reverse_lookup_filter@wubi_code），语义上属于反查，单独立页没人看得懂。
    case "reverse_lookup", "recognizer", "repeat_last_input",
         "wubi_code":                                     return "反查与造词"
    case "preset_color_schemes":                       return "主题配色"
    case "app_options":                                return "常用 APP 关联"
    default:
      let layer = file == "schema" ? "方案" : (file == "default" ? "通用" : "外观")
      return layer + " · " + section
    }
  }

  /// 标签页顺序（未列出的分组排在其后，按名称排序）。
  private let groupOrder = ["外观", "输入 · 按键 · 方案", "标点与简繁",
                            "反查与造词", "主题配色", "常用 APP 关联"]

  /// 取值有明确范围的数值项：用滑杆而不是步进器 —— 拖起来直观，
  /// 而且能一边拖一边看到数值。没列出的（留白之类的负数、无界值）仍用 −/＋。
  private static let numberRanges: [String: ClosedRange<Int>] = [
    "style/font_point": 8...48,
    "style/corner_radius": 0...40,
    "style/hilited_corner_radius": 0...40,
    "style/border_height": -20...40,
    "style/border_width": -20...40,
    "style/line_spacing": 0...30,
    "style/spacing": 0...30,
    "style/shadow_size": 0...24,
    "menu/page_size": 1...10,
    "speller/max_code_length": 1...8,
    "repeat_last_input/size": 1...20,
    "repeat_last_input/initial_quality": 0...100,
  ]

  /// 取值只有固定几个的项：用下拉菜单。否则用户得自己猜要写哪个单词，
  /// 写错就是一份坏配置。
  private static let choices: [String: [(String, String)]] = [
    // (给用户看的文字, 实际写进配置的值)
    "style/candidate_list_layout": [("横排", "linear"), ("竖排", "stacked")],
    "style/text_orientation": [("横排文字", "horizontal"), ("竖排文字", "vertical")],
    "style/status_message_type": [("长", "long"), ("短", "short"), ("混合", "mix")],
    "ascii_composer/switch_key/Shift_L": XpierSettingsWindowV10.shiftStyles,
    "ascii_composer/switch_key/Shift_R": XpierSettingsWindowV10.shiftStyles,
    "ascii_composer/switch_key/Control_L": XpierSettingsWindowV10.ctrlStyles,
    "ascii_composer/switch_key/Control_R": XpierSettingsWindowV10.ctrlStyles,
    "ascii_composer/switch_key/Caps_Lock": XpierSettingsWindowV10.capsStyles,
    "ascii_composer/switch_key/Eisu_toggle": XpierSettingsWindowV10.capsStyles,
    "selector/bindings/Tab": XpierSettingsWindowV10.selectorActions,
    "selector/bindings/Shift+Tab": XpierSettingsWindowV10.selectorActions,
    "selector/bindings/ISO_Left_Tab": XpierSettingsWindowV10.selectorActions,
    // 分段按钮的每一项都挤在同一个控件宽度里，中文长标签会被截成「…」，
    // 所以这里给两字短名；完整意思由行标签「何时弹提示」和悬停提示补足。
    "show_notifications_when": [("按需", "appropriate"),
                               ("总是", "always"), ("从不", "never")],
    "tradition/opencc_config": [("简体 → 繁体", "s2t.json"),
                                ("简体 → 香港繁体", "s2hk.json"),
                                ("简体 → 台湾正体", "s2tw.json"),
                                ("简体 → 台湾正体（含词汇）", "s2twp.json"),
                                ("繁体 → 简体", "t2s.json"),
                                ("繁体 → 台湾正体", "t2tw.json"),
                                ("繁体 → 香港繁体", "t2hk.json")],
  ]

  private static let shiftStyles: [(String, String)] = [
    ("原样输出编码", "commit_code"), ("上屏首选字", "commit_text"),
    ("转临时英文", "inline_ascii"), ("不处理", "noop"),
  ]
  private static let ctrlStyles: [(String, String)] = [
    ("不处理", "noop"), ("原样输出编码", "commit_code"),
    ("上屏首选字", "commit_text"), ("转临时英文", "inline_ascii"),
  ]
  /// 候选窗里几个键的作用。这两个动作名是 Rime 的固定写法，
  /// 让用户手打 next_candidate 迟早打错。
  private static let selectorActions: [(String, String)] = [
    ("下一个候选", "next_candidate"), ("上一个候选", "previous_candidate"),
  ]
  private static let capsStyles: [(String, String)] = [
    ("清空未上屏编码", "clear"), ("原样输出编码", "commit_code"),
    ("上屏首选字", "commit_text"), ("转临时英文", "inline_ascii"), ("不处理", "noop"),
  ]

  /// 分组后的短名。有二级分组的页只显示短名，完整路径在悬停提示里，
  /// 这样 21 行不会每行都拖着一串 style/ 前缀。
  private static let zhNames: [String: String] = [
    "style/font_face": "字体",
    "style/font_point": "字号",
    "style/color_scheme": "浅色主题",
    "style/color_scheme_dark": "深色主题",
    "style/candidate_list_layout": "候选排列",
    "style/text_orientation": "文字方向",
    "style/line_spacing": "行距",
    "style/spacing": "编码与候选的间距",
    "style/inline_preedit": "编码内嵌显示",
    "style/inline_candidate": "内嵌首选候选",
    "style/mutual_exclusive": "内嵌与候选窗互斥",
    "style/show_paging": "显示翻页箭头",
    "style/corner_radius": "候选窗圆角",
    "style/hilited_corner_radius": "选中项圆角",
    "style/border_height": "上下留白",
    "style/border_width": "左右留白",
    "style/shadow_size": "阴影大小",
    "style/translucency": "候选窗半透明",
    "style/memorize_size": "记住候选窗大小",
    "style/candidate_format": "候选行模板",
    "status_icon/show": "菜单栏中英图标",
    "show_notifications_when": "何时弹提示",
    "keyboard_layout": "英文键盘布局",
    "chord_duration": "和弦按键时长",
    // ---- 输入 · 按键 · 方案 ----
    "speller/max_code_length": "最长编码",
    "speller/auto_select": "唯一候选自动上屏",
    "translator/dictionary": "码表",
    "translator/enable_user_dict": "用户词典（记词频）",
    "translator/enable_charset_filter": "只出常用字",
    "translator/enable_completion": "简码联想",
    "translator/enable_sentence": "整句输入",
    "translator/enable_encoder": "开启自动造词",
    "translator/encode_commit_history": "用已上屏内容造词",
    "menu/page_size": "每页候选数",
    "key_binder/import_preset": "按键绑定预设",
    "switcher/caption": "选单标题",
    "switcher/fold_options": "折叠开关项",
    "switcher/abbreviate_options": "缩写开关项",
    "switcher/option_list_separator": "开关项分隔符",
    "ascii_composer/good_old_caps_lock": "Caps Lock 兼容旧习惯",
    "ascii_composer/switch_key/Shift_L": "左 Shift",
    "ascii_composer/switch_key/Shift_R": "右 Shift",
    "ascii_composer/switch_key/Control_L": "左 Control",
    "ascii_composer/switch_key/Control_R": "右 Control",
    "ascii_composer/switch_key/Caps_Lock": "Caps Lock",
    "ascii_composer/switch_key/Eisu_toggle": "英数键",
    // ---- 标点与简繁 ----
    "tradition/opencc_config": "转换方案",
    "tradition/option_name": "开关名",
    "punctuator/import_preset": "标点预设",
    // ---- 反查与造词 ----
    "reverse_lookup/dictionary": "反查码表",
    "wubi_code/dictionary": "编码提示码表",
    "wubi_code/overwrite_comment": "覆盖原有注释",
    "wubi_code/show_if_input_contains": "含此字符显示编码",
    "reverse_lookup/prefix": "起头字符",
    "reverse_lookup/suffix": "结束字符",
    "repeat_last_input/input": "触发键",
    "repeat_last_input/size": "记住条数",
    "repeat_last_input/initial_quality": "候选权重",
    "recognizer/import_preset": "识别规则预设",
    "recognizer/patterns/reverse_lookup": "反查触发串",
    "recognizer/patterns/email": "邮箱原样上屏",
    "recognizer/patterns/url": "网址原样上屏",
    "recognizer/patterns/uppercase": "全大写原样上屏",
  ]

  /// 逐键配置的中文短名。标点映射和 APP 关联都是「一批同构的键」，
  /// 逐个手写中文名既啰嗦又会随配置变化失配，用规则推。
  private static let appNames: [String: String] = [
    "co.zeit.hyper": "Hyper",
    "com.alfredapp.Alfred": "Alfred",
    "com.apple.Spotlight": "Spotlight",
    "com.apple.Terminal": "终端",
    "com.apple.dt.Xcode": "Xcode",
    "com.barebones.textwrangler": "TextWrangler",
    "com.blacktree.Quicksilver": "Quicksilver",
    "com.github.atom": "Atom",
    "com.google.Chrome": "Chrome",
    "com.googlecode.iterm2": "iTerm2",
    "com.macromates.TextMate.preview": "TextMate",
    "com.microsoft.VSCode": "VS Code",
    "com.microsoft.edgemac": "Edge",
    "com.runningwithcrayons.Alfred-2": "Alfred 2",
    "com.sublimetext.2": "Sublime 2",
    "org.alacritty": "Alacritty",
    "org.gnu.Aquamacs": "Aquamacs",
    "org.gnu.Emacs": "Emacs",
    "org.vim.MacVim": "MacVim",
    "ru.keepcoder.Telegram": "Telegram",
  ]
  /// 勾选框的文字排在固定 136px 的标签列里，超过就会被截成「…」。
  /// 所以这里刻意用两三个字的短名，完整含义靠分块标题和悬停提示补足。
  private static let appOptionNames: [String: String] = [
    "ascii_mode": "英文",
    "no_inline": "不进内嵌",
    "inline": "内嵌",
    "vim_mode": "Vim 模式",
    "force_marked_text_for_direct_commit": "直提交",
  ]

  private func rowLabel(_ path: String) -> String {
    if let n = Self.zhNames[path] { return n }
    let parts = path.split(separator: "/").map(String.init)
    // 标点映射：键本身就是要显示的东西，加个「键」字才不至于看不懂。
    if parts.count == 3, parts[0] == "punctuator",
       parts[1] == "full_shape" || parts[1] == "half_shape" {
      return parts[2] + " 键"
    }
    // 主题配色：一个主题块里十几个颜色，每行都拖一串 preset_color_schemes/xxx/ 前缀没法看。
    if parts.count == 3, parts[0] == "preset_color_schemes" {
      return Self.colorNames[parts[2]] ?? parts[2]
    }
    // APP 关联：com.apple.Terminal 这种反域名叫法放在勾选框里太占地方，
    // 换成软件短名，完整包名保留在悬停提示里。
    if parts.count == 3, parts[0] == "app_options" {
      let app = Self.appNames[parts[1]] ?? parts[1]
      let opt = Self.appOptionNames[parts[2]] ?? parts[2]
      return app + " · " + opt
    }
    return parts.last ?? ""
  }

  /// 标签页内的二级分组。(标题, 是否半宽, 键列表)。
  /// 半宽块两两并排成瀑布流，整宽块另起一行独占一排。
  ///
  /// 键列表必须与真实解析结果逐字对齐 —— 对不上的项会掉进一个叫「其他」的
  /// 兜底块，里面全是原始路径，而且只有肉眼去看才发现。核对的正确姿势是：
  ///   Xpier.app/Contents/MacOS/Xpier --settings-list > rows.tsv
  /// 这份数据由 app 自己吐出，是唯一的事实来源；早先另写的
  /// tools/gen_settings_doc.py 因为是一套独立解析器，早就和 app 走岔了
  /// （它数出 371 项，app 实际 398 项，还漏了 5 个真实设置）。
  ///
  /// 块序 = 瀑布流装箱顺序，不是阅读顺序，是用 tools 里的模拟脚本挑出来的：
  /// 目标是两列高度尽量相等、总高尽量小。
  /// 例外：外观页的顺序是按「落列」定的 —— 瀑布流把每块放进当前较矮的列，
  /// 所以哪块落左/右由块高度决定。用离屏截图实测过：字体与主题比候选窗布局
  /// 高约 8pt，于是「外观第 3」会落到右列；想要「显示方式＋菜单栏与提示」
  /// 都在右侧，顺序必须是 字体/布局/显示/外观/提示（左＝字体＋外观，
  /// 右＝布局＋显示＋提示）。改块高（如滑杆尺寸）后要重拍截图复核落列。
  private static let subGroups: [String: [(String, Bool, [String])]] = [
    "外观": [
      ("字体与主题", true, ["style/font_face", "style/font_point",
                          "style/color_scheme", "style/color_scheme_dark"]),
      ("候选窗布局", true, ["style/candidate_list_layout", "style/text_orientation",
                           "style/line_spacing", "style/spacing"]),
      ("显示方式", true, ["style/inline_preedit", "style/inline_candidate",
                         "style/mutual_exclusive", "style/show_paging"]),
      ("候选窗外观", true, ["style/corner_radius", "style/hilited_corner_radius",
                            "style/border_height", "style/border_width",
                            "style/shadow_size", "style/translucency",
                            "style/memorize_size", "style/candidate_format"]),
      ("菜单栏与提示", true, ["status_icon/show", "show_notifications_when"]),
    ],
    // 第 2 页是全窗口设置最多的一页（27 项），排下来约 686px > 574px 视口，
    // 底部要滚一点。已经按两列等高（列差 0）排过，再压只能靠合并分组，
    // 那样可读性反而变差。
    // 注：「中英切换按键」现在是半宽 + 下拉（早先是 4 个中文分段按钮并排，
    // 那才需要整宽；改下拉后半宽放得下，注释别信旧的）。
    // 块序同样按落列排过：中英切换放第 6，左侧短的方案选单被挤到右侧。
    // （瀑布流按块高分列，见 subGroups 头注释；改块高后重拍截图复核。）
    "输入 · 按键 · 方案": [
      ("五笔编码", true, ["speller/max_code_length", "speller/auto_select"]),
      ("词库与联想", true, ["translator/dictionary", "translator/enable_user_dict",
                           "translator/enable_charset_filter", "translator/enable_completion",
                           "translator/enable_sentence"]),
      ("自动造词", true, ["translator/enable_encoder", "translator/encode_commit_history"]),
      ("候选窗按键", true, ["selector/bindings/Tab", "selector/bindings/Shift+Tab",
                           "selector/bindings/ISO_Left_Tab"]),
      ("候选与快捷键", true, ["menu/page_size", "key_binder/import_preset"]),
      ("中英切换按键", true, ["ascii_composer/good_old_caps_lock",
                              "ascii_composer/switch_key/Shift_L",
                              "ascii_composer/switch_key/Shift_R",
                              "ascii_composer/switch_key/Control_L",
                              "ascii_composer/switch_key/Control_R",
                              "ascii_composer/switch_key/Caps_Lock",
                              "ascii_composer/switch_key/Eisu_toggle"]),
      ("方案选单", true, ["switcher/caption", "switcher/fold_options",
                         "switcher/abbreviate_options", "switcher/option_list_separator"]),
      ("键盘与和弦", true, ["keyboard_layout", "chord_duration"]),
    ],
    "标点与简繁": [
      ("简繁转换", true, ["tradition/opencc_config", "tradition/option_name"]),
      ("中文标点（全角）", true, ["punctuator/full_shape/\"", "punctuator/full_shape/&",
                                "punctuator/full_shape/(", "punctuator/full_shape/)",
                                "punctuator/full_shape/+", "punctuator/full_shape/-",
                                "punctuator/full_shape/=", "punctuator/full_shape/\\",
                                "punctuator/full_shape/_", "punctuator/full_shape/`",
                                "punctuator/full_shape/~"]),
      ("英文标点（半角）", true, ["punctuator/half_shape/\"", "punctuator/half_shape/#",
                                "punctuator/half_shape/&", "punctuator/half_shape/(",
                                "punctuator/half_shape/)", "punctuator/half_shape/+",
                                "punctuator/half_shape/-", "punctuator/half_shape/=",
                                "punctuator/half_shape/@", "punctuator/half_shape/\\",
                                "punctuator/half_shape/_", "punctuator/half_shape/`"]),
      ("标点预设", true, ["punctuator/import_preset"]),
    ],
    "反查与造词": [
      ("拼音反查", true, ["reverse_lookup/dictionary", "reverse_lookup/prefix",
                         "reverse_lookup/suffix"]),
      // 编码提示：构建期补丁给五笔方案挂的 reverse_lookup_filter@wubi_code。
      // 候选后面跟不跟五笔编码、什么时候跟，全看这三项，一般不用动。
      ("编码提示", true, ["wubi_code/dictionary", "wubi_code/overwrite_comment",
                         "wubi_code/show_if_input_contains"]),
      ("重复上次输入", true, ["repeat_last_input/input", "repeat_last_input/size",
                            "repeat_last_input/initial_quality"]),
      ("特殊串识别", true, ["recognizer/import_preset", "recognizer/patterns/reverse_lookup",
                            "recognizer/patterns/email", "recognizer/patterns/url",
                            "recognizer/patterns/uppercase"]),
    ],
    "常用 APP 关联": [
      ("这些 App 里默认输出英文", true,
       ["app_options/co.zeit.hyper/ascii_mode", "app_options/com.alfredapp.Alfred/ascii_mode",
        "app_options/com.apple.Spotlight/ascii_mode", "app_options/com.apple.Terminal/ascii_mode",
        "app_options/com.apple.dt.Xcode/ascii_mode", "app_options/com.barebones.textwrangler/ascii_mode",
        "app_options/com.blacktree.Quicksilver/ascii_mode", "app_options/com.github.atom/ascii_mode",
        "app_options/com.googlecode.iterm2/ascii_mode", "app_options/com.macromates.TextMate.preview/ascii_mode",
        "app_options/com.microsoft.VSCode/ascii_mode", "app_options/com.runningwithcrayons.Alfred-2/ascii_mode",
        "app_options/com.sublimetext.2/ascii_mode", "app_options/org.gnu.Aquamacs/ascii_mode",
        "app_options/org.gnu.Emacs/ascii_mode", "app_options/org.vim.MacVim/ascii_mode"]),
      ("编码不显示在光标处", true,
       ["app_options/com.apple.Terminal/no_inline", "app_options/com.googlecode.iterm2/no_inline",
        "app_options/org.gnu.Emacs/no_inline", "app_options/org.vim.MacVim/no_inline"]),
      ("强制显示在光标处", true,
       ["app_options/com.google.Chrome/inline", "app_options/com.microsoft.edgemac/inline",
        "app_options/ru.keepcoder.Telegram/inline"]),
      ("其他兼容", true,
       ["app_options/org.vim.MacVim/vim_mode",
        "app_options/org.alacritty/force_marked_text_for_direct_commit"]),
    ],
  ]
  private func hint(for path: String) -> String? {
    if let s = Self.hintTable[path] { return s }
    // 标点映射是一整批同构的键，逐个写提示没意义，按规则生成。
    if path.hasPrefix("punctuator/full_shape/") || path.hasPrefix("punctuator/half_shape/") {
      let k = String(path.split(separator: "/").last ?? "")
      let mode = path.hasPrefix("punctuator/full_shape/") ? "全角（中文标点）" : "半角（英文标点）"
      return "(mode)状态下按 (k) 输出的字符。留空表示不做转换，原样输出"
    }
    if path.hasPrefix("preset_color_schemes/") {
      let leaf = String(path.split(separator: "/").last ?? "")
      if let s = Self.colorHints[leaf] { return s }
      return "该主题的一个颜色值，写法 0xAARRGGBB（AA 是不透明度）"
    }
    if path.hasPrefix("app_options/") {
      let rest = String(path.dropFirst("app_options/".count))
      guard let slash = rest.lastIndex(of: "/") else { return nil }
      let app = String(rest[..<slash])
      let key = String(rest[rest.index(after: slash)...])
      switch key {
      case "ascii_mode": return "在 \(app) 里默认用英文输入（想直接打中文就关掉）"
      case "no_inline": return "在 \(app) 里不把编码显示在光标处，改为显示在候选窗里"
      case "inline": return "在 \(app) 里强制把编码显示在光标处"
      case "vim_mode": return "Vim 模式：按 Esc 回英文"
      case "force_marked_text_for_direct_commit": return "终端类兼容：直接提交，不做内嵌"
      default: return nil
      }
    }
    return nil
  }

  /// 主题配色页的短名。颜色名单独一张表，不和 hint 混用：
  /// hint 是完整说明（一到两句话），标签只要两三个字。
  private static let colorNames: [String: String] = [
    "name": "主题名", "author": "作者", "color_space": "色彩空间",
    "back_color": "背景", "border_color": "描边",
    "text_color": "编码文字", "hilited_text_color": "选中编码文字",
    "hilited_back_color": "选中编码背景",
    "candidate_text_color": "候选文字", "candidate_back_color": "候选背景",
    "hilited_candidate_text_color": "选中候选文字",
    "hilited_candidate_back_color": "选中候选背景",
    "comment_text_color": "注释文字", "hilited_comment_text_color": "选中注释文字",
    "label_color": "序号颜色", "hilited_candidate_label_color": "选中序号颜色",
    "corner_radius": "圆角", "hilited_corner_radius": "选中圆角",
    "border_height": "上下留白", "border_width": "左右留白",
    "line_spacing": "行距", "spacing": "编码与候选间距", "shadow_size": "阴影",
    "translucency": "半透明", "alpha": "不透明度",
    "mutual_exclusive": "内嵌与候选窗互斥", "memorize_size": "记住候选窗大小",
    "inline_preedit": "编码内嵌", "inline_candidate": "内嵌首选",
    "candidate_list_layout": "候选排列", "text_orientation": "文字方向",
    "candidate_format": "候选行模板", "font_face": "字体", "font_point": "字号",
    "show_paging": "翻页箭头",
  ]

  private static let colorHints: [String: String] = [
    "text_color": "候选窗里「未选中段」的编码文字颜色",
    "hilited_text_color": "候选窗里「选中段」的编码文字颜色",
    "hilited_back_color": "上面这段编码的背景色。不写就没有背景，浅色主题下白字会看不见",
    "candidate_text_color": "未选中候选的文字颜色",
    "candidate_back_color": "未选中候选的背景色（一般留空）",
    "hilited_candidate_text_color": "选中候选的文字颜色",
    "hilited_candidate_back_color": "选中候选的背景色",
    "comment_text_color": "候选后面注释（编码提示等）的颜色",
    "hilited_comment_text_color": "选中候选的注释颜色",
    "label_color": "候选序号颜色（留空则自动混色）",
    "hilited_candidate_label_color": "选中候选的序号颜色",
    "border_color": "候选窗描边颜色",
    "back_color": "候选窗背景色",
    "name": "主题显示名（出现在主题下拉框里）",
    "author": "主题作者",
    "color_space": "取色所用色彩空间，一般留空即 sRGB",
  ]

  private static let hintTable: [String: String] = [
    // ---- 外观 ----
    "style/color_scheme": "浅色主题。下拉里是全部内置预设",
    "style/color_scheme_dark": "系统切到深色时使用的主题",
    "style/font_point": "候选字号（本机最常改的一项）",
    "style/font_face": "候选窗用的字体，从系统已装的字体里选。\n原始写法可以是「字体名」或「字体名-字重」（例：Avenir-Book），\n也可以逗号分隔几个作为回退（例：PingFangSC-Regular,HanaMinB）。\n字体名写错不会报错，只会悄悄退回系统默认字体 —— 所以这里做成了下拉。",
    "style/inline_preedit": "编码直接显示在光标处。注意：这种模式下编码由客户端 App 自己画（用它自己的文字色 + 下划线），主题配色不参与，也无法由本输入法控制",
    "style/inline_candidate": "首选候选也内嵌显示在光标处",
    "style/memorize_size": "记住每个输入框里候选窗的大小",
    "style/mutual_exclusive": "内嵌编码与候选窗只显示其一",
    "style/candidate_list_layout": "linear=候选横排，stacked=候选竖排",
    "style/text_orientation": "候选文字方向：horizontal=横排，vertical=竖排",
    "style/show_paging": "候选窗是否显示翻页箭头",
    "style/corner_radius": "候选窗圆角半径",
    "style/hilited_corner_radius": "选中项高亮块的圆角，0=方角",
    "style/border_height": "候选窗上下留白，负数=按字号自动推算",
    "style/border_width": "候选窗左右留白，负数=按字号自动推算",
    "style/line_spacing": "候选之间的行间距（竖排时最明显）",
    "style/spacing": "编码与候选之间的间距",
    "style/shadow_size": "候选窗阴影大小，0=无阴影",
    "style/translucency": "候选窗背景模糊透出桌面。注意：只有主题背景色带透明度时才看得出变化 —— 默认主题背景不透明，开和关看起来一样",
    "style/alpha": "候选窗整体不透明度，1=不透明",
    "style/candidate_format": "候选行的排版模板：[label] 序号 [candidate] 候选字 [comment] 注释",
    "status_icon/show": "菜单栏是否显示中/英状态小图标",
    "show_notifications_when": "什么时候弹系统提示（部署完成、切换方案之类）",
    "keyboard_layout": "按 Shift 切到英文时用哪个键盘布局。last=上次用过的；default=US/ABC；也可以填自定义布局标识，例如 com.apple.keylayout.USExtended",
    "chord_duration": "和弦打字：多个键几乎同时按下时，判定为「一起按」的时间窗（秒）。普通打字用不到，保持默认即可",
    // ---- 输入 · 按键 · 方案 ----
    "speller/max_code_length": "最长编码长度。五笔=4，即四码上屏。\n记不清某一位编码时可以用 z 顶上（万能键）：只记得 t?fu 就输 tzfu。",
    "speller/auto_select": "编码唯一时自动上屏，不用再按空格/数字",
    "translator/dictionary": "打字用哪张码表。列表是本机 build 目录里已编译好的码表。\n注意：换成别的就不是五笔了（现有的 反查/简繁/标点 设置都是围绕五笔配的）。",
    "translator/enable_charset_filter": "只出常用字，过滤生僻字。\n默认关闭：五笔是精确码，敲对码才出字，生僻字（如 𡋤）可直接打，无需开菜单开关",
    "translator/enable_completion": "显示编码还没打全的词条（联想）。五笔一般保持开启",
    "translator/enable_sentence": "句子输入模式。五笔应保持关闭",
    "translator/enable_user_dict": "用户词典：记录字频词频、自造词。这是「即时调频」的基础，关掉就不记词频了",
    "translator/enable_encoder": "自动造词",
    "translator/encode_commit_history": "把已经上屏的内容自动造成新词",
    "menu/page_size": "每页显示几个候选",
    "ascii_composer/good_old_caps_lock": "兼容老习惯的 Caps Lock 行为",
    "ascii_composer/switch_key/Shift_L": "有编码时按左 Shift 的动作。commit_code=原样输出编码（本机要求）；commit_text=上屏首选字；inline_ascii=转临时英文",
    "ascii_composer/switch_key/Shift_R": "有编码时按右 Shift 的动作，取值含义同上",
    "ascii_composer/switch_key/Caps_Lock": "按 Caps Lock 的动作。clear=清空还没上屏的编码",
    "ascii_composer/switch_key/Control_L": "有编码时按左 Control 的动作。noop=不做任何事",
    "ascii_composer/switch_key/Control_R": "有编码时按右 Control 的动作。noop=不做任何事",
    "ascii_composer/switch_key/Eisu_toggle": "日文键盘才有的键，一般不用管",
    "key_binder/import_preset": "从哪个预设文件继承按键绑定，通常就是 default。\n列表是本机用户目录下的配置文件，换了它等于换一整套翻页/选词按键。",
    "selector/bindings/Tab": "候选窗里按 Tab 做什么",
    "selector/bindings/Shift+Tab": "候选窗里按 Shift+Tab 做什么",
    "selector/bindings/ISO_Left_Tab": "候选窗里按左 Tab（部分键盘）做什么",
    "switcher/caption": "弹出「方案选单」时显示的标题文字",
    "switcher/fold_options": "方案选单里折叠显示开关项",
    "switcher/abbreviate_options": "方案选单里缩写显示开关项",
    "switcher/option_list_separator": "方案选单里分隔开关项的符号",
    // ---- 标点与简繁 ----
    "tradition/opencc_config": "简转繁用哪套 OpenCC 方案。s2hk.json=简体→香港繁体，s2t.json=简体→繁体",
    "tradition/option_name": "对应的开关名，即 switches 里的 zh_trad",
    "punctuator/import_preset": "从哪个预设文件继承标点映射，通常就是 default。\n下面「全角/半角」两栏里没列到的键，都是从这个预设继承来的。",
    "punctuator/full_shape/\\": "全角模式下按 \\ 输出什么",
    "punctuator/half_shape/\\": "半角模式下按 \\ 输出什么",
    // ---- 反查与造词 ----
    "reverse_lookup/dictionary": "反查用哪张码表。五笔里 z 有两个用途，按位置区分：\n  · z 打头（第 1 位）→ 拼音反查：z + 拼音，查出这个字的五笔编码。\n    就是这一项在管。所以保留拼音类码表（luna_pinyin / terra_pinyin / bopomofo…）\n    才有意义，换成 stroke 就成了按笔画查，换成 wubi86_jidian 等于自己查自己。\n  · z 在第 2~4 位 → 万能键：记不清某一位时用 z 顶上。\n    例如只记得 t?fu，就输 tzfu，列出所有形如 t?fu 的词条。这是方案内置的，\n    不在这里配置（见 tools/patch_wubi_wildcard.py）。",
    "reverse_lookup/prefix": "反查的起头字符。设成 z，就是「输 z 起头进入拼音反查」",
    "wubi_code/dictionary": "编码提示回查哪张码表，一般不用动（构建期配好）",
    "wubi_code/overwrite_comment": "候选后面的编码是否覆盖掉原有注释",
    "wubi_code/show_if_input_contains": "输入里含这个字符时，才在候选后面显示编码。默认 z：首位 z 反查和中间 z 万能键都显示，平时打字干净",
    "reverse_lookup/suffix": "反查的结束符。输完拼音再按它才确认",
    "recognizer/import_preset": "从哪个预设文件继承下面这些「特殊串识别」规则，通常就是 default。",
    "recognizer/patterns/reverse_lookup": "多长什么样的串算反查：以 z 开头、后面全是小写字母、结尾可有一个单引号",
    "recognizer/patterns/email": "长成邮箱的串直接原样上屏，不进候选",
    "recognizer/patterns/url": "长成网址的串直接原样上屏",
    "recognizer/patterns/uppercase": "整串大写的直接原样上屏",
    "repeat_last_input/input": "「重复上次输入」的触发键。打完一个词后按它，可把刚才上屏的内容再打一遍",
    "repeat_last_input/size": "记住最近几条上屏内容",
    "repeat_last_input/initial_quality": "它在候选里的排位权重，越大越靠前",
  ]
  /// 取值只能在有限集合里挑、且集合要在运行期才知道的项。
  ///
  /// 这几项原来是普通文本框，这是个设计错误：用户既不知道系统里装了哪些字体、
  /// 有哪些码表可选，也不知道写错的后果 —— 而后果就是 Rime 静默忽略这一项，
  /// 表现成「改了没反应」。所以一律改成下拉，候选值从运行环境里枚举。
  /// 值分别是：f=系统字体族  d=本机已编译的码表  p=可继承的预设文件名。
  private static let pickSources: [String: String] = [
    "style/font_face": "f",
    "translator/dictionary": "d",
    "reverse_lookup/dictionary": "d",
    "wubi_code/dictionary": "d",
    "punctuator/import_preset": "p",
    "key_binder/import_preset": "p",
    "recognizer/import_preset": "p",
  ]

  private func inferType(path: String, value: String) -> String {
    if Self.pickSources[path] != nil { return "pick" }
    if path == "style/color_scheme" || path == "style/color_scheme_dark" { return "theme" }
    // 主题配色：0xAARRGGBB / 0xRRGGBB。只在主题段内判定，避免误伤其它数值。
    if path.hasPrefix("preset_color_schemes/"), value.hasPrefix("0x") { return "color" }
    if Self.choices[path] != nil { return "choice" }
    if value == "true" || value == "false" { return "bool" }
    if Int(value) != nil { return "number" }
    if Double(value) != nil { return "number" }
    return "text"
  }

  private func overlayCustom(_ url: URL, file: String) {
    guard let t = try? String(contentsOf: url, encoding: .utf8) else { return }
    var inManaged = false
    for raw in t.components(separatedBy: "\n") {
      let tr = raw.trimmingCharacters(in: .whitespaces)
      if tr.hasPrefix("# --- Xpier managed begin ---") { inManaged = true; continue }
      if tr.hasPrefix("# --- Xpier managed end ---") { break }
      guard inManaged, let c = tr.firstIndex(of: ":") else { continue }
      let k = yamlUnquote(String(tr[..<c]))
      let v = yamlUnquote(String(tr[tr.index(after: c)...]).trimmingCharacters(in: .whitespaces))
      if let idx = specs.firstIndex(where: { $0.file == file && $0.path == k }) {
        specs[idx].value = v
      }
    }
  }

  /// 从一份 squirrel.yaml 里读预设 id + 各自的 name:（下拉框中文名用）。
  private func parseThemeIDs(_ url: URL, into ids: inout [String], names: inout [String: String]) {
    guard let t = try? String(contentsOf: url, encoding: .utf8) else { return }
    var inPresets = false
    var cur = ""
    for raw in t.components(separatedBy: "\n") {
      if raw.contains("preset_color_schemes:") { inPresets = true; continue }
      guard inPresets else { continue }
      // 遇到下一个一级段落即结束：否则 app_options 下的包名会被当成主题名。
      if !raw.isEmpty && !raw.hasPrefix(" ") && !raw.hasPrefix("#") { break }
      if raw.hasPrefix("  ") && !raw.hasPrefix("    ") && raw.hasSuffix(":") && !raw.contains("#") {
        let k = raw.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        if !k.isEmpty && !ids.contains(k) { ids.append(k) }
        cur = k
        continue
      }
      if !cur.isEmpty && raw.hasPrefix("    name:") {
        let n = yamlUnquote(String(raw.dropFirst("    name:".count)).trimmingCharacters(in: .whitespaces))
        if !n.isEmpty { names[cur] = n }
      }
    }
  }

  /// 内置主题的 name/author 锁定：只能看不能改（改乱了分不清谁是谁）。
  /// 要改就先「复制主题」，副本随便改。
  private func themeFieldLocked(_ spec: XpierRowSpec) -> Bool {
    guard spec.path.hasPrefix("preset_color_schemes/") else { return false }
    let leaf = String(spec.path.split(separator: "/").last ?? "")
    guard leaf == "name" || leaf == "author" else { return false }
    let parts = spec.path.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return false }
    return builtinThemes.contains(parts[1])
  }

  /// 新复制主题的整组强制落盘：saveAll 只写"改过"的项，新增行比不出差异，
  /// 不强制就丢了。成功后也不能清 —— writeManaged 是整块替换，清了的话
  /// 下次保存只写新差异，主题定义就被冲掉了。重开窗口时 loadEffective 会清
  /// （那时行已进 custom.yaml，走正常 diff）。
  private func themeID(of spec: XpierRowSpec) -> String? {
    guard spec.path.hasPrefix("preset_color_schemes/") else { return nil }
    let parts = spec.path.split(separator: "/").map(String.init)
    return parts.count >= 2 ? parts[1] : nil
  }

  // ---------- 构建 UI ----------
  private func key(_ s: XpierRowSpec) -> String { s.file + "|" + s.path }

  /// 枚举候选项。当前值无论如何都保留在列表里（可能带字重后缀、或指向一个
  /// 已经不存在的码表），否则界面会显示成空，用户以为配置丢了。
  private func pickList(_ s: XpierRowSpec) -> [String] {
    var out: [String] = []
    switch Self.pickSources[s.path] {
    case "f":
      // 只列支持中文的字体族：拿「中」(U+4E2D) 试覆盖率。
      // 非中文字体列出来也没有意义 —— 候选窗里全是中文，选了等于没生效，
      // 用户只会觉得「改了没反应」。
      out = NSFontManager.shared.availableFontFamilies.filter { fam in
        guard let f = NSFontManager.shared.font(withFamily: fam, traits: [],
                                                weight: 5, size: 13) else { return false }
        return f.coveredCharacterSet.contains(UnicodeScalar(0x4E2D)!)
      }.sorted()
    case "d":
      out = fileStems(extension: "table.bin")
    case "p":
      out = fileStems(extension: "yaml")
    default:
      break
    }
    if !out.contains(s.value) { out.insert(s.value, at: 0) }
    return out
  }

  /// 主题下拉框的显示名：优先用预设自带的中文名（如「碧水／Aqua」），
  /// 没有才退回 id。存取仍按 id（下拉按序号读写，见 currentValue 的 theme 分支）。
  private func themeTitle(_ id: String) -> String {
    if let n = themeNames[id], !n.isEmpty { return n }
    return id
  }

  /// 字体下拉框的中文名：按系统语言本地化族名（中文系统下如「苹方-简」）。
  /// 存取仍用英文族名（Rime 只认它），下拉按序号读写。无中文名时退回原名；
  /// 当前值若带字重后缀或逗号回退（不在族列表里），也原样显示。
  private func fontTitle(_ family: String) -> String {
    guard let f = NSFontManager.shared.font(withFamily: family, traits: [],
                                            weight: 5, size: 13) else { return family }
    if let loc = CTFontCopyLocalizedName(f as CTFont, kCTFontFamilyNameKey, nil) as? String,
       !loc.isEmpty, loc != family {
      return loc
    }
    return family
  }

  /// 码表/预设下拉的中英对照，显示 "英文（中文）"，存取仍用英文原值（按序号对应）。
  /// 表里没有的新增码表/预设，原样显示英文 id，功能不受影响。
  private static let dictNames: [String: String] = [
    "wubi86_jidian": "五笔86·极点", "pinyin_simp": "简拼",
    "luna_pinyin": "拼音", "cangjie5": "仓颉五代",
    "stroke": "笔画", "terra_pinyin": "地球拼音",
  ]
  private static let presetNames: [String: String] = [
    "default": "默认",
  ]

  private func pickTitle(_ spec: XpierRowSpec, _ value: String) -> String {
    let table: [String: String]?
    switch Self.pickSources[spec.path] {
    case "f": return fontTitle(value)
    case "d": table = Self.dictNames
    case "p": table = Self.presetNames
    default: return value
    }
    guard let z = table?[value], !z.isEmpty else { return value }
    return "\(value)（\(z)）"
  }
  private func fileStems(extension ext: String) -> [String] {
    let dir = XpierApp.userDir.appendingPathComponent("build")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
    let suffix = "." + ext
    return names.filter { $0.hasSuffix(suffix) }
      .map { String($0.dropLast(suffix.count)) }
      .sorted()
  }

  /// 模板点插按钮：把占位符插到模板输入框的光标处（框没焦点就追加末尾）。
  @objc private func insertFormatToken(_ sender: NSButton) {
    guard let token = sender.identifier?.rawValue, !token.isEmpty,
          let k = formatKey,
          let field = controls[k] as? NSTextField else { return }
    // 按钮默认不抢焦点，点按钮时文本框的编辑状态一般还在。
    if let ed = field.currentEditor() as? NSTextView,
       field.window?.firstResponder == ed {
      ed.insertText(token, replacementRange: ed.selectedRange())
    } else {
      field.stringValue += token
    }
  }

  private func makeControl(_ s: XpierRowSpec, narrow: Bool) -> NSView {
    switch s.type {
    case "pick":
      let list = pickList(s)
      let p = NSPopUpButton(frame: .zero, pullsDown: false)
      // 下拉显示中英对照，存取仍用英文原值（按序号对应）。
      p.addItems(withTitles: list.map { pickTitle(s, $0) })
      if let i = list.firstIndex(of: s.value) { p.selectItem(at: i) }
      return p
    case "bool":
      let b = NSButton(checkboxWithTitle: "", target: nil, action: nil)
      b.state = s.value == "false" ? .off : .on
      return b
    case "theme":
      let p = NSPopUpButton(frame: .zero, pullsDown: false)
      p.addItems(withTitles: themes.map { themeTitle($0) })
      p.selectItem(at: max(0, themes.firstIndex(of: s.value) ?? 0))
      return p
    case "choice":
      let list = Self.choices[s.path] ?? []
      let cur = list.firstIndex { $0.1 == s.value } ?? 0
      // 选项少就用分段按钮（一排单选，一眼看全，少一次点击）；
      // 选项多才用下拉，否则一排按钮会撑爆一行。
      //
      // 半宽卡片留给控件的宽度只有 190pt 上下，一个中文选项就要 60~130pt，
      // 三个以上必然被压成「…」。所以窄卡片里只给两个选项以内的用分段按钮。
      let segLimit = narrow ? 2 : 5
      if list.count <= segLimit {
        let seg = NSSegmentedControl(labels: list.map { $0.0 },
                                     trackingMode: .selectOne, target: nil, action: nil)
        seg.selectedSegment = cur
        return seg
      }
      let p = NSPopUpButton(frame: .zero, pullsDown: false)
      p.addItems(withTitles: list.map { $0.0 })
      p.selectItem(at: cur)
      return p
    case "color":
      let well = NSColorWell()
      if #available(macOS 13.0, *) { well.colorWellStyle = .minimal }
      well.color = XpierColor.fromRime(s.value)
      well.translatesAutoresizingMaskIntoConstraints = false
      well.widthAnchor.constraint(equalToConstant: 44).isActive = true
      well.heightAnchor.constraint(equalToConstant: 22).isActive = true
      let hex = NSTextField(labelWithString: s.value)
      hex.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      hex.textColor = .secondaryLabelColor
      hex.tag = 1
      let cbox = NSStackView(views: [well, hex])
      cbox.orientation = .horizontal
      cbox.spacing = 8
      cbox.alignment = .centerY
      return cbox
    case "number":
      if let n = Int(s.value) {
        // 取值范围已知的用滑杆（拖起来直观、能实时看到数值）；
        // 其余用 −/＋ 步进。两者都把改动立刻写回控件，保存时才读得到。
        if let r = Self.numberRanges[s.path] {
          return XpierKeySlider(value: n, range: r)
        }
        return XpierKeyStepper(value: n)
      }
      let tf = NSTextField(string: s.value)
      tf.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
      return tf
    default:
      let tf = NSTextField(string: s.value)
      tf.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
      if themeFieldLocked(s) {
        tf.isEditable = false
        tf.textColor = .secondaryLabelColor
        tf.toolTip = "内置主题的名字/作者锁定不可改；点「复制主题」得到可改副本"
      }
      return tf
    }
  }

  private func buildWindow() throws {
    controls.removeAll()
    formatKey = nil
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 720))
    tab = NSTabView(frame: NSRect(x: 14, y: 80, width: 792, height: 620))
    tab.tabViewType = .topTabsBezelBorder
    tab.autoresizingMask = [.width, .height]   // 窗口放大时标签页跟着长

    var bySection: [String: [XpierRowSpec]] = [:]
    for s in specs { bySection[s.section, default: []].append(s) }
    let order = bySection.keys.sorted { a, b in
      let ia = groupOrder.firstIndex(of: a) ?? groupOrder.count
      let ib = groupOrder.firstIndex(of: b) ?? groupOrder.count
      return ia == ib ? a < b : ia < ib
    }

    for section in order {
      guard let rows = bySection[section], !rows.isEmpty else { continue }
      let item = NSTabViewItem(identifier: section)
      item.label = section
      item.view = makePage(rows, section: section)
      tab.addTabViewItem(item)
    }

    content.addSubview(tab)
    let save = NSButton(title: "保存并部署", target: self, action: #selector(saveAll))
    save.keyEquivalent = "\n"
    save.frame = NSRect(x: 16, y: 24, width: 120, height: 30)
    content.addSubview(save)
    let reset = NSButton(title: "恢复默认", target: self, action: #selector(doReset))
    reset.frame = NSRect(x: 142, y: 24, width: 100, height: 30)
    content.addSubview(reset)
    let redeploy = NSButton(title: "重新部署", target: self, action: #selector(doDeploy))
    redeploy.frame = NSRect(x: 248, y: 24, width: 96, height: 30)
    content.addSubview(redeploy)
    let imp = NSButton(title: "导入词库…", target: self, action: #selector(importDict))
    imp.frame = NSRect(x: 350, y: 24, width: 104, height: 30)
    content.addSubview(imp)
    let exp = NSButton(title: "导出备份…", target: self, action: #selector(exportDict))
    exp.frame = NSRect(x: 460, y: 24, width: 104, height: 30)
    content.addSubview(exp)
    status = NSTextField(labelWithString: "就绪 · 构建 \(buildStamp)")
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    status.frame = NSRect(x: 578, y: 30, width: 226, height: 18)
    content.addSubview(status)

    let win = NSWindow(contentRect: content.frame,
                       styleMask: [.titled, .closable, .resizable],
                       backing: .buffered, defer: false)
    // 标题里带构建时间：一眼就能确认「跑的是不是新版本」。
    win.title = "设置（全部配置项）· 构建 \(buildStamp)"
    win.contentView = content
    // 底部按钮是固定坐标，窗口再小就会被裁掉，所以下限给足。
    win.minSize = NSSize(width: 830, height: 520)
    for v in content.subviews where v !== tab {
      v.autoresizingMask = [.minYMargin]   // 按钮/状态栏始终贴底
    }
    win.isReleasedWhenClosed = false
    win.delegate = self
    window = win
  }

  // 每页：滚动视图 + 网格。行数不设上限 —— 需求是「把所有设置都列出来」，
  // 旧实现有 if count > 17 { break } 会静默丢弃后面的配置项。
  /// 页面上的一块：有标题的用 NSBox 画成 fieldset，没标题的就是普通容器。
  /// 页面上的一块：有标题的用 NSBox 画成 fieldset，没标题的就是普通容器。
  ///
  /// 组内排版规则：
  ///   · 勾选框不占一整行 —— 两个并排，各占 50%（一格跨两列，格里两个等宽）
  ///   · 其余项一行一个：[中文名 | 控件]
  /// 旧版把每个勾选框也单独占一行，4 个勾选框就是 4 行，纯属浪费。
  private func makeFieldset(title: String?, rows: [XpierRowSpec], short: Bool,
                            half: Bool, width: CGFloat) -> XpierFieldsetView {
    // 标签列宽：136 大约能放下 9 个 13pt 汉字（含勾选框本身），
    // 再窄就会出现「Telegram · 强制…」这种截断。
    let labelW: CGFloat = half ? 136 : 168
    // 标签与控件同号：以前标签是 12pt、控件是系统默认 13pt，
    // 放在一起就显得控件「偏大」，其实是标签小了一号。
    let labelFont = NSFont.systemFont(ofSize: 13)
    var lineViews: [[NSView]] = []
    var boolBuf: [XpierRowSpec] = []
    var pairRows: [Int] = []   // 勾选框成对的行号，网格建好后跨列 merge
    // 成对勾选框的显式等宽：(块内容宽 − 间距) / 2。实测 plain NSView 包的那层
    // box 不会被网格拉满（只取内容宽），靠拉伸分发(fill)到不了 50%，
    // 只能把宽度写死。块内容宽 = 卡片宽 − 两边内边距。
    let pairW = (width - XpierFieldsetView.padH * 2 - 12) / 2

    func tooltip(_ spec: XpierRowSpec) -> String {
      let origin = spec.file == "schema" ? "方案 wubi86_jidian"
                 : (spec.file == "default" ? "通用 default" : "外观 squirrel")
      return [hint(for: spec.path), "\(origin) · \(spec.path)"]
        .compactMap { $0 }.joined(separator: "\n")
    }

    /// 把攒着的勾选框铺成一行（最多两个）：两个等宽、各占 50%。
    /// 实现上是一格跨两列（行号记到 pairRows，网格建好后 mergeCells），
    /// 格里横向堆两个等宽勾选框。单个落单时不跨列，和原来一样待在标签列。
    func flushBools() {
      guard !boolBuf.isEmpty else { return }
      if boolBuf.count == 1, let r = boolBuf.first {
        let cb = NSButton(checkboxWithTitle: short ? rowLabel(r.path) : r.path,
                          target: nil, action: nil)
        cb.state = r.value == "false" ? .off : .on
        cb.font = labelFont
        cb.lineBreakMode = .byTruncatingTail
        cb.toolTip = tooltip(r)
        controls[key(r)] = cb
        lineViews.append([cb, NSView()])
        boolBuf.removeAll()
        return
      }
      let box = NSView()
      box.translatesAutoresizingMaskIntoConstraints = false
      let row = NSStackView()
      row.orientation = .horizontal
      row.spacing = 12
      row.alignment = .centerY
      // 必须 fill：默认 gravityAreas 只按内容宽摆、多的空间留白，
      // 那样等宽约束只保证两者一样宽，不保证撑满 50%。fill 才平分整行。
      row.distribution = .fill
      row.translatesAutoresizingMaskIntoConstraints = false
      for r in boolBuf {
        let cb = NSButton(checkboxWithTitle: short ? rowLabel(r.path) : r.path,
                          target: nil, action: nil)
        cb.state = r.value == "false" ? .off : .on
        cb.font = labelFont
        cb.lineBreakMode = .byTruncatingTail
        cb.toolTip = tooltip(r)
        cb.translatesAutoresizingMaskIntoConstraints = false
        cb.widthAnchor.constraint(equalToConstant: pairW).isActive = true
        controls[key(r)] = cb
        row.addArrangedSubview(cb)
      }
      box.addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: box.leadingAnchor),
        row.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        row.topAnchor.constraint(equalTo: box.topAnchor),
        row.bottomAnchor.constraint(equalTo: box.bottomAnchor),
      ])
      pairRows.append(lineViews.count)
      // merge 要求行里先有两个格：第二个放空位，合并时吸收掉。
      lineViews.append([box, NSView()])
      boolBuf.removeAll()
    }

    for spec in rows {
      // 候选行模板占两行：输入框一行，点插按钮另起一行。
      // 按钮要引用输入框（点按插入光标处），所以不能包进独立小视图里各自为政；
      // 试过包成 XpierFormatEditor（纵向堆），离屏截图里按钮画不出来
      // （帧/值/层级全对，就是没像素，原因没定位到），拆成两行普通控件最稳。
      if spec.path == "style/candidate_format" {
        flushBools()
        let flabel = NSTextField(labelWithString: short ? rowLabel(spec.path) : spec.path)
        flabel.font = labelFont
        flabel.lineBreakMode = .byTruncatingMiddle
        flabel.toolTip = tooltip(spec)
        let field = NSTextField(string: spec.value)
        field.font = labelFont
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: half ? 150 : 200).isActive = true
        controls[key(spec)] = field
        formatKey = key(spec)
        lineViews.append([flabel, field])
        var bts: [NSView] = []
        for t in Self.formatTokens {
          let b = NSButton(title: "＋" + t.title, target: self, action: #selector(insertFormatToken(_:)))
          b.identifier = NSUserInterfaceItemIdentifier(t.token)
          b.toolTip = t.token + "：" + t.tip + "（点按插入光标处）"
          b.font = .systemFont(ofSize: 11)
          b.bezelStyle = .smallSquare
          bts.append(b)
        }
        let brow = NSStackView(views: bts)
        brow.orientation = .horizontal
        brow.spacing = 8
        brow.alignment = .centerY
        lineViews.append([NSView(), brow])
        continue
      }
      // 只有做过改造的页（有中文名）才并排；其余页保持原样，便于逐页验收。
      if short && spec.type == "bool" {
        boolBuf.append(spec)
        if boolBuf.count == 2 { flushBools() }
        continue
      }
      flushBools()
      let label = NSTextField(labelWithString: short ? rowLabel(spec.path) : spec.path)
      label.font = labelFont
      label.lineBreakMode = .byTruncatingMiddle
      label.toolTip = tooltip(spec)
      let ctl = makeControl(spec, narrow: half)
      ctl.translatesAutoresizingMaskIntoConstraints = false
      ctl.widthAnchor.constraint(greaterThanOrEqualToConstant: half ? 150 : 200).isActive = true
      controls[key(spec)] = ctl
      lineViews.append([label, ctl])
    }
    flushBools()

    let grid = NSGridView(views: lineViews)
    grid.translatesAutoresizingMaskIntoConstraints = false
    // 勾选框成对的行：一格跨两列，两个勾选框各占 50%。
    for r in pairRows {
      grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2),
                      verticalRange: NSRange(location: r, length: 1))
    }
    // 行距 6 → 10：6pt 时相邻两行几乎贴在一起，13pt 的字看着很挤。
    grid.rowSpacing = 10
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .leading
    grid.column(at: 1).xPlacement = .fill
    if short { grid.column(at: 0).width = labelW }
    // 按基线对齐。默认是各格各自靠上，于是「标签 + 带边框的输入框」这一行里，
    // 标签文字会浮在输入框文字的上方 —— 看起来就是没对齐。
    grid.rowAlignment = .firstBaseline

    // 高度交给 Auto Layout：网格四边钉死，外部读 fittingSize 就是真实高度。
    return XpierFieldsetView(title: title, content: grid, width: width)
  }

  /// 主题配色页的切块方式：一个主题一块，两列并排。
  ///
  /// 这一页有 287 项，平铺下来是 8600 多像素的一条长条，找任何一个主题都得
  /// 从头滚到尾。按主题拆成块之后至少有个标题可找，而且拆成两列后总长减半。
  /// 当前正在用的浅色/深色主题排在最前面 —— 最常改的就是它们。
  /// 主题分桶。注意 pinned 必须从全量 specs 里找 color_scheme ——
  /// 以前写在传入的 rows 里找，而传进来的只有主题页的行，永远找不到，
  /// 「当前使用置顶带★」实际从没生效过（截图证实首块是冷漠/Apathy 而不是默认主题）。
  private func themeBuckets(_ rows: [XpierRowSpec])
    -> (order: [String], buckets: [String: [XpierRowSpec]], pinned: [String]) {
    var order: [String] = []
    var buckets: [String: [XpierRowSpec]] = [:]
    for r in rows {
      let parts = r.path.split(separator: "/").map(String.init)
      let theme = parts.count >= 2 ? parts[1] : "（无法识别）"
      if buckets[theme] == nil { order.append(theme) }
      buckets[theme, default: []].append(r)
    }
    var pinned: [String] = []
    for p in ["style/color_scheme", "style/color_scheme_dark"] {
      if let v = specs.first(where: { $0.path == p })?.value,
         buckets[v] != nil, !pinned.contains(v) {
        pinned.append(v)
      }
    }
    return (order, buckets, pinned)
  }

  /// 主题显示名：优先用主题自己的 name（如「冷漠／Apathy」），没有就退回目录名。
  private func themeDisplayName(_ id: String, _ rs: [XpierRowSpec], pinned: [String]) -> String {
    let name = rs.first(where: { $0.path.hasSuffix("/name") })?.value ?? id
    return pinned.contains(id) ? "★ " + name : name
  }

  /// 主题页的编辑块：只放选中主题（整宽，好改），不一次性建 287 个控件。
  /// 打开主题页就卡的原因就是全量渲染。
  private func themeEditorBlocks(_ rows: [XpierRowSpec]) -> [(String?, [XpierRowSpec], Bool)] {
    let (order, buckets, pinned) = themeBuckets(rows)
    let sel: String?
    if let t = themePreviewID, buckets[t] != nil {
      sel = t
    } else {
      sel = pinned.first ?? order.first
    }
    guard let id = sel, let rs = buckets[id] else { return [] }
    themePreviewID = id
    return [(themeDisplayName(id, rs, pinned: pinned), rs, false)]
  }

  /// 主题页顶部的选择卡：主题下拉 + 展开全部 + 静态预览（三行样例）。
  /// 预览颜色字体都取所选主题，缺键层层兜底，写坏了的主题也不会崩。
  private func themeSelectorCard(_ rows: [XpierRowSpec], width: CGFloat) -> XpierFieldsetView? {
    let (order, buckets, pinned) = themeBuckets(rows)
    let shown = pinned + order.filter { !pinned.contains($0) }
    guard !shown.isEmpty else { return nil }
    if themePreviewID == nil || buckets[themePreviewID ?? ""] == nil {
      themePreviewID = pinned.first ?? order.first
    }
    let sel = themePreviewID ?? shown[0]

    let plab = NSTextField(labelWithString: "编辑主题：")
    plab.font = .systemFont(ofSize: 13)
    let pop = NSPopUpButton(frame: .zero, pullsDown: false)
    pop.addItems(withTitles: shown.map {
      guard let rs = buckets[$0] else { return $0 }
      return themeDisplayName($0, rs, pinned: pinned)
    })
    pop.selectItem(at: max(0, shown.firstIndex(of: sel) ?? 0))
    pop.target = self
    pop.action = #selector(themePreviewChanged(_:))
    let cp = NSButton(title: "复制主题",
                      target: self, action: #selector(copyTheme(_:)))
    cp.bezelStyle = .rounded
    cp.toolTip = "复制当前主题为可编辑的自定义主题（名字/作者也可改）"
    cp.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    let top = NSStackView(views: [plab, pop, cp])
    top.orientation = .horizontal
    top.spacing = 8
    top.alignment = .centerY
    top.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [top, themePreviewView(sel, buckets[sel] ?? [], width: width)])
    stack.orientation = .vertical
    stack.spacing = 10
    stack.alignment = .leading
    stack.translatesAutoresizingMaskIntoConstraints = false
    return XpierFieldsetView(title: "主题选择", content: stack, width: width)
  }

  /// 选中主题的静态预览：编码 / 候选 / 高亮候选三行，背景字色都取该主题。
  /// 选中主题的静态预览：编码 / 候选 / 高亮候选三行，背景字色都取该主题。
  /// 几何全显式：外层盒子定宽（调用方给卡片内容宽）定高（label 实测高累加），
  /// 里面的堆只管摆 —— plain NSView/堆在纵向堆里会被压到 0 宽
  /// （勾选框五五开同款教训），靠拉伸到不了全幅；图层底之前也试过画不出来。
  private func themePreviewView(_ id: String, _ rs: [XpierRowSpec], width: CGFloat) -> NSView {
    var v: [String: String] = [:]
    for r in rs {
      v[String(r.path.split(separator: "/").last ?? "")] = r.value
    }
    let back = v["back_color"].map(XpierColor.fromRime) ?? .white
    let text = v["text_color"].map(XpierColor.fromRime) ?? .labelColor
    let cand = v["candidate_text_color"].map(XpierColor.fromRime) ?? text
    let hText = v["hilited_candidate_text_color"].map(XpierColor.fromRime) ?? cand
    let hBack = v["hilited_candidate_back_color"].map(XpierColor.fromRime) ?? back
    let size: CGFloat = v["font_point"].flatMap(Double.init).map { CGFloat($0) } ?? 16
    let font = ((v["font_face"] ?? "").isEmpty ? nil : NSFont(name: v["font_face"] ?? "", size: size))
      ?? .systemFont(ofSize: size)
    func lab(_ s: String, _ c: NSColor, _ bg: NSColor? = nil) -> NSTextField {
      let t = NSTextField(labelWithString: s)
      t.font = font
      t.textColor = c
      if let bg = bg { t.drawsBackground = true; t.backgroundColor = bg }
      return t
    }
    let labs = [lab("tffu", text), lab("1. 等", cand), lab("2. 徒增", hText, hBack)]
    let inner = NSStackView(views: labs)
    inner.orientation = .vertical
    inner.spacing = 4
    inner.alignment = .leading
    inner.translatesAutoresizingMaskIntoConstraints = false
    let box = NSView()
    box.wantsLayer = true
    box.layer?.backgroundColor = back.cgColor
    box.layer?.cornerRadius = 8
    box.translatesAutoresizingMaskIntoConstraints = false
    // 高按内容实测：三行 label 高 + 行距 + 上下边距，大字号主题也撑得下。
    let contentH = labs.reduce(0) { $0 + $1.fittingSize.height } + 8 + 20
    box.widthAnchor.constraint(equalToConstant: width).isActive = true
    box.heightAnchor.constraint(equalToConstant: contentH).isActive = true
    box.addSubview(inner)
    NSLayoutConstraint.activate([
      inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
      inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
      inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
      inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
    ])
    return box
  }

  /// 切主题/展开前，把已渲染主题控件的值写回 specs（只改内存，不落盘），
  /// 否则一切换，未保存的修改就丢了。其余页控件不动，不受影响。
  private func writebackThemeSpecs() {
    for idx in specs.indices {
      let s = specs[idx]
      guard s.path.hasPrefix("preset_color_schemes/"),
            let ctl = controls[key(s)] else { continue }
      specs[idx].value = currentValue(s, ctl)
    }
  }

  /// 只重建主题页：其余页控件原样保留，未保存的修改不受影响。
  private func rebuildThemePage() {
    for spec in specs where spec.section == "主题配色" {
      controls.removeValue(forKey: key(spec))
    }
    let rows = specs.filter { $0.section == "主题配色" }
    guard !rows.isEmpty,
          let idx = tab.tabViewItems.firstIndex(where: { ($0.identifier as? String) == "主题配色" })
    else { return }
    tab.tabViewItems[idx].view = makePage(rows, section: "主题配色")
    applyValues()
  }

  @objc private func themePreviewChanged(_ sender: NSPopUpButton) {
    let rows = specs.filter { $0.section == "主题配色" }
    let (order, buckets, pinned) = themeBuckets(rows)
    let shown = pinned + order.filter { !pinned.contains($0) }
    let i = sender.indexOfSelectedItem
    guard i >= 0, i < shown.count, buckets[shown[i]] != nil else { return }
    writebackThemeSpecs()
    themePreviewID = shown[i]
    rebuildThemePage()
  }

  /// 复制当前主题为自定义主题：新 id 保证唯一，名字默认"原名 副本"，
  /// 作者保留（可改）。新主题整组入库，保存并部署后生效；
  /// 不保存直接关窗口等于没复制。
  @objc private func copyTheme(_ sender: NSButton) {
    writebackThemeSpecs()
    let rows = specs.filter { $0.section == "主题配色" }
    let (_, buckets, _) = themeBuckets(rows)
    guard let src = themePreviewID, let srcRows = buckets[src], !srcRows.isEmpty else { return }
    var nid = src + "_custom", n = 2
    while buckets[nid] != nil { nid = "\(src)_custom\(n)"; n += 1 }
    let srcName = srcRows.first(where: { $0.path.hasSuffix("/name") })?.value ?? src
    var fresh = specs
    for r in srcRows {
      let leaf = String(r.path.split(separator: "/").last ?? "")
      // 取写回后的值：writeback 刚跑过，specs 里已是界面上的值。
      let cur = specs.first(where: { $0.file == r.file && $0.path == r.path })?.value ?? r.value
      fresh.append(XpierRowSpec(file: r.file,
                                path: "preset_color_schemes/\(nid)/\(leaf)",
                                section: r.section,
                                type: r.type,
                                value: leaf == "name" ? srcName + " 副本" : cur))
    }
    specs = fresh
    freshThemeIDs.insert(nid)
    themePreviewID = nid
    rebuildThemePage()
    status.stringValue = "已复制为「\(nid)」，点「保存并部署」后生效"
  }

  /// 标签页内容区宽度。卡片宽度按它算。
  /// 原来是 784，而真正的可视区是 772×574 —— 写大了 12pt，
  /// documentView 因此比 clipView 宽，横向也具备了滚动条件。
  static let pageWidth: CGFloat = 772

  private func makePage(_ rows: [XpierRowSpec], section: String) -> NSView {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.pageWidth, height: 574))
    container.autoresizingMask = [.width, .height]
    guard !rows.isEmpty else { return container }

    // short = 这一页做过「短名 + 勾选框并排」的改造。主题配色页没有 subGroups
    // （它的分块是按主题动态生成的），但同样要用短名，所以单独认一下。
    let short = Self.subGroups[section] != nil || section == "主题配色"

    // 先按用途切块；有分组表的页每组一个 fieldset，未列出的项兜到「其他」。
    var blocks: [(String?, [XpierRowSpec], Bool)] = []   // (标题, 内容, 是否半宽)
    if let groups = Self.subGroups[section] {
      var placed = Set<String>()
      for (title, half, paths) in groups {
        var bucket: [XpierRowSpec] = []
        for p in paths {
          guard let r = rows.first(where: { $0.path == p && !placed.contains(key($0)) }) else { continue }
          bucket.append(r)
          placed.insert(key(r))
        }
        if !bucket.isEmpty { blocks.append((title, bucket, half)) }
      }
      let rest = rows.filter { !placed.contains(key($0)) }
      if !rest.isEmpty { blocks.append(("其他", rest, false)) }
    } else if section == "主题配色" {
      blocks = themeEditorBlocks(rows)
    } else {
      blocks = [(nil, rows, false)]
    }

    let margin: CGFloat = 16
    let gapX: CGFloat = 12
    let gapY: CGFloat = 10
    let pageW = Self.pageWidth
    let innerW = pageW - margin * 2
    let halfW = (innerW - gapX) / 2

    // 两遍走：先把每一块建出来、量出真实高度，再按瀑布流落位。
    //
    // 高度必须实测。以前是「行数 × 30 + 36」估的 —— 那个数字比 NSGridView 的
    // 真实高度大 30pt 上下，于是每张卡片底部都空出整整一行，
    // 视觉上就是「内容贴着顶、下面很空」。
    var built: [(half: Bool, view: XpierFieldsetView, h: CGFloat)] = []
    // 主题页顶部先放一张选择卡（下拉 + 预览），整宽独占一行，后面编辑块顺排。
    if section == "主题配色", let sel = themeSelectorCard(rows, width: innerW) {
      sel.layoutSubtreeIfNeeded()
      built.append((false, sel, ceil(sel.fittingSize.height)))
    }
    for (title, rs, half) in blocks {
      let v = makeFieldset(title: title, rows: rs, short: short, half: half,
                           width: half ? halfW : innerW)
      v.layoutSubtreeIfNeeded()
      let h = ceil(v.fittingSize.height)
      built.append((half, v, h))
    }

    // 瀑布流排布：半宽块放进当前较矮的那一列，整宽块另起一行。
    var colY: [CGFloat] = [margin, margin]
    for (half, v, h) in built {
      if half {
        let c = colY[0] <= colY[1] ? 0 : 1
        v.frame = NSRect(x: margin + (halfW + gapX) * CGFloat(c), y: colY[c],
                         width: halfW, height: h)
        colY[c] += h + gapY
      } else {
        let y = max(colY[0], colY[1])
        v.frame = NSRect(x: margin, y: y, width: innerW, height: h)
        colY = [y + h + gapY, y + h + gapY]
      }
    }

    // 文档高度就是内容高度。以前是 max(container 高度, 内容高度) ——
    // container 写死 590 而可视区只有 574，于是**每页都**至少高 16pt，
    // 竖向滚动条常驻。内容明明放得下也滚。
    let docHeight = max(1, max(colY[0], colY[1]) - gapY + margin)
    let doc = XpierFlippedView(frame: NSRect(x: 0, y: 0, width: pageW, height: docHeight))
    for (_, v, _) in built { doc.addSubview(v) }

    let scroll = NSScrollView(frame: container.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    // 内容比可视区矮时，下方空出来的部分由滚动视图自己填底色。
    // 否则那一条会用另一个颜色，看上去又多出一层。
    scroll.drawsBackground = true
    scroll.backgroundColor = XpierFieldsetView.pageColor
    scroll.documentView = doc
    container.addSubview(scroll)
    return container
  }

  private func applyValues() {
    for spec in specs {
      guard let ctl = controls[key(spec)] else { continue }
      switch spec.type {
      case "bool":
        (ctl as? NSButton)?.state = spec.value == "false" ? .off : .on
      case "theme":
        (ctl as? NSPopUpButton)?.selectItem(at: max(0, themes.firstIndex(of: spec.value) ?? 0))
      case "choice":
        if let list = Self.choices[spec.path],
           let i = list.firstIndex(where: { $0.1 == spec.value }) {
          (ctl as? NSSegmentedControl)?.selectedSegment = i
          (ctl as? NSPopUpButton)?.selectItem(at: i)
        }
      case "color":
        if let stack = ctl as? NSStackView, let well = stack.views.first as? NSColorWell {
          well.color = XpierColor.fromRime(spec.value)
          (stack.views.last as? NSTextField)?.stringValue = spec.value
        }
      case "pick":
        if let p = ctl as? NSPopUpButton {
          let want = pickList(spec)
          if let i = want.firstIndex(of: spec.value) { p.selectItem(at: i) }
        }
      case "number":
        if let s = ctl as? XpierKeyStepper {
          s.field.stringValue = spec.value
        } else if let tf = ctl as? NSTextField {
          tf.stringValue = spec.value
        }
      default:
        (ctl as? NSTextField)?.stringValue = spec.value
      }
    }
  }

  private func currentValue(_ spec: XpierRowSpec, _ ctl: NSView) -> String {
    switch spec.type {
    case "bool":
      return (ctl as? NSButton)?.state == .on ? "true" : "false"
    case "theme":
      let i = (ctl as? NSPopUpButton)?.indexOfSelectedItem ?? 0
      return i >= 0 && i < themes.count ? themes[i] : spec.value
    case "choice":
      guard let list = Self.choices[spec.path], !list.isEmpty else { return spec.value }
      let i = (ctl as? NSSegmentedControl)?.selectedSegment
              ?? (ctl as? NSPopUpButton)?.indexOfSelectedItem ?? -1
      return (i >= 0 && i < list.count) ? list[i].1 : spec.value
    case "color":
      guard let stack = ctl as? NSStackView, let well = stack.views.first as? NSColorWell else { return spec.value }
      return XpierColor.toRime(well.color, keepingAlphaOf: spec.value)
    case "pick":
      // 下拉显示的是中英对照，按序号映回英文原值。
      guard let p = ctl as? NSPopUpButton else { return spec.value }
      let list = pickList(spec)
      let i = p.indexOfSelectedItem
      return (i >= 0 && i < list.count) ? list[i] : spec.value
    case "number":
      if let s = ctl as? XpierKeySlider { return String(s.intValue) }
      if let s = ctl as? XpierKeyStepper {
        return s.stringValue.isEmpty ? spec.value : s.stringValue
      }
      if let tf = ctl as? NSTextField { return tf.stringValue.isEmpty ? spec.value : tf.stringValue }
      return spec.value
    default:
      return (ctl as? NSTextField)?.stringValue ?? spec.value
    }
  }

  @objc private func saveAll() {
    var sqLines: [String] = ["patch:"]
    var wuLines: [String] = ["patch:"]
    var dfLines: [String] = ["patch:"]
    for spec in specs {
      guard let ctl = controls[key(spec)] else { continue }
      let v = currentValue(spec, ctl)
      // 颜色要按「规范化后」比较：0xffffff 与 0xffffffff 是同一个色，
      // 直接比字符串会把没动过的项也当成改动写进 custom.yaml。
      let base = spec.type == "color"
        ? XpierColor.toRime(XpierColor.fromRime(spec.value), keepingAlphaOf: spec.value)
        : spec.value
      // 新复制的主题整组强制写：diff 比不出"新增"，不强制就丢了。
      let fresh = themeID(of: spec).map { freshThemeIDs.contains($0) } ?? false
      if v == base && !fresh { continue }   // 未改动不写
      let quoted = yamlQuote(spec.path)
      switch spec.file {
      case "squirrel":
        sqLines.append("  " + quoted + ": " + wrap(v, type: spec.type))
      case "default":
        dfLines.append("  " + quoted + ": " + wrap(v, type: spec.type))
      default:
        wuLines.append("  " + quoted + ": " + wrap(v, type: spec.type))
      }
    }
    do {
      if sqLines.count > 1 {
        try writeManaged(XpierApp.userDir.appendingPathComponent("squirrel.custom.yaml"), sqLines)
      }
      if wuLines.count > 1 {
        try writeManaged(XpierApp.userDir.appendingPathComponent("wubi86_jidian.custom.yaml"), wuLines)
      }
      if dfLines.count > 1 {
        try writeManaged(XpierApp.userDir.appendingPathComponent("default.custom.yaml"), dfLines)
      }
      status.stringValue = "生效中…"
      owner?.deploy()
      status.stringValue = "已生效 ✓（改了 \(sqLines.count + wuLines.count + dfLines.count - 3) 项）"
    } catch {
      status.stringValue = "保存失败"
    }
  }

  private func wrap(_ v: String, type: String) -> String {
    if type == "bool" || type == "number" || type == "color" { return v }
    // pick 的值来自枚举，仍然是字符串，按文本加引号即可（走下面的 yamlQuote）
    return yamlQuote(v)
  }

  /// 校验一行是否是合法的托管行：「patch:」或「  "键": 值」。
  /// 键必须是完整的双引号标量（内部引号须转义），紧接一个冒号。
  private func isValidManagedLine(_ line: String) -> Bool {
    if line == "patch:" { return true }
    guard line.hasPrefix("  \"") else { return false }
    var idx = line.index(line.startIndex, offsetBy: 3)
    while idx < line.endIndex {
      let ch = line[idx]
      if ch == "\\" {
        idx = line.index(after: idx)
        if idx < line.endIndex { idx = line.index(after: idx) }
        continue
      }
      if ch == "\"" {
        let after = line.index(after: idx)
        return after < line.endIndex && line[after] == ":"
      }
      idx = line.index(after: idx)
    }
    return false
  }

  private func writeManaged(_ url: URL, _ lines: [String]) throws {
    // 落盘前自检：宁可报错不写，也不能写出坏 YAML ——
    // 那会让整个输入法起不来，比「改不动设置」严重得多。
    for line in lines where !isValidManagedLine(line) {
      throw NSError(domain: "Xpier", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "拒绝写入非法配置行：\(line)"])
    }
    let begin = "# --- Xpier managed begin ---"
    let end = "# --- Xpier managed end ---"
    let body = begin + "\n# 由 Xpier 设置维护\n" + lines.joined(separator: "\n") + "\n" + end
    if let existing = try? String(contentsOf: url, encoding: .utf8),
       let b = existing.range(of: begin), let e = existing.range(of: end) {
      try (String(existing[..<b.lowerBound]) + body + "\n" + String(existing[e.upperBound...])).write(to: url, atomically: true, encoding: .utf8)
    } else {
      try body.write(to: url, atomically: true, encoding: .utf8)
    }
  }
  @objc private func doReset() {
    stripManaged(XpierApp.userDir.appendingPathComponent("squirrel.custom.yaml"))
    stripManaged(XpierApp.userDir.appendingPathComponent("wubi86_jidian.custom.yaml"))
    stripManaged(XpierApp.userDir.appendingPathComponent("default.custom.yaml"))
    status.stringValue = "生效中…"
    owner?.deploy()
    loadEffective()
    applyValues()
    status.stringValue = "已恢复默认 ✓"
  }

  /// 只摘掉本程序写入的托管块，保留用户手写在 custom.yaml 里的其它内容。
  /// （旧实现直接删除整个文件，会连带删掉用户自己的定制。）
  private func stripManaged(_ url: URL) {
    guard let t = try? String(contentsOf: url, encoding: .utf8) else { return }
    let begin = "# --- Xpier managed begin ---"
    let end = "# --- Xpier managed end ---"
    guard let b = t.range(of: begin), let e = t.range(of: end) else { return }
    let kept = String(t[..<b.lowerBound]) + String(t[e.upperBound...])
    let trimmed = kept.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "patch:" {
      try? FileManager.default.removeItem(at: url)
    } else {
      try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  /// 构建时间戳（包内可执行文件里最新的 mtime）。
  /// 显示在窗口标题和状态栏，用于一眼确认「现在跑的到底是不是新版本」——
  /// 换包后如果输入法进程没重启，看到的会一直是旧界面，这个戳能立刻暴露出来。
  private var buildStamp: String {
    var newest: Date?
    let exeDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
    if let items = try? FileManager.default.contentsOfDirectory(
      at: exeDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
      for u in items {
        if let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           newest == nil || d > newest! {
          newest = d
        }
      }
    }
    guard let d = newest else { return "未知" }
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm"
    return f.string(from: d)
  }

  @objc private func doDeploy() {
    status.stringValue = "部署中…"
    owner?.deploy()
    status.stringValue = "已重新部署 ✓ · 构建 \(buildStamp)"
  }

  @objc private func importDict() {
    let panel = NSOpenPanel()
    panel.allowedFileTypes = ["txt"]
    panel.beginSheetModal(for: window ?? NSWindow()) { resp in
      guard resp == .OK, let url = panel.url else { return }
      let userDict = XpierApp.userDir.appendingPathComponent("wubi86_jidian_user.dict.yaml")
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
      p.arguments = ["/Users/admin/Server/Shurufa/squirrel-fork/tools/dict_import_export.py", "import", url.path, userDict.path]
      try? p.run()
      p.waitUntilExit()
      self.status.stringValue = p.terminationStatus == 0 ? "导入完成，请点保存并部署" : "导入失败"
    }
  }

  @objc private func exportDict() {
    let userDict = XpierApp.userDir.appendingPathComponent("wubi86_jidian_user.dict.yaml")
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "xpier-userdict.txt"
    panel.beginSheetModal(for: window ?? NSWindow()) { resp in
      guard resp == .OK, let url = panel.url else { return }
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
      let pipe = Pipe()
      p.standardOutput = pipe
      p.arguments = ["/Users/admin/Server/Shurufa/squirrel-fork/tools/dict_import_export.py", "export", userDict.path]
      try? p.run()
      p.waitUntilExit()
      try? pipe.fileHandleForReading.readDataToEndOfFile().write(to: url)
      self.status.stringValue = "已导出 ✓"
    }
  }
}
