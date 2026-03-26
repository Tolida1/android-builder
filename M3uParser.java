package PACKAGE_PLACEHOLDER;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class M3uParser {

    public static class Channel {
        public String name    = "";
        public String url     = "";
        public String logo    = "";
        public String group   = "";
        public String referer = "";
        public String origin  = "";

        public Map<String, Object> toMap() {
            Map<String, Object> m = new HashMap<>();
            m.put("name",    name);
            m.put("url",     url);
            m.put("logo",    logo);
            m.put("group",   group);
            m.put("referer", referer);
            m.put("origin",  origin);
            return m;
        }
    }

    public static List<Channel> parseFromUrl(String m3uUrl) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(m3uUrl).openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent", "VLC/3.0 LibVLC/3.0");
        BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
        return parse(reader);
    }

    public static List<Channel> parseFromString(String content) throws Exception {
        return parse(new BufferedReader(new StringReader(content)));
    }

    private static List<Channel> parse(BufferedReader reader) throws Exception {
        List<Channel> channels = new ArrayList<>();
        Channel current = null;
        String line;
        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty() || line.equals("#EXTM3U")) continue;
            if (line.startsWith("#EXTINF:")) {
                current = new Channel();
                int ci = line.lastIndexOf(',');
                if (ci >= 0 && ci < line.length() - 1)
                    current.name = line.substring(ci + 1).trim();
                current.logo  = attr(line, "tvg-logo");
                current.group = attr(line, "group-title");
                String tn = attr(line, "tvg-name");
                if (!tn.isEmpty() && current.name.isEmpty()) current.name = tn;
            } else if (line.startsWith("#EXTVLCOPT:")) {
                if (current != null) {
                    String opt = line.substring("#EXTVLCOPT:".length()).trim();
                    if (opt.startsWith("http-referrer="))
                        current.referer = opt.substring("http-referrer=".length()).trim();
                    else if (opt.startsWith("http-origin="))
                        current.origin = opt.substring("http-origin=".length()).trim();
                }
            } else if (!line.startsWith("#")) {
                if (current == null) current = new Channel();
                current.url = line;
                if (current.name.isEmpty()) current.name = nameFromUrl(line);
                channels.add(current);
                current = null;
            }
        }
        reader.close();
        return channels;
    }

    private static String attr(String text, String key) {
        String[] quotes = {"\"", "'"};
        for (String q : quotes) {
            String k = key + "=" + q;
            int idx = text.toLowerCase().indexOf(k.toLowerCase());
            if (idx >= 0) {
                int s = idx + k.length();
                int e = text.indexOf(q, s);
                if (e >= 0) return text.substring(s, e).trim();
            }
        }
        return "";
    }

    private static String nameFromUrl(String url) {
        try {
            String path = new URL(url).getPath();
            String[] parts = path.split("/");
            if (parts.length > 0) {
                String last = parts[parts.length - 1];
                int dot = last.lastIndexOf('.');
                if (dot > 0) last = last.substring(0, dot);
                return last.replace("-", " ").replace("_", " ");
            }
        } catch (Exception ignored) {}
        return "Channel";
    }

    public static Map<String, List<Channel>> group(List<Channel> channels) {
        Map<String, List<Channel>> map = new LinkedHashMap<>();
        for (Channel ch : channels) {
            String g = ch.group.isEmpty() ? "Genel" : ch.group;
            if (!map.containsKey(g)) map.put(g, new ArrayList<>());
            map.get(g).add(ch);
        }
        return map;
    }
}
