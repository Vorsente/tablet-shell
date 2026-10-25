// tabletshell: small always-on-top tablet UI pieces drawn on the layer-shell overlay layer.
//   tabletshell control   control center (D-Bus org.ipad.TabletShell: ToggleControlCenter, Back,
//                         ModeTransition/ModeReady = mode change animation, ShowCharging = charging
//                         animation, PowerMenu, PenRing; it also plays the lock/unlock sounds)
//   tabletshell pill      typewriter status pill: battery, clock, words today; while it runs
//                         notifications are inhibited (focus) and key presses are reported for sounds
// The QML files next to this binary describe the UI; `shell` gives them process and file helpers.
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusConnectionInterface>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDate>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTimer>
#include <QSocketNotifier>
#include <QJsonArray>
#include <QGuiApplication>
#include <QProcess>
#include <QSettings>
#include <QSet>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QPainterPath>
#include <QRegion>

#include <KWindowEffects>

#include <malloc.h>

#include <fcntl.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <algorithm>

#include "tr.h"
#include <QtCore/qlogging.h>
#include "../common/ui-style.h"

// AT-SPI object reference (a(so) in the accessibility bus API)
struct AtspiRef {
    QString service;
    QDBusObjectPath path;
};
Q_DECLARE_METATYPE(AtspiRef)
QDBusArgument &operator<<(QDBusArgument &arg, const AtspiRef &r)
{
    arg.beginStructure();
    arg << r.service << r.path;
    arg.endStructure();
    return arg;
}
const QDBusArgument &operator>>(const QDBusArgument &arg, AtspiRef &r)
{
    arg.beginStructure();
    arg >> r.service >> r.path;
    arg.endStructure();
    return arg;
}

class Shell : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.ipad.TabletShell")
    // KWin's tablet mode (the back gesture strip only exists in tablet mode)
    Q_PROPERTY(bool tabletMode READ tabletMode NOTIFY tabletModeChanged)
    // apps recording right now (privacy indicator, RecordingIndicator.qml)
    Q_PROPERTY(QStringList micApps MEMBER m_micApps NOTIFY recordingChanged)
    Q_PROPERTY(QStringList cameraApps MEMBER m_cameraApps NOTIFY recordingChanged)

public:
    ~Shell() override
    {
        if (m_uinput >= 0) {
            ioctl(m_uinput, UI_DEV_DESTROY);
            close(m_uinput);
        }
    }

    // Run a command and return its stdout (short helpers only: blocks the UI while running)
    Q_INVOKABLE QString run(const QStringList &cmd)
    {
        if (cmd.isEmpty()) {
            return {};
        }
        QProcess p;
        p.setProcessEnvironment(childEnvironment());
        p.start(cmd.first(), cmd.mid(1));
        p.waitForFinished(5000);
        return QString::fromUtf8(p.readAllStandardOutput());
    }

    Q_INVOKABLE void start(const QStringList &cmd)
    {
        if (!cmd.isEmpty()) {
            QProcess p;
            p.setProgram(cmd.first());
            p.setArguments(cmd.mid(1));
            p.setProcessEnvironment(childEnvironment());
            p.startDetached();
        }
    }

    // Our own surfaces are layer-shell (QT_WAYLAND_SHELL_INTEGRATION, set in main). Apps started
    // from here must not inherit it: they became layer surfaces too - no title, not in the task
    // switcher, the home gesture could not minimize them (seen with Settings from a tile).
    static QProcessEnvironment childEnvironment()
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.remove(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"));
        return env;
    }

    // the first battery (BAT0, BAT1, CMB0 ...), "" without one
    Q_INVOKABLE QString batteryDir() const
    {
        const QDir power(QStringLiteral("/sys/class/power_supply"));
        for (const QString &d : power.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            QFile type(power.filePath(d + QStringLiteral("/type")));
            if (type.open(QIODevice::ReadOnly) && type.readAll().trimmed() == "Battery") {
                return power.filePath(d);
            }
        }
        return QString();
    }

    // KWin blur behind parts of one of our windows (Liquid Glass): areas are
    // {x, y, width, height, radius} in window coordinates; none = blur off
    Q_INVOKABLE void blurBehind(QWindow *window, const QVariantList &areas)
    {
        if (!window) {
            return;
        }
        QRegion region;
        for (const QVariant &v : areas) {
            const QVariantMap a = v.toMap();
            const QRectF r(a.value(QStringLiteral("x")).toReal(), a.value(QStringLiteral("y")).toReal(),
                           a.value(QStringLiteral("width")).toReal(), a.value(QStringLiteral("height")).toReal());
            QPainterPath path;
            path.addRoundedRect(r, a.value(QStringLiteral("radius")).toReal(), a.value(QStringLiteral("radius")).toReal());
            region += QRegion(path.toFillPolygon().toPolygon());
        }
        KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
    }

    Q_INVOKABLE QString readFile(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
    }

    Q_INVOKABLE QString currentApp() const
    {
        return m_currentApp;
    }

    Q_INVOKABLE QString env(const QString &name)
    {
        return qEnvironmentVariable(name.toLocal8Bit().constData());
    }

    // After a panel was closed (QML ran gc() first): hidden windows drop their scene graph and
    // GPU buffers, and freed heap goes back to the system (this process lives all session long)
    // Put the text cursor of an app's editor at the first occurrence of `needle`, through the
    // accessibility bus (AT-SPI Text.SetCaretOffset; the editor scrolls there). Used by the
    // typewriter panel to jump to a scene: ghostwriter's menu shortcuts (find) are dead while its
    // menu bar is hidden in full screen. The app needs QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1.
    Q_INVOKABLE bool jumpToText(const QString &app, const QString &needle)
    {
        qDBusRegisterMetaType<AtspiRef>();
        qDBusRegisterMetaType<QList<AtspiRef>>();
        QDBusInterface a11y(QStringLiteral("org.a11y.Bus"), QStringLiteral("/org/a11y/bus"), QStringLiteral("org.a11y.Bus"));
        const QDBusReply<QString> address = a11y.call(QStringLiteral("GetAddress"));
        if (!address.isValid()) {
            return false;
        }
        QDBusConnection bus = QDBusConnection::connectToBus(address.value(), QStringLiteral("tabletshell-a11y"));
        const QString accessible = QStringLiteral("org.a11y.atspi.Accessible");
        auto children = [&](const AtspiRef &r) {
            QDBusMessage m = QDBusMessage::createMethodCall(r.service, r.path.path(), accessible, QStringLiteral("GetChildren"));
            const QDBusReply<QList<AtspiRef>> reply = bus.call(m, QDBus::Block, 1000);
            return reply.isValid() ? reply.value() : QList<AtspiRef>();
        };
        auto call = [&](const AtspiRef &r, const QString &iface, const QString &method, const QVariantList &args = {}) {
            QDBusMessage m = QDBusMessage::createMethodCall(r.service, r.path.path(), iface, method);
            m.setArguments(args);
            const QDBusMessage reply = bus.call(m, QDBus::Block, 1000);
            return reply.arguments().value(0);
        };
        auto name = [&](const AtspiRef &r) {
            return call(r, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"), {accessible, QStringLiteral("Name")})
                .value<QDBusVariant>().variant().toString();
        };
        for (const AtspiRef &appRef : children({QStringLiteral("org.a11y.atspi.Registry"), QDBusObjectPath(QStringLiteral("/org/a11y/atspi/accessible/root"))})) {
            if (!name(appRef).contains(app, Qt::CaseInsensitive)) {
                continue;
            }
            // breadth-first over the widget tree: the editor is the text object holding the needle
            QList<AtspiRef> queue{appRef};
            for (int visited = 0; !queue.isEmpty() && visited < 3000; ++visited) {
                const AtspiRef r = queue.takeFirst();
                const QStringList ifaces = call(r, accessible, QStringLiteral("GetInterfaces")).toStringList();
                if (ifaces.contains(QStringLiteral("org.a11y.atspi.Text"))) {
                    const QString text = call(r, QStringLiteral("org.a11y.atspi.Text"), QStringLiteral("GetText"), {0, -1}).toString();
                    const int at = text.indexOf(needle);
                    if (at >= 0) {
                        return call(r, QStringLiteral("org.a11y.atspi.Text"), QStringLiteral("SetCaretOffset"), {at}).toBool();
                    }
                }
                queue += children(r);
            }
        }
        return false;
    }

    Q_INVOKABLE void trim()
    {
        const auto windows = QGuiApplication::allWindows();
        for (QWindow *w : windows) {
            if (auto *qw = qobject_cast<QQuickWindow *>(w)) {
                qw->setPersistentGraphics(false);
                qw->setPersistentSceneGraph(false);
                if (!qw->isVisible()) {
                    qw->releaseResources();
                }
            }
        }
        malloc_trim(0);
    }

    // Focus: hold a notification inhibition for as long as this process lives
    void inhibitNotifications(const QString &reason)
    {
        QDBusInterface notifications(QStringLiteral("org.freedesktop.Notifications"),
                                     QStringLiteral("/org/freedesktop/Notifications"),
                                     QStringLiteral("org.freedesktop.Notifications"));
        notifications.call(QStringLiteral("Inhibit"), QStringLiteral("typewriter"), reason, QVariantMap());
    }

    // Report key presses of physical keyboards (needs read access to their event devices)
    // Privacy indicator. Microphone: PipeWire's recording streams (pactl subscribe tells when they
    // change), not counting monitors of outputs and the volume meters of the shell itself.
    // Camera: which processes hold /dev/video* open, checked every 3 s while such devices exist.
    void watchRecording()
    {
        auto *debounce = new QTimer(this);
        debounce->setSingleShot(true);
        debounce->setInterval(250);
        connect(debounce, &QTimer::timeout, this, &Shell::checkMic);
        auto *pactl = new QProcess(this);
        connect(pactl, &QProcess::readyReadStandardOutput, this, [pactl, debounce] {
            if (pactl->readAllStandardOutput().contains("source-output")) {
                debounce->start();
            }
        });
        // PipeWire restarted: subscribe again
        connect(pactl, &QProcess::finished, this, [pactl] {
            QTimer::singleShot(5000, pactl, [pactl] { startSubscribe(pactl); });
        });
        startSubscribe(pactl);
        checkMic();

        auto *camera = new QTimer(this);
        connect(camera, &QTimer::timeout, this, &Shell::checkCamera);
        camera->start(3000);
    }

    // line-buffered: piped, pactl would keep its events in the stdio buffer
    static void startSubscribe(QProcess *pactl)
    {
        pactl->start(QStringLiteral("stdbuf"), {QStringLiteral("-oL"), QStringLiteral("pactl"), QStringLiteral("subscribe")});
    }

    void checkMic()
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            p->deleteLater();
            QStringList apps;
            const QJsonArray outputs = QJsonDocument::fromJson(p->readAllStandardOutput()).array();
            for (const QJsonValue &v : outputs) {
                const QJsonObject o = v.toObject();
                const QJsonObject props = o.value(QStringLiteral("properties")).toObject();
                const QString binary = props.value(QStringLiteral("application.process.binary")).toString();
                const QString target = props.value(QStringLiteral("target.object")).toString() + props.value(QStringLiteral("node.target")).toString();
                if (o.value(QStringLiteral("corked")).toBool() || target.endsWith(QLatin1String(".monitor"))
                    || props.value(QStringLiteral("stream.monitor")).toString() == QLatin1String("true")
                    || binary == QLatin1String("plasmashell") || binary == QLatin1String("tabletshell")
                    || binary == QLatin1String("pavucontrol")) {
                    continue;
                }
                const QString name = props.value(QStringLiteral("application.name")).toString(binary);
                if (!name.isEmpty() && !apps.contains(name)) {
                    apps << name;
                }
            }
            if (apps != m_micApps) {
                m_micApps = apps;
                Q_EMIT recordingChanged();
            }
        });
        p->start(QStringLiteral("pactl"), {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), QStringLiteral("source-outputs")});
    }

    void checkCamera()
    {
        // Hash lookups make every /proc/PID/fd check O(1), regardless of
        // the number of video devices or already discovered applications.
        QSet<QString> devices;
        for (const QFileInfo &dev : QDir(QStringLiteral("/dev")).entryInfoList({QStringLiteral("video*")}, QDir::System)) {
            devices.insert(dev.canonicalFilePath());
        }
        QStringList apps;
        QSet<QString> found;
        if (!devices.isEmpty()) {
            // processes with an open descriptor on a video device (pipewire itself only while a
            // client streams from it)
            for (const QFileInfo &proc : QDir(QStringLiteral("/proc")).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
                bool ok = false;
                proc.fileName().toInt(&ok);
                if (!ok) {
                    continue;
                }
                const QDir fds(proc.filePath() + QStringLiteral("/fd"));
                for (const QFileInfo &fd : fds.entryInfoList(QDir::System | QDir::NoDotAndDotDot)) {
                    if (devices.contains(fd.symLinkTarget())) {
                        QFile comm(proc.filePath() + QStringLiteral("/comm"));
                        const QString name = comm.open(QIODevice::ReadOnly) ? QString::fromUtf8(comm.readAll()).trimmed() : proc.fileName();
                        if (name != QLatin1String("wireplumber") && !found.contains(name)) {
                            found.insert(name);
                            apps << name;
                        }
                        break;
                    }
                }
            }
        }
        // /proc traversal order is not stable. Canonicalize before comparing
        // so merely reordered process entries do not redraw the privacy UI.
        std::sort(apps.begin(), apps.end());
        if (apps != m_cameraApps) {
            m_cameraApps = apps;
            Q_EMIT recordingChanged();
        }
    }

    void watchKeyboards()
    {
        const auto inputs = QDir(QStringLiteral("/sys/class/input")).entryList({QStringLiteral("event*")});
        for (const QString &ev : inputs) {
            const QString caps = readFile(QStringLiteral("/sys/class/input/%1/device/capabilities/key").arg(ev));
            const QString name = readFile(QStringLiteral("/sys/class/input/%1/device/name").arg(ev));
            // a real keyboard has the letter keys (KEY_A..KEY_Z live in the lowest 64-bit word)
            if (caps.isEmpty() || name.contains(QLatin1String("tabletshell"))) {
                continue;
            }
            const quint64 low = caps.split(QLatin1Char(' ')).last().toULongLong(nullptr, 16);
            if (!(low & (1ULL << KEY_A)) || !(low & (1ULL << KEY_Z))) {
                continue;
            }
            const int fd = open(QStringLiteral("/dev/input/%1").arg(ev).toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK);
            if (fd < 0) {
                continue;
            }
            auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
            connect(notifier, &QSocketNotifier::activated, this, [this, fd] {
                input_event ev;
                while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
                    if (ev.type == EV_KEY && ev.value == 1) {
                        Q_EMIT keyPressed(ev.code);
                    }
                }
            });
        }
    }

public Q_SLOTS:
    Q_SCRIPTABLE void ToggleControlCenter()
    {
        Q_EMIT toggleRequested();
    }

    Q_SCRIPTABLE void ToggleNotifications()
    {
        Q_EMIT notificationsRequested();
    }

    // Mode change animation (ModeTransition.qml): tablet|pc|dock|typewriter|coding|reading, empty = the
    // current device mode. Off with tabletrc [Modes] transitionAnimation=false, silent with
    // transitionSound=false.
    Q_SCRIPTABLE void ModeTransition(const QString &from, const QString &to)
    {
        const QSettings tabletrc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
        if (tabletrc.value(QStringLiteral("Modes/transitionAnimation"), true).toBool() && from != to) {
            Q_EMIT modeTransitionRequested(from, to, tabletrc.value(QStringLiteral("Modes/transitionSound"), true).toBool());
        }
    }

    // the new mode is in place (tabletd: panels reshaped): the animation may uncover the screen
    Q_SCRIPTABLE void ModeReady()
    {
        Q_EMIT modeReadyRequested();
    }

    Q_SCRIPTABLE void ToggleScreenTime()
    {
        flushScreenTime();
        Q_EMIT screenTimeRequested();
    }

    // Press a key combination like "ctrl+alt+r" or "f11" through the uinput keyboard
    Q_SCRIPTABLE void Key(const QString &combo)
    {
        static const QHash<QString, int> names = {
            {QStringLiteral("ctrl"), KEY_LEFTCTRL}, {QStringLiteral("alt"), KEY_LEFTALT},
            {QStringLiteral("shift"), KEY_LEFTSHIFT}, {QStringLiteral("meta"), KEY_LEFTMETA},
            {QStringLiteral("esc"), KEY_ESC}, {QStringLiteral("enter"), KEY_ENTER},
            {QStringLiteral("left"), KEY_LEFT}, {QStringLiteral("right"), KEY_RIGHT},
            {QStringLiteral("pageup"), KEY_PAGEUP}, {QStringLiteral("pagedown"), KEY_PAGEDOWN},
            {QStringLiteral("plus"), KEY_EQUAL}, {QStringLiteral("minus"), KEY_MINUS},
            {QStringLiteral("home"), KEY_HOME}, {QStringLiteral("end"), KEY_END},
            {QStringLiteral("up"), KEY_UP}, {QStringLiteral("down"), KEY_DOWN},
        };
        static const int letters[] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K,
                                      KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V,
                                      KEY_W, KEY_X, KEY_Y, KEY_Z};
        static const int fkeys[] = {KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
                                    KEY_F11, KEY_F12};
        QList<int> codes;
        for (const QString &part : combo.toLower().split(QLatin1Char('+'))) {
            if (names.contains(part)) {
                codes << names.value(part);
            } else if (part.size() == 1 && part[0] >= QLatin1Char('1') && part[0] <= QLatin1Char('9')) {
                codes << KEY_1 + (part[0].unicode() - '1');   // KEY_1..KEY_9 are consecutive
            } else if (part == QLatin1String("0")) {
                codes << KEY_0;
            } else if (part.size() == 1 && part[0] >= QLatin1Char('a') && part[0] <= QLatin1Char('z')) {
                codes << letters[part[0].unicode() - 'a'];
            } else if (part.startsWith(QLatin1Char('f')) && part.mid(1).toInt() >= 1 && part.mid(1).toInt() <= 12) {
                codes << fkeys[part.mid(1).toInt() - 1];
            } else {
                return;
            }
        }
        if (codes.isEmpty() || !ensureUinput()) {
            return;
        }
        for (int c : std::as_const(codes)) {
            emitKey(c, 1);
        }
        for (auto it = codes.crbegin(); it != codes.crend(); ++it) {
            emitKey(*it, 0);
        }
    }

    // Android on demand: the tablet-gestures KWin script reports how many Waydroid windows are
    // open. With none for tabletrc [Android] autoStopMinutes (default 10; 0 = never) the Waydroid
    // session is stopped, which gives back about 1 GB; an Android app starts it again.
    Q_SCRIPTABLE void WaydroidWindows(int count)
    {
        m_waydroidWindows = count;
        if (count > 0) {
            m_waydroidIdle = 0;
        }
    }
    Q_SCRIPTABLE void WaydroidWindows(double count)
    {
        WaydroidWindows(int(count));
    }
    void startAndroidWatch()
    {
        auto *timer = new QTimer(this);
        connect(timer, &QTimer::timeout, this, [this] {
            const QSettings rc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
            const int minutes = rc.value(QStringLiteral("Android/autoStopMinutes"), 10).toInt();
            if (minutes <= 0 || m_waydroidWindows > 0) {
                m_waydroidIdle = 0;
                return;
            }
            // the process running the session (often `waydroid app launch` itself) owns this name
            if (!QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("id.waydro.Session"))) {
                m_waydroidIdle = 0;     // no session running
                return;
            }
            if (++m_waydroidIdle >= minutes) {
                m_waydroidIdle = 0;
                QProcess::startDetached(QStringLiteral("waydroid"), {QStringLiteral("session"), QStringLiteral("stop")});
                QProcess::startDetached(QStringLiteral("notify-send"),
                                        {QStringLiteral("-a"), QStringLiteral("Android"), QStringLiteral("-i"), QStringLiteral("waydroid"),
                                         T(QStringLiteral("Android остановлен")),
                                         T(QStringLiteral("Не использовался %1 мин — память освобождена. Запустится сам при открытии приложения.")).arg(minutes)});
            }
        });
        timer->start(60 * 1000);
    }

    // Screen time: KWin reports the active window's app id; time is summed per app per day
    Q_SCRIPTABLE void WindowActivated(const QString &appId)
    {
        flushScreenTime();
        m_currentApp = appId;
    }

    // the app in front, as last reported by KWin (used by the typewriter pill, which runs in
    // another process)
    Q_SCRIPTABLE QString CurrentApp() const
    {
        return m_currentApp;
    }

    Q_SCRIPTABLE void ScreenLocked(bool locked)
    {
        flushScreenTime();
        if (m_locked && !locked && effect("unlockSound")) {
            Q_EMIT unlocked();
        } else if (!m_locked && locked && effect("lockSound")) {
            Q_EMIT lockedNow();
        }
        m_locked = locked;
    }

    // Pen button held in the air (tabletd): the tool ring (PenRing.qml) where the pen is, as
    // fractions of the screen
    Q_SCRIPTABLE void PenRing(double x, double y)
    {
        Q_EMIT penRingRequested(x, y);
    }

    // Colour under the next tap (KWin's picker); the result goes to the clipboard (Klipper) and
    // to colorPicked as #rrggbb
    Q_INVOKABLE void pickColor()
    {
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                QStringLiteral("org.kde.KWin"), QStringLiteral("/ColorPicker"), QStringLiteral("org.kde.kwin.ColorPicker"), QStringLiteral("pick")),
                120000),
            this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            watcher->deleteLater();
            const QDBusMessage reply = watcher->reply();
            if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
                return;
            }
            // (u) = a struct holding the ARGB value
            uint argb = 0;
            const QDBusArgument arg = reply.arguments().first().value<QDBusArgument>();
            arg.beginStructure();
            arg >> argb;
            arg.endStructure();
            const QString hex = QStringLiteral("#%1").arg(argb & 0xffffff, 6, 16, QLatin1Char('0'));
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                QStringLiteral("org.kde.klipper"), QStringLiteral("/klipper"), QStringLiteral("org.kde.klipper.klipper"),
                QStringLiteral("setClipboardContents")) << hex);
            Q_EMIT colorPicked(hex);
        });
    }

    // Held power button (tabletd): the power menu (PowerMenu.qml)
    Q_SCRIPTABLE void PowerMenu()
    {
        Q_EMIT powerMenuRequested();
    }

    // Charger plugged in: the charging animation (ChargeAnimation.qml); also for testing
    Q_SCRIPTABLE void ShowCharging()
    {
        if (effect("chargeAnimation")) {
            Q_EMIT chargingStarted();
        }
    }

    // Press the hardware "Back" key (browser back, Android back) through a uinput keyboard
    Q_SCRIPTABLE void Back()
    {
        if (!ensureUinput()) {
            return;
        }
        emitKey(KEY_BACK, 1);
        emitKey(KEY_BACK, 0);
    }

    bool tabletMode() const
    {
        return m_tabletMode;
    }
    void watchTabletMode()
    {
        auto bus = QDBusConnection::sessionBus();
        bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"), QStringLiteral("org.kde.KWin.TabletModeManager"),
                    QStringLiteral("tabletModeChanged"), this, SLOT(onTabletModeChanged(bool)));
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"), QStringLiteral("org.freedesktop.DBus.Properties"));
        const QDBusReply<QDBusVariant> r = kwin.call(QStringLiteral("Get"), QStringLiteral("org.kde.KWin.TabletModeManager"), QStringLiteral("tabletMode"));
        if (r.isValid()) {
            onTabletModeChanged(r.value().variant().toBool());
        }
    }
    // UPower OnBattery true -> false = the charger was plugged in
    void watchPower()
    {
        QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.UPower"), QStringLiteral("/org/freedesktop/UPower"),
                                             QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"),
                                             this, SLOT(onUPowerChanged(QString, QVariantMap, QStringList)));
    }

    // tabletrc [Effects]: charging animation, lock/unlock sounds (on unless switched off)
    static bool effect(const char *key)
    {
        const QSettings tabletrc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
        return tabletrc.value(QStringLiteral("Effects/") + QLatin1String(key), true).toBool();
    }

    // Settings: Жесты -> "Назад" (kwinrc [Script-tablet-gestures] leftEdge), read at each touch
    Q_INVOKABLE bool backGestureEnabled() const
    {
        const QSettings kwinrc(QDir::homePath() + QStringLiteral("/.config/kwinrc"), QSettings::IniFormat);
        return kwinrc.value(QStringLiteral("Script-tablet-gestures/leftEdge"), true).toBool();
    }

public Q_SLOTS:
    void onUPowerChanged(const QString &, const QVariantMap &changed, const QStringList &)
    {
        const auto it = changed.find(QStringLiteral("OnBattery"));
        if (it != changed.end() && !it->toBool()) {
            ShowCharging();
        }
    }

    void onTabletModeChanged(bool tablet)
    {
        if (tablet != m_tabletMode) {
            m_tabletMode = tablet;
            Q_EMIT tabletModeChanged();
        }
    }

Q_SIGNALS:
    void tabletModeChanged();
    void toggleRequested();
    void notificationsRequested();
    void screenTimeRequested();
    void modeTransitionRequested(const QString &from, const QString &to, bool sound);
    void modeReadyRequested();
    void chargingStarted();
    void powerMenuRequested();
    void penRingRequested(double x, double y);
    void colorPicked(const QString &hex);
    void recordingChanged();
    void unlocked();
    void lockedNow();
    void keyPressed(int code);

public:
    void startScreenTime()
    {
        m_counting.start();
        auto *timer = new QTimer(this);
        connect(timer, &QTimer::timeout, this, &Shell::flushScreenTime);
        timer->start(60000);
        QDBusConnection::sessionBus().connect(QStringLiteral("org.freedesktop.ScreenSaver"),
                                              QStringLiteral("/ScreenSaver"),
                                              QStringLiteral("org.freedesktop.ScreenSaver"),
                                              QStringLiteral("ActiveChanged"), this, SLOT(ScreenLocked(bool)));
    }

    void flushScreenTime()
    {
        if (!m_counting.isValid()) {
            return;
        }
        const qint64 secs = m_counting.restart() / 1000;
        if (secs <= 0 || m_locked || m_currentApp.isEmpty()) {
            return;
        }
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/screentime");
        QDir().mkpath(dir);
        QFile f(dir + QLatin1Char('/') + QDate::currentDate().toString(Qt::ISODate) + QStringLiteral(".json"));
        QJsonObject day;
        if (f.open(QIODevice::ReadOnly)) {
            day = QJsonDocument::fromJson(f.readAll()).object();
            f.close();
        }
        day[m_currentApp] = day.value(m_currentApp).toInteger() + qMin<qint64>(secs, 3600);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write(QJsonDocument(day).toJson(QJsonDocument::Compact));
        }
    }

private:
    bool ensureUinput()
    {
        if (m_uinput >= 0) {
            return true;
        }
        m_uinput = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
        if (m_uinput < 0) {
            return false;
        }
        ioctl(m_uinput, UI_SET_EVBIT, EV_KEY);
        for (int code = KEY_ESC; code <= KEY_F12; ++code) {   // main keyboard block
            ioctl(m_uinput, UI_SET_KEYBIT, code);
        }
        for (int code : {KEY_BACK, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_LEFTMETA, KEY_HOME, KEY_END}) {
            ioctl(m_uinput, UI_SET_KEYBIT, code);
        }
        uinput_setup setup{};
        setup.id.bustype = BUS_VIRTUAL;
        strncpy(setup.name, "tabletshell virtual keys", UINPUT_MAX_NAME_SIZE - 1);
        ioctl(m_uinput, UI_DEV_SETUP, &setup);
        ioctl(m_uinput, UI_DEV_CREATE);
        usleep(300000); // let the compositor pick up the new device before the first key
        return true;
    }

    void emitKey(int code, int value)
    {
        input_event ev{};
        ev.type = EV_KEY;
        ev.code = code;
        ev.value = value;
        write(m_uinput, &ev, sizeof(ev));
        input_event syn{};
        syn.type = EV_SYN;
        syn.code = SYN_REPORT;
        write(m_uinput, &syn, sizeof(syn));
    }

    int m_uinput = -1;
    QElapsedTimer m_counting;
    bool m_tabletMode = false;
    QStringList m_micApps;
    QStringList m_cameraApps;
    int m_waydroidWindows = 0;
    int m_waydroidIdle = 0;      // minutes without a Waydroid window while the session runs
    QString m_currentApp;
    bool m_locked = false;
};

int main(int argc, char *argv[])
{
    // Keep Qt diagnostics silent without an app-local helper declaration.
    // TABLET_SHELL_DEBUG=1 keeps Qt/QML messages for troubleshooting
    if (!qEnvironmentVariableIsSet("TABLET_SHELL_DEBUG")) qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    const QString mode = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("control");
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");
    QGuiApplication app(argc, argv);
    app.setDesktopFileName(QStringLiteral("tabletshell"));

    Shell shell;
    if (mode == QLatin1String("control")) {
        auto bus = QDBusConnection::sessionBus();
        if (!bus.registerService(QStringLiteral("org.ipad.TabletShell"))) {
            return 0;
        }
        bus.registerObject(QStringLiteral("/"), &shell, QDBusConnection::ExportScriptableSlots);
        shell.startScreenTime();
        shell.startAndroidWatch();
        shell.watchTabletMode();
        shell.watchPower();
        shell.watchRecording();
        QObject::connect(&app, &QCoreApplication::aboutToQuit, &shell, &Shell::flushScreenTime);
    } else if (mode == QLatin1String("codingfocus")) {
        // Hold notification inhibition using a persistent DBus owner. It ends when
        // coding-mode kills this process; no user-wide DND flag is modified.
        shell.inhibitNotifications(T(QStringLiteral("Режим кодинга: фокус")));
        return app.exec();
    } else if (mode == QLatin1String("pill")) {
        if (qEnvironmentVariable("TYPEWRITER_FOCUS", QStringLiteral("true")) != QLatin1String("false")) {
            shell.inhibitNotifications(T(QStringLiteral("Печатная машинка: фокус")));
        }
        shell.watchKeyboards();
    }

    QQmlApplicationEngine engine;
    UiStyle uiStyle;
    engine.rootContext()->setContextProperty(QStringLiteral("uiStyle"), &uiStyle);
    engine.rootContext()->setContextProperty(QStringLiteral("shell"), &shell);
    engine.load(QUrl::fromLocalFile(QStringLiteral(SHELL_DIR "/") + mode + QStringLiteral(".qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    return app.exec();
}

#include "main.moc"
