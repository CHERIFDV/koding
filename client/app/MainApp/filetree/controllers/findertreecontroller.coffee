###
todo:

  - fix dimmed/selected states

###

class NFinderTreeController extends JTreeViewController

  constructor:->
    
    super
    
    if @getOptions().contextMenu
      @contextMenuController = new NFinderContextMenuController

      @listenTo 
        KDEventTypes       : "ContextMenuItemClicked"
        listenedToInstance : @contextMenuController
        callback           : (pubInst, {fileView, contextMenuItem})=>
          @contextMenuItemSelected fileView, contextMenuItem
    else
      @getView().setClass "no-context-menu"

    # @listenTo 
    #   KDEventTypes       : "WindowChangeKeyView"
    #   listenedToInstance : @getSingleton("windowController")
    #   callback           : (windowController, {view})=>
    #     dimmed = yes
    #     for listController in @listControllers
    #       if view is listController.getView()
    #         dimmed = no
    #       
    #     if dimmed
    #       node.setClass "dimmed" for node in @selectedNodes
    # @setFSListeners()

  addNode:(nodeData)->
    
    o = @getOptions()
    return if o.foldersOnly and nodeData.type is "file"
    # @setFileListeners nodeData if o.fsListeners
    item = super nodeData

  setItemListeners:(pubInst, node)->
    
    super

    # node.on "folderNeedsToRefresh", (path)=>
    # 
    #   log @nodes, @nodes[path], path
    # # 
    # # file.on "fs.saveAs.finished", (newFile, oldFile)=>
    # 
    #   log "fs.saveAs.finished", "+>>>>>"
    #   
    #   parentNode = @nodes[path]
    #   if parentNode
    #     if parentNode.expanded
    #       @refreshFolder @nodes[path], =>
    #         @selectNode @nodes[path]
    #     else
    #       @expandFolder @nodes[parentPath], =>
    #         @selectNode @nodes[path]
    
    # file.on "fs.remotefile.created", (oldPath)=>
    #   tc = @treeController
    #   parentNode = tc.nodes[file.parentPath]
    # 
    #   if parentNode
    #     if parentNode.expanded
    #       tc.refreshFolder tc.nodes[file.parentPath], ->
    #         tc.selectNode tc.nodes[file.path]
    #     else
    #       tc.expandFolder tc.nodes[file.parentPath], ->
    #         tc.selectNode tc.nodes[file.path]
    #   log "removed", oldPath
    #   delete @aceViews[oldPath]
    #   log "put", file.path
    #   @aceViews[file.path]
    
  
  ###
  FINDER OPERATIONS
  ###
  
  openItem:(nodeView, callback)->

    options  = @getOptions()
    nodeData = nodeView.getData()
    
    switch nodeData.type
      when "folder", "mount"
        @toggleFolder nodeView, callback
      when "file"
        @openFile nodeView
        @emit "file.opened", nodeData

  openFile:(nodeView, event)->

    file = nodeView.getData()
    appManager.openFileWithApplication file, "Ace"

  previewFile:(nodeView, event)->

    file = nodeView.getData()
    publicPath = file.path.replace /.*\/(.*\.beta.koding.com)\/httpdocs\/(.*)/, 'http://$1/$2'
    if publicPath is file.path
      {nickname} = KD.whoami().profile
      appManager.notify "File must be under: /#{nickname}/public_html/#{nickname}.#{location.hostname}/httpdocs/"
    else
      appManager.openFileWithApplication publicPath, "Viewer.kdapplication"


  refreshFolder:(nodeView, callback)->
    
    @notify "Refreshing..."
    folder = nodeView.getData()
    folder.emit "fs.nothing.finished", [] # in case of refresh to stop the spinner
    
    @collapseFolder nodeView, =>
      @expandFolder nodeView, ->
        notification.destroy()
        callback?()
    
  toggleFolder:(nodeView, callback)->
    
    if nodeView.expanded then @collapseFolder nodeView, callback else @expandFolder nodeView, callback
  
  expandFolder:(nodeView, callback)->
    
    return unless nodeView
    return if nodeView.isLoading or nodeView.expanded
    folder = nodeView.getData()

    folder.failTimer = setTimeout =>
      @notify "Couldn't fetch files!", null, "Sorry, a problem occured while communicating with servers, please try again later."
      folder.emit "fs.nothing.finished", []
    , 5000

    folder.fetchContents (files)=>
      clearTimeout folder.failTimer
      nodeView.expand()
      @initTree files
      callback? nodeView
    
  collapseFolder:(nodeView, callback)->
    
    return unless nodeView
    nodeData = nodeView.getData()
    path = @getNodeId nodeData
    if @listControllers[path]
      @listControllers[path].getView().collapse =>
        @removeChildNodes path
        nodeView.collapse()
        callback? nodeView
    else
      nodeView.collapse()
      callback? nodeView

  confirmDelete:(nodeView, event)->
    
    if @selectedNodes.length > 1
      new NFinderDeleteDialog {}, 
        items     : @selectedNodes
        callback  : (confirmation)=>
          @deleteFiles @selectedNodes if confirmation
          @setKeyView()
    else
      @beingEdited = nodeView
      nodeView.confirmDelete (confirmation)=>
        @deleteFiles [nodeView] if confirmation
        @setKeyView()
        @beingEdited = null
  
  deleteFiles:(nodes, callback)->

    stack = []
    nodes.forEach (node)=>
      stack.push (callback) =>
        node.getData().remove (err, response)=>
          if err then @notify null, null, err
          else
            callback err, node

    async.parallel stack, (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} deleted!", "success"
      @removeNodeView node for node in result
      callback?()


  showRenameDialog:(nodeView)->
    
    @beingEdited = nodeView
    nodeData = nodeView.getData()
    oldPath = nodeData.path
    nodeView.showRenameView (newValue)=>
      return if newValue is nodeData.name
      nodeData.rename newValue, (err)=>
        if err then @notify null, null, err
        else
          delete @nodes[oldPath]
          @nodes[nodeView.getData().path] = nodeView
          nodeView.childView.render()
      
      @setKeyView()
      @beingEdited = null
  
  createFile:(nodeView, type = "file")->
    
    @notify "creating a new #{type}!"
    nodeData = nodeView.getData()
    parentPath = if nodeData.type is "file"
      nodeData.parentPath
    else
      nodeData.path
    
    path = "#{parentPath}/New#{type.capitalize()}#{if type is 'file' then '.txt' else ''}"

    FSItem.create path, type, (err, file)=>
      @notify null, null, err if err
      @refreshFolder @nodes[parentPath], =>
        @selectNode @nodes[file.path]
        @notify "#{type} created!", "success"


  moveFiles:(nodesToBeMoved, targetNodeView, callback)->
    
    targetItem = targetNodeView.getData()
    if targetItem.type is "file"
      targetNodeView = @nodes[targetNodeView.getData().parentPath]
      targetItem = targetNodeView.getData()
    
    stack = []
    nodesToBeMoved.forEach (node)=>
      stack.push (callback) =>
        sourceItem = node.getData()
        FSItem.move sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            callback err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} moved!", "success"
      @removeNodeView node for node in result
      @refreshFolder targetNodeView

    async.parallel stack, callback

  copyFiles:(nodesToBeCopied, targetNodeView, callback)->
    
    targetItem = targetNodeView.getData()
    if targetItem.type is "file"
      targetNodeView = @nodes[targetNodeView.getData().parentPath]
      targetItem = targetNodeView.getData()
    
    stack = []
    nodesToBeCopied.forEach (node)=>
      stack.push (callback) =>
        sourceItem = node.getData()
        FSItem.copy sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            callback err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} copied!", "success"
      @refreshFolder targetNodeView

    async.parallel stack, callback
      
  duplicateFiles:(nodes, callback)->
    
    stack = []
    nodes.forEach (node)=>
      stack.push (callback) =>
        sourceItem = node.getData()
        targetItem = @nodes[sourceItem.parentPath].getData()
        FSItem.copy sourceItem, targetItem, (err, response)=>
          if err then @notify null, null, err
          else
            callback err, node

    callback or= (error, result) =>
      @notify "#{result.length} item#{if result.length > 1 then 's' else ''} duplicated!", "success"
      parentNodes = []
      result.forEach (node)=>
        parentNode = @nodes[node.getData().parentPath]
        parentNodes.push parentNode unless parentNode in parentNodes
      @refreshFolder parentNode for parentNode in parentNodes

    async.parallel stack, callback
  
  compressFiles:(nodeView, type)->
    
    file = nodeView.getData()
    FSItem.compress file, type, (err, response)=>
      if err then @notify null, null, err
      else
        @notify "#{file.type.capitalize()} compressed!", "success"
        @refreshFolder @nodes[file.parentPath]
    
  extractFiles:(nodeView)->
    
    file = nodeView.getData()
    FSItem.extract file, (err, response)=>
      if err then @notify null, null, err
      else
        @notify "#{file.type.capitalize()} extracted!", "success"
        @refreshFolder @nodes[file.parentPath], =>
          @selectNode @nodes[response.path]
    
    
  ###
  CONTEXT MENU OPERATIONS
  ###

  contextMenuOperationExpand:(nodeView, contextMenuItem)-> @expandFolder node for node in @selectedNodes
  contextMenuOperationCollapse:(nodeView, contextMenuItem)-> @collapseFolder node for node in @selectedNodes # error fix this
  contextMenuOperationRefresh:(nodeView, contextMenuItem)-> @refreshFolder nodeView
  contextMenuOperationCreateFile:(nodeView, contextMenuItem)-> @createFile nodeView
  contextMenuOperationCreateFolder:(nodeView, contextMenuItem)-> @createFile nodeView, "folder"
  contextMenuOperationRename:(nodeView, contextMenuItem)-> @showRenameDialog nodeView
  contextMenuOperationDelete:(nodeView, contextMenuItem)-> @confirmDelete nodeView
  contextMenuOperationDuplicate:(nodeView, contextMenuItem)-> @duplicateFiles @selectedNodes
  contextMenuOperationExtract:(nodeView, contextMenuItem)-> @extractFiles nodeView
  contextMenuOperationZip:(nodeView, contextMenuItem)-> @compressFiles nodeView, "zip"
  contextMenuOperationTarball:(nodeView, contextMenuItem)-> @compressFiles nodeView, "tar.gz"
  contextMenuOperationUpload:(nodeView, contextMenuItem)-> appManager.notify()
  contextMenuOperationDownload:(nodeView, contextMenuItem)-> appManager.notify()
  contextMenuOperationGitHubClone:(nodeView, contextMenuItem)-> appManager.notify()
  contextMenuOperationOpenFile:(nodeView, contextMenuItem)-> @openFile nodeView
  contextMenuOperationOpenFileWithCodeMirror:(nodeView, contextMenuItem)-> appManager.notify()
  contextMenuOperationPreviewFile:(nodeView, contextMenuItem)-> @previewFile nodeView

  ###
  CONTEXT MENU CREATE/MANAGE
  ###
  
  createContextMenu:(nodeView, event)->
    
    event.stopPropagation()
    event.preventDefault()
    return if nodeView.beingDeleted or nodeView.beingEdited
    
    if nodeView in @selectedNodes
      contextMenu = @contextMenuController.getContextMenu @selectedNodes, event
    else  
      @selectNode nodeView
      contextMenu = @contextMenuController.getContextMenu [nodeView], event
    no
  
  contextMenuItemSelected:(nodeView, contextMenuItem)->
    
    {action} = contextMenuItem.getData()
    if action
      # return false if you don't want contextmenu to disappear
      shouldDestroy = @["contextMenuOperation#{action.capitalize()}"]? nodeView, contextMenuItem
      if shouldDestroy isnt no
        @contextMenuController.destroyContextMenu()
  
  ###
  RESET STATES
  ###
  
  resetBeingEditedItems:->
    
    @beingEdited.resetView()
  
  organizeSelectedNodes:(listController, nodes, event = {})->
    
    @resetBeingEditedItems() if @beingEdited
    super

  ###
  DND UI FEEDBACKS
  ###
  
  showDragOverFeedback:(nodeView, event)-> super
    
  clearDragOverFeedback:(nodeView, event)-> super
  
  clearAllDragFeedback:-> super
  
  ###
  HANDLING MOUSE EVENTS
  ###
  
  click:(nodeView, event)->
    
    if $(event.target).is ".chevron-arrow"
      @contextMenu nodeView, event
      return no
    super
  
  dblClick:(nodeView, event)->

    @openItem nodeView

  contextMenu:(nodeView, event)->
    
    if @getOptions().contextMenu
      @createContextMenu nodeView, event

  ###
  HANDLING DND
  ###

  dragOver: (nodeView, event)->

    @showDragOverFeedback nodeView, event
    super

  lastEnteredNode = null
  dragEnter: (nodeView, event)->
    
    return nodeView if lastEnteredNode is nodeView or nodeView in @selectedNodes
    lastEnteredNode = nodeView
    clearTimeout @expandTimeout
    if nodeView.getData().type is ("folder" or "mount")
      @expandTimeout = setTimeout (=> @expandFolder nodeView), 800
    @showDragOverFeedback nodeView, event
    e = event.originalEvent
    
    if @boundaries.top > e.pageY > @boundaries.top + 20
      log "trigger top scroll"

    if @boundaries.top + @boundaries.height < e.pageY < @boundaries.top + @boundaries.height + 20
      log "trigger down scroll"
    
    super


  dragLeave: (nodeView, event)->
    
    @clearDragOverFeedback nodeView, event
    super

  dragEnd: (nodeView, event)->

    log "clear after drag"
    @clearAllDragFeedback()
    super

  drop: (nodeView, event)->
    
    return if nodeView in @selectedNodes

    if event.altKey
      @copyFiles @selectedNodes, nodeView
    else
      @moveFiles @selectedNodes, nodeView

    super

  ###
  HANDLING KEY EVENTS
  ###

  keyEventHappened:(event)->

    super
  
  performDownKey:(nodeView, event)->
    
    if event.altKey
      offset = nodeView.$('.chevron-arrow').offset()
      event.pageY = offset.top
      event.pageX = offset.left
      @contextMenu nodeView, event
    else
      super
    
  performBackspaceKey:(nodeView, event)->

    event.preventDefault()
    event.stopPropagation()
    @confirmDelete nodeView, event
    no
  
  performEnterKey:(nodeView, event)->

    @selectNode nodeView
    @openItem nodeView

  performRightKey:(nodeView, event)->
  performUpKey:(nodeView, event)-> super
  performLeftKey:(nodeView, event)-> super


  ###
  HELPERS
  ###

  notification = null

  notify:(msg, style, details)->
    
    return unless @getView().parent?.parent?.parent

    notification.destroy() if notification
    
    if details and not msg? and /Permission denied/.test details
      msg = "Permission denied!"
    
    style or= 'error' if details
    
    notification = new KDNotificationView
      title     : msg or "Something went wrong"
      type      : "mini"
      cssClass  : "filetree #{style}"
      container : @getView().parent.parent.parent # i know this is bad sinan 2012/5/21
      duration  : if details then 5000 else 2500
      details   : details
      click     : ->
        if notification.getOptions().details
          details = new KDNotificationView
            title     : "Error details"
            content   : notification.getOptions().details
            type      : "growl"
            duration  : 0
            click     : -> details.destroy()

          @getSingleton('windowController').addLayer details
          @listenTo
            KDEventTypes        : 'ReceivedClickElsewhere'
            listenedToInstance  : details
            callback            : (pubInst,event)=>
              @getSingleton('windowController').removeLayer @mainInputTabs
              details.destroy()
              
