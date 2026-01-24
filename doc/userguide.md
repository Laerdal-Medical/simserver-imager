# Laerdal SimServer Imager User Guide

This guide explains how to use Laerdal SimServer Imager to write system images to SD cards and USB drives for Laerdal simulation devices.

## Table of Contents

- [Getting Started](#getting-started)
- [Image Types](#image-types)
- [Writing an Image](#writing-an-image)
  - [From Laerdal CDN](#from-laerdal-cdn)
  - [From GitHub CI Builds](#from-github-ci-builds)
  - [From Local File](#from-local-file)
- [Device Selection](#device-selection)
- [Image Customization](#image-customization)
- [Application Options](#application-options)
- [Troubleshooting](#troubleshooting)

## Getting Started

1. **Download** the application for your platform from the [Releases page](https://github.com/Laerdal-Medical/simserver-imager/releases)
2. **Install** or extract the application
3. **Run** Laerdal SimServer Imager
4. **Insert** an SD card or USB drive

## Image Types

The application supports three types of images, indicated by colored badges in the selection list:

| Badge | Type | Description |
|-------|------|-------------|
| ![SPU](https://img.shields.io/badge/SPU-6366f1?style=flat-square) | **Software Package Update** | Firmware update files copied to a mounted device. Does not erase existing data. |
| ![WIC](https://img.shields.io/badge/WIC-10b981?style=flat-square) | **Disk Image** | Complete system image that overwrites the entire storage device. |
| ![VSI](https://img.shields.io/badge/VSI-06b6d4?style=flat-square) | **Versioned Sparse Image** | Efficient delta update format for incremental updates. |

**Warning:** WIC and VSI images will **erase all data** on the target device. SPU updates preserve existing data.

## Writing an Image

### Step 1: Select Device Type

Choose your target hardware device (SimPad PLUS, SimMan 3G, etc.). This filters the available images to show only compatible options.

### Step 2: Select Source

Choose where to get the image from:

- **Laerdal CDN** - Official release images from Laerdal's content delivery network
- **GitHub** - Development builds from GitHub Actions CI pipelines
- **Use custom file** - Select a local image file from your computer

### Step 3: Select Image

Browse and select the image you want to write. Images are sorted by version (newest first) and show:

- **Name** - Image name with version number
- **Badge** - Image type (SPU/WIC/VSI)
- **Description** - Brief description of the image
- **Status** - Whether the image is cached locally or needs to be downloaded
- **Release date** - When the image was published

### Step 3b: Select File (CI Artifacts only)

When selecting a GitHub CI artifact, the application downloads and inspects the ZIP archive to find installable image files. This step shows:

- Download progress with speed and estimated time remaining
- List of installable files found in the artifact (WIC, VSI, SPU)
- File sizes and types indicated by colored badges

Select the file you want to install and click **NEXT** to continue. Direct CDN files (.wic, .spu, .vsi) skip this step automatically.

### Step 4: Select Storage

Choose the target SD card or USB drive. The list shows:

- Device name and path
- Storage capacity
- Current mount status

**Caution:** Double-check you've selected the correct device. Writing to the wrong device will result in data loss.

### Step 5: Write

Click **NEXT** to begin the write process.

For WIC/VSI images:
- The device will be unmounted
- All existing data will be erased
- The image will be downloaded (if not cached), written, and verified
- Progress bar shows real-time speed (MB/s) and estimated time remaining
- After completion, write statistics (bytes written, duration, average speed) are displayed

For SPU updates:
- The device will be mounted (or stay mounted)
- Update files will be copied to the appropriate locations
- Existing data is preserved
- Copy progress shown with bytes transferred

After a successful write, you can click **Write Another** to write the same image to a different device.

## From Laerdal CDN

The default source for official release images.

1. Select **Laerdal CDN** as the source
2. Browse the available images for your device
3. Images marked "Cached on your computer" will install faster

## From GitHub CI Builds

Access development builds directly from GitHub Actions.

### Authentication

GitHub builds from private repositories require authentication:

1. Go to **App Options** > **GitHub**
2. Click **Sign in with GitHub**
3. Follow the device authorization flow
4. Enter the code shown on github.com/login/device

### Selecting a Build

1. Select **GitHub** as the source
2. Choose a repository
3. Select a branch (e.g., `main`, `release`, or a feature branch)
4. Browse available CI build artifacts
5. The artifact ZIP will be downloaded and inspected
6. Select which file to install from the artifact contents

**Note:** CI build artifacts typically contain multiple files. The application will download the artifact, scan for installable images (WIC, VSI, SPU), and present them for selection with file type badges and sizes.

### Build Types

- ![Release](https://img.shields.io/badge/Release-28a745?style=flat-square) - Tagged releases
- ![CI Build](https://img.shields.io/badge/CI%20Build-6f42c1?style=flat-square) - Automated builds from GitHub Actions

## From Local File

Write an image file stored on your computer:

1. Select **Use custom file** in the image selection
2. Browse to your image file (.wic, .vsi, or .spu)
3. The file type is detected automatically from the extension

Supported formats:
- `.wic`, `.wic.xz`, `.wic.gz`, `.wic.bz2`, `.wic.zst` - Disk images
- `.vsi` - Versioned Sparse Images
- `.spu` - Software Package Updates

## Device Selection

### Supported Devices

- **SimPad PLUS** - SimPad PLUS tablet
- **SimPad PLUS 2** - Second generation SimPad
- **SimMan 3G** - SimMan 3G manikin controller
- **LinkBox** - LinkBox communication unit
- **CAN CPU** - CAN bus CPU module

### Storage Requirements

Ensure your SD card or USB drive has sufficient capacity:

- Check the **extract_size** shown in the image details
- Allow ~10% extra space for filesystem overhead
- Use high-quality, high-speed cards for best performance

## Image Customization

Some images support pre-write customization:

### Hostname

Set a custom hostname for the device.

### Network Configuration

- **Wi-Fi** - Configure SSID and password
- **Ethernet** - Static IP or DHCP settings

### User Accounts

- Set default username and password
- Configure SSH access

### Locale Settings

- Timezone
- Keyboard layout
- Language

**Note:** Customization is only available for images with `init_format` set (typically `systemd` or `cloudinit`).

## Application Options

Access via the **APP OPTIONS** button.

### General

- **Cache location** - Where downloaded images are stored
- **Clear cache** - Remove cached images to free disk space
- **Telemetry** - Enable/disable usage statistics

### GitHub

- **Sign in/Sign out** - Manage GitHub authentication
- **Repository settings** - Configure which repos to show

### Advanced

- **Enable debug output** - Show detailed logging
- **Skip verification** - Skip SHA256 verification (not recommended)

## Troubleshooting

### "No drives found"

- Ensure your SD card/USB drive is properly inserted
- Try a different USB port
- On Linux, check if the device appears in `lsblk`
- On Windows, check Disk Management

### "Permission denied"

- **Linux**: Run with `sudo` or add user to `disk` group
- **Windows**: Run as Administrator
- **macOS**: Grant disk access in System Preferences > Security

### "Verification failed"

The written image doesn't match the expected checksum:

1. Try writing again
2. Use a different SD card (the card may be failing)
3. Download a fresh copy of the image

### "Download failed"

- Check your internet connection
- For GitHub sources, verify your authentication is valid
- Check if the CDN/GitHub is accessible from your network

### Image not showing for my device

- Verify you selected the correct device type
- Some images are device-specific and won't appear for other devices
- Check if newer images are available

### Slow write speed

- Use a high-speed SD card (Class 10 or UHS-I recommended)
- USB 3.0 ports are faster than USB 2.0
- Cached images write faster than downloading during write

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Select current item / Confirm |
| `Escape` | Go back / Cancel |
| `Tab` | Navigate between controls |
| `↑` / `↓` | Navigate lists |
| `Ctrl+Q` | Quit application |

## Command Line Options

```sh
# Write image directly (no GUI interaction needed)
laerdal-simserver-imager --cli --image <url-or-path> --device <device-path>

# Start with a specific image URL
laerdal-simserver-imager --image-url https://example.com/image.wic

# Enable debug logging
laerdal-simserver-imager --debug
```

## Getting Help

- **In-app help**: Press `F1` or click the help button
- **Report issues**: [GitHub Issues](https://github.com/Laerdal-Medical/simserver-imager/issues)
- **Laerdal Support**: Contact your Laerdal representative
