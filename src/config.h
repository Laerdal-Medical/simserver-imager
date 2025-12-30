#ifndef CONFIG_H
#define CONFIG_H

/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 *
 * Laerdal SimServer Imager Configuration
 */


/* Default Repository URL - Laerdal CDN Production (factory WIC images) */
#define OSLIST_URL                        "https://laerdalcdn.blob.core.windows.net/software/release/SimPad/factory-images/images.json"

/* GitHub OAuth Client ID - Register at https://github.com/settings/developers */
#define GITHUB_CLIENT_ID                  "Ov23liKEkgjtcfPAqOpG"

/* Default GitHub repositories for WIC files (JSON array) */
#define DEFAULT_GITHUB_REPOS              "[\"LaerdalMedical/simpad-top-plus\",\"LaerdalMedical/simserver-mcbapp\",\"LaerdalMedical/simpad-app-next\",\"LaerdalMedical/simserver-shared-libs\"]"

/* Custom repository manifest file extension (without leading dot) */
#define MANIFEST_EXTENSION                "laerdal-imager-manifest"

/* MIME type for manifest files */
#define MANIFEST_MIME_TYPE                "application/vnd.laerdal.imager-manifest+json"

/* Time synchronization URL (only used on linuxfb QPA platform, URL must be HTTP) */
#define TIME_URL                          "http://laerdalcdn.blob.core.windows.net/"

/* Telemetry disabled for Laerdal version */
#define TELEMETRY_URL                     ""

/* Hash algorithm for verifying (uncompressed image) checksum */
#define OSLIST_HASH_ALGORITHM             QCryptographicHash::Sha256

/* Update progressbar every 0.1 second */
#define PROGRESS_UPDATE_INTERVAL          100

/* Default block size for buffer allocation (dynamically adjusted at runtime) */
#define IMAGEWRITER_BLOCKSIZE             1*1024*1024

/* Enable caching */
#define IMAGEWRITER_ENABLE_CACHE_DEFAULT        true

/* Do not cache if it would bring free disk space under 5 GB */
#define IMAGEWRITER_MINIMAL_SPACE_FOR_CACHING   5*1024*1024*1024ll

#endif // CONFIG_H
