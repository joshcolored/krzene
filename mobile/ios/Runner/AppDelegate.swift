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
      registrar.register(KrzeneGenreMenuFactory(messenger: registrar.messenger()),
                         withId: "krzene/genre-menu")
      registrar.register(KrzeneSearchBarFactory(messenger: registrar.messenger()),
                         withId: "krzene/search-bar")
    }
  }
}

private final class KrzeneSearchBarFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    KrzeneSearchBarView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}

private final class KrzeneSearchBarView: NSObject, FlutterPlatformView, UISearchBarDelegate, UIGestureRecognizerDelegate {
  private let searchBar = UISearchBar()
  private let channel: FlutterMethodChannel
  private var outsideTap: UITapGestureRecognizer?

  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "krzene/search-bar/\(id)", binaryMessenger: messenger)
    super.init()
    searchBar.frame = frame
    searchBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    searchBar.delegate = self
    searchBar.searchBarStyle = .minimal
    searchBar.placeholder = (args as? [String: Any])?["placeholder"] as? String
    searchBar.autocapitalizationType = .none
    searchBar.autocorrectionType = .no
    searchBar.keyboardAppearance = .dark
    searchBar.returnKeyType = .search
    searchBar.searchTextField.backgroundColor = UIColor(white: 0.10, alpha: 1)
    searchBar.searchTextField.textColor = .white
    searchBar.searchTextField.layer.cornerRadius = 16
    searchBar.searchTextField.clipsToBounds = true
    searchBar.accessibilityLabel = "Search every movie and show"
  }

  func view() -> UIView { searchBar }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    channel.invokeMethod("changed", arguments: searchText)
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    searchBar.resignFirstResponder()
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    guard outsideTap == nil, let window = searchBar.window else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
    tap.cancelsTouchesInView = false
    tap.delegate = self
    window.addGestureRecognizer(tap)
    outsideTap = tap
  }

  func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
    if let tap = outsideTap { tap.view?.removeGestureRecognizer(tap) }
    outsideTap = nil
  }

  @objc private func dismissKeyboard() { searchBar.resignFirstResponder() }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard let view = touch.view else { return false }
    return !view.isDescendant(of: searchBar)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

  deinit {
    if let tap = outsideTap { tap.view?.removeGestureRecognizer(tap) }
    channel.setMethodCallHandler(nil)
  }
}

private final class KrzeneGenreMenuFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    KrzeneGenreMenuView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}

private final class KrzeneGenreMenuView: NSObject, FlutterPlatformView {
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel
  private var genres: [String] = []
  private var selected = ""

  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "krzene/genre-menu/\(id)", binaryMessenger: messenger)
    super.init()
    button.frame = frame
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    var configuration = UIButton.Configuration.gray()
    configuration.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = "Choose genre"
    update(args as? [String: Any] ?? [:])
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(values)
      result(nil)
    }
  }

  func view() -> UIView { button }

  private func update(_ values: [String: Any]) {
    genres = values["genres"] as? [String] ?? []
    selected = values["selected"] as? String ?? ""
    var actions = [UIAction(title: "All genres", image: UIImage(systemName: "rectangle.grid.2x2"), state: selected.isEmpty ? .on : .off) { [weak self] _ in
      self?.choose("")
    }]
    actions.append(contentsOf: genres.map { genre in
      UIAction(title: genre, state: genre == selected ? .on : .off) { [weak self] _ in
        self?.choose(genre)
      }
    })
    button.menu = UIMenu(title: "Genres", options: .displayInline, children: actions)
  }

  private func choose(_ genre: String) {
    selected = genre
    update(["genres": genres, "selected": genre])
    channel.invokeMethod("select", arguments: genre)
  }

  deinit { channel.setMethodCallHandler(nil) }
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
    for (title, asset, index) in [("Browse", "NavBrowse", 0),
                                  ("Library", "NavLibrary", 2),
                                  ("Profile", "NavProfile", 3),
                                  ("Search", "NavSearch", 1)] {
      let image = resizedTemplate(named: asset, size: CGSize(width: 18, height: 18))
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

  private func resizedTemplate(named name: String, size: CGSize) -> UIImage? {
    guard let source = UIImage(named: name) else { return nil }
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
      .withRenderingMode(.alwaysTemplate)
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
