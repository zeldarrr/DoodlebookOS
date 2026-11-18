/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * DoodlebookOS: rounded corners for scroll areas.
 *
 * - Main content view of a window (e.g. Dolphin's file view, frameless): where the view meets
 *   the window chrome (sidebar, toolbar), a small overlay paints the chrome colour outside a
 *   quarter circle, so the lighter chrome appears to curve into the darker content. Corners on
 *   the window edge, next to a scroll bar or next to non-chrome neighbours stay square.
 * - Framed scroll areas (lists, trees, text edits): the frame is rounded but the viewport and
 *   headers are square and used to stick out of it. Their corners are masked to the frame curve
 *   and the viewport stops auto-filling, so the frame's own rounded base shows through.
 *
 * Event driven: everything is recomputed (coalesced) only on geometry / visibility / palette
 * changes of the area, its viewport or, for content views, its ancestors.
 */
#pragma once

#include <QColor>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QWidget>

#include <array>

class QAbstractScrollArea;

namespace DoodlebookOS
{
class CornerPatch : public QWidget
{
    Q_OBJECT
public:
    enum Corner { TopLeft = 0, TopRight, BottomLeft, BottomRight };
    CornerPatch(QWidget *parent, Corner corner);
    void setColor(const QColor &color);

protected:
    void paintEvent(QPaintEvent *) override;

private:
    Corner _corner;
    QColor _color;
};

class ContentCorners : public QObject
{
    Q_OBJECT
public:
    explicit ContentCorners(QObject *parent = nullptr);
    void registerWidget(QWidget *widget);
    void unregisterWidget(QWidget *widget);
    // re-evaluate a registered view after its frame changed
    void refresh(QWidget *widget);
    bool eventFilter(QObject *object, QEvent *event) override;

    //* true when the area's frame is drawn rounded by the style (used for the scroll bar background too)
    static bool hasRoundedFrame(const QAbstractScrollArea *area);

private:
    static constexpr int ContentRadius = 14;
    using Patches = std::array<QPointer<CornerPatch>, 4>;

    bool contentEligible(QAbstractScrollArea *area) const;
    bool framedEligible(QAbstractScrollArea *area) const;
    void schedule(QAbstractScrollArea *area);
    void scheduleWindow(QWidget *window);
    void updateArea(QAbstractScrollArea *area);
    void updateContent(QAbstractScrollArea *area, bool enabled);
    void updateFramed(QAbstractScrollArea *area, bool enabled);
    void removePatches(QObject *area);
    void watchAncestors(QWidget *area);

    QSet<QObject *> _areas;
    QSet<QObject *> _watched;
    QSet<QObject *> _pending;
    QHash<QObject *, Patches> _patches;
};
}
