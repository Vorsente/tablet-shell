// tablet-settings: settings app for the ThinkPad 10 tablet environment (modes, gestures, home
// screen, power button, pen, typewriter, reading mode, Android...). C++ backend + Kirigami UI that
// adapts to the mode: touch-first in tablet mode, keyboard/mouse-first in PC mode.
#include "backend.h"
#include "../common/ui-style.h"

#include <QApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "tr.h"
#include <QtCore/qlogging.h>

int main(int argc, char *argv[])
{
    // Keep Qt diagnostics silent without an app-local helper declaration.
    // TABLET_SHELL_DEBUG=1 keeps Qt/QML messages for troubleshooting
    if (!qEnvironmentVariableIsSet("TABLET_SHELL_DEBUG")) qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("tablet-settings"));
    app.setApplicationDisplayName(T(QStringLiteral("Настройки планшета")));
    app.setDesktopFileName(QStringLiteral("tablet-settings"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-system")));
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    Backend backend;
    // `tablet-settings kcm_foo` (or the System Settings command line) opens that module directly
    QString module;
    for (const QString &arg : app.arguments().mid(1)) {
        if (!arg.startsWith(QLatin1Char('-'))) {
            module = arg;
            break;
        }
    }
    // one window: a second launch passes its module to the running app and exits
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.ipad.TabletSettings"))) {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.ipad.TabletSettings"), QStringLiteral("/"),
                                                          QStringLiteral("org.ipad.TabletSettings"), QStringLiteral("OpenModule"));
        msg << module;
        bus.call(msg, QDBus::Block, 3000);
        return 0;
    }
    bus.registerObject(QStringLiteral("/"), QStringLiteral("org.ipad.TabletSettings"), &backend, QDBusConnection::ExportScriptableSlots);
    backend.setStartModule(module);
    // shared with the embedded KDE settings modules
    auto engine = std::make_shared<QQmlApplicationEngine>();
    backend.setEngine(engine);
    UiStyle uiStyle;
    engine->rootContext()->setContextProperty(QStringLiteral("uiStyle"), &uiStyle);
    engine->rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine->load(QUrl::fromLocalFile(QStringLiteral(APP_DIR "/qml/Main.qml")));
    if (engine->rootObjects().isEmpty()) {
        return 1;
    }
    return app.exec();
}
