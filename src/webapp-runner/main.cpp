// Minimal web app window: webapp-runner <id> <name> <url>
// The id becomes the Wayland app id, so the dock and task switcher show the app's own icon.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtWebEngineQuick/QtWebEngineQuick>

int main(int argc, char *argv[])
{
    if (argc < 4) {
        qWarning("usage: webapp-runner <id> <name> <url>");
        return 1;
    }
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    const QString id = QString::fromLocal8Bit(argv[1]);
    app.setDesktopFileName(id);
    app.setApplicationName(id);
    app.setApplicationDisplayName(QString::fromLocal8Bit(argv[2]));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appId", id);
    engine.rootContext()->setContextProperty("appName", QString::fromLocal8Bit(argv[2]));
    engine.rootContext()->setContextProperty("startUrl", QUrl::fromUserInput(QString::fromLocal8Bit(argv[3])));
    engine.load(QUrl::fromLocalFile(QStringLiteral(RUNNER_DIR "/webapp.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    return app.exec();
}
