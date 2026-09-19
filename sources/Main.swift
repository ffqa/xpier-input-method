//
//  Main.swift
//  Xpier
//
//  Created by Leo Liu on 5/10/24.
//

import Foundation
import InputMethodKit

@main
struct XpierApp {
  static let userDir = if let pwuid = getpwuid(getuid()) {
    URL(fileURLWithFileSystemRepresentation: pwuid.pointee.pw_dir, isDirectory: true, relativeTo: nil).appending(components: "Library", "Xpier")
  } else {
    try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Xpier", isDirectory: true)
  }
  /// 输入法自身的 bundle 路径。
  ///
  /// 这里曾硬编码成 "/Library/Input Methods/Xpier.app"（系统级安装位置），
  /// 而本机是装在 "~/Library/Input Methods/Xpier.app"（用户级）。
  /// 于是 TISRegisterInputSource() 去注册一个根本不存在的路径，macOS 读不到
  /// bundle 里的本地化名字，只能拿路径末段当名字 —— 输入法菜单里显示的
  /// "Xpier - Simplified" 就是这么来的（少了本地化名，退回 CFBundleName/
  /// 路径名，再按 zh-Hans 拼上 "- Simplified"）。
  static let appDir = Bundle.main.bundleURL
  static let logDir = FileManager.default.temporaryDirectory.appending(component: "rime.xpier", directoryHint: .isDirectory)

  // swiftlint:disable:next cyclomatic_complexity
  static func main() {
    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee

    let handled = autoreleasepool {
      let installer = XpierInstaller()
      let args = CommandLine.arguments
      if args.count > 1 {
        switch args[1] {
        case "--quit":
          let bundleId = Bundle.main.bundleIdentifier!
          let runningXpiers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
          runningXpiers.forEach { $0.terminate() }
          return true
        case "--reload":
          // Xpier is a background app, and AppKit suspends distributed-notification delivery to inactive apps;
          // deliverImmediately is required for these notifications to reach Xpier while it stays in the background
          DistributedNotificationCenter.default().postNotificationName(.init("XpierReloadNotification"), object: nil, userInfo: nil, deliverImmediately: true)
          return true
        case "--register-input-source", "--install":
          installer.register()
          return true
        case "--enable-input-source":
          if args.count > 2 {
            let modes = args[2...].map { XpierInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              installer.enable(modes: modes)
              return true
            }
          }
          installer.enable()
          return true
        case "--disable-input-source":
          if args.count > 2 {
            let modes = args[2...].map { XpierInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              installer.disable(modes: modes)
              return true
            }
          }
          installer.disable()
          return true
        case "--select-input-source":
          if args.count > 2, let mode = XpierInstaller.InputMode(rawValue: args[2]) {
            installer.select(mode: mode)
          } else {
            installer.select()
          }
          return true
        case "--build":
          XpierApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_update", comment: ""))
          var builderTraits = RimeTraits.rimeStructInit()
          builderTraits.setCString("rime.xpier-builder", to: \.app_name)
          rimeAPI.setup(&builderTraits)
          rimeAPI.deployer_initialize(nil)
          _ = rimeAPI.deploy()
          return true
        case "--sync":
          DistributedNotificationCenter.default().postNotificationName(.init("XpierSyncNotification"), object: nil, userInfo: nil, deliverImmediately: true)
          return true
        case "--ascii":
          DistributedNotificationCenter.default().postNotificationName(.init("XpierToggleASCIIModeNotification"), object: "ascii", userInfo: nil, deliverImmediately: true)
          return true
        case "--nascii":
          DistributedNotificationCenter.default().postNotificationName(.init("XpierToggleASCIIModeNotification"), object: "nascii", userInfo: nil, deliverImmediately: true)
          return true
        case "--getascii":
          var responseReceived = false
          var asciiStatus = ""
          let observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("XpierASCIIModeResponse"),
            object: nil,
            queue: .main
          ) { notification in
            if let status = notification.object as? String {
              asciiStatus = status
              responseReceived = true
            }
          }
          DistributedNotificationCenter.default().postNotificationName(.init("XpierGetASCIIModeNotification"), object: nil, userInfo: nil, deliverImmediately: true)
          let timeout = Date().addingTimeInterval(2.0)
          while !responseReceived && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
          }
          DistributedNotificationCenter.default().removeObserver(observer)
          if responseReceived {
            print(asciiStatus)
          } else {
            print("nascii")
          }
          return true
        case "--settings-list":
          // 开发用：把当前生效的全部配置项按标签页导出成 TSV。
          XpierSettingsWindowV10(owner: XpierApplicationDelegate()).dumpRows()
          return true
        case "--settings-shot":
          // 开发用：把设置窗口的每一页离屏渲染成 PNG。
          // 主要给「改完界面自己先看一眼」用，不参与正常交互流程。
          let out = URL(fileURLWithPath: args.count > 2 ? args[2] : NSTemporaryDirectory())
          let app = NSApplication.shared
          app.setActivationPolicy(.accessory)
          // 必须设全局外观：只设窗口的 window.appearance 不管用 ——
          // cacheDisplay 绘制时取的是 NSApp 的外观，系统处于深色模式时
          // 截出来整片是黑的，看不出布局。踩过一次，记在这儿。
          app.appearance = NSAppearance(named: .aqua)
          let delegate = XpierApplicationDelegate()
          app.delegate = delegate
          do {
            try XpierSettingsWindowV10(owner: delegate).exportScreenshots(to: out)
            print("截图已写入 \(out.path)")
          } catch {
            print("截图失败：\(error)")
          }
          withExtendedLifetime(delegate) {}
          return true
        case "--help":
          print(helpDoc)
          return true
        default:
          break
        }
      }
      return false
    }
    if handled {
      return
    }

    autoreleasepool {
      let main = Bundle.main
      let connectionName = main.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
      _ = IMKServer(name: connectionName, bundleIdentifier: main.bundleIdentifier!)
      let app = NSApplication.shared
      let delegate = XpierApplicationDelegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)

      // OpenCC uses relative dictionary paths from SharedSupport.
      FileManager.default.changeCurrentDirectoryPath(main.sharedSupportPath!)

      if NSApp.xpierAppDelegate.problematicLaunchDetected() {
        print("Problematic launch detected!")
        let args = ["Problematic launch detected! Xpier may be suffering a crash due to improper configuration. Revert previous modifications to see if the problem recurs."]
        let task = Process()
        task.executableURL = "/usr/bin/say".withCString { dir in
          URL(fileURLWithFileSystemRepresentation: dir, isDirectory: false, relativeTo: nil)
        }
        task.arguments = args
        try? task.run()
      } else {
        NSApp.xpierAppDelegate.setupRime()
        NSApp.xpierAppDelegate.startRime(fullCheck: false)
        NSApp.xpierAppDelegate.loadSettings()
        print("Xpier reporting!")
      }

      app.run()
      print("Xpier is quitting...")
      rimeAPI.finalize()
    }
    return
  }

  static let helpDoc = """
Supported arguments:
Perform actions:
  --quit                     quit all Xpier process
  --reload                   deploy
  --sync                     sync user data
  --build                    build all schemas in current directory
  --ascii                    turn on ASCII mode
  --nascii                   turn off ASCII mode
  --getascii                 get current ASCII mode status
Develop:
  --settings-shot [dir]      render every settings tab to PNG (default: temp dir)
Install Xpier:
  --install, --register-input-source    register input source
  --enable-input-source [source id...]  input source list optional
  --disable-input-source [source id...] input source list optional
  --select-input-source [source id]     input source optional
"""
}
