//
//  CalculationParametersCodableTests.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan

class CalculationParametersCodableTests: XCTestCase {

    private let muslimWorldLeagueJSONWrittenBy140 = """
        "adjustments":{"asr":0,"dhuhr":0,"fajr":0,"isha":0,"maghrib":0,"sunrise":0},\
        "fajrAngle":18,"ishaAngle":17,"ishaInterval":0,"madhab":1,"method":"muslimWorldLeague",\
        "methodAdjustments":{"asr":0,"dhuhr":1,"fajr":0,"isha":0,"maghrib":0,"sunrise":0},\
        "rounding":"nearest","shafaq":"general"
        """

    private func decode(_ json: String, addingKeys extraKeys: String = "") throws -> CalculationParameters {
        let data = Data(("{" + json + extraKeys + "}").utf8)
        return try JSONDecoder().decode(CalculationParameters.self, from: data)
    }

    func testDecodesJSONWrittenBeforePolarCircleResolutionAndHourAngleCorrectionExisted() throws {
        let params = try decode(muslimWorldLeagueJSONWrittenBy140)
        XCTAssertEqual(params, CalculationMethod.muslimWorldLeague.params)
        XCTAssertEqual(params.polarCircleResolution, .aqrabBalad)
        XCTAssertEqual(params.hourAngleCorrection, .iterative)
    }

    func testDecodesJSONWrittenWithPolarCircleResolutionButNoHourAngleCorrection() throws {
        let params = try decode(muslimWorldLeagueJSONWrittenBy140, addingKeys: ",\"polarCircleResolution\":\"aqrabYaum\"")
        var expected = CalculationMethod.muslimWorldLeague.params
        expected.polarCircleResolution = .aqrabYaum
        XCTAssertEqual(params, expected)
        XCTAssertEqual(params.hourAngleCorrection, .iterative)
    }

    func testDecodesJSONWrittenWithBothKeys() throws {
        let params = try decode(muslimWorldLeagueJSONWrittenBy140, addingKeys: ",\"polarCircleResolution\":\"unresolved\",\"hourAngleCorrection\":\"singlePass\"")
        var expected = CalculationMethod.muslimWorldLeague.params
        expected.polarCircleResolution = .unresolved
        expected.hourAngleCorrection = .singlePass
        XCTAssertEqual(params, expected)
    }

    func testEncodingWritesBothKeysAndRoundTrips() throws {
        var params = CalculationMethod.muslimWorldLeague.params
        params.polarCircleResolution = .unresolved
        params.hourAngleCorrection = .singlePass
        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["polarCircleResolution"] as? String, "unresolved")
        XCTAssertEqual(object["hourAngleCorrection"] as? String, "singlePass")
        XCTAssertEqual(try JSONDecoder().decode(CalculationParameters.self, from: data), params)
    }
}
