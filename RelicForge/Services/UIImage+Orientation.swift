import UIKit

extension UIImage {
  func normalizedOrientation() -> UIImage {
    if imageOrientation == .up { return self }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { _ in
      draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
