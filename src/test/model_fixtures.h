/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#ifndef MODEL_FIXTURES_H
#define MODEL_FIXTURES_H

#include <QJsonArray>
#include <QJsonDocument>

#include "../hwlistmodel.h"

// Records what HWListModel asks its owner to do, using the model's public Actions seam.
struct TestOwner {
    QJsonDocument osListDocument;
    QJsonArray filterTags;
    QJsonArray capabilities;
    bool filterInclusive = false;
    int clearImageCalls = 0;

    HWListModel hw{HWListModel::Actions{
        [this](const QJsonArray &tags, bool inclusive) { filterTags = tags; filterInclusive = inclusive; },
        [this](const QJsonArray &caps) { capabilities = caps; },
        [this] { ++clearImageCalls; }}};
};

#endif
