using Toybox.Application;
using Toybox.WatchUi;

// Global handle so the view's button delegate can reach the BLE logic.
var gBle = null;

class MeckSpikeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        gBle = new SpikeBle();
        gBle.start();
    }

    function onStop(state) {
        if (gBle != null) {
            gBle.shutdown();
        }
    }

    function getInitialView() {
        return [new SpikeView(), new SpikeInputDelegate()];
    }
}
