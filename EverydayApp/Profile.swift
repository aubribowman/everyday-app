import SwiftUI
import UIKit

/// Saves your profile picture as a small square JPEG in the app's own storage.
///
/// The picture lives in a file rather than in SwiftData. Views watch the "profilePhotoVersion"
/// number in AppStorage, which goes up on every change, so they know to reload it.
enum ProfilePhoto {
    static let versionKey = "profilePhotoVersion"

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "profile-photo.jpg")
    }

    static func load() -> UIImage? {
        // Read via the URL itself; a plain path string would turn the space in
        // "Application Support" into "%20" and miss the file.
        (try? Data(contentsOf: fileURL)).flatMap(UIImage.init(data:))
    }

    /// Crops to a centered square, shrinks it to 400×400 and saves it.
    static func save(_ image: UIImage) throws {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2,
                          width: side, height: side)
        let target = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Draw the whole photo scaled so the cropped square fills the 400×400 canvas.
            let scale = target.width / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                withIntermediateDirectories: true)
        try square.jpegData(compressionQuality: 0.85)?.write(to: fileURL, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Your round profile picture, or your initials when there's no picture.
struct ProfileAvatar: View {
    var size: CGFloat = 44
    @AppStorage("userName") private var userName = "Aubri Bowman"
    @AppStorage(ProfilePhoto.versionKey) private var photoVersion = 0
    @State private var photo: UIImage?

    private var initials: String {
        userName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.peachInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.peach)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Reload whenever the picture changes (and once when the view first appears).
        .onChange(of: photoVersion, initial: true) { photo = ProfilePhoto.load() }
    }
}
