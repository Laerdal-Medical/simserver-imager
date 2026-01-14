/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2023 Raspberry Pi Ltd
 */

#include "macwlancredentials.h"
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <QProcess>
#include <QRegularExpression>
#include "ssid_helper.h"
#include "location_helper.h"

QByteArray MacWlanCredentials::getSSID()
{
    /* Note: Location permission request with async callback is handled by ImageWriter::getSSID()
     * to enable notification when permission is granted after the initial timeout.
     * Here we just check if we have permission and try to get the SSID. */

    /* Prefer CoreWLAN via Objective-C++ helper */
    if (_ssid.isEmpty())
    {
        const char *ssid_c = rpiimager_current_ssid_cstr();
        if (ssid_c)
        {
            _ssid = QByteArray(ssid_c);
            free((void*)ssid_c);
            if (!_ssid.isEmpty())
                qDebug() << "Detected SSID via CoreWLAN:" << _ssid;
        }
        else
        {
            /* Check if we have location permission - if not, SSID detection may have failed due to that */
            if (!rpiimager_check_location_permission())
            {
                qDebug() << "SSID detection failed - location permission not (yet) granted";
            }
        }
    }

    /* Removed legacy 'airport' tool fallback */

    /* Removed keychain-based SSID inference to avoid mis-filling */

    return _ssid;
}

QByteArray MacWlanCredentials::getPSK()
{
    if (_ssid.isEmpty())
    {
        qDebug() << "MacWlanCredentials::getPSK(): _ssid is empty, calling getSSID()";
        getSSID();
    }
    if (_ssid.isEmpty())
    {
        qDebug() << "MacWlanCredentials::getPSK(): _ssid still empty after getSSID(), cannot retrieve PSK";
        return QByteArray();
    }

    return getPSKForSSID(_ssid);
}

/* Helper function to search for WiFi password using modern SecItemCopyMatching API */
static QByteArray searchKeychainForPassword(const QByteArray &ssid, CFStringRef service)
{
    QByteArray psk;

    CFDataRef accountData = CFDataCreate(kCFAllocatorDefault,
                                         reinterpret_cast<const UInt8*>(ssid.constData()),
                                         ssid.length());
    if (!accountData)
        return psk;

    CFMutableDictionaryRef query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                             &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    if (!query)
    {
        CFRelease(accountData);
        return psk;
    }

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrAccount, accountData);
    if (service)
        CFDictionarySetValue(query, kSecAttrService, service);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result);

    if (status == errSecSuccess && result)
    {
        CFDataRef passwordData = static_cast<CFDataRef>(result);
        psk = QByteArray(reinterpret_cast<const char*>(CFDataGetBytePtr(passwordData)),
                         CFDataGetLength(passwordData));
        CFRelease(result);
    }

    CFRelease(query);
    CFRelease(accountData);

    return psk;
}

QByteArray MacWlanCredentials::getPSKForSSID(const QByteArray &ssid)
{
    if (ssid.isEmpty())
    {
        qDebug() << "MacWlanCredentials::getPSKForSSID(): Empty SSID provided, cannot retrieve PSK";
        return QByteArray();
    }

    qDebug() << "MacWlanCredentials::getPSKForSSID(): Attempting to retrieve PSK for SSID:" << ssid;

    QByteArray psk;

    /* Search with AirPort service name (standard for WiFi passwords) */
    CFStringRef airportService = CFSTR("AirPort");
    psk = searchKeychainForPassword(ssid, airportService);

    /* Fallback: search by account only without service filter */
    if (psk.isEmpty())
    {
        psk = searchKeychainForPassword(ssid, NULL);
    }

    if (!psk.isEmpty())
    {
        qDebug() << "MacWlanCredentials::getPSKForSSID(): Successfully retrieved PSK for SSID:" << ssid;
    }
    else
    {
        qDebug() << "MacWlanCredentials::getPSKForSSID(): No PSK found in keychain for SSID:" << ssid;
    }

    return psk;
}

WlanCredentials *WlanCredentials::_instance = NULL;
WlanCredentials *WlanCredentials::instance()
{
    if (!_instance)
        _instance = new MacWlanCredentials();

    return _instance;
}

