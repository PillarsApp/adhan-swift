//
//  PublishedRule.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// A rule of the `OTT 1` format. The raw value is the rule's stable id, the
/// one the format doc and the Dart library use.
public enum PublishedRule: String, CaseIterable, Sendable {
    case fileEmpty = "file.empty"
    case fileLastLineNoLF = "file.lastLineNoLF"
    case fileCR = "file.cr"
    case fileBOM = "file.bom"
    case fileMagic = "file.magic"
    case fileHeaderAbsent = "file.headerAbsent"

    case headerJSON = "header.json"
    case headerDuplicateKey = "header.duplicateKey"
    case headerKeyAbsent = "header.keyAbsent"
    case headerAuthority = "header.authority"
    case headerRevision = "header.revision"
    case headerPart = "header.part"
    case headerCoverage = "header.coverage"
    case headerCoverageOrder = "header.coverage.order"
    case headerAsrShadow = "header.asrShadow"

    case columnUnknown = "column.unknown"
    case columnDuplicate = "column.duplicate"
    case columnMissingCore = "column.missingCore"

    case zonesEmpty = "zones.empty"
    case zoneId = "zone.id"
    case zoneIdDuplicate = "zone.id.duplicate"
    case zoneOffsetsEmpty = "zone.offsets.empty"
    case zoneOffsetShape = "zone.offset.shape"
    case zoneOffsetDate = "zone.offset.date"
    case zoneOffsetOrder = "zone.offset.order"
    case zoneOffsetRange = "zone.offset.range"
    case zoneOffsetStart = "zone.offset.start"

    case localitiesEmpty = "localities.empty"
    case localityId = "locality.id"
    case localityIdDuplicate = "locality.id.duplicate"
    case localityGroup = "locality.group"
    case localityZone = "locality.zone"
    case localityNames = "locality.names"
    case localityRefShape = "locality.ref.shape"
    case localityRefInteger = "locality.ref.integer"
    case localityRefRange = "locality.ref.range"
    case localityValidityDate = "locality.validity.date"
    case localityValidityOrder = "locality.validity.order"
    case localitySuccessor = "locality.successor"
    case localityGeometry = "locality.geometry"
    case localityPointRadius = "locality.point.radius"
    case localityAreaPolygons = "locality.area.polygons"
    case localityAreaTolerance = "locality.area.tolerance"
    case localityAreaPolyline = "locality.area.polyline"
    case localityAreaRing = "locality.area.ring"
    case localityAreaVertex = "locality.area.vertex"

    case rowFields = "row.fields"
    case rowLocality = "row.locality"
    case rowDate = "row.date"
    case rowCoverage = "row.coverage"
    case rowFirstDayLength = "row.firstDay.length"
    case rowFirstDayDigits = "row.firstDay.digits"

    case cellTruncatedTime = "cell.truncatedTime"
    case cellDigits = "cell.digits"
    case cellMinute = "cell.minute"
    case cellHour = "cell.hour"
    case cellTruncatedDay = "cell.truncatedDay"
    case cellLetter = "cell.letter"
    case cellDelta = "cell.delta"
    case rowCoreOrder = "row.coreOrder"
    case rowCrossesYear = "row.crossesYear"
    case rowEndsAfterCoverage = "row.endsAfterCoverage"
    case rowOverlap = "row.overlap"
}
