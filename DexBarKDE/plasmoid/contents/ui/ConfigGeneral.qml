import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: configPage

    property alias cfg_username: usernameField.text
    property alias cfg_password: passwordField.text
    property alias cfg_useMmol: mmolCheckbox.checked
    property alias cfg_enableAlerts: alertsCheckbox.checked
    property alias cfg_alertHighMgdl: highAlertSpin.value
    property alias cfg_alertLowMgdl: lowAlertSpin.value
    property alias cfg_alertUrgentHighMgdl: urgentHighSpin.value
    property alias cfg_alertUrgentLowMgdl: urgentLowSpin.value
    property string cfg_region

    Kirigami.FormLayout {

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Dexcom Account"
        }

        QQC2.TextField {
            id: usernameField
            Kirigami.FormData.label: "Username:"
            placeholderText: "Dexcom Share username"
        }

        QQC2.TextField {
            id: passwordField
            Kirigami.FormData.label: "Password:"
            echoMode: TextInput.Password
            placeholderText: "Dexcom Share password"
        }

        QQC2.ComboBox {
            id: regionCombo
            Kirigami.FormData.label: "Region:"
            model: ["US", "Outside US", "Japan"]
            currentIndex: model.indexOf(cfg_region) >= 0 ? model.indexOf(cfg_region) : 0
            onCurrentTextChanged: cfg_region = currentText
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Display"
        }

        QQC2.CheckBox {
            id: mmolCheckbox
            Kirigami.FormData.label: "Units:"
            text: "Use mmol/L"
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Alerts"
        }

        QQC2.CheckBox {
            id: alertsCheckbox
            Kirigami.FormData.label: "Alerts:"
            text: "Enable glucose alerts (15-minute cooldown)"
        }

        QQC2.SpinBox {
            id: urgentLowSpin
            Kirigami.FormData.label: "Urgent Low (mg/dL):"
            from: 40; to: 80; stepSize: 1
            enabled: alertsCheckbox.checked
        }

        QQC2.SpinBox {
            id: lowAlertSpin
            Kirigami.FormData.label: "Low (mg/dL):"
            from: 50; to: 120; stepSize: 1
            enabled: alertsCheckbox.checked
        }

        QQC2.SpinBox {
            id: highAlertSpin
            Kirigami.FormData.label: "High (mg/dL):"
            from: 140; to: 280; stepSize: 1
            enabled: alertsCheckbox.checked
        }

        QQC2.SpinBox {
            id: urgentHighSpin
            Kirigami.FormData.label: "Urgent High (mg/dL):"
            from: 180; to: 400; stepSize: 1
            enabled: alertsCheckbox.checked
        }

        Kirigami.Separator {}

        QQC2.Label {
            text: "Note: credentials are stored in your Plasma configuration.\nConsider using a Dexcom Share-only account."
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
