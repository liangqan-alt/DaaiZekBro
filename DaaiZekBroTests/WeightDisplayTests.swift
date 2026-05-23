import Foundation
import Testing
@testable import DaaiZekBro

struct WeightDisplayTests {
    @Test func weightUnitMetadataMatchesStoragePreferenceContract() {
        #expect(WeightUnit.defaultUnit == .kilograms)
        #expect(WeightUnit.storageKey == "weightUnit")
        #expect(WeightUnit.kilograms.rawValue == "kg")
        #expect(WeightUnit.pounds.rawValue == "lb")
        #expect(WeightUnit.kilograms.label == "kg")
        #expect(WeightUnit.pounds.label == "lb")
    }

    @Test func weightUnitConvertsBetweenDisplayValuesAndKilograms() {
        #expect(WeightUnit.kilograms.displayValue(fromKilograms: 22.5) == 22.5)
        #expect(WeightUnit.kilograms.kilograms(fromDisplayValue: 22.5) == 22.5)
        #expect(abs(WeightUnit.pounds.kilograms(fromDisplayValue: 100) - 45.3592) < 0.000001)
        #expect(abs(WeightUnit.pounds.displayValue(fromKilograms: 45.3592) - 100) < 0.000001)
        #expect(abs(WeightUnit.pounds.displayValue(fromKilograms: 22.5) - 49.6040494541) < 0.000001)
        #expect(abs(WeightUnit.pounds.kilograms(fromDisplayValue: 49.6) - 22.4981632) < 0.000001)
    }

    @Test func weightDisplayFormatsIntegerAndOneDecimalValues() {
        #expect(WeightDisplay.text(24) == "24")
        #expect(WeightDisplay.text(22.5) == "22.5")
        #expect(WeightDisplay.text(1234.5) == "1234.5")
        #expect(WeightDisplay.text(forKilograms: 22.5, unit: .kilograms) == "22.5")
        #expect(WeightDisplay.text(forKilograms: 45.3592, unit: .pounds) == "100")
        #expect(WeightDisplay.text(forKilograms: 22.5, unit: .pounds) == "49.6")
    }
}
