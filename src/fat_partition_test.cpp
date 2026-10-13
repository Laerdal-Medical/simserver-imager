/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include <catch2/catch_test_macros.hpp>

#include "devicewrapper.h"
#include "devicewrapperfatpartition.h"
#include "file_operations.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>

#ifdef __APPLE__
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>
#endif

namespace fs = std::filesystem;

// Forward declarations
static std::string getTestPartitionDevice();
static std::string getWholeDiskPath(const std::string& partition_path);
static int getPartitionNumber(const std::string& partition_path);

// Global shared device wrapper (opened once, reused by all tests)
static std::shared_ptr<rpi_imager::FileOperations> g_shared_file_ops;
static std::shared_ptr<DeviceWrapper> g_shared_device_wrapper;
static int g_partition_num = 1;
static std::string g_test_device_path;

// Initialize the shared device wrapper only after a hardware test is selected.
static void initializeSharedDevice() {
    if (g_shared_device_wrapper) {
        return; // Already initialized
    }
    
    std::string partition_path = getTestPartitionDevice();
    if (partition_path.empty()) {
        throw std::runtime_error(
            "Set FAT_TEST_PARTITION_DEVICE to the partition device path.");
    }
    
    g_test_device_path = partition_path;
    
    // Convert partition to whole disk
    std::string disk_path = getWholeDiskPath(partition_path);
    g_partition_num = getPartitionNumber(partition_path);
    
    std::cout << "=========================================" << std::endl;
    std::cout << "Opening test device ONCE for all tests" << std::endl;
    std::cout << "Partition: " << partition_path << std::endl;
    std::cout << "Whole disk: " << disk_path << std::endl;
    std::cout << "Partition #: " << g_partition_num << std::endl;
    std::cout << "=========================================" << std::endl;
    
    auto file_ops = rpi_imager::FileOperations::Create();
    auto result = file_ops->OpenDevice(disk_path);
    
    if (result != rpi_imager::FileError::kSuccess) {
        std::cout << "ERROR: Failed to open device: " << disk_path << std::endl;
        return;
    }
    
    auto device_wrapper = std::make_unique<DeviceWrapper>(file_ops.get());
    
    // Convert to shared_ptr for global sharing
    g_shared_file_ops = std::shared_ptr<rpi_imager::FileOperations>(std::move(file_ops));
    g_shared_device_wrapper = std::shared_ptr<DeviceWrapper>(std::move(device_wrapper));
    
    std::cout << "✅ Device opened successfully and will be reused by all tests" << std::endl;
    std::cout << "=========================================" << std::endl;
}

// There is deliberately no default device: these tests can write to a partition.
static std::string getTestPartitionDevice() {
    const char* env_path = std::getenv("FAT_TEST_PARTITION_DEVICE");
    if (env_path && fs::exists(env_path)) {
        return env_path;
    }
    return "";
}

// Helper to convert partition device to whole disk device
// e.g., /dev/disk4s1 -> /dev/disk4
static std::string getWholeDiskPath(const std::string& partition_path) {
    const bool mac_disk_path = partition_path.rfind("/dev/disk", 0) == 0 ||
                               partition_path.rfind("/dev/rdisk", 0) == 0;
    const bool linux_p_partition = partition_path.rfind("/dev/nvme", 0) == 0 ||
                                   partition_path.rfind("/dev/mmcblk", 0) == 0;
    const char marker = mac_disk_path ? 's' : (linux_p_partition ? 'p' : '\0');
    const auto marker_pos = marker == '\0' ? std::string::npos
                                            : partition_path.rfind(marker);
    if (marker_pos != std::string::npos && marker_pos + 1 < partition_path.size()) {
        const auto suffix = partition_path.substr(marker_pos + 1);
        if (std::all_of(suffix.begin(), suffix.end(),
                        [](unsigned char ch) { return std::isdigit(ch); })) {
            return partition_path.substr(0, marker_pos);
        }
    }

    if (partition_path.rfind("/dev/sd", 0) == 0 ||
        partition_path.rfind("/dev/vd", 0) == 0 ||
        partition_path.rfind("/dev/xvd", 0) == 0) {
        const auto first_digit = partition_path.find_last_not_of("0123456789");
        if (first_digit != std::string::npos &&
            first_digit + 1 < partition_path.size()) {
            return partition_path.substr(0, first_digit + 1);
        }
    }
    return partition_path;
}

// Helper to extract partition number from device path
// Supports macOS diskXsN, Linux nvme/mmcblk ...pN, and Linux sd/vd/xvdN.
static int getPartitionNumber(const std::string& partition_path) {
    const bool mac_disk_path = partition_path.rfind("/dev/disk", 0) == 0 ||
                               partition_path.rfind("/dev/rdisk", 0) == 0;
    const bool linux_p_partition = partition_path.rfind("/dev/nvme", 0) == 0 ||
                                   partition_path.rfind("/dev/mmcblk", 0) == 0;
    const char marker = mac_disk_path ? 's' : (linux_p_partition ? 'p' : '\0');
    const auto marker_pos = marker == '\0' ? std::string::npos
                                            : partition_path.rfind(marker);
    if (marker_pos != std::string::npos && marker_pos + 1 < partition_path.size()) {
        const auto suffix = partition_path.substr(marker_pos + 1);
        if (std::all_of(suffix.begin(), suffix.end(),
                        [](unsigned char ch) { return std::isdigit(ch); })) {
            return std::stoi(suffix);
        }
    }

    if (partition_path.rfind("/dev/sd", 0) == 0 ||
        partition_path.rfind("/dev/vd", 0) == 0 ||
        partition_path.rfind("/dev/xvd", 0) == 0) {
        const auto first_digit = partition_path.find_last_not_of("0123456789");
        if (first_digit != std::string::npos &&
            first_digit + 1 < partition_path.size()) {
            return std::stoi(partition_path.substr(first_digit + 1));
        }
    }
    return 1;
}

// Helper to get the shared FAT partition (all tests use the same device)
static DeviceWrapperFatPartition* getSharedFatPartition() {
    const char* allow_writes = std::getenv("FAT_TEST_ALLOW_WRITES");
    if (!allow_writes || std::string(allow_writes) != "1") {
        throw std::runtime_error(
            "These tests modify a real partition. Set FAT_TEST_ALLOW_WRITES=1 "
            "only for disposable media.");
    }
    initializeSharedDevice();
    if (!g_shared_device_wrapper) {
        throw std::runtime_error(
            "Could not open the explicitly selected test partition.");
    }
    
    DeviceWrapperFatPartition* fat = g_shared_device_wrapper->fatPartition(g_partition_num);
    if (!fat) {
        throw std::runtime_error("Failed to get FAT partition");
    }
    
    return fat;
}

TEST_CASE("DeviceWrapperFatPartition list files", "[.fat-hardware]") {
    INFO("Testing against: " << g_test_device_path);
    
    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);
    
    // List all files recursively
    QStringList allFiles = fat->listAllFilesRecursive();
    
    std::cout << "Found " << allFiles.size() << " total files (recursive)" << std::endl;
    INFO("Found " << allFiles.size() << " total files");
    REQUIRE(!allFiles.isEmpty());
    
    // Count files by directory and show samples
    int rootFiles = 0;
    int subdirFiles = 0;
    QStringList sampleSubdirFiles;
    QStringList allSubdirs;
    
    for (const QString& file : allFiles) {
        if (file.contains("/")) {
            subdirFiles++;
            if (sampleSubdirFiles.size() < 10) {
                sampleSubdirFiles.append(file);
            }
            // Extract directory name
            QString dirName = file.left(file.indexOf('/'));
            if (!allSubdirs.contains(dirName)) {
                allSubdirs.append(dirName);
            }
        } else {
            rootFiles++;
        }
    }
    
    std::cout << "  Root files: " << rootFiles << std::endl;
    std::cout << "  Subdirectory files: " << subdirFiles << std::endl;
    std::cout << "  Subdirectories found: ";
    for (const QString& dir : allSubdirs) {
        std::cout << "'" << dir.toStdString() << "' ";
        // Show hex dump of first few characters
        std::cout << "(hex:";
        for (int i = 0; i < qMin(dir.length(), 8); i++) {
            std::cout << " " << std::hex << (int)dir[i].unicode() << std::dec;
        }
        std::cout << ") ";
    }
    std::cout << std::endl;
    if (!sampleSubdirFiles.isEmpty()) {
        std::cout << "  Sample subdirectory files:" << std::endl;
        for (const QString& sample : sampleSubdirFiles) {
            std::cout << "    - " << sample.toStdString() << std::endl;
        }
    } else {
        std::cout << "  WARNING: No subdirectory files found!" << std::endl;
    }
    INFO("Root files: " << rootFiles);
    INFO("Subdirectory files: " << subdirFiles);
    
    CHECK(rootFiles > 0);
    
    // List root files only
    QStringList rootFilesList = fat->listAllFiles();
    
    std::cout << "Found " << rootFilesList.size() << " root-only files" << std::endl;
    INFO("Found " << rootFilesList.size() << " root files");
    REQUIRE(!rootFilesList.isEmpty());
    
    // All returned files should be root files (no '/')
    for (const QString& file : rootFilesList) {
        CHECK(!file.contains("/"));
    }
}
TEST_CASE("DeviceWrapperFatPartition file reading", "[.fat-hardware]") {
    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);
    
    SECTION("Read root files") {
        QStringList files = fat->listAllFiles();
        REQUIRE(!files.isEmpty());
        
        // Test reading first few files
        int tested = 0;
        for (const QString& filename : files) {
            if (tested >= 3) break;
            
            INFO("Reading file: " << filename.toStdString());
            QByteArray content = fat->readFile(filename);
            
            INFO("File size: " << content.size() << " bytes");
            
            tested++;
        }
        
        REQUIRE(tested > 0);
    }
    
    SECTION("Read subdirectory files") {
        QStringList allFiles = fat->listAllFilesRecursive();
        
        // Find files in subdirectories
        QStringList subdirFiles;
        for (const QString& file : allFiles) {
            if (file.contains("/")) {
                subdirFiles.append(file);
                if (subdirFiles.size() >= 5) break;
            }
        }
        
        if (subdirFiles.isEmpty()) {
            SKIP("No subdirectory files found to test");
        }
        
        for (const QString& filename : subdirFiles) {
            INFO("Reading subdirectory file: " << filename.toStdString());
            
            REQUIRE_NOTHROW(fat->readFile(filename));
        }
    }
}
TEST_CASE("DeviceWrapperFatPartition fileExists", "[.fat-hardware]") {
    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);
    
    SECTION("Check existing files") {
        QStringList allFiles = fat->listAllFilesRecursive();
        REQUIRE(!allFiles.isEmpty());
        
        // Test a few existing files
        int tested = 0;
        for (const QString& filename : allFiles) {
            if (tested >= 5) break;
            
            INFO("Checking existence of: " << filename.toStdString());
            CHECK(fat->fileExists(filename));
            
            tested++;
        }
    }
    
    SECTION("Check non-existent files") {
        CHECK_FALSE(fat->fileExists("this_file_does_not_exist.txt"));
        CHECK_FALSE(fat->fileExists("overlays/nonexistent.dtbo"));
    }
}

TEST_CASE("DeviceWrapperFatPartition deleteFile", "[.fat-hardware][.destructive]") {
    WARN("This test will modify the filesystem!");
    
    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);
    
    SECTION("Delete root file") {
        // Create a test file
        QString testFile = "test_delete.txt";
        if (fat->fileExists(testFile)) {
            SKIP("The test filename already exists on the selected partition");
        }
        QByteArray testContent = "This is a test file for deletion";
        
        fat->writeFile(testFile, testContent);
        REQUIRE(fat->fileExists(testFile));
        
        // Delete it
        INFO("Deleting test file: " << testFile.toStdString());
        REQUIRE(fat->deleteFile(testFile));
        
        // Verify it's gone by trying to read it
        REQUIRE_THROWS(fat->readFile(testFile));
    }
    
}

TEST_CASE("DeviceWrapperFatPartition LFN filename round trips",
          "[.fat-hardware][.destructive]") {
    WARN("This test creates and deletes files on the selected partition.");
    
    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);
    
    SECTION("Create file with long name and verify LFN checksum") {
        // Create a file with a name longer than 8.3 (requires LFN entries).
        QString longName = "this_file_has_a_very_long_name_that_requires_lfn_entries.txt";
        if (fat->fileExists(longName)) {
            SKIP("The test filename already exists on the selected partition");
        }
        QByteArray content = "LFN checksum test content";
        
        std::cout << "Creating file with long name: " << longName.toStdString() << std::endl;
        
        fat->writeFile(longName, content);
        REQUIRE(fat->fileExists(longName));
        
        // Read it back - should work with the long name
        QByteArray readBack = fat->readFile(longName);
        REQUIRE(readBack == content);
        
        // Verify it appears in the file list with its long name
        QStringList allFiles = fat->listAllFiles();
        REQUIRE(allFiles.contains(longName));
        
        // Clean up
        REQUIRE(fat->deleteFile(longName));
        REQUIRE_FALSE(fat->fileExists(longName));
        
        std::cout << "  LFN creation, reading, and deletion successful" << std::endl;
    }
    
    SECTION("Multiple files with long names") {
        std::cout << "Testing multiple long filename files..." << std::endl;
        
        QStringList longNames = {
            "long_filename_test_number_one.dat",
            "another_very_long_filename_test.bin",
            "yet_another_extremely_long_filename_for_testing.tmp"
        };
        for (const QString& name : longNames) {
            if (fat->fileExists(name)) {
                SKIP("A test filename already exists on the selected partition");
            }
        }
        
        // Create all files
        for (const QString& name : longNames) {
            QByteArray content = QString("Content for %1").arg(name).toUtf8();
            fat->writeFile(name, content);
            REQUIRE(fat->fileExists(name));
        }
        
        // Verify all can be read back
        for (const QString& name : longNames) {
            QByteArray expected = QString("Content for %1").arg(name).toUtf8();
            QByteArray actual = fat->readFile(name);
            REQUIRE(actual == expected);
        }
        
        // List and verify all appear
        QStringList allFiles = fat->listAllFiles();
        for (const QString& name : longNames) {
            REQUIRE(allFiles.contains(name));
        }
        
        // Clean up
        for (const QString& name : longNames) {
            REQUIRE(fat->deleteFile(name));
        }
        
        std::cout << "  Created and verified " << longNames.size() << " long filename files" << std::endl;
    }
    
    SECTION("Mix of 8.3 and long filenames") {
        std::cout << "Testing mix of 8.3 and LFN files..." << std::endl;
        
        struct TestFile {
            QString name;
            bool isLongName;
        };
        
        QList<TestFile> testFiles = {
            {"SHORT.TXT", false},  // 8.3 name
            {"this_is_a_long_filename.txt", true},  // LFN
            {"TEST2.DAT", false},  // 8.3 name
            {"another_long_name_file.bin", true}  // LFN
        };
        for (const auto& tf : testFiles) {
            if (fat->fileExists(tf.name)) {
                SKIP("A test filename already exists on the selected partition");
            }
        }
        
        // Create all files
        for (const auto& tf : testFiles) {
            QByteArray content = QString("Content for %1").arg(tf.name).toUtf8();
            fat->writeFile(tf.name, content);
            REQUIRE(fat->fileExists(tf.name));
            std::cout << "  Created: " << tf.name.toStdString() 
                      << " (type: " << (tf.isLongName ? "LFN" : "8.3") << ")" << std::endl;
        }
        
        // Verify all are accessible
        QStringList allFiles = fat->listAllFiles();
        for (const auto& tf : testFiles) {
            // Check existence (case-insensitive for FAT)
            bool found = false;
            for (const QString& listedFile : allFiles) {
                if (listedFile.toLower() == tf.name.toLower()) {
                    found = true;
                    break;
                }
            }
            REQUIRE(found);
            
            // Verify content
            QByteArray expected = QString("Content for %1").arg(tf.name).toUtf8();
            QByteArray actual = fat->readFile(tf.name);
            REQUIRE(actual == expected);
        }
        
        // Clean up
        for (const auto& tf : testFiles) {
            REQUIRE(fat->deleteFile(tf.name));
        }
        
        std::cout << "  Successfully tested " << testFiles.size() << " mixed name files" << std::endl;
    }
}

TEST_CASE("DeviceWrapperFatPartition writes files across clusters",
          "[.fat-hardware][.destructive]") {
    WARN("This test creates and deletes files on the selected partition.");

    DeviceWrapperFatPartition* fat = getSharedFatPartition();
    REQUIRE(fat != nullptr);

    SECTION("Round-trip a multi-cluster file") {
        const QString filename = "fat_partition_cluster_test.bin";
        if (fat->fileExists(filename)) {
            SKIP("The test filename already exists on the selected partition");
        }

        const QByteArray contents(64 * 1024, 'F');
        fat->writeFile(filename, contents);
        REQUIRE(fat->readFile(filename) == contents);
        REQUIRE(fat->deleteFile(filename));
        CHECK_FALSE(fat->fileExists(filename));
    }

    SECTION("Create and remove a file in an existing subdirectory") {
        const QString filename = "overlays/fat_partition_test.dtbo";
        if (fat->fileExists(filename)) {
            SKIP("The test filename already exists on the selected partition");
        }

        const QStringList files = fat->listAllFilesRecursive();
        const bool hasOverlays = std::any_of(
            files.cbegin(), files.cend(),
            [](const QString& file) { return file.startsWith("overlays/"); });
        if (!hasOverlays) {
            SKIP("The selected partition has no overlays/ directory");
        }

        const QByteArray contents = "FAT subdirectory test";
        fat->writeFile(filename, contents);
        REQUIRE(fat->readFile(filename) == contents);
        REQUIRE(fat->deleteFile(filename));
        CHECK_FALSE(fat->fileExists(filename));
    }
}
