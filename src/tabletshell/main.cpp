// tabletshell: small always-on-top tablet UI pieces drawn on the layer-shell overlay layer.
//   tabletshell control   control center (D-Bus org.ipad.TabletShell: ToggleControlCenter, Back,
//                         ModeTransition/ModeReady = mode change animation, ShowCharging = charging
//                         animation, PowerMenu, PenRing; it also plays the lock/unlock sounds;
//                         a long press on text shows the phone-style text menu)
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
#include <QDBusUnixFileDescriptor>
#include <QImage>
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
#include <QLineF>
#include <QScreen>

#include <KWindowEffects>

#include <malloc.h>

#include <fcntl.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <algorithm>
#include <functional>

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

    // Our own volume / brightness indicator (Osd.qml). Plasma keeps receiving the org.kde.osdService
    // calls from plasma-pa, PowerDevil, the layout switcher...; we listen to them with dbus-monitor
    // and draw the bars ourselves, Plasma's own OSD is switched off (plasmarc [OSD] Enabled).
    // tabletrc [Effects] osd=false gives Plasma's back.
    void watchOsd()
    {
        const bool own = effect("osd");
        QProcess::startDetached(QStringLiteral("kwriteconfig6"), {QStringLiteral("--file"), QStringLiteral("plasmarc"), QStringLiteral("--group"),
                                                                   QStringLiteral("OSD"), QStringLiteral("--key"), QStringLiteral("Enabled"),
                                                                   QStringLiteral("--type"), QStringLiteral("bool"),
                                                                   own ? QStringLiteral("false") : QStringLiteral("true")});
        if (!own) {
            return;
        }
        // a call's arguments follow its header line; the last call has nothing after it, so it is
        // sent when the output pauses
        auto *flush = new QTimer(this);
        flush->setSingleShot(true);
        flush->setInterval(15);
        connect(flush, &QTimer::timeout, this, &Shell::emitOsd);
        auto *monitor = new QProcess(this);
        connect(monitor, &QProcess::readyReadStandardOutput, this, [this, monitor, flush] {
            while (monitor->canReadLine()) {
                const QString line = QString::fromUtf8(monitor->readLine()).trimmed();
                if (line.startsWith(QLatin1String("method call ")) || line.startsWith(QLatin1String("signal "))) {
                    emitOsd();
                    const int at = line.indexOf(QLatin1String("member="));
                    m_osdMember = line.startsWith(QLatin1String("method call ")) && at >= 0 ? line.mid(at + 7) : QString();
                } else if (!m_osdMember.isEmpty()) {
                    const int space = line.indexOf(QLatin1Char(' '));
                    const QStringView type = QStringView(line).left(space);
                    const QString value = line.mid(space + 1);
                    if (type == QLatin1String("string")) {
                        m_osdArgs << value.mid(1, value.size() - 2);
                    } else if (type == QLatin1String("int32") || type == QLatin1String("boolean") || type == QLatin1String("double")) {
                        m_osdArgs << value;
                    }
                }
            }
            flush->start();
        });
        connect(monitor, &QProcess::finished, this, [monitor] {
            QTimer::singleShot(5000, monitor, [monitor] { startOsdMonitor(monitor); });
        });
        startOsdMonitor(monitor);
    }

    static void startOsdMonitor(QProcess *monitor)
    {
        monitor->start(QStringLiteral("stdbuf"), {QStringLiteral("-oL"), QStringLiteral("dbus-monitor"), QStringLiteral("--session"),
                                                 QStringLiteral("type='method_call',interface='org.kde.osdService'")});
    }

    void emitOsd()
    {
        if (!m_osdMember.isEmpty()) {
            Q_EMIT osdRequested(m_osdMember, m_osdArgs);
        }
        m_osdMember.clear();
        m_osdArgs.clear();
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

    // Text menu like on a phone (TextMenu.qml): hold a finger on a text field, or select text with a
    // held finger, and Cut / Copy / Paste / Select all appear where the finger was lifted. The touch
    // screen is only read (KWin still gets every touch); it needs the uaccess rule of
    // system/devices.sh. A text field = KWin says the active window takes text input
    // (/VirtualKeyboard); a selection = the primary selection changed during the touch.
    // Off with tabletrc [Effects] textMenu=false.
    void watchTouch()
    {
        for (const QString &ev : QDir(QStringLiteral("/sys/class/input")).entryList({QStringLiteral("event*")})) {
            const QString dev = QStringLiteral("/sys/class/input/%1/device/").arg(ev);
            const quint64 props = readFile(dev + QStringLiteral("properties")).toULongLong(nullptr, 16);
            const quint64 abs = readFile(dev + QStringLiteral("capabilities/abs")).split(QLatin1Char(' ')).last().toULongLong(nullptr, 16);
            // a touch screen: direct input with multi-touch positions (the pen has no MT axes)
            if (!(props & (1ULL << INPUT_PROP_DIRECT)) || !(abs & (1ULL << ABS_MT_POSITION_X))) {
                continue;
            }
            m_touchFd = open(QStringLiteral("/dev/input/%1").arg(ev).toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK);
            if (m_touchFd < 0) {
                continue;   // no access yet (system/devices.sh not run)
            }
            ioctl(m_touchFd, EVIOCGABS(ABS_MT_POSITION_X), &m_touchX);
            ioctl(m_touchFd, EVIOCGABS(ABS_MT_POSITION_Y), &m_touchY);
            break;
        }
        if (m_touchFd < 0) {
            return;
        }
        createVirtualTouch();
        m_holdTimer = new QTimer(this);
        m_holdTimer->setSingleShot(true);
        m_holdTimer->setInterval(500);
        connect(m_holdTimer, &QTimer::timeout, this, [this] { m_held = true; });
        auto *notifier = new QSocketNotifier(m_touchFd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this] {
            input_event ev;
            while (read(m_touchFd, &ev, sizeof(ev)) == sizeof(ev)) {
                if (ev.type == EV_ABS && ev.code == ABS_MT_SLOT) {
                    m_slot = qBound(0, ev.value, kTouchSlots - 1);
                } else if (ev.type == EV_ABS && ev.code == ABS_MT_TRACKING_ID) {
                    m_contacts[m_slot].id = ev.value;
                } else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_X) {
                    m_contacts[m_slot].x = ev.value;
                } else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y) {
                    m_contacts[m_slot].y = ev.value;
                } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
                    touchFrame();
                }
            }
        });
        // the primary selection changes whenever text gets selected (text only: no image transfers)
        auto *primary = new QProcess(this);
        connect(primary, &QProcess::readyReadStandardOutput, this, [this, primary] {
            m_primaryChanges += primary->readAllStandardOutput().count('\n');
        });
        connect(primary, &QProcess::finished, this, [primary] {
            QTimer::singleShot(5000, primary, [primary] { startPrimaryWatch(primary); });
        });
        startPrimaryWatch(primary);
        // touches come in the panel's own orientation; follow the screen's rotation
        auto watchScreen = [this](QScreen *s) {
            connect(s, &QScreen::geometryChanged, this, &Shell::readRotation);
        };
        for (QScreen *s : QGuiApplication::screens()) {
            watchScreen(s);
        }
        connect(qApp, &QGuiApplication::screenAdded, this, watchScreen);
        readRotation();
    }

    static void startPrimaryWatch(QProcess *p)
    {
        p->start(QStringLiteral("wl-paste"), {QStringLiteral("--primary"), QStringLiteral("--type"), QStringLiteral("text"),
                                             QStringLiteral("--watch"), QStringLiteral("echo")});
    }

    // KScreen rotation of the built-in screen (1 none, 2 left, 4 inverted, 8 right)
    void readRotation()
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            p->deleteLater();
            const QJsonArray outputs = QJsonDocument::fromJson(p->readAllStandardOutput()).object().value(QStringLiteral("outputs")).toArray();
            for (const QJsonValue &v : outputs) {
                const QJsonObject o = v.toObject();
                const QString name = o.value(QStringLiteral("name")).toString();
                if (name.startsWith(QLatin1String("eDP")) || name.startsWith(QLatin1String("LVDS")) || name.startsWith(QLatin1String("DSI"))) {
                    m_rotation = o.value(QStringLiteral("rotation")).toInt(1);
                }
            }
        });
        p->start(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")});
    }

    // where a contact is, as fractions of the (rotated) built-in screen
    QPointF touchPoint(int slot) const
    {
        const double rx = double(m_contacts[slot].x - m_touchX.minimum) / qMax(1, m_touchX.maximum - m_touchX.minimum);
        const double ry = double(m_contacts[slot].y - m_touchY.minimum) / qMax(1, m_touchY.maximum - m_touchY.minimum);
        switch (m_rotation) {
        case 2: return {1 - ry, rx};
        case 4: return {1 - rx, 1 - ry};
        case 8: return {ry, 1 - rx};
        default: return {rx, ry};
        }
    }

    // one complete touch frame: a single finger held still for 500 ms makes a long press (after
    // that it may move: dragging selects text); it counts when the finger is lifted
    void touchFrame()
    {
        int down = 0;
        int first = -1;
        for (int i = 0; i < kTouchSlots; ++i) {
            if (m_contacts[i].id >= 0) {
                ++down;
                if (first < 0) {
                    first = i;
                }
            }
        }
        if (m_dragHandle) {
            handleDragFrame(down, first);
            return;
        }
        if (!m_touching) {
            if (down == 0) {
                return;
            }
            const QPointF at = touchPoint(first);
            const int handle = down == 1 ? handleAt(at) : 0;
            if (handle) {
                beginHandleDrag(handle, at);
                return;
            }
            m_touching = true;
            m_held = false;
            m_cancelled = down > 1;
            m_touchSlot = first;
            m_touchStart = m_touchLast = touchPoint(first);
            m_primaryAtDown = m_primaryChanges;
            Q_EMIT touchStarted(m_touchStart.x(), m_touchStart.y());
            if (!m_cancelled) {
                m_holdTimer->start();
            }
            return;
        }
        if (down == 0) {
            m_touching = false;
            m_holdTimer->stop();
            if (m_held && !m_cancelled) {
                // let the app take focus / finish its selection first
                QTimer::singleShot(150, this, [this, at = m_touchLast] { offerTextMenu(at); });
            }
            return;
        }
        if (down > 1) {
            m_cancelled = true;   // pinch, two-finger scroll
            m_holdTimer->stop();
            return;
        }
        if (m_contacts[m_touchSlot].id >= 0) {
            m_touchLast = touchPoint(m_touchSlot);
        }
        if (!m_held && QLineF(m_touchStart, m_touchLast).length() > 0.015) {
            m_cancelled = true;   // a swipe or scroll
            m_holdTimer->stop();
        }
    }

    // apps that bring their own long-press text menu: browsers, Electron, GTK, Kirigami (Qt Quick
    // Controls show MobileTextActionsToolBar in tablet mode), Android; plus tabletrc [TextMenu] skip
    bool ownTextMenu(const QString &app) const
    {
        const QSettings tabletrc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
        const QStringList skip = tabletrc.value(QStringLiteral("TextMenu/skip"),
            QStringList{QStringLiteral("firefox"), QStringLiteral("chromium"), QStringLiteral("chrome"), QStringLiteral("brave"),
                        QStringLiteral("waydroid"), QStringLiteral("claude"), QStringLiteral("org.kde.plasmashell")}).toStringList();
        for (const QString &s : skip) {
            if (!s.isEmpty() && app.contains(s, Qt::CaseInsensitive)) {
                return true;
            }
        }
        QFile maps(QStringLiteral("/proc/%1/maps").arg(m_windowPid));
        if (!maps.open(QIODevice::ReadOnly)) {
            return true;   // not ours to look at (another user, gone): stay out of the way
        }
        const QByteArray libs = maps.readAll();
        for (const char *lib : {"libKirigami", "libgtk-3", "libgtk-4", "libxul", "libcef", "libQt6WebEngineCore", "libelectron"}) {
            if (libs.contains(lib)) {
                return true;
            }
        }
        return false;
    }

    void offerTextMenu(QPointF at)
    {
        // the home screen counts as no app for screen time, but its search bar is a text field
        const QString app = m_windowHome ? QStringLiteral("plasmashell") : m_currentApp;
        if (m_locked || !effect("textMenu") || app.isEmpty()) {
            return;
        }
        // panels, the dock and our own overlays lie outside the active window; the home screen's
        // search bar is a bare TextInput without a menu of its own
        if (m_windowPid <= 0 || !m_windowArea.contains(at) || (!m_windowHome && ownTextMenu(app))) {
            return;
        }
        const bool selected = m_primaryChanges != m_primaryAtDown;
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualKeyboard"), QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("GetAll")) << QStringLiteral("org.kde.kwin.VirtualKeyboard")),
            this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, at, selected, app] {
            watcher->deleteLater();
            const QDBusReply<QVariantMap> reply = *watcher;
            const QVariantMap vk = reply.isValid() ? reply.value() : QVariantMap();
            const bool editable = vk.value(QStringLiteral("activeClientSupportsTextInput")).toBool();
            if (!editable && !selected) {
                return;
            }
            // a long press on the on-screen keyboard (its own alternates) is not for us
            if (vk.value(QStringLiteral("visible")).toBool()) {
                const QSettings kb(QDir::homePath() + QStringLiteral("/.config/tablet-keyboardrc"), QSettings::IniFormat);
                const bool portrait = m_rotation == 2 || m_rotation == 8;
                const double share = portrait ? kb.value(QStringLiteral("General/heightPortrait"), 26).toDouble()
                                              : kb.value(QStringLiteral("General/height"), 40).toDouble();
                if (at.y() > 1 - share / 100) {
                    return;
                }
            }
            // Paste only with something on the clipboard (types only: no data is transferred)
            auto *types = new QProcess(this);
            connect(types, &QProcess::finished, this, [this, types, at, editable, selected, app] {
                types->deleteLater();
                const bool canPaste = !types->readAllStandardOutput().trimmed().isEmpty();
                if (selected) {
                    // selected with the held finger: the handles go where the finger began and ended
                    QPointF a = m_touchStart, b = at;
                    if (b.y() < a.y() - 0.01 || (qAbs(b.y() - a.y()) <= 0.01 && b.x() < a.x())) {
                        std::swap(a, b);
                    }
                    Q_EMIT textMenuRequested(at.x(), at.y(), editable, true, canPaste, app, selection(a, b, 0.028));
                } else if (editable && effect("textSelect")) {
                    selectWordAt(at, canPaste, app);
                } else {
                    Q_EMIT textMenuRequested(at.x(), at.y(), editable, false, canPaste, app, {});
                }
            });
            types->start(QStringLiteral("wl-paste"), {QStringLiteral("--list-types")});
        });
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

    // The active window for the text menu (tablet-gestures KWin script): "pid x y width height",
    // the rectangle as fractions of the built-in screen; pid 0 = no app window in front; a sixth
    // field "home" = the home screen (Plasma's desktop window, without the panels)
    Q_SCRIPTABLE void WindowArea(const QString &area)
    {
        const QStringList v = area.split(QLatin1Char(' '));
        if (v.size() >= 5) {
            m_windowPid = v[0].toLongLong();
            m_windowArea = QRectF(v[1].toDouble(), v[2].toDouble(), v[3].toDouble(), v[4].toDouble());
            m_windowHome = v.value(5) == QLatin1String("home");
        }
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

    // The text menu at x, y (fractions of the built-in screen) with every button, for testing
    Q_SCRIPTABLE void ShowTextMenu(double x, double y)
    {
        Q_EMIT textMenuRequested(x, y, true, true, true, QString(), selection({x - 0.05, y}, {x + 0.05, y}, 0.028));
    }

    // A finger on the touch screen for testing the text menu without one: phase 0 down, 1 moved,
    // 2 lifted, at x, y (fractions of the screen). Only the menu sees it, not the app.
    Q_SCRIPTABLE void TestTouch(int phase, double x, double y)
    {
        if (!m_holdTimer) {
            return;   // no touch screen
        }
        double rx = x, ry = y;
        switch (m_rotation) {
        case 2: rx = y; ry = 1 - x; break;
        case 4: rx = 1 - x; ry = 1 - y; break;
        case 8: rx = 1 - y; ry = x; break;
        default: break;
        }
        m_contacts[0].id = phase == 2 ? -1 : 0xbeef;
        m_contacts[0].x = m_touchX.minimum + qRound(rx * (m_touchX.maximum - m_touchX.minimum));
        m_contacts[0].y = m_touchY.minimum + qRound(ry * (m_touchY.maximum - m_touchY.minimum));
        touchFrame();
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
        // waking up reports the charger again: no animation for that (see onUPowerChanged)
        QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                             QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("PrepareForSleep"),
                                             this, SLOT(onPrepareForSleep(bool)));
        m_woke.start();   // the session just started (power on): the same
    }

    // the screen is dark: backlight powered down or at zero (DPMS off, the tablet asleep)
    static bool screenOff()
    {
        const QDir backlights(QStringLiteral("/sys/class/backlight"));
        for (const QString &b : backlights.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            QFile power(backlights.filePath(b + QStringLiteral("/bl_power")));
            QFile level(backlights.filePath(b + QStringLiteral("/actual_brightness")));
            if (power.open(QIODevice::ReadOnly) && power.readAll().trimmed() != "0") {
                return true;
            }
            if (level.open(QIODevice::ReadOnly) && level.readAll().trimmed() == "0") {
                return true;
            }
        }
        return false;
    }

    // tabletrc [Effects]: charging animation, lock/unlock sounds (on unless switched off)
    static bool effect(const char *key)
    {
        const QSettings tabletrc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
        return tabletrc.value(QStringLiteral("Effects/") + QLatin1String(key), true).toBool();
    }

    // tabletrc [Effects] KEY for QML, read at each call (Osd.qml: osdPercent)
    Q_INVOKABLE bool effectOn(const QString &key, bool fallback) const
    {
        const QSettings tabletrc(QDir::homePath() + QStringLiteral("/.config/tabletrc"), QSettings::IniFormat);
        return tabletrc.value(QStringLiteral("Effects/") + key, fallback).toBool();
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
        // Only a charger plugged in while someone looks at the screen gets the animation: not
        // while it is off or locked, and not for the charger that was already in when the tablet
        // was switched on or woke up (that one is reported again then)
        if (it != changed.end() && !it->toBool() && !m_locked && !screenOff()
            && (!m_woke.isValid() || m_woke.elapsed() > 15000)) {
            ShowCharging();
        }
    }

    void onPrepareForSleep(bool sleeping)
    {
        if (!sleeping) {
            m_woke.start();
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
    // org.kde.osdService call (volumeChanged, screenBrightnessChanged, showText...) and its arguments
    void osdRequested(const QString &member, const QStringList &args);
    // touch screen (watchTouch): a finger went down / a long press for the text menu, as fractions
    // of the built-in screen
    void touchStarted(double x, double y);
    // sel: the selected text's ends for the handles (sx, sy, ex, ey, lineHeight, fractions; the
    // ends are on the middle of their line), empty = no handles
    void textMenuRequested(double x, double y, bool editable, bool selected, bool canPaste, const QString &app, const QVariantMap &sel);
    // a selection handle is being dragged (the handles and the menu step aside) / was let go
    void handleDragStarted();
    void handleDragMoved(int handle, double x, double y);
    void handleDragFinished(int handle, double x, double y);

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


    // ---- text selection --------------------------------------------------------------------
    // The app selects for us: a double tap on a word, Shift + touch to move an end. The taps come
    // from a virtual touch screen with the real one's ranges, so KWin maps them the same way.

    void createVirtualTouch()
    {
        m_vtouchFd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
        if (m_vtouchFd < 0) {
            return;
        }
        ioctl(m_vtouchFd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);
        ioctl(m_vtouchFd, UI_SET_EVBIT, EV_KEY);
        ioctl(m_vtouchFd, UI_SET_KEYBIT, BTN_TOUCH);
        ioctl(m_vtouchFd, UI_SET_EVBIT, EV_ABS);
        uinput_setup setup{};
        setup.id.bustype = BUS_VIRTUAL;
        strncpy(setup.name, "tabletshell virtual touch", UINPUT_MAX_NAME_SIZE - 1);
        ioctl(m_vtouchFd, UI_DEV_SETUP, &setup);
        const std::pair<int, input_absinfo> axes[] = {
            {ABS_X, m_touchX}, {ABS_Y, m_touchY}, {ABS_MT_POSITION_X, m_touchX}, {ABS_MT_POSITION_Y, m_touchY},
            {ABS_MT_SLOT, input_absinfo{0, 0, 0, 0, 0, 0}}, {ABS_MT_TRACKING_ID, input_absinfo{0, 0, 65535, 0, 0, 0}},
        };
        for (const auto &[code, info] : axes) {
            ioctl(m_vtouchFd, UI_SET_ABSBIT, code);
            uinput_abs_setup abs{};
            abs.code = code;
            abs.absinfo = info;
            abs.absinfo.value = 0;
            ioctl(m_vtouchFd, UI_ABS_SETUP, &abs);
        }
        ioctl(m_vtouchFd, UI_DEV_CREATE);
    }

    void vEvent(int type, int code, int value)
    {
        input_event ev{};
        ev.type = type;
        ev.code = code;
        ev.value = value;
        write(m_vtouchFd, &ev, sizeof(ev));
    }

    // 0 = finger down, 1 = moved, 2 = lifted, at a point given as fractions of the screen
    void vTouch(int phase, QPointF at)
    {
        if (m_vtouchFd < 0) {
            return;
        }
        // back into the panel's own orientation (touchPoint the other way round)
        double rx = at.x(), ry = at.y();
        switch (m_rotation) {
        case 2: rx = at.y(); ry = 1 - at.x(); break;
        case 4: rx = 1 - at.x(); ry = 1 - at.y(); break;
        case 8: rx = 1 - at.y(); ry = at.x(); break;
        default: break;
        }
        const int x = m_touchX.minimum + qRound(qBound(0.0, rx, 1.0) * (m_touchX.maximum - m_touchX.minimum));
        const int y = m_touchY.minimum + qRound(qBound(0.0, ry, 1.0) * (m_touchY.maximum - m_touchY.minimum));
        vEvent(EV_ABS, ABS_MT_SLOT, 0);
        if (phase == 2) {
            vEvent(EV_ABS, ABS_MT_TRACKING_ID, -1);
            vEvent(EV_KEY, BTN_TOUCH, 0);
        } else {
            if (phase == 0) {
                vEvent(EV_ABS, ABS_MT_TRACKING_ID, m_vtrack++ & 0xffff);
            }
            vEvent(EV_ABS, ABS_MT_POSITION_X, x);
            vEvent(EV_ABS, ABS_MT_POSITION_Y, y);
            if (phase == 0) {
                vEvent(EV_KEY, BTN_TOUCH, 1);
            }
            vEvent(EV_ABS, ABS_X, x);
            vEvent(EV_ABS, ABS_Y, y);
        }
        vEvent(EV_SYN, SYN_REPORT, 0);
    }

    // timed input: each step runs `ms` after the one before
    void steps(QList<std::pair<int, std::function<void()>>> list)
    {
        int at = 0;
        for (auto &[ms, fn] : list) {
            at += ms;
            QTimer::singleShot(at, this, fn);
        }
    }

    static QVariantMap selection(QPointF a, QPointF b, double lineHeight)
    {
        return {{QStringLiteral("sx"), a.x()}, {QStringLiteral("sy"), a.y()}, {QStringLiteral("ex"), b.x()},
                {QStringLiteral("ey"), b.y()}, {QStringLiteral("lh"), lineHeight}};
    }

    // A strip of the screen through KWin (org.kde.KWin.ScreenShot2, allowed for us by
    // tabletshell.desktop); a null image when it is not to be had
    void capture(const QRectF &frac, std::function<void(QImage)> done)
    {
        QScreen *scr = builtInScreen();
        if (!scr) {
            done({});
            return;
        }
        const QRect g = scr->geometry();
        const QRect area = QRect(g.x() + qRound(frac.x() * g.width()), g.y() + qRound(frac.y() * g.height()),
                                 qRound(frac.width() * g.width()), qRound(frac.height() * g.height())).intersected(g);
        int fds[2];
        if (area.isEmpty() || pipe2(fds, O_CLOEXEC) != 0) {
            done({});
            return;
        }
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                           QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("CaptureArea"));
        call << area.x() << area.y() << uint(area.width()) << uint(area.height())
             << QVariantMap{{QStringLiteral("native-resolution"), false}} << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        close(fds[1]);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 3000), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, fd = fds[0], done] {
            watcher->deleteLater();
            const QDBusReply<QVariantMap> reply = *watcher;
            if (!reply.isValid()) {
                close(fd);
                done({});
                return;
            }
            const QVariantMap info = reply.value();
            const int w = info.value(QStringLiteral("width")).toInt();
            const int h = info.value(QStringLiteral("height")).toInt();
            const int stride = info.value(QStringLiteral("stride")).toInt();
            const auto format = QImage::Format(info.value(QStringLiteral("format")).toInt());
            QByteArray data;
            data.resize(qsizetype(stride) * h);
            qsizetype got = 0;
            while (got < data.size()) {   // KWin writes the pixels right after the reply
                const ssize_t n = read(fd, data.data() + got, data.size() - got);
                if (n <= 0) {
                    break;
                }
                got += n;
            }
            close(fd);
            if (w <= 0 || h <= 0 || got < data.size()) {
                done({});
                return;
            }
            done(QImage(reinterpret_cast<const uchar *>(data.constData()), w, h, stride, format).copy());
        });
    }

    QScreen *builtInScreen() const
    {
        const auto screens = QGuiApplication::screens();
        for (QScreen *s : screens) {
            if (s->name().startsWith(QLatin1String("eDP")) || s->name().startsWith(QLatin1String("LVDS")) || s->name().startsWith(QLatin1String("DSI"))) {
                return s;
            }
        }
        return screens.isEmpty() ? nullptr : screens.first();
    }

    // Where the selection highlight appeared: the pixels that changed between two pictures of the
    // same strip, in the run through `p` (picture coordinates). An empty rect = not found.
    static QRect changedRun(const QImage &before, const QImage &after, QPoint p)
    {
        if (before.size() != after.size() || before.isNull() || !QRect(QPoint(), before.size()).contains(p)) {
            return {};
        }
        const QImage a = before.convertToFormat(QImage::Format_RGB32);
        const QImage b = after.convertToFormat(QImage::Format_RGB32);
        auto changed = [&](int x, int y) {
            const QRgb u = a.pixel(x, y), v = b.pixel(x, y);
            return qAbs(qRed(u) - qRed(v)) + qAbs(qGreen(u) - qGreen(v)) + qAbs(qBlue(u) - qBlue(v)) > 24;
        };
        // columns with a change close to the finger's row, then the run around the finger
        const int w = a.width(), h = a.height();
        QList<bool> col(w, false);
        for (int x = 0; x < w; ++x) {
            for (int y = qMax(0, p.y() - 8); y <= qMin(h - 1, p.y() + 8) && !col[x]; ++y) {
                col[x] = changed(x, y);
            }
        }
        int seed = -1;
        for (int d = 0; d < 24 && seed < 0; ++d) {
            if (p.x() - d >= 0 && col[p.x() - d]) {
                seed = p.x() - d;
            } else if (p.x() + d < w && col[p.x() + d]) {
                seed = p.x() + d;
            }
        }
        if (seed < 0) {
            return {};
        }
        const int gap = 2;   // a letter stroke the highlight leaves as it was
        int x0 = seed, x1 = seed;
        for (int x = seed, miss = 0; x >= 0 && miss <= gap; --x) {
            col[x] ? (x0 = x, miss = 0) : ++miss;
        }
        for (int x = seed, miss = 0; x < w && miss <= gap; ++x) {
            col[x] ? (x1 = x, miss = 0) : ++miss;
        }
        // the caret right beside the highlight: a sliver of a few columns behind a gap
        for (int x = x1; x > x1 - 4 && x > x0; --x) {
            if (!col[x]) {
                x1 = x - 1;
                break;
            }
        }
        for (int x = x0; x < x0 + 4 && x < x1; ++x) {
            if (!col[x]) {
                x0 = x + 1;
                break;
            }
        }
        // rows: the same, inside those columns
        QList<bool> row(h, false);
        for (int y = 0; y < h; ++y) {
            for (int x = x0; x <= x1 && !row[y]; x += 2) {
                row[y] = changed(x, y);
            }
        }
        int y0 = p.y(), y1 = p.y();
        for (int y = p.y(), miss = 0; y >= 0 && miss <= 0; --y) {
            row[y] ? (y0 = y, miss = 0) : ++miss;
        }
        for (int y = p.y(), miss = 0; y < h && miss <= 0; ++y) {
            row[y] ? (y1 = y, miss = 0) : ++miss;
        }
        return QRect(QPoint(x0, y0), QPoint(x1, y1));
    }

    // Long press on a word in a text field: select the word (a double tap), find its box on screen
    // and put the handles on its ends. Nothing selected (an empty spot) = the menu without them.
    void selectWordAt(QPointF at, bool canPaste, const QString &app)
    {
        const double halfBand = 0.06;
        const QRectF band(m_windowArea.x(), at.y() - halfBand, m_windowArea.width(), 2 * halfBand);
        capture(band, [this, at, canPaste, app, band](QImage before) {
            const int primaryBefore = m_primaryChanges;
            steps({{0, [this, at] { vTouch(0, at); }}, {35, [this, at] { vTouch(2, at); }},
                   {70, [this, at] { vTouch(0, at); }}, {35, [this, at] { vTouch(2, at); }},
                   {260, [this, at, canPaste, app, band, before, primaryBefore] {
                       if (m_primaryChanges == primaryBefore) {
                           Q_EMIT textMenuRequested(at.x(), at.y(), true, false, canPaste, app, {});
                           return;
                       }
                       if (before.isNull()) {
                           Q_EMIT textMenuRequested(at.x(), at.y(), true, true, canPaste, app, {});
                           return;
                       }
                       capture(band, [this, at, canPaste, app, band, before](QImage after) {
                           QScreen *scr = builtInScreen();
                           const double sw = scr ? scr->geometry().width() : 1, sh = scr ? scr->geometry().height() : 1;
                           // picture pixels per screen fraction
                           const double kx = before.width() / band.width(), ky = before.height() / band.height();
                           const QPoint p(qRound((at.x() - band.x()) * kx), qRound((at.y() - band.y()) * ky));
                           const QRect r = changedRun(before, after, p);
                           if (r.isEmpty() || r.height() / ky * sh > 90 || r.width() < 3) {
                               Q_EMIT textMenuRequested(at.x(), at.y(), true, true, canPaste, app, {});
                               return;
                           }
                           Q_UNUSED(sw);
                           const double midY = band.y() + (r.top() + r.bottom() + 1) / 2.0 / ky;
                           const QPointF a(band.x() + r.left() / kx, midY), b(band.x() + (r.right() + 1) / kx, midY);
                           Q_EMIT textMenuRequested((a.x() + b.x()) / 2, a.y(), true, true, canPaste, app,
                                                    selection(a, b, (r.height() + 1) / ky));
                       });
                   }}});
        });
    }

    int handleAt(QPointF at) const
    {
        if (!m_handlesOn) {
            return 0;
        }
        for (int i : {2, 1}) {   // the end first: a single letter puts them on top of each other
            if (m_handleHit[i].contains(at)) {
                return i;
            }
        }
        return 0;
    }

    // A handle picked up: put the caret on the other end, then Shift + touch at this end, and the
    // touch follows the finger, so the app moves the end of the selection along with it
    void beginHandleDrag(int handle, QPointF finger)
    {
        m_dragHandle = handle;
        m_dragLive = false;
        m_dragUp = false;
        m_dragOffset = m_tip[handle] - finger;
        m_dragLast = finger;
        m_handlesOn = false;
        Q_EMIT handleDragStarted();
        const QPointF anchor = m_tip[handle == 1 ? 2 : 1];
        const QPointF tip = m_tip[handle];
        // two taps close together would be a double click (a word) instead
        const int pause = QLineF(anchor, tip).length() < 0.03 ? 450 : 90;
        steps({{60, [this, anchor] { vTouch(0, anchor); }}, {35, [this, anchor] { vTouch(2, anchor); }},
               {pause, [this] {
                    if (ensureUinput()) {
                        emitKey(KEY_LEFTSHIFT, 1);
                    }
                }},
               // the app has to hear about Shift before the touch (another device, another queue)
               {60, [this, tip] {
                    vTouch(0, tip);
                    m_dragLive = true;
                    if (m_dragUp) {
                        finishHandleDrag();
                    } else {
                        vTouch(1, m_dragLast + m_dragOffset);
                    }
                }}});
    }

    void handleDragFrame(int down, int first)
    {
        if (down == 0) {
            m_dragUp = true;
            if (m_dragLive) {
                finishHandleDrag();
            }
            return;
        }
        m_dragLast = touchPoint(first);
        const QPointF tip = m_dragLast + m_dragOffset;
        if (m_dragLive) {
            vTouch(1, tip);
        }
        Q_EMIT handleDragMoved(m_dragHandle, tip.x(), tip.y());
    }

    void finishHandleDrag()
    {
        const int handle = m_dragHandle;
        QPointF tip = m_dragLast + m_dragOffset;
        tip = {qBound(0.0, tip.x(), 1.0), qBound(0.0, tip.y(), 1.0)};
        vTouch(1, tip);
        vTouch(2, tip);
        m_dragLive = false;
        steps({{40, [this] { emitKey(KEY_LEFTSHIFT, 0); }},
               {80, [this, handle, tip] {
                    m_dragHandle = 0;
                    Q_EMIT handleDragFinished(handle, tip.x(), tip.y());
                }}});
    }

public:
    // TextMenu.qml: the handles on screen (or gone): their tips and where a finger takes them
    Q_INVOKABLE void setHandles(bool on, double sx, double sy, double ex, double ey, const QRectF &startHit, const QRectF &endHit)
    {
        m_handlesOn = on;
        m_tip[1] = {sx, sy};
        m_tip[2] = {ex, ey};
        m_handleHit[1] = startHit;
        m_handleHit[2] = endHit;
    }

private:
    int m_uinput = -1;
    QElapsedTimer m_counting;
    bool m_tabletMode = false;
    QStringList m_micApps;
    QStringList m_cameraApps;
    int m_waydroidWindows = 0;
    int m_waydroidIdle = 0;      // minutes without a Waydroid window while the session runs
    QString m_currentApp;
    bool m_locked = false;
    QElapsedTimer m_woke;   // since the session started or the tablet woke up
    QString m_osdMember;
    QStringList m_osdArgs;
    // text menu: touch screen state
    static constexpr int kTouchSlots = 16;
    struct Contact {
        int id = -1;
        int x = 0;
        int y = 0;
    };
    Contact m_contacts[kTouchSlots];
    int m_touchFd = -1;
    input_absinfo m_touchX{};
    input_absinfo m_touchY{};
    int m_slot = 0;
    int m_touchSlot = 0;
    bool m_touching = false;
    bool m_held = false;
    bool m_cancelled = false;
    QPointF m_touchStart;
    QPointF m_touchLast;
    QTimer *m_holdTimer = nullptr;
    int m_primaryChanges = 0;
    int m_primaryAtDown = 0;
    int m_rotation = 1;
    qint64 m_windowPid = 0;
    QRectF m_windowArea;
    bool m_windowHome = false;
    // text selection: the virtual touch screen (taps for the app), the handles on screen
    int m_vtouchFd = -1;
    int m_vtrack = 1;
    bool m_handlesOn = false;
    QPointF m_tip[3];          // [1] start, [2] end: middle of the line at either end
    QRectF m_handleHit[3];     // where a finger picks the handle up
    int m_dragHandle = 0;
    bool m_dragLive = false;
    bool m_dragUp = false;
    QPointF m_dragOffset;      // tip minus finger
    QPointF m_dragLast;
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
        shell.watchOsd();
        shell.watchTouch();
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
