// tablet-keyboard: on-screen keyboard of the ThinkPad 10 setup (replaces plasma-keyboard).
// KWin starts it as its input method (kwinrc [Wayland] InputMethod=tablet-keyboard.desktop) and
// only then grants it the input-method-unstable-v1 globals:
//   zwp_input_method_v1   activate/deactivate with a context per focused text field;
//                         text goes in with commit_string, editing keys with keysym
//   zwp_input_panel_v1    turns our window into the input panel KWin shows at the bottom
// The keyboard itself is QML (qml/), this file is the bridge.
#include "qwayland-input-method-unstable-v1.h"

#include <QtWaylandClient/QWaylandClientExtension>
#include <QtWaylandClient/private/qwaylandscreen_p.h>
#include <QtWaylandClient/private/qwaylandshellintegration_p.h>
#include <QtWaylandClient/private/qwaylandshellsurface_p.h>
#include <QtWaylandClient/private/qwaylandwindow_p.h>

#include <QElapsedTimer>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QStandardPaths>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QFile>
#include <QRegion>
#include <QScreen>
#include <QSettings>
#include <QRegularExpression>
#include "../common/ui-style.h"
#include <QtCore/qlogging.h>
#include <QTimer>

// ---- input panel: our window as a zwp_input_panel_surface_v1 --------------------------------

class PanelSurface : public QtWaylandClient::QWaylandShellSurface, public QtWayland::zwp_input_panel_surface_v1
{
public:
    PanelSurface(struct ::zwp_input_panel_surface_v1 *object, QtWaylandClient::QWaylandWindow *window)
        : QWaylandShellSurface(window)
        , zwp_input_panel_surface_v1(object)
    {
        auto *screen = window->waylandScreen();
        set_toplevel(screen ? screen->output() : nullptr, position_center_bottom);
    }
    ~PanelSurface() override
    {
        zwp_input_panel_surface_v1_destroy(object());
    }
};

class PanelShell : public QtWaylandClient::QWaylandShellIntegrationTemplate<PanelShell>, public QtWayland::zwp_input_panel_v1
{
public:
    PanelShell()
        : QWaylandShellIntegrationTemplate<PanelShell>(1)
    {
    }
    // bind zwp_input_panel_v1 now (KWin only offers it to the input method it started)
    bool start()
    {
        QWaylandClientExtension::initialize();
        return isActive();
    }
    QtWaylandClient::QWaylandShellSurface *createShellSurface(QtWaylandClient::QWaylandWindow *window) override
    {
        return new PanelSurface(get_input_panel_surface(window->wlSurface()), window);
    }
};

// ---- input method: text out ----------------------------------------------------------------

class Keyboard;

class Context : public QtWayland::zwp_input_method_context_v1
{
public:
    Context(struct ::zwp_input_method_context_v1 *object, Keyboard *kb)
        : zwp_input_method_context_v1(object)
        , m_kb(kb)
    {
    }
    ~Context() override
    {
        zwp_input_method_context_v1_destroy(object());
    }
    uint32_t serial = 0;
    QString surrounding;
    int cursor = 0;

protected:
    void zwp_input_method_context_v1_surrounding_text(const QString &text, uint32_t cur, uint32_t) override;
    void zwp_input_method_context_v1_content_type(uint32_t hint, uint32_t purpose) override;
    void zwp_input_method_context_v1_commit_state(uint32_t s) override
    {
        serial = s;
    }
    void zwp_input_method_context_v1_reset() override;

private:
    Keyboard *m_kb;
};

class InputMethod : public QWaylandClientExtensionTemplate<InputMethod>, public QtWayland::zwp_input_method_v1
{
    Q_OBJECT
public:
    InputMethod()
        : QWaylandClientExtensionTemplate<InputMethod>(1)
    {
        initialize();
    }
Q_SIGNALS:
    void activated(struct ::zwp_input_method_context_v1 *context);
    void deactivated(struct ::zwp_input_method_context_v1 *context);

protected:
    void zwp_input_method_v1_activate(struct ::zwp_input_method_context_v1 *id) override
    {
        Q_EMIT activated(id);
    }
    void zwp_input_method_v1_deactivate(struct ::zwp_input_method_context_v1 *context) override
    {
        Q_EMIT deactivated(context);
    }
};

// ---- bridge to QML -------------------------------------------------------------------------

class Keyboard : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int purpose READ purpose NOTIFY contentChanged)
    Q_PROPERTY(int hints READ hints NOTIFY contentChanged)
    Q_PROPERTY(QString textBeforeCursor READ textBeforeCursor NOTIFY surroundingChanged)
    Q_PROPERTY(QVariantMap config READ config NOTIFY configChanged)

public:
    explicit Keyboard(QQuickView *view)
        : m_view(view)
    {
        // settings (Настройки -> Клавиатура) apply live: watch the file and its folder (KConfig
        // replaces the file on save)
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
        m_watcher.addPath(dir);
        if (QFile::exists(configPath())) {
            m_watcher.addPath(configPath());
        }
        auto reload = [this] {
            if (QFile::exists(configPath()) && !m_watcher.files().contains(configPath())) {
                m_watcher.addPath(configPath());
            }
            const QVariantMap c = readConfig();
            if (c != m_config) {
                m_config = c;
                Q_EMIT configChanged();
            }
        };
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, reload);
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, reload);
        m_config = readConfig();
        connect(&m_im, &InputMethod::activated, this, [this](struct ::zwp_input_method_context_v1 *c) {
            delete m_context;
            m_context = new Context(c, this);
            m_purpose = 0;
            m_hints = 0;
            Q_EMIT contentChanged();
            Q_EMIT activeChanged();
            if (!hiddenByHardware()) {
                m_view->show();
            }
        });
        // a keyboard plugged in while the panel is up takes it away
        m_devices.addPath(QStringLiteral("/dev/input"));
        connect(&m_devices, &QFileSystemWatcher::directoryChanged, this, [this] {
            if (m_view->isVisible() && hiddenByHardware()) {
                m_view->hide();
            }
        });
        connect(&m_im, &InputMethod::deactivated, this, [this](struct ::zwp_input_method_context_v1 *c) {
            if (m_context && m_context->object() == c) {
                delete m_context;
                m_context = nullptr;
                Q_EMIT activeChanged();
                m_view->hide();
            }
        });
    }

    bool active() const
    {
        return m_context;
    }
    int purpose() const
    {
        return m_purpose;
    }
    int hints() const
    {
        return m_hints;
    }
    QString textBeforeCursor() const
    {
        return m_context ? m_context->surrounding.left(m_context->cursor) : QString();
    }

    // text-input content type (zwp_text_input_v1 values), sent by KWin per field
    void setContent(uint32_t hint, uint32_t purpose)
    {
        m_hints = int(hint);
        m_purpose = int(purpose);
        Q_EMIT contentChanged();
    }
    void surroundingUpdated()
    {
        Q_EMIT surroundingChanged();
    }

    Q_INVOKABLE void commit(const QString &text)
    {
        if (m_context) {
            m_context->commit_string(m_context->serial, text);
        }
    }

    // editing keys as keysyms: KWin delivers them to the app as real key presses
    Q_INVOKABLE void key(const QString &name)
    {
        static const QHash<QString, uint32_t> syms{{QStringLiteral("BackSpace"), 0xff08}, {QStringLiteral("Return"), 0xff0d},
                                                   {QStringLiteral("Tab"), 0xff09},       {QStringLiteral("Escape"), 0xff1b},
                                                   {QStringLiteral("Left"), 0xff51},      {QStringLiteral("Up"), 0xff52},
                                                   {QStringLiteral("Right"), 0xff53},     {QStringLiteral("Down"), 0xff54},
                                                   {QStringLiteral("Delete"), 0xffff}};
        if (!m_context || !syms.contains(name)) {
            return;
        }
        const uint32_t time = uint32_t(m_clock.elapsed());
        m_context->keysym(m_context->serial, time, syms.value(name), 1, 0);
        m_context->keysym(m_context->serial, time, syms.value(name), 0, 0);
    }

    // drop the panel until the next text field asks for it
    Q_INVOKABLE void hide()
    {
        m_view->hide();
    }

    // split keyboard: only the two halves take touches, apps stay usable in between
    Q_INVOKABLE void setInputRegion(const QVariantList &rects)
    {
        QRegion region;
        for (const QVariant &v : rects) {
            region += v.toRect();
        }
        m_view->setMask(region);
    }

    // ~/.config/tablet-keyboardrc: options from the settings app and the keyboard's own state
    // (language, split, recent emoji)
    static QString configPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/tablet-keyboardrc");
    }
    // a real keyboard is attached (keyboard dock, USB or Bluetooth device with letter keys):
    // then text fields get no panel unless the option "hideWithKeyboard" is off
    bool hiddenByHardware() const
    {
        if (m_config.value(QStringLiteral("hideWithKeyboard"), true).toString() == QLatin1String("false")) {
            return false;
        }
        // a cover folded behind the screen is still attached: tabletd then forces KWin's tablet mode
        const QSettings kwinrc(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/kwinrc"),
                               QSettings::IniFormat);
        if (kwinrc.value(QStringLiteral("Input/TabletMode")).toString() == QLatin1String("on")) {
            return false;
        }
        // USB, Bluetooth, and covers behind the Surface System Aggregator (ssam, HID bus 0019)
        static const QRegularExpression hostHid(QStringLiteral("/0019:[0-9A-F]{4}:[0-9A-F]{4}\\."));
        const QDir input(QStringLiteral("/sys/class/input"));
        for (const QString &e : input.entryList({QStringLiteral("input*")})) {
            const QString path = QFileInfo(input.filePath(e)).canonicalFilePath();
            if (!path.contains(QLatin1String("/usb")) && !path.contains(QLatin1String("/bluetooth")) && !path.contains(QLatin1String("/uhid"))
                && !path.contains(QLatin1String("/ssam:")) && !path.contains(QLatin1String("surface")) && !hostHid.match(path).hasMatch()) {
                continue;
            }
            // letter keys Q, A and Z: the lowest 64 key bits are the last word of the mask
            QFile caps(path + QStringLiteral("/capabilities/key"));
            if (!caps.open(QIODevice::ReadOnly)) {
                continue;
            }
            const QList<QByteArray> words = caps.readAll().trimmed().split(' ');
            const quint64 low = words.last().toULongLong(nullptr, 16);
            if ((low >> 16 & 1) && (low >> 30 & 1) && (low >> 44 & 1)) {
                return true;
            }
        }
        return false;
    }

    static QVariantMap readConfig()
    {
        QSettings s(configPath(), QSettings::IniFormat);
        QVariantMap m;
        for (const QString &k : s.allKeys()) {
            m.insert(k, s.value(k));
        }
        return m;
    }
    QVariantMap config() const
    {
        return m_config;
    }
    Q_INVOKABLE QVariant setting(const QString &key, const QVariant &fallback) const
    {
        return m_config.value(key, fallback);
    }
    Q_INVOKABLE void setSetting(const QString &key, const QVariant &value)
    {
        QSettings s(configPath(), QSettings::IniFormat);
        s.setValue(key, value);
        s.sync();
        m_config.insert(key, value);
    }

    Context *context() const
    {
        return m_context;
    }

Q_SIGNALS:
    void activeChanged();
    void contentChanged();
    void surroundingChanged();
    void resetRequested();
    void configChanged();

private:
    QQuickView *m_view;
    InputMethod m_im;
    Context *m_context = nullptr;
    int m_purpose = 0;
    int m_hints = 0;
    QElapsedTimer m_clock = [] { QElapsedTimer t; t.start(); return t; }();
    QFileSystemWatcher m_watcher;
    QFileSystemWatcher m_devices;
    QVariantMap m_config;
};

void Context::zwp_input_method_context_v1_surrounding_text(const QString &text, uint32_t cur, uint32_t)
{
    surrounding = text;
    // the cursor is a byte offset into the UTF-8 text
    cursor = QString::fromUtf8(text.toUtf8().left(int(cur))).size();
    m_kb->surroundingUpdated();
}
void Context::zwp_input_method_context_v1_content_type(uint32_t hint, uint32_t purpose)
{
    m_kb->setContent(hint, purpose);
}
void Context::zwp_input_method_context_v1_reset()
{
    Q_EMIT m_kb->resetRequested();
}

// the built-in display (eDP / DSI), whatever the primary output is; else the primary one
static QScreen *panelScreen()
{
    for (QScreen *s : QGuiApplication::screens()) {
        if (s->name().startsWith(QLatin1String("eDP")) || s->name().startsWith(QLatin1String("DSI")) || s->name().startsWith(QLatin1String("LVDS"))) {
            return s;
        }
    }
    return QGuiApplication::primaryScreen();
}

int main(int argc, char *argv[])
{
    // Keep Qt diagnostics silent without an app-local helper declaration.
    // TABLET_SHELL_DEBUG=1 keeps Qt/QML messages for troubleshooting
    if (!qEnvironmentVariableIsSet("TABLET_SHELL_DEBUG")) qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    // input panels must not take focus away from the text field
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("tablet-keyboard"));
    app.setDesktopFileName(QStringLiteral("tablet-keyboard"));

    QQuickView view;
    view.setFlags(Qt::WindowDoesNotAcceptFocus | Qt::FramelessWindowHint);
    view.setColor(Qt::transparent);
    view.setResizeMode(QQuickView::SizeRootObjectToView);

    const bool demo = qEnvironmentVariableIsSet("TABLET_KEYBOARD_DEMO");
    // the input panel lives on the tablet's own screen, not on an external monitor of PC mode
    view.setScreen(panelScreen());
    PanelShell shell;
    view.create();
    if (!demo) {
        auto *w = dynamic_cast<QtWaylandClient::QWaylandWindow *>(view.handle());
        if (!shell.start() || !w) {
            return 1;
        }
        w->setShellIntegration(&shell);
    }

    Keyboard keyboard(&view);
    UiStyle uiStyle;
    view.rootContext()->setContextProperty(QStringLiteral("uiStyle"), &uiStyle);
    view.rootContext()->setContextProperty(QStringLiteral("keyboard"), &keyboard);
    view.rootContext()->setContextProperty(QStringLiteral("demoMode"), qEnvironmentVariable("TABLET_KEYBOARD_DEMO"));
    const QString dir = qEnvironmentVariable("TABLET_KEYBOARD_QML", QStringLiteral(KEYBOARD_QML_DIR));
    view.setSource(QUrl::fromLocalFile(dir + QStringLiteral("/Main.qml")));

    // panel size follows the screen it is on and its orientation: full width, and the height
    // share from the settings app (height = landscape, heightPortrait = portrait, % of the screen)
    auto fit = [&view, &keyboard] {
        const QSize s = view.screen()->size();
        const bool portrait = s.height() > s.width();
        const double share = portrait ? keyboard.setting(QStringLiteral("heightPortrait"), 26).toDouble()
                                      : keyboard.setting(QStringLiteral("height"), 40).toDouble();
        view.resize(s.width(), int(s.height() * qBound(0.15, share / 100.0, 0.6)));
    };
    QMetaObject::Connection screenWatch;
    auto track = [&view, &screenWatch, fit] {
        QObject::disconnect(screenWatch);
        screenWatch = QObject::connect(view.screen(), &QScreen::geometryChanged, &view, fit);
        fit();
    };
    track();
    QObject::connect(&view, &QWindow::screenChanged, &view, track);
    QObject::connect(&keyboard, &Keyboard::configChanged, &view, fit);
    if (demo) {
        view.show();
    }
    return app.exec();
}

#include "main.moc"
