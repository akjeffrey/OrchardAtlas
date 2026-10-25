import Flutter
import UIKit
import UserNotifications
import GoogleMaps
import CoreLocation
import ImageIO
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let geocoder = CLGeocoder()
  private let photoPicker = OrchardPhotoPicker()
  private let iconPicker = OrchardIconPicker()
  private var mapsConfigured = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
       !key.isEmpty, !key.hasPrefix("$(") {
      GMSServices.provideAPIKey(key)
      mapsConfigured = true
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OrchardMapServices")!
    let photoChannel = FlutterMethodChannel(name: "orchard_atlas/photos", binaryMessenger: registrar.messenger())
    photoChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "capture", let self = self else { result(FlutterMethodNotImplemented); return }
      let args = call.arguments as? [String: Any]
      self.photoPicker.open(camera: args?["camera"] as? Bool ?? false, result: result)
    }
    let reminders = FlutterMethodChannel(name: "orchard_atlas/reminders", binaryMessenger: registrar.messenger())
    reminders.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      if call.method == "permission" {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in DispatchQueue.main.async { result(granted) } }
      } else if call.method == "replace", let args = call.arguments as? [String: Any],
          let orchard = args["orchard"] as? String, let rows = args["notifications"] as? [[String: Any]] {
        let prefix = "orchard/\(orchard)/"
        center.getPendingNotificationRequests { existing in
          center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier })
          for row in rows.prefix(60) {
            guard let id = row["id"] as? String, let millis = row["time"] as? NSNumber else { continue }
            let date = Date(timeIntervalSince1970: millis.doubleValue / 1000)
            if date <= Date() { continue }
            let content = UNMutableNotificationContent()
            content.title = row["title"] as? String ?? "Orchard task"
            content.body = row["body"] as? String ?? "Task due"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
            center.add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
          }
          DispatchQueue.main.async { result(nil) }
        }
      } else { result(FlutterMethodNotImplemented) }
    }
    let channel = FlutterMethodChannel(name: "orchard_atlas/map_services", binaryMessenger: registrar.messenger())
    let iconChannel = FlutterMethodChannel(name: "orchard_atlas/backup", binaryMessenger: registrar.messenger())
    iconChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "version" {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        result("\(name) (\(build))")
        return
      }
      guard call.method == "importIcon", let self = self else { result(FlutterMethodNotImplemented); return }
      self.iconPicker.open(result)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "mapsConfigured": result(self.mapsConfigured)
      case "searchAddress":
        let arguments = call.arguments as? [String: Any]
        let query = (arguments?["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 500 else {
          result(FlutterError(code: "invalid_query", message: "Enter an address", details: nil))
          return
        }
        if self.geocoder.isGeocoding {
          result(FlutterError(code: "busy", message: "Address lookup is busy. Try again.", details: nil))
          return
        }
        self.geocoder.geocodeAddressString(query) { placemarks, error in
          if error != nil {
            result(FlutterError(code: "lookup_failed", message: "Address lookup failed. Check your connection or use coordinates.", details: nil))
            return
          }
          let matches: [[String: Any]] = (placemarks ?? []).prefix(5).compactMap { place in
            guard let coordinate = place.location?.coordinate else { return nil }
            let label = [place.name, place.locality, place.administrativeArea, place.country]
              .compactMap { $0 }.joined(separator: ", ")
            return ["label": label.isEmpty ? query : label,
                    "latitude": coordinate.latitude, "longitude": coordinate.longitude]
          }
          result(matches)
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}


private final class OrchardIconPicker: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  func open(_ result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "busy", message: "An image picker is already open", details: nil)); return }
    let roots = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.filter { $0.isKeyWindow }
    guard var presenter = roots.first?.rootViewController else { result(FlutterError(code: "picker_failed", message: "Could not open image picker", details: nil)); return }
    while let next = presenter.presentedViewController { presenter = next }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .open)
    }
    pending = result
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending; pending = nil; result?(nil)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else { result(nil); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 8 * 1024 * 1024,
          let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 16384, height <= 16384, Int64(width) * Int64(height) <= 64000000 else { throw NSError(domain: "icon", code: 1) }
        func thumbnail(_ pixels: Int) -> Data? {
          guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
          return UIImage(cgImage: image).pngData()
        }
        guard var png = thumbnail(96) else { throw NSError(domain: "icon", code: 2) }
        if png.count > 32768 { guard let smaller = thumbnail(64) else { throw NSError(domain: "icon", code: 3) }; png = smaller }
        guard png.count <= 32768 else { throw NSError(domain: "icon", code: 4) }
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: png)) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "icon_failed", message: "Choose a valid image under 8 MB (up to 64 megapixels).", details: nil)) }
      }
    }
  }
}

private final class OrchardPhotoPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private var pending: FlutterResult?
  func open(camera: Bool, result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "busy", message: "Photo picker already open", details: nil)); return }
    let source: UIImagePickerController.SourceType = camera ? .camera : .photoLibrary
    guard UIImagePickerController.isSourceTypeAvailable(source) else { result(FlutterError(code: "unavailable", message: "Camera or gallery unavailable", details: nil)); return }
    let roots = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.filter { $0.isKeyWindow }
    guard var presenter = roots.first?.rootViewController else { result(FlutterError(code: "unavailable", message: "Cannot open photo picker", details: nil)); return }
    while let next = presenter.presentedViewController { presenter = next }
    pending = result
    let picker = UIImagePickerController(); picker.sourceType = source; picker.delegate = self
    presenter.present(picker, animated: true)
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    let reply = pending; pending = nil; picker.dismiss(animated: true) { reply?(nil) }
  }
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    let reply = pending; pending = nil
    guard let original = info[.originalImage] as? UIImage else { picker.dismiss(animated: true); reply?(FlutterError(code: "photo_failed", message: "Invalid photo", details: nil)); return }
    func encode(_ side: CGFloat, budget: Int) -> Data? {
      let ratio = min(1, side / max(original.size.width, original.size.height))
      let size = CGSize(width: max(1,original.size.width*ratio), height: max(1,original.size.height*ratio))
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
      for quality in stride(from: 0.85, through: 0.25, by: -0.1) {
        if let data = image.jpegData(compressionQuality: quality), data.count <= budget { return data }
      }
      return nil
    }
    guard let image = encode(1280,budget:512*1024), let thumbnail = encode(160,budget:32*1024) else {
      picker.dismiss(animated:true); reply?(FlutterError(code:"photo_failed",message:"Photo too large",details:nil)); return
    }
    picker.dismiss(animated: true) { reply?(["image":FlutterStandardTypedData(bytes:image),"thumbnail":FlutterStandardTypedData(bytes:thumbnail)]) }
  }
}
