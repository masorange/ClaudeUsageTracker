import SwiftUI

struct LoginPromptView: View {
    @ObservedObject var prefs: Preferences
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(prefs.tr("Sign in with your corporate account", "Inicia sesión con tu cuenta corporativa"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(prefs.tr("The app reads your personal AI usage from AI Platform using your SSO session. Nothing is stored outside your Mac.",
                          "La app lee tu consumo personal de IA desde AI Platform con tu sesión SSO. No se guarda nada fuera de tu Mac."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(prefs.tr("Sign in", "Iniciar sesión"), action: onSignIn)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(prefs.tr("Loading your usage…", "Cargando tu consumo…"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    @ObservedObject var prefs: Preferences
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button(prefs.tr("Retry", "Reintentar"), action: onRetry)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct BannerView: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(actionTitle, action: action).font(.caption)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}
