/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef GITHUBAUTH_H
#define GITHUBAUTH_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QSettings>

#ifndef CLI_ONLY_BUILD
#include <QQmlEngine>
#endif

/**
 * @brief GitHub OAuth Device Flow authentication handler
 *
 * Implements the GitHub Device Flow for OAuth authentication:
 * 1. Request device code from GitHub
 * 2. User visits verification URL and enters the code
 * 3. Poll GitHub for access token
 * 4. Store token securely for future use
 */
class GitHubAuth : public QObject
{
    Q_OBJECT
#ifndef CLI_ONLY_BUILD
    QML_ELEMENT
    QML_UNCREATABLE("Created by C++")
#endif

public:
    enum AuthState {
        Idle,               ///< No authentication in progress
        WaitingForUserCode, ///< Device code received, waiting for user to enter code
        Polling,            ///< Polling GitHub for access token
        Authenticated,      ///< Successfully authenticated
        Error               ///< Authentication failed
    };
    Q_ENUM(AuthState)

    explicit GitHubAuth(QObject *parent = nullptr);
    virtual ~GitHubAuth();

    // Properties exposed to QML
    Q_PROPERTY(AuthState state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString userCode READ userCode NOTIFY userCodeChanged)
    Q_PROPERTY(QString verificationUrl READ verificationUrl NOTIFY verificationUrlChanged)
    Q_PROPERTY(bool isAuthenticated READ isAuthenticated NOTIFY authenticationChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(int expiresIn READ expiresIn NOTIFY expiresInChanged)

    // Getters
    AuthState state() const { return _state; }
    QString userCode() const { return _userCode; }
    QString verificationUrl() const { return _verificationUrl; }
    bool isAuthenticated() const { return _state == Authenticated && !_accessToken.isEmpty(); }
    QString errorMessage() const { return _errorMessage; }
    int expiresIn() const { return _expiresIn; }
    QString accessToken() const { return _accessToken; }

    /**
     * @brief Start the OAuth Device Flow
     *
     * Requests a device code from GitHub and transitions to WaitingForUserCode state.
     * User should then visit the verification URL and enter the displayed code.
     */
    Q_INVOKABLE void startDeviceFlow();

    /**
     * @brief Cancel the current authentication attempt
     */
    Q_INVOKABLE void cancelAuth();

    /**
     * @brief Log out and clear stored token
     */
    Q_INVOKABLE void logout();

    /**
     * @brief Attempt to load a previously stored token
     * @return true if a valid token was loaded
     */
    Q_INVOKABLE bool loadStoredToken();

    /**
     * @brief Copy the user code to clipboard
     */
    Q_INVOKABLE void copyCodeToClipboard();

    /**
     * @brief Open the verification URL in the default browser
     */
    Q_INVOKABLE void openVerificationUrl();

    /**
     * @brief Set the GitHub OAuth Client ID
     * @param clientId The client ID from GitHub OAuth App settings
     */
    void setClientId(const QString &clientId);

signals:
    void stateChanged();
    void userCodeChanged();
    void verificationUrlChanged();
    void authenticationChanged();
    void errorMessageChanged();
    void expiresInChanged();
    void authError(const QString &message);
    void authSuccess();

private slots:
    void onDeviceCodeResponse(QNetworkReply *reply);
    void onTokenPollResponse(QNetworkReply *reply);
    void pollForToken();

private:
    void setState(AuthState newState);
    void setError(const QString &message);
    void storeToken(const QString &token);
    QString retrieveStoredToken();
    void clearStoredToken();
    QNetworkRequest createRequest(const QUrl &url);

    // GitHub OAuth endpoints
    static constexpr const char* DEVICE_CODE_URL = "https://github.com/login/device/code";
    static constexpr const char* TOKEN_URL = "https://github.com/login/oauth/access_token";

    // Required scope for accessing private repos
    static constexpr const char* SCOPE = "repo";

    // Settings key for storing token
    static constexpr const char* TOKEN_SETTINGS_KEY = "github/access_token";

    QNetworkAccessManager _networkManager;
    QSettings _settings;
    QTimer _pollTimer;

    AuthState _state = Idle;
    QString _clientId;
    QString _deviceCode;
    QString _userCode;
    QString _verificationUrl;
    QString _accessToken;
    QString _errorMessage;
    int _pollInterval = 5;  // seconds
    int _expiresIn = 0;     // seconds until code expires
};

#endif // GITHUBAUTH_H
