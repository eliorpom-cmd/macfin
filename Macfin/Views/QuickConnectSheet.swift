import SwiftUI

/// Signs another device (Swiftfin on iPhone/iPad) in as the current user with its Quick Connect code.
struct QuickConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var status: String?
    @State private var done = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: done ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Tokens.Color.text)
            Text("Connect a Device").font(.title3.weight(.bold))
            Text("In Swiftfin, choose Quick Connect, then enter the code it shows.")
                .font(Tokens.Font.meta).foregroundStyle(Tokens.Color.text2)
                .multilineTextAlignment(.center)
            TextField("Code", text: $code)
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(authorize)
                .disabled(done)
            if let status {
                Text(status).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text2)
            }
            HStack(spacing: 12) {
                Button(done ? "Done" : "Cancel") { dismiss() }
                    .buttonStyle(.glass).controlSize(.large)
                    .keyboardShortcut(done ? .defaultAction : .cancelAction)
                if !done {
                    Button("Allow", action: authorize)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                }
            }
        }
        .padding(32)
        .frame(width: 380)
    }

    private func authorize() {
        let digits = code.filter(\.isNumber)
        guard !busy, digits.count >= 6, let client = model.client else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await client.authorizeQuickConnect(code: digits)
                done = true
                status = model.userName.map { String(localized: "Device signed in as \($0).") } ?? String(localized: "Device signed in.")
            } catch JellyfinError.unreachable {
                status = JellyfinError.unreachable.localizedDescription
            } catch {
                status = String(localized: "This code is unknown or has expired. Get a new code in Swiftfin.")
            }
        }
    }
}
