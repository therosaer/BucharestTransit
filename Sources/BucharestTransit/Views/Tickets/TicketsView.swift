import SwiftUI

public struct TicketsView: View {
    @ObservedObject var appState: AppState

    @State private var usernameInput = ""
    @State private var passwordInput = ""
    @State private var isLoggingIn = false
    @State private var loginError: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if appState.biletStatus.authenticated {
                        authenticatedDashboardView
                    } else {
                        unauthenticatedLoginView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .refreshable {
                if appState.biletStatus.authenticated {
                    await appState.loadBiletActiveTickets()
                }
            }
            .navigationTitle("Elevi și studenți")
        }
    }

    private var authenticatedDashboardView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appleBlue)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(appState.biletStatus.account?.initials ?? "AI")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.biletStatus.account?.fullName ?? "Cont Bilet TB")
                        .font(.system(size: 16, weight: .bold))
                    Text(appState.biletStatus.account?.email ?? "Cont Bilet TB")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    HapticFeedback.trigger(.medium)
                    Task { await appState.logoutBilet() }
                }) {
                    Text("Deconectare")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appleRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appleRed.opacity(0.12), in: Capsule())
                }
            }
            .padding(14)
            .appleGlassBackground(cornerRadius: 18)

            activeTicketsTab
        }
    }

    private var activeTicketsTab: some View {
        VStack(spacing: 14) {
            if appState.biletTicketsLoading && appState.biletActiveTickets.isEmpty {
                ProgressView("Se încarcă titlurile...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let error = appState.biletTicketsError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.appleOrange)
                    Text("Titlurile nu au putut fi încărcate.")
                        .font(.system(size: 15, weight: .semibold))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Încearcă din nou") {
                        Task { await appState.loadBiletActiveTickets() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .appleGlassBackground(cornerRadius: 18)
            } else if appState.biletActiveTickets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "ticket")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Nu există un titlu activ pentru acest cont.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Aici apar titlurile anuale pentru elevi și studenți deja înregistrate în YouthTB.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
            } else {
                ForEach(appState.biletActiveTickets) { ticket in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.appleGreen)
                                        .font(.system(size: 13))
                                    Text("ACTIV • VALABIL PENTRU CONTROL")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.appleGreen)
                                }

                                Text(ticket.title)
                                    .font(.system(size: 18, weight: .heavy))
                                Text("Titlu înregistrat în YouthTB")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if ticket.isStudentElev {
                                Text("ELEV / STUDENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.appleGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.appleGreen.opacity(0.15), in: Capsule())
                            }
                        }

                        if let remaining = ticket.remainingSeconds {
                            HStack {
                                HStack(spacing: 8) {
                                    Text("⏳")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("TIMP RĂMAS")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Text(TransitTimeFormatter.formatRemaining(seconds: remaining))
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundColor(remaining < 600 ? .appleRed : .appleGreen)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    if let from = ticket.validFromDate {
                                        Text("De la: \(from)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    if let to = ticket.validToDate {
                                        Text("Până la: \(to)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.appleGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        VStack(spacing: 8) {
                            Text("Prezintă codul QR la verificare")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            QRCodeView(base64Image: ticket.qrBase64Payload)

                            if let series = ticket.seriesCode {
                                Text("Seria: \(series)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding(18)
                    .appleGlassBackground(cornerRadius: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.appleGreen.opacity(0.5), lineWidth: 1.5)
                    )
                }
            }
        }
    }

    private var unauthenticatedLoginView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.appleBlue)

                Text("Titluri pentru elevi și studenți")
                    .font(.system(size: 20, weight: .heavy))

                Text("Autentifică-te pentru a vedea titlurile anuale deja înregistrate în YouthTB și codul QR pentru control. Nu se pot cumpăra titluri din această secțiune.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .padding(.top, 20)

            VStack(spacing: 12) {
                TextField("Email sau Număr Telefon", text: $usernameInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                SecureField("Parolă", text: $passwordInput)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                if let loginError {
                    Text(loginError)
                        .font(.system(size: 12))
                        .foregroundColor(.appleRed)
                }

                Button(action: {
                    HapticFeedback.trigger(.medium)
                    isLoggingIn = true
                    loginError = nil
                    Task {
                        let success = await appState.loginBilet(username: usernameInput, pass: passwordInput)
                        isLoggingIn = false
                        if !success {
                            loginError = "Autentificarea nu a reușit. Verifică datele contului."
                        }
                    }
                }) {
                    HStack {
                        if isLoggingIn {
                            ProgressView().tint(.white)
                        } else {
                            Text("Autentificare")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appleBlue, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoggingIn)
            }
            .padding(18)
            .appleGlassBackground(cornerRadius: 22)
        }
    }
}
