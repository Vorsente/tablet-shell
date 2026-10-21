// Touch-friendly Firefox for tablets (tablet-shell)
user_pref("browser.uidensity", 2);                         // touch density: bigger tabs and buttons
user_pref("browser.compactmode.show", false);
user_pref("widget.use-xdg-desktop-portal.file-picker", 1); // KDE file dialogs
user_pref("widget.use-xdg-desktop-portal.mime-handler", 1);
user_pref("apz.allow_zooming", true);                      // pinch to zoom pages
user_pref("apz.gtk.kinetic_scroll.enabled", true);         // kinetic finger scrolling
user_pref("apz.overscroll.enabled", true);                 // iOS-like rubber band at page edges
user_pref("general.smoothScroll", true);
user_pref("dom.w3c_touch_events.enabled", 1);
user_pref("browser.gesture.swipe.left", "Browser:BackOrBackDuplicate");
user_pref("browser.gesture.swipe.right", "Browser:ForwardOrForwardDuplicate");
user_pref("widget.gtk.overlay-scrollbars.enabled", true);  // thin scrollbars that do not eat space
user_pref("browser.tabs.inTitlebar", 1);                   // tabs in the title bar: more room for pages
user_pref("ui.key.menuAccessKeyFocuses", false);
user_pref("gfx.webrender.software", false);
user_pref("media.ffmpeg.vaapi.enabled", true);             // hardware video decoding
