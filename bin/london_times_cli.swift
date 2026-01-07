#!/usr/bin/env swift

//
//  london_times_cli.swift
//  Adhan
//
//  CLI tool for managing London Prayer Times data.
//  Usage: swift bin/london_times_cli.swift <command> [options]
//
//  Commands:
//    info              Show data statistics
//    validate          Check data integrity
//    add <year>        Add a year's data from the API
//    remove <year>     Remove a year's data
//

import Foundation

// MARK: - Configuration

let defaultApiKey = "12181c35-b4c7-4b8b-9bab-1f7ea8fee28a"
let dataFilePath = "Sources/Resources/LondonPrayerTimes.json"
let apiBaseUrl = "https://www.londonprayertimes.com/api/times/"

// MARK: - Data Models

struct LondonTimesData: Codable {
    let city: String
    var times: [String: DayTimes]
}

struct DayTimes: Codable {
    let date: String
    let fajr: String
    let fajr_jamat: String
    let sunrise: String
    let dhuhr: String
    let dhuhr_jamat: String
    let asr: String
    let asr_2: String
    let asr_jamat: String
    let magrib: String
    let magrib_jamat: String
    let isha: String
    let isha_jamat: String
}

// MARK: - CLI

class LondonTimesCLI {
    let fileManager = FileManager.default
    var dryRun = false
    var noBackup = false
    var apiKey: String

    init() {
        self.apiKey = ProcessInfo.processInfo.environment["LONDON_TIMES_API_KEY"] ?? defaultApiKey
    }

    func run() {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        let command = args[1]

        switch command {
        case "info":
            runInfo()
        case "validate":
            runValidate()
        case "add":
            guard args.count >= 3, let year = Int(args[2]) else {
                print("Error: add command requires a year argument")
                print("Usage: swift bin/london_times_cli.swift add <year>")
                exit(1)
            }
            parseOptions(Array(args.dropFirst(3)))
            runAdd(year: year)
        case "remove":
            guard args.count >= 3, let year = Int(args[2]) else {
                print("Error: remove command requires a year argument")
                print("Usage: swift bin/london_times_cli.swift remove <year>")
                exit(1)
            }
            parseOptions(Array(args.dropFirst(3)))
            runRemove(year: year)
        case "help", "-h", "--help":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }

    func parseOptions(_ options: [String]) {
        for option in options {
            switch option {
            case "--dry-run":
                dryRun = true
            case "--no-backup":
                noBackup = true
            default:
                if option.hasPrefix("--api-key=") {
                    apiKey = String(option.dropFirst(10))
                }
            }
        }
    }

    func printUsage() {
        print("""
        London Prayer Times CLI

        Usage: swift bin/london_times_cli.swift <command> [options]

        Commands:
          info              Show data statistics
          validate          Check data integrity
          add <year>        Add a year's data from the API
          remove <year>     Remove a year's data

        Options for add/remove:
          --dry-run         Preview changes without writing
          --no-backup       Skip creating backup file
          --api-key=KEY     Use custom API key

        Environment:
          LONDON_TIMES_API_KEY    API key for londonprayertimes.com
        """)
    }

    // MARK: - Commands

    func runInfo() {
        guard let data = loadData() else {
            print("Error: Could not load data file")
            exit(1)
        }

        let dates = data.times.keys.sorted()
        guard !dates.isEmpty else {
            print("No data entries found")
            return
        }

        // Group by year
        var yearCounts: [Int: (count: Int, min: String, max: String)] = [:]
        for dateStr in dates {
            if let year = Int(dateStr.prefix(4)) {
                if var existing = yearCounts[year] {
                    existing.count += 1
                    if dateStr < existing.min { existing.min = dateStr }
                    if dateStr > existing.max { existing.max = dateStr }
                    yearCounts[year] = existing
                } else {
                    yearCounts[year] = (1, dateStr, dateStr)
                }
            }
        }

        let years = yearCounts.keys.sorted()

        print("""
        === London Prayer Times Data Statistics ===

        City: \(data.city)
        Total entries: \(dates.count)
        Years covered: \(years)
        """)

        for year in years {
            if let info = yearCounts[year] {
                print("  \(year): \(info.count) entries (\(info.min) to \(info.max))")
            }
        }

        print("\nOverall range: \(dates.first!) to \(dates.last!)")
    }

    func runValidate() {
        guard let data = loadData() else {
            print("Error: Could not load data file")
            exit(1)
        }

        var errors: [String] = []
        var warnings: [String] = []

        let dates = data.times.keys.sorted()

        // Check for gaps
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var previousDate: Date? = nil
        for dateStr in dates {
            guard let date = dateFormatter.date(from: dateStr) else {
                errors.append("Invalid date format: \(dateStr)")
                continue
            }

            if let prev = previousDate {
                let daysDiff = Calendar.current.dateComponents([.day], from: prev, to: date).day ?? 0
                if daysDiff > 1 {
                    warnings.append("Gap detected: \(daysDiff - 1) missing day(s) between \(dateFormatter.string(from: prev)) and \(dateStr)")
                }
            }
            previousDate = date
        }

        // Validate each entry
        for (dateStr, times) in data.times {
            // Validate time format
            let timeFields = [
                ("fajr", times.fajr),
                ("sunrise", times.sunrise),
                ("dhuhr", times.dhuhr),
                ("asr", times.asr),
                ("asr_2", times.asr_2),
                ("magrib", times.magrib),
                ("isha", times.isha)
            ]

            var parsedTimes: [(String, Int)] = []
            for (name, timeStr) in timeFields {
                if let minutes = parseTimeToMinutes(timeStr) {
                    parsedTimes.append((name, minutes))
                } else {
                    errors.append("\(dateStr): Invalid time format for \(name): \(timeStr)")
                }
            }

            // Check chronological order
            for i in 1..<parsedTimes.count {
                let (prevName, prevMinutes) = parsedTimes[i-1]
                let (currName, currMinutes) = parsedTimes[i]
                if currMinutes <= prevMinutes {
                    errors.append("\(dateStr): \(currName) (\(timeFields[i].1)) should be after \(prevName) (\(timeFields[i-1].1))")
                }
            }
        }

        // Print results
        print("=== Validation Results ===\n")

        if errors.isEmpty && warnings.isEmpty {
            print("✓ All \(dates.count) entries are valid")
        } else {
            if !warnings.isEmpty {
                print("Warnings (\(warnings.count)):")
                for warning in warnings {
                    print("  ⚠ \(warning)")
                }
                print()
            }

            if !errors.isEmpty {
                print("Errors (\(errors.count)):")
                for error in errors.prefix(20) {
                    print("  ✗ \(error)")
                }
                if errors.count > 20 {
                    print("  ... and \(errors.count - 20) more errors")
                }
                exit(1)
            }
        }
    }

    func runAdd(year: Int) {
        print("Fetching data for year \(year)...")

        guard let apiData = fetchFromAPI(year: year) else {
            print("Error: Failed to fetch data from API")
            exit(1)
        }

        print("Fetched \(apiData.times.count) entries")

        // Validate fetched data
        print("Validating fetched data...")
        if !validateTimes(apiData.times) {
            print("Error: Fetched data failed validation")
            exit(1)
        }

        // Load existing data
        var existingData = loadData() ?? LondonTimesData(city: "london", times: [:])

        // Count existing entries for this year
        let existingYearCount = existingData.times.keys.filter { $0.hasPrefix("\(year)-") }.count
        if existingYearCount > 0 {
            print("Note: Replacing \(existingYearCount) existing entries for \(year)")
        }

        // Merge data
        for (date, times) in apiData.times {
            existingData.times[date] = times
        }

        let totalEntries = existingData.times.count
        print("Total entries after merge: \(totalEntries)")

        // Validate merged data
        print("Validating merged data...")
        if !validateTimes(existingData.times) {
            print("Error: Merged data failed validation")
            exit(1)
        }

        if dryRun {
            print("\n[Dry run] Would write \(totalEntries) entries to \(dataFilePath)")
        } else {
            // Create backup
            if !noBackup {
                createBackup()
            }

            // Write data
            if saveData(existingData) {
                print("✓ Successfully wrote \(totalEntries) entries to \(dataFilePath)")
            } else {
                print("Error: Failed to write data file")
                exit(1)
            }
        }
    }

    func runRemove(year: Int) {
        guard var data = loadData() else {
            print("Error: Could not load data file")
            exit(1)
        }

        let keysToRemove = data.times.keys.filter { $0.hasPrefix("\(year)-") }

        if keysToRemove.isEmpty {
            print("No entries found for year \(year)")
            return
        }

        print("Found \(keysToRemove.count) entries for \(year)")

        if dryRun {
            print("[Dry run] Would remove \(keysToRemove.count) entries")
        } else {
            // Create backup
            if !noBackup {
                createBackup()
            }

            // Remove entries
            for key in keysToRemove {
                data.times.removeValue(forKey: key)
            }

            // Write data
            if saveData(data) {
                print("✓ Removed \(keysToRemove.count) entries, \(data.times.count) remaining")
            } else {
                print("Error: Failed to write data file")
                exit(1)
            }
        }
    }

    // MARK: - Helpers

    func loadData() -> LondonTimesData? {
        guard let data = fileManager.contents(atPath: dataFilePath) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(LondonTimesData.self, from: data)
    }

    func saveData(_ data: LondonTimesData) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(data) else {
            return false
        }

        // Custom formatting: sort dates in descending order
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let times = jsonObject["times"] as? [String: Any] else {
            return false
        }

        // Sort dates descending for output
        let sortedDates = times.keys.sorted().reversed()
        var orderedTimes: [[String: Any]] = []
        for date in sortedDates {
            if let dayData = times[date] as? [String: Any] {
                orderedTimes.append(dayData)
            }
        }

        // Build output JSON manually for better formatting
        var output = "{\n  \"city\": \"\(data.city)\",\n  \"times\": {\n"

        for (index, date) in sortedDates.enumerated() {
            if let dayData = times[date] as? [String: Any] {
                output += "    \"\(date)\": {\n"

                // Order fields consistently
                let fieldOrder = ["date", "fajr", "fajr_jamat", "sunrise", "dhuhr", "dhuhr_jamat",
                                  "asr", "asr_2", "asr_jamat", "magrib", "magrib_jamat", "isha", "isha_jamat"]

                for (fieldIndex, field) in fieldOrder.enumerated() {
                    if let value = dayData[field] as? String {
                        output += "      \"\(field)\": \"\(value)\""
                        if fieldIndex < fieldOrder.count - 1 {
                            output += ","
                        }
                        output += "\n"
                    }
                }

                output += "    }"
                if index < sortedDates.count - 1 {
                    output += ","
                }
                output += "\n"
            }
        }

        output += "  }\n}"

        return fileManager.createFile(atPath: dataFilePath, contents: output.data(using: .utf8))
    }

    func createBackup() {
        let backupPath = dataFilePath + ".bak"
        try? fileManager.removeItem(atPath: backupPath)
        try? fileManager.copyItem(atPath: dataFilePath, toPath: backupPath)
        print("Created backup at \(backupPath)")
    }

    func fetchFromAPI(year: Int) -> LondonTimesData? {
        let urlString = "\(apiBaseUrl)?format=json&key=\(apiKey)&year=\(year)&24hours=true"

        guard let url = URL(string: urlString) else {
            print("Error: Invalid URL")
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: LondonTimesData? = nil

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("Error: No data received")
                return
            }

            // Debug: print first 500 chars of response
            if let responseStr = String(data: data, encoding: .utf8) {
                if responseStr.count < 100 {
                    print("API Response: \(responseStr)")
                }
            }

            let decoder = JSONDecoder()
            do {
                result = try decoder.decode(LondonTimesData.self, from: data)
            } catch {
                print("Error decoding response: \(error)")
                // Try to print the actual response for debugging
                if let responseStr = String(data: data, encoding: .utf8)?.prefix(500) {
                    print("Response preview: \(responseStr)")
                }
            }
        }

        task.resume()
        semaphore.wait()

        return result
    }

    func parseTimeToMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              hours >= 0, hours <= 23,
              minutes >= 0, minutes <= 59 else {
            return nil
        }
        return hours * 60 + minutes
    }

    func validateTimes(_ times: [String: DayTimes]) -> Bool {
        for (dateStr, dayTimes) in times {
            let timeFields = [
                ("fajr", dayTimes.fajr),
                ("sunrise", dayTimes.sunrise),
                ("dhuhr", dayTimes.dhuhr),
                ("asr", dayTimes.asr),
                ("asr_2", dayTimes.asr_2),
                ("magrib", dayTimes.magrib),
                ("isha", dayTimes.isha)
            ]

            var prevMinutes = -1
            for (name, timeStr) in timeFields {
                guard let minutes = parseTimeToMinutes(timeStr) else {
                    print("Invalid time format for \(name) on \(dateStr): \(timeStr)")
                    return false
                }
                if minutes <= prevMinutes {
                    print("Time order error on \(dateStr): \(name) should be after previous time")
                    return false
                }
                prevMinutes = minutes
            }
        }
        return true
    }
}

// Run the CLI
let cli = LondonTimesCLI()
cli.run()
