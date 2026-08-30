import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm = AuthViewModel()
    @State private var showSignup = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 8) {
                            Image("SettlrLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .accessibilityHidden(true)
                            Text("Settlr")
                                .font(.largeTitle.bold())
                                .foregroundStyle(Theme.ink)
                            Text("Track every peso.")
                                .font(.body)
                                .foregroundStyle(Theme.muted)
                        }

                        VStack(spacing: 14) {
                            StyledTextField(placeholder: "Email", text: $vm.email, keyboardType: .emailAddress)
                            StyledTextField(placeholder: "Password", text: $vm.password, isSecure: true)

                            if let error = vm.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.expense)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .accessibilityLabel("Sign in failed. \(error)")
                            }

                            Button {
                                Task { await vm.signIn(appState: appState) }
                            } label: {
                                if vm.isLoading {
                                    ProgressView().tint(Theme.buttonInk)
                                } else {
                                    Text("Sign in")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(vm.isLoading)

                            HStack(spacing: 12) {
                                Rectangle().fill(Theme.line).frame(height: 1)
                                Text("or").font(.footnote.weight(.medium)).foregroundStyle(Theme.faint)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }

                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                Task { await vm.signInWithApple(result: result, appState: appState) }
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .disabled(vm.isLoading)

                            Button {
                                Task { await vm.signInWithGoogle(appState: appState) }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("G")
                                        .font(.title3.bold())
                                        .foregroundStyle(Theme.accentText)
                                    Text("Continue with Google")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Theme.line, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.isLoading)
                        }

                        HStack(spacing: 4) {
                            Text("Don't have an account?").foregroundStyle(Theme.muted)
                            Button("Sign up") { showSignup = true }
                                .foregroundStyle(Theme.accentText)
                                .frame(minHeight: 44)
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
        }
    }
}

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
        }
        .font(.body)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }
}
