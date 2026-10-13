/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>
#include "downloadonly.h"
#include "platformhelper.h"
#include "urlfmt.h"
#include "curlnetworkconfig.h"
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUuid>
#include <archive.h>
#include <archive_entry.h>
#include <functional>

namespace {
void application()
{
    static int argc = 1;
    static char name[] = "downloadonly_test";
    static char *argv[] = {name, nullptr};
    static QCoreApplication app(argc, argv);
    CurlNetworkConfig::ensureInitialized();
}

bool waitFor(const std::function<bool()> &condition)
{
    QElapsedTimer timer;
    timer.start();
    while (!condition() && timer.elapsed() < 10000) {
        QCoreApplication::processEvents();
        QThread::msleep(1);
    }
    QCoreApplication::processEvents();
    return condition();
}

struct Files {
    QString directory = QDir::currentPath() + "/downloadonly-test-" + QUuid::createUuid().toString(QUuid::Id128);
    Files() { REQUIRE(QDir().mkpath(directory)); }
    ~Files() { QDir(directory).removeRecursively(); }
    QString path(const QString &name) const { return directory + "/" + name; }
    QUrl url(const QString &name) const { return QUrl::fromLocalFile(path(name)); }
    void write(const QString &name, const QByteArray &data) const {
        QFile file(path(name));
        REQUIRE(file.open(QIODevice::WriteOnly));
        REQUIRE(file.write(data) == data.size());
    }
    QByteArray read(const QString &name) const {
        QFile file(path(name));
        REQUIRE(file.open(QIODevice::ReadOnly));
        return file.readAll();
    }
    void zip(const QList<QPair<QString, QByteArray>> &entries) const {
        archive *writer = archive_write_new();
        REQUIRE(archive_write_set_format_zip(writer) == ARCHIVE_OK);
        REQUIRE(archive_write_open_filename(writer, QFile::encodeName(path("artifact.zip")).constData()) == ARCHIVE_OK);
        for (const auto &[name, data] : entries) {
            archive_entry *entry = archive_entry_new();
            archive_entry_set_pathname(entry, name.toUtf8().constData());
            archive_entry_set_filetype(entry, AE_IFREG);
            archive_entry_set_perm(entry, 0644);
            archive_entry_set_size(entry, data.size());
            REQUIRE(archive_write_header(writer, entry) == ARCHIVE_OK);
            REQUIRE(archive_write_data(writer, data.constData(), data.size()) == data.size());
            archive_entry_free(entry);
        }
        REQUIRE(archive_write_close(writer) == ARCHIVE_OK);
        archive_write_free(writer);
    }
};
}

TEST_CASE("Save dialog normalizes local paths and rejects unavailable folders", "[downloadonly]")
{
    application();
    Files files;
    PlatformHelper helper;
    UrlFmt formatter;
    const QString path = files.directory + "/space # percent% folder";
    REQUIRE(QDir().mkpath(path));
    const QUrl url = helper.localFileUrl(path);
    REQUIRE(url.isLocalFile());
    REQUIRE(helper.directoryExists(url));
    REQUIRE(formatter.display(helper.localFileUrl(url.toString())) == path);
    REQUIRE(formatter.display(helper.localFileUrl(path + "/../space # percent% folder")) == path);
#ifndef Q_OS_WIN
    REQUIRE(formatter.display(helper.localFileUrl("file//" + path)) == path);
#endif
    REQUIRE(helper.localFileUrl("relative/folder").isEmpty());
    REQUIRE(helper.localFileUrl("https://example.com/folder").isEmpty());
    REQUIRE_FALSE(helper.directoryExists(helper.localFileUrl(files.path("missing"))));
    files.write("not-a-folder", "file");
    REQUIRE_FALSE(helper.directoryExists(helper.localFileUrl(files.path("not-a-folder"))));
}

TEST_CASE("Download only folder opening uses the configured launcher and reports failures", "[downloadonly]")
{
    application();
    Files files;
    files.write("image.spu", "payload");
    DownloadOnly transfer;
    transfer.start({{"url", files.url("image.spu").toString()}}, files.url("saved.spu"), {}, false);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE(transfer.error().isEmpty());
    QUrl opened;
    transfer.setFolderLauncher([&opened](const QUrl &url) {
        opened = url;
        return true;
    });
    REQUIRE(transfer.openContainingFolder());
    REQUIRE(opened.toLocalFile() == files.directory);
    transfer.setFolderLauncher([](const QUrl &) { return false; });
    REQUIRE_FALSE(transfer.openContainingFolder());
    REQUIRE_FALSE(transfer.error().isEmpty());
}

TEST_CASE("Download only preserves original compressed bytes and confirms overwrite", "[downloadonly]")
{
    application();
    Files files;
    const QByteArray original("\xfd\x37\x7a\x58\x5a\0original compressed payload", 33);
    files.write("image.wic.xz", original);
    files.write("saved.wic.xz", "existing");
    DownloadOnly transfer;
    QVariantMap source{{"url", files.url("image.wic.xz").toString()}};
    REQUIRE(transfer.suggestedFilename(source) == "image.wic.xz");
    REQUIRE(transfer.destinationExists(files.url("saved.wic.xz")));
    transfer.start(source, files.url("saved.wic.xz"), {}, false);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE_FALSE(transfer.error().isEmpty());
    REQUIRE(files.read("saved.wic.xz") == "existing");
    transfer.start(source, files.url("saved.wic.xz"), {}, true);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE(transfer.error().isEmpty());
    REQUIRE(transfer.savedFile() == files.url("saved.wic.xz"));
    REQUIRE(files.read("saved.wic.xz") == original);
}

TEST_CASE("Download only extracts exactly the selected ZIP entry without decompressing the image", "[downloadonly]")
{
    application();
    Files files;
    files.zip({{"other/image.wic.xz", "wrong"}, {"selected/image.wic.xz", "compressed image"},
               {"firmware.spu", "SPU"}, {"image.vsi", "VSI"}});
    DownloadOnly transfer;
    for (const QString &entry : {"selected/image.wic.xz", "firmware.spu", "image.vsi"}) {
        QVariantMap source{{"zip_path", files.path("artifact.zip")}, {"entry", entry}};
        const QString filename = QFileInfo(entry).fileName();
        transfer.start(source, files.url(filename), {}, false);
        REQUIRE(waitFor([&] { return !transfer.busy(); }));
        REQUIRE(transfer.error().isEmpty());
    }
    REQUIRE(files.read("image.wic.xz") == "compressed image");
    REQUIRE(files.read("firmware.spu") == "SPU");
    REQUIRE(files.read("image.vsi") == "VSI");
    REQUIRE(QDir(files.directory).entryList(QDir::Files | QDir::Hidden).size() == 4);
}

TEST_CASE("Missing ambiguous or broken artifact entries leave existing files unchanged", "[downloadonly]")
{
    application();
    Files files;
    files.zip({{"a/image.wic", "first"}, {"b/image.wic", "second"}});
    files.write("saved.wic", "existing");
    DownloadOnly transfer;
    QVariantMap source{{"zip_path", files.path("artifact.zip")}, {"entry", "missing.wic"}};
    SECTION("Missing entry") {}
    SECTION("Ambiguous streaming entry") {
        source["entry"] = "image.wic";
        source["match_basename"] = true;
    }
    SECTION("Broken ZIP") { files.write("artifact.zip", "not a ZIP"); }
    transfer.start(source, files.url("saved.wic"), {}, true);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE_FALSE(transfer.error().isEmpty());
    REQUIRE(transfer.savedFile().isEmpty());
    REQUIRE(files.read("saved.wic") == "existing");
    REQUIRE(QDir(files.directory).entryList(QDir::Files | QDir::Hidden).size() == 2);
}

TEST_CASE("Cancelling a network download cleans partial files and preserves the destination", "[downloadonly]")
{
    application();
    Files files;
    files.write("saved.spu", "existing");
    bool hadDestination = true;
    SECTION("Replacing an existing file") {}
    SECTION("Saving a new file") {
        REQUIRE(QFile::remove(files.path("saved.spu")));
        hadDestination = false;
    }
    QTcpServer server;
    REQUIRE(server.listen(QHostAddress::LocalHost));
    QTcpSocket *socket = nullptr;
    bool sent = false;
    QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        socket = server.nextPendingConnection();
        QObject::connect(socket, &QTcpSocket::readyRead, &server, [&] {
            socket->readAll();
            socket->write("HTTP/1.1 200 OK\r\nContent-Length: 100000000\r\n\r\n");
            socket->write(QByteArray(256 * 1024, 'x'));
            sent = true;
        });
    });
    DownloadOnly transfer;
    QVariantMap source{{"url", QString("http://127.0.0.1:%1/image.spu").arg(server.serverPort())}};
    transfer.start(source, files.url("saved.spu"), {}, true);
    REQUIRE(waitFor([&] { return sent; }));
    transfer.cancel();
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE(transfer.savedFile().isEmpty());
    REQUIRE(transfer.error().isEmpty());
    if (hadDestination) REQUIRE(files.read("saved.spu") == "existing");
    else REQUIRE_FALSE(QFileInfo::exists(files.path("saved.spu")));
    REQUIRE(QDir(files.directory).entryList(QDir::Files | QDir::Hidden).size() == (hadDestination ? 1 : 0));
    if (socket) socket->abort();
}

TEST_CASE("A destination created during download is not silently overwritten", "[downloadonly]")
{
    application();
    Files files;
    QTcpServer server;
    REQUIRE(server.listen(QHostAddress::LocalHost));
    QTcpSocket *socket = nullptr;
    bool sent = false;
    QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        socket = server.nextPendingConnection();
        QObject::connect(socket, &QTcpSocket::readyRead, &server, [&] {
            socket->readAll();
            socket->write("HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\norig");
            sent = true;
        });
    });
    DownloadOnly transfer;
    QVariantMap source{{"url", QString("http://127.0.0.1:%1/image.wic").arg(server.serverPort())}};
    transfer.start(source, files.url("saved.wic"), {}, false);
    REQUIRE(waitFor([&] { return sent; }));
    files.write("saved.wic", "created during download");
    socket->write("inal");
    socket->disconnectFromHost();
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE_FALSE(transfer.error().isEmpty());
    REQUIRE(transfer.savedFile().isEmpty());
    REQUIRE(files.read("saved.wic") == "created during download");
    REQUIRE(QDir(files.directory).entryList(QDir::Files | QDir::Hidden).size() == 1);
}

TEST_CASE("Network downloads save original bytes and surface HTTP and truncation failures", "[downloadonly]")
{
    application();
    Files files;
    files.write("saved.vsi", "existing");
    QTcpServer server;
    REQUIRE(server.listen(QHostAddress::LocalHost));
    QByteArray response = "HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\noriginal";
    bool expectError = false;
    SECTION("Success") {}
    SECTION("HTTP error") {
        response = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        expectError = true;
    }
    SECTION("Truncated response") {
        response = "HTTP/1.1 200 OK\r\nContent-Length: 800\r\nConnection: close\r\n\r\noriginal";
        expectError = true;
    }
    QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        auto *socket = server.nextPendingConnection();
        QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, response] {
            socket->readAll();
            socket->write(response);
            socket->disconnectFromHost();
        });
        QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    });
    DownloadOnly transfer;
    QVariantMap source{{"url", QString("http://127.0.0.1:%1/image.vsi").arg(server.serverPort())}};
    transfer.start(source, files.url("saved.vsi"), {}, true);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE(transfer.error().isEmpty() == !expectError);
    REQUIRE(files.read("saved.vsi") == (expectError ? "existing" : "original"));
    REQUIRE(transfer.savedFile().isEmpty() == expectError);
    REQUIRE(QDir(files.directory).entryList(QDir::Files | QDir::Hidden).size() == 1);
}

TEST_CASE("Download only rejects device-like and symbolic-link destinations", "[downloadonly]")
{
    application();
    Files files;
    files.write("image.vsi", "image");
    Files nested;
    DownloadOnly transfer;
    QVariantMap source{{"url", files.url("image.vsi").toString()}};
    transfer.start(source, QUrl::fromLocalFile(nested.directory), {}, true);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE_FALSE(transfer.error().isEmpty());
#ifndef Q_OS_WIN
    REQUIRE(QFile::link(files.path("image.vsi"), files.path("link.vsi")));
    transfer.start(source, files.url("link.vsi"), {}, true);
    REQUIRE(waitFor([&] { return !transfer.busy(); }));
    REQUIRE_FALSE(transfer.error().isEmpty());
    REQUIRE(files.read("image.vsi") == "image");
#endif
}
