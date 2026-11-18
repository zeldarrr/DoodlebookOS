// SPDX-License-Identifier: GPL-3.0-or-later
// doodlebookos-qml — runs DoodlebookOS's QML apps (« Fond d'écran et style », capture thumbnail)
// where Qt's own `qml` tool isn't installed (Fedora / Bazzite ship it only in -devel packages).
//   doodlebookos-qml [-d desktop-file-id] FILE.qml [-- args…]
// A QApplication, so KDE's Qt Quick style (and the DoodlebookOS app style) can draw controls; the
// desktop file id gives the window its app icon and name on Wayland.
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QUrl>
#include <QFileInfo>
#include <cstdio>

int main(int argc, char **argv)
{
    QString desktopId;
    QString file;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == QLatin1String("--")) {
            break;
        } else if (a == QLatin1String("-d") && i + 1 < argc) {
            desktopId = QString::fromLocal8Bit(argv[++i]);
        } else if (file.isEmpty()) {
            file = a;
        }
    }
    if (file.isEmpty()) {
        std::fprintf(stderr, "usage: doodlebookos-qml [-d desktop-file-id] FILE.qml [-- args]\n");
        return 2;
    }
    QApplication app(argc, argv);
    if (!desktopId.isEmpty()) {
        QGuiApplication::setDesktopFileName(desktopId);
    }
    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::quit, &app, &QCoreApplication::quit, Qt::QueuedConnection);
    QObject::connect(&engine, &QQmlApplicationEngine::exit, &app, &QCoreApplication::exit, Qt::QueuedConnection);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(QUrl::fromLocalFile(QFileInfo(file).absoluteFilePath()));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    return app.exec();
}
