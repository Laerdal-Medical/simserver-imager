/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include <catch2/catch_test_macros.hpp>

#include "disk_formatter.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;
using namespace rpi_imager;

namespace {

constexpr std::uint64_t kImageSize = 64ULL * 1024 * 1024;
constexpr std::uint32_t kSectorSize = 512;
constexpr std::uint32_t kPartitionStart = 8192;

class TemporaryImage {
 public:
  TemporaryImage() {
    const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto base = fs::temp_directory_path() /
                      ("simserver-imager-disk-formatter-" + std::to_string(nonce));
    for (unsigned attempt = 0; attempt < 100; ++attempt) {
      directory_ = base.string() + "-" + std::to_string(attempt);
      if (fs::create_directory(directory_)) {
        path_ = directory_ / "image.img";
        return;
      }
    }
    throw std::runtime_error("Unable to create a unique temporary image directory");
  }

  ~TemporaryImage() {
    std::error_code error;
    fs::remove(path_, error);
    fs::remove(directory_, error);
  }

  const fs::path& path() const { return path_; }

 private:
  fs::path directory_;
  fs::path path_;
};

std::array<std::uint8_t, kSectorSize> readSector(const fs::path& path,
                                                 std::uint64_t sector) {
  std::ifstream image(path, std::ios::binary);
  if (!image) {
    throw std::runtime_error("Unable to open formatted image");
  }

  std::array<std::uint8_t, kSectorSize> data{};
  image.seekg(static_cast<std::streamoff>(sector * kSectorSize));
  image.read(reinterpret_cast<char*>(data.data()), data.size());
  if (!image || image.gcount() != static_cast<std::streamsize>(data.size())) {
    throw std::runtime_error("Unable to read complete image sector");
  }
  return data;
}

std::uint32_t readLittleEndian(const std::uint8_t* data, std::size_t offset,
                               std::size_t length) {
  std::uint32_t result = 0;
  for (std::size_t i = 0; i < length; ++i) {
    result |= static_cast<std::uint32_t>(data[offset + i]) << (i * 8);
  }
  return result;
}

}  // namespace

TEST_CASE("DiskFormatter creates an image of the requested size", "[disk-formatter]") {
  TemporaryImage image;
  DiskFormatter formatter;

  const auto result = formatter.FormatFile(image.path().string(), kImageSize);

  REQUIRE(result.has_value());
  REQUIRE(fs::exists(image.path()));
  CHECK(fs::file_size(image.path()) == kImageSize);
}

TEST_CASE("DiskFormatter writes a valid MBR and FAT32 volume", "[disk-formatter]") {
  TemporaryImage image;
  DiskFormatter formatter;

  const auto result = formatter.FormatFile(image.path().string(), kImageSize);
  REQUIRE(result.has_value());

  const auto mbr = readSector(image.path(), 0);
  CHECK(mbr[510] == 0x55);
  CHECK(mbr[511] == 0xAA);
  CHECK(mbr[446] == 0x80);
  CHECK(mbr[450] == 0x0C);
  CHECK(readLittleEndian(mbr.data(), 454, 4) == kPartitionStart);
  CHECK(readLittleEndian(mbr.data(), 458, 4) ==
        kImageSize / kSectorSize - kPartitionStart);

  const auto boot = readSector(image.path(), kPartitionStart);
  CHECK(boot[510] == 0x55);
  CHECK(boot[511] == 0xAA);
  CHECK(readLittleEndian(boot.data(), 11, 2) == kSectorSize);
  CHECK(boot[13] == 2);
  CHECK(readLittleEndian(boot.data(), 14, 2) == 32);
  CHECK(boot[16] == 2);
  CHECK(readLittleEndian(boot.data(), 28, 4) == kPartitionStart);
  CHECK(readLittleEndian(boot.data(), 32, 4) ==
        kImageSize / kSectorSize - kPartitionStart);
  CHECK(readLittleEndian(boot.data(), 36, 4) > 0);
  CHECK(readLittleEndian(boot.data(), 44, 4) == 2);
  CHECK(readLittleEndian(boot.data(), 48, 2) == 1);
  CHECK(readLittleEndian(boot.data(), 50, 2) == 6);
  CHECK(std::string(reinterpret_cast<const char*>(boot.data() + 71), 11) ==
        "BOOT       ");
  CHECK(std::string(reinterpret_cast<const char*>(boot.data() + 82), 8) ==
        "FAT32   ");

  const auto fs_info = readSector(image.path(), kPartitionStart + 1);
  CHECK(readLittleEndian(fs_info.data(), 0, 4) == 0x41615252);
  CHECK(readLittleEndian(fs_info.data(), 484, 4) == 0x61417272);
  CHECK(readLittleEndian(fs_info.data(), 508, 4) == 0xAA550000);
  CHECK(readSector(image.path(), kPartitionStart + 6) == boot);

  const auto sectors_per_fat = readLittleEndian(boot.data(), 36, 4);
  const auto first_fat_sector = kPartitionStart + 32;
  const auto fat = readSector(image.path(), first_fat_sector);
  CHECK(readLittleEndian(fat.data(), 0, 4) == 0x0FFFFFF8);
  CHECK(readLittleEndian(fat.data(), 4, 4) == 0x0FFFFFFF);
  CHECK(readLittleEndian(fat.data(), 8, 4) == 0x0FFFFFFF);
  CHECK(readSector(image.path(), first_fat_sector + sectors_per_fat) == fat);
}

TEST_CASE("DiskFormatter reports failure when the output cannot be created",
          "[disk-formatter][errors]") {
  TemporaryImage image;
  const auto missing_directory = image.path().string() + ".missing";
  DiskFormatter formatter;

  const auto result =
      formatter.FormatFile(missing_directory + "/image.img", kImageSize);

  REQUIRE_FALSE(result);
  CHECK(result.error() == FormatError::kFileOpenError);
  CHECK_FALSE(fs::exists(missing_directory));
}

TEST_CASE("DiskFormatter rejects undersized images before creating them",
          "[disk-formatter][errors]") {
  TemporaryImage image;
  DiskFormatter formatter;
  constexpr std::uint64_t tooSmall =
      (static_cast<std::uint64_t>(kPartitionStart) + 127) * kSectorSize;

  const auto result = formatter.FormatFile(image.path().string(), tooSmall);

  REQUIRE_FALSE(result);
  CHECK(result.error() == FormatError::kInsufficientSpace);
  CHECK_FALSE(fs::exists(image.path()));
}
