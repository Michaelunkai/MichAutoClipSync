package com.mich.autoclipsync;

import android.content.ClipData;
import android.content.Context;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.List;

class SamsungClipboardObserver {
    final Context context;
    Object manager;
    Object listener;
    volatile boolean running;

    SamsungClipboardObserver(Context context) {
        this.context = context.getApplicationContext();
    }

    void start() {
        try {
            manager = context.getSystemService("semclipboard");
            if (manager == null) {
                ClipBridgeService.publishSemClipboardState(false, false, "semclipboard_missing", "", "");
                return;
            }
            String klass = manager.getClass().getName();
            ClipBridgeService.publishSemClipboardMethods(summarizeMethods(manager.getClass()));
            ClipBridgeService.publishSemClipboardState(true, false, "semclipboard_found", "", klass);
            registerListener(klass);
            running = true;
            startPoller(klass);
        } catch (Throwable t) {
            ClipBridgeService.publishSemClipboardState(false, false, "semclipboard_start_blocked", rootName(t), "");
        }
    }

    void registerListener(final String klass) {
        try {
            final Class<?> listenerClass = Class.forName("com.samsung.android.content.clipboard.SemClipboardEventListener");
            listener = Proxy.newProxyInstance(listenerClass.getClassLoader(), new Class<?>[]{listenerClass}, new InvocationHandler() {
                public Object invoke(Object proxy, Method method, Object[] args) {
                    String name = method == null ? "" : method.getName();
                    if ("onClipboardUpdated".equals(name)) {
                        ClipBridgeService.publishSemClipboardDetails(-1, "", name);
                        ClipBridgeService.publishSemClipboardEventArgs(summarizeArgs(args));
                        Object semClip = args != null && args.length > 1 ? args[1] : null;
                        if (semClip == null) ClipBridgeService.publishSemClipboardState(true, true, "semclipboard_listener_null_clip", "", manager == null ? "" : manager.getClass().getName());
                        if (!publishSemClip(semClip, "semclipboard_listener") && !readLatest("semclipboard_listener_fallback")) {
                            ClipAccessibilityService.publishLastKnownSelection("semclipboard_accessibility_fallback");
                        }
                    } else if (!"onFilterUpdated".equals(name) && !"toString".equals(name) && !"hashCode".equals(name) && !"equals".equals(name)) {
                        ClipBridgeService.publishSemClipboardDetails(-1, "", name);
                        ClipBridgeService.publishSemClipboardEventArgs(summarizeArgs(args));
                        readLatest("semclipboard_event_" + name);
                    }
                    return defaultValue(method == null ? null : method.getReturnType());
                }
            });
            Method register = findMethod(manager.getClass(), "registerClipboardEventListener", listenerClass);
            register.invoke(manager, listener);
            ClipBridgeService.publishSemClipboardState(true, true, "semclipboard_registered", "", klass);
            readLatest("semclipboard_initial", false);
        } catch (Throwable t) {
            ClipBridgeService.publishSemClipboardState(true, false, "semclipboard_register_blocked", rootName(t), klass);
        }
    }

    void startPoller(final String klass) {
        Thread poller = new Thread(new Runnable() {
            public void run() {
                while (running) {
                    readLatest("semclipboard_poll", false);
                    try {
                        Thread.sleep(500);
                    } catch (InterruptedException ignored) {
                    }
                }
            }
        }, "MichAutoClipSyncSamsungClipboard");
        poller.setDaemon(true);
        poller.start();
    }

    boolean readLatest(String source) {
        return readLatest(source, true);
    }

    boolean readLatest(String source, boolean allowPublish) {
        try {
            if (manager == null) return false;
            int count = -1;
            try {
                Method getCount = findMethod(manager.getClass(), "getCount");
                Object countObject = getCount.invoke(manager);
                if (countObject instanceof Integer) count = ((Integer) countObject).intValue();
            } catch (Throwable ignored) {
            }
            if (allowPublish) {
                for (int type = 1; type <= 8; type++) {
                    if (publishFromIntMethod("getLatestClip", type, source + "_latest_" + type)) return true;
                }
                if (count > 0) {
                    for (int index = count - 1; index >= 0; index--) {
                        if (publishFromIntMethod("getClip", index, source + "_clip_" + index)) return true;
                    }
                }
            }
            Method getClips = findMethod(manager.getClass(), "getClips");
            Object clipsObject = getClips.invoke(manager);
            if (!(clipsObject instanceof List)) {
                ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_not_list", "", manager.getClass().getName());
                return false;
            }
            List<?> clips = (List<?>) clipsObject;
            if (count >= 0 && clips.size() != count) count = clips.size();
            ClipBridgeService.publishSemClipboardDetails(clips.size(), summarizeClips(clips), "");
            if (allowPublish) {
                for (int i = clips.size() - 1; i >= 0; i--) {
                    if (publishSemClip(clips.get(i), source)) return true;
                }
            }
            ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_empty", "", manager.getClass().getName());
            return false;
        } catch (Throwable t) {
            ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_blocked", rootName(t), manager == null ? "" : manager.getClass().getName());
            return false;
        }
    }

    boolean publishFromIntMethod(String methodName, int value, String source) {
        try {
            Method method = findMethod(manager.getClass(), methodName, Integer.TYPE);
            Object semClip = method.invoke(manager, Integer.valueOf(value));
            if (semClip == null) {
                ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_null", "", manager == null ? "" : manager.getClass().getName());
                return false;
            }
            return publishSemClip(semClip, source);
        } catch (Throwable t) {
            ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_blocked", rootName(t), manager == null ? "" : manager.getClass().getName());
            return false;
        }
    }

    boolean publishSemClip(Object semClip, String source) {
        try {
            if (semClip == null) return false;
            Method getClipData = findMethod(semClip.getClass(), "getClipData");
            Object clipObject = getClipData.invoke(semClip);
            if (!(clipObject instanceof ClipData)) {
                ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_not_clipdata", "", manager == null ? "" : manager.getClass().getName());
                return false;
            }
            boolean published = ClipBridgeService.publishClipData(context, (ClipData) clipObject, source);
            ClipBridgeService.publishSemClipboardState(true, listener != null, source, published ? "" : "publish_failed", manager == null ? "" : manager.getClass().getName());
            if (published) ClipBridgeService.lastSemClipboardPublish = System.currentTimeMillis();
            return published;
        } catch (Throwable t) {
            ClipBridgeService.publishSemClipboardState(true, listener != null, source + "_blocked", rootName(t), manager == null ? "" : manager.getClass().getName());
            return false;
        }
    }

    String summarizeClips(List<?> clips) {
        if (clips == null) return "";
        StringBuilder sb = new StringBuilder();
        int limit = Math.min(clips.size(), 6);
        for (int i = 0; i < limit; i++) {
            if (i > 0) sb.append("|");
            Object clip = clips.get(i);
            sb.append(i).append(":").append(clip == null ? "null" : clip.getClass().getName());
        }
        if (clips.size() > limit) sb.append("|...");
        return sb.toString();
    }

    String summarizeArgs(Object[] args) {
        if (args == null) return "null";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append("|");
            Object arg = args[i];
            sb.append(i).append(":").append(arg == null ? "null" : arg.getClass().getName()).append("=").append(String.valueOf(arg));
        }
        return sb.toString();
    }

    String summarizeMethods(Class<?> klass) {
        try {
            Method[] methods = klass.getMethods();
            StringBuilder sb = new StringBuilder();
            int count = 0;
            for (int i = 0; i < methods.length && count < 30; i++) {
                String name = methods[i].getName();
                String lower = name.toLowerCase();
                if (lower.indexOf("clip") >= 0 || lower.indexOf("data") >= 0 || lower.indexOf("count") >= 0 || lower.indexOf("paste") >= 0) {
                    if (count > 0) sb.append("|");
                    sb.append(name).append("(").append(methods[i].getParameterTypes().length).append(")");
                    count++;
                }
            }
            return sb.toString();
        } catch (Throwable t) {
            return rootName(t);
        }
    }

    Method findMethod(Class<?> klass, String name, Class<?>... args) throws NoSuchMethodException {
        try {
            Method method = klass.getMethod(name, args);
            method.setAccessible(true);
            return method;
        } catch (NoSuchMethodException ignored) {
            Method method = klass.getDeclaredMethod(name, args);
            method.setAccessible(true);
            return method;
        }
    }

    Object defaultValue(Class<?> type) {
        if (type == null || type == Void.TYPE) return null;
        if (type == Boolean.TYPE) return Boolean.FALSE;
        if (type == Byte.TYPE) return Byte.valueOf((byte) 0);
        if (type == Short.TYPE) return Short.valueOf((short) 0);
        if (type == Integer.TYPE) return Integer.valueOf(0);
        if (type == Long.TYPE) return Long.valueOf(0L);
        if (type == Float.TYPE) return Float.valueOf(0f);
        if (type == Double.TYPE) return Double.valueOf(0d);
        if (type == Character.TYPE) return Character.valueOf((char) 0);
        return null;
    }

    String rootName(Throwable t) {
        Throwable x = t;
        while (x != null && x.getCause() != null) x = x.getCause();
        return x == null ? "" : x.getClass().getSimpleName();
    }
}
