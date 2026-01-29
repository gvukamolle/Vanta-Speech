import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    // Animation states
    @State private var showVanta = false
    @State private var showSpeech = false
    @State private var showFields = false
    @State private var showButton = false

    enum Field {
        case username, password
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: geometry.size.height * 0.18)

                    // Logo / Title - Left aligned
                    titleSection
                        .padding(.horizontal, 32)
                        .padding(.bottom, 64)

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
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "#000000") : Color(hex: "#FFFFFF")
    }

    private var textColor: Color {
        colorScheme == .dark ? Color(hex: "#FFFFFF") : Color(hex: "#000000")
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(hex: "#A0A0A0") : Color(hex: "#808080")
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(hex: "#252525") : Color(hex: "#F5F5F5")
    }

    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color(hex: "#FFFFFF") : Color(hex: "#363636")
    }

    private var buttonForegroundColor: Color {
        colorScheme == .dark ? Color(hex: "#363636") : Color(hex: "#FFFFFF")
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: -8) {
            Text("Vanta")
                .font(.system(size: 64, weight: .bold, design: .default))
                .foregroundStyle(textColor)
                .opacity(showVanta ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: showVanta)

            Text("Speech")
                .font(.system(size: 64, weight: .bold, design: .default))
                .foregroundStyle(textColor)
                .opacity(showSpeech ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: showSpeech)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 16) {
            // Username field
            TextField("Логин", text: $username)
                .textFieldStyle(LoginTextFieldStyle(
                    backgroundColor: surfaceColor,
                    textColor: textColor,
                    borderColor: colorScheme == .dark ? Color(hex: "#404040") : Color(hex: "#E0E0E0")
                ))
                .tint(.primary)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .password
                }
                .opacity(showFields ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: showFields)

            // Password field
            SecureField("Пароль", text: $password)
                .textFieldStyle(LoginTextFieldStyle(
                    backgroundColor: surfaceColor,
                    textColor: textColor,
                    borderColor: colorScheme == .dark ? Color(hex: "#404040") : Color(hex: "#E0E0E0")
                ))
                .tint(.primary)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    if canLogin {
                        login()
                    }
                }
                .opacity(showFields ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: showFields)

            // Login button - appears only when both fields have text
            if showButton {
                Button {
                    login()
                } label: {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .tint(buttonForegroundColor)
                        } else {
                            Text("Войти")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(buttonBackgroundColor)
                    .foregroundStyle(buttonForegroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(authManager.isLoading)
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .onChange(of: username) { _ in updateButtonVisibility() }
        .onChange(of: password) { _ in updateButtonVisibility() }
    }

    private var canLogin: Bool {
        !username.isEmpty && !password.isEmpty
    }

    private func updateButtonVisibility() {
        withAnimation {
            showButton = canLogin
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colorScheme == .dark ? Color(hex: "#FFB84D") : Color(hex: "#FF9500"))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(textColor)

            Spacer()
        }
        .padding()
        .background(
            (colorScheme == .dark ? Color(hex: "#FFB84D") : Color(hex: "#FF9500"))
                .opacity(0.15)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Animations

    private func startAnimations() {
        // Reset states
        showVanta = false
        showSpeech = false
        showFields = false
        showButton = false

        // Sequential animation: Vanta -> Speech -> Fields
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showVanta = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showSpeech = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showFields = true
        }
    }

    // MARK: - Actions

    private func login() {
        guard canLogin else { return }
        focusedField = nil
        Task {
            await authManager.login(username: username, password: password)
        }
    }
}

// MARK: - Custom Text Field Style

struct LoginTextFieldStyle: TextFieldStyle {
    let backgroundColor: Color
    let textColor: Color
    let borderColor: Color

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 17))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

#Preview {
    LoginView()
}

#Preview("Dark Mode") {
    LoginView()
        .preferredColorScheme(.dark)
}
