import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = AuthViewModel()
    @State private var showSignup = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo / wordmark
                    VStack(spacing: 8) {
                        Image("SettlrLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                        Text("Settlr")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(hex: "#ecedee"))
                        Text("Track every peso.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(hex: "#8e9197"))
                    }
                    .padding(.bottom, 48)

                    // Form
                    VStack(spacing: 14) {
                        StyledTextField(placeholder: "Email", text: $vm.email, keyboardType: .emailAddress)
                        StyledTextField(placeholder: "Password", text: $vm.password, isSecure: true)

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#ff6b6b"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await vm.signIn(appState: appState) }
                        } label: {
                            Group {
                                if vm.isLoading {
                                    ProgressView().tint(Color(hex: "#0e0f11"))
                                } else {
                                    Text("Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#0e0f11"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(hex: "#c8ff5a"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(vm.isLoading)

                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color(hex: "#2a2d32"))
                                .frame(height: 1)
                            Text("or")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "#5a5d63"))
                            Rectangle()
                                .fill(Color(hex: "#2a2d32"))
                                .frame(height: 1)
                        }

                        Button {
                            Task { await vm.signInWithGoogle(appState: appState) }
                        } label: {
                            HStack(spacing: 10) {
                                Text("G")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hex: "#c8ff5a"))
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(hex: "#ecedee"))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "#15171a"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                                    )
                            )
                        }
                        .disabled(vm.isLoading)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Sign up link
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundStyle(Color(hex: "#8e9197"))
                        Button("Sign Up") { showSignup = true }
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }
                    .font(.system(size: 14))
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(isPresented: $showSignup) {
                SignupView()
            }
        }
        .preferredColorScheme(.dark)
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
        .font(.system(size: 16))
        .foregroundStyle(Color(hex: "#ecedee"))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                )
        )
    }
}
