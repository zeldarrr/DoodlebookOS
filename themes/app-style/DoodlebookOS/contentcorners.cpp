/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "contentcorners.h"
#include "metrics.h"
#include "propertynames.h"

#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QDockWidget>
#include <QEvent>
#include <QMainWindow>
#include <QPainter>
#include <QPainterPath>
#include <QPlainTextEdit>
#include <QRegion>
#include <QTextEdit>
#include <QTimer>

#include <cmath>

namespace DoodlebookOS
{
namespace
{
const char MaskedProperty[] = "_doodle_corner_masked";
const char AutoFillProperty[] = "_doodle_corner_autofill";

QWidget *visibleChild(QAbstractScrollArea *area, const char *name)
{
    auto w = area->findChild<QWidget *>(QLatin1String(name), Qt::FindDirectChildrenOnly);
    return (w && w->isVisibleTo(area)) ? w : nullptr;
}

// mask for a child of a framed area so that it stays inside the frame's rounded inner edge
QRegion frameCornerMask(const QRect &g, const QRect &fr)
{
    const int R = Metrics::Frame_FrameRadius;   // the outline arc is centred R px in from each side
    const qreal inner = R - 1.0;                // inner edge of the 1 px outline
    QRegion cut;
    for (int c = 0; c < 4; ++c) {
        const bool left = (c == 0 || c == 2);
        const bool top = (c == 0 || c == 1);
        const QRect zone(left ? fr.left() : fr.right() + 1 - R, top ? fr.top() : fr.bottom() + 1 - R, R, R);
        const QRect hit = zone & g;
        if (hit.isEmpty()) {
            continue;
        }
        const qreal cx = left ? fr.left() + R : fr.right() + 1 - R;
        const qreal cy = top ? fr.top() + R : fr.bottom() + 1 - R;
        for (int y = hit.top(); y <= hit.bottom(); ++y) {
            const qreal dy = std::abs(cy - (y + 0.5));
            QRect row;
            if (dy >= inner) {
                row = QRect(zone.left(), y, R, 1);
            } else {
                const qreal dx = std::sqrt(inner * inner - dy * dy);
                if (left) {
                    const int firstKept = int(std::ceil(cx - dx - 0.5));
                    row = QRect(zone.left(), y, firstKept - zone.left(), 1);
                } else {
                    const int lastKept = int(std::floor(cx + dx - 0.5));
                    row = QRect(lastKept + 1, y, zone.right() - lastKept, 1);
                }
            }
            row &= g;
            if (!row.isEmpty()) {
                cut += row;
            }
        }
    }
    if (cut.isEmpty()) {
        return QRegion();
    }
    return (QRegion(g) - cut).translated(-g.topLeft());
}

// the colour actually visible at a point of the window, if it is the plain window background
bool isChromeAt(QWidget *window, const QPoint &pos, const QColor &chrome)
{
    if (!window->rect().contains(pos)) {
        return false;
    }
    for (QWidget *w = window->childAt(pos); w && w != window; w = w->parentWidget()) {
        if (w->autoFillBackground() || w->testAttribute(Qt::WA_OpaquePaintEvent)) {
            return w->palette().color(w->backgroundRole()) == chrome;
        }
    }
    return true;
}
}

//____________________________________________________________________________________
CornerPatch::CornerPatch(QWidget *parent, Corner corner)
    : QWidget(parent)
    , _corner(corner)
{
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setFocusPolicy(Qt::NoFocus);
    setAutoFillBackground(false);
}

void CornerPatch::setColor(const QColor &color)
{
    if (color != _color) {
        _color = color;
        update();
    }
}

void CornerPatch::paintEvent(QPaintEvent *)
{
    const qreal r = qMin(width(), height());
    if (r <= 0) {
        return;
    }
    QRectF circle(0, 0, 2 * r, 2 * r);
    if (_corner == TopRight || _corner == BottomRight) {
        circle.moveLeft(-r);
    }
    if (_corner == BottomLeft || _corner == BottomRight) {
        circle.moveTop(-r);
    }
    QPainterPath outside;
    outside.addRect(QRectF(rect()));
    QPainterPath inside;
    inside.addEllipse(circle);
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.fillPath(outside.subtracted(inside), _color);
}

//____________________________________________________________________________________
ContentCorners::ContentCorners(QObject *parent)
    : QObject(parent)
{
}

bool ContentCorners::hasRoundedFrame(const QAbstractScrollArea *area)
{
    return area->frameShape() == QFrame::StyledPanel && area->frameShadow() != QFrame::Plain && area->frameWidth() > 0
        && !area->property(PropertyNames::bordersSides).isValid() && !area->property(PropertyNames::sidePanelView).toBool();
}

void ContentCorners::registerWidget(QWidget *widget)
{
    auto area = qobject_cast<QAbstractScrollArea *>(widget);
    if (!area || _areas.contains(area) || !area->viewport() || area->inherits("QComboBoxListView")) {
        return;
    }
    _areas.insert(area);
    area->installEventFilter(this);
    area->viewport()->installEventFilter(this);
    connect(area, &QObject::destroyed, this, [this](QObject *o) {
        _areas.remove(o);
        _pending.remove(o);
        removePatches(o);
    });
    schedule(area);
}

void ContentCorners::unregisterWidget(QWidget *widget)
{
    if (!_areas.remove(widget)) {
        return;
    }
    _pending.remove(widget);
    widget->removeEventFilter(this);
    auto area = static_cast<QAbstractScrollArea *>(widget);
    if (area->viewport()) {
        area->viewport()->removeEventFilter(this);
    }
    removePatches(area);
    updateFramed(area, false);
}

void ContentCorners::refresh(QWidget *widget)
{
    if (_areas.contains(widget)) {
        schedule(static_cast<QAbstractScrollArea *>(widget));
    }
}

bool ContentCorners::contentEligible(QAbstractScrollArea *area) const
{
    if (!area->isVisible() || area->frameShape() != QFrame::NoFrame || area->viewport()->backgroundRole() != QPalette::Base
        || area->property(PropertyNames::sidePanelView).toBool()) {
        return false;
    }
    if (!qobject_cast<QMainWindow *>(area->window())) {
        return false;   // main application windows only (no dialogs, popups, embedded lists)
    }
    for (QWidget *p = area->parentWidget(); p && !p->isWindow(); p = p->parentWidget()) {
        if (qobject_cast<QDockWidget *>(p)) {
            return false;   // side panels
        }
    }
    const QSize s = area->viewport()->size();
    return s.width() >= 240 && s.height() >= 160;
}

bool ContentCorners::framedEligible(QAbstractScrollArea *area) const
{
    if (!hasRoundedFrame(area) || !area->styleSheet().isEmpty()) {
        return false;
    }
    // views that scroll their viewport by repainting it; a QScrollArea moves a child widget instead
    if (!(qobject_cast<QAbstractItemView *>(area) || qobject_cast<QTextEdit *>(area) || qobject_cast<QPlainTextEdit *>(area))) {
        return false;
    }
    if (area->window()->windowType() == Qt::Popup) {
        return false;
    }
    QWidget *vp = area->viewport();
    if (vp->testAttribute(Qt::WA_OpaquePaintEvent) || vp->inherits("QOpenGLWidget") || !vp->styleSheet().isEmpty()) {
        return false;
    }
    // the frame paints the area's base colour: only let it show through when it is the same colour
    if (vp->autoFillBackground() && !vp->property(AutoFillProperty).toBool()) {
        const QBrush brush = vp->palette().brush(vp->backgroundRole());
        if (brush.style() != Qt::SolidPattern || brush.color() != area->palette().color(QPalette::Base)) {
            return false;
        }
    }
    const QRect fr = area->frameRect();
    return fr.width() >= 4 * Metrics::Frame_FrameRadius && fr.height() >= 3 * Metrics::Frame_FrameRadius;
}

bool ContentCorners::eventFilter(QObject *object, QEvent *event)
{
    switch (event->type()) {
    case QEvent::Show:
    case QEvent::Hide:
    case QEvent::Move:
    case QEvent::Resize:
    case QEvent::PaletteChange:
    case QEvent::ParentChange:
    case QEvent::ChildAdded:
        if (_watched.contains(object)) {
            scheduleWindow(static_cast<QWidget *>(object)->window());
        }
        if (event->type() == QEvent::ChildAdded) {
            break;
        }
        if (_areas.contains(object)) {
            schedule(static_cast<QAbstractScrollArea *>(object));
        } else {
            // a viewport (scroll bars appearing / disappearing resize it)
            if (auto area = qobject_cast<QAbstractScrollArea *>(static_cast<QWidget *>(object)->parentWidget()); area && _areas.contains(area)) {
                schedule(area);
            }
        }
        break;
    default:
        break;
    }
    return false;
}

void ContentCorners::schedule(QAbstractScrollArea *area)
{
    if (_pending.contains(area)) {
        return;
    }
    _pending.insert(area);
    QPointer<QAbstractScrollArea> guard(area);
    QTimer::singleShot(0, this, [this, guard]() {
        if (!guard) {
            return;
        }
        _pending.remove(guard.data());
        if (_areas.contains(guard.data())) {
            updateArea(guard.data());
        }
    });
}

void ContentCorners::scheduleWindow(QWidget *window)
{
    // only content views follow their ancestors
    for (auto it = _patches.cbegin(); it != _patches.cend(); ++it) {
        auto area = static_cast<QAbstractScrollArea *>(it.key());
        if (_areas.contains(area) && area->window() == window) {
            schedule(area);
        }
    }
}

void ContentCorners::watchAncestors(QWidget *area)
{
    // a sidebar toggle moves an ancestor, not the view itself: follow the chain up to the window
    for (QWidget *p = area->parentWidget(); p; p = p->parentWidget()) {
        if (!_watched.contains(p)) {
            _watched.insert(p);
            p->installEventFilter(this);
            connect(p, &QObject::destroyed, this, [this](QObject *o) {
                _watched.remove(o);
            });
        }
        if (p->isWindow()) {
            break;
        }
    }
}

void ContentCorners::removePatches(QObject *area)
{
    const auto it = _patches.find(area);
    if (it == _patches.end()) {
        return;
    }
    for (const auto &patch : std::as_const(*it)) {
        if (patch) {
            patch->hide();
            patch->deleteLater();
        }
    }
    _patches.erase(it);
}

void ContentCorners::updateArea(QAbstractScrollArea *area)
{
    if (!area->isVisible()) {
        updateContent(area, false);   // hidden: keep the framed state, just hide the overlays
        return;
    }
    const bool content = contentEligible(area);
    updateContent(area, content);
    updateFramed(area, !content && framedEligible(area));
}

void ContentCorners::updateContent(QAbstractScrollArea *area, bool enabled)
{
    if (!enabled) {
        if (const auto it = _patches.constFind(area); it != _patches.cend()) {
            for (const auto &patch : *it) {
                if (patch) {
                    patch->hide();
                }
            }
        }
        return;
    }

    watchAncestors(area);
    QWidget *win = area->window();
    const QColor chrome = win->palette().color(QPalette::Window);
    const QPoint offset = area->mapTo(win, QPoint(0, 0));
    const QRect areaRect(offset, area->size());
    const QRect vp = area->viewport()->geometry().translated(offset);
    const QRect wr = win->rect();
    const int r = qMin(ContentRadius, qMin(vp.width(), vp.height()) / 2);

    bool left = areaRect.left() > wr.left() + 2;
    bool top = areaRect.top() > wr.top() + 2;
    bool right = areaRect.right() < wr.right() - 2;
    bool bottom = areaRect.bottom() < wr.bottom() - 2;
    // never curve next to a scroll bar: it would stick out of the rounded edge
    if (QWidget *vc = visibleChild(area, "qt_scrollarea_vcontainer")) {
        (vc->x() > area->viewport()->x() ? right : left) = false;
    }
    if (visibleChild(area, "qt_scrollarea_hcontainer")) {
        bottom = false;
    }
    // only curve into the window chrome, not into another view
    left = left && isChromeAt(win, QPoint(vp.left() - 1, vp.center().y()), chrome);
    right = right && isChromeAt(win, QPoint(vp.right() + 1, vp.center().y()), chrome);
    top = top && isChromeAt(win, QPoint(vp.center().x(), vp.top() - 1), chrome);
    bottom = bottom && isChromeAt(win, QPoint(vp.center().x(), vp.bottom() + 1), chrome);

    const bool want[4] = {left && top, right && top, left && bottom, right && bottom};
    if (!_patches.contains(area) && !(want[0] || want[1] || want[2] || want[3])) {
        return;
    }
    Patches &patches = _patches[area];
    for (int c = 0; c < 4; ++c) {
        QPointer<CornerPatch> &patch = patches[c];
        if (!want[c] || r <= 0) {
            if (patch) {
                patch->hide();
            }
            continue;
        }
        if (patch && patch->parentWidget() != win) {
            patch->deleteLater();
            patch = nullptr;
        }
        if (!patch) {
            // child of the window, above everything (overlays such as floating status bars included)
            patch = new CornerPatch(win, static_cast<CornerPatch::Corner>(c));
        }
        const int x = (c == CornerPatch::TopLeft || c == CornerPatch::BottomLeft) ? vp.left() : vp.right() + 1 - r;
        const int y = (c == CornerPatch::TopLeft || c == CornerPatch::TopRight) ? vp.top() : vp.bottom() + 1 - r;
        patch->setGeometry(x, y, r, r);
        patch->setColor(chrome);
        patch->raise();
        patch->show();
    }
}

void ContentCorners::updateFramed(QAbstractScrollArea *area, bool enabled)
{
    const QRect fr = area->frameRect();
    const auto children = area->children();
    for (QObject *child : children) {
        auto w = qobject_cast<QWidget *>(child);
        if (!w || w->isWindow() || qobject_cast<CornerPatch *>(w) || w->inherits("DoodlebookOS::FrameShadow")) {
            continue;
        }
        const QRegion mask = enabled ? frameCornerMask(w->geometry(), fr) : QRegion();
        if (!mask.isEmpty()) {
            if (w->mask() != mask) {
                w->setMask(mask);
            }
            w->setProperty(MaskedProperty, true);
        } else if (w->property(MaskedProperty).toBool()) {
            w->clearMask();
            w->setProperty(MaskedProperty, QVariant());
        }
    }

    // the viewport stops painting its square background: the frame's rounded base shows instead.
    // A non-opaque viewport is also scrolled by repainting, so the mask never gets blitted around.
    QWidget *vp = area->viewport();
    if (enabled) {
        if (vp->autoFillBackground()) {
            vp->setAutoFillBackground(false);
            vp->setProperty(AutoFillProperty, true);
        }
    } else if (vp->property(AutoFillProperty).toBool()) {
        vp->setAutoFillBackground(true);
        vp->setProperty(AutoFillProperty, QVariant());
    }
}
}
