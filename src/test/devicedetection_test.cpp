/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include <catch2/catch_test_macros.hpp>

#include <QStringList>

#include "../devicedetection.h"

using namespace DeviceDetection;

namespace {
QStringList tags(DeviceType t, bool vsi = false)
{
    QStringList out;
    for (const auto &v : getDeviceTags(t, vsi)) out << v.toString();
    out.sort();
    return out;
}
} // namespace

TEST_CASE("detectFromFilename resolves the most specific device first", "[devicedetection]")
{
    struct Row { const char *name; DeviceType type; };
    const Row rows[] = {
        {"simman3g-64-image.wic", DeviceType::SimMan3G64},
        {"SimMan-64.wic.xz", DeviceType::SimMan3G64},
        {"simman3g-32.wic", DeviceType::SimMan3G32},
        {"simman3g.wic", DeviceType::SimMan3G},
        {"simman-release.spu", DeviceType::SimMan3G},
        {"linkbox2-9.3.0.wic", DeviceType::LinkBox2},
        {"linkbox-9.3.0.wic", DeviceType::LinkBox},
        {"cancpu2.wic", DeviceType::CANCPU2},
        {"CANCPU.wic", DeviceType::CANCPU},
        {"simpad-plus2-9.3.0.wic", DeviceType::SimPadPlus2},
        {"simpad_plus2.wic", DeviceType::SimPadPlus2},
        {"SimPad Plus 2.wic", DeviceType::SimPadPlus2},
        {"simpadplus2.wic", DeviceType::SimPadPlus2},
        {"simpad2.wic", DeviceType::SimPadPlus2},
        {"image-imx8.wic", DeviceType::SimPadPlus2},
        {"simpad-plus-9.3.0.wic", DeviceType::SimPadPlus},
        {"simpad_plus.wic", DeviceType::SimPadPlus},
        {"SimPad Plus.wic", DeviceType::SimPadPlus},
        {"simpad.spu", DeviceType::SimPadPlus},
        {"image-imx6.wic", DeviceType::SimPadPlus},
        {"rootfs.wic", DeviceType::Unknown},
        {"", DeviceType::Unknown},
    };
    for (const Row &r : rows) {
        INFO(r.name);
        REQUIRE(detectFromFilename(QString::fromLatin1(r.name)) == r.type);
    }
    // Peripheral names win over an embedded SoC/product name.
    REQUIRE(detectFromFilename("linkbox2-imx8.wic") == DeviceType::LinkBox2);
    REQUIRE(detectFromFilename("simpad-cancpu.wic") == DeviceType::CANCPU);
    REQUIRE(detectFromFilename("simman-simpad.wic") == DeviceType::SimMan3G);
}

TEST_CASE("detectFromCdnType uses canonical CDN identifiers", "[devicedetection]")
{
    REQUIRE(detectFromCdnType("plus") == DeviceType::SimPadPlus);
    REQUIRE(detectFromCdnType("PLUS") == DeviceType::SimPadPlus);
    REQUIRE(detectFromCdnType("imx6") == DeviceType::SimPadPlus);
    REQUIRE(detectFromCdnType("plus2") == DeviceType::SimPadPlus2);
    REQUIRE(detectFromCdnType("imx8") == DeviceType::SimPadPlus2);
    REQUIRE(detectFromCdnType("simman3g-32") == DeviceType::SimMan3G32);
    REQUIRE(detectFromCdnType("simman3g-64") == DeviceType::SimMan3G64);
    REQUIRE(detectFromCdnType("simman3g") == DeviceType::SimMan3G);
    REQUIRE(detectFromCdnType("linkbox2") == DeviceType::LinkBox2);
    REQUIRE(detectFromCdnType("linkbox") == DeviceType::LinkBox);
    REQUIRE(detectFromCdnType("cancpu2") == DeviceType::CANCPU2);
    REQUIRE(detectFromCdnType("cancpu") == DeviceType::CANCPU);
    // Equality-based for SimPad: free text must not be guessed.
    REQUIRE(detectFromCdnType("simpad plus") == DeviceType::Unknown);
    REQUIRE(detectFromCdnType("") == DeviceType::Unknown);
}

TEST_CASE("getDeviceTags adds cross-device tags only for non-VSI SimPad images", "[devicedetection]")
{
    REQUIRE(tags(DeviceType::SimPadPlus) == QStringList{"cancpu", "imx6", "linkbox"});
    REQUIRE(tags(DeviceType::SimPadPlus, true) == QStringList{"imx6"});
    REQUIRE(tags(DeviceType::SimPadPlus2) == QStringList{"cancpu2", "imx8", "linkbox2"});
    REQUIRE(tags(DeviceType::SimPadPlus2, true) == QStringList{"imx8"});
    REQUIRE(tags(DeviceType::SimMan3G32) == QStringList{"simman3g-32"});
    REQUIRE(tags(DeviceType::SimMan3G64) == QStringList{"simman3g-64"});
    REQUIRE(tags(DeviceType::SimMan3G) == QStringList{"simman3g"});
    REQUIRE(tags(DeviceType::LinkBox) == QStringList{"linkbox"});
    REQUIRE(tags(DeviceType::LinkBox2, true) == QStringList{"linkbox2"});
    REQUIRE(tags(DeviceType::CANCPU) == QStringList{"cancpu"});
    REQUIRE(tags(DeviceType::CANCPU2) == QStringList{"cancpu2"});
    REQUIRE(tags(DeviceType::Unknown).isEmpty());
}

TEST_CASE("isFileCompatibleWithDevice gates builds by device tag", "[devicedetection][compat]")
{
    // Generic files are shown for every device.
    for (const char *tag : {"imx6", "imx8", "linkbox", "simman3g-64", "", "unknown"})
        REQUIRE(isFileCompatibleWithDevice("rootfs.wic", tag));

    // SimPad Plus images also run on the i.MX6 peripherals, but not on i.MX8 ones.
    REQUIRE(isFileCompatibleWithDevice("simpad-plus-9.3.0.wic", "imx6"));
    REQUIRE(isFileCompatibleWithDevice("simpad-plus-9.3.0.wic", "linkbox"));
    REQUIRE(isFileCompatibleWithDevice("simpad-plus-9.3.0.wic", "cancpu"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus-9.3.0.wic", "imx8"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus-9.3.0.wic", "linkbox2"));

    REQUIRE(isFileCompatibleWithDevice("simpad-plus2-9.3.0.wic", "imx8"));
    REQUIRE(isFileCompatibleWithDevice("simpad-plus2-9.3.0.wic", "linkbox2"));
    REQUIRE(isFileCompatibleWithDevice("simpad-plus2-9.3.0.wic", "cancpu2"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus2-9.3.0.wic", "imx6"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus2-9.3.0.wic", "cancpu"));

    // Device-specific files only match their own tag.
    REQUIRE(isFileCompatibleWithDevice("linkbox-1.0.wic", "linkbox"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("linkbox-1.0.wic", "imx6"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("linkbox-1.0.wic", "linkbox2"));
    REQUIRE(isFileCompatibleWithDevice("simman3g-64.wic", "simman3g-64"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simman3g-64.wic", "simman3g-32"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus.wic", ""));

    // Matching is case-insensitive on the file name but exact on the tag.
    REQUIRE(isFileCompatibleWithDevice("SIMPAD-PLUS.WIC", "imx6"));
    REQUIRE_FALSE(isFileCompatibleWithDevice("simpad-plus.wic", "IMX6"));
}
