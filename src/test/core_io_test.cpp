/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */

#include <catch2/catch_test_macros.hpp>

#include "asynccachewriter.h"
#include "archiveentryiodevice.h"
#include "ringbuffer.h"

#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QFile>
#include <QList>
#include <QPair>
#include <QTemporaryDir>
#include <QThread>

#include <archive.h>
#include <archive_entry.h>

#include <chrono>
#include <cstring>
#include <future>
#include <memory>
#include <string>

namespace {

class CancelRingBufferOnExit
{
public:
    explicit CancelRingBufferOnExit(RingBuffer &buffer)
        : _buffer(buffer)
    {
    }

    ~CancelRingBufferOnExit()
    {
        _buffer.cancel();
    }

private:
    RingBuffer &_buffer;
};

struct ZipFixture {
    QTemporaryDir directory;

    ZipFixture()
    {
        REQUIRE(directory.isValid());
    }

    QString archivePath() const
    {
        return directory.filePath(QStringLiteral("fixture.zip"));
    }

    void create(const QList<QPair<QString, QByteArray>> &entries) const
    {
        using ArchivePtr = std::unique_ptr<archive, decltype(&archive_write_free)>;
        ArchivePtr writer(archive_write_new(), &archive_write_free);
        REQUIRE(writer);
        REQUIRE(archive_write_set_format_zip(writer.get()) == ARCHIVE_OK);

        const QByteArray filename = QFile::encodeName(archivePath());
        REQUIRE(archive_write_open_filename(writer.get(), filename.constData()) == ARCHIVE_OK);

        for (const auto &[name, data] : entries) {
            using EntryPtr = std::unique_ptr<archive_entry, decltype(&archive_entry_free)>;
            EntryPtr entry(archive_entry_new(), &archive_entry_free);
            REQUIRE(entry);

            const QByteArray encodedName = name.toUtf8();
            archive_entry_set_pathname(entry.get(), encodedName.constData());
            archive_entry_set_filetype(entry.get(), AE_IFREG);
            archive_entry_set_perm(entry.get(), 0644);
            archive_entry_set_size(entry.get(), data.size());
            REQUIRE(archive_write_header(writer.get(), entry.get()) == ARCHIVE_OK);
            REQUIRE(archive_write_data(writer.get(), data.constData(),
                                       static_cast<size_t>(data.size())) ==
                    static_cast<la_ssize_t>(data.size()));
        }

        REQUIRE(archive_write_close(writer.get()) == ARCHIVE_OK);
    }
};

QByteArray makePayload(qsizetype size)
{
    QByteArray payload(size, Qt::Uninitialized);
    for (qsizetype i = 0; i < size; ++i) {
        payload[i] = static_cast<char>((i * 37 + i / 251) & 0xff);
    }
    return payload;
}

bool waitForBytesWritten(const AsyncCacheWriter &writer, qint64 expected)
{
    QElapsedTimer timer;
    timer.start();
    while (writer.bytesWritten() != expected && timer.elapsed() < 3000) {
        QThread::msleep(1);
    }
    return writer.bytesWritten() == expected;
}

} // namespace

TEST_CASE("RingBuffer applies backpressure, wraps slots, and drains after producer completion",
          "[ringbuffer]")
{
    RingBuffer buffer(2, 8, 64);

    auto *first = buffer.acquireWriteSlot();
    REQUIRE(first);
    std::memcpy(first->data, "first", 5);
    buffer.commitWriteSlot(first, 5);

    auto *second = buffer.acquireWriteSlot();
    REQUIRE(second);
    std::memcpy(second->data, "second", 6);
    buffer.commitWriteSlot(second, 6);

    REQUIRE(buffer.getCommittedCount() == 2);
    REQUIRE(buffer.acquireWriteSlot(5) == nullptr);

    auto *readFirst = buffer.acquireReadSlot();
    REQUIRE(readFirst);
    REQUIRE(std::string(readFirst->data, readFirst->size) == "first");
    buffer.releaseReadSlot(readFirst);

    auto *third = buffer.acquireWriteSlot();
    REQUIRE(third);
    std::memcpy(third->data, "third", 5);
    buffer.commitWriteSlot(third, 5);

    buffer.producerDone();
    REQUIRE_FALSE(buffer.isComplete());
    for (const std::string expected : {"second", "third"}) {
        auto *slot = buffer.acquireReadSlot();
        REQUIRE(slot);
        REQUIRE(std::string(slot->data, slot->size) == expected);
        buffer.releaseReadSlot(slot);
    }

    REQUIRE(buffer.acquireReadSlot() == nullptr);
    REQUIRE(buffer.isComplete());
}

TEST_CASE("RingBuffer cancellation wakes blocked producer and consumer", "[ringbuffer]")
{
    SECTION("consumer waiting for data")
    {
        RingBuffer buffer(1, 8, 64);
        std::promise<void> entered;
        auto started = entered.get_future();
        auto waitingRead = std::async(std::launch::async, [&buffer, &entered] {
            entered.set_value();
            return buffer.acquireReadSlot(5000);
        });
        CancelRingBufferOnExit cancelOnExit(buffer);
        started.wait();
        const bool wasBlocked =
            waitingRead.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout;

        buffer.cancel();

        REQUIRE(wasBlocked);
        REQUIRE(waitingRead.wait_for(std::chrono::seconds(1)) == std::future_status::ready);
        REQUIRE(waitingRead.get() == nullptr);
    }

    SECTION("producer waiting for a released slot")
    {
        RingBuffer buffer(1, 8, 64);
        auto *slot = buffer.acquireWriteSlot();
        REQUIRE(slot);

        std::promise<void> entered;
        auto started = entered.get_future();
        auto waitingWrite = std::async(std::launch::async, [&buffer, &entered] {
            entered.set_value();
            return buffer.acquireWriteSlot(5000);
        });
        CancelRingBufferOnExit cancelOnExit(buffer);
        started.wait();
        const bool wasBlocked =
            waitingWrite.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout;

        buffer.cancel();

        REQUIRE(wasBlocked);
        REQUIRE(waitingWrite.wait_for(std::chrono::seconds(1)) == std::future_status::ready);
        REQUIRE(waitingWrite.get() == nullptr);
    }
}

TEST_CASE("RingBuffer preserves ordered payloads across concurrent slot reuse", "[ringbuffer]")
{
    constexpr std::uint64_t itemCount = 1000;
    RingBuffer buffer(3, sizeof(std::uint64_t), 64);

    auto producer = std::async(std::launch::async, [&buffer] {
        for (std::uint64_t value = 0; value < itemCount; ++value) {
            auto *slot = buffer.acquireWriteSlot(5000);
            if (!slot) {
                buffer.cancel();
                return false;
            }
            std::memcpy(slot->data, &value, sizeof(value));
            buffer.commitWriteSlot(slot, sizeof(value));
        }
        buffer.producerDone();
        return true;
    });
    CancelRingBufferOnExit cancelOnExit(buffer);

    for (std::uint64_t expected = 0; expected < itemCount; ++expected) {
        auto *slot = buffer.acquireReadSlot(1000);
        REQUIRE(slot);
        std::uint64_t actual = 0;
        REQUIRE(slot->size == sizeof(actual));
        std::memcpy(&actual, slot->data, sizeof(actual));
        REQUIRE(actual == expected);
        buffer.releaseReadSlot(slot);
    }

    REQUIRE(producer.wait_for(std::chrono::seconds(5)) == std::future_status::ready);
    REQUIRE(producer.get());
    REQUIRE(buffer.acquireReadSlot() == nullptr);
    REQUIRE(buffer.isComplete());
}

TEST_CASE("ArchiveEntryIODevice streams the selected ZIP member to EOF", "[archiveentry]")
{
    ZipFixture fixture;
    const QByteArray expected = makePayload(150'123);
    fixture.create({{QStringLiteral("metadata/readme.txt"), QByteArrayLiteral("metadata")},
                    {QStringLiteral("nested/image.wic"), expected}});

    ArchiveEntryIODevice device(fixture.archivePath(), QStringLiteral("image.wic"));
    REQUIRE(device.isSequential());
    REQUIRE(device.open(QIODevice::ReadOnly));
    REQUIRE(device.size() == expected.size());
    REQUIRE_FALSE(device.atEnd());

    QByteArray actual;
    while (!device.atEnd()) {
        const QByteArray chunk = device.read(997);
        if (chunk.isEmpty()) {
            break;
        }
        actual.append(chunk);
    }

    REQUIRE(actual == expected);
    REQUIRE(device.atEnd());
    REQUIRE(device.read(1).isEmpty());
}

TEST_CASE("ArchiveEntryIODevice rejects missing members and non-read-only opens", "[archiveentry]")
{
    ZipFixture fixture;
    fixture.create({{QStringLiteral("image.wic"), QByteArrayLiteral("image")}});

    ArchiveEntryIODevice missing(fixture.archivePath(), QStringLiteral("missing.wic"));
    REQUIRE_FALSE(missing.open(QIODevice::ReadOnly));
    REQUIRE_FALSE(missing.isOpen());

    ArchiveEntryIODevice writeOnly(fixture.archivePath(), QStringLiteral("image.wic"));
    REQUIRE_FALSE(writeOnly.open(QIODevice::WriteOnly));
    REQUIRE_FALSE(writeOnly.isOpen());
}

TEST_CASE("AsyncCacheWriter preserves fully written data when finishing a partial cache",
          "[async-cache]")
{
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("partial.cache"));
    QByteArray expectedFile;

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));
    for (int chunkIndex = 0; chunkIndex < 8; ++chunkIndex) {
        const QByteArray chunk = makePayload(64 * 1024 + chunkIndex);
        REQUIRE(writer.write(chunk.constData(), static_cast<size_t>(chunk.size())));
        expectedFile.append(chunk);
    }

    writer.finishPartial();

    REQUIRE_FALSE(writer.isRunning());
    REQUIRE_FALSE(writer.isActive());
    REQUIRE(writer.bytesWritten() == expectedFile.size());
    REQUIRE(QFile::exists(path));
    QFile file(path);
    REQUIRE(file.open(QIODevice::ReadOnly));
    REQUIRE(file.readAll() == expectedFile);
}

TEST_CASE("AsyncCacheWriter appends partial cache data and hashes the resumed payload",
          "[async-cache]")
{
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("resumed.cache"));
    const QByteArray existingData = makePayload(257);
    const QByteArray appendedData = makePayload(4099);

    QFile existingFile(path);
    REQUIRE(existingFile.open(QIODevice::WriteOnly));
    REQUIRE(existingFile.write(existingData) == existingData.size());
    existingFile.close();

    AsyncCacheWriter writer;
    REQUIRE(writer.openForAppend(path));
    for (qsizetype offset = 0; offset < appendedData.size(); offset += 512) {
        const qsizetype size = qMin(qsizetype(512), appendedData.size() - offset);
        REQUIRE(writer.write(appendedData.constData() + offset, static_cast<size_t>(size)));
    }

    writer.finishPartial();

    REQUIRE_FALSE(writer.isRunning());
    REQUIRE_FALSE(writer.isActive());
    REQUIRE(writer.bytesWritten() == existingData.size() + appendedData.size());
    REQUIRE(writer.hash() ==
            QCryptographicHash::hash(appendedData, QCryptographicHash::Sha256).toHex());

    QFile resumedFile(path);
    REQUIRE(resumedFile.open(QIODevice::ReadOnly));
    REQUIRE(resumedFile.readAll() == existingData + appendedData);
}

TEST_CASE("AsyncCacheWriter cancellation removes its partial output", "[async-cache]")
{
    QTemporaryDir directory;
    REQUIRE(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("cancelled.cache"));
    const QByteArray payload = makePayload(4097);

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));
    REQUIRE(writer.write(payload.constData(), static_cast<size_t>(payload.size())));
    REQUIRE(waitForBytesWritten(writer, payload.size()));

    writer.cancel();

    REQUIRE_FALSE(writer.isRunning());
    REQUIRE_FALSE(writer.isActive());
    REQUIRE_FALSE(QFile::exists(path));
}
