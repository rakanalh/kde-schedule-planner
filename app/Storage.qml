/*
 * Storage — same read/write strategy as the plasmoid (Plasma5Support
 * executable engine; `cat` to read, base64 to write), but this copy lives
 * with the app and imports the sibling schedule.js.
 */
import QtQuick
import Qt.labs.platform as Platform
import org.kde.plasma.plasma5support as P5
import "schedule.js" as Sched

Item {
    id: storage

    // ~/.config/myschedule — lives under config so it can go in a dotfiles repo
    readonly property string dirPath:
        Platform.StandardPaths.writableLocation(Platform.StandardPaths.GenericConfigLocation)
            .toString().replace("file://", "") + "/myschedule"
    readonly property string filePath: dirPath + "/schedule.json"

    signal loaded(var schedule)
    signal saveDone(bool ok)
    signal parseError(string message)

    property var _callbacks: ({})
    property int _nonce: 0

    P5.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            var cb = storage._callbacks[source];
            delete storage._callbacks[source];
            exec.disconnectSource(source);
            if (cb) cb(data);
        }
    }

    function _run(cmd, cb) {
        storage._nonce += 1;
        var unique = cmd + " # " + storage._nonce;
        storage._callbacks[unique] = cb;
        exec.connectSource(unique);
    }

    function _shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function load() {
        _run("mkdir -p " + _shq(dirPath) + " && cat " + _shq(filePath) + " 2>/dev/null",
             function (data) {
                 var raw = (data["stdout"] || "").trim();
                 var obj = {};
                 if (raw.length > 0) {
                     try {
                         obj = JSON.parse(raw);
                     } catch (e) {
                         storage.parseError("Could not parse schedule.json: " + e);
                         obj = {};
                     }
                 }
                 storage.loaded(Sched.normalize(obj));
             });
    }

    function save(schedule) {
        var payload = JSON.stringify(Sched.normalize(schedule), null, 2);
        var b64 = Qt.btoa(payload);
        _run("mkdir -p " + _shq(dirPath) + " && printf %s " + _shq(b64)
             + " | base64 -d > " + _shq(filePath),
             function (data) {
                 storage.saveDone(data["exit code"] === 0);
             });
    }
}
