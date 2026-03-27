import Foundation
import CoreLocation

@MainActor
class HeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var heading: Double = 0 // degrees from magnetic north

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start() {
        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 2 // update every 2 degrees
            locationManager.startUpdatingHeading()
        }
    }

    func stop() {
        locationManager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use true heading if available, otherwise magnetic
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = h
        }
    }
}
