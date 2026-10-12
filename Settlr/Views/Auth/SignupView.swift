import AuthenticationServices
import SwiftUI

struct SignupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm = AuthViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Image("SettlrLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        Text("Create account")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.ink)
                        Text("Start tracking your finances.")
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 14) {
                        StyledTextField(placeholder: "Full name", text: $vm.name)
                        StyledTextField(placeholder: "Email", text: $vm.email, keyboardType: .emailAddress)
                        StyledTextField(placeholder: "Password", text: $vm.password, isSecure: true)

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .accessibilityLabel("Account creation failed. \(error)")
                        }

                        Button {
                            Task { await vm.signUp(appState: appState) }
                        } label: {
                            if vm.isLoading {
                                ProgressView().tint(Theme.buttonInk)
                            } else {
                                Text("Create account")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(vm.isLoading)

                        HStack(spacing: 12) {
                            Rectangle().fill(Theme.line).frame(height: 1)
                            Text("or").font(.footnote.weight(.medium)).foregroundStyle(Theme.faint)
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }

                        SignInWithAppleButton(.signUp) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await vm.signInWithApple(result: result, appState: appState) }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(vm.isLoading)
                    }

                    HStack(spacing: 4) {
                        Text("Already have an account?").foregroundStyle(Theme.muted)
                        Button("Sign in") { dismiss() }
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
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to sign in")
            }
        }
    }
}
