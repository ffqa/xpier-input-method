//
//  XpierInputController.swift
//  Xpier
//
//  Created by Leo Liu on 5/7/24.
//

import Carbon
import InputMethodKit

final class XpierInputController: IMKInputController {
  private static let keyRollOver = 50
  private static var unknownAppCnt: UInt = 0

  private weak var client: IMKTextInput?
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  private var lastModifiers: NSEvent.ModifierFlags = .init()
  private var session: RimeSessionId = 0
  private var schemaId: String = ""
  private var inlinePreedit = false
  private var inlineCandidate = false
  private var chordKeyCodes: [UInt32] = .init(repeating: 0, count: XpierInputController.keyRollOver)
  private var chordModifiers: [UInt32] = .init(repeating: 0, count: XpierInputController.keyRollOver)
  private var chordKeyCount: Int = 0
  private var chordTimer: Timer?
  private var chordDuration: TimeInterval = 0
  private var currentApp: String = ""

  // swiftlint:disable:next cyclomatic_complexity
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let event = event else { return false }
    let modifiers = event.modifierFlags
    let changes = lastModifiers.symmetricDifference(modifiers)

    // Return true to consume the key event; return false to pass it to the client app.
    var handled = false

    if session == 0 || !rimeAPI.find_session(session) {
      createSession()
      if session == 0 {
        return false
      }
    }

    self.client ?= sender as? IMKTextInput
    if let app = client?.bundleIdentifier(), currentApp != app {
      currentApp = app
      updateAppOptions()
    }

    switch event.type {
    case .flagsChanged:
      if lastModifiers == modifiers {
        handled = true
        break
      }
      var rimeModifiers: UInt32 = XpierKeycode.osxModifiersToRime(modifiers: modifiers)
      // Some remote desktop tools send flagsChanged with keyCode 0; infer the real modifier key when needed.
      var keyCode = event.keyCode
      if !XpierKeycode.modifierKeycodes.contains(keyCode) {
        guard let inferred = XpierKeycode.inferModifierKeycode(from: changes) else {
          lastModifiers = modifiers
          rimeUpdate()
          handled = true
          break
        }
        keyCode = inferred
      }
      let rimeKeycode: UInt32 = XpierKeycode.osxKeycodeToRime(keycode: keyCode, keychar: nil, shift: false, caps: false)

      if changes.contains(.capsLock) {
        // Rime expects XK_Caps_Lock before the lock mask changes; NSFlagsChanged has already applied it.
        rimeModifiers ^= kLockMask.rawValue
        _ = processKey(rimeKeycode, modifiers: rimeModifiers)
      }

      // Process releases first because some modifier releases arrive with the next keydown.
      var buffer = [(keycode: UInt32, modifier: UInt32)]()
      for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] where changes.contains(flag) {
        if modifiers.contains(flag) {
          buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
        } else {
          buffer.insert((keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue), at: 0)
        }
      }
      for (keycode, modifier) in buffer {
        _ = processKey(keycode, modifiers: modifier)
      }

      lastModifiers = modifiers
      rimeUpdate()

    case .keyDown:
      // Let client apps handle Command shortcuts.
      if modifiers.contains(.command) {
        break
      }

      // 菜单开关的键盘版（Rime 传统键位）：Ctrl+Shift+3=全角形状，Ctrl+Shift+4=输简出繁。
      // 必须走应用侧拦截、进 flipSwitch（落盘+广播+菜单勾三统一），不能用 librime 的
      // key_binder：那条路只写当前会话，不落盘不广播，终端里误触还没处看——
      // 之前「卡在全角退不出」就是它（numbered_mode_switch 已从构建数据里摘掉）。
      // 只认纯 Ctrl+Shift（带 Cmd/Option 的放行，不吃宿主 App 的快捷键）；
      // 按键按 ANSI 位置认（3/4 键位），非常用布局下对不上就当没这功能。
      // 标题里明示快捷键（见 menu()），只写字不设 keyEquivalent（IMK 菜单设了会劫持宿主）。
      if modifiers.contains(.control) && modifiers.contains(.shift)
          && !modifiers.contains(.option) {
        if event.keyCode == kVK_ANSI_3 {
          flipSwitch("full_shape")
          handled = true
          break
        }
        if event.keyCode == kVK_ANSI_4 {
          flipSwitch("zh_trad")
          handled = true
          break
        }
      }

      // 引号配对关：在半角下按引号直出单个（写代码、敲命令不断行）。
      // 只在空闲（无构词）时拦截；构词中交给引擎走配对，不动引擎逻辑。
      // 开关状态走自定义 option quote_pair（引擎不读，只当存身；默认开=配对=现状，
      // 见 switchLogicalDefault + save_options）。不碰全角：中文标点里配对是正经写法。
      // 注意不用 keyCode 而用字符认：非 US 键盘引号不在 3/4 旁边，按字符认才对。
      if !modifiers.contains(.control) && !modifiers.contains(.option),
         let ch = event.charactersIgnoringModifiers, (ch == "\"" || ch == "'"),
         session != 0 && rimeAPI.find_session(session),
         !rimeAPI.get_option(session, "full_shape"),
         !quotePairEnabled(),
         isInputEmpty() {
        commit(string: ch)
        handled = true
        break
      }

      // FR-4b: Ctrl+= 手动置顶最近一次上屏词（需 librime promote_last_commit，已在子模块实现）
      if modifiers.contains(.control) {
        let chars = event.charactersIgnoringModifiers ?? ""
        NSLog("FR4b: ctrl-key chars=[%@] keyCode=%d", chars, event.keyCode)
        if chars == "=" {
          let ok = rimeAPI.promote_last_commit(session)
          NSLog("FR4b: promote_last_commit result=%d", ok ? 1 : 0)
          if ok {
            handled = true
            break
          }
        }
      }

      let keyCode = event.keyCode
      var keyChars = event.charactersIgnoringModifiers
      let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
      if let code = keyChars?.first,
         (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII) {
        keyChars = event.characters
      }
      if let char = keyChars?.first {
        let rimeKeycode = XpierKeycode.osxKeycodeToRime(keycode: keyCode, keychar: char,
                                                           shift: modifiers.contains(.shift),
                                                           caps: modifiers.contains(.capsLock))
        if rimeKeycode != 0 {
          let rimeModifiers = XpierKeycode.osxModifiersToRime(modifiers: modifiers)
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
          rimeUpdate()
        }
      }

    default:
      break
    }

    return handled
  }

  func selectCandidate(_ index: Int) -> Bool {
    let success = rimeAPI.select_candidate_on_current_page(session, index)
    if success {
      rimeUpdate()
    }
    return success
  }

  // swiftlint:disable:next identifier_name
  func page(up: Bool) -> Bool {
    var handled = false
    handled = rimeAPI.change_page(session, up)
    if handled {
      rimeUpdate()
    }
    return handled
  }

  func moveCaret(forward: Bool) -> Bool {
    let currentCaretPos = rimeAPI.get_caret_pos(session)
    guard let input = rimeAPI.get_input(session) else { return false }
    if forward {
      if currentCaretPos <= 0 {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos - 1)
    } else {
      let inputStr = String(cString: input)
      if currentCaretPos >= inputStr.utf8.count {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos + 1)
    }
    rimeUpdate()
    return true
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
  }

  override func activateServer(_ sender: Any!) {
    self.client ?= sender as? IMKTextInput
    var keyboardLayout = NSApp.xpierAppDelegate.config?.getString("keyboard_layout") ?? ""
    if keyboardLayout == "last" || keyboardLayout == "" {
      keyboardLayout = ""
    } else if keyboardLayout == "default" {
      keyboardLayout = "com.apple.keylayout.ABC"
    } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
      keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
    }
    if keyboardLayout != "" {
      client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
    }
    // Activation delivers no flagsChanged event, and NSEvent.modifierFlags
    // only reflects this process's own event stream, so lastModifiers may
    // disagree with the actual Caps Lock state by now. Seed it from the
    // session-wide hardware state; otherwise the next Caps Lock press can
    // compare equal to the stale lastModifiers and be dropped by the
    // early-return in handle().
    if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) {
      lastModifiers.insert(.capsLock)
    } else {
      lastModifiers.remove(.capsLock)
    }
    preedit = ""
    if session != 0 {
      let state = rimeAPI.get_option(session, "ascii_mode")
      let label = rimeAPI.get_state_label_abbreviated(session, "ascii_mode", state, true).asString
      NSApp.xpierAppDelegate.updateStatusIcon(asciiMode: state, schemaLabel: label)
    }
  }

  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    self.client = client as? IMKTextInput
    super.init(server: server, delegate: delegate, client: client)
    createSession()

    NotificationCenter.default.addObserver(
      forName: .init("XpierSetASCIIModeNotification"),
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.handleASCIIModeToggle(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .init("XpierReportASCIIModeNotification"),
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.reportASCIIMode(notification)
    }

    // 菜单开关广播：点菜单的常常是没会话的 controller（菜单栏无焦点），
    // 它只能写盘；正在打字的 controller 收到后就地生效，否则「关了当前框不变」。
    // 只收不发（发只在 flipSwitch），不会循环。
    NotificationCenter.default.addObserver(
      forName: .init("XpierSwitchChangedNotification"),
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.applySwitchBroadcast(notification)
    }
  }

  private func applySwitchBroadcast(_ notification: Notification) {
    guard let info = notification.userInfo,
          let name = info["option"] as? String,
          let value = info["value"] as? Bool,
          session != 0, rimeAPI.find_session(session),
          rimeAPI.get_option(session, name) != value else { return }
    rimeAPI.set_option(session, name, value)
    rimeUpdate(clearReservedComments: true)
  }

  override func deactivateServer(_ sender: Any!) {
    hidePalettes()
    commitComposition(sender)
    client = nil
  }

  override func hidePalettes() {
    NSApp.xpierAppDelegate.panel?.hide()
    super.hidePalettes()
  }

  override func commitComposition(_ sender: Any!) {
    self.client ?= sender as? IMKTextInput
    if session != 0 {
      if let input = rimeAPI.get_input(session) {
        commit(string: String(cString: input))
        rimeAPI.clear_composition(session)
      }
    }
  }

  override func menu() -> NSMenu! {
    // Xpier：普通用户只保留「设置…」；开发工具（部署/日志/同步/Wiki/更新）移入设置页高级区
    // 严禁在此设置 keyEquivalent：输入法菜单会被 IMK 插入宿主 App 的菜单栏，
    // 其快捷键先于 App 自身菜单匹配 —— 曾用 Cmd+, 导致所有 App 的「设置/偏好设置」
    // 被本输入法劫持。默认留空，从输入法菜单点入。
    let setting = NSMenuItem(title: NSLocalizedString("设置…", comment: "Menu item"), action: #selector(showSettings), keyEquivalent: "")
    setting.target = self
    let menu = NSMenu()
    menu.addItem(setting)

    // 打字时随手要切的几个开关，放在这里和「设置…」平级。
    // 这几个以前只能进设置窗口翻半天 —— 而它们的使用时机恰恰是「正打着字，想换个形态」，
    // 藏进设置面板本身就说不通。
    // 名字按「勾上之后是什么」取，不照搬 Rime 的开关名：zh_trad / full_shape
    // 这种叫法没人看得懂，而「输简出繁」一眼就明白。
    // 全角(full_shape)和英文标点(ascii_punct)是正交的两维，不是互斥：
    // 前者管形状（全角半角），后者管标点集中英文哪套。常用组合是
    //「全角+中文标点」和「半角+英文标点」，但四个组合都合法，各管各的。
    // 没有「生僻字」：方案里字符集不过滤（translator/enable_charset_filter: false，
    // 五笔精确码不需要这层过滤），extended_charset 开关已无作用，不放个摆设按钮。
    // 真想滤回常用字，去设置里开「只出常用字」，再用 Ctrl+` 切「常用/扩展」。
    menu.addItem(.separator())
    // 开关项的 action 必须是无参的（与上游/设置项同形）：TextInputMenuAgent
    // 跨进程派发时，带参 action（toggleSwitch:）会被静默吞掉——点了没反应、
    // 不崩溃、无日志，面包屑实测（/tmp/xpier-menu.log）零送达。
    // 所以每个开关一个无参方法，由它指名 option；state 照常显示勾。
    menu.addItem(switchItem("输简出繁 (Ctrl+Shift+4)", option: "zh_trad", action: #selector(toggleTrad)))
    menu.addItem(switchItem("全角形状 (Ctrl+Shift+3)", option: "full_shape", action: #selector(toggleFullShape)))
    menu.addItem(switchItem("英文标点", option: "ascii_punct", action: #selector(toggleAsciiPunct)))
    // 引号配对：开=半角引号也成对（现状），关=半角下直出单个（写代码不断行）。
    // 全角中文里配对是正经写法，不动。默认开，用户关了才直出。
    menu.addItem(switchItem("引号配对", option: "quote_pair", action: #selector(toggleQuotePair)))
    return menu
  }

  private func switchItem(_ title: String, option: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.representedObject = option
    item.state = currentSwitch(option) ? .on : .off
    return item
  }

  @objc func toggleTrad() { flipSwitch("zh_trad") }
  @objc func toggleFullShape() { flipSwitch("full_shape") }
  @objc func toggleAsciiPunct() { flipSwitch("ascii_punct") }
  @objc func toggleQuotePair() { flipSwitch("quote_pair") }

  /// 自定义开关的逻辑默认值（Rime 只认 false，逻辑默认开的只能这里记）。
  /// quote_pair=true 是现状（半角引号也配对），默认保持现状，用户关了才直出。
  private func switchLogicalDefault(_ name: String) -> Bool {
    name == "quote_pair" ? true : false
  }

  /// 新会话把逻辑默认开的自定义开关种进去，否则活会话读出来和菜单显示对不上
  /// （Rime 默认全关）。只种 user.yaml 里没存过的——存过的一律听存盘的。
  private func applySwitchDefaults() {
    guard session != 0 && rimeAPI.find_session(session) else { return }
    for name in ["quote_pair"] where switchLogicalDefault(name) {
      if persistedSwitch(name) == nil {
        rimeAPI.set_option(session, name, true)
      }
    }
  }

  /// 引号配对的当前有效值（活会话读会话；没会话读存盘；都没读逻辑默认）。
  private func quotePairEnabled() -> Bool {
    if session != 0, rimeAPI.find_session(session) {
      return rimeAPI.get_option(session, "quote_pair")
    }
    return persistedSwitch("quote_pair") ?? switchLogicalDefault("quote_pair")
  }

  /// 会话是否空闲（无输入串）。引号直出只在空闲时拦截。
  private func isInputEmpty() -> Bool {
    guard session != 0, let input = rimeAPI.get_input(session) else { return true }
    return String(cString: input).isEmpty
  }

  /// 开关的当前状态。菜单每次弹出都会重新构建，所以这里现读就行，不缓存 ——
  /// 用户可能刚用别的途径（Ctrl+`、设置页）切过，缓存下来就会显示成错的。
  /// 有活会话读会话（最准，含本次还没落盘的）；没会话（菜单栏点开时常常没焦点、
  /// 根本没建会话）读 user.yaml 里存的值；都没就读逻辑默认（quote_pair 默认开）。
  private func currentSwitch(_ name: String) -> Bool {
    if session != 0, rimeAPI.find_session(session) {
      return rimeAPI.get_option(session, name)
    }
    return persistedSwitch(name) ?? switchLogicalDefault(name)
  }

  /// 切换一个 Rime 开关。
  ///
  /// 注意：RimeSetOption 只作用于**当前会话**，librime 只在走 switcher（Ctrl+`选单）
  /// 那条路时才顺手写 user.yaml，调 API 是不落盘的。所以这里双写：有会话就地生效，
  /// 同时写 user.yaml（var/option/<名>，save_options 里有的开关下次建会话会自动读回）。
  /// 没会话（菜单栏无焦点点开）就只写 user.yaml，下次打字即生效 —— 菜单原来这种情况
  /// 直接 return，点了等于没点，这就是「无论怎么点都是简体」的另一半原因
  /// （一半是 zh_trad 的 reset: 0 每次建会话强制掰回简体，见方案注释）。
  /// save_options 现状：full_shape / ascii_punct 本来就有，zh_trad 是补进去的，
  /// 见 tools/patch_save_options.py。
  ///
  /// 开关双写的公共体：有会话就地生效 + 落盘；无会话只落盘，
  /// 再广播给所有活会话就地生效（否则当前打字的框不变，看着像没关掉）。
  private func flipSwitch(_ name: String) {
    let live = session != 0 && rimeAPI.find_session(session)
    let base: Bool = live ? rimeAPI.get_option(session, name)
                          : (persistedSwitch(name) ?? switchLogicalDefault(name))
    let next = !base
    if live {
      rimeAPI.set_option(session, name, next)
      rimeUpdate(clearReservedComments: true)
    }
    persistSwitch(name, value: next)
    NotificationCenter.default.post(
      name: .init("XpierSwitchChangedNotification"),
      object: nil, userInfo: ["option": name, "value": next])
  }

  /// 从 ~/Library/Xpier/user.yaml 读开关存值。没有文件/没有该项返回 nil（调用方按默认关处理）。
  private func persistedSwitch(_ name: String) -> Bool? {
    let url = XpierApp.userDir.appendingPathComponent("user.yaml")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    // 只认 var: → option: 这一条线上的键，不全局搜，避免撞上别处的同名键。
    var scope: Int = 0  // 0=找var 1=找option 2=读值
    for raw in text.components(separatedBy: "\n") {
      if raw.trimmingCharacters(in: .whitespaces).isEmpty || raw.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
      let indent = raw.prefix(while: { $0 == " " }).count
      let stripped = raw.trimmingCharacters(in: .whitespaces)
      if indent == 0 {
        scope = stripped == "var:" ? 1 : 0
        continue
      }
      guard scope > 0 else { continue }
      if indent == 2 {
        scope = stripped == "option:" ? 2 : 1
        continue
      }
      if scope == 2, indent > 2, stripped.hasPrefix(name + ":") {
        let v = stripped.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
        if v == "true" { return true }
        if v == "false" { return false }
        return nil
      }
    }
    return nil
  }

  /// 写开关存值进 user.yaml（行级合并，只动 var/option/<名> 这一行，别的不碰）。
  /// 角落情况：librime 只在切方案时全量 Save() 一次 user.yaml，会丢掉它内存里没有的键
  /// （也就是我们写的这个）。单方案用户基本碰不到切方案，真碰到了重勾一次就行。
  private func persistSwitch(_ name: String, value: Bool) {
    let url = XpierApp.userDir.appendingPathComponent("user.yaml")
    var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n") ?? []
    var scope: Int = 0
    var varIdx: Int? = nil
    var optIdx: Int? = nil
    var done = false
    for i in lines.indices {
      let raw = lines[i]
      if raw.trimmingCharacters(in: .whitespaces).isEmpty || raw.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
      let indent = raw.prefix(while: { $0 == " " }).count
      let stripped = raw.trimmingCharacters(in: .whitespaces)
      if indent == 0 {
        scope = stripped == "var:" ? 1 : 0
        if scope == 1 { varIdx = i }
        continue
      }
      guard scope > 0 else { continue }
      if indent == 2 {
        scope = stripped == "option:" ? 2 : 1
        if scope == 2 { optIdx = i }
        continue
      }
      if scope == 2, indent > 2, stripped.hasPrefix(name + ":") {
        lines[i] = String(raw.prefix(indent)) + "\(name): \(value ? "true" : "false")"
        done = true
        break
      }
    }
    if !done {
      let line = "    \(name): \(value ? "true" : "false")"
      if let o = optIdx {
        lines.insert(line, at: o + 1)
      } else if let v = varIdx {
        lines.insert("  option:", at: v + 1)
        lines.insert(line, at: v + 2)
      } else {
        lines.append("var:")
        lines.append("  option:")
        lines.append(line)
      }
    }
    do {
      try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    } catch {
      NSLog("XpierMenu: persist %@ FAILED: %@", name, String(describing: error))
    }
  }

  @objc func deploy() {
    NSApp.xpierAppDelegate.deploy()
  }

  @objc func syncUserData() {
    NSApp.xpierAppDelegate.syncUserData()
  }

  @objc func openLogFolder() {
    NSApp.xpierAppDelegate.openLogFolder()
  }

  @objc func showSettings() {
    NSApp.xpierAppDelegate.showSettingsWindow()
  }

  @objc func openRimeFolder() {
    NSApp.xpierAppDelegate.openRimeFolder()
  }

  @objc func checkForUpdates() {
    NSApp.xpierAppDelegate.checkForUpdates()
  }

  @objc func openWiki() {
    NSApp.xpierAppDelegate.openWiki()
  }

  private(set) var specialCommentIndices: [ReservedPropertyKey: Set<Int>] = [:]

  func handleReservedProperty(key rawKey: String, value rawValue: String, for sessionId: RimeSessionId) throws(ReservedPropertyError) {
    guard session == sessionId, session != 0, rimeAPI.find_session(session) else { return }
    guard let key = ReservedPropertyKey(rawValue: rawKey) else { throw .unknownInput(rawKey) }
    let parsed = try ReservedPropertyValue.parse(rawValue)
    switch key {
    case .commentHighlight:
      specialCommentIndices[.commentHighlight] = try parsed.indices()
    case .commentWarning:
      specialCommentIndices[.commentWarning] = try parsed.indices()
    case .refreshUI:
      rimeUpdate(clearReservedComments: false)
    }
  }

  deinit {
    destroySession()
  }
}

private extension XpierInputController {

  func onChordTimer(_: Timer) {
    var processedKeys = false
    if chordKeyCount > 0 && session != 0 {
      // Chord typing releases are synthesized after the configured timeout.
      for i in 0..<chordKeyCount {
        let handled = rimeAPI.process_key(session, Int32(chordKeyCodes[i]), Int32(chordModifiers[i] | kReleaseMask.rawValue))
        if handled {
          processedKeys = true
        }
      }
    }
    clearChord()
    if processedKeys {
      rimeUpdate()
    }
  }

  func updateChord(keycode: UInt32, modifiers: UInt32) {
    for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
      return
    }
    if chordKeyCount >= Self.keyRollOver {
      return
    }
    chordKeyCodes[chordKeyCount] = keycode
    chordModifiers[chordKeyCount] = modifiers
    chordKeyCount += 1
    if let timer = chordTimer, timer.isValid {
      timer.invalidate()
    }
    chordDuration = 0.1
    if let duration = NSApp.xpierAppDelegate.config?.getDouble("chord_duration"), duration > 0 {
      chordDuration = duration
    }
    chordTimer = Timer.scheduledTimer(withTimeInterval: chordDuration, repeats: false, block: onChordTimer)
  }

  func clearChord() {
    chordKeyCount = 0
    if let timer = chordTimer {
      if timer.isValid {
        timer.invalidate()
      }
      chordTimer = nil
    }
  }

  func createSession() {
    let app = client?.bundleIdentifier() ?? {
      XpierInputController.unknownAppCnt &+= 1
      return "UnknownApp\(XpierInputController.unknownAppCnt)"
    }()
    print("createSession: \(app)")
    currentApp = app
    session = rimeAPI.create_session()
    schemaId = ""

    if session != 0 {
      updateAppOptions()
      applySwitchDefaults()
    }
  }

  func updateAppOptions() {
    if currentApp == "" {
      return
    }
    if let appOptions = NSApp.xpierAppDelegate.config?.getAppOptions(currentApp) {
      for (key, value) in appOptions {
        print("set app option: \(key) = \(value)")
        rimeAPI.set_option(session, key, value)
      }
    }
    if let reportBundleID = NSApp.xpierAppDelegate.config?.getBool("unsafe/report_bundleid"), reportBundleID {
      currentApp.withCString { name in
        rimeAPI.set_property(session, "client_app", name)
      }
    }
  }

  func destroySession() {
    if session != 0 {
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    clearChord()
  }

  func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    if let panel = NSApp.xpierAppDelegate.panel {
      if panel.linear != rimeAPI.get_option(session, "_linear") {
        rimeAPI.set_option(session, "_linear", panel.linear)
      }
      if panel.vertical != rimeAPI.get_option(session, "_vertical") {
        rimeAPI.set_option(session, "_vertical", panel.vertical)
      }
    }

    let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))

    if !handled {
      let isVimBackInCommandMode = rimeKeycode == XK_Escape || ((rimeModifiers & kControlMask.rawValue != 0) && (rimeKeycode == XK_c || rimeKeycode == XK_C || rimeKeycode == XK_bracketleft))
      if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode") &&
          !rimeAPI.get_option(session, "ascii_mode") {
        rimeAPI.set_option(session, "ascii_mode", true)
      }
    } else {
      let isChordingKey = switch Int32(rimeKeycode) {
      case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R, XK_Shift_L, XK_Shift_R:
        true
      default:
        false
      }
      if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
        updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
      } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
        clearChord()
      }
    }

    return handled
  }

  func rimeConsumeCommittedText() {
    var commitText = RimeCommit.rimeStructInit()
    if rimeAPI.get_commit(session, &commitText) {
      if let text = commitText.text {
        commit(string: String(cString: text))
      }
      _ = rimeAPI.free_commit(&commitText)
    }
  }

  // Preserve reserved comment marks when librime requests a UI-only refresh.
  func rimeUpdate(clearReservedComments: Bool = true) {
    if clearReservedComments {
      specialCommentIndices = [:]
    }
    rimeConsumeCommittedText()

    var status = RimeStatus_stdbool.rimeStructInit()
    if rimeAPI.get_status(session, &status) {
      // swiftlint:disable:next identifier_name
      if let schema_id = status.schema_id, schemaId == "" || schemaId != String(cString: schema_id) {
        schemaId = String(cString: schema_id)
        NSApp.xpierAppDelegate.loadSettings(for: schemaId)
        if let panel = NSApp.xpierAppDelegate.panel {
          inlinePreedit = (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline")) || rimeAPI.get_option(session, "inline")
          inlineCandidate = panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
          rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
        }
      }
      _ = rimeAPI.free_status(&status)
    }

    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

      let start = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)), within: preedit) ?? preedit.startIndex
      let end = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)), within: preedit) ?? preedit.startIndex
      let caretPos = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)), within: preedit) ?? preedit.startIndex

      if inlineCandidate {
        var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
        let endOfCandidatePreview = candidatePreview.endIndex
        if inlinePreedit {
          // 左移光標後的情形：
          // preedit:             ^已選某些字[xiang zuo yi dong]|guangbiao$
          // commit_text_preview: ^已選某些字向左移動$
          // candidate_preview:   ^已選某些字[向左移動]|guangbiao$
          // 繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidong$
          // candidate_preview:   ^已選某些字[向左]yidong|guangbiao$
          // 光標移至當前段落最左端的情形：
          // preedit:             ^已選某些字|[xiang zuo yi dong guang biao]$
          // commit_text_preview: ^已選某些字向左移動光標$
          // candidate_preview:   ^已選某些字|[向左移動光標]$
          // 討論：
          // preedit 與 commit_text_preview 中“已選某些字”部分一致
          // 因此，選中範圍即正在翻譯的碼段“向左移動”中，兩者的 start 值一致
          // 光標位置的範圍是 start ..= endOfCandidatePreview
          if caretPos >= end && caretPos < preedit.endIndex {
            // 從 preedit 截取光標後未翻譯的編碼“guangbiao”
            candidatePreview += preedit[caretPos...]
          }
        } else {
          // 翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字[向左???]|$
          // 光標移至當前段落最左端，繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字|[xiang zuo]yidongguangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字|[向左]???$
          // FIXME: add librime APIs to support preview candidate without remaining code.
        }
        // preedit can contain additional prompt text before start:
        // ^(prompt)[selection]$
        let start = min(start, candidatePreview.endIndex)
        let caretPos = caretPos <= start ? caretPos : endOfCandidatePreview
        show(preedit: candidatePreview,
             selRange: NSRange(location: start.utf16Offset(in: candidatePreview),
                               length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
             caretPos: caretPos.utf16Offset(in: candidatePreview))
      } else {
        if inlinePreedit {
          show(preedit: preedit, selRange: NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end)), caretPos: caretPos.utf16Offset(in: preedit))
        } else {
          // Use a full-width space placeholder to prevent iTerm2 from echoing raw preedit;
          // half-width placeholders make the Chinese composition baseline unstable.
          show(preedit: preedit.isEmpty ? "" : "　", selRange: NSRange(location: 0, length: 0), caretPos: 0)
        }
      }

      let numCandidates = Int(ctx.menu.num_candidates)
      var candidates = [String]()
      var comments = [String]()
      for i in 0..<numCandidates {
        let candidate = ctx.menu.candidates[i]
        candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        comments.append(candidate.comment.map { String(cString: $0) } ?? "")
      }
      var labels = [String]()
      // swiftlint:disable identifier_name
      if let select_keys = ctx.menu.select_keys {
        labels = String(cString: select_keys).map { String($0) }
      } else if let select_labels = ctx.select_labels {
        let pageSize = Int(ctx.menu.page_size)
        for i in 0..<pageSize {
          labels.append(select_labels[i].map { String(cString: $0) } ?? "")
        }
      }
      // swiftlint:enable identifier_name
      let page = Int(ctx.menu.page_no)
      let lastPage = ctx.menu.is_last_page

      let selRange = NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end))
      showPanel(preedit: inlinePreedit ? "" : preedit, selRange: selRange, caretPos: caretPos.utf16Offset(in: preedit),
                candidates: candidates, comments: comments, labels: labels, highlighted: Int(ctx.menu.highlighted_candidate_index),
                page: page, lastPage: lastPage)
      _ = rimeAPI.free_context(&ctx)
    } else {
      hidePalettes()
    }
  }

  func commit(string: String) {
    guard let client = client else { return }

    let forceMarkedText =
      session != 0 &&
      rimeAPI.get_option(session, "force_marked_text_for_direct_commit")

    // Direct commits such as full-width punctuation do not necessarily have an
    // active marked-text phase. Some NSTextInputClient implementations require
    // one before accepting insertText.
    if forceMarkedText && preedit.isEmpty && !string.isEmpty {
      let markedText = NSMutableAttributedString(string: string)
      client.setMarkedText(
        markedText,
        selectionRange: NSRange(location: markedText.length, length: 0),
        replacementRange: .empty
      )
    }

    client.insertText(string, replacementRange: .empty)
    preedit = ""
    hidePalettes()
  }

  func show(preedit: String, selRange: NSRange, caretPos: Int) {
    guard let client = client else { return }
    if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
      return
    }

    self.preedit = preedit
    self.caretPos = caretPos
    self.selRange = selRange

    let start = selRange.location
    let attrString = NSMutableAttributedString(string: preedit)
    if start > 0 {
      let attrs = mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))! as! [NSAttributedString.Key: Any]
      attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
    }
    let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)! as! [NSAttributedString.Key: Any]
    attrString.setAttributes(attrs, range: remainingRange)
    client.setMarkedText(attrString, selectionRange: NSRange(location: caretPos, length: 0), replacementRange: .empty)
  }

  // swiftlint:disable:next function_parameter_count
  func showPanel(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted: Int, page: Int, lastPage: Bool) {
    guard let client = client else { return }
    var inputPos = NSRect()
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)
    if let panel = NSApp.xpierAppDelegate.panel {
      panel.position = inputPos
      panel.inputController = self
      panel.update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels,
                   highlighted: highlighted, page: page, lastPage: lastPage, update: true)
    }
  }

  private func handleASCIIModeToggle(_ notification: Notification) {
    guard let enableASCII = notification.object as? Bool else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    rimeAPI.set_option(session, "ascii_mode", enableASCII)
    rimeUpdate()
  }

  private func reportASCIIMode(_: Notification) {
    guard client != nil else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    let isASCIIMode = rimeAPI.get_option(session, "ascii_mode")
    let status = isASCIIMode ? "ascii" : "nascii"

    DistributedNotificationCenter.default().postNotificationName(
      .init("XpierASCIIModeResponse"),
      object: status
    )
  }

}
