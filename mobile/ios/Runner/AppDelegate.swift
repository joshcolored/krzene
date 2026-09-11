import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KrzeneNavigation") {
      registrar.register(KrzeneNavigationFactory(messenger: registrar.messenger()),
                         withId: "krzene/native-navigation")
    }
  }
}

private final class KrzeneNavigationFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    KrzeneNavigationView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}

private final class KrzeneNavigationView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let root: UIView
  private let channel: FlutterMethodChannel
  private let tabBar = UITabBar()

  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    root = UIView(frame: frame)
    channel = FlutterMethodChannel(name: "krzene/native-navigation/\(id)", binaryMessenger: messenger)
    super.init()
    root.backgroundColor = .clear
    root.overrideUserInterfaceStyle = .dark
    // Keep the system appearance and selection indicator: UIKit owns the
    // glass lens, its gesture handling, and its animation between items.
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.tintColor = UIColor(red: 0.9, green: 0.035, blue: 0.08, alpha: 1)
    tabBar.unselectedItemTintColor = .white
    tabBar.itemPositioning = .fill
    root.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: root.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    // Display Search at the right, as in the reference; tags retain Flutter's page indices.
    var items: [UITabBarItem] = []
    for (title, symbol, index) in [("Browse", "house.fill", 0),
                                   ("Library", "books.vertical.fill", 2),
                                   ("Profile", "person.crop.circle.fill", 3),
                                   ("Search", "magnifyingglass", 1)] {
      let image = UIImage(systemName: symbol,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
      let item = UITabBarItem(title: title, image: image, tag: index)
      let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 10, weight: .medium)
      ]
      item.setTitleTextAttributes(titleAttributes, for: .normal)
      item.setTitleTextAttributes(titleAttributes, for: .selected)
      item.accessibilityLabel = title
      items.append(item)
    }
    tabBar.setItems(items, animated: false)
    select((args as? [String: Any])?["index"] as? Int ?? 0)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "select", let index = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.select(index)
      result(nil)
    }
  }

  func view() -> UIView { root }

  private func select(_ index: Int) {
    guard let item = tabBar.items?.first(where: { $0.tag == index }),
          tabBar.selectedItem !== item else { return }
    tabBar.selectedItem = item
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("select", arguments: item.tag)
  }

  deinit { channel.setMethodCallHandler(nil) }
}
