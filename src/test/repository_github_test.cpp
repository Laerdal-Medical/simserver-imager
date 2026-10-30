/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_session.hpp>

#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QSettings>
#include <QTemporaryDir>
#include <QUrl>
#include <QtNetwork>


#include "../github/githubclient.h"
#include "../repository/githubsource.h"
#include "../repository/laerdalcdnsource.h"
#include "../repository/repositorymanager.h"

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    return Catch::Session().run(argc, argv);
}

namespace {

// Redirects every QSettings() created afterwards into a throw-away directory.
struct IsolatedSettings {
    QTemporaryDir dir;
    IsolatedSettings()
    {
        REQUIRE(dir.isValid());
        QCoreApplication::setOrganizationName(QStringLiteral("LaerdalImagerTest"));
        QCoreApplication::setApplicationName(QStringLiteral("repository_github_test"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        for (auto format : {QSettings::NativeFormat, QSettings::IniFormat})
            for (auto scope : {QSettings::UserScope, QSettings::SystemScope})
                QSettings::setPath(format, scope, dir.path());
    }
};

bool waitFor(const std::function<bool()> &predicate, int timeoutMs = 5000)
{
    QDeadlineTimer deadline(timeoutMs);
    while (!predicate() && !deadline.hasExpired()) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    }
    return predicate();
}

QString writeFile(const QTemporaryDir &dir, const QString &name, const QByteArray &data)
{
    const QString path = dir.filePath(name);
    QFile f(path);
    REQUIRE(f.open(QIODevice::WriteOnly));
    REQUIRE(f.write(data) == data.size());
    return path;
}

QStringList strings(const QJsonArray &array)
{
    QStringList out;
    for (const auto &v : array) out << v.toString();
    return out;
}

QStringList sorted(QStringList l)
{
    l.sort();
    return l;
}

QJsonObject asset(const QString &name, qint64 id = 1)
{
    return QJsonObject{{"name", name}, {"asset_id", id}, {"size", 10}, {"type", "wic"}};
}

QJsonObject releaseGroup(const QString &tag, const QString &releaseName, const QJsonArray &assets,
                         const QString &published = QStringLiteral("2025-05-01T00:00:00Z"))
{
    return QJsonObject{{"tag", tag}, {"release_name", releaseName}, {"owner", "Laerdal-Medical"},
                       {"repo", "simpad"}, {"published_at", published}, {"prerelease", false},
                       {"assets", assets}};
}

QJsonObject artifactFile(qint64 id, const QString &name, const QString &branch, const QString &created)
{
    return QJsonObject{{"name", name}, {"artifact_id", id}, {"size", 2048}, {"branch", branch},
                       {"created_at", created}, {"owner", "Laerdal-Medical"}, {"repo", "simpad"},
                       {"run_id", 77}, {"download_url", QStringLiteral("https://api.example/zip/%1").arg(id)}};
}

struct Spy {
    int count = 0;
    template<typename Obj, typename Signal>
    Spy(Obj *obj, Signal signal)
    {
        QObject::connect(obj, signal, obj, [this] { ++count; });
    }
};

const QJsonArray kDefaultRepos = QJsonArray{
    QJsonObject{{"owner", "Laerdal-Medical"}, {"repo", "simpad"}, {"defaultBranch", "develop"}},
    QJsonObject{{"owner", "Laerdal-Medical"}, {"repo", "linkbox"}, {"defaultBranch", "main"}},
};

QString json(const QJsonArray &a) { return QString::fromUtf8(QJsonDocument(a).toJson(QJsonDocument::Compact)); }

} // namespace

// ---------------------------------------------------------------- RepositoryManager

TEST_CASE("RepositoryManager persists environment, source type and branch filter", "[repository][settings]")
{
    IsolatedSettings iso;
    {
        RepositoryManager mgr;
        Spy env(&mgr, &RepositoryManager::environmentChanged);
        Spy src(&mgr, &RepositoryManager::selectedSourceTypeChanged);
        Spy osReady(&mgr, &RepositoryManager::osListReady);
        Spy branch(&mgr, &RepositoryManager::artifactBranchFilterChanged);

        mgr.setCurrentEnvironment(RepositoryManager::Dev);
        mgr.setCurrentEnvironment(RepositoryManager::Dev);
        REQUIRE(env.count == 1);

        mgr.setSelectedSourceType("github-ci");
        mgr.setSelectedSourceType("github-ci");
        REQUIRE(src.count == 1);
        REQUIRE(osReady.count == 1);

        mgr.setArtifactBranchFilter("release/9.3");
        mgr.setArtifactBranchFilter("release/9.3");
        REQUIRE(branch.count == 1);
    }
    RepositoryManager restored;
    restored.loadSettings();
    REQUIRE(restored.currentEnvironment() == RepositoryManager::Dev);
    REQUIRE(restored.selectedSourceType() == "github-ci");
    REQUIRE(restored.artifactBranchFilter() == "release/9.3");
}

TEST_CASE("RepositoryManager migrates the legacy 'github' source type", "[repository][settings]")
{
    IsolatedSettings iso;
    QString expectedType, expectedFilter;

    SECTION("RELEASES_ONLY becomes github-releases without a branch filter")
    {
        QSettings s;
        s.setValue("laerdal/source_type", "github");
        s.setValue("laerdal/artifact_branch_filter", "RELEASES_ONLY");
        expectedType = "github-releases";
    }
    SECTION("any other filter becomes github-ci and keeps its branch")
    {
        QSettings s;
        s.setValue("laerdal/source_type", "github");
        s.setValue("laerdal/artifact_branch_filter", "develop");
        expectedType = "github-ci";
        expectedFilter = "develop";
    }
    SECTION("a lingering RELEASES_ONLY marker is dropped from current source types")
    {
        QSettings s;
        s.setValue("laerdal/source_type", "github-ci");
        s.setValue("laerdal/artifact_branch_filter", "RELEASES_ONLY");
        expectedType = "github-ci";
    }

    {
        RepositoryManager mgr;
        mgr.loadSettings();
        REQUIRE(mgr.selectedSourceType() == expectedType);
        REQUIRE(mgr.artifactBranchFilter() == expectedFilter);
    }
    // The migration itself must have been written back.
    RepositoryManager again;
    again.loadSettings();
    REQUIRE(again.selectedSourceType() == expectedType);
    REQUIRE(again.artifactBranchFilter() == expectedFilter);
}

TEST_CASE("RepositoryManager parses repository JSON defensively", "[repository][config]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    Spy changed(&mgr, &RepositoryManager::reposChanged);

    mgr.loadReposFromJson(json({
        QJsonObject{{"owner", "a"}, {"repo", "b"}},
        QJsonObject{{"owner", ""}, {"repo", "skipped"}},
        QJsonObject{{"owner", "skipped"}},
        QJsonObject{{"owner", "c"}, {"repo", "d"}, {"defaultBranch", "dev"}},
    }));
    const QJsonArray repos = mgr.githubRepos();
    REQUIRE(repos.size() == 2);
    REQUIRE(repos[0].toObject()["defaultBranch"].toString() == "main");
    REQUIRE(repos[0].toObject()["enabled"].toBool());
    REQUIRE(repos[0].toObject()["fullName"].toString() == "a/b");
    REQUIRE(repos[1].toObject()["defaultBranch"].toString() == "dev");
    REQUIRE(changed.count == 1);

    // Round trip through the JSON used for persistence.
    RepositoryManager other;
    other.loadReposFromJson(mgr.reposToJson());
    REQUIRE(other.githubRepos().size() == 2);

    mgr.loadReposFromJson("not json");
    REQUIRE(mgr.githubRepos().isEmpty());
    mgr.loadReposFromJson("{\"owner\":\"a\"}");
    REQUIRE(mgr.githubRepos().isEmpty());
}

TEST_CASE("RepositoryManager seeds default repositories once and then respects user changes", "[repository][config]")
{
    IsolatedSettings iso;
    {
        RepositoryManager first;
        first.loadReposFromJson(json(kDefaultRepos));
        first.loadSettings();
        REQUIRE(first.githubRepos().size() == 2);

        first.setRepoEnabled("Laerdal-Medical", "simpad", false);
        first.setDefaultBranch("Laerdal-Medical", "simpad", "hotfix");
        first.removeGitHubRepo("Laerdal-Medical", "linkbox");
    }

    RepositoryManager second;
    second.loadReposFromJson(json(kDefaultRepos));
    second.loadSettings();

    const QJsonArray repos = second.githubRepos();
    // The removed default is not resurrected and the per-repo state survives restarts.
    REQUIRE(repos.size() == 1);
    REQUIRE(repos[0].toObject()["repo"].toString() == "simpad");
    REQUIRE_FALSE(repos[0].toObject()["enabled"].toBool());
    REQUIRE(repos[0].toObject()["defaultBranch"].toString() == "hotfix");
}

TEST_CASE("RepositoryManager keeps custom repositories and de-duplicates defaults case-insensitively", "[repository][config]")
{
    IsolatedSettings iso;
    {
        QSettings s;
        s.setValue("laerdal/github_repos",
                   json({QJsonObject{{"owner", "laerdal-medical"}, {"repo", "SIMPAD"}, {"defaultBranch", "mine"}},
                         QJsonObject{{"owner", "custom"}, {"repo", "thing"}}}));
    }
    RepositoryManager mgr;
    mgr.loadReposFromJson(json(kDefaultRepos));
    mgr.loadSettings();

    QStringList full;
    for (const auto &r : mgr.githubRepos()) full << r.toObject()["fullName"].toString();
    REQUIRE(sorted(full) == sorted({"laerdal-medical/SIMPAD", "custom/thing", "Laerdal-Medical/linkbox"}));
}

TEST_CASE("RepositoryManager converts release groups into device-tagged OS entries", "[repository][releases]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    GitHubClient client;
    mgr.setGitHubClient(&client);
    Spy ready(&mgr, &RepositoryManager::osListReady);
    Spy github(&mgr, &RepositoryManager::githubListReady);

    emit client.wicFilesReady(QJsonArray{
        releaseGroup("v9.3.0", "SimPad Plus 9.3.0",
                     {asset("simpad-plus-9.3.0.wic.xz", 11), asset("simpad-plus-9.3.0.vsi", 12)}),
        releaseGroup("v1.0.0-rc1", "Generic image", {asset("rootfs.wic", 13)}, "2025-01-01T00:00:00Z"),
        releaseGroup("simpad-plus2-v2.0.0", "Plus2 drop", {asset("rootfs.wic.gz", 14)}, "2025-03-01T00:00:00Z"),
    });

    REQUIRE(ready.count == 1);
    REQUIRE(github.count == 1);

    mgr.setGitHubClient(nullptr);
    mgr.setSelectedSourceType("github-releases");
    const QJsonArray list = mgr.getMergedOsList();
    REQUIRE(list.size() == 3);

    // Newest release first.
    REQUIRE(list[0].toObject()["release_tag"].toString() == "v9.3.0");
    REQUIRE(list[1].toObject()["release_tag"].toString() == "simpad-plus2-v2.0.0");
    REQUIRE(list[2].toObject()["release_tag"].toString() == "v1.0.0-rc1");

    const QJsonObject plus = list[0].toObject();
    REQUIRE(plus["name"].toString() == "SimPad Plus v9.3.0");
    REQUIRE(plus["url"].toString() == "github-release://Laerdal-Medical/simpad/releases/tag/v9.3.0");
    REQUIRE(plus["source_type"].toString() == "release");
    REQUIRE(plus["init_format"].toString() == "none");
    REQUIRE(plus["release_assets"].toArray().size() == 2);
    REQUIRE(sorted(strings(plus["devices"].toArray())) == sorted({"imx6", "linkbox", "cancpu"}));
    REQUIRE(plus["icon"].toString().endsWith("simpad_plus.png"));

    // Device detection falls back to the release tag when assets are generic.
    REQUIRE(sorted(strings(list[1].toObject()["devices"].toArray())) == sorted({"imx8", "linkbox2", "cancpu2"}));
    REQUIRE(list[1].toObject()["name"].toString() == "SimPad Plus 2 v2.0.0");

    // No device or recognisable pattern: all-device entry using the release name.
    const QJsonObject generic = list[2].toObject();
    REQUIRE(generic["devices"].toArray().isEmpty());
    REQUIRE(generic["name"].toString() == "v1.0.0-rc1");
    REQUIRE(generic["icon"].toString().endsWith("use_custom.png"));
}

TEST_CASE("RepositoryManager shows full asset versions below release selection names", "[repository][releases]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    GitHubClient client;
    mgr.setGitHubClient(&client);

    QString expectedBuildLine;
    QJsonArray assets;
    SECTION("Repeated build versions are displayed once") {
        assets = {asset("simpad-plus-9.2.0.127.wic.xz"),
                  asset("simpad-plus-9.2.0.127.spu")};
        expectedBuildLine = "[9.2.0.127]\n";
    }
    SECTION("Distinct build versions are all displayed") {
        assets = {asset("simpad-plus-9.2.0.128.wic.xz"),
                  asset("simpad-plus-9.2.0.127.spu")};
        expectedBuildLine = "[9.2.0.127, 9.2.0.128]\n";
    }
    SECTION("Versions already in the title are not duplicated") {
        assets = {asset("simpad-plus-9.2.0.wic.xz")};
    }
    SECTION("Unversioned assets leave the title unchanged") {
        assets = {asset("factory-image.wic.xz")};
    }

    emit client.wicFilesReady(QJsonArray{releaseGroup("v9.2.0", "SimPad Plus 9.2.0", assets)});
    mgr.setGitHubClient(nullptr);
    mgr.setSelectedSourceType("github-releases");
    const QJsonArray list = mgr.getMergedOsList();
    REQUIRE(list.size() == 1);
    REQUIRE(list[0].toObject()["name"].toString() == "SimPad Plus v9.2.0");
    REQUIRE(list[0].toObject()["description"].toString()
            == expectedBuildLine + "Laerdal-Medical/simpad - Release: SimPad Plus 9.2.0");
    REQUIRE(list[0].toObject()["release_tag"].toString() == "v9.2.0");
    REQUIRE(list[0].toObject()["release_assets"].toArray() == assets);
}

TEST_CASE("RepositoryManager de-duplicates CI artifacts across incremental batches", "[repository][artifacts]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    GitHubClient client;
    mgr.setGitHubClient(&client);
    Spy ready(&mgr, &RepositoryManager::osListReady);

    const QJsonArray first{
        artifactFile(1, "wic-simpad-plus-9.3.0", "main", "2025-02-01T00:00:00Z"),
        artifactFile(0, "invalid-id", "main", "2025-02-02T00:00:00Z"),
        artifactFile(2, "wic-simpad-plus2-9.3.1", "develop", "2025-02-03T00:00:00Z"),
    };
    emit client.artifactWicFilesBatchReady(first);
    REQUIRE(ready.count == 1);

    // A page that only repeats known artifacts does not notify.
    emit client.artifactWicFilesBatchReady(QJsonArray{first[0]});
    REQUIRE(ready.count == 1);

    // The completion signal adds only what the batches missed.
    emit client.artifactWicFilesReady(QJsonArray{first[0], first[2], artifactFile(3, "build-wic", "main", "2025-02-04T00:00:00Z")});

    mgr.setGitHubClient(nullptr);
    mgr.setSelectedSourceType("github-ci");

    QJsonArray all = mgr.getMergedOsList();
    REQUIRE(all.size() == 3);
    REQUIRE(all[0].toObject()["artifact_id"].toVariant().toLongLong() == 3);
    REQUIRE(all[1].toObject()["artifact_id"].toVariant().toLongLong() == 2);

    const QJsonObject plus2 = all[1].toObject();
    REQUIRE(plus2["name"].toString() == "SimPad Plus 2 v9.3.1");
    REQUIRE(plus2["description"].toString() == "Laerdal-Medical/simpad - Branch: develop");
    REQUIRE(plus2["source_type"].toString() == "artifact");
    REQUIRE(plus2["extract_size"].toVariant().toLongLong() == 2048);

    mgr.setArtifactBranchFilter("develop");
    all = mgr.getMergedOsList();
    REQUIRE(all.size() == 1);
    REQUIRE(all[0].toObject()["branch"].toString() == "develop");

    mgr.setArtifactBranchFilter("does-not-exist");
    REQUIRE(mgr.getMergedOsList().isEmpty());
}

TEST_CASE("RepositoryManager separates CDN, release and CI lists by selected source", "[repository][merge]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    GitHubClient client;
    mgr.setGitHubClient(&client);

    const QJsonArray cdn{QJsonObject{{"name", "CDN v1.0.0"}}};
    REQUIRE(QMetaObject::invokeMethod(&mgr, "onCdnListReady", Qt::DirectConnection, Q_ARG(QJsonArray, cdn)));
    emit client.wicFilesReady(QJsonArray{releaseGroup("v2.0.0", "SimPad Plus 2.0.0", {asset("simpad-plus.wic")})});
    emit client.artifactWicFilesBatchReady(QJsonArray{artifactFile(5, "simpad-plus-wic", "main", "2025-02-01T00:00:00Z")});
    mgr.setGitHubClient(nullptr);

    REQUIRE(mgr.selectedSourceType() == "cdn");
    REQUIRE(mgr.getMergedOsList().size() == 1);
    REQUIRE(mgr.getMergedOsList()[0].toObject()["name"].toString() == "CDN v1.0.0");
    REQUIRE(mgr.getCdnOsList().size() == 1);

    mgr.setSelectedSourceType("github-releases");
    REQUIRE(mgr.getMergedOsList().size() == 1);
    REQUIRE(mgr.getMergedOsList()[0].toObject()["source_type"].toString() == "release");

    mgr.setSelectedSourceType("github-ci");
    REQUIRE(mgr.getMergedOsList().size() == 1);
    REQUIRE(mgr.getMergedOsList()[0].toObject()["source_type"].toString() == "artifact");

    // An unknown source type falls back to the CDN list.
    mgr.setSelectedSourceType("something-else");
    REQUIRE(mgr.getMergedOsList()[0].toObject()["name"].toString() == "CDN v1.0.0");
}

TEST_CASE("RepositoryManager aggregates branch and tag names without duplicates", "[repository][branches]")
{
    IsolatedSettings iso;
    RepositoryManager mgr;
    GitHubClient client;
    mgr.setGitHubClient(&client);
    Spy changed(&mgr, &RepositoryManager::availableBranchesChanged);

    emit client.branchesReady(QJsonArray{"main", "develop", "", "main"});
    REQUIRE(mgr.availableBranches() == QStringList{"develop", "main"});
    REQUIRE(changed.count == 1);

    emit client.tagsReady(QJsonArray{"v1.0.0", "develop"});
    REQUIRE(mgr.availableBranches() == QStringList{"develop", "main", "v1.0.0"});
}

TEST_CASE("LaerdalCdnSource converts an updates manifest to OS list entries", "[cdn]")
{
    IsolatedSettings iso;
    QTemporaryDir files;
    const QString path = writeFile(files, "images.json", R"({"updates":[
      {"simpadtype":"plus","version":"9.2.0.127","url":"https://cdn.example/a.wic.xz","md5":"m1",
       "info":"","releasenotes":"notes","image_download_size":100,"extract_size":400},
      {"simpadtype":"plus2","version":"9.3.0","url":"https://cdn.example/b.VSI","md5":"m2","info":"Info text"},
      {"simpadtype":"mystery","version":"1.0.0","url":"https://cdn.example/c.wic","md5":"m3"}
    ]})");

    LaerdalCdnSource source;
    QJsonArray list;
    QString error;
    bool gotList = false;
    QObject::connect(&source, &LaerdalCdnSource::listReady, &source, [&](const QJsonArray &l) { list = l; gotList = true; });
    QObject::connect(&source, &LaerdalCdnSource::error, &source, [&](const QString &m) { error = m; });

    source.fetchList(QUrl::fromLocalFile(path));
    REQUIRE(source.isFetching());
    REQUIRE(waitFor([&] { return gotList; }));
    REQUIRE(error.isEmpty());
    REQUIRE_FALSE(source.isFetching());
    REQUIRE(list.size() == 3);

    const QJsonObject a = list[0].toObject();
    REQUIRE(a["name"].toString() == "SimPad Plus v9.2.0.127");
    REQUIRE(a["description"].toString() == "notes");
    REQUIRE(a["release_notes"].toString() == "notes");
    REQUIRE(a["extract_md5"].toString() == "m1");
    REQUIRE(a["image_download_size"].toDouble() == 100);
    REQUIRE(a["extract_size"].toDouble() == 400);
    REQUIRE(a["init_format"].toString() == "none");
    REQUIRE(a["source"].toString() == "laerdal_cdn");
    REQUIRE(sorted(strings(a["devices"].toArray())) == sorted({"imx6", "linkbox", "cancpu"}));

    // VSI images are device specific, so cross-device tags are omitted.
    const QJsonObject b = list[1].toObject();
    REQUIRE(b["description"].toString() == "Info text");
    REQUIRE_FALSE(b.contains("release_notes"));
    REQUIRE(strings(b["devices"].toArray()) == QStringList{"imx8"});

    const QJsonObject c = list[2].toObject();
    REQUIRE(c["name"].toString() == "Mystery v1.0.0");
    REQUIRE(c["devices"].toArray().isEmpty());
}

TEST_CASE("LaerdalCdnSource reports malformed and missing manifests", "[cdn]")
{
    IsolatedSettings iso;
    QTemporaryDir files;
    QString path;
    SECTION("not JSON") { path = writeFile(files, "images.json", "<html>"); }
    SECTION("JSON array root") { path = writeFile(files, "images.json", "[]"); }
    SECTION("missing file") { path = files.filePath("absent.json"); }

    LaerdalCdnSource source;
    int errors = 0;
    int lists = 0;
    QObject::connect(&source, &LaerdalCdnSource::error, &source, [&](const QString &) { ++errors; });
    QObject::connect(&source, &LaerdalCdnSource::listReady, &source, [&](const QJsonArray &) { ++lists; });
    source.fetchList(QUrl::fromLocalFile(path));
    REQUIRE(waitFor([&] { return errors + lists > 0; }));
    REQUIRE(errors == 1);
    REQUIRE(lists == 0);
    REQUIRE_FALSE(source.isFetching());
}

TEST_CASE("LaerdalCdnSource treats a manifest without updates as an empty list", "[cdn]")
{
    IsolatedSettings iso;
    QTemporaryDir files;
    LaerdalCdnSource source;
    bool done = false;
    qsizetype size = -1;
    QObject::connect(&source, &LaerdalCdnSource::listReady, &source, [&](const QJsonArray &l) { size = l.size(); done = true; });
    source.fetchList(QUrl::fromLocalFile(writeFile(files, "images.json", "{}")));
    REQUIRE(waitFor([&] { return done; }));
    REQUIRE(size == 0);
}

TEST_CASE("GitHubSource tags results with their origin and forwards client events", "[githubsource]")
{
    IsolatedSettings iso;
    GitHubClient client;
    GitHubSource source("Laerdal-Medical", "simpad");
    REQUIRE(source.fullName() == "Laerdal-Medical/simpad");
    REQUIRE(source.defaultBranch() == "main");
    source.setGitHubClient(&client);

    QJsonArray releases, artifacts;
    QString url, file, error;
    QObject::connect(&source, &GitHubSource::wicFilesReady, &source, [&](const QJsonArray &a) { releases = a; });
    QObject::connect(&source, &GitHubSource::artifactWicFilesReady, &source, [&](const QJsonArray &a) { artifacts = a; });
    QObject::connect(&source, &GitHubSource::fileReady, &source, [&](const QString &u, const QString &f) { url = u; file = f; });
    QObject::connect(&source, &GitHubSource::error, &source, [&](const QString &m) { error = m; });

    emit client.wicFilesReady(QJsonArray{QJsonObject{{"tag", "v1"}}});
    REQUIRE(releases.size() == 1);
    const QJsonObject r = releases[0].toObject();
    REQUIRE(r["source_type"].toString() == "release");
    REQUIRE(r["source_owner"].toString() == "Laerdal-Medical");
    REQUIRE(r["source_repo_name"].toString() == "simpad");
    REQUIRE(r["source_repo"].toString() == "Laerdal-Medical/simpad");
    REQUIRE(source.getWicFiles().size() == 1);

    emit client.artifactWicFilesReady(QJsonArray{QJsonObject{{"artifact_id", 1}}});
    REQUIRE(artifacts[0].toObject()["source_type"].toString() == "artifact");

    emit client.fileUrlReady("https://x/y", "y.wic");
    REQUIRE(url == "https://x/y");
    REQUIRE(file == "y.wic");
    emit client.error("nope");
    REQUIRE(error == "nope");

    // Replacing the client must detach the previous one.
    GitHubClient replacement;
    source.setGitHubClient(&replacement);
    releases = QJsonArray();
    emit client.wicFilesReady(QJsonArray{QJsonObject{{"tag", "stale"}}});
    REQUIRE(releases.isEmpty());
    emit replacement.wicFilesReady(QJsonArray{QJsonObject{{"tag", "fresh"}}});
    REQUIRE(releases.size() == 1);
}

TEST_CASE("GitHubSource reports a missing client and skips disabled repositories", "[githubsource]")
{
    IsolatedSettings iso;
    GitHubSource source("o", "r");
    QStringList errors;
    QObject::connect(&source, &GitHubSource::error, &source, [&](const QString &m) { errors << m; });

    source.searchReleasesForWicFiles();
    source.searchArtifactsForWicFiles("main");
    source.getFileFromBranch("main", "a.wic");
    source.getFileFromTag("v1", "a.wic");
    REQUIRE(errors.size() == 4);

    GitHubClient client;
    source.setGitHubClient(&client);
    source.setEnabled(false);
    errors.clear();
    source.searchReleasesForWicFiles();
    source.searchArtifactsForWicFiles();
    REQUIRE(errors.isEmpty());
}
