{ CompositeDisposable, Disposable } = require "atom"
packageDeps = require "atom-package-deps"
path = require "path"
os = require "os"
fs = require "fs"
childProcess = require "child_process"

SidebarView = require "./sidebar-view"
OutputView = require "./output-view"
Controller = require "./controller"
ViewManager = require "./view-manager"
Downloader = require "./downloader"
{SIDEBAR_VIEW, OUTPUT_VIEW, FORMATTED_OUTPUT_VIEW} = require "./constants"

module.exports=
  subscriptions: null
  activeProject: null
  viewManager: new ViewManager @activeProject
  toolBarButtons: {}
  messageQueue: []

  activate: ->
    containerDir = path.join os.homedir(), ".tessla-env"
    imageDir = path.join path.dirname(__dirname), "docker-image"

    unless atom.config.get("tessla2.alreadySetUpDockerContainer") is yes
      Downloader.download
        url: "http://rv.isp.uni-luebeck.de/tessla/tessla2-docker.zip"
        filePath: path.join imageDir, "tessla-docker.zip"
        callback: ->

    packageDeps.install("tessla2").catch (error) ->
      notifications.addError "Could not start TeSSLa package",
        detail: "Package dependencies could not be installed. The package was not started because the TeSSLa package will not run properly without this dependencies.\n#{error.message}"
      return

    # set up container directory
    fs.stat containerDir, (err, stats) =>
      if err?.code is "ENOENT"
        fs.mkdir containerDir, =>
          # create container directory
          @messageQueue.push type: "command", msg: "mkdir #{containerDir}"

          # create build directory in container directory
          fs.mkdir path.join(containerDir, "build"), =>
            @messageQueue.push type: "command", msg: "mkdir #{path.join containerDir, "build"}";

            # start docker tessla container
            dockerArgs = ["run", "--volume", "#{containerDir}:/tessla", "-w", "/tessla", "-tid", "--name", "tessla", "tessla", "sh"]
            childProcess.spawn "docker", dockerArgs

            # log command
            @messageQueue.push type: "Docker", msg: "docker #{dockerArgs.join " "}"

      else
        # if file exists just start docker
        dockerArgs = ["run", "--volume", "#{containerDir}:/tessla", "-w", "/tessla", "-tid", "--name", "tessla", "tessla", "sh"];
        childProcess.spawn "docker", dockerArgs

        # log command
        @messageQueue.push type: "Docker", msg: "docker #{dockerArgs.join " "}"

    # create view manager
    @subscriptions = new CompositeDisposable
    controller = new Controller @viewManager

    @subscriptions.add atom.commands.add "atom-workspace",
      "tessla2:toggle": => @toggle()
      "tessla2:set-up-split-view": => @viewManager.setUpSplitView()
      "tessla2:build-and-run-c-code": => controller.onCompileAndRunCCode()
      "tessla2:build-c-code": => controller.onBuildCCode buildAssembly: no
      "tessla2:run-c-code": => controller.onRunBinary {}
      "tessla2:stop-current-process": => controller.onStopRunningProcess()
      "tessla2:build-and-run-project": => controller.onCompileAndRunProject()
      "tessla2:reset-view": => @viewManager.restoreViews()

    @subscriptions.add atom.workspace.addOpener (URI) ->
      switch URI
        when SIDEBAR_VIEW          then new SidebarView title: "Functions", URI: SIDEBAR_VIEW
        when FORMATTED_OUTPUT_VIEW then new OutputView title: "Formatted output", URI: FORMATTED_OUTPUT_VIEW

    @subscriptions.add new Disposable ->
      atom.workspace.getPaneItems().forEach (item) ->
        if item instanceof SidebarView or item instanceof OutputView
          item.destroy()

  deactivate: ->
    @subscriptions.dispose()
    console.log "docker rm -f tessla"
    childProcess.spawnSync "docker", ["rm", "-f", "tessla"]

  toggle: ->
    activeEditor = null

    atom.workspace.getTextEditors().forEach (editor) ->
      activeEditor = editor if atom.views.getView(editor).offsetParent?

    @viewManager.activeProject.setProjPath path.dirname activeEditor.getPath() if activeEditor?

    Promise.all([
      atom.workspace.toggle(FORMATTED_OUTPUT_VIEW),
      atom.workspace.toggle(SIDEBAR_VIEW),
    ]).then (views) =>
      viewsContainer = {}
      viewsContainer.unknown = []

      views.forEach (view) ->
        switch view?.getURI()
          when SIDEBAR_VIEW then viewsContainer.sidebarViews = view
          when FORMATTED_OUTPUT_VIEW then viewsContainer.formattedOutputView = view
          else viewsContainer.unknown.push view

      @viewManager.connectViews viewsContainer

  consumeFlexiblePanels: (flexiblePanelsManager) ->
    logCols = [
        name: "Type", align: "center", fixedWidth: 70, type: "label"
      ,
        name: "Description", indentWrappedText: yes
      ,
        name: "Time", align: "center", fixedWidth: 95, type: "time"
    ]

    cols = [
        name: "Description", type: "text"
      ,
        name: "Time", align: "center", fixedWidth: 95, type: "time"
    ]

    logLbls = [
        type: "command", background: "#F75D59", color: "#FFF"
      ,
        type: "message", background: "#3090C7", color: "#FFF"
      ,
        type: "Docker", background: "#8E5287", color: "#FFF"
      ,
        type: "TeSSLa RV", background: "#5BB336", color: "#FFF"
    ]

    Promise.all([
      flexiblePanelsManager.createFlexiblePanel
        title: "Console"
        columns: cols
        useMonospaceFont: yes
        hideTableHead: yes
        hideCellBorders: yes
      flexiblePanelsManager.createFlexiblePanel
        title: "Errors (C)"
        columns: cols
        useMonospaceFont: yes
        hideTableHead: yes
      flexiblePanelsManager.createFlexiblePanel
        title: "Errors (TeSSLa)"
        columns: cols
        useMonospaceFont: yes
        hideTableHead: yes
      flexiblePanelsManager.createFlexiblePanel
        title: "Warnings"
        columns: cols
        useMonospaceFont: yes
        hideTableHead: yes
      flexiblePanelsManager.createFlexiblePanel
        title: "Log"
        columns: logCols
        labels: logLbls
        useMonospaceFont: yes
    ]).then (views) =>
      viewsContainer = {}
      viewsContainer.unknown = []

      views.forEach (view) ->
        switch view?.getTitle()
          when "Console" then viewsContainer.consoleView = view
          when "Errors (C)" then viewsContainer.errorsCView = view
          when "Errors (TeSSLa)" then viewsContainer.errorsTeSSLaView = view
          when "Warnings" then viewsContainer.warningsView = view
          when "Log" then viewsContainer.logView = view
          else viewsContainer.unknown.push view

      @viewManager.connectViews viewsContainer
      @viewManager.addIconsToTabs()
      @viewManager.setUpSplitView()

      @messageQueue.forEach (element) ->
        viewsContainer.logView.addEntry [element.type, element.msg]

      @messageQueue = []

  consumeToolBar: (getToolBar) ->
    toolBar = getToolBar "tessla2"

    @toolBarButtons.BuildAndRunCCode = toolBar.addButton
      icon: "play-circle"
      callback: "tessla2:build-and-run-c-code"
      tooltip: "Builds and runs C code from project directory"
      iconset: "fa"

    @toolBarButtons.BuildCCode = toolBar.addButton
      icon: "gear-a"
      callback: "tessla2:build-c-code"
      tooltip: "Builds the C code of this project into a binary"
      iconset: "ion"

    @toolBarButtons.RunCCode = toolBar.addButton
      icon: "play"
      callback: "tessla2:run-c-code"
      tooltip: "Runs the binaray compiled from C code"
      iconset: "ion"

    toolBar.addSpacer()

    @toolBarButtons.BuildAndRunProject = toolBar.addButton
      icon: "ios-circle-filled"
      callback: "tessla2:build-and-run-project"
      tooltip: "Builds and runs C code and analizes runtime behavior"
      iconset: "ion"

    toolBar.addSpacer()

    @toolBarButtons.Stop = toolBar.addButton
      icon: "android-checkbox-blank"
      callback: "tessla2:stop-current-process"
      tooltip: "Stops the process that is currently running"
      iconset: "ion"
    @toolBarButtons.Stop.setEnabled no

    toolBar.addSpacer()

    toolBar.addButton
      icon: "columns"
      callback: "tessla2:set-up-split-view"
      tooltip: "Set up split view"
      iconset: "fa"

    @toolBarButtons.showLog = toolBar.addButton
      icon: "window-maximize"
      callback: "tessla2:reset-view"
      tooltip: "Restore all view Components"
      iconset: "fa"

    @viewManager.connectBtns @toolBarButtons

    atom.config.set "tool-bar.iconSize", "16px"
    atom.config.set "tool-bar.position", "Right"


  config:
    variableValueFormatting:
      type: "string"
      default: "variable_values:%m %d(%s) %us%n"
      order: 1
      title: "zlog string format for variables"
      description: "This setting will format the output of variables in the trace file"
    functionCallFormatting:
      type: "string"
      default: "function_calls:%m nil %d(%s) %us%n"
      order: 2
      title: "zlog string format for function calls"
      description: "This setting will format the output of function calls in the trace file."
    animationSpeed:
      type: "integer"
      default: 200
      order: 3
      title: "Animation speed"
      description: "This will set the speed of animations used in this package. The time is represented in milliseconds."
    alreadySetUpDockerContainer:
      type: "boolean"
      default: no
      order: 4
      title: "Docker already set up?"
      description: "This flag is set to true if the docker container is already set up otherwise it will be set to false."
