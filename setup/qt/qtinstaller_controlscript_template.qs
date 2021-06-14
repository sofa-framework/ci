// BASED ON https://github.com/appveyor/build-images/blob/master/scripts/Windows/install_qt.qs

// Emacs mode hint: -*- mode: JavaScript -*-
// https://stackoverflow.com/questions/25105269/silent-install-qt-run-installer-on-ubuntu-server
// https://github.com/wireshark/wireshark/blob/master/tools/qt-installer-windows.qs

// Look for Name elements in
// https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_5123/Updates.xml
// Unfortunately it is not possible to disable deps like qt.tools.qtcreator

// Parameters (must be surrounded by underscores):
// QTVERSION (e.g: 5.12.6) -> _QTVERSION_
// QTCOMPILER (e.g: gcc_64, win64_msvc2017_64) -> _QTCOMPILER_
// QTINSTALLDIR (e.g: "/opt/Qt", "C:\\Qt") -> _QTINSTALLDIR_


var INSTALL_COMPONENTS = [
    "qt.qt5._QTVERSION_._QTCOMPILER_",
    "qt.qt5._QTVERSION_.qtcharts",
    "qt.qt5._QTVERSION_.qtcharts._QTCOMPILER_",
    "qt.qt5._QTVERSION_.qtwebengine",
    "qt.qt5._QTVERSION_.qtwebengine._QTCOMPILER_"
]


function dump_var(v) {
    switch (typeof v) {
        case "object":
            for (var i in v) {
                console.log(i+":"+v[i]);
            }
            break;
        default: //number, string, boolean, null, undefined
            console.log(typeof v+":"+v);
            break;
    }
}

function Controller() {
    installer.autoRejectMessageBoxes();
    installer.setMessageBoxAutomaticAnswer("OverwriteTargetDirectory", QMessageBox.Yes);
    installer.setMessageBoxAutomaticAnswer("stopProcessesForUpdates", QMessageBox.Ignore);

    installer.setAutoAcceptLicenses();

    installer.installationFinished.connect(function() {
        gui.clickButton(buttons.NextButton, 2000);
    })
}

Controller.prototype.WelcomePageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    // click delay here because the next button is initially disabled for ~1 second
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.CredentialsPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.IntroductionPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ObligationsPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    var page = gui.pageWidgetByObjectName("ObligationsPage");
    page.obligationsAgreement.setChecked(true);

    var nameEdit = gui.findChild(page, "CompanyName")
    if (nameEdit) {
        nameEdit.text = "SOFA Framework"
    }
    // Or alternatively:
    // var individualCheckbox = gui.findChild(page, "IndividualPerson")
    // if (individualCheckbox) {
    //     individualCheckbox.checked = true;
    // }

    page.completeChanged();
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.DynamicTelemetryPluginFormCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.currentPageWidget().TelemetryPluginForm.statisticGroupBox.disableStatisticRadioButton.setChecked(true);
    gui.clickButton(buttons.NextButton, 2000);

    //for(var key in widget.TelemetryPluginForm.statisticGroupBox){
    //    console.log(key);
    //}
}

Controller.prototype.TargetDirectoryPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.currentPageWidget().TargetDirectoryLineEdit.setText("_QTINSTALLDIR_");
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ComponentSelectionPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
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
    console.log("Step: " + gui.currentPageWidget());
    gui.currentPageWidget().AcceptLicenseCheckBox.setChecked(true);
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.StartMenuDirectoryPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.ReadyForInstallationPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    gui.clickButton(buttons.NextButton, 2000);
}

Controller.prototype.FinishedPageCallback = function() {
    console.log("Step: " + gui.currentPageWidget());
    var checkBoxForm = gui.currentPageWidget().LaunchQtCreatorCheckBoxForm;
    if (checkBoxForm && checkBoxForm.launchQtCreatorCheckBox) {
        checkBoxForm.launchQtCreatorCheckBox.checked = false;
    }
    gui.clickButton(buttons.FinishButton, 2000);
}
