path = require("path")

module.exports=
  class SidebarViewElement

    constructor: ({ name: name, file: file, line: line, column: col, observed: o, exists: e, path: p, spec: spec }) ->
      @projectPath = p
      observed = o ? no
      exists = e ? no

      itemWrapper = document.createElement "li"
      itemWrapper.classList.add "list-item", "function-wrapper"

      addBtn = document.createElement "a"
      addBtn.classList.add "ion-plus-circled"

      fxLabel = document.createElement("span");
      fxLabel.classList.add "text-info" if observed
      fxLabel.classList.add "text-success" if not observed and exists

      unless exists or observed
        fxLabel.classList.add "text-error"
        addBtn.classList.add "icon-invisible", "cursor-default"

      fxLabel.innerHTML = "f(x)"

      fxName = document.createElement "span"
      fxName.classList.add "cursor-pointer"
      fxName.innerHTML = name

      itemWrapper.appendChild addBtn
      itemWrapper.appendChild fxLabel
      itemWrapper.appendChild fxName

      unless line is "" or col is ""
        lineCol = document.createElement "span"
        lineCol.classList.add "align-right", "itshape", "subtle"
        lineCol.innerHTML = "#{file} (l#{line}:c#{col})"
        itemWrapper.appendChild lineCol

      @element = itemWrapper

      fxName.addEventListener "click", (event) =>
        @onShowFunction file, line, col

      addBtn.addEventListener "click", (event) =>
        @onAddTest
          file: file
          functionName: name
          projectPath: p
          spec: spec
        , event


    onClick: (self) ->
      if self.classList.contains "collapsed"
        self.classList.remove "collapsed"
      else
        self.classList.add "collapsed"


    onShowFunction: (file, line, column) ->
      atom.workspace.open(path.join(@projectPath, file), {
        split: "left",
        searchAllPanes: yes,
        initialLine: parseInt(line) - 1,
        initialColumn: parseInt(column) - 1
      })


    onAddTest: ({ file, functionName, projectPath, spec }, event) ->
      atom.workspace.open(spec, { split: "right", searchAllPanes: yes }).then (editor) ->
        editor.setCursorBufferPosition [editor.getLineCount(), 0]

        text  = "\n# Trace function calls for #{functionName}"
        text += "\ndef calls_#{functionName}: Events[Unit] := function_call(\"#{functionName}\")"

        editor.save() if editor.insertText text, { select: yes, autoIndent: yes }

      event.preventDefault()
      event.stopPropagation()
