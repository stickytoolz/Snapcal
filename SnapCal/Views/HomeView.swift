import SwiftUI
import PhotosUI
import VisionKit

struct HomeView: View {
    let onImage: (UIImage) -> Void

    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(spacing: 8) {
                    Text("SnapCal").font(.largeTitle.bold())
                    Text("Take a picture of your paper calendar.\nSnapCal puts it in your iPhone calendar.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        if VNDocumentCameraViewController.isSupported { showScanner = true } else { showCamera = true }
                    } label: {
                        Label("Scan Calendar", systemImage: "camera.viewfinder")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Tip: get the whole month in the picture, straight-on, in good light.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { image in
                    showScanner = false
                    if let image { onImage(image) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    showCamera = false
                    if let image { onImage(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pickerItem = nil
                        onImage(image)
                    }
                }
            }
        }
    }
}

/// Apple's document scanner: finds the page edges and straightens it automatically.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}

/// Plain camera, used if the document scanner isn't available.
struct CameraView: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

struct ProcessingView: View {
    let text: String
    let value: Double

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            Text(text).font(.headline)
            Text("Several readers are checking the handwriting and comparing answers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct DoneView: View {
    let count: Int
    let onUndo: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("Added \(count) event\(count == 1 ? "" : "s")").font(.title.bold())
            Text("They're in your iPhone calendar now.").foregroundStyle(.secondary)
            Spacer()
            Button {
                if let url = URL(string: "calshow://") { UIApplication.shared.open(url) }
            } label: {
                Label("Open Calendar", systemImage: "calendar").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            Button("Scan Another", action: onFinish)
                .frame(maxWidth: .infinity, minHeight: 44)
            Button("Undo — remove these events", role: .destructive, action: onUndo)
                .font(.footnote)
        }
        .padding(24)
    }
}
