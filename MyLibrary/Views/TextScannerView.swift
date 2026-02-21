import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct TextScannerView: UIViewControllerRepresentable {
    let onTextFound: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning {
            try? vc.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextFound: onTextFound)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTextFound: (String) -> Void

        init(onTextFound: @escaping (String) -> Void) {
            self.onTextFound = onTextFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .text(let text):
                onTextFound(text.transcript)
            default:
                break
            }
        }
    }
}
