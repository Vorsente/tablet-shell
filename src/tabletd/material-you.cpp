// Material You for the Pixel look: colours from the wallpaper, like a Pixel phone.
//
//   tablet-tools material-you [--print]
//
// The seed: tabletrc [Appearance] materialSeed (#RRGGBB) or, when empty, the most characteristic
// colour of the Pixel wallpaper (pixelWallpaper; a wallpaper package: its light image). Pixels are
// counted per hue in CIELAB; a hue scores by how much of the picture it covers and how colourful it
// is (Material's Score: chroma near 48 preferred, greys never win). materialYou=false gives the
// baseline Material purple.
//
// From the seed hue the tonal palettes of Material 3's "Tonal spot" scheme (Pixel's default):
// primary (chroma 36), secondary (16), tertiary (hue + 60, 24), neutral (6), neutral variant (8).
// A tone is CIELAB L*; colours outside sRGB lose chroma until they fit. The colour roles of the light
// and the dark scheme go into
//   ~/.config/tablet-material-you.json            (for anything that wants the roles)
//   ~/.local/share/color-schemes/TabletPixel{Light,Dark}.colors
// and, when one of them is the current colour scheme, straight into kdeglobals with a palette
// change notification: Plasma, the apps and the shell recolour at once. The shell's own Material
// colours follow through MaterialYou.js (seed hue = the hue of Kirigami's highlight colour).
#include <KConfig>
#include <KConfigGroup>

#include <QColor>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <map>

namespace {

struct Lab { double L, a, b; };

double toLinear(double c) { return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); }
double fromLinear(double c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * std::pow(c, 1 / 2.4) - 0.055; }
double labF(double t) { return t > 216.0 / 24389 ? std::cbrt(t) : (24389.0 / 27 * t + 16) / 116; }
double labFInv(double t) { return t * t * t > 216.0 / 24389 ? t * t * t : (116 * t - 16) / (24389.0 / 27); }
constexpr double Xn = 0.95047, Yn = 1.0, Zn = 1.08883;

Lab toLab(QRgb c)
{
    const double r = toLinear(qRed(c) / 255.0), g = toLinear(qGreen(c) / 255.0), b = toLinear(qBlue(c) / 255.0);
    const double x = 0.4124 * r + 0.3576 * g + 0.1805 * b;
    const double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const double z = 0.0193 * r + 0.1192 * g + 0.9505 * b;
    const double fx = labF(x / Xn), fy = labF(y / Yn), fz = labF(z / Zn);
    return {116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)};
}

// the colour of tone L, chroma C, hue h (degrees) in sRGB; false when it does not fit
bool fromLch(double L, double C, double h, QRgb *out)
{
    const double a = C * std::cos(h * M_PI / 180), b = C * std::sin(h * M_PI / 180);
    const double fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
    const double x = Xn * labFInv(fx), y = Yn * labFInv(fy), z = Zn * labFInv(fz);
    const double rl = 3.2406 * x - 1.5372 * y - 0.4986 * z;
    const double gl = -0.9689 * x + 1.8758 * y + 0.0415 * z;
    const double bl = 0.0557 * x - 0.2040 * y + 1.0570 * z;
    const double eps = 1e-4;
    if (rl < -eps || gl < -eps || bl < -eps || rl > 1 + eps || gl > 1 + eps || bl > 1 + eps) {
        return false;
    }
    auto ch = [](double v) { return int(std::lround(std::clamp(fromLinear(std::clamp(v, 0.0, 1.0)), 0.0, 1.0) * 255)); };
    *out = qRgb(ch(rl), ch(gl), ch(bl));
    return true;
}

// tone of a palette: as much of the palette's chroma as sRGB allows
QRgb tone(double hue, double chroma, double t)
{
    QRgb c = qRgb(0, 0, 0);
    if (fromLch(t, chroma, hue, &c)) {
        return c;
    }
    double lo = 0, hi = chroma;
    fromLch(t, 0, hue, &c);
    for (int i = 0; i < 18; ++i) {
        const double mid = (lo + hi) / 2;
        QRgb m;
        if (fromLch(t, mid, hue, &m)) {
            lo = mid;
            c = m;
        } else {
            hi = mid;
        }
    }
    return c;
}

QString hex(QRgb c) { return QStringLiteral("#%1").arg(c & 0xFFFFFF, 6, 16, QLatin1Char('0')).toUpper(); }
QString rgb(QRgb c) { return QStringLiteral("%1,%2,%3").arg(qRed(c)).arg(qGreen(c)).arg(qBlue(c)); }

double hueOf(QRgb c)
{
    const Lab l = toLab(c);
    double h = std::atan2(l.b, l.a) * 180 / M_PI;
    return h < 0 ? h + 360 : h;
}

// the seed hue of a picture (-1: nothing colourful enough)
double wallpaperHue(const QImage &source)
{
    if (source.isNull()) {
        return -1;
    }
    const QImage img = source.scaled(128, 128, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB32);
    constexpr int bins = 36;
    std::array<double, bins> count{}, sumA{}, sumB{}, sumC{};
    int total = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const Lab l = toLab(line[x]);
            const double c = std::hypot(l.a, l.b);
            ++total;
            if (c < 8 || l.L < 12 || l.L > 96) {
                continue;   // greys, black, white tell nothing about the colour
            }
            double h = std::atan2(l.b, l.a) * 180 / M_PI;
            if (h < 0) h += 360;
            const int i = int(h / (360.0 / bins)) % bins;
            count[i] += 1;
            sumA[i] += l.a / c;
            sumB[i] += l.b / c;
            sumC[i] += c;
        }
    }
    double best = -1e9, bestHue = -1;
    for (int i = 0; i < bins; ++i) {
        // a hue with its neighbours (+-15 degrees), like Material's "excited proportion"
        const double near = count[i] + 0.5 * (count[(i + 1) % bins] + count[(i + bins - 1) % bins]);
        const double proportion = near / std::max(1, total);
        if (count[i] < 1 || proportion < 0.01) {
            continue;
        }
        const double chroma = sumC[i] / count[i];
        if (chroma < 15) {
            continue;
        }
        const double score = proportion * 100 * 0.7 + (chroma - 48) * (chroma < 48 ? 0.1 : 0.3);
        if (score > best) {
            best = score;
            double h = std::atan2(sumB[i], sumA[i]) * 180 / M_PI;
            bestHue = h < 0 ? h + 360 : h;
        }
    }
    return bestHue;
}

QString wallpaperImage()
{
    KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    QString path = rc.group(QStringLiteral("Appearance")).readEntry("pixelWallpaper", QString());
    if (path.isEmpty()) {
        path = QDir::homePath() + QStringLiteral("/.local/share/wallpapers/Material-Orbit");
    }
    if (QFileInfo(path).isDir()) {
        const QFileInfoList files = QDir(path + QStringLiteral("/contents/images")).entryInfoList(QDir::Files, QDir::Size);
        return files.isEmpty() ? QString() : files.first().absoluteFilePath();
    }
    return path;
}

struct Scheme { std::map<QString, QRgb> roles; };

Scheme makeScheme(double hue, bool dark)
{
    const double th = std::fmod(hue + 60, 360);
    auto P = [&](double t) { return tone(hue, 36, t); };
    auto S = [&](double t) { return tone(hue, 16, t); };
    auto T = [&](double t) { return tone(th, 24, t); };
    auto N = [&](double t) { return tone(hue, 6, t); };
    auto V = [&](double t) { return tone(hue, 8, t); };
    auto E = [&](double t) { return tone(25, 60, t); };
    Scheme s;
    auto& r = s.roles;
    if (!dark) {
        r = {{QStringLiteral("primary"), P(40)}, {QStringLiteral("onPrimary"), P(100)},
             {QStringLiteral("primaryContainer"), P(90)}, {QStringLiteral("onPrimaryContainer"), P(10)},
             {QStringLiteral("secondary"), S(40)}, {QStringLiteral("onSecondary"), S(100)},
             {QStringLiteral("secondaryContainer"), S(90)}, {QStringLiteral("onSecondaryContainer"), S(10)},
             {QStringLiteral("tertiary"), T(40)}, {QStringLiteral("onTertiary"), T(100)},
             {QStringLiteral("tertiaryContainer"), T(90)}, {QStringLiteral("onTertiaryContainer"), T(10)},
             {QStringLiteral("error"), E(40)}, {QStringLiteral("errorContainer"), E(90)},
             {QStringLiteral("surface"), N(98)}, {QStringLiteral("surfaceDim"), N(87)},
             {QStringLiteral("surfaceContainerLowest"), N(100)}, {QStringLiteral("surfaceContainerLow"), N(96)},
             {QStringLiteral("surfaceContainer"), N(94)}, {QStringLiteral("surfaceContainerHigh"), N(92)},
             {QStringLiteral("surfaceContainerHighest"), N(90)}, {QStringLiteral("onSurface"), N(10)},
             {QStringLiteral("onSurfaceVariant"), V(30)}, {QStringLiteral("outline"), V(50)},
             {QStringLiteral("outlineVariant"), V(80)}, {QStringLiteral("inverseSurface"), N(20)},
             {QStringLiteral("inverseOnSurface"), N(95)}, {QStringLiteral("inversePrimary"), P(80)}};
    } else {
        r = {{QStringLiteral("primary"), P(80)}, {QStringLiteral("onPrimary"), P(20)},
             {QStringLiteral("primaryContainer"), P(30)}, {QStringLiteral("onPrimaryContainer"), P(90)},
             {QStringLiteral("secondary"), S(80)}, {QStringLiteral("onSecondary"), S(20)},
             {QStringLiteral("secondaryContainer"), S(30)}, {QStringLiteral("onSecondaryContainer"), S(90)},
             {QStringLiteral("tertiary"), T(80)}, {QStringLiteral("onTertiary"), T(20)},
             {QStringLiteral("tertiaryContainer"), T(30)}, {QStringLiteral("onTertiaryContainer"), T(90)},
             {QStringLiteral("error"), E(80)}, {QStringLiteral("errorContainer"), E(30)},
             {QStringLiteral("surface"), N(6)}, {QStringLiteral("surfaceDim"), N(6)},
             {QStringLiteral("surfaceContainerLowest"), N(4)}, {QStringLiteral("surfaceContainerLow"), N(10)},
             {QStringLiteral("surfaceContainer"), N(12)}, {QStringLiteral("surfaceContainerHigh"), N(17)},
             {QStringLiteral("surfaceContainerHighest"), N(22)}, {QStringLiteral("onSurface"), N(90)},
             {QStringLiteral("onSurfaceVariant"), V(80)}, {QStringLiteral("outline"), V(60)},
             {QStringLiteral("outlineVariant"), V(30)}, {QStringLiteral("inverseSurface"), N(90)},
             {QStringLiteral("inverseOnSurface"), N(20)}, {QStringLiteral("inversePrimary"), P(40)}};
    }
    return s;
}

// a KDE colour scheme from the roles (the layout of scripts/build-material-theme.py)
QString colorScheme(const Scheme &s, bool dark)
{
    auto c = [&](const char *role) { return s.roles.at(QLatin1String(role)); };
    const QString name = dark ? QStringLiteral("TabletPixelDark") : QStringLiteral("TabletPixelLight");
    QString out;
    QTextStream t(&out);
    t << "[General]\nName=Tablet Pixel " << (dark ? "Dark" : "Light") << "\nColorScheme=" << name << "\n";
    struct Role { const char *group, *bg, *alt, *fg; };
    // Window: the plates of Plasma's panels and dialogs (surface container); View: app content
    const Role roles[] = {
        {"Window", "surfaceContainer", "surfaceContainerHigh", "onSurface"},
        {"View", "surface", "surfaceContainerLow", "onSurface"},
        {"Button", "surfaceContainerHighest", "surfaceContainerHigh", "onSurface"},
        {"Tooltip", "inverseSurface", "inverseSurface", "inverseOnSurface"},
        {"Complementary", "surfaceContainer", "surfaceContainerHigh", "onSurface"},
        {"Header", "surfaceContainer", "surfaceContainerHigh", "onSurface"},
        {"Selection", "primary", "primaryContainer", "onPrimary"},
    };
    for (const Role &r : roles) {
        const bool tip = QLatin1String(r.group) == QLatin1String("Tooltip");
        t << "\n[Colors:" << r.group << "]\n"
          << "BackgroundNormal=" << rgb(c(r.bg)) << "\n"
          << "BackgroundAlternate=" << rgb(c(r.alt)) << "\n"
          << "ForegroundNormal=" << rgb(c(r.fg)) << "\n"
          << "ForegroundInactive=" << rgb(tip ? c("inverseOnSurface") : c("onSurfaceVariant")) << "\n"
          << "ForegroundActive=" << rgb(tip ? c("inversePrimary") : c("primary")) << "\n"
          << "ForegroundLink=" << rgb(tip ? c("inversePrimary") : c("primary")) << "\n"
          << "ForegroundVisited=" << rgb(tip ? c("inverseOnSurface") : c("tertiary")) << "\n"
          << "ForegroundNegative=" << rgb(c("error")) << "\n"
          << "ForegroundNeutral=" << rgb(dark ? qRgb(0xFF, 0xB8, 0x6C) : qRgb(0x82, 0x55, 0x00)) << "\n"
          << "ForegroundPositive=" << rgb(dark ? qRgb(0x81, 0xC9, 0x95) : qRgb(0x14, 0x6C, 0x2E)) << "\n"
          << "DecorationFocus=" << rgb(c("primary")) << "\n"
          << "DecorationHover=" << rgb(c("primary")) << "\n";
    }
    t << "\n[WM]\nactiveBackground=" << rgb(c("surfaceContainer")) << "\nactiveForeground=" << rgb(c("onSurface"))
      << "\ninactiveBackground=" << rgb(c("surfaceContainerLow")) << "\ninactiveForeground=" << rgb(c("onSurfaceVariant"))
      << "\nactiveBlend=" << rgb(c("primary")) << "\ninactiveBlend=" << rgb(c("outline")) << "\n";
    return out;
}

bool writeIfChanged(const QString &path, const QByteArray &data)
{
    QFile in(path);
    if (in.open(QIODevice::ReadOnly) && in.readAll() == data) {
        return false;
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile out(path + QStringLiteral(".new"));
    if (!out.open(QIODevice::WriteOnly)) {
        return false;
    }
    out.write(data);
    out.close();
    QFile::remove(path);
    return out.rename(path);
}

// the current colour scheme again from its (rewritten) file: kdeglobals + palette notification,
// what plasma-apply-colorscheme does (it refuses to apply the scheme that is already set)
void applyToKdeglobals(const QString &schemeFile)
{
    KConfig scheme(schemeFile, KConfig::SimpleConfig);
    KConfig globals(QStringLiteral("kdeglobals"));
    for (const QString &group : scheme.groupList()) {
        if (group == QLatin1String("General")) {
            continue;
        }
        KConfigGroup from = scheme.group(group);
        KConfigGroup to = globals.group(group);
        const auto entries = from.entryMap();
        for (auto it = entries.cbegin(); it != entries.cend(); ++it) {
            to.writeEntry(it.key(), it.value());
        }
    }
    QFile f(schemeFile);
    if (f.open(QIODevice::ReadOnly)) {
        globals.group(QStringLiteral("General")).writeEntry("ColorSchemeHash",
            QString::fromLatin1(QCryptographicHash::hash(f.readAll(), QCryptographicHash::Sha1).toHex()));
    }
    globals.sync();
    QDBusMessage changed = QDBusMessage::createSignal(QStringLiteral("/KGlobalSettings"), QStringLiteral("org.kde.KGlobalSettings"),
                                                      QStringLiteral("notifyChange"));
    changed << 0 << 0;   // PaletteChanged
    QDBusConnection::sessionBus().send(changed);
    QDBusMessage kwin = QDBusMessage::createSignal(QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reloadConfig"));
    QDBusConnection::sessionBus().send(kwin);
}

} // namespace

int materialYouCommand(const QStringList &args)
{
    KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    const KConfigGroup look = rc.group(QStringLiteral("Appearance"));
    const QRgb baseline = qRgb(0x67, 0x50, 0xA4);
    double hue = hueOf(baseline);
    QString source = QStringLiteral("baseline");
    if (look.readEntry("materialYou", true)) {
        const QString seed = look.readEntry("materialSeed", QString());
        if (QColor::isValidColorName(seed)) {
            hue = hueOf(QColor(seed).rgb());
            source = seed;
        } else {
            const QString image = wallpaperImage();
            const double h = wallpaperHue(QImage(image));
            if (h >= 0) {
                hue = h;
                source = image;
            }
        }
    }
    QJsonObject json{{QStringLiteral("seedHue"), std::round(hue * 10) / 10}, {QStringLiteral("source"), source}};
    bool changed = false;
    const QString schemes = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/color-schemes/");
    for (const bool dark : {false, true}) {
        const Scheme s = makeScheme(hue, dark);
        QJsonObject roles;
        for (const auto &[k, v] : s.roles) {
            roles.insert(k, hex(v));
        }
        json.insert(dark ? QStringLiteral("dark") : QStringLiteral("light"), roles);
        const QString file = schemes + (dark ? QStringLiteral("TabletPixelDark.colors") : QStringLiteral("TabletPixelLight.colors"));
        changed = writeIfChanged(file, colorScheme(s, dark).toUtf8()) || changed;
    }
    const QByteArray data = QJsonDocument(json).toJson();
    if (args.contains(QStringLiteral("--print"))) {
        std::fputs(data.constData(), stdout);
    }
    writeIfChanged(QDir::homePath() + QStringLiteral("/.config/tablet-material-you.json"), data);
    const QString current = KConfig(QStringLiteral("kdeglobals")).group(QStringLiteral("General")).readEntry("ColorScheme", QString());
    if (current.startsWith(QLatin1String("TabletPixel")) && (changed || args.contains(QStringLiteral("--apply")))) {
        applyToKdeglobals(schemes + current + QStringLiteral(".colors"));
    }
    return 0;
}
