/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include "bootimgcreator.h"
#include "platformquirks.h"
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QTextStream>
#include <QDebug>

bool BootImgCreator::createBootImg(const QMap<QString, QByteArray> &files, 
                                   const QString &outputPath, 
                                   qint64 totalSize)
{
    if (files.isEmpty()) {
        qDebug() << "BootImgCreator (Windows): no files to pack";
        return false;
    }

    qDebug() << "BootImgCreator (Windows): creating" << totalSize << "byte boot.img";
    
    // Ensure parent directory exists
    QFileInfo outputInfo(outputPath);
    QDir().mkpath(outputInfo.absolutePath());
    
    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        qDebug() << "BootImgCreator (Windows): failed to create temp directory";
        return false;
    }
    
    // Create empty file
    QFile imgFile(outputPath);
    if (!imgFile.open(QIODevice::WriteOnly)) {
        qDebug() << "BootImgCreator (Windows): failed to create" << outputPath;
        return false;
    }
    imgFile.resize(totalSize);
    imgFile.close();
    
    // Create a diskpart script to format the image
    QString diskpartScript = tempDir.path() + "/format_boot.txt";
    QFile scriptFile(diskpartScript);
    if (!scriptFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qDebug() << "BootImgCreator (Windows): failed to create diskpart script";
        return false;
    }
    
    QTextStream script(&scriptFile);
    QString winPath = QDir::toNativeSeparators(outputPath);
    script << "select vdisk file=\"" << winPath << "\"\r\n";
    script << "attach vdisk\r\n";
    script << "create partition primary\r\n";
    script << "format fs=fat32 quick\r\n";
    script << "assign letter=Z\r\n";
    scriptFile.close();
    
    // Run diskpart
    QProcess diskpartProc;
    diskpartProc.start("diskpart", QStringList() << "/s" << diskpartScript);
    if (!diskpartProc.waitForFinished(60000) || diskpartProc.exitCode() != 0) {
        qDebug() << "BootImgCreator (Windows): diskpart failed:"
                 << diskpartProc.readAllStandardError();
        return false;
    }

    // Wait for the virtual drive to be ready at Z:
    if (!PlatformQuirks::waitForDeviceReady("\\\\.\\Z:", 5000)) {
        qWarning() << "BootImgCreator (Windows): Virtual drive may not be fully ready";
    }

    // Copy files to Z:
    for (auto it = files.constBegin(); it != files.constEnd(); ++it) {
        QString destPath = "Z:\\" + QString(it.key()).replace("/", "\\");
        
        // Create parent directory if needed
        QFileInfo fileInfo(destPath);
        QString parentDir = fileInfo.absolutePath();
        if (!QDir(parentDir).exists()) {
            QDir().mkpath(parentDir);
        }
        
        // Write file
        QFile outFile(destPath);
        if (!outFile.open(QIODevice::WriteOnly)) {
            qDebug() << "BootImgCreator (Windows): failed to create" << destPath;
            continue;
        }
        outFile.write(it.value());
        outFile.close();
    }
    
    // Detach the virtual disk
    QString detachScript = tempDir.path() + "/detach.txt";
    QFile detachFile(detachScript);
    if (detachFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream ds(&detachFile);
        ds << "select vdisk file=\"" << winPath << "\"\r\n";
        ds << "detach vdisk\r\n";
        detachFile.close();
        
        QProcess detachProc;
        detachProc.start("diskpart", QStringList() << "/s" << detachScript);
        detachProc.waitForFinished(10000);
    }
    
    qDebug() << "BootImgCreator (Windows): boot.img created successfully";
    return true;
}

