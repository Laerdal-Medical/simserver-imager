/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>
#include <QVariantMap>

#include "../oslistmodel.h"
#include "../hwlistmodel.h"
#include "model_fixtures.h"

namespace {

QJsonObject entry(const QString &name, const QString &url = {}, const QString &description = QStringLiteral("desc"))
{
    QJsonObject o;
    o["name"] = name;
    o["url"] = url.isEmpty() ? QStringLiteral("https://cdn.example/%1.wic").arg(name) : url;
    o["description"] = description;
    return o;
}

QJsonObject release(const QString &name, const QString &tag, const QString &repo = QStringLiteral("repo"))
{
    QJsonObject o = entry(name, QStringLiteral("github-release://o/%1/releases/tag/%2").arg(repo, tag));
    o["source_type"] = "release";
    o["source_owner"] = "o";
    o["source_repo_name"] = repo;
    o["release_tag"] = tag;
    return o;
}

QJsonObject artifact(const QString &name, qint64 id, const QString &date)
{
    QJsonObject o = entry(name);
    o["source_type"] = "artifact";
    o["artifact_id"] = id;
    o["release_date"] = date;
    return o;
}

QJsonDocument doc(const QJsonArray &list)
{
    QJsonObject root;
    root["os_list"] = list;
    return QJsonDocument(root);
}

struct Fixture {
    TestOwner writer;
    OSListModel model{OSListModel::Source{[this] { return writer.osListDocument; },
                                          [this] { return writer.hw.currentArchitecture(); }}};
    QAbstractItemModel *base = &model;
    int resets = 0;
    int inserts = 0;
    int firstInsertedRow = -1;
    int parseEvents = 0;
    bool parseSuccess = false;
    QList<QList<int>> dataChangedRoles;

    Fixture()
    {
        writer.hw.reload();
        QObject::connect(&model, &QAbstractItemModel::modelReset, &model, [this] { ++resets; });
        QObject::connect(&model, &QAbstractItemModel::rowsInserted, &model, [this](const QModelIndex &, int first, int) {
            if (inserts++ == 0) firstInsertedRow = first;
        });
        QObject::connect(&model, &QAbstractItemModel::dataChanged, &model,
                         [this](const QModelIndex &, const QModelIndex &, const QList<int> &roles) { dataChangedRoles.append(roles); });
        QObject::connect(&model, &OSListModel::eventOsListParse, &model, [this](quint32, bool ok) { ++parseEvents; parseSuccess = ok; });
    }

    void load(const QJsonArray &list) { writer.osListDocument = doc(list); }
    QString name(int row) const { return base->data(base->index(row, 0), OSListModel::NameRole).toString(); }
    QString description(int row) const { return base->data(base->index(row, 0), OSListModel::DescriptionRole).toString(); }
    QStringList names() const
    {
        QStringList out;
        for (int i = 0; i < base->rowCount({}); ++i) out << name(i);
        return out;
    }
};

const QString kRecommended = QStringLiteral(" (Recommended)");

} // namespace

TEST_CASE("OSListModel orders releases, then CI artifacts, then others, with internal entries last", "[oslistmodel][sorting]")
{
    Fixture f;
    QJsonObject erase = entry("Erase", "internal://format");
    f.load({
        erase,
        entry("CDN v9.0.0"),
        artifact("Artifact old v9.9.9", 1, "2025-01-01"),
        release("SimPad v1.2.0", "v1.2.0"),
        artifact("Artifact new v0.0.1", 2, "2025-02-01"),
        release("SimPad v1.10.0-rc1", "v1.10.0-rc1"),
        release("Unversioned release", "nightly"),
        release("SimPad v1.10.0", "v1.10.0"),
        entry("Use custom", "internal://custom"),
    });

    REQUIRE(f.model.reload());

    REQUIRE(f.names() == QStringList{
        "SimPad v1.10.0",       // numeric (not lexicographic) comparison, final beats its pre-release
        "SimPad v1.10.0-rc1",
        "SimPad v1.2.0",
        "Unversioned release",  // versioned entries precede unversioned ones
        "Artifact new v0.0.1",  // artifacts: newest date first, version ignored
        "Artifact old v9.9.9",
        "CDN v9.0.0",
        "Erase",
        "Use custom",
    });
}

TEST_CASE("OSListModel compares four-part versions and prerelease identifiers by precedence", "[oslistmodel][sorting]")
{
    Fixture f;
    f.load({
        entry("Image v2.0.0-alpha.2"),
        entry("Image v2.0.0-alpha.10"),
        entry("Image v2.0.0-alpha"),
        entry("Image v2.0.0-beta"),
        entry("Image v2.0.0.1"),
        entry("Image v2.0.0"),
        entry("Image v2.0.0-alpha.beta"),
    });
    REQUIRE(f.model.reload());
    REQUIRE(f.names() == QStringList{
        "Image v2.0.0.1",
        "Image v2.0.0",
        "Image v2.0.0-beta",
        "Image v2.0.0-alpha.beta",   // alphanumeric identifiers outrank numeric ones
        "Image v2.0.0-alpha.10",     // numeric identifiers compare numerically
        "Image v2.0.0-alpha.2",
        "Image v2.0.0-alpha",        // a shorter identifier list is lower
    });
}

TEST_CASE("OSListModel ordering is deterministic regardless of input order", "[oslistmodel][sorting]")
{
    const QJsonArray forward{
        release("Same v1.0.0", "v1.0.0", "repoB"),
        release("Same v1.0.0", "v1.0.0", "repoA"),
        artifact("CI", 7, "2025-03-01"),
        artifact("CI", 5, "2025-03-01"),
    };
    QJsonArray reversed;
    for (qsizetype i = forward.size() - 1; i >= 0; --i) reversed.append(forward[i]);

    Fixture a;
    a.load(forward);
    a.model.reload();
    Fixture b;
    b.load(reversed);
    b.model.reload();

    QStringList keysA, keysB;
    for (int i = 0; i < 4; ++i) {
        keysA << a.model.getOsEntry(i).value("source_repo").toString() + QString::number(a.model.getOsEntry(i).value("artifact_id").toLongLong());
        keysB << b.model.getOsEntry(i).value("source_repo").toString() + QString::number(b.model.getOsEntry(i).value("artifact_id").toLongLong());
    }
    REQUIRE(keysA == keysB);
    REQUIRE(keysA.first() == "repoA0");
}

TEST_CASE("OSListModel marks only the first real image as recommended and never stacks the label", "[oslistmodel][recommended]")
{
    Fixture f;
    QJsonObject withSubitems = entry("Group v9.0.0");
    withSubitems["subitems"] = QJsonArray{entry("Child v9.0.0")};
    f.load({
        entry("Erase", "internal://format", "Format"),
        entry("Image v1.0.0", {}, "First" + kRecommended),
        entry("Image v0.9.0", {}, "Second (Recommended)"),
    });

    REQUIRE(f.model.reload());
    REQUIRE(f.description(0) == "First" + kRecommended);
    REQUIRE(f.description(1) == "Second");
    REQUIRE(f.description(2) == "Format");

    REQUIRE(f.model.reload());
    REQUIRE(f.description(0) == "First" + kRecommended);

    SECTION("an entry with subitems is not labelled")
    {
        f.load({withSubitems});
        REQUIRE(f.model.reload());
        REQUIRE(f.description(0) == "desc");
    }
    SECTION("an empty description is not labelled")
    {
        f.load({entry("Blank v1.0.0", {}, "")});
        REQUIRE(f.model.reload());
        REQUIRE(f.description(0).isEmpty());
    }
}

TEST_CASE("OSListModel prunes invalid init_format entries and flattens subitems", "[oslistmodel][filtering]")
{
    Fixture f;
    QJsonObject good = entry("Good v1.0.0");
    good["init_format"] = "cloudinit";
    QJsonObject bad = entry("Bad v2.0.0");
    bad["init_format"] = "bogus";

    QJsonObject goodChild = entry("Child ok");
    goodChild["init_format"] = "systemd";
    QJsonObject badChild = entry("Child bad");
    badChild["init_format"] = "nope";
    QJsonObject mixed = entry("Mixed v3.0.0");
    mixed["subitems"] = QJsonArray{badChild, goodChild};
    QJsonObject allBad = entry("AllBad v4.0.0");
    allBad["subitems"] = QJsonArray{badChild};

    f.load({good, bad, mixed, allBad});
    REQUIRE(f.model.reload());

    REQUIRE(f.names() == QStringList{"Mixed v3.0.0", "Good v1.0.0"});

    const QString subitems = f.base->data(f.base->index(0, 0), OSListModel::SubItemsJsonRole).toString();
    const QJsonArray children = QJsonDocument::fromJson(subitems.toUtf8()).array();
    REQUIRE(children.size() == 1);
    REQUIRE(children[0].toObject()["name"].toString() == "Child ok");
}

TEST_CASE("OSListModel prefers images matching the selected device architecture", "[oslistmodel][architecture]")
{
    Fixture f;
    QJsonObject arm32 = entry("Img v3.0.0");
    arm32["architecture"] = "armhf";
    QJsonObject arm64 = entry("Img v2.0.0");
    arm64["architecture"] = "aarch64";
    QJsonObject arm64b = entry("Img v1.0.0");
    arm64b["architecture"] = "aarch64";
    f.load({arm32, arm64, arm64b});

    SECTION("default device is armhf")
    {
        REQUIRE(f.writer.hw.currentArchitecture() == "armhf");
        REQUIRE(f.model.reload());
        REQUIRE(f.names() == QStringList{"Img v3.0.0", "Img v2.0.0", "Img v1.0.0"});
    }
    SECTION("switching to an aarch64 device moves its images first, keeping version order")
    {
        f.writer.hw.setCurrentIndex(1);
        REQUIRE(f.writer.hw.currentArchitecture() == "aarch64");
        REQUIRE(f.model.reload());
        REQUIRE(f.names() == QStringList{"Img v2.0.0", "Img v1.0.0", "Img v3.0.0"});
        REQUIRE(f.description(0) == "desc" + kRecommended);
        REQUIRE(f.description(2) == "desc");
    }
    SECTION("no selected device keeps pure version order")
    {
        f.writer.hw.setCurrentIndex(-1);
        REQUIRE(f.model.reload());
        REQUIRE(f.names() == QStringList{"Img v3.0.0", "Img v2.0.0", "Img v1.0.0"});
    }
}

TEST_CASE("OSListModel reload clears stale rows when the new list is empty or malformed", "[oslistmodel][reload]")
{
    Fixture f;
    f.load({entry("Image v1.0.0")});
    REQUIRE(f.model.reload());
    REQUIRE(f.base->rowCount({}) == 1);
    const int resetsAfterFirstLoad = f.resets;

    SECTION("empty os_list")
    {
        f.load({});
    }
    SECTION("document without os_list")
    {
        f.writer.osListDocument = QJsonDocument(QJsonObject{{"other", 1}});
    }
    SECTION("every entry pruned")
    {
        QJsonObject bad = entry("Bad v1.0.0");
        bad["init_format"] = "bogus";
        f.load({bad});
    }

    f.parseEvents = 0;
    REQUIRE(f.model.reload());
    REQUIRE(f.base->rowCount({}) == 0);
    REQUIRE(f.resets == resetsAfterFirstLoad + 1);
    REQUIRE(f.parseEvents == 1);
    REQUIRE(f.parseSuccess);

    // An already-empty model must not emit a reset again.
    REQUIRE(f.model.reload());
    REQUIRE(f.resets == resetsAfterFirstLoad + 1);
}

TEST_CASE("OSListModel incremental reload inserts new entries at their sorted position without resetting", "[oslistmodel][incremental]")
{
    Fixture f;
    f.load({artifact("Build v1.0.0", 1, "2025-01-01")});
    REQUIRE(f.model.reload());
    REQUIRE(f.description(0) == "desc" + kRecommended);
    const int resetsBefore = f.resets;

    f.load({artifact("Build v1.0.0 renamed", 1, "2025-01-01"), artifact("Build v2.0.0", 2, "2025-02-01")});
    f.dataChangedRoles.clear();
    REQUIRE(f.model.reloadIncremental());

    REQUIRE(f.resets == resetsBefore);
    REQUIRE(f.inserts == 1);
    REQUIRE(f.firstInsertedRow == 0);
    REQUIRE(f.base->rowCount({}) == 2);
    REQUIRE(f.name(0) == "Build v2.0.0");
    // Identity is the artifact id, so the renamed duplicate is not added again.
    REQUIRE(f.name(1) == "Build v1.0.0");
    // The recommendation moves to the new first row and the old one is cleared.
    REQUIRE(f.description(0) == "desc" + kRecommended);
    REQUIRE(f.description(1) == "desc");
    REQUIRE_FALSE(f.dataChangedRoles.isEmpty());
    REQUIRE(f.dataChangedRoles.last() == QList<int>{OSListModel::DescriptionRole});

    // Repeating the same update is a no-op for the row set.
    const int insertsBefore = f.inserts;
    REQUIRE(f.model.reloadIncremental());
    REQUIRE(f.inserts == insertsBefore);
    REQUIRE(f.base->rowCount({}) == 2);
}

TEST_CASE("OSListModel incremental reload distinguishes releases by repository and tag", "[oslistmodel][incremental]")
{
    Fixture f;
    f.load({release("Img v1.0.0", "v1.0.0", "repoA")});
    REQUIRE(f.model.reload());

    f.load({release("Img v1.0.0", "v1.0.0", "repoA"), release("Img v1.0.0", "v1.0.0", "repoB"),
            release("Img v1.1.0", "v1.1.0", "repoA")});
    REQUIRE(f.model.reloadIncremental());

    REQUIRE(f.base->rowCount({}) == 3);
    QStringList repos;
    for (int i = 0; i < 3; ++i) repos << f.model.getOsEntry(i).value("source_repo").toString() + "/" + f.model.getOsEntry(i).value("release_tag").toString();
    repos.sort();
    REQUIRE(repos == QStringList{"repoA/v1.0.0", "repoA/v1.1.0", "repoB/v1.0.0"});
}

TEST_CASE("OSListModel incremental reload only adds: it keeps rows and ignores empty updates", "[oslistmodel][incremental]")
{
    Fixture f;
    f.load({entry("Image v1.0.0"), entry("Image v2.0.0")});
    REQUIRE(f.model.reload());

    f.load({entry("Image v2.0.0")});
    f.parseEvents = 0;
    REQUIRE(f.model.reloadIncremental());
    REQUIRE(f.base->rowCount({}) == 2);

    f.load({});
    REQUIRE(f.model.reloadIncremental());
    REQUIRE(f.base->rowCount({}) == 2);
    REQUIRE(f.parseEvents == 2);
    REQUIRE(f.parseSuccess);
}

TEST_CASE("OSListModel incremental reload from an empty model appends in sorted order", "[oslistmodel][incremental]")
{
    Fixture f;
    f.load({entry("Image v1.0.0"), entry("Image v3.0.0"), entry("Image v2.0.0")});
    REQUIRE(f.model.reloadIncremental());
    REQUIRE(f.names() == QStringList{"Image v3.0.0", "Image v2.0.0", "Image v1.0.0"});
    REQUIRE(f.resets == 0);
    REQUIRE(f.inserts == 3);
}

TEST_CASE("OSListModel exposes parsed fields consistently through roles and getOsEntry", "[oslistmodel][fields]")
{
    Fixture f;
    QJsonObject o = release("Img v1.0.0", "v1.0.0");
    o["extract_size"] = 4294967296.0;
    o["image_download_size"] = 123456789.0;
    o["extract_sha256"] = "abc";
    o["devices"] = QJsonArray{"imx6", "linkbox"};
    o["asset_id"] = 99;
    o["branch"] = "main";
    o["release_assets"] = QJsonArray{QJsonObject{{"name", "a.wic"}, {"asset_id", 1}}, QJsonObject{{"name", "b.spu"}, {"asset_id", 2}}};
    f.load({o});
    REQUIRE(f.model.reload());

    const QVariantMap e = f.model.getOsEntry(0);
    REQUIRE(e["extract_size"].toULongLong() == 4294967296ULL);
    REQUIRE(e["image_download_size"].toULongLong() == 123456789ULL);
    REQUIRE(e["devices"].toStringList() == QStringList{"imx6", "linkbox"});
    REQUIRE(e["release_asset_id"].toLongLong() == 99);
    REQUIRE(e["release_tag"].toString() == "v1.0.0");
    REQUIRE(e["source_owner"].toString() == "o");
    REQUIRE(e["branch"].toString() == "main");
    const QVariantList assets = e["release_assets"].toList();
    REQUIRE(assets.size() == 2);
    REQUIRE(assets[1].toMap()["name"].toString() == "b.spu");

    const QVariant viaRole = f.base->data(f.base->index(0, 0), OSListModel::ReleaseAssetsRole);
    REQUIRE(viaRole.toList().size() == 2);

    REQUIRE(f.model.getOsEntry(-1).isEmpty());
    REQUIRE(f.model.getOsEntry(1).isEmpty());
    REQUIRE_FALSE(f.base->data(f.base->index(5, 0), OSListModel::NameRole).isValid());

    // Every role name exposed to QML must be populated for the same row.
    const auto names = f.base->roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it) {
        INFO("role " << it.value().toStdString());
        REQUIRE(f.base->data(f.base->index(0, 0), it.key()).isValid());
    }
}

TEST_CASE("OSListModel sanitises icon sources", "[oslistmodel][icons]")
{
    Fixture f;
    auto withIcon = [](const QString &n, const QString &icon) {
        QJsonObject o = entry(n);
        o["icon"] = icon;
        return o;
    };
    f.load({
        withIcon("A v9.0.0", "icons/a.png"),
        withIcon("B v8.0.0", "https://example.invalid/b.png"),
        withIcon("C v7.0.0", "qrc:/c.png"),
        withIcon("D v6.0.0", "https:///nohost.png"),
        withIcon("E v5.0.0", "relative.png"),
        withIcon("F v4.0.0", ""),
    });
    REQUIRE(f.model.reload());

    auto icon = [&](int row) { return f.model.getOsEntry(row)["icon"].toString(); };
    REQUIRE(icon(0) == "../icons/a.png");
    REQUIRE(icon(1) == "image://icons/https://example.invalid/b.png");
    REQUIRE(icon(2) == "qrc:/c.png");
    REQUIRE(icon(3).isEmpty());
    REQUIRE(icon(4) == "relative.png");
    REQUIRE(icon(5).isEmpty());
}

TEST_CASE("OSListModel softRefresh notifies all rows without resetting", "[oslistmodel]")
{
    Fixture f;
    f.model.softRefresh();
    REQUIRE(f.dataChangedRoles.isEmpty());

    f.load({entry("Image v1.0.0"), entry("Image v2.0.0")});
    REQUIRE(f.model.reload());
    const int resets = f.resets;
    f.model.softRefresh();
    REQUIRE(f.dataChangedRoles.size() == 1);
    REQUIRE(f.resets == resets);
}
