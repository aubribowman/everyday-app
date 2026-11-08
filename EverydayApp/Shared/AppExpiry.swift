// With a free Apple developer account, an app you install from Xcode stops opening 7 days
// after its provisioning profile was made. Running it from Xcode again renews it and keeps
// your data. This reads the exact cutoff from the profile Xcode put inside the app, so
// Settings can show it and Reminders.swift can remind you before it runs out.

import Foundation

enum AppExpiry {
    /// When this copy of the app stops opening. Nil in the simulator, where there's no profile.
    static let date: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(inProfile: data)
    }()

    /// The profile is a signed file with a property list inside. Finds the list and reads
    /// its ExpirationDate.
    static func expirationDate(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let dictionary = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return dictionary?["ExpirationDate"] as? Date
    }

    /// "Sat, Nov 14 at 8:20 PM"
    static func text(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
