/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "githubauth.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrlQuery>
#include <QDesktopServices>
#include <QClipboard>
#include <QGuiApplication>
#include <QDebug>

GitHubAuth::GitHubAuth(QObject *parent)
    : QObject(parent)
{
    connect(&_pollTimer, &QTimer::timeout, this, &GitHubAuth::pollForToken);
}

GitHubAuth::~GitHubAuth()
{
    _pollTimer.stop();
}

void GitHubAuth::setClientId(const QString &clientId)
{
    _clientId = clientId;
}

void GitHubAuth::startDeviceFlow()
{
    if (_clientId.isEmpty()) {
        setError(tr("GitHub Client ID not configured"));
        return;
    }

    // Reset state
    _deviceCode.clear();
    _userCode.clear();
    _verificationUrl.clear();
    _accessToken.clear();
    _errorMessage.clear();
    _pollTimer.stop();

    setState(Idle);

    // Prepare request
    QUrl url(DEVICE_CODE_URL);
    QNetworkRequest request = createRequest(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    // Prepare form data
    QUrlQuery postData;
    postData.addQueryItem("client_id", _clientId);
    postData.addQueryItem("scope", SCOPE);

    QNetworkReply *reply = _networkManager.post(request, postData.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onDeviceCodeResponse(reply);
    });

    qDebug() << "GitHubAuth: Starting device flow...";
}

void GitHubAuth::onDeviceCodeResponse(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        setError(tr("Network error: %1").arg(reply->errorString()));
        return;
    }

    QByteArray responseData = reply->readAll();

    // GitHub returns form-encoded by default, but we requested JSON via Accept header
    QJsonDocument doc = QJsonDocument::fromJson(responseData);

    if (doc.isNull()) {
        // Try parsing as form-encoded
        QUrlQuery query(QString::fromUtf8(responseData));

        if (query.hasQueryItem("error")) {
            setError(query.queryItemValue("error_description"));
            return;
        }

        _deviceCode = query.queryItemValue("device_code");
        _userCode = query.queryItemValue("user_code");
        _verificationUrl = query.queryItemValue("verification_uri");
        _pollInterval = query.queryItemValue("interval").toInt();
        _expiresIn = query.queryItemValue("expires_in").toInt();
    } else {
        QJsonObject json = doc.object();

        if (json.contains("error")) {
            setError(json["error_description"].toString());
            return;
        }

        _deviceCode = json["device_code"].toString();
        _userCode = json["user_code"].toString();
        _verificationUrl = json["verification_uri"].toString();
        _pollInterval = json["interval"].toInt();
        _expiresIn = json["expires_in"].toInt();
    }

    if (_deviceCode.isEmpty() || _userCode.isEmpty()) {
        setError(tr("Invalid response from GitHub"));
        return;
    }

    // Ensure minimum poll interval
    if (_pollInterval < 5) {
        _pollInterval = 5;
    }

    qDebug() << "GitHubAuth: Got device code, user code:" << _userCode;
    qDebug() << "GitHubAuth: Verification URL:" << _verificationUrl;
    qDebug() << "GitHubAuth: Poll interval:" << _pollInterval << "seconds";
    qDebug() << "GitHubAuth: Expires in:" << _expiresIn << "seconds";

    emit userCodeChanged();
    emit verificationUrlChanged();
    emit expiresInChanged();

    setState(WaitingForUserCode);

    // Start polling for token
    _pollTimer.start(_pollInterval * 1000);
}

void GitHubAuth::pollForToken()
{
    if (_state != WaitingForUserCode && _state != Polling) {
        _pollTimer.stop();
        return;
    }

    setState(Polling);

    QUrl url(TOKEN_URL);
    QNetworkRequest request = createRequest(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QUrlQuery postData;
    postData.addQueryItem("client_id", _clientId);
    postData.addQueryItem("device_code", _deviceCode);
    postData.addQueryItem("grant_type", "urn:ietf:params:oauth:grant-type:device_code");

    QNetworkReply *reply = _networkManager.post(request, postData.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onTokenPollResponse(reply);
    });
}

void GitHubAuth::onTokenPollResponse(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        // Network error, keep polling
        qDebug() << "GitHubAuth: Network error while polling:" << reply->errorString();
        setState(WaitingForUserCode);
        return;
    }

    QByteArray responseData = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(responseData);

    QString error;
    QString accessToken;

    if (doc.isNull()) {
        // Try parsing as form-encoded
        QUrlQuery query(QString::fromUtf8(responseData));
        error = query.queryItemValue("error");
        accessToken = query.queryItemValue("access_token");
    } else {
        QJsonObject json = doc.object();
        error = json["error"].toString();
        accessToken = json["access_token"].toString();
    }

    if (!accessToken.isEmpty()) {
        // Success!
        _pollTimer.stop();
        _accessToken = accessToken;
        storeToken(_accessToken);

        qDebug() << "GitHubAuth: Successfully authenticated!";

        setState(Authenticated);
        emit authenticationChanged();
        emit authSuccess();
        return;
    }

    if (error == "authorization_pending") {
        // User hasn't authorized yet, keep polling
        qDebug() << "GitHubAuth: Authorization pending...";
        setState(WaitingForUserCode);
        return;
    }

    if (error == "slow_down") {
        // We're polling too fast, increase interval
        _pollInterval += 5;
        _pollTimer.setInterval(_pollInterval * 1000);
        qDebug() << "GitHubAuth: Slowing down, new interval:" << _pollInterval;
        setState(WaitingForUserCode);
        return;
    }

    if (error == "expired_token") {
        _pollTimer.stop();
        setError(tr("The device code has expired. Please try again."));
        return;
    }

    if (error == "access_denied") {
        _pollTimer.stop();
        setError(tr("Access was denied. Please try again and authorize the application."));
        return;
    }

    // Unknown error
    _pollTimer.stop();
    setError(tr("Authentication failed: %1").arg(error));
}

void GitHubAuth::cancelAuth()
{
    _pollTimer.stop();
    _deviceCode.clear();
    _userCode.clear();
    _verificationUrl.clear();
    _errorMessage.clear();

    setState(Idle);

    qDebug() << "GitHubAuth: Authentication cancelled";
}

void GitHubAuth::logout()
{
    _pollTimer.stop();
    _deviceCode.clear();
    _userCode.clear();
    _verificationUrl.clear();
    _accessToken.clear();
    _errorMessage.clear();

    clearStoredToken();

    setState(Idle);
    emit authenticationChanged();

    qDebug() << "GitHubAuth: Logged out";
}

bool GitHubAuth::loadStoredToken()
{
    QString token = retrieveStoredToken();

    if (token.isEmpty()) {
        return false;
    }

    _accessToken = token;
    setState(Authenticated);
    emit authenticationChanged();

    qDebug() << "GitHubAuth: Loaded stored token";
    return true;
}

void GitHubAuth::copyCodeToClipboard()
{
    if (!_userCode.isEmpty()) {
        QClipboard *clipboard = QGuiApplication::clipboard();
        if (clipboard) {
            clipboard->setText(_userCode);
            qDebug() << "GitHubAuth: User code copied to clipboard";
        }
    }
}

void GitHubAuth::openVerificationUrl()
{
    if (!_verificationUrl.isEmpty()) {
        QDesktopServices::openUrl(QUrl(_verificationUrl));
        qDebug() << "GitHubAuth: Opening verification URL in browser";
    }
}

void GitHubAuth::setState(AuthState newState)
{
    if (_state != newState) {
        _state = newState;
        emit stateChanged();
    }
}

void GitHubAuth::setError(const QString &message)
{
    _errorMessage = message;
    setState(Error);
    emit errorMessageChanged();
    emit authError(message);

    qWarning() << "GitHubAuth error:" << message;
}

void GitHubAuth::storeToken(const QString &token)
{
    // Simple storage in QSettings
    // For production, consider using platform-specific secure storage:
    // - macOS: Keychain
    // - Windows: Credential Manager
    // - Linux: libsecret/kwallet
    _settings.setValue(TOKEN_SETTINGS_KEY, token);
    _settings.sync();
}

QString GitHubAuth::retrieveStoredToken()
{
    return _settings.value(TOKEN_SETTINGS_KEY).toString();
}

void GitHubAuth::clearStoredToken()
{
    _settings.remove(TOKEN_SETTINGS_KEY);
    _settings.sync();
}

QNetworkRequest GitHubAuth::createRequest(const QUrl &url)
{
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager");
    request.setRawHeader("Accept", "application/json");
    return request;
}
