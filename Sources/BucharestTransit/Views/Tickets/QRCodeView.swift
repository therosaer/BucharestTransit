import SwiftUI

public struct QRCodeView: View {
    public let base64Image: String?

    public init(base64Image: String? = nil) {
        self.base64Image = base64Image
    }

    public var body: some View {
        #if canImport(UIKit)
        Group {
            if let base64Image, let image = decodeBase64Image(base64Image) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36))
                    Text("Cod QR indisponibil")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Imaginea oficială a biletului nu a putut fi încărcată.")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(12)
            }
        }
        .frame(width: 190, height: 190)
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        #else
        Image(systemName: "qrcode")
            .frame(width: 190, height: 190)
        #endif
    }

    #if canImport(UIKit)
    private func decodeBase64Image(_ value: String) -> UIImage? {
        var base64 = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if base64.hasPrefix("data:"), let comma = base64.firstIndex(of: ",") {
            base64 = String(base64[base64.index(after: comma)...])
        }
        base64 = base64.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }
    #endif
}
