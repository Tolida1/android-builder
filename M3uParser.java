package PACKAGE_PLACEHOLDER;

import java.io.*;
import java.net.*;
import java.util.*;

/**
 * M3uParser — Tüm M3U formatlarını parse eder
 * Desteklenen:
 *  - #EXTM3U başlıklı listeler
 *  - #EXTINF satırları (tvg-name, tvg-logo, group-title)
 *  - #EXTVLCOPT:http-referrer ve http-origin
 *  - Uzantısız URL'ler (video formatına bağımsız)
 */
public class M3uParser {

    public static class Channel {
        public String name     = "";
        public String url      = "";
        public String logo     = "";
        public String group    = "";
        public String referer  = "";
        public String origin   = "";
        public Map<String,String> extra = new HashMap<>();

        public Map<String,Object> toMap() {
            Map<String,Object> m = new HashMap<>();
            m.put("name",   name);
            m.put("url",    url);
            m.put("logo",   logo);
            m.put("group",  group);
            m.put("referer",referer);
            m.put("origin", origin);
            return m;
        }
    }

    /** Parse from URL (runs in background) */
    public static List<Channel> parseFromUrl(String m3uUrl) throws Exception {
        URL url = new URL(m3uUrl);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent","VLC/3.0 LibVLC/3.0");
        BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
        return parseFromReader(reader);
    }

    /** Parse from raw string */
    public static List<Channel> parseFromString(String content) throws Exception {
        return parseFromReader(new BufferedReader(new StringReader(content)));
    }

    private static List<Channel> parseFromReader(BufferedReader reader) throws Exception {
        List<Channel> channels = new ArrayList<>();
        Channel current = null;
        String line;

        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;

            if (line.startsWith("#EXTM3U")) {
                // Header — skip
                continue;
            }

            if (line.startsWith("#EXTINF:")) {
                current = new Channel();
                parseExtInf(line, current);
                continue;
            }

            if (line.startsWith("#EXTVLCOPT:")) {
                if (current != null) parseVlcOpt(line, current);
                continue;
            }

            if (line.startsWith("#")) continue; // Other comments

            // URL line
            if (current == null) current = new Channel();
            current.url = line;
            if (current.name.isEmpty()) {
                // Extract name from URL
                current.name = extractNameFromUrl(line);
            }
            channels.add(current);
            current = null;
        }

        reader.close();
        return channels;
    }

    private static void parseExtInf(String line, Channel ch) {
        // Format: #EXTINF:-1 tvg-id="..." tvg-name="..." tvg-logo="..." group-title="...",Display Name
        int commaIdx = line.lastIndexOf(',');
        if (commaIdx >= 0 && commaIdx < line.length()-1) {
            ch.name = line.substring(commaIdx+1).trim();
        }

        // Parse attributes
        String attrs = commaIdx > 0 ? line.substring(0, commaIdx) : line;

        ch.logo  = extractAttr(attrs, "tvg-logo");
        ch.group = extractAttr(attrs, "group-title");

        String tvgName = extractAttr(attrs, "tvg-name");
        if (!tvgName.isEmpty() && ch.name.isEmpty()) ch.name = tvgName;
    }

    private static void parseVlcOpt(String line, Channel ch) {
        // #EXTVLCOPT:http-referrer=https://...
        // #EXTVLCOPT:http-origin=https://...
        String opt = line.substring("#EXTVLCOPT:".length()).trim();
        if (opt.startsWith("http-referrer=")) {
            ch.referer = opt.substring("http-referrer=".length()).trim();
        } else if (opt.startsWith("http-origin=")) {
            ch.origin = opt.substring("http-origin=".length()).trim();
        }
    }

    private static String extractAttr(String text, String attr) {
        // Try: attr="value" or attr='value'
        String[] quotes = {"\"", "'"};
        for (String q : quotes) {
            String key = attr + "=" + q;
            int start = text.toLowerCase().indexOf(key.toLowerCase());
            if (start >= 0) {
                start += key.length();
                int end = text.indexOf(q, start);
                if (end >= 0) return text.substring(start, end).trim();
            }
        }
        return "";
    }

    private static String extractNameFromUrl(String url) {
        try {
            String path = new URL(url).getPath();
            String[] parts = path.split("/");
            if (parts.length > 0) {
                String last = parts[parts.length-1];
                // Remove extension
                int dot = last.lastIndexOf('.');
                if (dot > 0) last = last.substring(0, dot);
                return last.replace("-","").replace("_"," ");
            }
        } catch(Exception ignored){}
        return "Channel";
    }

    /** Group channels by their group field */
    public static Map<String, List<Channel>> groupChannels(List<Channel> channels) {
        Map<String, List<Channel>> map = new LinkedHashMap<>();
        for (Channel ch : channels) {
            String g = ch.group.isEmpty() ? "Genel" : ch.group;
            if (!map.containsKey(g)) map.put(g, new ArrayList<>());
            map.get(g).add(ch);
        }
        return map;
    }
}

