/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_session.hpp>
#include <catch2/catch_approx.hpp>
#include <QDateTime>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QJSValue>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QThread>
#include <QVariant>
#include <QWheelEvent>
#include <memory>

int main(int argc, char *argv[])
{
    // Catch2 discovery runs outside CTest and must also work without a display.
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication application(argc, argv);
    return Catch::Session().run(argc, argv);
}

namespace {
struct Utils {
    QQmlEngine engine;
    QQmlComponent component{&engine, QUrl::fromLocalFile(QStringLiteral(TEST_QML_SOURCE_DIR "/Utils.qml"))};
    std::unique_ptr<QObject> object;

    Utils()
    {
        INFO(component.errorString().toStdString());
        REQUIRE(component.isReady());
        object.reset(component.create());
        REQUIRE(object);
    }

    template<typename... Args>
    QVariant call(const char *method, const Args &...args)
    {
        QVariant result;
        REQUIRE(QMetaObject::invokeMethod(object.get(), method, Qt::DirectConnection,
                                         Q_RETURN_ARG(QVariant, result), Q_ARG(QVariant, QVariant(args))...));
        if (result.metaType() == QMetaType::fromType<QJSValue>())
            return result.value<QJSValue>().toVariant();
        return result;
    }
};
}

TEST_CASE("QML throughput sampling converts units and applies smoothing only to network rates", "[qml-utils]")
{
    Utils utils;
    const qint64 previousTime = QDateTime::currentMSecsSinceEpoch() - 2000;
    const auto network = utils.call("calculateThroughputMbps", 500000, 0, previousTime, 1.0, 500, 0.25).toMap();
    const double elapsed = (network.value("newLastTime").toLongLong() - previousTime) / 1000.0;
    const double instantMbps = 500000.0 * 8 / 1000000 / elapsed;
    REQUIRE(network.value("throughputMbps").toDouble() == Catch::Approx(0.25 * instantMbps + 0.75));
    REQUIRE(network.value("newLastBytes").toLongLong() == 500000);
    const auto disk = utils.call("calculateThroughputKBps", 500000, 0, previousTime, 500).toMap();
    const double milliseconds = disk.value("newLastTime").toLongLong() - previousTime;
    REQUIRE(disk.value("throughputKBps").toInt() == qRound(500000.0 * 1000 / 1024 / milliseconds));
}

TEST_CASE("QML throughput sampling initializes and handles stalled or reset counters", "[qml-utils]")
{
    Utils utils;
    const auto first = utils.call("calculateThroughputMbps", 1234, 0, 0, 0, 500, 0.3).toMap();
    REQUIRE(first.value("throughputMbps").toDouble() == 0);
    REQUIRE(first.value("newLastBytes").toInt() == 1234);
    REQUIRE(first.value("newLastTime").toLongLong() > 0);
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    REQUIRE(utils.call("calculateThroughputMbps", 5678, 1234, now + 10000, 5, 500, 0.3).isNull());
    const auto stalled = utils.call("calculateThroughputMbps", 1234, 1234, now - 2000, 5, 500, 0.3).toMap();
    REQUIRE(stalled.value("throughputMbps").toDouble() == 5);
    const auto reset = utils.call("calculateThroughputKBps", 0, 1234, now - 2000, 500).toMap();
    REQUIRE(reset.value("throughputKBps").toDouble() == 0);
    REQUIRE(reset.value("newLastBytes").toInt() == 0);
}

TEST_CASE("QML transfer estimates distinguish binary disk units from decimal network units", "[qml-utils]")
{
    Utils utils;
    REQUIRE(utils.call("calculateTimeRemainingKBps", 0, 1048576, 1024).toInt() == 1);
    REQUIRE(utils.call("calculateTimeRemainingMbps", 0, 1000000, 8).toInt() == 1);
    REQUIRE(utils.call("calculateTimeRemainingKBps", 0, 1025, 1).toInt() == 2);
    REQUIRE(utils.call("calculateTimeRemainingMbps", 0, 125001, 1).toInt() == 2);
    for (const char *method : {"calculateTimeRemainingKBps", "calculateTimeRemainingMbps"}) {
        REQUIRE(utils.call(method, 0, 1000, 0).toInt() == -1);
        REQUIRE(utils.call(method, 0, 0, 1).toInt() == -1);
        REQUIRE(utils.call(method, 1001, 1000, 1).toInt() == 0);
    }
}

TEST_CASE("QML duration formatting handles rounding across minute and hour boundaries", "[qml-utils]")
{
    Utils utils;
    REQUIRE(utils.call("formatDuration", 59.6).toString() == utils.call("formatDuration", 60).toString());
    REQUIRE(utils.call("formatDuration", 3599.6).toString() == utils.call("formatDuration", 3600).toString());
    REQUIRE(utils.call("formatDuration", -1).toString().isEmpty());
    REQUIRE(utils.call("calculateAverageSpeed", 1048576, 0).toString().isEmpty());
    REQUIRE(utils.call("calculateAverageSpeed", 1048576, 2).toString().contains("0.5"));
}

TEST_CASE("Expanded branch dropdown stays below its selector and fits available window space", "[qml-controls]")
{
    const QString directory = QStringLiteral(TEST_QML_SOURCE_DIR);
    qmlRegisterSingletonType(QUrl::fromLocalFile(directory + "/Style.qml"), "RpiImager", 1, 0, "Style");
    qmlRegisterType(QUrl::fromLocalFile(directory + "/qmlcomponents/ImScrollBar.qml"),
                    "RpiImager", 1, 0, "ImScrollBar");
    qmlRegisterType(QUrl::fromLocalFile(directory + "/qmlcomponents/ImComboBox.qml"),
                    "RpiImager", 1, 0, "ImComboBox");
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(R"(
        import QtQuick
        import QtQuick.Controls
        import RpiImager 1.0
        ApplicationWindow {
            width: 800
            height: 720
            visible: true
            property alias expanded: combo.expandPopupToWindow
            property alias branches: combo.model
            property alias selectorContainerY: container.y
            readonly property real dropdownHeight: combo.popup.height
            readonly property real dropdownTop: container.y + combo.y + combo.popup.y
            readonly property real selectorBottom: container.y + combo.y + combo.height
            readonly property real popupMargin: Style.spacingMedium
            readonly property real scrollPosition: combo.popup.contentItem.contentY
            function openDropdown() { combo.popup.open() }
            function closeDropdown() { combo.popup.close() }
            Item {
                id: container
                y: 40
                ImComboBox {
                id: combo
                y: 120
                width: 400
                imageWriter: null
                expandPopupToWindow: true
                model: 40
                }
            }
        }
    )", QUrl());
    INFO(component.errorString().toStdString());
    REQUIRE(component.isReady());
    std::unique_ptr<QObject> window(component.create());
    REQUIRE(window);
    REQUIRE(QMetaObject::invokeMethod(window.get(), "openDropdown"));
    QCoreApplication::processEvents();
    const double margin = window->property("popupMargin").toDouble();
    const double bottom = window->property("selectorBottom").toDouble();
    REQUIRE(window->property("dropdownHeight").toDouble() == Catch::Approx(720 - bottom - margin));
    REQUIRE(window->property("dropdownTop").toDouble() == Catch::Approx(bottom));

    auto *quickWindow = qobject_cast<QQuickWindow *>(window.get());
    REQUIRE(quickWindow);
    const QPointF wheelPosition(100, bottom + 100);
    auto scroll = [&](QPoint pixels, QPoint angle, bool inverted, double expected) {
        QWheelEvent event(wheelPosition, quickWindow->mapToGlobal(wheelPosition.toPoint()),
                          pixels, angle, Qt::NoButton, Qt::NoModifier,
                          Qt::NoScrollPhase, inverted);
        QCoreApplication::sendEvent(quickWindow, &event);
        QElapsedTimer timer;
        timer.start();
        while (timer.elapsed() < 1000
               && qAbs(window->property("scrollPosition").toDouble() - expected) > 0.1) {
            QCoreApplication::processEvents();
            QThread::msleep(5);
        }
        REQUIRE(window->property("scrollPosition").toDouble() == Catch::Approx(expected).margin(0.1));
    };
    // The inverted flag describes the supplied delta, not another inversion to apply.
    scroll(QPoint(0, -60), {}, false, 60);
    scroll(QPoint(0, -60), {}, true, 120);
    scroll(QPoint(0, 60), {}, true, 60);
    scroll(QPoint(0, 60), {}, false, 0);
    scroll({}, QPoint(0, -120), false, 120);
    scroll({}, QPoint(0, 120), true, 0);

    REQUIRE(window->setProperty("height", 480));
    QCoreApplication::processEvents();
    REQUIRE(window->property("dropdownHeight").toDouble() == Catch::Approx(480 - bottom - margin));
    REQUIRE(window->setProperty("branches", 3));
    REQUIRE(window->property("dropdownHeight").toDouble() == 150);
    REQUIRE(QMetaObject::invokeMethod(window.get(), "closeDropdown"));
    REQUIRE(window->setProperty("selectorContainerY", 220));
    REQUIRE(window->setProperty("branches", 40));
    REQUIRE(QMetaObject::invokeMethod(window.get(), "openDropdown"));
    QCoreApplication::processEvents();
    const double movedBottom = window->property("selectorBottom").toDouble();
    REQUIRE(window->property("dropdownTop").toDouble() == Catch::Approx(movedBottom));
    REQUIRE(window->property("dropdownHeight").toDouble() == Catch::Approx(480 - movedBottom - margin));
    REQUIRE(window->setProperty("expanded", false));
    QCoreApplication::processEvents();
    REQUIRE(window->property("dropdownHeight").toDouble() <= 300);
    REQUIRE(QMetaObject::invokeMethod(window.get(), "closeDropdown"));
    QCoreApplication::processEvents();
}
