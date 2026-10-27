using Toybox.Application;
using Toybox.WatchUi;

// Globals shared by the link and the views.
var gModel = null;   // Model
var gLink = null;    // NodeLink
var gSched = null;   // Sched (the app's one timer)

class MeckApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        gSched = new Sched();
        gModel = new Model();
        gLink = new NodeLink();
        gLink.start();
    }

    function onStop(state) {
        if (gLink != null) {
            gLink.shutdown();
        }
    }

    function getInitialView() {
        var v = new HomeView();
        return [v, new HomeDelegate(v)];
    }
}
