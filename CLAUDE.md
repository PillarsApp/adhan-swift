# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Adhan Swift is a library for calculating Islamic prayer times with high precision astronomical calculations. It supports Swift 4.0-5.5 and Objective-C, targeting iOS, macOS, tvOS, and watchOS platforms.

## Development Commands

### Testing
- **Run all tests**: `bundle exec fastlane tests` (runs tests for all platforms with Swift 4.0 and 5.3)
- **Run specific platform tests**: 
  - `bundle exec fastlane test scheme:Adhan-iOS swift_version:5.3`
  - `bundle exec fastlane test scheme:Adhan-macOS swift_version:5.3`
  - `bundle exec fastlane test scheme:Adhan-tvOS swift_version:5.3`
- **Swift Package Manager tests**: `swift test`

### Building
- **Xcode**: Open `Adhan.xcodeproj` and build specific schemes (Adhan-iOS, Adhan-macOS, etc.)
- **Swift Package Manager**: `swift build`

### Package Management
- **CocoaPods**: Uses `Adhan.podspec`
- **Swift Package Manager**: Uses `Package.swift`
- **Carthage**: Supported via git tags

## Code Architecture

### Core Components

**PrayerTimes.swift** - Main calculation engine that computes all five prayer times plus sunrise. Handles complex astronomical calculations, special cases for high latitudes, and applies various adjustments.

**Models/** - Contains core data structures:
- `CalculationMethod.swift` - Predefined calculation methods for different regions/organizations
- `CalculationParameters.swift` - Configurable parameters for calculations
- `Coordinates.swift` - Geographic coordinate handling
- `Prayer.swift`, `Madhab.swift`, `HighLatitudeRule.swift`, `Shafaq.swift` - Enums for various calculation options

**Astronomy/** - High-precision astronomical calculations:
- `Astronomical.swift` - Core astronomical functions
- `SolarCoordinates.swift`, `SolarTime.swift` - Solar position calculations

**Qibla.swift** - Calculates direction to Mecca from any coordinates

**SunnahTimes.swift** - Calculates recommended prayer times (Qiyam periods)

### Key Design Patterns

- All prayer times returned as UTC `Date` objects - consumers must apply timezone formatting
- Initialization can fail (returns `nil`) if astronomical calculations are impossible for given coordinates/date
- Extensive use of calculation parameters for regional customization
- High latitude special handling (>55° latitude) with night fraction approximations

### Test Structure

Tests are organized by functionality:
- `AdhanTests.swift` - Main prayer time calculation tests
- `AstronomicalTests.swift` - Astronomical calculation tests  
- `QiblaTests.swift` - Qibla direction tests
- `TimeTests.swift` - Time-related utility tests
- `Tests/Resources/Times/` - JSON test data for various cities/methods

The library includes comprehensive test data comparing against known prayer times for multiple cities and calculation methods.