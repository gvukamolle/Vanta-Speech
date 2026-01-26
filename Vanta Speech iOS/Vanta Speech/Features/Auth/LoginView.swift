import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case username, password
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: geometry.size.height * 0.15)

                    // Logo / Title
                    titleSection
                        .padding(.bottom, 48)

                    // Login Form
                    formSection
                        .padding(.horizontal, 32)

                    // Error message
                    if let error = authManager.error {
                        errorBanner(error)
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 32)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.pinkLight.opacity(0.1),
                    Color.blueLight.opacity(0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 12) {
            // "Vanta Speech" with Speech in italic
            HStack(spacing: 0) {
                Text("Vanta ")
                    .font(.system(size: 36, weight: .bold))
                Text("Speech")
                    .font(.system(size: 36, weight: .bold))
                    .italic()
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.pinkVibrant, Color.blueVibrant],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            Text("Войдите в свой аккаунт")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 16) {
            // Username field
            VStack(alignment: .leading, spacing: 8) {
                Text("Логин")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("Введите логин", text: $username)
                    .textFieldStyle(VantaTextFieldStyle())
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Пароль")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                SecureField("Введите пароль", text: $password)
                    .textFieldStyle(VantaTextFieldStyle())
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        login()
                    }
            }

            // Login button
            Button {
                login()
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Войти")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.pinkVibrant, Color.blueVibrant],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(authManager.isLoading || username.isEmpty || password.isEmpty)
            .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1.0)
            .padding(.top, 8)

#if DEBUG
            // Skip auth button (debug only)
            Button {
                skipAuth()
            } label: {
                Text("Пропустить авторизацию (тест)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
#endif
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func login() {
        focusedField = nil
        Task {
            await authManager.login(username: username, password: password)
        }
    }

    private func skipAuth() {
        authManager.skipAuthentication()
    }
}

// MARK: - Custom Text Field Style

struct VantaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

#Preview {
    LoginView()
}
