import SwiftUI

struct SignupView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = AuthViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#0e0f11").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Create account")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    Text("Start tracking your finances.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
                .padding(.bottom, 40)

                VStack(spacing: 14) {
                    StyledTextField(placeholder: "Full name", text: $vm.name)
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
                        Task { await vm.signUp(appState: appState) }
                    } label: {
                        Group {
                            if vm.isLoading {
                                ProgressView().tint(Color(hex: "#0e0f11"))
                            } else {
                                Text("Create Account")
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
                }
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(Color(hex: "#8e9197"))
                    Button("Sign In") { dismiss() }
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                }
                .font(.system(size: 14))
                .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
