import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.private.mpris as Mpris
import org.kde.taskmanager as TaskManager

import "../code/format.js" as Format
import "../code/mode.js" as Mode
import "../code/measure.js" as Measure

PlasmoidItem {
    id: root

    // Widget properties
    property string mediaText: ""
    property string activePlayer: ""
    property string playerIdentity: ""
    property int padding: 20
    property int visualizerGutter: 48
    property int minWidth: 120
    property int maxWidth: 650
    property int fixedHeight: 48
    property string uiFont: "Adwaita Sans, Source Sans 3, Noto Sans, sans-serif"
    property string idleGreeting: "Hello, Arvin!"
    property int playerPid: 0

    property real animatedWidth: 200
    property real lastTargetWidth: -1
    // Smoothed LLM pill suffix — avoids choppy width from tok/s flicker
    property real pillLlmTps: 0
    property string pillLlmPhase: "idle" // idle | processing
    property string pillLlmModel: ""
    // Staged text: grow expands first, then commits; shrink commits text first
    property string visibleDisplayText: ""
    property string pendingDisplayText: ""
    property bool awaitingGrowCommit: false

    // v1.3 structured caches
    property var sysData: ({})
    property var mediaData: ({})
    property var installData: ({})
    property var llmData: ({})
    property string userSticky: ""
    property color accentGreen: "#3DDC97"

    readonly property bool mediaModeActive: {
        // Live MPRIS wins; paused/stopped leaves media mode until play resumes
        var player = mpris2Model.currentPlayer
        if (player)
            return player.playbackStatus === Mpris.PlaybackStatus.Playing
        return !!(mediaData && mediaData.playing === true)
    }
    readonly property bool installModeActive: {
        if (!installData || !installData.action || installData.action === "none") {
            return isInstalling || isUninstalling || isInstalled || isUninstalled
        }
        var completedAt = Number(installData.completed_at || 0)
        if (completedAt > 0) {
            var now = Date.now() / 1000
            return (now - completedAt) <= 5
        }
        return true
    }
    readonly property bool llmModeActive: !!(llmData && (llmData.model || llmData.loaded))

    readonly property string defaultPriority:
        Mode.defaultPriority(installModeActive, mediaModeActive, llmModeActive)

    readonly property string priorityMode:
        Mode.resolvePriority(userSticky, installModeActive, mediaModeActive, llmModeActive, defaultPriority)

    function setPriority(mode) { userSticky = mode }

    // Activation delegates to AppActivation (which owns the exec + task-matching
    // logic). These stay on the root because IslandPill and AppletCard call them
    // through `islandRoot.activate…()`.
    function activateSystemMonitor() { appActivation.activateSystemMonitor() }
    function activateMediaPlayer() { appActivation.activateMediaPlayer() }
    function activateLlmRunner() { appActivation.activateLlmRunner() }
    function activateInstallTerminal() { appActivation.activateInstallTerminal() }

    // Structured install action from JSON
    readonly property string installAction: {
        if (installData && installData.action && installData.action !== "none")
            return String(installData.action).toLowerCase()
        return ""
    }

    property bool isInstalling: {
        if (installAction.indexOf("install") >= 0 && installAction.indexOf("installed") < 0)
            return true
        if (installAction.indexOf("download") >= 0)
            return true
        return false
    }
    property bool isUninstalling: {
        if (installAction.indexOf("remov") >= 0 || installAction.indexOf("uninstall") >= 0)
            return true
        return false
    }
    property bool isInstalled: installAction === "installed"
    property bool isUninstalled: installAction === "removed"

    property bool isSystemActive: isInstalling || isUninstalling
    property bool isSystemCompleted: isInstalled || isUninstalled

    // Visualizer only when the pill is actually showing media (not install/llm)
    property bool isMediaOnly: mediaModeActive && priorityMode === "media"
        && !isSystemActive && !isSystemCompleted

    property bool hasMedia: mediaModeActive && mediaText !== ""
    property bool hasStatus: installModeActive || llmModeActive
    property bool hasContent: hasMedia || hasStatus || installModeActive || llmModeActive
        || priorityMode === "system"
    property bool isDefaultState: priorityMode === "idle" && !hasMedia && !installModeActive && !llmModeActive

    // Desired label (may wait for grow animation before becoming visible)
    readonly property string desiredDisplayText: getDisplayText()

    // Home directory (shared by the poller + activation components)
    property string homeDirectory: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString().replace("file://", "")

    // Show widget when there's content OR in default state
    visible: hasContent || isDefaultState

    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.preferredWidth: animatedWidth
    Layout.preferredHeight: fixedHeight
    Layout.minimumWidth: minWidth
    Layout.maximumWidth: maxWidth
    Layout.minimumHeight: fixedHeight
    Layout.maximumHeight: fixedHeight

    width: animatedWidth
    height: fixedHeight

    // Panel shows the pill; hover opens fullRepresentation as a popup beyond the bar
    preferredRepresentation: compactRepresentation
    // Keep full rep in popup (never squeeze into panel)
    switchWidth: 10000
    switchHeight: 10000
    activationTogglesExpanded: false
    hideOnWindowDeactivate: false
    // Transparent Plasma popup — floating cards provide their own color
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function openExpanded() {
        collapseGraceTimer.stop()
        expanded = true
    }

    function scheduleCollapse() {
        collapseGraceTimer.restart()
    }

    function cancelCollapse() {
        collapseGraceTimer.stop()
    }

    Timer {
        id: collapseGraceTimer
        interval: 400
        repeat: false
        onTriggered: root.expanded = false
    }

    readonly property int widthAnimMs: 520

    Timer {
        id: contentTransitionTimer
        interval: 90
        repeat: false
        onTriggered: root.runContentTransition()
    }

    // After grow animation finishes, commit the new text
    Timer {
        id: growCommitTimer
        interval: root.widthAnimMs
        repeat: false
        onTriggered: root.commitGrowText()
    }

    // Measure unconstrained text (same font as the label) — always the *desired* string
    TextMetrics {
        id: widthMetrics
        text: root.desiredDisplayText
        font.family: root.uiFont
        font.pixelSize: 14
        font.weight: Font.Medium
        font.letterSpacing: 0.3

        onWidthChanged: root.scheduleContentTransition()
        onTextChanged: root.scheduleContentTransition()
    }

    // Probe for stable LLM width (processing ↔ tok/s shouldn't resize the pill)
    TextMetrics {
        id: llmWidthProbe
        font.family: root.uiFont
        font.pixelSize: 14
        font.weight: Font.Medium
        font.letterSpacing: 0.3
    }

    Behavior on animatedWidth {
        id: widthBehavior
        enabled: true
        NumberAnimation {
            duration: root.widthAnimMs
            easing.type: Easing.InOutCubic
        }
    }

    function measureDisplayText(str) {
        llmWidthProbe.text = str || ""
        return llmWidthProbe.width
    }

    function widthForDisplayText(displayText) {
        return Measure.widthForDisplayText(displayText, {
            measure: root.measureDisplayText,
            priorityMode: priorityMode,
            pillLlmModel: pillLlmModel,
            pillLlmPhase: pillLlmPhase,
            isDefaultState: isDefaultState,
            padding: padding,
            visualizerGutter: visualizerGutter,
            isMediaOnly: isMediaOnly,
            minWidth: minWidth,
            maxWidth: maxWidth
        })
    }

    function calculateTargetWidth() {
        return widthForDisplayText(desiredDisplayText)
    }

    function scheduleContentTransition() {
        if (!contentTransitionTimer)
            return
        contentTransitionTimer.restart()
    }

    function scheduleIslandWidthSync() {
        scheduleContentTransition()
    }

    function commitVisibleText(text) {
        if (visibleDisplayText === text)
            return
        visibleDisplayText = text
    }

    function commitGrowText() {
        if (!awaitingGrowCommit)
            return
        awaitingGrowCommit = false
        commitVisibleText(pendingDisplayText)
    }

    function runContentTransition() {
        var next = desiredDisplayText
        pendingDisplayText = next
        var target = widthForDisplayText(next)

        var grow = target > animatedWidth + 12
        var shrink = target < animatedWidth - 12

        if (grow) {
            // Expand first, keep old text until width lands
            awaitingGrowCommit = true
            lastTargetWidth = target
            animatedWidth = target
            if (growCommitTimer)
                growCommitTimer.restart()
            return
        }

        // Shrink or same-size: text first, then width (shrink path you like)
        awaitingGrowCommit = false
        if (growCommitTimer)
            growCommitTimer.stop()
        commitVisibleText(next)

        if (!shrink && Math.abs(target - lastTargetWidth) < 12 && Math.abs(target - animatedWidth) < 12)
            return
        lastTargetWidth = target
        animatedWidth = target
    }

    function syncIslandWidth() { scheduleContentTransition() }

    onMediaTextChanged: scheduleContentTransition()
    onIsMediaOnlyChanged: scheduleContentTransition()
    onIsDefaultStateChanged: scheduleContentTransition()
    onDesiredDisplayTextChanged: scheduleContentTransition()
    onPriorityModeChanged: scheduleContentTransition()
    onPillLlmPhaseChanged: scheduleContentTransition()
    onPillLlmTpsChanged: scheduleContentTransition()

    // Initialization log
    Timer {
        id: initTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            console.log("=== Enhanced Dynamic Island Initialized ===")
            console.log("Media:", mediaText)
            console.log("Size:", width + "x" + height)
        }
    }

    TaskManager.TasksModel {
        id: tasks2Model
        filterByVirtualDesktop: false
        filterByActivity: false
        filterMinimized: false
        filterHidden: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    // Plasma 6 MPRIS (replaces removed plasma5support mpris2 dataengine)
    Mpris.Mpris2Model {
        id: mpris2Model
    }

    // JSON-cache + MPRIS ingestion (writes onto this root)
    DataPoller {
        id: dataPoller
        islandRoot: root
        mprisModel: mpris2Model
        homeDirectory: root.homeDirectory
    }

    // Click-to-focus activation (reads root state + models)
    AppActivation {
        id: appActivation
        islandRoot: root
        tasksModel: tasks2Model
        mprisModel: mpris2Model
        homeDirectory: root.homeDirectory
    }

    /// Apple-Quality Dynamic Island Visual Shell
    /// Enhanced for luxury, precision, depth, and animation
    compactRepresentation: IslandPill {
        islandRoot: root
    }

    // Popup hugs the cards. Plasma's AppletPopup persists popupHeight/popupWidth
    // from the last hide; Layout.maximumHeight must match the stack or the shell
    // keeps the old taller window (empty grey band above the cards).
    fullRepresentation: Item {
        id: expandedContainer

        readonly property int contentH: expandedView.implicitHeight

        implicitWidth: 420
        implicitHeight: contentH
        Layout.minimumWidth: 400
        Layout.preferredWidth: 420
        Layout.maximumWidth: 420
        Layout.minimumHeight: contentH
        Layout.preferredHeight: contentH
        Layout.maximumHeight: contentH

        width: 420
        height: contentH

        // Cover the whole popup so moving from the pill onto empty chrome still
        // counts as hovering. acceptedButtons is none so cards keep their clicks.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: root.cancelCollapse()
            onExited: root.scheduleCollapse()
        }

        ExpandedView {
            id: expandedView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            islandRoot: root
        }
    }

    // Display logic delegates to the pure mode.js builder; the data object is read
    // inside this binding so reactivity stays on the root.
    function getDisplayText() {
        return Mode.getDisplayText(priorityMode, {
            installData: installData,
            mediaData: mediaData,
            mediaText: mediaText,
            llmData: llmData,
            pillLlmModel: pillLlmModel,
            pillLlmPhase: pillLlmPhase,
            pillLlmTps: pillLlmTps,
            sysData: sysData,
            userSticky: userSticky,
            idleGreeting: idleGreeting,
            formatMediaText: Format.formatMediaText
        })
    }

    Component.onCompleted: {
        console.log("=== Enhanced Dynamic Island Widget Initialized ===")
        console.log("Home directory:", homeDirectory)

        dataPoller.syncMprisPlayer()

        visibleDisplayText = desiredDisplayText
        pendingDisplayText = desiredDisplayText
        lastTargetWidth = widthForDisplayText(desiredDisplayText)
        animatedWidth = lastTargetWidth
        syncIslandWidth()
    }
}
