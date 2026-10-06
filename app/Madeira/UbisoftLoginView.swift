// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Ubisoft Connect sign-in view: embeds the Ubisoft login page in a web view.
// On success the session is captured and stored in the Keychain by
// UbisoftAuth; on cancel/dismiss nothing is kept.
import SwiftUI
import WebKit

struct UbisoftLoginView: View {
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: (UbisoftSession) -> Void = { _ in }

    @State private var webView: WKWebView?
    @State private var errorMessage: String?
    @State private var isWorking = true

    var body: some View {
        NavigationStack {
            ZStack {
                if let webView {
                    WebViewWrapper(webView: webView)
                        .ignoresSafeArea(edges: .bottom)
                }
                if isWorking {
                    ProgressView("Contacting Ubisoft…")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Ubisoft Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        UbisoftAuth.shared.cancelLogin()
                        dismiss()
                    }
                }
            }
            .alert("Sign-in failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(errorMessage ?? "Unknown error.")
            }
        }
        .onAppear {
            let web = UbisoftAuth.shared.beginLogin()
            UbisoftAuth.shared.onLoginComplete { result in
                Task { @MainActor in
                    switch result {
                    case .success(let session):
                        onSignedIn(session)
                        dismiss()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                    isWorking = false
                }
            }
            // Hide the spinner once the page loads (delegate keeps working).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isWorking = false }
            webView = web
        }
    }
}

private struct WebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
