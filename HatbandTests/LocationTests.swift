import CoreLocation
import Foundation
import Testing
@testable import Hatband

struct LocationTests {
    @Test func fixRoundsToHundredths() {
        let fix = Fix(latitude: 51.5074, longitude: -0.1278, accuracy: 4321.4)
        #expect(fix.latitudeHundredths == 5151)
        #expect(fix.longitudeHundredths == -13)
        #expect(fix.accuracyMetres == 4321)
        let southern = Fix(latitude: -33.8688, longitude: 151.2093, accuracy: 49.5)
        #expect(southern.latitudeHundredths == -3387)
        #expect(southern.longitudeHundredths == 15121)
        #expect(southern.accuracyMetres == 50)
    }

    @Test func fixFromLocationUsesTheSameRounding() {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), altitude: 0,
                                  horizontalAccuracy: 4321.4, verticalAccuracy: -1, timestamp: Date())
        let fix = Fix(location: location)
        #expect(fix == Fix(latitude: 51.5074, longitude: -0.1278, accuracy: 4321.4))
        let invalid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 0,
                                 horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        #expect(Fix(location: invalid).accuracyMetres == 0)
    }

    @Test func timeoutIsTwentySeconds() {
        #expect(Location.timeout == .seconds(20))
    }
}
