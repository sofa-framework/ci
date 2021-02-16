// BASED ON https://github.com/appveyor/build-images/blob/master/scripts/Windows/install_qt.qs

// Emacs mode hint: -*- mode: JavaScript -*-
// https://stackoverflow.com/questions/25105269/silent-install-qt-run-installer-on-ubuntu-server
// https://github.com/wireshark/wireshark/blob/master/tools/qt-installer-windows.qs

// Look for Name elements in
// https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_5123/Updates.xml
// Unfortunately it is not possible to disable deps like qt.tools.qtcreator

var INSTALL_COMPONENTS = [
    "qt.qt5._QTVERSION_.gcc_64",
    "qt.qt5._QTVERSION_.qtcharts",
    "qt.qt5._QTVERSION_.qtcharts.gcc_64",    
    "qt.qt5._QTVERSION_.qtwebengine",
    "qt.qt5._QTVERSION_.qtwebengine.gcc_64"
]


function Controller() {
    installer.autoRejectMessageBoxes();
    installer.installationFinished.connect(function() {
        gui.clickButton(buttons.NextButton, 2000);
    })
}

Controller.prototype.WelcomePageCallback = function() {
    // click delay here because the next button is initially disabled for ~1 second
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.CredentialsPageCallback = function() {
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.IntroductionPageCallback = function() {
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ObligationsPageCallback = function() {
    var page = gui.pageWidgetByObjectName("ObligationsPage");
    page.obligationsAgreement.setChecked(true);
    page.completeChanged();
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.DynamicTelemetryPluginFormCallback = function() {
    gui.currentPageWidget().TelemetryPluginForm.statisticGroupBox.disableStatisticRadioButton.setChecked(true);
    gui.clickButton(buttons.NextButton, 2000);

    //for(var key in widget.TelemetryPluginForm.statisticGroupBox){
    //    console.log(key);
    //}
}

Controller.prototype.TargetDirectoryPageCallback = function()
{
    gui.currentPageWidget().TargetDirectoryLineEdit.setText("_QT_INSTALLDIR_");
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ComponentSelectionPageCallback = function() {

    // https://doc-snapshots.qt.io/qtifw-3.1/noninteractive.html
    var page = gui.pageWidgetByObjectName("ComponentSelectionPage");

    var archiveCheckBox = gui.findChild(page, "Archive");
    var latestCheckBox = gui.findChild(page, "Latest releases");
    var fetchButton = gui.findChild(page, "FetchCategoryButton");

    if(archiveCheckBox) archiveCheckBox.click();
    if(latestCheckBox) latestCheckBox.click();
    if(fetchButton) fetchButton.click();

    var widget = gui.currentPageWidget();

    widget.deselectAll();

    for (var i = 0; i < INSTALL_COMPONENTS.length; i++) {
        widget.selectComponent(INSTALL_COMPONENTS[i]);
    }

    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.LicenseAgreementPageCallback = function() {
    gui.currentPageWidget().AcceptLicenseRadioButton.setChecked(true);
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.StartMenuDirectoryPageCallback = function() {
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ReadyForInstallationPageCallback = function()
{
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.FinishedPageCallback = function() {
var checkBoxForm = gui.currentPageWidget().LaunchQtCreatorCheckBoxForm;
if (checkBoxForm && checkBoxForm.launchQtCreatorCheckBox) {
    checkBoxForm.launchQtCreatorCheckBox.checked = false;
}
    gui.clickButton(buttons.FinishButton, 2000);
}
