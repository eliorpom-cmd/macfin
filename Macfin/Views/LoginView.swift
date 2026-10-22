import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = AppModel.defaultServer.absoluteString
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Tokens.Color.text)
                Text(verbatim: "Macfin").font(Tokens.Font.section).foregroundStyle(Tokens.Color.text)
                Text("Sign in to your Jellyfin server").font(Tokens.Font.meta).foregroundStyle(Tokens.Color.text2)
            }
            VStack(spacing: 10) {
                TextField("Server", text: $server)
                TextField("User Name", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .frame(width: 320)

            if let error {
                Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text2)
                    .multilineTextAlignment(.center).frame(width: 320)
            }
            Button(action: signIn) {
                if busy { ProgressView().controlSize(.small).tint(Tokens.Color.onAction) } else { Text("Sign In") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(busy || username.isEmpty)
        }
        .padding(48)
    }

    private func signIn() {
        // Return in the password field bypasses the disabled button.
        guard !busy, !username.isEmpty else { return }
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            error = String(localized: "Check the server address."); return
        }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                model.signIn(try await JellyfinClient(server: url).authenticate(username: username, password: password))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
