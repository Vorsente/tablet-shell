// tablet-greeter: login screen of the ThinkPad 10 setup, styled like the Plasma Mobile lock screen.
// greetd (the login daemon: PAM, logind session, VT) runs it under the cage kiosk compositor and
// talks to it over $GREETD_SOCK (JSON messages with a 32-bit native-endian length prefix).
// Without $GREETD_SOCK it runs as a window in demo mode (password "test") for testing.
//
// Config: /etc/greetd/tablet-greeter.conf (INI, [General] user=, session=, wallpaper=) and the look
// shared with the lock screen: /var/lib/tablet-greeter/lock.conf (written by the settings app)
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlContext>
#include <QQuickView>
#include <QSettings>
#include <QTimer>

#include <pwd.h>

#include "tr.h"

class Greeter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString user MEMBER m_user CONSTANT)
    Q_PROPERTY(QString fullName MEMBER m_fullName CONSTANT)
    Q_PROPERTY(QString avatar MEMBER m_avatar CONSTANT)
    Q_PROPERTY(QString wallpaper MEMBER m_wallpaper CONSTANT)
    Q_PROPERTY(bool demo READ demo CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantMap config MEMBER m_config CONSTANT)

public:
    explicit Greeter(QObject *parent = nullptr)
        : QObject(parent)
    {
        QSettings cfg(qEnvironmentVariable("TABLET_GREETER_CONF", QStringLiteral("/etc/greetd/tablet-greeter.conf")), QSettings::IniFormat);
        m_user = cfg.value(QStringLiteral("user")).toString();
        m_wallpaper = cfg.value(QStringLiteral("wallpaper"), QStringLiteral("/var/lib/tablet-greeter/wallpaper.jpg")).toString();
        if (!QFile::exists(m_wallpaper)) {
            m_wallpaper.clear();
        }
        QSettings look(qEnvironmentVariable("TABLET_GREETER_LOOK", QStringLiteral("/var/lib/tablet-greeter/lock.conf")), QSettings::IniFormat);
        // [Login] group: the login screen's own look (the lock screen uses [Lock])
        look.beginGroup(QStringLiteral("Login"));
        for (const QString &k : look.childKeys()) {
            m_config.insert(k, look.value(k));
        }
        look.endGroup();
        // a session chosen in the settings app wins over the installer's default
        const QString session = m_config.value(QStringLiteral("session")).toString();
        m_session = sessionCommand(QFile::exists(session) ? session
                                   : cfg.value(QStringLiteral("session"), QStringLiteral("/usr/share/wayland-sessions/plasma.desktop")).toString());
        if (const passwd *pw = getpwnam(m_user.toLocal8Bit().constData())) {
            m_fullName = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0);
        }
        if (m_fullName.isEmpty()) {
            m_fullName = m_user;
        }
        const QString icon = QStringLiteral("/var/lib/AccountsService/icons/") + m_user;
        if (!m_user.isEmpty() && QFileInfo(icon).isFile()) {
            m_avatar = QStringLiteral("file://") + icon;
        }
        const QByteArray sock = qgetenv("GREETD_SOCK");
        m_demo = sock.isEmpty();
        if (!m_demo) {
            m_socket.connectToServer(QString::fromLocal8Bit(sock));
            connect(&m_socket, &QLocalSocket::readyRead, this, &Greeter::onReadyRead);
        }
    }

    bool demo() const
    {
        return m_demo;
    }
    bool busy() const
    {
        return m_busy;
    }

    Q_INVOKABLE void login(const QString &password)
    {
        if (m_busy) {
            return;
        }
        setBusy(true);
        m_password = password;
        if (demo()) {
            QTimer::singleShot(400, this, [this] {
                setBusy(false);
                if (m_password == QLatin1String("test")) {
                    Q_EMIT loggedIn();
                } else {
                    Q_EMIT failed(T(QStringLiteral("Неверный пароль")));
                }
            });
            return;
        }
        m_state = Authenticating;
        send({{QStringLiteral("type"), QStringLiteral("create_session")}, {QStringLiteral("username"), m_user}});
    }

    Q_INVOKABLE void powerOff()
    {
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
    }
    Q_INVOKABLE void reboot()
    {
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
    }
    Q_INVOKABLE void suspend()
    {
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("suspend")});
    }

Q_SIGNALS:
    void failed(const QString &message);
    void loggedIn();
    void busyChanged();

private:
    // Exec= line of a wayland-sessions .desktop file, split like a shell would (no quoting needed here)
    static QStringList sessionCommand(const QString &desktopFile)
    {
        QFile f(desktopFile);
        if (f.open(QIODevice::ReadOnly)) {
            while (!f.atEnd()) {
                const QString line = QString::fromUtf8(f.readLine()).trimmed();
                if (line.startsWith(QLatin1String("Exec="))) {
                    return line.mid(5).split(QLatin1Char(' '), Qt::SkipEmptyParts);
                }
            }
        }
        return {QStringLiteral("/usr/bin/startplasma-wayland")};
    }

    void setBusy(bool b)
    {
        if (m_busy != b) {
            m_busy = b;
            Q_EMIT busyChanged();
        }
    }

    void send(const QJsonObject &msg)
    {
        const QByteArray body = QJsonDocument(msg).toJson(QJsonDocument::Compact);
        const quint32 len = body.size();
        m_socket.write(reinterpret_cast<const char *>(&len), sizeof(len));
        m_socket.write(body);
        m_socket.flush();
    }

    void onReadyRead()
    {
        m_buffer += m_socket.readAll();
        while (m_buffer.size() >= 4) {
            quint32 len;
            memcpy(&len, m_buffer.constData(), sizeof(len));
            if (quint32(m_buffer.size()) < 4 + len) {
                return;
            }
            const QJsonObject msg = QJsonDocument::fromJson(m_buffer.mid(4, len)).object();
            m_buffer.remove(0, 4 + len);
            handle(msg);
        }
    }

    void handle(const QJsonObject &msg)
    {
        const QString type = msg.value(QStringLiteral("type")).toString();
        if (type == QLatin1String("auth_message")) {
            // the password for secret/visible prompts, an empty answer for info/error lines
            const QString kind = msg.value(QStringLiteral("auth_message_type")).toString();
            QJsonObject reply{{QStringLiteral("type"), QStringLiteral("post_auth_message_response")}};
            if (kind == QLatin1String("secret") || kind == QLatin1String("visible")) {
                reply.insert(QStringLiteral("response"), m_password);
            }
            send(reply);
        } else if (type == QLatin1String("success")) {
            if (m_state == Cancelling) {
                // the answer to cancel_session after a wrong password
                m_state = Idle;
                setBusy(false);
            } else if (m_state == Authenticating) {
                // authenticated: hand the session command to greetd; it starts it once we exit
                m_state = Starting;
                m_password.fill(QLatin1Char(' '));
                m_password.clear();
                QJsonArray cmd;
                for (const QString &a : std::as_const(m_session)) {
                    cmd.append(a);
                }
                send({{QStringLiteral("type"), QStringLiteral("start_session")}, {QStringLiteral("cmd"), cmd},
                      {QStringLiteral("env"), QJsonArray{QStringLiteral("XDG_SESSION_TYPE=wayland"), QStringLiteral("XDG_SESSION_DESKTOP=KDE"),
                                                         QStringLiteral("XDG_CURRENT_DESKTOP=KDE"), QStringLiteral("DESKTOP_SESSION=plasma")}}});
            } else if (m_state == Starting) {
                m_state = Idle;
                Q_EMIT loggedIn();
            }
        } else if (type == QLatin1String("error")) {
            m_password.fill(QLatin1Char(' '));
            m_password.clear();
            // the session must be cancelled before the next try; busy until greetd confirmed it
            m_state = Cancelling;
            send({{QStringLiteral("type"), QStringLiteral("cancel_session")}});
            Q_EMIT failed(msg.value(QStringLiteral("error_type")).toString() == QLatin1String("auth_error")
                              ? T(QStringLiteral("Неверный пароль"))
                              : msg.value(QStringLiteral("description")).toString());
        }
    }

    QLocalSocket m_socket;
    QByteArray m_buffer;
    QString m_user, m_fullName, m_avatar, m_wallpaper, m_password;
    QStringList m_session;
    QVariantMap m_config;
    bool m_demo = true;
    bool m_busy = false;
    enum { Idle, Authenticating, Starting, Cancelling } m_state = Idle;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("tablet-greeter"));
    Greeter greeter;
    QQuickView view;
    view.setColor(Qt::black);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty(QStringLiteral("greeter"), &greeter);
    QObject::connect(&greeter, &Greeter::loggedIn, &app, [&app] {
        // let the fade-out finish, then exit: greetd starts the session after the greeter is gone
        QTimer::singleShot(350, &app, &QCoreApplication::quit);
    });
    const QString dir = qEnvironmentVariable("TABLET_GREETER_QML", QStringLiteral("/usr/local/share/tablet-greeter"));
    view.setSource(QUrl::fromLocalFile(dir + QStringLiteral("/Main.qml")));
    if (greeter.demo()) {
        view.resize(1280, 800);
        view.show();
    } else {
        view.showFullScreen();
    }
    return app.exec();
}

#include "main.moc"
