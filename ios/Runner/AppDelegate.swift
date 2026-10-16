import Flutter
import UIKit
import GoogleMaps
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let geocoder = CLGeocoder()
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
    let channel = FlutterMethodChannel(name: "orchard_atlas/map_services", binaryMessenger: registrar.messenger())
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
