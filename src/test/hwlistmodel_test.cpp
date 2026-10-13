/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>

#include <QJsonArray>
#include <QSet>

#include "../hwlistmodel.h"
#include "../drivelistitem.h"
#include "model_fixtures.h"

namespace {

QString nameAt(QAbstractItemModel *m, int row)
{
    return m->data(m->index(row, 0), HWListModel::NameRole).toString();
}

QVariant roleAt(QAbstractItemModel *m, int row, int role)
{
    return m->data(m->index(row, 0), role);
}

} // namespace

TEST_CASE("HWListModel lists Laerdal devices followed by Erase and Use custom", "[hwlistmodel]")
{
    TestOwner writer;
    HWListModel &hw = writer.hw;
    QAbstractItemModel *m = &hw;
    REQUIRE(m->rowCount({}) == 0);
    REQUIRE(hw.reload());

    const int rows = m->rowCount({});
    REQUIRE(rows >= 3);
    REQUIRE(nameAt(m, rows - 2) == "Erase");
    REQUIRE(nameAt(m, rows - 1) == "Use custom");

    QSet<QString> seen;
    for (int i = 0; i < rows - 2; ++i) {
        INFO(nameAt(m, i).toStdString());
        REQUIRE_FALSE(seen.contains(nameAt(m, i)));
        seen.insert(nameAt(m, i));
        // Real devices filter strictly by tag and prefer an architecture.
        REQUIRE(roleAt(m, i, HWListModel::TagsRole).toJsonArray().size() >= 1);
        REQUIRE(roleAt(m, i, HWListModel::MatchingTypeRole).toString() == "exclusive");
        REQUIRE_FALSE(roleAt(m, i, HWListModel::ArchitectureRole).toString().isEmpty());
        REQUIRE_FALSE(roleAt(m, i, HWListModel::DisabledRole).toBool());
    }
    for (int i = rows - 2; i < rows; ++i) {
        // The two pseudo devices must never filter the OS list.
        REQUIRE(roleAt(m, i, HWListModel::TagsRole).toJsonArray().isEmpty());
        REQUIRE(roleAt(m, i, HWListModel::MatchingTypeRole).toString() == "inclusive");
        REQUIRE(roleAt(m, i, HWListModel::ArchitectureRole).toString().isEmpty());
    }
}

TEST_CASE("HWListModel reload is idempotent and preselects the default device", "[hwlistmodel]")
{
    TestOwner writer;
    HWListModel &hw = writer.hw;
    QAbstractItemModel *m = &hw;

    REQUIRE(hw.currentName() == "CHOOSE DEVICE");
    REQUIRE(hw.currentArchitecture().isEmpty());

    hw.reload();
    const int rows = m->rowCount({});
    hw.reload();
    REQUIRE(m->rowCount({}) == rows);

    REQUIRE(hw.currentIndex() == 0);
    REQUIRE(hw.currentName() == nameAt(m, 0));
    REQUIRE(writer.filterTags == roleAt(m, 0, HWListModel::TagsRole).toJsonArray());
    REQUIRE_FALSE(writer.filterInclusive);
}

TEST_CASE("HWListModel only clears the image source when the device really changes", "[hwlistmodel]")
{
    TestOwner writer;
    HWListModel &hw = writer.hw;
    QAbstractItemModel *m = &hw;
    hw.reload();
    REQUIRE(writer.clearImageCalls == 1);

    // Reloading and re-selecting the same default device keeps the image selection.
    hw.reload();
    REQUIRE(writer.clearImageCalls == 1);

    hw.setCurrentIndex(1);
    REQUIRE(writer.clearImageCalls == 2);
    REQUIRE(writer.filterTags == roleAt(m, 1, HWListModel::TagsRole).toJsonArray());
    REQUIRE(hw.currentArchitecture() == roleAt(m, 1, HWListModel::ArchitectureRole).toString());

    // A different row carrying identical tags/name would not count; same row does not either.
    int emitted = 0;
    QObject::connect(&hw, &HWListModel::currentIndexChanged, &hw, [&] { ++emitted; });
    hw.setCurrentIndex(1);
    REQUIRE(emitted == 0);

    const int erase = m->rowCount({}) - 2;
    hw.setCurrentIndex(erase);
    REQUIRE(writer.filterTags.isEmpty());
    REQUIRE(writer.filterInclusive);
    REQUIRE(hw.currentName() == "Erase");
    REQUIRE(hw.currentArchitecture().isEmpty());
    REQUIRE(emitted == 1);
}

TEST_CASE("HWListModel rejects out-of-range indexes and clears the selection with -1", "[hwlistmodel]")
{
    TestOwner writer;
    HWListModel &hw = writer.hw;
    hw.reload();
    const int count = static_cast<QAbstractItemModel &>(hw).rowCount({});

    hw.setCurrentIndex(count);
    REQUIRE(hw.currentIndex() == 0);
    hw.setCurrentIndex(-2);
    REQUIRE(hw.currentIndex() == 0);

    int names = 0, archs = 0;
    QObject::connect(&hw, &HWListModel::currentNameChanged, &hw, [&] { ++names; });
    QObject::connect(&hw, &HWListModel::currentArchitectureChanged, &hw, [&] { ++archs; });
    hw.setCurrentIndex(-1);
    REQUIRE(hw.currentIndex() == -1);
    REQUIRE(hw.currentName() == "CHOOSE DEVICE");
    REQUIRE(names == 1);
    REQUIRE(archs == 1);

    // Selecting the same device after clearing must clear the image source again.
    const int before = writer.clearImageCalls;
    hw.setCurrentIndex(0);
    REQUIRE(writer.clearImageCalls == before + 1);
}

TEST_CASE("DriveListItem converts large byte counts to truncated decimal gigabytes", "[drivelistitem]")
{
    DriveListItem item("/dev/sdb", "USB stick", 32000000000ULL, true, false, true, false,
                       {"/media/a"}, {"/dev/sdb1"});
    REQUIRE(item.sizeInGb() == 32);
    REQUIRE(DriveListItem("x", "y", 31999999999ULL).sizeInGb() == 31);
    REQUIRE(DriveListItem("x", "y", 999999999ULL).sizeInGb() == 0);
    // Sizes above the 32-bit byte range must not overflow the conversion.
    REQUIRE(DriveListItem("x", "y", 16000000000000ULL).sizeInGb() == 16000);
}
