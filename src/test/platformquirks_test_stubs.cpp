/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */

#include "../platformquirks.h"

// downloadonly_test only exercises local URL helpers; keep unrelated host
// services and platform libraries out of this test executable.
namespace PlatformQuirks {

bool hasNetworkConnectivity() {
  return false;
}

void beep() {}

bool isScrollInverted(bool qtInvertedFlag) {
  return qtInvertedFlag;
}

#ifdef Q_OS_LINUX
const char* findCACertBundle() {
  return nullptr;
}
#endif

}  // namespace PlatformQuirks
