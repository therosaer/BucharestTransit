import SwiftUI

public struct TicketsView: View {
    @ObservedObject var appState: AppState

    @State private var usernameInput = ""
    @State private var passwordInput = ""
    @State private var isLoggingIn = false
    @State private var loginError: String?
    @State private var savedBrightness: CGFloat?

    private enum Field { case username, password }
    @FocusState private var focusedField: Field?

    public var body: some View {
        NavigationStack {
            Group {
                if appState.biletStatus.authenticated {
                    ScrollView {
                        authenticatedDashboardView
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                    }
                    .background(Color.appBackground)
                    .refreshable {
                        await appState.loadBiletActiveTickets()
                    }
                } else {
                    unauthenticatedLoginView
                }
            }
            .navigationTitle("Bilete")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if appState.biletStatus.authenticated {
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Section {
                Text(appState.biletStatus.account?.fullName ?? "Cont Bilet TB")
                Text(appState.biletStatus.account?.email ?? "")
            }
            Button(role: .destructive) {
                Task { await appState.logoutBilet() }
            } label: {
                Label("Deconectare", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Text(appState.biletStatus.account?.initials ?? "AI")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
        }
        .accessibilityLabel("Cont")
    }

    // MARK: - Date helpers

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Bucharest")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    private func displayDate(_ string: String?) -> String? {
        guard let string else { return nil }
        guard let date = parseDate(string) else { return string }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "ro_RO")))
    }

    private var canSubmit: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty && !passwordInput.isEmpty && !isLoggingIn
    }

    private func submitLogin() {
        guard canSubmit else { return }
        focusedField = nil
        HapticFeedback.trigger(.medium)
        isLoggingIn = true
        loginError = nil
        appState.clearBiletLoginError()
        Task {
            let success = await appState.loginBilet(username: usernameInput, pass: passwordInput)
            isLoggingIn = false
            if !success {
                loginError = appState.biletLoginError ?? "Autentificarea nu a reușit. Verifică datele contului."
            }
        }
    }

    private var authenticatedDashboardView: some View {
        VStack(spacing: 16) {
            activeTicketsTab
        }
        .onAppear { raiseBrightness() }
        .onDisappear { restoreBrightness() }
    }

    private func raiseBrightness() {
        #if canImport(UIKit)
        guard savedBrightness == nil else { return }
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = max(UIScreen.main.brightness, 0.9)
        #endif
    }

    private func restoreBrightness() {
        #if canImport(UIKit)
        if let saved = savedBrightness {
            UIScreen.main.brightness = saved
            savedBrightness = nil
        }
        #endif
    }

    private var activeTicketsTab: some View {
        VStack(spacing: 14) {
            if appState.biletTicketsLoading && appState.biletActiveTickets.isEmpty {
                ProgressView("Se încarcă titlurile")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let error = appState.biletTicketsError {
                ContentUnavailableView {
                    Label("Titlurile nu au putut fi încărcate", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Încearcă din nou") {
                        Task { await appState.loadBiletActiveTickets() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if appState.biletActiveTickets.isEmpty {
                ContentUnavailableView {
                    Label("Niciun titlu activ", systemImage: "ticket")
                } description: {
                    Text("Titlurile anuale din YouthTB apar aici.")
                }
            } else {
                ForEach(appState.biletActiveTickets) { ticket in
                    ticketCard(ticket)
                }
            }
        }
    }

    private func ticketCard(_ ticket: Ticket) -> some View {
        VStack(spacing: 20) {
            // QR first: it is the only thing an inspector needs.
            VStack(spacing: 12) {
                QRCodeView(base64Image: ticket.qrBase64Payload)

                if let series = ticket.seriesCode {
                    Text("Seria \(series)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.appleGreen).frame(width: 6, height: 6)
                        Text("Activ")
                            .font(.footnote)
                            .foregroundStyle(Color.appleGreenText)
                        if ticket.isStudentElev {
                            Text("· Elev / Student")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(ticket.title)
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                remainingRow(ticket)

                if ticket.validFromDate != nil || ticket.validToDate != nil {
                    VStack(spacing: 8) {
                        if let from = displayDate(ticket.validFromDate) {
                            LabeledContent("Valabil de la", value: from)
                        }
                        if let to = displayDate(ticket.validToDate) {
                            LabeledContent("Valabil până la", value: to)
                        }
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        }
        .padding(20)
        .groupedCardBackground(cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ticket.title)
    }

    @ViewBuilder
    private func remainingRow(_ ticket: Ticket) -> some View {
        let endDate = parseDate(ticket.validToDate)
            ?? ticket.remainingSeconds.map { Date().addingTimeInterval(TimeInterval($0)) }
        if let endDate {
            let seconds = Int(endDate.timeIntervalSinceNow)
            HStack {
                Text("Timp rămas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    if seconds <= 0 {
                        Text("Expirat")
                    } else if seconds < 86_400 {
                        Text(timerInterval: Date.now...endDate, countsDown: true)
                    } else {
                        Text(TransitTimeFormatter.formatRemaining(seconds: seconds))
                    }
                }
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(seconds < 600 ? Color.appleRed : Color.appleGreenText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var unauthenticatedLoginView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Autentifică-te cu contul YouthTB pentru titlul anual și codul QR de control. Biletele nu se cumpără din aplicație.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    TextField("Email sau telefon", text: $usernameInput)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    SecureField("Parolă", text: $passwordInput)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit { submitLogin() }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let message = appState.biletLoginError ?? loginError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.appleRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button(action: submitLogin) {
                    Group {
                        if isLoggingIn {
                            ProgressView()
                        } else {
                            Text("Autentificare")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.appBackground)
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: loginError) { _, new in new != nil }
    }
}
